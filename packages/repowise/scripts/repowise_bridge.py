"""Stdio bridge from one host session to the one shared RepoWise MCP server.

Why this exists (2026-10-14): hosts used to carry a bare HTTP entry for
http://127.0.0.1:7339/mcp. When the shared server died with the rest of the
local stack, every host got ECONNREFUSED and nothing on the RepoWise path could
bring it back -- the no-autostart policy forbids a logon or scheduled job, and an
HTTP entry cannot start anything. This bridge is the capability-invoked start:
the host spawns it only because the repowise plugin is enabled, and the bridge
starts the shared server (through Start-RepoWiseShared.ps1, hidden, fail-closed
on the embedder) only when it finds the port down.

It is a thin client, not a second server. The heavy process stays single and
shared; each host session holds one small stdlib-only Python process that
forwards JSON-RPC lines to the streamable-HTTP endpoint and back.

Behaviour:
  * initialize / tools/list / prompts/list / resources/list are answered live
    when the server is up and cached on disk. If the server is down and does
    not come up within the handshake wait, the cached answer is returned so the
    host still registers the tools instead of timing out; the server keeps
    starting in the background.
  * Every other request waits (up to the call wait) for the server, starting it
    if needed, and re-establishes the upstream session transparently when the
    server restarts mid-session (connection refused or 404 on the session).
  * If the launcher exits non-zero (it fails closed when the embedder is not
    ready, rather than serving mock vectors), pending requests get a JSON-RPC
    error naming the launcher log instead of hanging.

Remote mode (2026-10-28): with AGENTHUB_REPOWISE_MODE=remote the bridge
forwards to a hosted RepoWise endpoint instead of the local shared server. The
URL comes from AGENTHUB_REPOWISE_REMOTE_URL (https, or loopback for tests) and
the bearer token from the environment variable named by
AGENTHUB_REPOWISE_REMOTE_TOKEN_ENV (default REPOWISE_REMOTE_TOKEN). In remote
mode the local launcher never runs and there is no silent fallback to the local
server: an unreachable or misconfigured remote is reported as an error. The
handshake cache is kept per mode. Local mode stays the default; the private
overlay owns the switch, the URL and the token.

Stdlib only. Never writes anything but protocol messages to stdout; diagnostics
go to bridge.log under the shared runtime directory and never contain message
bodies or credentials.
"""

from __future__ import annotations

import http.client
import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable

DEFAULT_URL = "http://127.0.0.1:7339/mcp"
MODE_ENV = "AGENTHUB_REPOWISE_MODE"
REMOTE_URL_ENV = "AGENTHUB_REPOWISE_REMOTE_URL"
REMOTE_TOKEN_ENV_ENV = "AGENTHUB_REPOWISE_REMOTE_TOKEN_ENV"
DEFAULT_REMOTE_TOKEN_ENV = "REPOWISE_REMOTE_TOKEN"
CACHED_METHODS = ("initialize", "tools/list", "prompts/list", "resources/list")
# Requests with possible side effects (RepoWise has write tools such as
# update_decision_records): never resent after the connection dropped mid-call.
NOT_RESENT_METHODS = ("tools/call",)
INTERNAL_ID_PREFIX = "repowise-bridge-"

# Windows process creation flags. CREATE_NO_WINDOW gives the launcher a console
# with no window, so powershell.exe and everything it starts stay invisible.
# CREATE_BREAKAWAY_FROM_JOB lets the shared server outlive the host session
# that happened to start it; it is refused when the host's job forbids
# breakaway, and the spawn is then retried without it.
CREATE_NEW_PROCESS_GROUP = 0x00000200
CREATE_BREAKAWAY_FROM_JOB = 0x01000000
CREATE_NO_WINDOW = 0x08000000


class UpstreamDown(Exception):
    """Nothing answered at the endpoint; safe to retry, nothing was executed."""


class UpstreamLost(UpstreamDown):
    """The connection dropped after the request was sent. The server may have
    run it, so a request with side effects must not be resent."""


class SessionExpired(Exception):
    """The server no longer knows our session id (it restarted)."""

    def __init__(self, sent_session: str | None = None) -> None:
        super().__init__("session expired")
        self.sent_session = sent_session


class UpstreamSlow(Exception):
    """Connected, but no answer in time. The server is up (a cold RepoWise
    loads every workspace repo on its first session), so this must never run
    the launcher, and a request that may have executed must not be resent."""


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, ""))
    except ValueError:
        return default


def runtime_dir() -> Path:
    override = os.environ.get("REPOWISE_BRIDGE_RUNTIME")
    if override:
        return Path(override)
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "AgentHub" / "runtime" / "repowise-shared"


class UpstreamConfig:
    """Where the bridge forwards, and whether it may start a local server."""

    def __init__(self, url: str, remote: bool, authorization: str | None = None,
                 error: str | None = None) -> None:
        self.url = url
        self.remote = remote
        self.authorization = authorization
        self.error = error  # set when remote mode is requested but unusable

    @property
    def label(self) -> str:
        if not self.remote:
            return self.url
        try:
            parsed = urllib.parse.urlsplit(self.url)
            return f"remote {parsed.scheme}://{parsed.hostname}"
        except ValueError:
            return "remote (invalid url)"


def resolve_upstream(env: dict[str, str] | None = None) -> UpstreamConfig:
    env = os.environ if env is None else env
    mode = (env.get(MODE_ENV) or "local").strip().lower()
    if mode in ("", "local"):
        return UpstreamConfig(env.get("REPOWISE_BRIDGE_URL", DEFAULT_URL), remote=False)
    if mode != "remote":
        return UpstreamConfig(DEFAULT_URL, remote=True, error=f"{MODE_ENV}={mode!r} is not 'local' or 'remote'")
    url = (env.get(REMOTE_URL_ENV) or "").strip()
    if not url:
        return UpstreamConfig("", remote=True, error=f"remote mode needs {REMOTE_URL_ENV}")
    try:
        parsed = urllib.parse.urlsplit(url)
        host = parsed.hostname or ""
    except ValueError:
        return UpstreamConfig(url, remote=True, error=f"{REMOTE_URL_ENV} is not a valid URL")
    loopback = host in ("127.0.0.1", "localhost", "::1")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        return UpstreamConfig(url, remote=True, error=f"{REMOTE_URL_ENV} must not carry credentials, a query or a fragment")
    if parsed.scheme != "https" and not (parsed.scheme == "http" and loopback):
        return UpstreamConfig(url, remote=True, error=f"{REMOTE_URL_ENV} must use https")
    token_env = (env.get(REMOTE_TOKEN_ENV_ENV) or DEFAULT_REMOTE_TOKEN_ENV).strip()
    token = env.get(token_env) or ""
    if not token:
        return UpstreamConfig(url, remote=True, error=f"remote mode needs the bearer token in {token_env}")
    return UpstreamConfig(url, remote=True, authorization=f"Bearer {token}")


def default_launcher_command() -> list[str]:
    script = Path(__file__).resolve().parent / "Start-RepoWiseShared.ps1"
    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    powershell = Path(system_root) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
    return [
        str(powershell), "-NoProfile", "-NonInteractive",
        "-ExecutionPolicy", "Bypass", "-File", str(script),
    ]


def launcher_command() -> list[str]:
    override = os.environ.get("REPOWISE_BRIDGE_LAUNCHER")
    if override:
        command = json.loads(override)
        if not isinstance(command, list) or not all(isinstance(p, str) for p in command):
            raise ValueError("REPOWISE_BRIDGE_LAUNCHER must be a JSON array of strings")
        return command
    return default_launcher_command()


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes

        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        try:
            code = ctypes.c_ulong()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
                return False
            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def wait_for_launch_probe(deadline: float, log: Callable[[str], None]) -> None:
    """Block while any launcher is between starting RepoWise and confirming it
    is not on a mock embedder (launcher.state.json says "starting" and its pid
    is alive). The port is already listening in that window, so connecting is
    not proof the server is fit to answer real queries."""
    path = runtime_dir() / "launcher.state.json"
    logged = False
    while True:
        try:
            state = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return
        if not isinstance(state, dict):
            return
        try:
            pid = int(state.get("pid") or 0)
        except (TypeError, ValueError):
            pid = 0
        if state.get("state") != "starting" or not pid_alive(pid):
            return
        if not logged:
            log(f"waiting for launcher pid {state.get('pid')} to finish its embedder probe")
            logged = True
        if time.monotonic() >= deadline:
            raise TimeoutError("RepoWise shared server is still being verified by its launcher; try again shortly")
        time.sleep(0.5)


def spawn_flags(breakaway: bool) -> int:
    flags = CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
    if breakaway:
        flags |= CREATE_BREAKAWAY_FROM_JOB
    return flags


class Log:
    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = threading.Lock()

    def __call__(self, message: str) -> None:
        line = f"[{time.strftime('%Y-%m-%dT%H:%M:%S')}] bridge[{os.getpid()}] {message}\n"
        with self._lock:
            try:
                self._path.parent.mkdir(parents=True, exist_ok=True)
                with self._path.open("a", encoding="utf-8") as handle:
                    handle.write(line)
            except OSError:
                pass


class Launcher:
    """Starts Start-RepoWiseShared.ps1 at most once at a time."""

    def __init__(self, command: list[str], log: Log, enabled: bool = True) -> None:
        self._command = command
        self._log = log
        # False in remote mode: the hosted server is not ours to start.
        self.enabled = enabled
        self._lock = threading.Lock()
        self._process: subprocess.Popen | None = None
        self.last_exit: int | None = None
        self._finished_at: float | None = None
        # A fail-closed exit is reported for this long, then a later request
        # may launch again (the embedder may have come up meanwhile).
        self.failure_cooldown = _env_float("REPOWISE_BRIDGE_RELAUNCH_COOLDOWN", 30.0)
        # Never respawn more often than this, even after a clean exit that
        # still left the port down.
        self.min_interval = _env_float("REPOWISE_BRIDGE_RELAUNCH_INTERVAL", 10.0)

    def running(self) -> bool:
        with self._lock:
            return self._poll_locked()

    def _poll_locked(self) -> bool:
        if self._process is None:
            return False
        code = self._process.poll()
        if code is None:
            return True
        self.last_exit = code
        self._finished_at = time.monotonic()
        self._log(f"launcher pid {self._process.pid} exited {code}")
        self._process = None
        return False

    def failed(self) -> bool:
        """The last launch finished non-zero recently and nothing is running."""
        with self._lock:
            if self._poll_locked() or self.last_exit in (None, 0) or self._finished_at is None:
                return False
            return time.monotonic() - self._finished_at < self.failure_cooldown

    def may_start(self) -> bool:
        if not self.enabled:
            return False
        with self._lock:
            if self._poll_locked():
                return False
            return self._finished_at is None or time.monotonic() - self._finished_at >= self.min_interval

    def start(self) -> None:
        if not self.enabled:
            return
        with self._lock:
            if self._poll_locked():
                return
            self.last_exit = None
            kwargs: dict[str, Any] = {
                "stdin": subprocess.DEVNULL,
                "stdout": subprocess.DEVNULL,
                "stderr": subprocess.DEVNULL,
                "close_fds": True,
            }
            if os.name == "nt":
                try:
                    self._process = subprocess.Popen(
                        self._command, creationflags=spawn_flags(True), **kwargs
                    )
                except OSError:
                    self._process = subprocess.Popen(
                        self._command, creationflags=spawn_flags(False), **kwargs
                    )
            else:
                self._process = subprocess.Popen(self._command, start_new_session=True, **kwargs)
            self._log(f"started launcher pid {self._process.pid}")


class Upstream:
    def __init__(self, url: str, deliver: Callable[[dict], None], launcher: Launcher, log: Log,
                 config: UpstreamConfig | None = None) -> None:
        self.url = url
        self.config = config or UpstreamConfig(url, remote=False)
        self._deliver = deliver
        self._launcher = launcher
        self._log = log
        self._session_lock = threading.Lock()
        self.session_id: str | None = None
        self.protocol: str | None = None
        self.init_params: dict | None = None
        self._internal = 0
        self._slow = False

    # ----------------------------------------------------------- transport
    def _headers(self) -> dict[str, str]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.config.authorization:
            headers["Authorization"] = self.config.authorization
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        if self.protocol:
            headers["MCP-Protocol-Version"] = self.protocol
        return headers

    def _execute_post(
        self, request: urllib.request.Request, timeout: float, sent_session: str | None
    ) -> Any:
        try:
            return urllib.request.urlopen(request, timeout=max(timeout, 1.0))
        except urllib.error.HTTPError as exc:
            if exc.code == 404 and sent_session:
                raise SessionExpired(sent_session) from exc
            if exc.code in (502, 503, 504):
                raise UpstreamDown(f"http {exc.code}") from exc
            if exc.code in (401, 403) and self.config.remote:
                raise RuntimeError(f"remote RepoWise refused the bearer token (http {exc.code}); "
                                   "check the token named by " + REMOTE_TOKEN_ENV_ENV) from exc
            detail = exc.read(512).decode("utf-8", "replace")
            raise RuntimeError(f"upstream http {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            if isinstance(exc.reason, (socket.timeout, TimeoutError)):
                raise UpstreamSlow(str(exc.reason)) from exc
            if isinstance(exc.reason, ConnectionRefusedError):
                raise UpstreamDown(str(exc.reason)) from exc
            if isinstance(exc.reason, (ConnectionResetError, ConnectionAbortedError)):
                raise UpstreamLost(str(exc.reason)) from exc
            raise UpstreamDown(str(exc.reason)) from exc
        except (socket.timeout, TimeoutError) as exc:
            raise UpstreamSlow(str(exc)) from exc
        except ConnectionRefusedError as exc:
            raise UpstreamDown(str(exc)) from exc
        except (http.client.HTTPException, ConnectionResetError, ConnectionAbortedError) as exc:
            raise UpstreamLost(str(exc)) from exc

    def post(self, message: dict, timeout: float) -> tuple[dict | None, dict[str, str]]:
        """POST one message. Returns (response for its id or None, headers).

        Server notifications and requests that arrive on the same stream are
        delivered to the client as they come.
        """
        body = json.dumps(message).encode("utf-8")
        sent_session = self.session_id
        request = urllib.request.Request(self.url, data=body, headers=self._headers(), method="POST")
        response = self._execute_post(request, timeout, sent_session)
        try:
            return self._read_response(response, message)
        except (socket.timeout, TimeoutError) as exc:
            raise UpstreamSlow(str(exc)) from exc
        except (http.client.HTTPException, ConnectionResetError, ConnectionAbortedError) as exc:
            raise UpstreamLost(str(exc)) from exc

    def _read_response(self, response: Any, message: dict) -> tuple[dict | None, dict[str, str]]:
        with response:
            headers = {k.lower(): v for k, v in response.headers.items()}
            if response.status == 202 or "id" not in message:
                return None, headers
            content_type = headers.get("content-type", "")
            if content_type.startswith("text/event-stream"):
                return self._read_sse(response, message.get("id")), headers
            try:
                raw = response.read()
            except (http.client.HTTPException, ConnectionResetError, ConnectionAbortedError) as exc:
                raise UpstreamLost(str(exc)) from exc
            if not raw:
                return None, headers
            return self._pick(json.loads(raw), message.get("id")), headers

    def _pick(self, payload: Any, wanted: Any) -> dict | None:
        items = payload if isinstance(payload, list) else [payload]
        found = None
        for item in items:
            if isinstance(item, dict) and "method" not in item and item.get("id") == wanted:
                found = item
            elif isinstance(item, dict):
                self._deliver(item)
        return found

    def _read_sse(self, response: Any, wanted: Any) -> dict | None:
        data: list[str] = []
        try:
            for raw in response:
                line = raw.decode("utf-8").rstrip("\r\n")
                if line.startswith("data:"):
                    data.append(line[5:].lstrip(" "))
                    continue
                if line == "" and data:
                    message = json.loads("\n".join(data))
                    data = []
                    found = self._pick(message, wanted)
                    if found is not None:
                        return found
        except (http.client.HTTPException, ConnectionResetError, ConnectionAbortedError) as exc:
            raise UpstreamLost(str(exc)) from exc
        if data:
            return self._pick(json.loads("\n".join(data)), wanted)
        return None

    # ------------------------------------------------------------- session
    def _next_internal_id(self) -> str:
        self._internal += 1
        return f"{INTERNAL_ID_PREFIX}{self._internal}"

    def open_session(self, message_id: Any, params: dict, timeout: float) -> dict:
        """Run initialize upstream; on success the session is live."""
        self.session_id = None
        self.protocol = None
        reply, headers = self.post(
            {"jsonrpc": "2.0", "id": message_id, "method": "initialize", "params": params}, timeout
        )
        if reply is None:
            raise UpstreamDown("initialize returned no response")
        if "result" in reply:
            self.session_id = headers.get("mcp-session-id")
            self.protocol = str(reply["result"].get("protocolVersion") or "") or None
            try:
                self.post({"jsonrpc": "2.0", "method": "notifications/initialized"}, timeout)
            except Exception:
                self.session_id = None
                self.protocol = None
                raise
        return reply

    def ensure_session(self, deadline: float) -> None:
        with self._session_lock:
            if self.session_id:
                return
            params = self.init_params or {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "repowise-bridge", "version": "1"},
            }
            self._until_up(deadline, lambda remaining: self.open_session(self._next_internal_id(), params, remaining))

    def _until_up(self, deadline: float, attempt: Callable[[float], Any]) -> Any:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(self._down_reason())
            try:
                return attempt(min(remaining, 120.0))
            except UpstreamSlow:
                self._slow = True
                continue
            except UpstreamDown:
                self._slow = False
                if self._launcher.failed():
                    raise TimeoutError(self._down_reason())
                if self._launcher.may_start():
                    self._launcher.start()
                time.sleep(min(1.0, max(deadline - time.monotonic(), 0)))

    def _down_reason(self) -> str:
        if self.config.remote:
            if self._slow:
                return f"RepoWise ({self.config.label}) is up but did not answer in time"
            return (f"RepoWise ({self.config.label}) is not reachable; remote mode never falls back to "
                    f"the local server. Set {MODE_ENV}=local to use the local index.")
        code = self._launcher.last_exit if self._launcher else None
        log = runtime_dir() / "launcher.log"
        if self._slow:
            return f"RepoWise shared server at {self.url} is up but did not answer in time"
        if code not in (None, 0):
            return f"RepoWise shared server did not start: launcher exited {code} (fail-closed); see {log}"
        return f"RepoWise shared server at {self.url} is not reachable; see {log}"

    def _drop_session(self, sent: str | None) -> None:
        # Only the session this request used: a concurrent request may already
        # have opened a fresh one, and dropping that would re-initialize again.
        with self._session_lock:
            if self.session_id == sent:
                self.session_id = None

    def _handle_forward_error(self, exc: Exception, message: dict, sent: str | None) -> None:
        if isinstance(exc, SessionExpired):
            self._log("session expired upstream; re-initializing")
            self._drop_session(exc.sent_session)
        elif isinstance(exc, UpstreamLost):
            self._drop_session(sent)
            if message.get("method") in NOT_RESENT_METHODS:
                raise TimeoutError(
                    f"connection to RepoWise was lost during {message.get('method')}; not resent because it may already have run ({exc})"
                ) from exc
            self._log("upstream connection lost; retrying")
        elif isinstance(exc, UpstreamDown):
            self._log("upstream down mid-session; restarting")
            self._drop_session(sent)
        elif isinstance(exc, UpstreamSlow):
            # The request reached the server and may have run; never resend it.
            raise TimeoutError(
                f"RepoWise shared server did not answer {message.get('method')} in time ({exc})"
            ) from exc
        else:
            raise exc

    def forward(self, message: dict, deadline: float) -> dict | None:
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError(self._down_reason())
            self.ensure_session(deadline)
            # A server whose launcher is still probing it may be running on mock
            # vectors; hold real traffic until the probe has passed.
            wait_for_launch_probe(deadline, self._log)
            if time.monotonic() >= deadline:
                raise TimeoutError(self._down_reason())
            sent = self.session_id
            try:
                reply, _ = self.post(message, max(deadline - time.monotonic(), 1.0))
                return reply
            except Exception as exc:
                self._handle_forward_error(exc, message, sent)

    def close(self) -> None:
        if not self.session_id:
            return
        try:
            request = urllib.request.Request(self.url, headers=self._headers(), method="DELETE")
            urllib.request.urlopen(request, timeout=2).close()
        except Exception:
            pass


class Cache:
    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = threading.Lock()

    def _read_data(self) -> dict[str, Any]:
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def get(self, method: str) -> Any:
        data = self._read_data()
        return data.get(method)

    def put(self, method: str, result: Any) -> None:
        with self._lock:
            data = self._read_data()
            data[method] = result
            data["savedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S")
            tmp = self._path.with_name(f"{self._path.name}.{os.getpid()}.tmp")
            try:
                self._path.parent.mkdir(parents=True, exist_ok=True)
                tmp.write_text(json.dumps(data), encoding="utf-8")
                os.replace(tmp, self._path)
            except OSError:
                pass
            finally:
                if tmp.exists():
                    try:
                        tmp.unlink()
                    except OSError:
                        pass


class Bridge:
    def __init__(self, stdin: Any, stdout: Any) -> None:
        self._stdin = stdin
        self._stdout = stdout
        self._out_lock = threading.Lock()
        self._stop = threading.Event()
        runtime = runtime_dir()
        self.log = Log(runtime / "bridge.log")
        self.config = resolve_upstream()
        self.cache = Cache(runtime / ("bridge-cache-remote.json" if self.config.remote else "bridge-cache.json"))
        # Hosts give the whole handshake (initialize, then tools/list) about 30 s.
        # Each cached step waits this long for a live answer before using the
        # cache, so both together stay well inside that budget.
        self.handshake_wait = _env_float("REPOWISE_BRIDGE_HANDSHAKE_WAIT", 4.0)
        self.call_wait = _env_float("REPOWISE_BRIDGE_CALL_WAIT", 300.0)
        self.launcher = Launcher([] if self.config.remote else launcher_command(), self.log,
                                 enabled=not self.config.remote)
        self.upstream = Upstream(self.config.url, self.write, self.launcher, self.log, self.config)
        self._pool = ThreadPoolExecutor(max_workers=8)
        self._warm_lock = threading.Lock()
        self._warming = False

    def write(self, message: dict) -> None:
        try:
            line = json.dumps(message, separators=(",", ":")).encode("utf-8") + b"\n"
        except Exception as exc:
            self.log(f"write serialize error: {exc}")
            return
        with self._out_lock:
            try:
                self._stdout.write(line)
                self._stdout.flush()
            except (BrokenPipeError, OSError) as exc:
                self.log(f"stdout pipe broken: {exc}")
                self._stop.set()

    def error(self, message_id: Any, text: str, code: int = -32603) -> None:
        self.write({"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": text}})

    # ---------------------------------------------------------- handlers
    def handle_initialize(self, message: dict) -> None:
        self.upstream.init_params = message.get("params") or {}
        message_id = message.get("id")
        deadline = time.monotonic() + self.handshake_wait
        try:
            with self.upstream._session_lock:
                reply = self.upstream._until_up(
                    deadline,
                    lambda remaining: self.upstream.open_session(message_id, self.upstream.init_params, remaining),
                )
            if "result" in reply:
                self.cache.put("initialize", reply["result"])
            self.write(reply)
            return
        except TimeoutError as exc:
            reason = str(exc)
        except Exception as exc:  # noqa: BLE001 - reported to the client
            reason = f"{type(exc).__name__}: {exc}"
        cached = self.cache.get("initialize")
        if cached is not None:
            self.log(f"initialize answered from cache; upstream pending ({reason})")
            self.write({"jsonrpc": "2.0", "id": message_id, "result": cached})
            return
        # No cache yet: keep waiting for the real server rather than failing.
        self.handle_request(message, wait=self.call_wait)

    def _try_answer_from_cache(self, method: str, message_id: Any, params: dict | None) -> bool:
        if (params or {}).get("cursor") or self.upstream.session_id:
            return False
        cached = self.cache.get(method)
        if cached is None:
            return False
        self.write({"jsonrpc": "2.0", "id": message_id, "result": cached})
        self._schedule_warm_up()
        return True

    def _forward_request(
        self, message: dict, message_id: Any, method: str, deadline: float, cacheable: bool
    ) -> None:
        try:
            if method == "initialize":
                with self.upstream._session_lock:
                    reply = self.upstream._until_up(
                        deadline,
                        lambda remaining: self.upstream.open_session(
                            message_id, message.get("params") or {}, remaining
                        ),
                    )
            else:
                reply = self.upstream.forward(message, deadline)
        except TimeoutError as exc:
            cached = self.cache.get(method) if cacheable else None
            if cached is not None:
                self.log(f"{method} answered from cache; upstream pending")
                self.write({"jsonrpc": "2.0", "id": message_id, "result": cached})
            else:
                self.log(f"{method} failed: {exc}")
                self.error(message_id, str(exc))
            return
        except Exception as exc:  # noqa: BLE001 - reported to the client
            self.log(f"{method} failed: {type(exc).__name__}: {exc}")
            self.error(message_id, f"repowise bridge: {type(exc).__name__}: {exc}")
            return
        if reply is None:
            self.error(message_id, "repowise bridge: upstream returned no response")
            return
        if cacheable and "result" in reply:
            self.cache.put(method, reply["result"])
        self.write(reply)

    def handle_request(self, message: dict, wait: float | None = None) -> None:
        method = message.get("method")
        message_id = message.get("id")
        if method == "ping":
            self.write({"jsonrpc": "2.0", "id": message_id, "result": {}})
            return
        # Only the first page of a list: a cursor request would overwrite it.
        params = message.get("params") or {}
        cacheable = method in CACHED_METHODS and not params.get("cursor")
        if cacheable and method != "initialize" and self._try_answer_from_cache(method, message_id, params):
            return
        if wait is None:
            wait = self.handshake_wait if cacheable else self.call_wait
        deadline = time.monotonic() + wait
        self._forward_request(message, message_id, method, deadline, cacheable)

    def handle_notification(self, message: dict) -> None:
        if message.get("method") == "notifications/initialized":
            return  # sent upstream by open_session for every (re)initialize
        if not self.upstream.session_id:
            return
        try:
            self.upstream.post(message, 10.0)
        except Exception as exc:  # noqa: BLE001 - notifications are best-effort
            self.log(f"notification {message.get('method')} dropped: {type(exc).__name__}")

    def dispatch(self, message: dict) -> None:
        if "method" not in message:
            # A client response to a server-initiated request.
            self.handle_notification(message)
            return
        if "id" not in message:
            self.handle_notification(message)
            return
        if self.config.error and message["method"] != "ping":
            # Misconfigured remote mode fails closed with a reason the host can show.
            self.error(message.get("id"), f"RepoWise bridge remote mode is misconfigured: {self.config.error}")
            return
        if message["method"] == "initialize":
            # Synchronous: the client sends nothing else until it is answered.
            self.handle_initialize(message)
            return
        self._pool.submit(self._guarded, message)

    def _schedule_warm_up(self) -> None:
        # Single flight: tools/list, prompts/list and resources/list can all
        # arrive before a session exists, and stacked warm-ups would each hold
        # a worker and queue on the session lock ahead of real calls.
        with self._warm_lock:
            if self._warming:
                return
            self._warming = True
        self._pool.submit(self._warm_session)

    def _warm_session(self) -> None:
        try:
            self.upstream.ensure_session(time.monotonic() + self.call_wait)
        except Exception as exc:  # noqa: BLE001 - the next real call retries and reports
            self.log(f"background session warm-up failed: {type(exc).__name__}: {exc}")
        finally:
            with self._warm_lock:
                self._warming = False

    def _guarded(self, message: dict) -> None:
        try:
            self.handle_request(message)
        except Exception as exc:  # noqa: BLE001 - never let a worker die silently
            self.log(f"worker error: {type(exc).__name__}: {exc}")
            self.error(message.get("id"), f"repowise bridge: {type(exc).__name__}")

    def run(self) -> int:
        self.log(f"start upstream={self.config.label}" + (f" config-error={self.config.error}" if self.config.error else ""))
        for raw in self._stdin:
            if self._stop.is_set():
                break
            line = raw.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except ValueError:
                self.error(None, "parse error", code=-32700)
                continue
            if isinstance(message, list):
                if not message:
                    self.error(None, "invalid request: batch is empty", code=-32600)
                    continue
                for item in message:
                    if isinstance(item, dict):
                        self.dispatch(item)
                    else:
                        self.error(None, "invalid request: expected JSON-RPC object", code=-32600)
                continue
            if not isinstance(message, dict):
                self.error(None, "invalid request: expected JSON-RPC object", code=-32600)
                continue
            self.dispatch(message)
        # The host is gone; do not keep this process alive for up to the call
        # wait just to finish answering nobody.
        self._pool.shutdown(wait=False, cancel_futures=True)
        self.upstream.close()
        self.log("stdin closed; exiting")
        return 0


def main() -> int:
    code = Bridge(sys.stdin.buffer, sys.stdout.buffer).run()
    sys.stdout.flush()
    # Executor workers are joined at interpreter exit, which would keep this
    # process alive until an in-flight call to a host that is gone finishes.
    os._exit(code)


if __name__ == "__main__":
    sys.exit(main())
