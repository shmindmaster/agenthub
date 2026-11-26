"""Daytona spot GPU lifecycle helper for AgentHub inference.

Enforces:
- Spot-only Daytona GPU sandboxes (never on-demand).
- The recorded model-hosting authorization: exactly two AMD MI355X sandboxes
  in the engineering and media roles, nothing else, and the llm-models volume
  retained but never written to.
- One GPU per instance.
- Central LiteLLM gateway backend updates at https://inference.shtrial.com without
  touching individual coding-agent configurations on eviction or replacement.

The authorization is data in catalog.json (policy.modelHostingAuthorization), not
a magic sandbox id in this file. A third GPU sandbox, a non-AMD GPU, an unknown
role sandbox or an unauthorized volume is refused rather than adopted.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parent
CATALOG_PATH = ROOT / "catalog.json"
CADDY_SNIPPET_PATH = ROOT / "gateway" / "Caddyfile.snippet"
RUNTIME_DIR = (
    Path(os.environ.get("LOCALAPPDATA") or (Path.home() / ".config")) / "AgentHub" / "daytona-inference"
    if (ROOT.parent.parent / ".git").exists()
    else ROOT
)
STATE_PATH = RUNTIME_DIR / "state.json"
SECRET_DIR = RUNTIME_DIR / "secrets"
LOG_DIR = RUNTIME_DIR / "logs"

MANAGED_ROLES = ["engineering", "media", "specialist", "flagship"]
# A live check alone is not enough: MI355X spot boxes were evicted 28 and 42 minutes after a verified boot (2026-11-25).
MIN_ENGINEERING_UPTIME_HOURS = 6
DEFAULT_ALIVE_PATTERN = r"[v]llm serve|[v]llm\.entrypoints\.openai\.api_server|[l]lama-server|[s]erve-(specialist|flagship|engineering)"


def media_server_dir() -> Path:
    override = os.environ.get("MEDIA_GPU_GEN_SERVER_DIR", "").strip()
    if override:
        return Path(override)
    media_root = os.environ.get("MEDIA_STUDIO_ROOT", "").strip() or r"D:\Media-Studio"
    return Path(media_root) / "gpu-gen" / "server"


def role_volume_spec(role: str, catalog: dict[str, Any]) -> tuple[str, str]:
    policy = catalog["policy"]
    if role == "media":
        return str(policy["mediaVolumeName"]), str(policy["mediaMountPath"])
    return str(policy["weightsVolumeName"]), str(policy["weightsMountPath"])


def load_catalog() -> dict[str, Any]:
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def ttl_minutes(value: str) -> int:
    """argparse type: every managed sandbox gets a wall-clock TTL between 1 minute and the catalog cap."""
    cap = int(load_catalog()["policy"].get("maxTtlMinutes", 480))
    try:
        minutes = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"TTL must be whole minutes, got {value!r}") from exc
    if not 1 <= minutes <= cap:
        raise argparse.ArgumentTypeError(f"TTL must be 1-{cap} minutes (policy.maxTtlMinutes), got {minutes}")
    return minutes


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


def gpu_authorization(catalog: dict[str, Any] | None = None) -> dict[str, Any]:
    """The owner's recorded model-hosting authorization, read from the catalog."""
    return (catalog or load_catalog())["policy"]["modelHostingAuthorization"]


def authorized_sandbox_names(catalog: dict[str, Any] | None = None) -> set[str]:
    """Every sandbox name the authorization permits, including recorded legacy names."""
    effective = catalog or load_catalog()
    names: set[str] = set()
    for role in gpu_authorization(effective)["allowedRoles"]:
        role_cfg = effective["roles"][role]
        names.add(str(role_cfg["sandboxName"]))
        names.update(str(name) for name in role_cfg.get("legacySandboxNames", []))
    return names


def active_gpu_sandboxes(live_sandboxes: list[Any]) -> list[Any]:
    return [
        sb
        for sb in live_sandboxes
        if getattr(sb, "gpu", 0)
        and "DESTROY" not in str(getattr(sb, "state", "")).upper()
        and "ARCHIV" not in str(getattr(sb, "state", "")).upper()
    ]


def protect_sandbox(sandbox: Any, catalog: dict[str, Any] | None = None) -> None:
    """Refuse to modify a GPU sandbox outside the recorded authorization."""
    effective = catalog or load_catalog()
    auth = gpu_authorization(effective)
    sid = getattr(sandbox, "id", "")
    sname = getattr(sandbox, "name", "")
    gpu_type = gpu_value(getattr(sandbox, "gpu_type", ""))
    if gpu_type not in auth["allowedGpuTypes"] or sname not in authorized_sandbox_names(effective):
        raise SystemExit(
            f"refusing to modify GPU sandbox {sname} ({sid}) gpu={gpu_type}: "
            f"outside the recorded authorization ({', '.join(auth['allowedGpuTypes'])} in "
            f"{', '.join(auth['allowedRoles'])})"
        )


def protect_volume_name(name: str, catalog: dict[str, Any] | None = None) -> None:
    retained = gpu_authorization(catalog)["retainedVolumes"]
    if name in retained:
        raise SystemExit(f"refusing to write weights to retained volume {name}")


def check_gpu_authorization(
    live_sandboxes: list[Any], catalog: dict[str, Any] | None = None
) -> tuple[bool, str]:
    """Pure check used by status, doctor and every mutating path. Never mutates."""
    effective = catalog or load_catalog()
    auth = gpu_authorization(effective)
    active = active_gpu_sandboxes(live_sandboxes)
    names = authorized_sandbox_names(effective)
    allowed_types = set(auth["allowedGpuTypes"])
    unauthorized = [
        sb for sb in active
        if gpu_value(getattr(sb, "gpu_type", "")) not in allowed_types
        or getattr(sb, "name", "") not in names
    ]
    if unauthorized:
        summary = ", ".join(
            f"{getattr(sb, 'name', '')}({gpu_value(getattr(sb, 'gpu_type', ''))})" for sb in unauthorized
        )
        return False, f"unauthorized GPU sandbox running: {summary}; authorization permits only {', '.join(auth['allowedRoles'])} on {', '.join(sorted(allowed_types))}"
    limit = int(auth["maxGpuInstances"])
    if len(active) > limit:
        summary = ", ".join(f"{sb.name}({gpu_value(sb.gpu_type)})" for sb in active)
        return False, f"{len(active)} GPU sandboxes running, authorization permits {limit}: {summary}"
    return True, f"{len(active)}/{limit} authorized GPU sandboxes"


def assert_gpu_authorization(live_sandboxes: list[Any], catalog: dict[str, Any] | None = None) -> None:
    ok, detail = check_gpu_authorization(live_sandboxes, catalog)
    if not ok:
        raise SystemExit(f"GPU hosting authorization refused: {detail}")


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


def enforce_gpu_limit(
    live_sandboxes: list[Any],
    target_sandbox_names: set[str],
    max_gpus: int | None = None,
    catalog: dict[str, Any] | None = None,
) -> None:
    """Refuse unauthorized GPU sandboxes, then enforce the recorded instance cap."""
    effective = catalog or load_catalog()
    assert_gpu_authorization(live_sandboxes, effective)
    limit = int(max_gpus if max_gpus is not None else gpu_authorization(effective)["maxGpuInstances"])
    active_gpu_boxes = active_gpu_sandboxes(live_sandboxes)
    reusable = [sb for sb in active_gpu_boxes if getattr(sb, "name", "") in target_sandbox_names]
    if reusable:
        return
    if len(active_gpu_boxes) >= limit:
        summary = ", ".join(f"{sb.name}({gpu_value(sb.gpu_type)})" for sb in active_gpu_boxes)
        raise SystemExit(
            f"GPU instance limit reached ({len(active_gpu_boxes)}/{limit} active: {summary}). "
            "Refusing to start a 3rd GPU instance."
        )


def ensure_volume(v0: Any, volume_name: str) -> str:
    protect_volume_name(volume_name)
    volume = v0.volume.get(volume_name, create=True)
    protect_volume_name(str(volume.name))
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


def gateway_delete_by_role_or_alias(aliases: list[str], exclude_sandbox_id: str | None = None) -> int:
    models = gateway_list_models()
    deleted = 0
    for item in models:
        mname = item.get("model_name")
        info = item.get("model_info") or {}
        mid = info.get("id")
        if exclude_sandbox_id and info.get("sandbox_id") == exclude_sandbox_id:
            continue
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


def wait_for_sandbox_models(
    sandbox: Any,
    port: int,
    expected_model: str,
    log_file: str,
    alive_pattern: str = DEFAULT_ALIVE_PATTERN,
) -> list[str]:
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
            print(f"worker_models port={port} http={code} ids={','.join(ids) if ids else '-'}", flush=True)
            last_marker = marker
        if code == 200 and expected_model in ids:
            return ids
        alive = sandbox.process.exec(
            f"ps -eo args | grep -E '{alive_pattern}' >/dev/null && echo UP || echo DOWN",
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


def upload_media_server_files(sandbox: Any) -> list[str]:
    src_dir = media_server_dir()
    required = ("models.json", "gateway.py", "audio_worker.py")
    missing = [name for name in required if not (src_dir / name).is_file()]
    if missing:
        raise SystemExit(f"Missing media server files in {src_dir}: {', '.join(missing)}")
    sandbox.process.exec("mkdir -p /opt/gpu-gen/server /run /opt", timeout=30)
    uploaded: list[str] = []
    for name in required:
        payload = (src_dir / name).read_bytes().replace(b"\r\n", b"\n")
        sandbox.fs.upload_file(payload, f"/opt/gpu-gen/server/{name}")
        uploaded.append(name)
    print(f"media_server uploaded={','.join(uploaded)} from={src_dir}")
    return uploaded


def wait_for_media_gateway(sandbox: Any, port: int, fallback_token: str, log_file: str) -> tuple[str, dict[str, Any]]:
    started_at = time.time()
    deadline = started_at + 50 * 60
    last_marker = ""
    down_streak = 0
    while time.time() < deadline:
        cmd = (
            "python3 - <<'PY'\n"
            "import json, pathlib, urllib.request\n"
            "tok_path = pathlib.Path('/opt/gpu-gen/token')\n"
            f"tok = tok_path.read_text().strip() if tok_path.is_file() else {json.dumps(fallback_token)}\n"
            "try:\n"
            f"    with urllib.request.urlopen('http://127.0.0.1:{port}/healthz', timeout=10) as hz:\n"
            "        hz_code = hz.status\n"
            f"    req = urllib.request.Request('http://127.0.0.1:{port}/v1/info', headers={{'Authorization': 'Bearer ' + tok}})\n"
            "    with urllib.request.urlopen(req, timeout=15) as inf:\n"
            "        info_body = json.load(inf)\n"
            "        print(f'{hz_code}:{inf.status}')\n"
            "        print(tok)\n"
            "        print(json.dumps(info_body))\n"
            "except Exception as exc:\n"
            "    print('0:0')\n"
            "    print(type(exc).__name__)\n"
            "PY"
        )
        res = sandbox.process.exec(cmd, timeout=30)
        lines = [line.strip() for line in (res.result or "").splitlines() if line.strip()]
        status_pair = lines[0] if lines else "0:0"
        if status_pair != last_marker:
            detail = lines[1] if status_pair == "0:0" and len(lines) > 1 else "ready"
            print(f"media_gateway port={port} healthz_info={status_pair} ({detail})", flush=True)
            last_marker = status_pair
        if status_pair == "200:200" and len(lines) >= 3:
            media_token = lines[1]
            info_json = json.loads(lines[2])
            return media_token, info_json
        alive = sandbox.process.exec(
            "ps -eo args | grep -E '[s]erve-media|[g]ateway\\.py|[C]omfyUI' >/dev/null && echo UP || echo DOWN",
            timeout=20,
        )
        if "UP" in (alive.result or ""):
            down_streak = 0
        elif time.time() - started_at > 20:
            down_streak += 1
            if down_streak >= 2:
                tail = sandbox.process.exec(f"tail -n 30 {log_file} 2>/dev/null || true", timeout=20)
                print(tail.result or "")
                raise SystemExit("Media gateway process exited before passing /healthz and /v1/info")
        time.sleep(20)
    tail = sandbox.process.exec(f"tail -n 30 {log_file} 2>/dev/null || true", timeout=30)
    print(tail.result or "")
    raise SystemExit("Media gateway did not pass /healthz and /v1/info before timeout")


def write_media_target_json(
    sandbox: Any,
    gpu_name: str,
    preview_origin: str,
    port: int,
    gateway_media_url: str,
    target_path: Path | None = None,
) -> Path:
    dest = target_path or (media_server_dir() / "target.json")
    dest.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "sandbox_id": str(sandbox.id),
        "name": str(sandbox.name),
        "gpu": gpu_name,
        "gpu_type": gpu_name,
        "preview_origin": preview_origin.rstrip("/"),
        "port": int(port),
        "gg_root": "/opt/gpu-gen",
        "gateway_url": gateway_media_url.rstrip("/"),
        "updated_at": utc_now(),
        "note": "Managed by AgentHub gpu.py media role (Slot 2 Daytona Spot GPU). No secrets stored here.",
    }
    dest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return dest


def render_caddyfile_site_block(
    owner_ip: str,
    inference_key: str,
    media_preview_url: str,
    media_preview_token: str,
    media_gateway_token: str,
    template_path: Path | None = None,
) -> str:
    src = template_path or CADDY_SNIPPET_PATH
    text = src.read_text(encoding="utf-8")
    replacements = {
        "<OWNER_IP>": owner_ip.strip(),
        "<AGENTHUB_INFERENCE_KEY>": inference_key.strip(),
        "<MEDIA_PREVIEW_URL>": media_preview_url.strip().rstrip("/"),
        "<MEDIA_PREVIEW_TOKEN>": media_preview_token.strip(),
        "<MEDIA_GATEWAY_TOKEN>": media_gateway_token.strip(),
    }
    for placeholder, val in replacements.items():
        if not val:
            raise SystemExit(f"Cannot render Caddyfile block: missing value for {placeholder}")
        text = text.replace(placeholder, val)
    lines = [line for line in text.splitlines() if not line.lstrip().startswith("#")]
    return "\n".join(lines).strip() + "\n"


def upsert_caddy_site_block(existing_caddyfile: str, site_host: str, new_block: str) -> str:
    pattern = re.compile(rf"(?m)^[ \t]*{re.escape(site_host)}[ \t]*\{{")
    match = pattern.search(existing_caddyfile)
    if not match:
        sep = "" if not existing_caddyfile or existing_caddyfile.endswith("\n") else "\n"
        prefix = existing_caddyfile + sep + ("\n" if existing_caddyfile.strip() else "")
        return prefix + new_block.strip() + "\n"
    start = match.start()
    depth = 0
    idx = match.end() - 1
    end = len(existing_caddyfile)
    while idx < len(existing_caddyfile):
        ch = existing_caddyfile[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = idx + 1
                break
        idx += 1
    while end < len(existing_caddyfile) and existing_caddyfile[end] in "\r\n":
        end += 1
    before = existing_caddyfile[:start].rstrip()
    after = existing_caddyfile[end:].lstrip("\r\n")
    parts = []
    if before:
        parts.append(before)
    parts.append(new_block.strip())
    if after:
        parts.append(after.rstrip())
    return "\n\n".join(parts) + "\n"


def update_sh_forge_caddy(
    preview_origin: str | None = None,
    preview_token: str | None = None,
    media_token: str | None = None,
    owner_ip: str | None = None,
    dry_run: bool = False,
) -> None:
    state = load_state()
    media_worker = state.get("workers", {}).get("media", {})
    url = (preview_origin or media_worker.get("preview_origin") or "").strip().rstrip("/")
    if not url:
        target_file = media_server_dir() / "target.json"
        if target_file.is_file():
            url = str(json.loads(target_file.read_text(encoding="utf-8")).get("preview_origin", "")).strip().rstrip("/")
    if not url:
        raise SystemExit("Media preview URL unavailable; run `gpu.py up media` or pass --preview-url")
    p_tok = (preview_token or read_secret_value(("MEDIA_PREVIEW_TOKEN",), "media.preview")).strip()
    g_tok = (media_token or read_secret_value(("MEDIA_GATEWAY_TOKEN", "INFERENCE_WORKER_API_KEY", "H100_LLM_API_KEY"), "media.token")).strip()
    inf_key = read_secret_value(("AGENTHUB_INFERENCE_KEY",), "inference.key").strip()
    if not p_tok:
        raise SystemExit("Missing media.preview secret; run `gpu.py up media` first")
    if not g_tok:
        raise SystemExit("Missing media.token secret; run `gpu.py up media` first")
    if not inf_key:
        raise SystemExit("Missing AGENTHUB_INFERENCE_KEY / secrets/inference.key")

    ssh_host = os.environ.get("SH_FORGE_SSH_HOST", "sh-inference").strip() or "sh-inference"
    resolved_ip = (owner_ip or os.environ.get("OWNER_IP", "")).strip()
    existing_caddy = ""
    if not dry_run:
        read_res = subprocess.run(
            ["ssh", ssh_host, "cat /opt/forge/caddy/Caddyfile"],
            capture_output=True,
            text=True,
            check=False,
        )
        if read_res.returncode != 0:
            raise SystemExit(f"Failed to read /opt/forge/caddy/Caddyfile on {ssh_host}: {read_res.stderr.strip()[:240]}")
        existing_caddy = read_res.stdout
        if not resolved_ip:
            m = re.search(r"@owner\s+remote_ip\s+([0-9A-Fa-f:./]+)", existing_caddy)
            if m:
                resolved_ip = m.group(1)
    if not resolved_ip:
        resolved_ip = "127.0.0.1" if dry_run else ""
    if not resolved_ip:
        raise SystemExit("Unable to determine owner IP from --owner-ip, OWNER_IP, or remote Caddyfile @owner rule")

    block = render_caddyfile_site_block(resolved_ip, inf_key, url, p_tok, g_tok)
    if dry_run:
        print(
            f"dry_run caddy-media upstream={url} owner_ip={resolved_ip} "
            f"preview_token={mask_secret(p_tok)} media_token={mask_secret(g_tok)} inference_key={mask_secret(inf_key)}"
        )
        return

    updated_caddy = existing_caddy
    for host in ("inference.shtrial.com", "comfy.shtrial.com"):
        host_match = re.search(rf"(?m)^[ \t]*{re.escape(host)}[ \t]*\{{", block)
        if not host_match:
            continue
        start = host_match.start()
        depth, idx, end = 0, host_match.end() - 1, len(block)
        while idx < len(block):
            if block[idx] == "{":
                depth += 1
            elif block[idx] == "}":
                depth -= 1
                if depth == 0:
                    end = idx + 1
                    break
            idx += 1
        updated_caddy = upsert_caddy_site_block(updated_caddy, host, block[start:end])
    remote_cmd = (
        # Write in place: the container bind-mounts this one file, and a rename would leave it reading the old one.
        "cat > /opt/forge/caddy/Caddyfile && "
        "if command -v caddy >/dev/null 2>&1; then "
        "caddy validate --config /opt/forge/caddy/Caddyfile && "
        "(systemctl reload caddy 2>/dev/null || service caddy reload 2>/dev/null); "
        "elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qi caddy; then "
        "CCTR=$(docker ps --format '{{.Names}}' | grep -i caddy | head -n1); "
        "docker exec \"$CCTR\" caddy validate --config /etc/caddy/Caddyfile && "
        "docker exec \"$CCTR\" caddy reload --config /etc/caddy/Caddyfile; "
        "else echo 'no caddy binary or caddy container found' >&2; exit 1; "
        "fi"
    )
    # Send bytes: text-mode stdin would turn every newline into CRLF on Windows.
    write_res = subprocess.run(
        ["ssh", ssh_host, remote_cmd],
        input=updated_caddy.encode("utf-8"),
        capture_output=True,
        check=False,
    )
    if write_res.returncode != 0:
        # The new file is already in place when validate/reload fails; put the previous content back (no reload).
        restored = False
        if existing_caddy.strip():
            restore_res = subprocess.run(
                ["ssh", ssh_host, "cat > /opt/forge/caddy/Caddyfile"],
                input=existing_caddy.encode("utf-8"),
                capture_output=True,
                check=False,
            )
            restored = restore_res.returncode == 0
        raise SystemExit(
            f"Failed to update Caddy on {ssh_host} (previous Caddyfile restored={restored}): "
            f"{(write_res.stderr or write_res.stdout).decode('utf-8', errors='replace').strip()[:300]}"
        )
    print(
        f"caddy_updated host={ssh_host} upstream={url} "
        f"preview_token={mask_secret(p_tok)} media_token={mask_secret(g_tok)}"
    )


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
    auth = gpu_authorization(catalog)
    if role not in auth["allowedRoles"]:
        raise SystemExit(
            f"role '{role}' is not in the recorded model-hosting authorization "
            f"({', '.join(auth['allowedRoles'])}); refusing to start a GPU sandbox"
        )
    role_cfg = catalog["roles"][role]
    vol_name, mount_path = role_volume_spec(role, catalog)
    app = get_daytona_client()
    try:
        v0 = app.v0
        from daytona.v0 import CreateSandboxFromImageParams, CreateSandboxFromSnapshotParams, GpuType, Resources, VolumeMount

        live = list(v0.list())
        names = {role_cfg["sandboxName"], *role_cfg.get("legacySandboxNames", [])}
        enforce_gpu_limit(live, names, catalog["policy"]["maxGpuInstancesTotal"])

        volume_id = ensure_volume(v0, vol_name)
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
                        volumes=[VolumeMount(volume_id=volume_id, mount_path=mount_path)],
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
                        volumes=[VolumeMount(volume_id=volume_id, mount_path=mount_path)],
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

        port = int(role_cfg["port"])
        origin, preview_token = preview_origin_and_token(sandbox, port, role)
        worker_key = upload_runtime_keys(sandbox)

        recipe_rel = profile["recipe"]
        recipe_bytes = (ROOT / recipe_rel).read_bytes().replace(b"\r\n", b"\n")
        remote_script = f"/opt/serve-{role}.sh"
        sandbox.fs.upload_file(recipe_bytes, remote_script)

        if role == "media":
            upload_media_server_files(sandbox)
            env_vars = {
                "PORT": str(port),
                "WEIGHTS_ROOT": mount_path,
                "GPU_TYPE": gpu_name,
            }
            env_prefix = " ".join(f"{k}={json.dumps(v)}" for k, v in env_vars.items())
            log_file = "/tmp/media.log"
            already_up = sandbox.process.exec(
                "ps -eo args | grep -E '[s]erve-media|[g]ateway\\.py' >/dev/null && echo UP || echo DOWN",
                timeout=20,
            )
            if "UP" not in (already_up.result or ""):
                sandbox.process.exec(
                    f"mkdir -p /run /opt && chmod 755 {remote_script} && "
                    f"setsid -f env {env_prefix} bash {remote_script} </dev/null >/tmp/media.nohup 2>&1",
                    timeout=30,
                )
            media_token, media_info = wait_for_media_gateway(sandbox, port, worker_key, log_file)
            write_secret("media.token", media_token)
            sandbox.set_ttl(args.ttl)
            sandbox.refresh_data()
            target_path = write_media_target_json(sandbox, gpu_name, origin, port, catalog["policy"]["gatewayMediaUrl"])

            state = load_state()
            state["media_volume_id"] = volume_id
            state["media_volume_name"] = vol_name
            state.setdefault("workers", {})["media"] = {
                "sandbox_id": sandbox.id,
                "name": sandbox.name,
                "spot": True,
                "gpu_type": gpu_name,
                "backend": profile["backend"],
                "image": catalog["images"][profile["backend"]]["image"],
                "volume_id": volume_id,
                "volume_name": vol_name,
                "mount_path": mount_path,
                "preview_origin": origin,
                "gateway_media_url": catalog["policy"]["gatewayMediaUrl"],
                "target_json": str(target_path),
                "media_gpu_info": media_info.get("gpu"),
                "ttl_minutes": args.ttl,
                "auto_destroy_at": sandbox.auto_destroy_at,
                "status": "serving",
                "checked_at": utc_now(),
            }
            save_state(state)
            print(f"serving role=media gpu={gpu_name} preview={origin} target={target_path}")
            if os.environ.get("SH_FORGE_UPDATE", "").strip() == "1":
                update_sh_forge_caddy(preview_origin=origin, preview_token=preview_token, media_token=media_token)
            return

        is_dual = role == "engineering" and profile.get("backend") == "engineering-rocm-gfx950"
        flagship_enabled = is_dual and (
            os.environ.get("FLAGSHIP_ENABLED", "1" if role_cfg.get("flagshipEnabled", False) else "0").strip() == "1"
        )
        if is_dual:
            flag_quant = str(args.quant or "Q8_0")
            flag_port = int(role_cfg["flagshipPort"])
            env_vars = {
                "FLAGSHIP_ENABLED": "1" if flagship_enabled else "0",
                "WEIGHTS_ROOT": mount_path,
                "GPU_TYPE": gpu_name,
                "SPEC_REPO": role_cfg["modelRepo"],
                "SPEC_FILE": str(role_cfg.get("modelFile", "")),
                "SPEC_MMPROJ": str(role_cfg.get("modelMmproj", "")),
                "FLAG_REPO": role_cfg["flagshipRepo"],
                "FLAG_FILE": str(role_cfg.get("flagshipFile", "")),
                "FLAG_MMPROJ": str(role_cfg.get("flagshipMmproj", "")),
                "FLAG_QUANT": flag_quant,
                "SPEC_PORT": str(port),
                "FLAG_PORT": str(flag_port),
                "MAX_MODEL_LEN": str(profile["maxModelLen"]),
                "CTX_SIZE": str(profile["ctxSize"]),
                "MAX_NUM_SEQS": str(profile["maxNumSeqs"]),
                "GPU_MEM_UTIL": str(profile["gpuMemUtil"]),
                "MAX_NUM_BATCHED_TOKENS": str(profile["maxNumBatchedTokens"]),
                "MTP_TOKENS": str(profile["mtpTokens"]),
                "PARALLEL": str(profile["parallel"]),
                "FLAG_PARALLEL": str(profile.get("flagshipParallel", 1)),
                "BATCH_SIZE": str(profile["batchSize"]),
                "UBATCH_SIZE": str(profile["ubatchSize"]),
                "CACHE_TYPE_K": str(profile["cacheTypeK"]),
                "CACHE_TYPE_V": str(profile["cacheTypeV"]),
                "FLAG_CACHE_TYPE_K": str(profile.get("flagshipCacheTypeK", "q8_0")),
                "FLAG_CACHE_TYPE_V": str(profile.get("flagshipCacheTypeV", "q8_0")),
            }
        else:
            env_vars = {
                "MODEL_REPO": role_cfg["modelRepo"],
                "SERVED_MODEL_NAME": role_cfg["primaryServedModelName"],
                "PORT": str(port),
                "WEIGHTS_ROOT": mount_path,
                "GPU_TYPE": gpu_name,
            }
            if role in ("specialist", "engineering"):
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
        log_file = "/tmp/specialist.log" if is_dual else f"/tmp/{role}.log"
        # Skip re-launching if the worker process (staging or serving) is already alive.
        already_up = sandbox.process.exec(
            f"ps -eo args | grep -E '{DEFAULT_ALIVE_PATTERN}' >/dev/null && echo UP || echo DOWN",
            timeout=20,
        )
        if "UP" not in (already_up.result or ""):
            sandbox.process.exec(
                f"mkdir -p /run /opt && chmod 755 {remote_script} && "
                f"setsid -f env {env_prefix} bash {remote_script} </dev/null >/tmp/{role}.nohup 2>&1",
                timeout=30,
            )
        wait_for_sandbox_models(sandbox, port, role_cfg["primaryServedModelName"], log_file)
        if flagship_enabled:
            wait_for_sandbox_models(sandbox, int(role_cfg["flagshipPort"]), role_cfg["flagshipServedModelName"], "/tmp/flagship.log")
        sandbox.set_ttl(args.ttl)
        sandbox.refresh_data()

        api_base = origin.rstrip("/") + "/v1"
        upstream_model = f"openai/{role_cfg['primaryServedModelName']}"
        gateway_ids: dict[str, str] = {}
        spec_ctx = int(profile.get("maxModelLen") or profile.get("ctxSize"))
        for alias in role_cfg["servedAliases"]:
            info = {
                "id": f"{alias}-{sandbox.id[:8]}",
                "mode": "chat",
                "max_input_tokens": spec_ctx - int(profile["maxOutputTokens"]),
                "max_output_tokens": int(profile["maxOutputTokens"]),
                "supports_function_calling": bool(role_cfg["tools"]),
                "supports_vision": bool(role_cfg["vision"]),
                "supports_reasoning": True,
                "gpu_type": gpu_name,
                "quantization": profile["quantization"],
                "sandbox_id": sandbox.id,
                "spot": True,
            }
            gateway_ids[alias] = gateway_register_alias(alias, upstream_model, api_base, worker_key, preview_token, info)

        registered_aliases = list(role_cfg["servedAliases"])
        flag_origin = ""
        if flagship_enabled:
            flag_port = int(role_cfg["flagshipPort"])
            flag_origin, flag_preview_token = preview_origin_and_token(sandbox, flag_port, "engineering-flagship")
            flag_api_base = flag_origin.rstrip("/") + "/v1"
            flag_upstream = f"openai/{role_cfg['flagshipServedModelName']}"
            flag_ctx = int(profile.get("ctxSize") or profile.get("maxModelLen"))
            for alias in role_cfg.get("flagshipAliases", []):
                info = {
                    "id": f"{alias}-{sandbox.id[:8]}",
                    "mode": "chat",
                    "max_input_tokens": flag_ctx - int(profile["maxOutputTokens"]),
                    "max_output_tokens": int(profile["maxOutputTokens"]),
                    "supports_function_calling": bool(role_cfg["tools"]),
                    "supports_vision": bool(role_cfg.get("flagshipVision", False)),
                    "supports_reasoning": True,
                    "gpu_type": gpu_name,
                    "quantization": profile["quantization"],
                    "sandbox_id": sandbox.id,
                    "spot": True,
                }
                gateway_ids[alias] = gateway_register_alias(alias, flag_upstream, flag_api_base, worker_key, flag_preview_token, info)
                registered_aliases.append(alias)

        state = load_state()
        state["volume_id"] = volume_id
        state["volume_name"] = vol_name
        worker_state: dict[str, Any] = {
            "sandbox_id": sandbox.id,
            "name": sandbox.name,
            "spot": True,
            "gpu_type": gpu_name,
            "backend": profile["backend"],
            "image": catalog["images"][profile["backend"]]["image"],
            "model_repo": role_cfg["modelRepo"],
            "quantization": profile["quantization"],
            "context_limit": spec_ctx,
            "max_output_tokens": int(profile["maxOutputTokens"]),
            "vision": bool(role_cfg["vision"]),
            "tools": bool(role_cfg["tools"]),
            "preview_origin": origin,
            "base_url": api_base,
            "served_aliases": registered_aliases,
            "gateway_model_ids": gateway_ids,
            "ttl_minutes": args.ttl,
            "auto_destroy_at": sandbox.auto_destroy_at,
            "status": "serving",
            "checked_at": utc_now(),
        }
        if flagship_enabled and flag_origin:
            worker_state["flagship_repo"] = role_cfg["flagshipRepo"]
            worker_state["flagship_preview_origin"] = flag_origin
            worker_state["flagship_base_url"] = flag_origin.rstrip("/") + "/v1"
        state.setdefault("workers", {})[role] = worker_state
        save_state(state)
        print(f"serving role={role} gpu={gpu_name} aliases={','.join(registered_aliases)} gateway={catalog['policy']['gatewayBaseUrl']}")
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

    aliases = [*role_cfg.get("servedAliases", []), *role_cfg.get("flagshipAliases", [])]
    removed = gateway_delete_by_role_or_alias(aliases) if aliases else 0
    print(f"gateway_deregistered aliases={','.join(aliases) or '-'} count={removed}")
    if worker:
        worker["status"] = "deleted"
        worker["checked_at"] = utc_now()
        save_state(state)


def cmd_extend(args: argparse.Namespace) -> None:
    load_catalog()
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
    auth_ok, auth_detail = check_gpu_authorization(sbs, catalog)
    print(f"state_file {STATE_PATH}")
    print(f"gpu_authorization {'OK' if auth_ok else 'FAIL'}: {auth_detail}")
    print(f"gpu_instances {len(sbs)}/{gpu_authorization(catalog)['maxGpuInstances']}")
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
        all_sandboxes = list(app.v0.list())
        live = {
            sb.id: sb
            for sb in all_sandboxes
            if getattr(sb, "gpu", 0) and "STARTED" in str(sb.state).upper()
        }
    finally:
        app.close()
    assert_gpu_authorization(all_sandboxes, catalog)

    registered = gateway_list_models()
    for item in registered:
        info = item.get("model_info") or {}
        sid = info.get("sandbox_id")
        mid = info.get("id")
        mname = item.get("model_name")
        if sid and sid not in live and mid:
            code, _ = litellm_request("POST", "/model/delete", {"id": mid}, require_master=True)
            print(f"pruned stale alias={mname} sandbox={sid} http={code}")

    # No legacy sandbox is authorized: aliases whose backend is gone are pruned
    # above and never re-registered here.

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


def sandbox_age_hours(sandbox: Any, now: datetime | None = None) -> float | None:
    """Hours since the sandbox was created, or None when the API gave no usable createdAt."""
    raw = getattr(sandbox, "created_at", None) or getattr(sandbox, "createdAt", None)
    if not raw:
        return None
    try:
        created = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except ValueError:
        return None
    if created.tzinfo is None:
        created = created.replace(tzinfo=timezone.utc)
    return ((now or datetime.now(timezone.utc)) - created).total_seconds() / 3600


def check_retire_legacy_turbo_gates(
    live_sandboxes: list[Any],
    gateway_base_url: str,
    inference_key: str,
    probe_fn: Callable[[str, str, dict[str, Any] | None], tuple[int, dict[str, Any]]] | None = None,
    now: datetime | None = None,
) -> Any:
    """Verify engineering has been STARTED for MIN_ENGINEERING_UPTIME_HOURS and is live-verified on the gateway."""
    eng_sb = next(
        (
            sb
            for sb in live_sandboxes
            if getattr(sb, "name", "") == "agenthub-engineering"
            and "STARTED" in str(getattr(sb, "state", "")).upper()
        ),
        None,
    )
    if eng_sb is None:
        raise SystemExit("Refusing retire-legacy-turbo: agenthub-engineering sandbox is not STARTED")
    age_hours = sandbox_age_hours(eng_sb, now)
    if age_hours is None:
        raise SystemExit("Refusing retire-legacy-turbo: agenthub-engineering has no readable createdAt, so its uptime is unknown")
    if age_hours < MIN_ENGINEERING_UPTIME_HOURS:
        raise SystemExit(
            f"Refusing retire-legacy-turbo: agenthub-engineering has been up {age_hours:.1f} h; "
            f"need {MIN_ENGINEERING_UPTIME_HOURS} h (spot boxes were evicted within an hour)"
        )
    if not inference_key:
        raise SystemExit("Refusing retire-legacy-turbo: AGENTHUB_INFERENCE_KEY / secrets/inference.key is missing")

    base = gateway_base_url.rstrip("/")

    def default_probe(method: str, path: str, body: dict[str, Any] | None) -> tuple[int, dict[str, Any]]:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Authorization": f"Bearer {inference_key}"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
                return resp.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(raw) if raw else {}
            except Exception:
                parsed = {"raw": raw[:200]}
            return exc.code, parsed
        except Exception as exc:
            return 0, {"error": type(exc).__name__}

    call = probe_fn or default_probe
    status_models, body_models = call("GET", "/models", None)
    if status_models != 200:
        raise SystemExit(f"Refusing retire-legacy-turbo: {base}/models returned HTTP {status_models}")
    listed_ids = {str(item.get("id", "")) for item in body_models.get("data", []) if isinstance(item, dict)}
    for required_alias in ("qwen3.8-27b-unc-q8", "inkling2-min-26b-unc-q8-128k"):
        if required_alias not in listed_ids:
            raise SystemExit(f"Refusing retire-legacy-turbo: {required_alias} missing from {base}/models")
        status_chat, body_chat = call(
            "POST",
            "/chat/completions",
            {
                "model": required_alias,
                "messages": [{"role": "user", "content": "Reply with OK"}],
                "max_tokens": 8,
            },
        )
        choices = body_chat.get("choices") or []
        if status_chat != 200 or not choices:
            raise SystemExit(
                f"Refusing retire-legacy-turbo: live {required_alias} check on {base} failed (http={status_chat})"
            )
    return eng_sb


def cmd_retire_legacy_turbo(args: argparse.Namespace) -> None:
    catalog = load_catalog()
    inf_key = read_secret_value(("AGENTHUB_INFERENCE_KEY",), "inference.key")
    gateway_base = catalog["policy"]["gatewayBaseUrl"]
    eng_cfg = catalog["roles"]["engineering"]
    worker_key = read_secret_value(("INFERENCE_WORKER_API_KEY", "H100_LLM_API_KEY"))

    app = get_daytona_client()
    try:
        live = list(app.v0.list())
        assert_gpu_authorization(live, catalog)
        eng_sb = check_retire_legacy_turbo_gates(live, gateway_base, inf_key)
        gpu_name = gpu_value(eng_sb.gpu_type)
        profile = dict(eng_cfg["profiles"].get(gpu_name) or next(iter(eng_cfg["profiles"].values())))
        flag_port = int(eng_cfg.get("flagshipPort") or eng_cfg["port"])
        flag_origin, flag_preview_token = preview_origin_and_token(eng_sb, flag_port, "engineering-flagship")
        if args.dry_run:
            print(f"dry_run retire-legacy-turbo READY engineering={eng_sb.id} flagship_origin={flag_origin}")
            return
        if not worker_key:
            raise SystemExit("Refusing retire-legacy-turbo: INFERENCE_WORKER_API_KEY / H100_LLM_API_KEY is missing")
        ctx = int(profile.get("ctxSize") or profile.get("maxModelLen"))
        max_out = int(profile["maxOutputTokens"])
        turbo_id = gateway_register_alias(
            "qwen3.8-27b-unc-q8",
            f"openai/{eng_cfg['flagshipServedModelName']}",
            flag_origin.rstrip("/") + "/v1",
            worker_key,
            flag_preview_token,
            {
                "id": f"qwen3.8-27b-unc-q8-{eng_sb.id[:8]}",
                "mode": "chat",
                "max_input_tokens": ctx - max_out,
                "max_output_tokens": max_out,
                "supports_function_calling": bool(eng_cfg["tools"]),
                "supports_vision": False,
                "supports_reasoning": True,
                "gpu_type": gpu_name,
                "quantization": profile["quantization"],
                "sandbox_id": eng_sb.id,
                "spot": True,
            },
        )
        print(f"routed qwen3.8-27b-unc-q8 -> {eng_sb.name} ({eng_sb.id}) id={turbo_id}")

        # The legacy H200 sandbox is not part of the recorded authorization and
        # was retired out of band. This command only re-routes qwen3.8-27b-unc-q8 to the
        # authorized engineering flagship; it never adopts or deletes another box.
        print("no legacy turbo sandbox is authorized; retained volumes were untouched")

        state = load_state()
        eng_worker = state.get("workers", {}).get("engineering")
        if eng_worker:
            aliases = list(eng_worker.get("served_aliases") or [])
            if "qwen3.8-27b-unc-q8" not in aliases:
                aliases.append("qwen3.8-27b-unc-q8")
            eng_worker["served_aliases"] = aliases
            eng_worker.setdefault("gateway_model_ids", {})["qwen3.8-27b-unc-q8"] = turbo_id
            eng_worker["checked_at"] = utc_now()
            save_state(state)
    finally:
        app.close()


def cmd_caddy_media(args: argparse.Namespace) -> None:
    update_sh_forge_caddy(
        preview_origin=args.preview_url,
        owner_ip=args.owner_ip,
        dry_run=args.dry_run,
    )


def cmd_save_cache(args: argparse.Namespace) -> None:
    catalog = load_catalog()
    role = args.role
    role_cfg = catalog["roles"][role]
    if role_cfg["engine"] not in ("vllm", "dual"):
        raise SystemExit(f"save-cache is only supported for vllm/dual roles (got engine={role_cfg['engine']})")
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


PREFILL_IMAGE = "python:3.12-slim"
PREFILL_POLL_SECONDS = 20


def cmd_prefill(args: argparse.Namespace) -> None:
    """Fill the media weights volume from Hugging Face on a throwaway CPU box (no GPU, no GPU slot used)."""
    catalog = load_catalog()
    vol_name, mount_path = role_volume_spec("media", catalog)
    hf_token = read_secret_value(("HF_TOKEN",), "hf.token")
    if len(hf_token) < 8:
        raise SystemExit("HF_TOKEN (or secrets/hf.token) is not set")
    models_path = media_server_dir() / "models.json"
    if not models_path.is_file():
        raise SystemExit(f"Missing {models_path}")
    script = (ROOT / "recipes" / "prefill-media.py").read_bytes().replace(b"\r\n", b"\n")
    run_id = f"media-prefill-{int(time.time())}"
    app = get_daytona_client()
    sandbox = None
    try:
        v0 = app.v0
        from daytona.v0 import CreateSandboxFromImageParams, Resources, VolumeMount

        volume_id = ensure_volume(v0, vol_name)
        sandbox = v0.create(
            CreateSandboxFromImageParams(
                image=PREFILL_IMAGE,
                public=False,
                ephemeral=True,
                auto_stop_interval=60,
                ttl_minutes=args.ttl,
                labels={"owner": "agenthub", "purpose": "media-prefill", "run": run_id},
                volumes=[VolumeMount(volume_id=volume_id, mount_path=mount_path)],
                resources=Resources(cpu=4, memory=8, disk=10),
            )
        )
        print(f"prefill box {sandbox.id} run={run_id} ttl_minutes={args.ttl}", flush=True)
        sandbox.fs.upload_file(hf_token.encode("utf-8"), "/tmp/hf.token")
        sandbox.process.exec("chmod 600 /tmp/hf.token", timeout=30)
        sandbox.fs.upload_file(script, "/tmp/prefill-media.py")
        sandbox.fs.upload_file(models_path.read_bytes().replace(b"\r\n", b"\n"), "/tmp/models.json")
        sandbox.process.exec(
            "touch /tmp/pf.run; nohup sh -c 'python3 /tmp/prefill-media.py > /tmp/prefill.log 2>&1; rm -f /tmp/pf.run' "
            ">/dev/null 2>&1 & echo started",
            timeout=30,
        )
        shown = 0
        deadline = time.time() + max(args.ttl - 5, 1) * 60
        log = ""
        while time.time() < deadline:
            time.sleep(PREFILL_POLL_SECONDS)
            res = sandbox.process.exec("cat /tmp/prefill.log; test -e /tmp/pf.run || echo NOT_RUNNING", timeout=60)
            log = res.result or ""
            if len(log) > shown:
                print(log[shown:].replace("NOT_RUNNING", "").rstrip("\n"), flush=True)
                shown = len(log)
            if "PREFILL_DONE" in log or "NOT_RUNNING" in log:
                break
        else:
            raise SystemExit("prefill did not finish before the TTL window; box deleted")
        if "PREFILL_DONE" not in log:
            raise SystemExit("prefill process stopped before PREFILL_DONE")
        if not re.search(r"^bad \[\]$", log, re.MULTILINE):
            raise SystemExit("prefill finished with failed files (see 'bad' line above); rerun to resume")
        print(f"prefill complete volume={vol_name}")
    finally:
        if sandbox is not None:
            try:
                sandbox.delete(timeout=120)
                print(f"deleted prefill box {sandbox.id}")
            except Exception as exc:
                print(f"WARNING: could not delete prefill box {sandbox.id} ({type(exc).__name__}); delete label run={run_id} by hand")
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
            media_vol_name = catalog["policy"].get("mediaVolumeName")
            if media_vol_name:
                try:
                    mvol = app.v0.volume.get(media_vol_name, create=False)
                    checks.append(("daytona.media_volume", True, f"{mvol.name} {mvol.state}"))
                except Exception as exc:
                    checks.append(("daytona.media_volume", False, type(exc).__name__))
            auth_ok, auth_detail = check_gpu_authorization(sbs, catalog)
            checks.append(("daytona.gpu_authorization", auth_ok, auth_detail))
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
        p.add_argument("role", choices=MANAGED_ROLES)
        p.add_argument("--gpu", default="auto", help="auto or explicit GPU type (MI355X, B300, B200, H200, RTX-PRO-6000, H100)")
        p.add_argument("--quant", choices=["Q8_0", "Q6_K"], default=None)
        p.add_argument("--allow-q6-fallback", action="store_true")
        p.add_argument("--ttl", type=ttl_minutes, default=120)

    p_down = sub.add_parser("down", help="Delete a managed GPU sandbox and deregister its aliases")
    p_down.add_argument("role", choices=MANAGED_ROLES)

    p_ext = sub.add_parser("extend", help="Reset wall-clock TTL minutes on a managed GPU sandbox")
    p_ext.add_argument("role", choices=MANAGED_ROLES)
    p_ext.add_argument("minutes", nargs="?", type=ttl_minutes, default=120)

    p_save = sub.add_parser("save-cache", help="Persist vLLM/FlashInfer JIT cache from a live GPU sandbox onto weights volume")
    p_save.add_argument("role", choices=["specialist", "engineering"])

    p_retire = sub.add_parser(
        "retire-legacy-turbo",
        help="Route the retired alias to the engineering flagship; no legacy GPU sandbox is authorized",
    )
    p_retire.add_argument("--dry-run", action="store_true")

    p_prefill = sub.add_parser("prefill", help="Fill the media weights volume from Hugging Face on a CPU box (no GPU)")
    p_prefill.add_argument("role", choices=["media"])
    p_prefill.add_argument("--ttl", type=ttl_minutes, default=90)

    p_caddy = sub.add_parser("caddy-media", help="Update sh-forge Caddyfile /v1/media/* proxy to Slot 2 media gateway")
    p_caddy.add_argument("--preview-url", default=None)
    p_caddy.add_argument("--owner-ip", default=None)
    p_caddy.add_argument("--dry-run", action="store_true")

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
        "retire-legacy-turbo": cmd_retire_legacy_turbo,
        "caddy-media": cmd_caddy_media,
        "prefill": cmd_prefill,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main(sys.argv[1:])
