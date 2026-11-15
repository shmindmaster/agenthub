#!/usr/bin/env python3
"""sh-forge jobs dashboard (SH-4524): read-only status of the build lanes and media jobs.

Serves HTML at / and JSON at /status.json on 127.0.0.1:8790. Caddy publishes it at
https://jobs.forge.shtrial.com, owner IP only (/opt/forge/caddy/Caddyfile). It reads
only this host: /srv/work/jobs, /srv/work/android/artifacts, the macos container,
/run/mac-leases and /proc. No writes, no external calls, no credentials.

Canonical copy: AgentHub ci/do-runner/jobs-dashboard.py.
Installed at /opt/forge/jobs-dashboard/jobs-dashboard.py, run by
forge-jobs-dashboard.service (ci/do-runner/forge-jobs-dashboard.service).

Paths are overridable by environment so tests run against fixtures:
FORGE_JOBS_DIR, FORGE_ANDROID_ARTIFACTS, FORGE_MAC_LEASES, JOBS_DASHBOARD_PORT,
FORGE_DASHBOARD_NO_DOCKER (skip docker subprocesses).
"""
from __future__ import annotations

import html
import json
import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

JOBS_DIR = os.environ.get("FORGE_JOBS_DIR", "/srv/work/jobs")
ANDROID_ARTIFACTS = os.environ.get("FORGE_ANDROID_ARTIFACTS", "/srv/work/android/artifacts")
MAC_LEASES = os.environ.get("FORGE_MAC_LEASES", "/run/mac-leases")
PORT = int(os.environ.get("JOBS_DASHBOARD_PORT", "8790"))
NO_DOCKER = os.environ.get("FORGE_DASHBOARD_NO_DOCKER", "") == "1"
CACHE_SECONDS = 15
MAX_ENTRIES = 40


def _run(cmd: list[str], timeout: float = 10.0) -> str | None:
    if NO_DOCKER:
        return None
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip() if out.returncode == 0 else None
    except Exception:
        return None


def fmt_bytes(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def fmt_age(ts: float, now: float) -> str:
    secs = max(0, int(now - ts))
    if secs < 60:
        return f"{secs}s ago"
    if secs < 3600:
        return f"{secs // 60}m ago"
    if secs < 86400:
        return f"{secs // 3600}h ago"
    return f"{secs // 86400}d ago"


def collect_host(now: float) -> dict:
    mem = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                key, value = line.split(":", 1)
                mem[key] = int(value.strip().split()[0])  # kB
    except Exception:
        pass
    disk = {"total_gb": 0, "used_gb": 0, "pct": 0}
    try:
        st = os.statvfs("/")
        total = st.f_blocks * st.f_frsize
        free = st.f_bfree * st.f_frsize
        disk = {
            "total_gb": round(total / 2**30, 1),
            "used_gb": round((total - free) / 2**30, 1),
            "pct": round(100 * (total - free) / total) if total else 0,
        }
    except Exception:
        pass
    try:
        load = list(os.getloadavg())
    except Exception:
        load = [0, 0, 0]
    uptime_s = 0.0
    try:
        with open("/proc/uptime") as f:
            uptime_s = float(f.read().split()[0])
    except Exception:
        pass
    return {
        "load": [round(x, 2) for x in load],
        "uptime": fmt_age(now - uptime_s, now).replace(" ago", ""),
        "mem_total_gb": round(mem.get("MemTotal", 0) / 2**20, 1),
        "mem_available_gb": round(mem.get("MemAvailable", 0) / 2**20, 1),
        "disk": disk,
    }


def collect_containers() -> list[dict] | None:
    raw = _run(["docker", "ps", "-a", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}"])
    if raw is None:
        return None
    rows = []
    for line in raw.splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            rows.append({"name": parts[0], "image": parts[1], "status": parts[2]})
    return rows


def collect_mac_lane(containers: list[dict], now: float, docker_available: bool = True) -> dict:
    found = any(c["name"] == "macos" for c in containers)
    if not docker_available:
        state = "unknown"
    elif not found:
        state = "absent"
    else:
        state = _run(["docker", "inspect", "-f", "{{.State.Status}}", "macos"]) or "unknown"
    leases = 0
    try:
        for entry in os.listdir(MAC_LEASES):
            if entry == "keep":
                leases += 1
                continue
            try:
                os.kill(int(entry), 0)
                leases += 1
            except (ValueError, OSError):
                pass
    except OSError:
        pass
    storage = _run(["du", "-sm", "/opt/macos/storage"], timeout=30)
    storage_gb = round(float(storage.split()[0]) / 1024, 1) if storage is not None and storage.split()[:1] else None
    return {"state": state, "leases": leases, "storage_gb": storage_gb, "idle_stop": "15 min after last lease (mac)"}


def collect_android_lane(containers: list[dict], now: float, docker_available: bool = True) -> dict:
    images = _run(["docker", "image", "ls", "--format", "{{.Repository}}:{{.Tag}}", "forge/android-builder:2"]) if docker_available else None
    image_built = _run(["docker", "image", "inspect", "-f", "{{.Created}}", "forge/android-builder:2"]) if images else None
    artifacts = collect_files(ANDROID_ARTIFACTS, now, suffixes=(".apk", ".aab", ".log"))
    image_state = "unknown" if images is None else ("forge/android-builder:2" if images else "missing")
    return {"image": image_state, "image_built": image_built, "artifacts": artifacts}


def collect_ci(containers: list[dict], docker_available: bool = True) -> list[dict]:
    running = [c for c in containers if c["status"].startswith("Up")]
    runners = [c for c in running if c["name"].endswith("-runner-1")]
    dbs = [c for c in running if any(c["name"].endswith(s) for s in ("-postgres-1", "-valkey-1", "-valkey-b-1"))]
    return [
        {"kind": "runners", "count": len(runners) if docker_available else None, "names": sorted(c["name"] for c in runners)},
        {"kind": "sidecars", "count": len(dbs) if docker_available else None, "names": sorted(c["name"] for c in dbs)},
    ]


def collect_dirs(path: str, now: float) -> list[dict]:
    entries = []
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    if entry.is_dir(follow_symlinks=False):
                        st = entry.stat(follow_symlinks=False)
                        entries.append({"name": entry.name, "mtime": st.st_mtime, "age": fmt_age(st.st_mtime, now)})
                except OSError:
                    continue
    except OSError:
        return []
    entries.sort(key=lambda e: e["mtime"], reverse=True)
    return entries[:MAX_ENTRIES]


def collect_files(path: str, now: float, suffixes: tuple[str, ...] = ()) -> list[dict]:
    entries = []
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    if entry.is_file(follow_symlinks=False) and (not suffixes or entry.name.endswith(suffixes)):
                        st = entry.stat(follow_symlinks=False)
                        entries.append({
                            "name": entry.name,
                            "mtime": st.st_mtime,
                            "age": fmt_age(st.st_mtime, now),
                            "size": fmt_bytes(st.st_size),
                        })
                except OSError:
                    continue
    except OSError:
        return []
    entries.sort(key=lambda e: e["mtime"], reverse=True)
    return entries[:MAX_ENTRIES]


def collect() -> dict:
    now = time.time()
    found_containers = collect_containers()
    docker_available = found_containers is not None
    containers = found_containers or []
    return {
        "generated": time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(now)),
        "docker_available": docker_available,
        "host": collect_host(now),
        "mac_lane": collect_mac_lane(containers, now, docker_available),
        "android_lane": collect_android_lane(containers, now, docker_available),
        "ci": collect_ci(containers, docker_available),
        "other_containers": ([c for c in containers if not c["name"].endswith(("-runner-1", "-postgres-1", "-valkey-1", "-valkey-b-1")) and c["name"] != "macos"] if docker_available else None),
        "media_jobs": collect_dirs(JOBS_DIR, now),
    }


CSS = """
body { font: 14px/1.45 system-ui, sans-serif; margin: 24px; background: #111418; color: #d7dce2; }
h1 { font-size: 20px; } h2 { font-size: 15px; margin-top: 28px; color: #9fb0c3; text-transform: uppercase; letter-spacing: .06em; }
table { border-collapse: collapse; width: 100%; max-width: 980px; }
td, th { text-align: left; padding: 4px 10px; border-bottom: 1px solid #232a33; }
th { color: #7d8b9c; font-weight: 600; }
.ok { color: #7ec97e; } .warn { color: #e0b34a; } .off { color: #8a93a0; }
.meta { color: #7d8b9c; } .grid { display: flex; gap: 32px; flex-wrap: wrap; }
"""


def _table(headers: list[str], rows: list[list[str]]) -> str:
    out = ["<table><tr>" + "".join(f"<th>{html.escape(h)}</th>" for h in headers) + "</tr>"]
    for row in rows:
        out.append("<tr>" + "".join(f"<td>{cell}</td>" for cell in row) + "</tr>")
    out.append("</table>")
    return "".join(out)


def render_html(data: dict) -> str:
    host = data["host"]
    mac = data["mac_lane"]
    mac_cls = "ok" if mac["state"] == "running" else "off"
    disk_cls = "warn" if host["disk"]["pct"] >= 85 else "ok"
    parts = [
        "<!doctype html><html><head><meta charset='utf-8'>",
        "<meta http-equiv='refresh' content='60'>",
        "<title>sh-forge jobs</title>", f"<style>{CSS}</style></head><body>",
        "<h1>sh-forge &mdash; jobs &amp; lanes</h1>",
        f"<p class='meta'>generated {html.escape(data['generated'])} &middot; read-only &middot; owner IP only &middot; <a href='/status.json' style='color:#9fb0c3'>json</a></p>",
        ("<p class='warn'>Docker status unavailable; container and lane states are unknown.</p>" if not data.get("docker_available", True) else ""),
        "<h2>Host</h2>",
        _table(["", ""], [
            ["load (1/5/15)", " ".join(str(x) for x in host["load"])],
            ["uptime", html.escape(host["uptime"])],
            ["memory", f"{host['mem_available_gb']} / {host['mem_total_gb']} GB available"],
            ["disk /", f"<span class='{disk_cls}'>{host['disk']['used_gb']} / {host['disk']['total_gb']} GB ({host['disk']['pct']}%)</span>"],
        ]),
        "<h2>Build lanes</h2>",
        _table(["lane", "state", "detail"], [
            ["macOS VM (<code>mac</code>)", f"<span class='{mac_cls}'>{html.escape(mac['state'])}</span>",
             f"leases: {mac['leases']} &middot; storage: {mac['storage_gb'] if mac['storage_gb'] is not None else '?'} GB &middot; {html.escape(mac['idle_stop'])}"],
            ["Android builder", html.escape(data["android_lane"]["image"]),
             f"built: {html.escape(data['android_lane']['image_built'] or 'never')[:19]}"],
        ]),
        "<h2>CI lane (sh-ci)</h2>",
    ]
    for group in data["ci"]:
        count = group["count"]
        count_text = str(count) if count is not None else "unknown"
        names_text = ", ".join(group["names"]) or ("unknown" if count is None else "none")
        parts.append(_table([group["kind"], "names"], [[count_text, html.escape(names_text)]]))
    parts.append("<h2>Android artifacts</h2>")
    arts = data["android_lane"]["artifacts"]
    if arts:
        parts.append(_table(["artifact", "size", "modified"], [
            [html.escape(a["name"]), a["size"], a["age"]] for a in arts]))
    else:
        parts.append("<p class='meta'>none yet</p>")
    parts.append("<h2>Media &amp; render jobs (/srv/work/jobs)</h2>")
    jobs = data["media_jobs"]
    if jobs:
        parts.append(_table(["job", "modified"], [[html.escape(j["name"]), j["age"]] for j in jobs]))
    else:
        parts.append("<p class='meta'>none</p>")
    if data["other_containers"]:
        parts.append("<h2>Other containers</h2>")
        parts.append(_table(["name", "image", "status"], [
            [html.escape(c["name"]), html.escape(c["image"]), html.escape(c["status"])] for c in data["other_containers"]]))
    parts.append("</body></html>")
    return "".join(parts)


class Handler(BaseHTTPRequestHandler):
    cache: tuple[float, dict] = (0.0, {})

    def _data(self) -> dict:
        now = time.time()
        if now - self.cache[0] > CACHE_SECONDS or not self.cache[1]:
            Handler.cache = (now, collect())
        return self.cache[1]

    def _send(self, body: str, ctype: str, code: int = 200) -> None:
        raw = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            self._send(render_html(self._data()), "text/html; charset=utf-8")
        elif path == "/status.json":
            self._send(json.dumps(self._data(), indent=1), "application/json")
        elif path == "/healthz":
            self._send("ok\n", "text/plain")
        else:
            self._send("not found\n", "text/plain", 404)

    def log_message(self, fmt, *args) -> None:  # quieter journal
        pass


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"jobs-dashboard listening on 127.0.0.1:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
