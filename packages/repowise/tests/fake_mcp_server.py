"""Minimal streamable-HTTP MCP server for the repowise bridge and launcher tests.

Speaks just enough of the 2025-06-18 transport: initialize issues an
Mcp-Session-Id, unknown sessions get 404 (what a restarted server returns),
notifications get 202, tools/call answers over SSE with a progress notification
ahead of the result. GET /v1/models answers 200 so the same process can stand
in for a local embedder (bridge tests). `--check-embedder` stands in for the
real shared server's embedder probe.

Usage: fake_mcp_server.py --port N [--degraded] [--json] [--marker PATH] [--require-bearer TOKEN]
       fake_mcp_server.py <workspace> --check-embedder
       (also accepts the real repowise argv: <workspace> --transport ... --port N)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def build_handler(degraded: bool, json_mode: bool, slow_init: float = 0.0, bearer: str | None = None):
    sessions: set[str] = set()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):  # keep test output clean
            pass

        def _send(self, code: int, body: bytes = b"", ctype: str = "application/json", extra=None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if body:
                self.wfile.write(body)

        def _sse(self, messages, extra=None):
            body = b"".join(
                b"event: message\r\ndata: " + json.dumps(m).encode() + b"\r\n\r\n" for m in messages
            )
            self._send(200, body, "text/event-stream", extra)

        def do_GET(self):
            if self.path.startswith("/v1/models"):
                self._send(200, b'{"object":"list","data":[]}')
            else:
                self._send(405)

        def do_DELETE(self):
            sessions.discard(self.headers.get("Mcp-Session-Id", ""))
            self._send(200)

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            msg = json.loads(self.rfile.read(length))
            if bearer is not None and self.headers.get("Authorization") != f"Bearer {bearer}":
                self._send(401, b'{"error":"bearer required"}')
                return
            method = msg.get("method")
            sid = self.headers.get("Mcp-Session-Id")
            if method == "initialize":
                if slow_init:
                    time.sleep(slow_init)  # a cold repowise loading its workspace
                new = uuid.uuid4().hex
                sessions.add(new)
                result = {
                    "protocolVersion": msg["params"].get("protocolVersion", "2025-06-18"),
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "fake-repowise", "version": "0"},
                }
                self._sse([{"jsonrpc": "2.0", "id": msg["id"], "result": result}], {"Mcp-Session-Id": new})
                return
            if sid not in sessions:
                self._send(404, b'{"error":"session not found"}')
                return
            if "id" not in msg:
                self._send(202)
                return
            if method == "tools/list":
                reply = {"jsonrpc": "2.0", "id": msg["id"], "result": {"tools": [{"name": "list_repos", "inputSchema": {"type": "object"}}]}}
                if json_mode:
                    self._send(200, json.dumps(reply).encode())
                else:
                    self._sse([reply])
                return
            if method == "tools/call":
                call_log = os.environ.get("FAKE_MCP_CALL_LOG")
                if call_log:
                    with open(call_log, "a", encoding="utf-8") as handle:
                        handle.write("call\n")
                if os.environ.get("FAKE_MCP_DROP_CALL") == "1":
                    # The server ran the call, then the connection died
                    # before the response: what a crash mid-call looks like.
                    self.close_connection = True
                    self.connection.close()
                    return
                meta = {"embedder_degraded": degraded}
                text = json.dumps({"repos": ["fixture"], "_meta": meta})
                reply = {"jsonrpc": "2.0", "id": msg["id"], "result": {
                    "content": [{"type": "text", "text": text}],
                    "structuredContent": {"result": {"_meta": meta}}, "isError": False}}
                progress = {"jsonrpc": "2.0", "method": "notifications/progress", "params": {"progressToken": 1, "progress": 1}}
                self._sse([progress, reply])
                return
            self._sse([{"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": "no such method"}}])

    return Handler


def main(argv: list[str]) -> int:
    if "--check-embedder" in argv:
        # Stands in for `shared_server.py --check-embedder`: exit 0 when the
        # embedder probe passes, 2 when it fails closed. FAKE_EMBEDDER_OK=0
        # makes it fail; FAKE_EMBEDDER_CHECK_MARKER records that it ran.
        marker = os.environ.get("FAKE_EMBEDDER_CHECK_MARKER")
        if marker:
            with open(marker, "a", encoding="utf-8") as handle:
                handle.write("checked\n")
        return 0 if os.environ.get("FAKE_EMBEDDER_OK", "1") == "1" else 2
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--degraded", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--marker")
    parser.add_argument("--slow-init", type=float, default=0.0)
    parser.add_argument("--require-bearer", help="answer 401 unless this bearer token is sent (remote-mode tests)")
    args, _unknown = parser.parse_known_args(argv)
    # The launcher test runs this file in place of repowise.exe, whose argv it
    # cannot extend, so it takes these two switches from the environment too.
    args.degraded = args.degraded or os.environ.get("FAKE_MCP_DEGRADED") == "1"
    args.marker = args.marker or os.environ.get("FAKE_MCP_MARKER")
    if args.marker:
        with open(args.marker, "a", encoding="utf-8") as handle:
            handle.write("started\n")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), build_handler(args.degraded, args.json, args.slow_init, args.require_bearer))
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
