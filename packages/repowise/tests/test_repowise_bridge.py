"""Behaviour tests for scripts/repowise_bridge.py.

Each test runs the real bridge as a subprocess speaking stdio, against
fake_mcp_server.py on a free loopback port, with the launcher replaced by a
command the test controls. Run: py -3 -m unittest packages/repowise/tests/test_repowise_bridge.py
"""

from __future__ import annotations

import http.client
import io
import json
import os
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRIDGE = HERE.parent / "scripts" / "repowise_bridge.py"
FAKE = HERE / "fake_mcp_server.py"

sys.path.insert(0, str(BRIDGE.parent))
import repowise_bridge  # noqa: E402


def kill_listener(port: int) -> None:
    """Stop whatever process listens on 127.0.0.1:<port> (test ports only)."""
    if os.name != "nt":
        return
    out = subprocess.run(["netstat", "-ano", "-p", "tcp"], capture_output=True, text=True,
                         creationflags=0x08000000).stdout
    for line in out.splitlines():
        parts = line.split()
        if (len(parts) >= 5 and parts[0] == "TCP" and parts[1] == f"127.0.0.1:{port}"
                and parts[3] == "LISTENING" and parts[4] not in ("0", str(os.getpid()))):
            subprocess.run(["taskkill", "/PID", parts[4], "/T", "/F"], capture_output=True,
                           creationflags=0x08000000)


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_port(port: int, up: bool, seconds: float = 10.0) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                if up:
                    return
        except OSError:
            if not up:
                return
        time.sleep(0.05)
    raise AssertionError(f"port {port} did not become {'up' if up else 'down'}")


INIT = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}}}
INITIALIZED = {"jsonrpc": "2.0", "method": "notifications/initialized"}


class BridgeHarness:
    def __init__(self, port: int, launcher: list[str], runtime: Path, extra_env: dict | None = None) -> None:
        env = dict(os.environ)
        env.update({
            "REPOWISE_BRIDGE_URL": f"http://127.0.0.1:{port}/mcp",
            "REPOWISE_BRIDGE_LAUNCHER": json.dumps(launcher),
            "REPOWISE_BRIDGE_RUNTIME": str(runtime),
            "REPOWISE_BRIDGE_HANDSHAKE_WAIT": "3",
            "REPOWISE_BRIDGE_CALL_WAIT": "20",
        })
        env.update(extra_env or {})
        self.proc = subprocess.Popen(
            [sys.executable, "-I", str(BRIDGE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=env,
        )
        self.lines: "queue.Queue[str]" = queue.Queue()
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self) -> None:
        for raw in self.proc.stdout:
            self.lines.put(raw.decode("utf-8"))

    def send(self, message: dict) -> None:
        self.proc.stdin.write((json.dumps(message) + "\n").encode())
        self.proc.stdin.flush()

    def recv_id(self, wanted, timeout: float = 30.0) -> tuple[dict, list[dict]]:
        others = []
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"no response for id {wanted}; saw {others}")
            line = self.lines.get(timeout=remaining)
            message = json.loads(line)  # every stdout line must be JSON-RPC
            if message.get("id") == wanted and "method" not in message:
                return message, others
            others.append(message)

    def close(self) -> None:
        try:
            if self.proc.stdin and not self.proc.stdin.closed:
                self.proc.stdin.close()
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()
        finally:
            if self.proc.stdout and not self.proc.stdout.closed:
                self.proc.stdout.close()
            if self.proc.stderr and not self.proc.stderr.closed:
                self.proc.stderr.close()


class BridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="rwbridge-"))
        self.port = free_port()
        self.marker = self.tmp / "launcher-ran.txt"
        self.servers: list[subprocess.Popen] = []
        self.harness: BridgeHarness | None = None

    def tearDown(self) -> None:
        if self.harness:
            self.harness.close()
        for s in self.servers:
            s.kill()
            s.wait()
        # A server the bridge's launcher started is detached from this test
        # (breakaway, new process group), so it is not in self.servers. Left
        # running, every suite run leaked about three of them; on 2026-10-15
        # 25 had piled up on a machine already out of memory.
        kill_listener(self.port)

    def start_server(self, *flags: str) -> None:
        self.servers.append(subprocess.Popen([sys.executable, "-I", str(FAKE), "--port", str(self.port), *flags]))
        wait_port(self.port, up=True)

    def server_launcher(self) -> list[str]:
        """A launcher that brings the fake server up, like the real one does."""
        return [sys.executable, "-I", str(FAKE), "--port", str(self.port), "--marker", str(self.marker)]

    def handshake(self) -> dict:
        self.harness.send(INIT)
        reply, _ = self.harness.recv_id(1)
        self.harness.send(INITIALIZED)
        return reply

    def test_proxies_live_server_without_launching(self) -> None:
        self.start_server()
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        self.assertEqual(self.handshake()["result"]["serverInfo"]["name"], "fake-repowise")
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        reply, _ = self.harness.recv_id(2)
        self.assertEqual(reply["result"]["tools"][0]["name"], "list_repos")
        self.harness.send({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, others = self.harness.recv_id(3)
        self.assertFalse(reply["result"]["isError"])
        self.assertIn("notifications/progress", [m.get("method") for m in others], "server notifications must pass through")
        self.assertFalse(self.marker.exists(), "launcher must not run while the port is served")

    # ------------------------------------------------------------ remote mode
    def remote_env(self, token: str | None = "remote-test-token", **extra: str) -> dict:
        env = {
            "AGENTHUB_REPOWISE_MODE": "remote",
            "AGENTHUB_REPOWISE_REMOTE_URL": f"http://127.0.0.1:{self.port}/mcp",
            "AGENTHUB_REPOWISE_REMOTE_TOKEN_ENV": "RW_TEST_REMOTE_TOKEN",
            "REPOWISE_BRIDGE_CALL_WAIT": "3",
        }
        if token is not None:
            env["RW_TEST_REMOTE_TOKEN"] = token
        env.update(extra)
        return env

    def test_remote_mode_forwards_with_bearer_and_never_launches(self) -> None:
        self.start_server("--require-bearer", "remote-test-token")
        # The local URL points at a dead port: remote mode must ignore it.
        env = self.remote_env(REPOWISE_BRIDGE_URL=f"http://127.0.0.1:{free_port()}/mcp")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp, env)
        self.assertEqual(self.handshake()["result"]["serverInfo"]["name"], "fake-repowise")
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(2)
        self.assertFalse(reply["result"]["isError"])
        self.assertFalse(self.marker.exists(), "remote mode must never run the local launcher")
        self.assertTrue((self.tmp / "bridge-cache-remote.json").exists(), "remote handshake cache is kept apart")
        log = (self.tmp / "bridge.log").read_text(encoding="utf-8")
        self.assertNotIn("remote-test-token", log, "the bearer token must never be logged")
        self.assertIn("remote http://127.0.0.1", log)

    def test_remote_mode_down_does_not_fall_back_or_launch(self) -> None:
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp,
                                     self.remote_env(REPOWISE_BRIDGE_HANDSHAKE_WAIT="1"))
        self.harness.send(INIT)
        reply, _ = self.harness.recv_id(1, timeout=20)
        self.assertIn("error", reply)
        self.assertIn("never falls back", reply["error"]["message"])
        self.assertFalse(self.marker.exists(), "remote mode must never run the local launcher")

    def test_remote_mode_without_token_fails_closed(self) -> None:
        self.start_server("--require-bearer", "remote-test-token")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp, self.remote_env(token=None))
        self.harness.send(INIT)
        reply, _ = self.harness.recv_id(1, timeout=10)
        self.assertIn("RW_TEST_REMOTE_TOKEN", reply["error"]["message"])
        self.harness.send({"jsonrpc": "2.0", "id": 9, "method": "ping"})
        pong, _ = self.harness.recv_id(9, timeout=10)
        self.assertIn("result", pong, "ping still answers so the host can show the error")

    def test_remote_mode_wrong_token_reports_refusal(self) -> None:
        self.start_server("--require-bearer", "remote-test-token")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp, self.remote_env(token="bad-token-123"))
        self.harness.send(INIT)
        reply, _ = self.harness.recv_id(1, timeout=20)
        self.assertIn("refused the bearer token", reply["error"]["message"])
        self.assertNotIn("bad-token-123", json.dumps(reply), "the token must never be echoed")

    def test_resolve_upstream_rules(self) -> None:
        r = repowise_bridge.resolve_upstream
        self.assertFalse(r({}).remote)
        self.assertEqual(r({}).url, repowise_bridge.DEFAULT_URL)
        self.assertIsNone(r({"AGENTHUB_REPOWISE_MODE": "local"}).error)
        base = {"AGENTHUB_REPOWISE_MODE": "remote", "REPOWISE_REMOTE_TOKEN": "t"}
        self.assertIn("https", r({**base, "AGENTHUB_REPOWISE_REMOTE_URL": "http://example.test/mcp"}).error)
        self.assertIn("credentials", r({**base, "AGENTHUB_REPOWISE_REMOTE_URL": "https://u:p@example.test/mcp"}).error)
        ok = r({**base, "AGENTHUB_REPOWISE_REMOTE_URL": "https://example.test/mcp"})
        self.assertIsNone(ok.error)
        self.assertEqual(ok.authorization, "Bearer t")
        self.assertEqual(ok.label, "remote https://example.test")
        self.assertIn("not 'local' or 'remote'", r({"AGENTHUB_REPOWISE_MODE": "hosted"}).error)

    def test_json_responses_are_proxied(self) -> None:
        self.start_server("--json")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        self.handshake()
        self.harness.send({"jsonrpc": "2.0", "id": "s-2", "method": "tools/list"})
        reply, _ = self.harness.recv_id("s-2")
        self.assertEqual(len(reply["result"]["tools"]), 1)

    def test_starts_server_when_port_is_down(self) -> None:
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        reply = self.handshake()
        self.assertIn("result", reply)
        self.assertTrue(self.marker.exists(), "bridge must invoke the launcher when nothing listens")
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(2)
        self.assertFalse(reply["result"]["isError"])

    def test_recovers_when_server_restarts_mid_session(self) -> None:
        self.start_server()
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        self.handshake()
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        self.harness.recv_id(2)
        # Kill the server the bridge has a session with. The next call must
        # find the port refused, run the launcher, re-initialize, and succeed.
        self.servers[0].kill()
        self.servers[0].wait()
        wait_port(self.port, up=False)
        self.harness.send({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(3)
        self.assertFalse(reply["result"]["isError"])
        self.assertTrue(self.marker.exists())

    def test_recovers_from_expired_session(self) -> None:
        # A different server instance on the same port knows none of the old
        # sessions and answers 404, exactly as a restarted repowise does.
        self.start_server()
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        self.handshake()
        self.servers[0].kill()
        self.servers[0].wait()
        wait_port(self.port, up=False)
        self.start_server()
        self.harness.send({"jsonrpc": "2.0", "id": 4, "method": "tools/list"})
        reply, _ = self.harness.recv_id(4)
        self.assertIn("result", reply)
        self.assertFalse(self.marker.exists(), "an expired session alone must not run the launcher")

    def test_slow_server_is_not_treated_as_down(self) -> None:
        # Seen 2026-10-14: a freshly started repowise took longer than the
        # handshake wait to answer initialize. That is a busy server, not a
        # dead one: answer the handshake from cache, run no launcher, and let
        # the first real call complete once the server answers.
        cache = {"initialize": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                                "serverInfo": {"name": "cached", "version": "0"}},
                 "tools/list": {"tools": [{"name": "list_repos", "inputSchema": {"type": "object"}}]}}
        (self.tmp / "bridge-cache.json").write_text(json.dumps(cache), encoding="utf-8")
        self.start_server("--slow-init", "3")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp,
                                     {"REPOWISE_BRIDGE_HANDSHAKE_WAIT": "1"})
        reply = self.handshake()
        self.assertEqual(reply["result"]["serverInfo"]["name"], "cached")
        # With no upstream session yet, tools/list must not pay a second cold
        # session open: hosts time the tool fetch tighter than that.
        started = time.monotonic()
        self.harness.send({"jsonrpc": "2.0", "id": "tl", "method": "tools/list"})
        listed, _ = self.harness.recv_id("tl")
        self.assertEqual(listed["result"]["tools"][0]["name"], "list_repos")
        self.assertLess(time.monotonic() - started, 2.0, "tools/list must come straight from cache while the session opens")
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(2)
        self.assertFalse(reply["result"]["isError"])
        self.assertFalse(self.marker.exists(), "a slow but listening server must not run the launcher")

    def test_fail_closed_launcher_errors_fast_and_handshake_uses_cache(self) -> None:
        cache = {"initialize": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                                "serverInfo": {"name": "cached", "version": "0"}},
                 "tools/list": {"tools": [{"name": "list_repos", "inputSchema": {"type": "object"}}]}}
        (self.tmp / "bridge-cache.json").write_text(json.dumps(cache), encoding="utf-8")
        fail_closed = [sys.executable, "-I", "-c", "import sys; sys.exit(2)"]
        self.harness = BridgeHarness(self.port, fail_closed, self.tmp)
        started = time.monotonic()
        reply = self.handshake()
        self.assertEqual(reply["result"]["serverInfo"]["name"], "cached")
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        reply, _ = self.harness.recv_id(2)
        self.assertEqual(reply["result"]["tools"][0]["name"], "list_repos")
        self.harness.send({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(3)
        self.assertIn("error", reply)
        self.assertIn("exited 2", reply["error"]["message"])
        self.assertLess(time.monotonic() - started, 15, "a fail-closed launcher must not make calls wait out the full call budget")

    def test_no_cache_and_fail_closed_returns_error_for_initialize(self) -> None:
        fail_closed = [sys.executable, "-I", "-c", "import sys; sys.exit(2)"]
        self.harness = BridgeHarness(self.port, fail_closed, self.tmp)
        self.harness.send(INIT)
        reply, _ = self.harness.recv_id(1)
        self.assertIn("error", reply)

    def test_relaunches_after_fail_closed_cooldown(self) -> None:
        # Review finding: a fail-closed launch used to be final for the
        # bridge's whole life, even after the embedder came back.
        flip = self.tmp / "second-launch.txt"
        script = (
            "import os, sys, subprocess\n"
            f"flag = {str(flip)!r}\n"
            "if not os.path.exists(flag):\n"
            "    open(flag, 'w').close(); sys.exit(2)\n"
            f"os.execv(sys.executable, [sys.executable, '-I', {str(FAKE)!r}, '--port', '{self.port}', '--marker', {str(self.marker)!r}])\n"
        )
        launcher = [sys.executable, "-I", "-c", script]
        self.harness = BridgeHarness(self.port, launcher, self.tmp, {
            "REPOWISE_BRIDGE_RELAUNCH_COOLDOWN": "1", "REPOWISE_BRIDGE_RELAUNCH_INTERVAL": "0.5"})
        self.harness.send(INIT)
        first, _ = self.harness.recv_id(1)
        self.assertIn("error", first, "first launch fails closed")
        time.sleep(1.5)
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(2)
        self.assertFalse(reply["result"]["isError"], "after the cooldown the bridge must launch again")
        self.assertTrue(self.marker.exists())

    def test_holds_calls_while_launcher_is_probing(self) -> None:
        # Review finding: the port listens before the launcher has confirmed
        # the server is not on the mock embedder; real calls must wait.
        self.start_server()
        sleeper = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(60)"])
        self.servers.append(sleeper)
        state = self.tmp / "launcher.state.json"
        state.write_text(json.dumps({"pid": sleeper.pid, "state": "starting"}), encoding="utf-8")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        self.handshake()
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        with self.assertRaises((AssertionError, queue.Empty), msg="the call must not be answered while the probe runs"):
            self.harness.recv_id(2, timeout=2)
        state.write_text(json.dumps({"pid": sleeper.pid, "state": "ready"}), encoding="utf-8")
        reply, _ = self.harness.recv_id(2)
        self.assertFalse(reply["result"]["isError"])

    def test_probe_gate_times_out_with_a_clear_error(self) -> None:
        self.start_server()
        sleeper = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(60)"])
        self.servers.append(sleeper)
        (self.tmp / "launcher.state.json").write_text(json.dumps({"pid": sleeper.pid, "state": "starting"}), encoding="utf-8")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp, {"REPOWISE_BRIDGE_CALL_WAIT": "2"})
        self.handshake()
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(2)
        self.assertIn("still being verified", reply["error"]["message"])

    def test_stale_launcher_state_from_a_dead_pid_is_ignored(self) -> None:
        self.start_server()
        (self.tmp / "launcher.state.json").write_text(json.dumps({"pid": 999999, "state": "starting"}), encoding="utf-8")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp, {"REPOWISE_BRIDGE_CALL_WAIT": "5"})
        self.handshake()
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_repos", "arguments": {}}})
        reply, _ = self.harness.recv_id(2)
        self.assertFalse(reply["result"]["isError"])

    def test_tool_call_is_not_resent_after_connection_drops_mid_call(self) -> None:
        # Review finding: a reset after the server began a call used to be
        # retried on a new session, running a write tool twice.
        calls = self.tmp / "calls.txt"
        os.environ["FAKE_MCP_CALL_LOG"] = str(calls)
        os.environ["FAKE_MCP_DROP_CALL"] = "1"
        try:
            self.start_server()
        finally:
            os.environ.pop("FAKE_MCP_CALL_LOG", None)
            os.environ.pop("FAKE_MCP_DROP_CALL", None)
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        self.handshake()
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "update_decision_records", "arguments": {}}})
        reply, _ = self.harness.recv_id(2)
        self.assertIn("not resent", reply["error"]["message"])
        self.assertEqual(calls.read_text(encoding="utf-8").count("call"), 1, "the server must see the call exactly once")

    def test_cursor_pages_do_not_overwrite_the_cached_first_page(self) -> None:
        self.start_server()
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp)
        self.handshake()
        self.harness.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        self.harness.recv_id(2)
        before = json.loads((self.tmp / "bridge-cache.json").read_text(encoding="utf-8"))["tools/list"]
        self.harness.send({"jsonrpc": "2.0", "id": 3, "method": "tools/list", "params": {"cursor": "page-2"}})
        self.harness.recv_id(3)
        after = json.loads((self.tmp / "bridge-cache.json").read_text(encoding="utf-8"))["tools/list"]
        self.assertEqual(before, after)

    def test_ping_is_answered_locally(self) -> None:
        self.harness = BridgeHarness(self.port, [sys.executable, "-I", "-c", "import sys; sys.exit(2)"], self.tmp)
        self.harness.send({"jsonrpc": "2.0", "id": 9, "method": "ping"})
        reply, _ = self.harness.recv_id(9, timeout=5)
        self.assertEqual(reply["result"], {})


class SpawnFlagTests(unittest.TestCase):
    def test_launcher_is_windowless_and_detached(self) -> None:
        flags = repowise_bridge.spawn_flags(True)
        self.assertTrue(flags & repowise_bridge.CREATE_NO_WINDOW)
        self.assertTrue(flags & repowise_bridge.CREATE_BREAKAWAY_FROM_JOB)
        fallback = repowise_bridge.spawn_flags(False)
        self.assertTrue(fallback & repowise_bridge.CREATE_NO_WINDOW)
        self.assertFalse(fallback & repowise_bridge.CREATE_BREAKAWAY_FROM_JOB)

    def test_default_launcher_is_the_shared_script_via_windows_powershell(self) -> None:
        os.environ.pop("REPOWISE_BRIDGE_LAUNCHER", None)
        command = repowise_bridge.launcher_command()
        self.assertTrue(command[0].lower().endswith("powershell.exe"))
        self.assertIn("-NonInteractive", command)
        self.assertTrue(command[-1].endswith("Start-RepoWiseShared.ps1"))
        self.assertTrue(Path(command[-1]).exists())


class BridgeHardeningTests(unittest.TestCase):
    def test_partial_read_raises_upstream_lost(self) -> None:
        up = repowise_bridge.Upstream("http://127.0.0.1:9999", lambda m: None, None, repowise_bridge.Log(repowise_bridge.runtime_dir() / "test.log"))

        class FakeResp:
            headers = {"content-type": "application/json"}
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def read(self):
                raise http.client.IncompleteRead(b"part", 50)

        with self.assertRaises(repowise_bridge.UpstreamLost):
            up._read_response(FakeResp(), {"id": 1, "method": "tools/call"})

    def test_invalid_jsonrpc_request_returns_invalid_request_error(self) -> None:
        out = io.BytesIO()
        bridge = repowise_bridge.Bridge(io.BytesIO(b"[]\n123\n"), out)
        bridge.run()
        lines = [json.loads(line) for line in out.getvalue().splitlines() if line.strip()]
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0]["error"]["code"], -32600)
        self.assertEqual(lines[1]["error"]["code"], -32600)

    def test_broken_stdout_pipe_handled_cleanly(self) -> None:
        class BrokenStream:
            def write(self, b):
                raise BrokenPipeError("Broken pipe")

            def flush(self):
                raise BrokenPipeError("Broken pipe")

        bridge = repowise_bridge.Bridge(io.BytesIO(), BrokenStream())
        bridge.write({"jsonrpc": "2.0", "id": 1, "result": {}})
        self.assertTrue(bridge._stop.is_set())

    def test_open_session_cleans_up_on_failed_initialized_notification(self) -> None:
        up = repowise_bridge.Upstream("http://127.0.0.1:9999", lambda m: None, None, repowise_bridge.Log(repowise_bridge.runtime_dir() / "test.log"))

        def mock_post(msg, timeout):
            if msg.get("method") == "initialize":
                return {"result": {"protocolVersion": "2025-06-18"}}, {"mcp-session-id": "sess-123"}
            raise repowise_bridge.UpstreamDown("dropped on initialized notification")

        up.post = mock_post
        with self.assertRaises(repowise_bridge.UpstreamDown):
            up.open_session(1, {}, 5.0)
        self.assertIsNone(up.session_id)

    def test_corrupted_state_and_cache_files_handled_gracefully(self) -> None:
        tmp = Path(tempfile.mkdtemp())
        os.environ["REPOWISE_BRIDGE_RUNTIME"] = str(tmp)
        cache_file = tmp / "bridge-cache.json"
        cache_file.write_text("null", encoding="utf-8")
        c = repowise_bridge.Cache(cache_file)
        self.assertIsNone(c.get("tools/list"))
        c.put("tools/list", {"tools": []})
        self.assertEqual(c.get("tools/list"), {"tools": []})

        state_file = tmp / "launcher.state.json"
        state_file.write_text("null", encoding="utf-8")
        self.assertIsNone(repowise_bridge.wait_for_launch_probe(0, lambda m: None))
        state_file.write_text('{"state": "starting", "pid": "bad_pid"}', encoding="utf-8")
        self.assertIsNone(repowise_bridge.wait_for_launch_probe(0, lambda m: None))

    def test_forward_respects_expired_deadline_without_posting(self) -> None:
        up = repowise_bridge.Upstream("http://127.0.0.1:9999", lambda m: None, None, repowise_bridge.Log(repowise_bridge.runtime_dir() / "test.log"))
        up.session_id = "sess-1"
        posted = False

        def mock_post(msg, timeout):
            nonlocal posted
            posted = True
            return {"result": {}}, {}

        up.post = mock_post
        with self.assertRaises(TimeoutError):
            up.forward({"id": 1, "method": "tools/list"}, deadline=time.monotonic() - 1.0)
        self.assertFalse(posted)


if __name__ == "__main__":
    unittest.main()
