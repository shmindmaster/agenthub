"""General-purpose client for the Daytona AI Media Lab gateway.

Supports:
1. Permanent gateway endpoint: `https://inference.shtrial.com/v1/media`
   with Bearer `AGENTHUB_INFERENCE_KEY` (or secrets/inference.key).
2. Direct Daytona sandbox preview URL fallback via `target.json` + `DAYTONA_API_KEY`
   (including `x-daytona-preview-token` and remote `/opt/gpu-gen/token` or `/root/gpu-gen/token`).

Supports job types:
  image | image_edit | video | talk | music | tts | speakers | transcribe

Enforces:
- `authorization_profile`: `commercial` (default, Apache-2.0/MIT) or `research`.
- SHA-256 + byte-size verification on every downloaded output before deleting the job from the server.
- Scene manifest skip-on-complete (`run-manifest`): skips any scene whose local output files already match recorded `size` and `sha256`.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_MEDIA_URL = "https://inference.shtrial.com/v1/media"
MEDIA_PORT = 8189
MAX_JOB_SECONDS = 7200
_SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def _safe_name(value: Any, what: str) -> str:
    """The server names job ids and output files; never let that name leave the output directory."""
    name = str(value)
    if not _SAFE_ID.match(name) or ".." in name:
        raise RuntimeError(f"refusing unsafe {what} from media server: {name[:80]!r}")
    return name


def _write_json_atomic(path: Path, data: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".part")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def _secret_file_candidates(filename: str) -> list[Path]:
    roots: list[Path] = []
    local_app = os.environ.get("LOCALAPPDATA", "").strip()
    if local_app:
        roots.append(Path(local_app) / "AgentHub" / "daytona-inference" / "secrets")
    roots.append(Path.home() / ".config" / "AgentHub" / "daytona-inference" / "secrets")
    return [r / filename for r in roots]


def _read_secret(env_names: tuple[str, ...], filename: str | None = None) -> str:
    for name in env_names:
        val = os.environ.get(name, "").strip()
        if val:
            return val
    if filename:
        for cand in _secret_file_candidates(filename):
            if cand.is_file():
                val = cand.read_text(encoding="utf-8").strip()
                if val:
                    return val
    return ""


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_target_json(explicit: str | Path | None = None) -> Path | None:
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    env_target = os.environ.get("DAYTONA_MEDIA_TARGET", "").strip()
    if env_target:
        candidates.append(Path(env_target))
    media_root = os.environ.get("MEDIA_STUDIO_ROOT", "").strip()
    if media_root:
        candidates.append(Path(media_root) / "gpu-gen" / "server" / "target.json")
    candidates.append(Path.cwd() / "target.json")
    for p in candidates:
        if p.is_file():
            return p
    return None


class MediaApiClient:
    """HTTP client supporting permanent inference gateway and Daytona preview URL fallback."""

    def __init__(
        self,
        base_url: str,
        bearer_token: str,
        extra_headers: dict[str, str] | None = None,
        mode: str = "gateway",
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.bearer_token = bearer_token.strip()
        self.extra_headers = dict(extra_headers or {})
        self.mode = mode

    @classmethod
    def from_gateway(cls, base_url: str | None = None, token: str | None = None) -> "MediaApiClient":
        url = (base_url or os.environ.get("AGENTHUB_MEDIA_URL") or DEFAULT_MEDIA_URL).rstrip("/")
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" and parsed.hostname not in ("localhost", "127.0.0.1", "::1"):
            raise RuntimeError(f"gateway URL must be https (the Bearer key is sent to it): {url}")
        key = (token or _read_secret(("AGENTHUB_INFERENCE_KEY",), "inference.key")).strip()
        if not key:
            raise RuntimeError("Missing AGENTHUB_INFERENCE_KEY (or secrets/inference.key) for gateway mode")
        return cls(url, key, mode="gateway")

    @classmethod
    def from_daytona(cls, target_path: str | Path | None = None) -> "MediaApiClient":
        if not os.environ.get("DAYTONA_API_KEY", "").strip():
            raise RuntimeError("Missing DAYTONA_API_KEY for direct Daytona preview fallback")
        tpath = find_target_json(target_path)
        if not tpath:
            raise RuntimeError("target.json not found; pass --target or set DAYTONA_MEDIA_TARGET")
        target_cfg = json.loads(tpath.read_text(encoding="utf-8"))
        sandbox_id = target_cfg.get("sandbox_id")
        if not sandbox_id:
            raise RuntimeError(f"target.json missing sandbox_id: {tpath}")

        from daytona import Daytona

        app = Daytona()
        try:
            v0 = getattr(app, "v0", app)
            sb = v0.get(sandbox_id)
            link = sb.get_preview_link(int(target_cfg.get("port", MEDIA_PORT)))
            preview_url = str(link.url).rstrip("/")
            preview_tok = str(getattr(link, "token", "") or "")
            tok = _read_secret(("MEDIA_GATEWAY_TOKEN",), "media.token")
            if not tok:
                for remote_tok in ("/opt/gpu-gen/token", "/root/gpu-gen/token"):
                    try:
                        tok = sb.fs.download_file(remote_tok).decode("utf-8").strip()
                        if tok:
                            break
                    except Exception:
                        continue
            if not tok:
                raise RuntimeError(f"Unable to read gateway token from sandbox {sandbox_id}")
            headers = {"x-daytona-preview-token": preview_tok} if preview_tok else {}
            return cls(preview_url, tok, extra_headers=headers, mode="daytona")
        finally:
            if hasattr(app, "close"):
                app.close()

    @classmethod
    def connect(
        cls,
        endpoint: str = "auto",
        gateway_url: str | None = None,
        target_path: str | Path | None = None,
    ) -> "MediaApiClient":
        if endpoint == "gateway":
            return cls.from_gateway(gateway_url)
        if endpoint == "daytona":
            return cls.from_daytona(target_path)

        # auto: prefer permanent gateway endpoint, fall back to direct Daytona sandbox preview URL
        gw_err: Exception | None = None
        try:
            client = cls.from_gateway(gateway_url)
            client.info(timeout=15)
            return client
        except Exception as exc:
            gw_err = exc

        try:
            return cls.from_daytona(target_path)
        except Exception as dt_err:
            raise RuntimeError(f"Failed both gateway ({gw_err}) and Daytona fallback ({dt_err})") from dt_err

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        raw: bool = False,
        timeout: int = 120,
    ) -> Any:
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(self.base_url + path, data=payload, method=method)
        req.add_header("Authorization", f"Bearer {self.bearer_token}")
        for k, v in self.extra_headers.items():
            req.add_header(k, v)
        if payload is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = resp.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:500]
            raise RuntimeError(f"{method} {path}: HTTP {exc.code} {detail}") from exc
        return data if raw else json.loads(data.decode("utf-8"))

    def info(self, timeout: int = 30) -> dict[str, Any]:
        return self.request("GET", "/v1/info", timeout=timeout)

    def submit_and_pull(
        self,
        job_type: str,
        params: dict[str, Any],
        out_dir: Path,
        authorization_profile: str = "commercial",
        poll_interval: float = 4.0,
        verbose: bool = False,
        delete_remote: bool = True,
    ) -> dict[str, Any]:
        job = self.request(
            "POST",
            "/v1/jobs",
            {"type": job_type, "authorization_profile": authorization_profile, "params": params},
        )
        jid = _safe_name(job["id"], "job id")
        t0 = time.time()
        while job["state"] not in ("done", "error"):
            if time.time() - t0 > MAX_JOB_SECONDS:
                raise RuntimeError(f"media job {jid} still {job['state']} after {MAX_JOB_SECONDS}s; left on the server")
            time.sleep(poll_interval)
            job = self.request("GET", f"/v1/jobs/{jid}")
            if verbose:
                print(f"  {time.time() - t0:5.1f}s {job['state']} {job.get('progress', '')}", file=sys.stderr, flush=True)
        if job["state"] == "error":
            raise RuntimeError(f"media job {jid} failed: {job.get('error', 'unknown error')}")

        accepted = pull_verified_outputs(self, job, out_dir)
        if delete_remote:
            self.request("DELETE", f"/v1/jobs/{jid}")
        return {
            "job": jid,
            "type": job_type,
            "model": job.get("model"),
            "authorization_profile": job.get("authorization_profile", authorization_profile),
            "endpoint_mode": self.mode,
            "seconds": job.get("seconds"),
            "peak_vram_mb": job.get("peak_vram_mb"),
            "peak_vram_gb": job.get("peak_vram_gb"),
            "files": accepted,
        }


def pull_verified_outputs(client: MediaApiClient, job: dict[str, Any], out_dir: Path) -> list[dict[str, Any]]:
    out_dir.mkdir(parents=True, exist_ok=True)
    accepted: list[dict[str, Any]] = []
    jid = _safe_name(job["id"], "job id")
    for item in job.get("outputs", []):
        name = _safe_name(item["name"], "output name")
        dest = out_dir / name
        if dest.is_file() and dest.stat().st_size == item["size"] and _sha256_file(dest) == item["sha256"]:
            accepted.append({**item, "path": str(dest), "note": "already_verified"})
            continue
        data = client.request("GET", f"/v1/files/{jid}/{urllib.parse.quote(name)}", raw=True, timeout=600)
        digest = _sha256_bytes(data)
        if len(data) != int(item["size"]) or digest != item["sha256"]:
            raise RuntimeError(
                f"SHA-256/size mismatch for {item['name']}: got {len(data)} B {digest[:12]}, "
                f"expected {item['size']} B {item['sha256'][:12]}"
            )
        tmp = dest.with_suffix(dest.suffix + ".part")
        tmp.write_bytes(data)
        tmp.replace(dest)
        accepted.append({**item, "path": str(dest)})
    return accepted


def scene_is_complete(entry: dict[str, Any], out_dir: Path) -> bool:
    """Return True if a scene manifest entry already has all outputs verified locally."""
    if entry.get("status") != "done":
        return False
    files = entry.get("files") or []
    if not files:
        return False
    for f in files:
        p = Path(f.get("path") or (out_dir / f["name"]))
        if not p.is_file():
            return False
        if p.stat().st_size != int(f["size"]) or _sha256_file(p) != f["sha256"]:
            return False
    return True


def _attach_file_params(params: dict[str, Any], input_path: str | None, audio_path: str | None, ref_audio_path: str | None) -> dict[str, Any]:
    out = dict(params)
    if input_path:
        p = Path(input_path)
        out["input_b64"] = base64.b64encode(p.read_bytes()).decode("ascii")
        out["input_name"] = p.name
    if audio_path:
        p = Path(audio_path)
        out["audio_b64"] = base64.b64encode(p.read_bytes()).decode("ascii")
        out["audio_name"] = p.name
    if ref_audio_path:
        p = Path(ref_audio_path)
        out["ref_audio_b64"] = base64.b64encode(p.read_bytes()).decode("ascii")
        out["ref_audio_name"] = p.name
    return out


def run_scene_manifest(
    client: MediaApiClient,
    manifest_path: Path,
    default_out_dir: Path,
    default_profile: str = "commercial",
    verbose: bool = False,
) -> dict[str, Any]:
    """Execute a scene manifest JSON with SHA-256 verification and skip-on-complete."""
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    scenes = manifest.get("scenes") if isinstance(manifest, dict) else manifest
    if not isinstance(scenes, list):
        raise ValueError("manifest must contain a 'scenes' list or be a JSON array")

    results: list[dict[str, Any]] = []
    skipped = 0
    executed = 0
    for idx, scene in enumerate(scenes):
        sid = str(scene.get("id") or f"scene-{idx + 1:03d}")
        scene_dir = Path(scene.get("out") or (default_out_dir / sid))
        if scene_is_complete(scene, scene_dir):
            skipped += 1
            results.append({"id": sid, "status": "skipped_complete", "files": scene["files"]})
            continue

        params = _attach_file_params(
            scene.get("params") or {},
            scene.get("input"),
            scene.get("audio"),
            scene.get("ref_audio"),
        )
        if scene.get("model") and "model" not in params:
            params["model"] = scene["model"]
        profile = str(scene.get("authorization_profile") or default_profile)
        record = client.submit_and_pull(
            job_type=scene["type"],
            params=params,
            out_dir=scene_dir,
            authorization_profile=profile,
            verbose=verbose,
        )
        scene["status"] = "done"
        scene["job"] = record["job"]
        scene["model"] = record["model"]
        scene["seconds"] = record["seconds"]
        scene["peak_vram_mb"] = record["peak_vram_mb"]
        scene["files"] = record["files"]
        executed += 1
        results.append({"id": sid, "status": "done", **record})
        if isinstance(manifest, dict):
            _write_json_atomic(manifest_path, manifest)

    if isinstance(manifest, dict):
        _write_json_atomic(manifest_path, manifest)
    return {"executed": executed, "skipped": skipped, "scenes": results}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Daytona AI Media Lab client (gateway + Daytona preview fallback)")
    p.add_argument("--endpoint", choices=["auto", "gateway", "daytona"], default="auto")
    p.add_argument("--gateway-url", default=None, help=f"Override permanent gateway URL (default {DEFAULT_MEDIA_URL})")
    p.add_argument("--target", default=None, help="Path to target.json for direct Daytona preview fallback")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info", help="Query /v1/info (GPU telemetry, models, authorization profiles)")

    r = sub.add_parser("run", help="Submit a media generation job and pull SHA-256 verified outputs")
    r.add_argument("type", choices=["image", "image_edit", "video", "talk", "music", "tts", "speakers", "transcribe"])
    r.add_argument("--authorization-profile", "--profile", dest="authorization_profile", choices=["commercial", "research"], default="commercial")
    r.add_argument("--model", default=None)
    r.add_argument("--json", default="{}")
    r.add_argument("--input", default=None)
    r.add_argument("--audio", default=None)
    r.add_argument("--ref-audio", default=None)
    r.add_argument("--out", required=True)
    r.add_argument("-v", "--verbose", action="store_true")

    rm = sub.add_parser("run-manifest", help="Run a scene manifest with SHA-256 skip-on-complete")
    rm.add_argument("manifest", help="Path to scene manifest JSON")
    rm.add_argument("--out", required=True, help="Default output directory for scenes")
    rm.add_argument("--authorization-profile", "--profile", dest="authorization_profile", choices=["commercial", "research"], default="commercial")
    rm.add_argument("-v", "--verbose", action="store_true")

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    client = MediaApiClient.connect(endpoint=args.endpoint, gateway_url=args.gateway_url, target_path=args.target)
    if args.cmd == "info":
        print(json.dumps({"endpoint_mode": client.mode, "base_url": client.base_url, **client.info()}, indent=2))
        return 0
    if args.cmd == "run":
        params = json.loads(args.json) if args.json else {}
        if args.model:
            params["model"] = args.model
        params = _attach_file_params(params, args.input, args.audio, args.ref_audio)
        out_dir = Path(args.out)
        rec = client.submit_and_pull(
            args.type,
            params,
            out_dir,
            authorization_profile=args.authorization_profile,
            verbose=args.verbose,
        )
        _write_json_atomic(out_dir / f"{rec['job']}.json", rec)
        print(json.dumps(rec, indent=2))
        return 0
    if args.cmd == "run-manifest":
        summary = run_scene_manifest(
            client,
            Path(args.manifest),
            Path(args.out),
            default_profile=args.authorization_profile,
            verbose=args.verbose,
        )
        print(json.dumps(summary, indent=2))
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
