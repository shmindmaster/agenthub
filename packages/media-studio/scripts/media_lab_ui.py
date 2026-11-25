#!/usr/bin/env python3
"""Local screen for the self-hosted AI Media Lab (stdlib only; one HTML file beside it).

Binds 127.0.0.1 only. A random per-run token arrives once in the launch URL and becomes an HttpOnly SameSite=Strict
cookie; every other request needs it, a loopback Host and (for POST) a same-origin Origin. The inference key stays in
this process (HTTP, retry, SHA-256 and safe-name checks are daytona_media_client's) and is masked out of every response.
Box control runs the installed gpu.py windowless, for the `media` role only. Exits after --idle-minutes with no browser
request and no running job. No scheduled task, Run key or service: only the Start Menu shortcut the owner asks for.
"""
from __future__ import annotations

import argparse, base64, collections, hmac, json, math, os, re, secrets, shutil, socket, subprocess, sys, threading, time, traceback, webbrowser
from datetime import datetime, timezone
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

import daytona_media_client as mc

HERE = Path(__file__).resolve().parent
DEFAULT_PORT, IDLE_MINUTES = 8791, 30
GPU_PY = Path.home() / ".config" / "opencode" / "daytona" / "gpu.py"
# Spot price of one MI355X box in USD per hour, read 2026-11-25. catalog.json carries no price; set
# policy.approxHourlyUsd in the installed catalog.json to override this when the rate changes.
APPROX_USD_PER_HOUR = 3.56
TTL_MIN, EXTEND_MIN, MAX_TTL_MIN, BOOT_MIN, MAX_BODY = 120, 60, 480, 10, 300 << 20
NOWIN = getattr(subprocess, "CREATE_NO_WINDOW", 0)
SHORTCUT = Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "AI Media Lab.lnk"
PROFILES = ("commercial", "research")
KINDS = {".png": "image", ".jpg": "image", ".jpeg": "image", ".webp": "image", ".mp4": "video", ".webm": "video",
         ".wav": "audio", ".mp3": "audio", ".flac": "audio", ".ogg": "audio", ".json": "text", ".txt": "text"}
TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".mp4": "video/mp4",
         ".webm": "video/webm", ".wav": "audio/wav", ".mp3": "audio/mpeg", ".flac": "audio/flac", ".ogg": "audio/ogg",
         ".json": "application/json", ".txt": "text/plain; charset=utf-8"}
FILE_PARAMS = {"input": ("input_b64", "input_name"), "audio": ("audio_b64", "audio_name"), "ref_audio": ("ref_audio_b64", "ref_audio_name")}


def F(k, label, kind="text", d="", **x):
    return {"k": k, "label": label, "kind": kind, "def": d, **x}


SIZE = lambda w, h: [F("width", "Width", "int", w), F("height", "Height", "int", h)]
SPECS = {
    "image": [F("prompt", "Prompt", "area", req=1), F("negative", "Negative"), *SIZE(1024, 1024), F("steps", "Steps", "int"), F("seed", "Seed", "int")],
    "image_edit": [F("prompt", "Edit", "area", req=1), F("input", "Image", "file", accept="image/*", req=1), F("steps", "Steps", "int"), F("seed", "Seed", "int")],
    "video": [F("prompt", "Prompt", "area", req=1), F("input", "Start image", "file", accept="image/*", req=1), *SIZE(640, 640),
              F("frames", "Frames", "int", 81), F("steps", "Steps", "int"), F("seed", "Seed", "int"),
              F("quality", "Quality", "select", "draft", opts=["draft", "standard"], research=1)],
    "talk": [F("prompt", "Prompt", "area", "a person speaking to the camera", req=1), F("input", "Portrait", "file", accept="image/*", req=1),
             F("audio", "Speech", "file", accept="audio/*", req=1), F("subject", "Subject", "select", "synthetic", opts=["synthetic", "consented"]),
             *SIZE(512, 512), F("seed", "Seed", "int")],
    "tts": [F("text", "Text", "area", req=1), F("speaker", "Speaker", "text", "ryan"), F("language", "Language", "text", "English"),
            F("instruct", "Style"), F("ref_audio", "Reference voice", "file", accept="audio/*", research=1),
            F("subject", "Subject", "select", "synthetic", opts=["synthetic", "consented"], research=1)],
    "transcribe": [F("input", "Audio", "file", accept="audio/*", req=1), F("language", "Language", "text", "English")],
    "music": [F("tags", "Tags", "area", req=1), F("lyrics", "Lyrics", "area"), F("seconds", "Seconds", "int", 30),
              F("bpm", "BPM", "int", 100), F("seed", "Seed", "int")],
}


class Refuse(Exception):
    def __init__(self, msg, code=409):
        super().__init__(msg)
        self.code = code


def parse_status(text: str) -> dict:
    """Read `gpu.py status`: `gpu_instances N/M` then one `<id> <name> <state> gpu=.. spot=.. destroy_at=..` row per box."""
    m = re.search(r"gpu_instances (\d+)/(\d+)", text)
    if not m:
        return {"ok": False, "error": "gpu.py status printed no gpu_instances line"}
    rows = re.findall(r"^\s+(\S+) (\S+) (\S+) gpu=(\S+) spot=\S+ destroy_at=(.*)$", text, re.M)
    return {"ok": True, "n": int(m[1]), "max": int(m[2]), "boxes": [dict(id=r[0], name=r[1], state=r[2], gpu=r[3], destroy_at=r[4].strip()) for r in rows]}


def minutes_left(stamp: str):
    try:
        when = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return None
    when = when if when.tzinfo else when.replace(tzinfo=timezone.utc)
    return max(0, math.ceil((when - datetime.now(timezone.utc)).total_seconds() / 60))


class Lab:
    def __init__(self, a):
        self.token, self.port = secrets.token_urlsafe(32), a.port
        self.out_root, self.gpu, self.poll_s = Path(a.out), Path(a.gpu_py), a.poll
        self.lock, self.last, self.stop = threading.RLock(), time.monotonic(), threading.Event()
        self.jobs, self.log, self.runner, self.status = {}, collections.deque(maxlen=40), None, None
        self.info, self.info_err, self.was_ready, self.status_at, self.opener = None, "", False, 0.0, getattr(os, "startfile", None)
        cat = {}
        try:
            cat = json.loads((self.gpu.parent / "catalog.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
        self.sandbox = cat.get("roles", {}).get("media", {}).get("sandboxName", "agenthub-media")
        self.usd = float(cat.get("policy", {}).get("approxHourlyUsd", APPROX_USD_PER_HOUR))
        try:
            self.client, self.client_err = mc.MediaApiClient.from_gateway(a.gateway_url), ""
        except Exception as exc:
            self.client, self.client_err = None, str(exc)
        named = [v for k, v in os.environ.items() if re.search(r"KEY|TOKEN|SECRET", k, re.I) and len(v) >= 8]
        self.secrets = sorted({*named, *([self.client.bearer_token] if self.client else [])}, key=len, reverse=True)
        self.load_history()

    def mask(self, text, bearer=True) -> str:
        text = str(text)
        for s in self.secrets:
            text = text.replace(s, "****" + s[-4:])
        return re.sub(r"(?i)(bearer\s+)[^\s\"',]+", r"\1****", text) if bearer else text

    def touch(self):
        self.last = time.monotonic()

    def active(self) -> bool:
        with self.lock:
            return any(j["state"] in ("queued", "running") for j in self.jobs.values()) or bool(self.runner and self.runner["running"])

    # ---- box --------------------------------------------------------------------------------------------------
    def refresh(self, gpu=True):
        try:
            if not self.client:
                raise RuntimeError(self.client_err)
            self.info, self.info_err, self.was_ready = self.client.info(timeout=8), "", True
        except Exception as exc:
            self.info, self.info_err = None, self.mask(exc)[:300]
        if gpu:
            self.status, self.status_at = self.read_status(), time.monotonic()

    def exec_logged(self, argv, capture=None) -> int:
        """Run argv windowless (never a shell); masked output lines go to the log, or into `capture` when given."""
        with subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, text=True, encoding="utf-8",
                              errors="replace", creationflags=NOWIN, env={**os.environ, "PYTHONIOENCODING": "utf-8"}) as proc:
            for line in proc.stdout:
                (self.log if capture is None else capture).append(self.mask(line.rstrip()))
            return proc.wait()

    def gpu_argv(self, *args):
        exe = Path(sys.executable)
        py = exe.with_name("python.exe") if exe.name.lower() == "pythonw.exe" and exe.with_name("python.exe").is_file() else exe
        return [str(py), str(self.gpu), *args]

    def read_status(self) -> dict:
        out = []
        try:
            rc = self.exec_logged(self.gpu_argv("status"), out)
        except OSError as exc:
            return {"ok": False, "error": self.mask(exc)}
        st = parse_status(os.linesep.join(out))
        if not st["ok"] and rc:
            st["error"] = f"gpu.py status exited {rc}: " + (out[-1] if out else "no output")
        return st

    def media_box(self):
        return next((b for b in (self.status or {}).get("boxes", []) if b["name"] == self.sandbox), None)

    def box(self) -> dict:
        r, mb, st = self.runner, self.media_box(), self.status or {}
        busy = r["name"] if r and r["running"] else ""
        if busy == "start":
            state = "starting"
        elif self.info:
            state = "ready"
        elif self.status is None and not self.info_err:
            state = "checking"
        elif mb:
            state = "lost" if self.was_ready else "starting"
        else:
            state = "lost" if self.was_ready else "off"
        return {"state": state, "busy": busy, "left_min": minutes_left(mb["destroy_at"]) if mb else None, "usd_per_hour": self.usd,
                "ttl": TTL_MIN, "extend": EXTEND_MIN, "boot_min": BOOT_MIN, "n": st.get("n"), "max": st.get("max"),
                "queue": (self.info or {}).get("queue"), "error": st.get("error") or (self.info_err if state == "lost" else ""),
                "result": r["result"] if r and not r["running"] else "", "log": list(self.log)[-12:]}

    def run_steps(self, name, steps):
        with self.lock:
            if self.runner and self.runner["running"]:
                raise Refuse(f"{self.runner['name']} is still running")
            self.runner, self.log = {"name": name, "running": True, "result": ""}, collections.deque(maxlen=40)

        def work():
            ok = False
            try:
                for argv in steps:
                    self.log.append("$ gpu.py " + " ".join(argv))
                    rc = self.exec_logged(self.gpu_argv(*argv))
                    if rc:
                        self.log.append(f"exit code {rc}")
                        break
                else:
                    ok = True
                if name == "stop" and ok:
                    self.was_ready = False
                self.runner.update(result="ok" if ok else "failed")
                self.refresh()
            except Exception as exc:
                self.log.append(self.mask(f"{type(exc).__name__}: {exc}"))
                self.runner.update(result="failed")
            finally:
                self.runner["running"] = False
        threading.Thread(target=work, daemon=True).start()

    def control(self, action):
        if action == "start":
            st = self.read_status()
            if not st["ok"]:
                raise Refuse("cannot check the GPU limit: " + st["error"])
            self.status = st
            if self.media_box():
                raise Refuse(f"{self.sandbox} already exists ({self.media_box()['state']})")
            if st["n"] >= st["max"]:
                running = ", ".join(f"{b['name']} ({b['gpu']})" for b in st["boxes"])
                raise Refuse(f"GPU limit reached, {st['n']}/{st['max']} running: {running}. Stop one first.")
            self.run_steps("start", [["up", "media", "--gpu", "MI355X", "--ttl", str(TTL_MIN)], ["caddy-media"]])
        elif action == "extend":
            self.status = self.read_status()
            mb = self.media_box()
            left = minutes_left(mb["destroy_at"]) if mb else None
            if left is None:
                raise Refuse("no running media box with a known time left")
            self.run_steps("extend", [["extend", "media", str(min(MAX_TTL_MIN, left + EXTEND_MIN))]])
        elif action == "stop":
            self.run_steps("stop", [["down", "media"]])
        else:
            raise Refuse("unknown action", 404)

    # ---- modes and jobs ---------------------------------------------------------------------------------------
    def modes(self) -> dict:
        reg = (self.info or {}).get("models") or {}
        gone = set((self.info or {}).get("missing_weights") or {})
        out = {}
        for mode in SPECS:
            out[mode] = {}
            for prof in PROFILES:
                default = (reg.get("authorizationProfiles", {}).get(prof, {}).get("defaults") or {}).get(mode)
                ids = [m["id"] for m in reg.get("installed", []) if mode in m.get("jobs", []) and m["id"] not in gone and (prof == "research" or m.get("commercial"))]
                out[mode][prof] = {"default": default if default in ids else None, "models": sorted(ids, key=lambda i: i != default) if default in ids else []}
        return out

    def find_output(self, job, name) -> Path:
        try:
            job, name = mc._safe_name(job, "job"), mc._safe_name(name, "file")
        except RuntimeError as exc:
            raise Refuse(str(exc), 400)
        for p in self.out_root.glob(f"????-??-??/{job}/{name}"):
            if p.is_file() and p.resolve().is_relative_to(self.out_root.resolve()):
                return p
        raise Refuse("no such output", 404)

    def build_params(self, mode, profile, body):
        spec, vals, ins, params, blobs = SPECS[mode], body.get("params") or {}, body.get("inputs") or {}, {}, {}
        for f in spec:
            if f.get("research") and profile != "research":
                continue
            k, v = f["k"], vals.get(f["k"])
            if f["kind"] == "file":
                ref = ins.get(k)
                if not ref:
                    if f.get("req"):
                        raise Refuse(f"{f['label']} is required", 400)
                    continue
                if "job" in ref:
                    p = self.find_output(ref.get("job"), ref.get("name"))
                    name, data = p.name, p.read_bytes()
                else:
                    name = re.sub(r"[^A-Za-z0-9._-]", "_", Path(str(ref.get("name", "input"))).name)[:80] or "input"
                    try:
                        data = base64.b64decode(str(ref.get("b64", "")), validate=True)
                    except ValueError:
                        raise Refuse(f"{f['label']} is not valid base64", 400)
                if not data:
                    raise Refuse(f"{f['label']} is empty", 400)
                params[FILE_PARAMS[k][0]], params[FILE_PARAMS[k][1]] = base64.b64encode(data).decode("ascii"), name
                blobs[k] = {"name": name, "sha256": mc._sha256_bytes(data)}
            elif v in (None, ""):
                if f.get("req"):
                    raise Refuse(f"{f['label']} is required", 400)
            elif f["kind"] == "select" and v not in f["opts"]:
                raise Refuse(f"{f['label']} must be one of {', '.join(f['opts'])}", 400)
            else:
                try:
                    params[k] = int(v) if f["kind"] == "int" else str(v).strip()
                except ValueError:
                    raise Refuse(f"{f['label']} must be a whole number", 400)
        if mode == "tts" and "ref_audio_b64" not in params:
            params.pop("subject", None)
        return params, blobs

    def submit(self, body) -> str:
        mode, profile = body.get("mode"), body.get("profile", "commercial")
        if mode not in SPECS or profile not in PROFILES:
            raise Refuse("unknown mode or profile", 400)
        if not self.client or not self.info:
            raise Refuse("the box is not ready")
        choice = self.modes()[mode][profile]
        if not choice["default"]:
            raise Refuse(f"no {profile} model for {mode}")
        params, blobs = self.build_params(mode, profile, body)
        model = str(body.get("model") or choice["default"])
        if model not in choice["models"]:
            raise Refuse(f"{model} is not available for {mode} under {profile}", 400)
        params["model"] = model
        job = {"id": secrets.token_hex(4), "mode": mode, "profile": profile, "model": model, "state": "queued", "created": time.time(), "started": None,
               "ended": None, "progress": "", "error": "", "outputs": [], "dir": "", "prompt": str(params.get("prompt") or params.get("text") or params.get("tags") or "")}
        with self.lock:
            self.jobs[job["id"]] = job
        threading.Thread(target=self.run_job, args=(job, params, blobs), daemon=True).start()
        return job["id"]

    def run_job(self, job, params, blobs):
        try:
            remote = self.client.request("POST", "/v1/jobs", {"type": job["mode"], "authorization_profile": job["profile"], "params": params})
            jid = mc._safe_name(remote["id"], "job id")
            job.update(dir=jid, state="running", started=time.time())
            while remote["state"] not in ("done", "error"):
                if time.time() - job["started"] > mc.MAX_JOB_SECONDS:
                    raise RuntimeError(f"still {remote['state']} after {mc.MAX_JOB_SECONDS}s; left on the box")
                time.sleep(self.poll_s)
                remote = self.client.request("GET", f"/v1/jobs/{jid}")
                job["progress"] = str(remote.get("progress") or "")
            if remote["state"] == "error":
                raise RuntimeError(remote.get("error") or "unknown error")
            out_dir = self.out_root / time.strftime("%Y-%m-%d") / jid
            files = mc.pull_verified_outputs(self.client, remote, out_dir)
            self.client.request("DELETE", f"/v1/jobs/{jid}")
            shown = {k: v for k, v in params.items() if not k.endswith("_b64")}
            meta = {"job": jid, "mode": job["mode"], "profile": job["profile"], "model": remote.get("model") or job["model"], "prompt": job["prompt"],
                    "params": shown, "inputs": blobs, "seconds": remote.get("seconds"), "files": [{k: f[k] for k in ("name", "size", "sha256")} for f in files]}
            mc._write_json_atomic(out_dir / f"{jid}.json", meta)
            job.update(outputs=meta["files"], model=meta["model"], state="done")
        except Exception as exc:
            job.update(state="error", error=self.mask(exc)[:600])
        job["ended"] = time.time()

    def load_history(self):
        for meta in sorted(self.out_root.glob("????-??-??/*/*.json"), key=lambda p: p.stat().st_mtime if p.exists() else 0)[-30:]:
            try:
                m = json.loads(meta.read_text(encoding="utf-8"))
                if m["job"] == meta.stem and m["mode"] in SPECS:
                    t = meta.stat().st_mtime
                    self.jobs[m["job"]] = {"id": m["job"], "mode": m["mode"], "profile": m.get("profile", ""), "model": m.get("model", ""), "state": "done", "created": t,
                                           "started": t - float(m.get("seconds") or 0), "ended": t, "progress": "", "error": "", "outputs": m["files"], "dir": m["job"], "prompt": m.get("prompt", "")}
            except (OSError, ValueError, KeyError):
                continue

    def state(self) -> dict:
        with self.lock:
            jobs = [{**j, "outputs": [{**o, "kind": KINDS.get(Path(o["name"]).suffix.lower(), "file")} for o in j["outputs"]]} for j in sorted(self.jobs.values(), key=lambda j: -j["created"])]
        return {"box": self.box(), "modes": self.modes(), "specs": SPECS, "jobs": jobs, "gateway_error": self.client_err}


class Handler(BaseHTTPRequestHandler):
    server_version = "MediaLab"
    lab: Lab

    def log_message(self, *_):  # the launch URL carries the token; nothing is logged
        pass

    def reply(self, code, body: bytes, ctype="application/json", extra=()):
        self.send_response(code)
        for k, v in (("Content-Type", ctype), ("Content-Length", str(len(body))), ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff"),
                     ("X-Frame-Options", "DENY"), ("Content-Security-Policy", "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; media-src 'self'; connect-src 'self'; frame-ancestors 'none'"), *extra):
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, code, obj):
        self.reply(code, self.lab.mask(json.dumps(obj), bearer=False).encode("utf-8"))

    def deny(self, code, msg):
        self.send_json(code, {"error": msg})

    def route(self, method):
        lab, url = self.lab, urlparse(self.path)
        origin = self.headers.get("Origin")
        if self.headers.get("Host") not in (f"127.0.0.1:{lab.port}", f"localhost:{lab.port}"):
            return self.deny(403, "bad host")
        if (origin and origin not in (f"http://127.0.0.1:{lab.port}", f"http://localhost:{lab.port}")) or (method == "POST" and not origin):
            return self.deny(403, "bad origin")
        if method == "GET" and url.path == "/" and "t" in parse_qs(url.query):
            if not hmac.compare_digest(parse_qs(url.query)["t"][0].encode("utf-8", "replace"), lab.token.encode()):
                return self.deny(403, "bad token")
            return self.reply(302, b"", "text/plain", (("Location", "/"), ("Set-Cookie", f"medialab={lab.token}; Path=/; HttpOnly; SameSite=Strict")))
        jar = cookies.SimpleCookie(self.headers.get("Cookie", ""))
        if "medialab" not in jar or not hmac.compare_digest(jar["medialab"].value.encode("utf-8", "replace"), lab.token.encode()):
            return self.deny(403, "open the launch link")
        lab.touch()
        try:
            parts = [unquote(p) for p in url.path.strip("/").split("/")]
            if method == "GET" and url.path == "/":
                return self.reply(200, (HERE / "media_lab_ui.html").read_bytes(), "text/html; charset=utf-8")
            if method == "GET" and parts == ["api", "state"]:
                return self.send_json(200, lab.state())
            if method == "GET" and len(parts) == 4 and parts[:2] == ["api", "files"]:
                return self.send_file(lab.find_output(parts[2], parts[3]), "dl" in parse_qs(url.query))
            body = {}
            if method == "POST":
                size = int(self.headers.get("Content-Length") or 0)
                if size > MAX_BODY:
                    raise Refuse("request too large", 413)
                try:
                    body = json.loads(self.rfile.read(size) or b"{}")
                except ValueError:
                    raise Refuse("body is not JSON", 400)
            if method == "POST" and parts == ["api", "jobs"]:
                return self.send_json(201, {"id": lab.submit(body)})
            if method == "POST" and len(parts) == 3 and parts[:2] == ["api", "box"]:
                if parts[2] in ("start", "stop") and body.get("confirm") is not True:
                    raise Refuse("confirmation required", 400)
                return self.send_json(202, lab.control(parts[2]) or {"ok": True})
            if method == "POST" and parts == ["api", "open"]:
                folder = lab.find_output(body.get("job"), body.get("name")).parent
                if not lab.opener:
                    raise Refuse("cannot open a folder on this system")
                lab.opener(str(folder))
                return self.send_json(200, {"opened": folder.name})
            self.deny(404, "not found")
        except Refuse as exc:
            self.deny(exc.code, str(exc))
        except Exception as exc:
            self.deny(500, lab.mask(f"{type(exc).__name__}: {exc}"))

    def send_file(self, path: Path, download: bool):
        size, start, end, code = path.stat().st_size, 0, path.stat().st_size - 1, 200
        m = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if m and (m[1] or m[2]):
            start, end, code = (int(m[1]), min(int(m[2] or end), end), 206) if m[1] else (max(0, size - int(m[2])), end, 206)
        if start > end:
            return self.reply(416, b"", "text/plain", (("Content-Range", f"bytes */{size}"),))
        with path.open("rb") as fh:
            fh.seek(start)
            data = fh.read(end - start + 1)
        extra = [("Accept-Ranges", "bytes")] + ([("Content-Range", f"bytes {start}-{end}/{size}")] if code == 206 else []) + ([("Content-Disposition", f'attachment; filename="{path.name}"')] if download else [])
        self.reply(code, data, TYPES.get(path.suffix.lower(), "application/octet-stream"), extra)

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")


class Server(ThreadingHTTPServer):
    """No shared port: SO_REUSEADDR would let a second process bind the same Windows port beside this one."""
    allow_reuse_address = False

    def server_bind(self):
        if os.name == "nt":
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def make_server(a):
    lab = Lab(a)
    handler = type("BoundHandler", (Handler,), {"lab": lab})
    httpd = Server(("127.0.0.1", a.port), handler)
    httpd.daemon_threads, httpd.lab = True, lab
    lab.port = httpd.server_address[1]
    return httpd, lab


def start_threads(httpd, lab, idle_s):
    def poll():
        lab.refresh()
        while not lab.stop.wait(lab.poll_s * 3):
            if time.monotonic() - lab.last < 90 and not (lab.runner and lab.runner["running"]):
                lab.refresh(gpu=time.monotonic() - lab.status_at > 60)

    def idle():
        while not lab.stop.wait(min(5, max(idle_s / 4, 0.05))):
            if time.monotonic() - lab.last > idle_s and not lab.active():
                httpd.shutdown()
                return
    for fn in (poll, idle):
        threading.Thread(target=fn, daemon=True).start()


def install_shortcut(install: bool):
    if not install:
        SHORTCUT.unlink(missing_ok=True)
        return f"removed {SHORTCUT}"
    exe = Path(sys.executable).with_name("pythonw.exe")
    exe = exe if exe.is_file() else Path(shutil.which("pythonw") or "")
    if not exe.is_file():
        raise SystemExit("pythonw.exe not found")
    ps = ("$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:ML_LNK);$s.TargetPath=$env:ML_EXE;$s.Arguments=$env:ML_ARGS;"
          "$s.WorkingDirectory=$env:ML_DIR;$s.Description='AI Media Lab';$s.Save()")
    env = {**os.environ, "ML_LNK": str(SHORTCUT), "ML_EXE": str(exe), "ML_ARGS": f'"{Path(__file__).resolve()}" --open', "ML_DIR": str(HERE)}
    SHORTCUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", ps], env=env, creationflags=NOWIN, check=True, capture_output=True)
    return f"created {SHORTCUT}"


def main(argv=None) -> int:
    root = Path(os.environ.get("MEDIA_STUDIO_ROOT") or r"D:\Media-Studio")
    p = argparse.ArgumentParser(description="Local screen for the self-hosted AI Media Lab")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--gateway-url", default=None)
    p.add_argument("--out", default=str(root / "gpu-gen" / "out"))
    p.add_argument("--gpu-py", default=str(GPU_PY))
    p.add_argument("--idle-minutes", type=float, default=IDLE_MINUTES)
    p.add_argument("--poll", type=float, default=3.0, help="seconds between job polls")
    p.add_argument("--state-dir", default=str(Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".config") / "AgentHub" / "media-lab-ui"))
    p.add_argument("--open", action="store_true", help="open the default browser at the launch URL")
    p.add_argument("--install-shortcut", action="store_true")
    p.add_argument("--remove-shortcut", action="store_true")
    a = p.parse_args(argv)
    say = (lambda s: print(s, flush=True)) if sys.stdout else (lambda s: None)
    if a.install_shortcut or a.remove_shortcut:
        say(install_shortcut(a.install_shortcut))
        return 0
    state = Path(a.state_dir) / "session.json"
    try:
        httpd, lab = make_server(a)
    except OSError as exc:  # port taken: another copy is serving, so open its page instead of starting a second one
        try:
            live = json.loads(state.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            live = None
        if live and live.get("port") == a.port:
            url = f"http://127.0.0.1:{a.port}/?t={live['token']}"
            if a.open:
                webbrowser.open(url)
            say(f"already running: {url}")
            return 0
        msg = f"cannot bind 127.0.0.1:{a.port}: {exc}"
        say(msg)
        if a.open and os.name == "nt" and not sys.stdout:  # started from the shortcut: no console to print to
            import ctypes
            ctypes.windll.user32.MessageBoxW(None, f"{msg}\nAnother program is using this port.", "AI Media Lab", 0x30)
        return 1
    url = f"http://127.0.0.1:{lab.port}/?t={lab.token}"
    state.parent.mkdir(parents=True, exist_ok=True)
    mc._write_json_atomic(state, {"port": lab.port, "token": lab.token, "pid": os.getpid()})
    start_threads(httpd, lab, a.idle_minutes * 60)
    say(f"AI Media Lab: {url}")
    if a.open:
        webbrowser.open(url)
    try:
        httpd.serve_forever()
    finally:
        lab.stop.set()
        state.unlink(missing_ok=True)
        httpd.server_close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        log = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "AgentHub" / "media-lab-ui"
        log.mkdir(parents=True, exist_ok=True)
        (log / "error.log").write_text(traceback.format_exc(), encoding="utf-8")
        raise
