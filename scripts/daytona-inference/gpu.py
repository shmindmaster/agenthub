"""Unified NVIDIA + AMD Daytona spot GPU lifecycle helper for AgentHub inference.

Enforces:
- Spot-only Daytona GPU sandboxes (never on-demand).
- Maximum two GPU instances combined across NVIDIA and AMD.
- One GPU per instance.
- Protection of the live turbo sandbox (qwen38-turbo-q6k) and llm-models volume.
- Central LiteLLM gateway backend updates at https://inference.shtrial.com without
  touching individual coding-agent configurations on eviction or replacement.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
CATALOG_PATH = ROOT / "catalog.json"
STATE_PATH = ROOT / "state.json"
SECRET_DIR = ROOT / "secrets"
LOG_DIR = ROOT / "logs"

PROTECTED_SANDBOX_ID = "0075feb8-9387-43fd-85b3-ee8f2bb5930c"
PROTECTED_SANDBOX_NAME = "qwen38-turbo-q6k"
PROTECTED_VOLUME_NAME = "llm-models"


def load_catalog() -> dict[str, Any]:
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def load_state() -> dict[str, Any]:
    if not STATE_PATH.exists():
        return {"volume_id": None, "organization_id": None, "workers": {}}
    return json.loads(STATE_PATH.read_text(encoding="utf-8"))


def save_state(state: dict[str, Any]) -> None:
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def gpu_value(gpu: Any) -> str:
    return getattr(gpu, "value", str(gpu))


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def protect_sandbox(sandbox: Any) -> None:
    sid = getattr(sandbox, "id", "")
    sname = getattr(sandbox, "name", "")
    if sid == PROTECTED_SANDBOX_ID or sname == PROTECTED_SANDBOX_NAME:
        raise SystemExit(f"refusing to modify protected sandbox {sname} ({sid})")


def protect_volume_name(name: str) -> None:
    if name == PROTECTED_VOLUME_NAME:
        raise SystemExit(f"refusing to write weights to protected volume {PROTECTED_VOLUME_NAME}")


def read_secret_value(env_names: tuple[str, ...], file_name: str | None = None) -> str:
    for env_name in env_names:
        val = os.environ.get(env_name, "").strip()
        if val:
            return val
    if file_name:
        p = SECRET_DIR / file_name
        if p.is_file():
            val = p.read_text(encoding="utf-8").strip()
            if val:
                return val
    return ""


def write_secret(name: str, value: str) -> Path:
    SECRET_DIR.mkdir(parents=True, exist_ok=True)
    path = SECRET_DIR / name
    path.write_text(value.strip(), encoding="utf-8")
    if os.name == "nt":
        user = os.environ.get("USERNAME", "")
        if user:
            subprocess.run(
                ["icacls", str(path), "/inheritance:r", "/grant:r", f"{user}:(R,W)"],
                check=False,
                capture_output=True,
                text=True,
            )
    else:
        os.chmod(path, 0o600)
    return path


def mask_secret(value: str) -> str:
    if not value:
        return "unset"
    return f"set(len={len(value)},last4={value[-4:]})"


def get_daytona_client():
    from daytona import Daytona

    return Daytona()


def resolve_org_id(v0: Any) -> str:
    env_org = os.environ.get("DAYTONA_ORG_ID", "").strip()
    if env_org:
        return env_org
    state = load_state()
    if state.get("organization_id"):
        return str(state["organization_id"])
    for sb in v0.list():
        oid = getattr(sb, "organization_id", None)
        if oid:
            state["organization_id"] = str(oid)
            save_state(state)
            return str(oid)
    raise SystemExit("Unable to resolve Daytona organization_id; set DAYTONA_ORG_ID or ensure a sandbox is visible.")


def fetch_gpu_capacity(v0: Any) -> dict[str, dict[str, int]]:
    from daytona_api_client import OrganizationsApi

    org_id = resolve_org_id(v0)
    resp = OrganizationsApi(v0._api_client).get_gpu_capacity(org_id)
    out: dict[str, dict[str, int]] = {}
    for entry in resp.capacity:
        gname = gpu_value(entry.gpu_type)
        out[gname] = {
            "spot": int(entry.available_spot or 0),
            "on_demand": int(entry.available_on_demand or 0),
        }
    return out


def select_gpu_for_role(
    role: str,
    requested_gpu: str,
    capacity: dict[str, dict[str, int]],
    catalog: dict[str, Any],
    quant: str | None = None,
    allow_q6_fallback: bool = False,
) -> tuple[str, dict[str, Any]]:
    role_cfg = catalog["roles"][role]
    profiles = role_cfg["profiles"]
    priority = role_cfg["gpuPriority"]

    if requested_gpu != "auto":
        if requested_gpu not in profiles:
            raise SystemExit(f"GPU {requested_gpu} is not compatible with role '{role}' (supported: {', '.join(profiles.keys())})")
        spot_avail = capacity.get(requested_gpu, {}).get("spot", 0)
        if spot_avail <= 0:
            raise SystemExit(f"No live Daytona spot capacity for {requested_gpu} (spot={spot_avail}). Never falling back to on-demand.")
        chosen = requested_gpu
    else:
        chosen = ""
        for candidate in priority:
            if candidate not in profiles:
                continue
            if role == "flagship" and profiles[candidate].get("requiresExplicitQ6Fallback") and not allow_q6_fallback and quant != "Q6_K":
                continue
            if capacity.get(candidate, {}).get("spot", 0) > 0:
                chosen = candidate
                break
        if not chosen:
            raise SystemExit(
                f"No live Daytona spot GPU available for role '{role}' "
                f"(checked {', '.join(priority)}; capacity={ {k: v['spot'] for k, v in capacity.items()} })."
            )

    profile = dict(profiles[chosen])
    if role == "flagship":
        effective_quant = quant or role_cfg.get("defaultQuantization", "Q8_0")
        if chosen == "H200" and effective_quant == "Q8_0":
            if not allow_q6_fallback:
                raise SystemExit(
                    "H200 cannot hold Flash-Next Q8_0 (188 GB). Pass --quant Q6_K or --allow-q6-fallback explicitly; "
                    "never silently substituting Q6_K."
                )
            effective_quant = "Q6_K"
        profile["quantization"] = effective_quant
    return chosen, profile


def enforce_gpu_limit(live_sandboxes: list[Any], target_sandbox_names: set[str], max_gpus: int = 2) -> None:
    """Enforce max GPU instances across NVIDIA and AMD combined."""
    active_gpu_boxes = [
        sb
        for sb in live_sandboxes
        if getattr(sb, "gpu", 0)
        and "DESTROY" not in str(getattr(sb, "state", "")).upper()
        and "ARCHIV" not in str(getattr(sb, "state", "")).upper()
    ]
    reusable = [sb for sb in active_gpu_boxes if getattr(sb, "name", "") in target_sandbox_names]
    if reusable:
        return
    if len(active_gpu_boxes) >= max_gpus:
        summary = ", ".join(f"{sb.name}({gpu_value(sb.gpu_type)})" for sb in active_gpu_boxes)
        raise SystemExit(
            f"GPU instance limit reached ({len(active_gpu_boxes)}/{max_gpus} active: {summary}). "
            "Refusing to start a 3rd GPU instance."
        )


def ensure_volume(v0: Any, volume_name: str) -> str:
    protect_volume_name(volume_name)
    volume = v0.volume.get(volume_name, create=True)
    if volume.name == PROTECTED_VOLUME_NAME:
        raise SystemExit("refusing to use protected llm-models volume")
    deadline = time.time() + 180
    while str(volume.state).endswith("CREATING") or "PENDING" in str(volume.state):
        if time.time() > deadline:
            break
        time.sleep(2)
        volume = v0.volume.get(volume_name)
    print(f"volume {volume.name} {volume.id} {volume.state}")
    return str(volume.id)


def find_role_sandbox(v0: Any, role: str, catalog: dict[str, Any]) -> Any | None:
    role_cfg = catalog["roles"][role]
    names = {role_cfg["sandboxName"], *role_cfg.get("legacySandboxNames", [])}
    for sb in v0.list():
        if getattr(sb, "name", "") in names and "DESTROY" not in str(getattr(sb, "state", "")).upper():
            return sb
    return None


def litellm_request(method: str, path: str, payload: dict[str, Any] | None = None, require_master: bool = True) -> tuple[int, Any]:
    catalog = load_catalog()
    base = catalog["policy"]["gatewayAdminUrl"].rstrip("/")
    key = read_secret_value(("LITELLM_MASTER_KEY",), "litellm.master") if require_master else read_secret_value(
        ("AGENTHUB_INFERENCE_KEY", "LITELLM_MASTER_KEY"), "inference.key"
    )
    if not key:
        raise SystemExit("Missing gateway key (set LITELLM_MASTER_KEY or secrets/litellm.master).")
    body_bytes = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {"Authorization": f"Bearer {key}"}
    if body_bytes is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=body_bytes, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {}
        except Exception:
            parsed = {"raw": raw[:300]}
        return exc.code, parsed


def gateway_list_models() -> list[dict[str, Any]]:
    status, body = litellm_request("GET", "/model/info", require_master=True)
    if status != 200:
        raise SystemExit(f"LiteLLM /model/info failed with HTTP {status}")
    return list(body.get("data", []))


def gateway_delete_by_role_or_alias(aliases: list[str]) -> int:
    models = gateway_list_models()
    deleted = 0
    for item in models:
        mname = item.get("model_name")
        mid = (item.get("model_info") or {}).get("id")
        if mname in aliases and mid:
            code, _ = litellm_request("POST", "/model/delete", {"id": mid}, require_master=True)
            if code == 200:
                deleted += 1
    return deleted


def gateway_register_alias(
    alias: str,
    upstream_model: str,
    api_base: str,
    api_key: str,
    preview_token: str | None,
    model_info: dict[str, Any],
) -> str:
    # Remove any prior DB registration for the same alias to avoid stale multi-backend routing.
    gateway_delete_by_role_or_alias([alias])
    litellm_params: dict[str, Any] = {
        "model": upstream_model,
        "api_base": api_base.rstrip("/"),
        "api_key": api_key,
    }
    if preview_token:
        litellm_params["extra_headers"] = {"x-daytona-preview-token": preview_token}
    payload = {
        "model_name": alias,
        "litellm_params": litellm_params,
        "model_info": model_info,
    }
    code, body = litellm_request("POST", "/model/new", payload, require_master=True)
    if code != 200:
        raise SystemExit(f"LiteLLM /model/new failed for {alias}: HTTP {code} {body}")
    return str(model_info.get("id") or body.get("model_id") or alias)


def preview_origin_and_token(sandbox: Any, port: int, role: str) -> tuple[str, str]:
    link = sandbox.get_preview_link(port)
    token = str(link.token or "")
    url = str(link.url).rstrip("/")
    if not token:
        raise SystemExit(f"private preview on port {port} returned no token")
    write_secret(f"{role}.preview", token)
    print(f"preview {url} token={mask_secret(token)}")
    return url, token


def upload_runtime_keys(sandbox: Any) -> str:
    worker_key = read_secret_value(("INFERENCE_WORKER_API_KEY", "H100_LLM_API_KEY"))
    if len(worker_key) < 8:
        raise SystemExit("INFERENCE_WORKER_API_KEY or H100_LLM_API_KEY is not set")
    hf_token = read_secret_value(("HF_TOKEN",))
    sandbox.fs.upload_file(worker_key.encode("utf-8"), "/run/llm.key")
    sandbox.process.exec("chmod 600 /run/llm.key", timeout=30)
    print(f"worker_key uploaded {mask_secret(worker_key)}")
    if len(hf_token) >= 8:
        sandbox.fs.upload_file(hf_token.encode("utf-8"), "/run/hf.token")
        sandbox.process.exec("chmod 600 /run/hf.token", timeout=30)
        print(f"hf_token uploaded {mask_secret(hf_token)}")
    return worker_key


def wait_for_sandbox_models(sandbox: Any, port: int, expected_model: str, log_file: str) -> list[str]:
    started_at = time.time()
    deadline = started_at + 50 * 60
    last_marker = ""
    down_streak = 0
    while time.time() < deadline:
        cmd = (
            "python3 - <<'PY'\n"
            "import json, urllib.request\n"
            "key=open('/run/llm.key').read().strip()\n"
            f"req=urllib.request.Request('http://127.0.0.1:{port}/v1/models', headers={{'Authorization':'Bearer '+key}})\n"
            "try:\n"
            "    with urllib.request.urlopen(req, timeout=10) as r:\n"
            "        body=json.load(r)\n"
            "        print(r.status)\n"
            "        for item in body.get('data', []):\n"
            "            print(item.get('id', ''))\n"
            "except Exception as exc:\n"
            "    print('0')\n"
            "    print(type(exc).__name__)\n"
            "PY"
        )
        res = sandbox.process.exec(cmd, timeout=30)
        lines = [line.strip() for line in (res.result or "").splitlines() if line.strip()]
        code = int(lines[0]) if lines and lines[0].isdigit() else 0
        ids = lines[1:] if len(lines) > 1 else []
        marker = f"{code}:{','.join(ids)}"
        if marker != last_marker:
            print(f"worker_models http={code} ids={','.join(ids) if ids else '-'}", flush=True)
            last_marker = marker
        if code == 200 and expected_model in ids:
            return ids
        alive = sandbox.process.exec(
            "ps -eo args | grep -E '[v]llm serve|[l]lama-server|[s]erve-(specialist|flagship)' >/dev/null && echo UP || echo DOWN",
            timeout=20,
        )
        if "UP" in (alive.result or ""):
            down_streak = 0
        elif time.time() - started_at > 20:
            down_streak += 1
            if down_streak >= 2:
                tail = sandbox.process.exec(f"tail -n 30 {log_file} 2>/dev/null || true", timeout=20)
                print(tail.result or "")
                raise SystemExit(f"Worker process exited before publishing {expected_model}")
        time.sleep(20)
    tail = sandbox.process.exec(f"tail -n 30 {log_file} 2>/dev/null || true", timeout=30)
    print(tail.result or "")
    raise SystemExit(f"Worker did not publish {expected_model} before timeout")


def resolve_active_snapshot(v0: Any, snapshot_name: str | None) -> str | None:
    if not snapshot_name:
        return None
    try:
        snap = v0.snapshot.get(snapshot_name)
    except Exception:
        return None
    return snapshot_name if str(getattr(snap, "state", "")).upper().endswith("ACTIVE") else None


def cmd_capacity(_args: argparse.Namespace) -> None:
    catalog = load_catalog()
    app = get_daytona_client()
    try:
        cap = fetch_gpu_capacity(app.v0)
    finally:
        app.close()
    print(f"{'GPU':<14} {'Vendor':<7} {'VRAM':<7} {'Spot':<6} {'OnDemand':<9} {'Eligible Roles'}")
    for gname, gmeta in catalog["gpus"].items():
        c = cap.get(gname, {"spot": 0, "on_demand": 0})
        roles = [r for r, rcfg in catalog["roles"].items() if gname in rcfg["profiles"]]
        print(f"{gname:<14} {gmeta['vendor']:<7} {gmeta['vramGb']:<7} {c['spot']:<6} {c['on_demand']:<9} {','.join(roles) or '-'}")


def cmd_up(args: argparse.Namespace) -> None:
    catalog = load_catalog()
    role = args.role
    role_cfg = catalog["roles"][role]
    app = get_daytona_client()
    try:
        v0 = app.v0
        from daytona.v0 import CreateSandboxFromImageParams, CreateSandboxFromSnapshotParams, GpuType, Resources, VolumeMount

        live = list(v0.list())
        names = {role_cfg["sandboxName"], *role_cfg.get("legacySandboxNames", [])}
        enforce_gpu_limit(live, names, catalog["policy"]["maxGpuInstancesTotal"])

        volume_id = ensure_volume(v0, catalog["policy"]["weightsVolumeName"])
        existing = find_role_sandbox(v0, role, catalog)
        if existing is not None:
            protect_sandbox(existing)
            if "STARTED" not in str(existing.state):
                raise SystemExit(f"{existing.name} exists ({existing.id}) in state {existing.state}; remove or reconcile first")
            sandbox = existing
            gpu_name = gpu_value(sandbox.gpu_type)
            profile = dict(role_cfg["profiles"].get(gpu_name) or next(iter(role_cfg["profiles"].values())))
            print(f"reuse {sandbox.id} {sandbox.name} spot={sandbox.spot} gpu={gpu_name}")
        else:
            cap = fetch_gpu_capacity(v0)
            gpu_name, profile = select_gpu_for_role(
                role, args.gpu, cap, catalog, quant=args.quant, allow_q6_fallback=args.allow_q6_fallback
            )
            image_spec = catalog["images"][profile["backend"]]
            gpu_enum = GpuType(gpu_name)
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            log_path = LOG_DIR / f"{role}-create.log"

            def on_log(line: str) -> None:
                with log_path.open("a", encoding="utf-8") as handle:
                    handle.write(line + "\n")

            active_snapshot = resolve_active_snapshot(v0, profile.get("snapshotName"))
            if active_snapshot:
                print(f"creating spot {gpu_name} {role_cfg['sandboxName']} snapshot={active_snapshot}", flush=True)
                sandbox = v0.create(
                    CreateSandboxFromSnapshotParams(
                        name=role_cfg["sandboxName"],
                        snapshot=active_snapshot,
                        public=False,
                        spot=True,
                        auto_stop_interval=0,
                        auto_delete_interval=0,
                        ttl_minutes=args.ttl,
                        labels={
                            "owner": "agenthub",
                            "purpose": role_cfg["primaryServedModelName"],
                            "role": role,
                        },
                        volumes=[VolumeMount(volume_id=volume_id, mount_path=catalog["policy"]["weightsMountPath"])],
                    ),
                    timeout=0,
                )
            else:
                print(f"creating spot {gpu_name} {role_cfg['sandboxName']} image={image_spec['image']}", flush=True)
                sandbox = v0.create(
                    CreateSandboxFromImageParams(
                        name=role_cfg["sandboxName"],
                        image=image_spec["image"],
                        public=False,
                        spot=True,
                        auto_stop_interval=0,
                        auto_delete_interval=0,
                        ttl_minutes=args.ttl,
                        labels={
                            "owner": "agenthub",
                            "purpose": role_cfg["primaryServedModelName"],
                            "role": role,
                        },
                        volumes=[VolumeMount(volume_id=volume_id, mount_path=catalog["policy"]["weightsMountPath"])],
                        resources=Resources(
                            cpu=role_cfg["cpu"],
                            memory=role_cfg["ramGb"],
                            disk=role_cfg["diskGb"],
                            gpu=1,
                            gpu_type=gpu_enum,
                        ),
                    ),
                    timeout=0,
                    on_snapshot_create_logs=on_log,
                )
            protect_sandbox(sandbox)
            sandbox.refresh_data()
            actual_gpu = gpu_value(sandbox.gpu_type)
            if sandbox.spot is not True or actual_gpu != gpu_name:
                sandbox.delete()
                raise SystemExit(f"created sandbox spot={sandbox.spot} gpu={actual_gpu} did not match requested spot {gpu_name}; deleted")
            gpu_name = actual_gpu

        port = role_cfg["port"]
        origin, preview_token = preview_origin_and_token(sandbox, port, role)
        worker_key = upload_runtime_keys(sandbox)

        recipe_rel = profile["recipe"]
        recipe_bytes = (ROOT / recipe_rel).read_bytes().replace(b"\r\n", b"\n")
        remote_script = f"/opt/serve-{role}.sh"
        sandbox.fs.upload_file(recipe_bytes, remote_script)

        env_vars = {
            "MODEL_REPO": role_cfg["modelRepo"],
            "SERVED_MODEL_NAME": role_cfg["primaryServedModelName"],
            "PORT": str(port),
            "WEIGHTS_ROOT": catalog["policy"]["weightsMountPath"],
            "GPU_TYPE": gpu_name,
        }
        if role == "specialist":
            env_vars.update(
                {
                    "MAX_MODEL_LEN": str(profile["maxModelLen"]),
                    "MAX_NUM_SEQS": str(profile["maxNumSeqs"]),
                    "GPU_MEM_UTIL": str(profile["gpuMemUtil"]),
                    "MAX_NUM_BATCHED_TOKENS": str(profile["maxNumBatchedTokens"]),
                    "MTP_TOKENS": str(profile["mtpTokens"]),
                }
            )
        else:
            env_vars.update(
                {
                    "QUANT": str(profile["quantization"]),
                    "CTX_SIZE": str(profile["ctxSize"]),
                    "PARALLEL": str(profile["parallel"]),
                    "BATCH_SIZE": str(profile["batchSize"]),
                    "UBATCH_SIZE": str(profile["ubatchSize"]),
                    "CACHE_TYPE_K": str(profile["cacheTypeK"]),
                    "CACHE_TYPE_V": str(profile["cacheTypeV"]),
                }
            )
        env_prefix = " ".join(f"{k}={json.dumps(v)}" for k, v in env_vars.items())
        log_file = f"/tmp/{role}.log"
        # Skip re-launching if the worker server process is already alive and serving.
        already_up = sandbox.process.exec(
            "ps -eo args | grep -E '[v]llm serve|[l]lama-server' >/dev/null && echo UP || echo DOWN",
            timeout=20,
        )
        if "UP" not in (already_up.result or ""):
            sandbox.process.exec(
                f"mkdir -p /run /opt && chmod 755 {remote_script} && "
                f"setsid -f env {env_prefix} bash {remote_script} </dev/null >/tmp/{role}.nohup 2>&1",
                timeout=30,
            )
        wait_for_sandbox_models(sandbox, port, role_cfg["primaryServedModelName"], log_file)
        sandbox.set_ttl(args.ttl)
        sandbox.refresh_data()

        api_base = origin.rstrip("/") + "/v1"
        upstream_model = f"openai/{role_cfg['primaryServedModelName']}"
        gateway_ids: dict[str, str] = {}
        for alias in role_cfg["servedAliases"]:
            info = {
                "id": f"{alias}-{sandbox.id[:8]}",
                "mode": "chat",
                "max_input_tokens": int(profile.get("maxModelLen") or profile.get("ctxSize")) - int(profile["maxOutputTokens"]),
                "max_output_tokens": int(profile["maxOutputTokens"]),
                "supports_function_calling": bool(role_cfg["tools"]),
                "supports_vision": bool(role_cfg["vision"] and alias != "agent-fast"),
                "supports_reasoning": True,
                "gpu_type": gpu_name,
                "quantization": profile["quantization"],
                "sandbox_id": sandbox.id,
                "spot": True,
            }
            gateway_ids[alias] = gateway_register_alias(alias, upstream_model, api_base, worker_key, preview_token, info)

        state = load_state()
        state["volume_id"] = volume_id
        state["volume_name"] = catalog["policy"]["weightsVolumeName"]
        state.setdefault("workers", {})[role] = {
            "sandbox_id": sandbox.id,
            "name": sandbox.name,
            "spot": True,
            "gpu_type": gpu_name,
            "backend": profile["backend"],
            "image": catalog["images"][profile["backend"]]["image"],
            "model_repo": role_cfg["modelRepo"],
            "quantization": profile["quantization"],
            "context_limit": int(profile.get("maxModelLen") or profile.get("ctxSize")),
            "max_output_tokens": int(profile["maxOutputTokens"]),
            "vision": bool(role_cfg["vision"]),
            "tools": bool(role_cfg["tools"]),
            "preview_origin": origin,
            "base_url": api_base,
            "served_aliases": role_cfg["servedAliases"],
            "gateway_model_ids": gateway_ids,
            "ttl_minutes": args.ttl,
            "auto_destroy_at": sandbox.auto_destroy_at,
            "status": "serving",
            "checked_at": utc_now(),
        }
        save_state(state)
        print(f"serving role={role} gpu={gpu_name} aliases={','.join(role_cfg['servedAliases'])} gateway={catalog['policy']['gatewayBaseUrl']}")
    finally:
        app.close()


def cmd_down(args: argparse.Namespace) -> None:
    catalog = load_catalog()
    role = args.role
    role_cfg = catalog["roles"][role]
    state = load_state()
    worker = state.get("workers", {}).get(role)
    app = get_daytona_client()
    try:
        sb = None
        if worker and worker.get("sandbox_id"):
            try:
                sb = app.v0.get(worker["sandbox_id"])
            except Exception:
                sb = None
        if sb is None:
            sb = find_role_sandbox(app.v0, role, catalog)
        if sb is not None:
            protect_sandbox(sb)
            sb.delete(timeout=120, wait=True)
            print(f"deleted {sb.id} ({sb.name})")
        else:
            print(f"no live sandbox found for {role}")
    finally:
        app.close()

    removed = gateway_delete_by_role_or_alias(role_cfg["servedAliases"])
    print(f"gateway_deregistered aliases={','.join(role_cfg['servedAliases'])} count={removed}")
    if worker:
        worker["status"] = "deleted"
        worker["checked_at"] = utc_now()
        save_state(state)


def cmd_extend(args: argparse.Namespace) -> None:
    catalog = load_catalog()
    role = args.role
    state = load_state()
    worker = state.get("workers", {}).get(role)
    if not worker or not worker.get("sandbox_id"):
        raise SystemExit(f"no recorded sandbox for {role}")
    app = get_daytona_client()
    try:
        sb = app.v0.get(worker["sandbox_id"])
        protect_sandbox(sb)
        sb.set_ttl(args.minutes)
        sb.refresh_data()
        worker["ttl_minutes"] = args.minutes
        worker["auto_destroy_at"] = sb.auto_destroy_at
        worker["checked_at"] = utc_now()
        save_state(state)
        print(f"extended {role} ttl_minutes={args.minutes} destroy_at={sb.auto_destroy_at}")
    finally:
        app.close()


def cmd_status(_args: argparse.Namespace) -> None:
    catalog = load_catalog()
    app = get_daytona_client()
    try:
        sbs = [sb for sb in app.v0.list() if getattr(sb, "gpu", 0) and "DESTROY" not in str(sb.state).upper()]
    finally:
        app.close()
    print(f"state_file {STATE_PATH}")
    print(f"gpu_instances {len(sbs)}/{catalog['policy']['maxGpuInstancesTotal']}")
    for sb in sbs:
        print(
            f"  {sb.id} {sb.name} {sb.state} gpu={gpu_value(sb.gpu_type)} "
            f"spot={sb.spot} destroy_at={sb.auto_destroy_at}"
        )
    try:
        models = gateway_list_models()
        print("gateway_models:")
        for item in models:
            info = item.get("model_info") or {}
            print(f"  {item.get('model_name')} -> gpu={info.get('gpu_type')} quant={info.get('quantization')} sandbox={info.get('sandbox_id')}")
    except SystemExit as exc:
        print(f"gateway_models unavailable ({exc})")


def cmd_reconcile(_args: argparse.Namespace) -> None:
    catalog = load_catalog()
    app = get_daytona_client()
    try:
        live = {
            sb.id: sb
            for sb in app.v0.list()
            if getattr(sb, "gpu", 0) and "STARTED" in str(sb.state).upper()
        }
    finally:
        app.close()

    registered = gateway_list_models()
    for item in registered:
        info = item.get("model_info") or {}
        sid = info.get("sandbox_id")
        mid = info.get("id")
        mname = item.get("model_name")
        if sid and sid not in live and mid:
            code, _ = litellm_request("POST", "/model/delete", {"id": mid}, require_master=True)
            print(f"pruned stale alias={mname} sandbox={sid} http={code}")

    # Ensure protected turbo sandbox stays registered as agent-turbo when live.
    if PROTECTED_SANDBOX_ID in live:
        turbo_sb = live[PROTECTED_SANDBOX_ID]
        worker_key = read_secret_value(("H100_LLM_API_KEY", "INFERENCE_WORKER_API_KEY"))
        if worker_key:
            link = turbo_sb.get_preview_link(8000)
            api_base = str(link.url).rstrip("/") + "/v1"
            preview_tok = str(link.token or "") or None
            already = [
                m for m in gateway_list_models()
                if m.get("model_name") == "agent-turbo" and (m.get("model_info") or {}).get("sandbox_id") == PROTECTED_SANDBOX_ID
            ]
            if not already:
                gateway_register_alias(
                    "agent-turbo",
                    "openai/qwen3.8-27b-turbo-heretic-mtp-q6",
                    api_base,
                    worker_key,
                    preview_tok,
                    {
                        "id": "agent-turbo-live",
                        "mode": "chat",
                        "max_input_tokens": 49152,
                        "max_output_tokens": 16384,
                        "supports_function_calling": True,
                        "supports_vision": False,
                        "supports_reasoning": True,
                        "gpu_type": gpu_value(turbo_sb.gpu_type),
                        "quantization": "Q6_K",
                        "sandbox_id": PROTECTED_SANDBOX_ID,
                        "spot": True,
                    },
                )
                print("registered agent-turbo -> qwen38-turbo-q6k")
            else:
                print("ok agent-turbo -> qwen38-turbo-q6k")

    state = load_state()
    changed = False
    for role, w in state.get("workers", {}).items():
        sid = w.get("sandbox_id")
        if sid and sid not in live and w.get("status") == "serving":
            w["status"] = "evicted_or_stopped"
            w["checked_at"] = utc_now()
            changed = True
            print(f"marked worker {role} ({sid}) as evicted_or_stopped")
    if changed:
        save_state(state)


def cmd_save_cache(args: argparse.Namespace) -> None:
    catalog = load_catalog()
    role = args.role
    role_cfg = catalog["roles"][role]
    if role_cfg["engine"] != "vllm":
        raise SystemExit(f"save-cache is only supported for vllm roles (got engine={role_cfg['engine']})")
    state = load_state()
    worker = state.get("workers", {}).get(role)
    app = get_daytona_client()
    try:
        sb = None
        if worker and worker.get("sandbox_id"):
            try:
                sb = app.v0.get(worker["sandbox_id"])
            except Exception:
                sb = None
        if sb is None:
            sb = find_role_sandbox(app.v0, role, catalog)
        if sb is None:
            raise SystemExit(f"no live sandbox found for {role}")
        protect_sandbox(sb)
        gpu_name = gpu_value(sb.gpu_type)
        weights_mount = catalog["policy"]["weightsMountPath"]
        py_remote = f"""python3 - <<'PY'
import hashlib, pathlib, shutil, tarfile
import vllm

vllm_ver = vllm.__version__
cache_name = f"vllm-{{vllm_ver}}-{gpu_name}.tar.gz"
cache_root = pathlib.Path("/root/.cache")
items = [n for n in ("vllm", "flashinfer") if (cache_root / n).is_dir()]
if not items:
    raise SystemExit("no /root/.cache/vllm directory to persist")

tmp_tar = pathlib.Path("/tmp") / cache_name
with tarfile.open(tmp_tar, "w:gz") as tf:
    for item in items:
        tf.add(cache_root / item, arcname=item)

caches_dir = pathlib.Path("{weights_mount}") / "caches"
caches_dir.mkdir(parents=True, exist_ok=True)
dst_tar = caches_dir / cache_name
shutil.copyfile(tmp_tar, dst_tar)

h = hashlib.sha256()
with dst_tar.open("rb") as fh:
    for chunk in iter(lambda: fh.read(1024 * 1024), b""):
        h.update(chunk)
digest = h.hexdigest()
(caches_dir / f"{{cache_name}}.sha256").write_text(f"{{digest}}  {{cache_name}}\\n", encoding="utf-8")
tmp_tar.unlink(missing_ok=True)

with tarfile.open(dst_tar, "r:gz") as tf:
    entries = len(tf.getmembers())
print(f"persisted={{dst_tar}} bytes={{dst_tar.stat().st_size}} sha256={{digest}} entries={{entries}}")
PY"""
        res = sb.process.exec(py_remote, timeout=300)
        print(res.result or "")
        if res.exit_code != 0:
            raise SystemExit(f"save-cache failed inside sandbox with exit_code={res.exit_code}")
    finally:
        app.close()


def cmd_doctor(_args: argparse.Namespace) -> None:
    catalog = load_catalog()
    checks: list[tuple[str, bool, str]] = []

    checks.append(("env.DAYTONA_API_KEY", bool(os.environ.get("DAYTONA_API_KEY")), mask_secret(os.environ.get("DAYTONA_API_KEY", ""))))
    checks.append(("env.AGENTHUB_INFERENCE_KEY", bool(read_secret_value(("AGENTHUB_INFERENCE_KEY",), "inference.key")), mask_secret(read_secret_value(("AGENTHUB_INFERENCE_KEY",), "inference.key"))))
    checks.append(("secret.LITELLM_MASTER_KEY", bool(read_secret_value(("LITELLM_MASTER_KEY",), "litellm.master")), mask_secret(read_secret_value(("LITELLM_MASTER_KEY",), "litellm.master"))))
    checks.append(("env.H100_LLM_API_KEY", bool(os.environ.get("H100_LLM_API_KEY")), mask_secret(os.environ.get("H100_LLM_API_KEY", ""))))

    try:
        app = get_daytona_client()
        try:
            sbs = list(app.v0.list())
            vol = app.v0.volume.get(catalog["policy"]["weightsVolumeName"], create=False)
            checks.append(("daytona.api", True, f"sandboxes={len(sbs)}"))
            checks.append(("daytona.weights_volume", True, f"{vol.name} {vol.state}"))
            turbo_live = any(sb.id == PROTECTED_SANDBOX_ID and "STARTED" in str(sb.state).upper() for sb in sbs)
            checks.append(("daytona.protected_turbo", turbo_live, PROTECTED_SANDBOX_ID))
            configured_snaps = sorted({
                prof["snapshotName"]
                for rcfg in catalog["roles"].values()
                for prof in rcfg["profiles"].values()
                if prof.get("snapshotName")
            })
            if configured_snaps:
                all_snaps = {s.name: str(getattr(s, "state", "")) for s in app.v0.snapshot.list().items}
                active_snaps = [n for n in configured_snaps if all_snaps.get(n, "").upper().endswith("ACTIVE")]
                checks.append(
                    (
                        "daytona.snapshots",
                        len(active_snaps) == len(configured_snaps),
                        f"active={len(active_snaps)}/{len(configured_snaps)} ({','.join(active_snaps) or 'none'})",
                    )
                )
        finally:
            app.close()
    except Exception as exc:
        checks.append(("daytona.api", False, type(exc).__name__))

    try:
        req = urllib.request.Request(catalog["policy"]["gatewayAdminUrl"].rstrip("/") + "/health/liveliness")
        with urllib.request.urlopen(req, timeout=10) as r:
            checks.append(("gateway.liveliness", r.status == 200, f"http={r.status}"))
    except Exception as exc:
        checks.append(("gateway.liveliness", False, type(exc).__name__))

    try:
        models = gateway_list_models()
        checks.append(("gateway.admin_api", True, f"registered={len(models)}"))
    except Exception as exc:
        checks.append(("gateway.admin_api", False, str(exc)[:120]))

    failed = 0
    for name, ok, detail in checks:
        mark = "PASS" if ok else "FAIL"
        if not ok:
            failed += 1
        print(f"[{mark}] {name}: {detail}")
    if failed:
        raise SystemExit(1)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Unified NVIDIA + AMD Daytona spot GPU lifecycle helper")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("capacity", help="Show live Daytona spot GPU capacity")
    sub.add_parser("status", help="Show live GPU sandboxes and gateway model aliases")
    sub.add_parser("reconcile", help="Prune evicted backends and sync live sandboxes with LiteLLM")
    sub.add_parser("doctor", help="Check credentials, Daytona API, weights volume, and gateway health")

    for cmd_name in ("up", "recover"):
        p = sub.add_parser(cmd_name, help=f"{cmd_name} a managed spot GPU role")
        p.add_argument("role", choices=["specialist", "flagship"])
        p.add_argument("--gpu", default="auto", help="auto or explicit GPU type (H200, MI355X, B200, B300, RTX-PRO-6000, H100)")
        p.add_argument("--quant", choices=["Q8_0", "Q6_K"], default=None)
        p.add_argument("--allow-q6-fallback", action="store_true")
        p.add_argument("--ttl", type=int, default=120)

    p_down = sub.add_parser("down", help="Delete a managed GPU sandbox and deregister its aliases")
    p_down.add_argument("role", choices=["specialist", "flagship"])

    p_ext = sub.add_parser("extend", help="Reset wall-clock TTL minutes on a managed GPU sandbox")
    p_ext.add_argument("role", choices=["specialist", "flagship"])
    p_ext.add_argument("minutes", nargs="?", type=int, default=120)

    p_save = sub.add_parser("save-cache", help="Persist vLLM/FlashInfer JIT cache from a live GPU sandbox onto weights volume")
    p_save.add_argument("role", choices=["specialist"])

    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        return
    dispatch = {
        "capacity": cmd_capacity,
        "status": cmd_status,
        "reconcile": cmd_reconcile,
        "doctor": cmd_doctor,
        "up": cmd_up,
        "recover": cmd_up,
        "down": cmd_down,
        "extend": cmd_extend,
        "save-cache": cmd_save_cache,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main(sys.argv[1:])
