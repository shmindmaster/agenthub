"""Behaviour tests for scripts/repowise_bridge.py.

Each test runs the real bridge as a subprocess speaking stdio, against
fake_mcp_server.py on a free loopback port, with the launcher replaced by a
command the test controls. Run: py -3 -m unittest packages/repowise/tests/test_repowise_bridge.py
"""

from __future__ import annotations

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
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()


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
                                "serverInfo": {"name": "cached", "version": "0"}}}
        (self.tmp / "bridge-cache.json").write_text(json.dumps(cache), encoding="utf-8")
        self.start_server("--slow-init", "3")
        self.harness = BridgeHarness(self.port, self.server_launcher(), self.tmp,
                                     {"REPOWISE_BRIDGE_HANDSHAKE_WAIT": "1"})
        reply = self.handshake()
        self.assertEqual(reply["result"]["serverInfo"]["name"], "cached")
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


if __name__ == "__main__":
    unittest.main()
