"""Stdio MCP bridge to the cloud RepoWise server over the SSH tunnel.

Sits where a host's repowise MCP entry would point: newline-delimited JSON-RPC
on stdin is POSTed to REPOWISE_CLOUD_MCP_URL (the tunnel's loopback endpoint),
responses are written to stdout, and every CallToolResult passes through
context_cap so an agent's pre-task context and post-diff context stay bounded
(env caps: REPOWISE_CTX_MAX_BYTES, REPOWISE_CTX_MAX_ITEMS).

This is the cloud counterpart of scripts/repowise_bridge.py, deliberately
smaller: the tunnel itself is the availability story (Connect-RepoWiseCloud.ps1
opens it on demand), so this bridge never launches a server and never falls
back silently -- an unreachable endpoint answers every pending request with a
JSON-RPC error.

Stdlib only. Diagnostics never reach stdout.
"""

from __future__ import annotations

import http.client
import json
import os
import sys
import urllib.error
import urllib.request

from context_cap import cap_response

DEFAULT_URL = "http://127.0.0.1:7339/mcp"


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, ""))
    except ValueError:
        return default


class Session:
    def __init__(self, url: str, timeout: float) -> None:
        self.url = url
        self.timeout = timeout
        self.session_id: str | None = None
        self.protocol: str | None = None

    def headers(self) -> dict:
        headers = {"Content-Type": "application/json",
                   "Accept": "application/json, text/event-stream"}
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        if self.protocol:
            headers["MCP-Protocol-Version"] = self.protocol
        return headers

    def post(self, message: dict) -> list[dict]:
        """POST one JSON-RPC message; returns the JSON-RPC messages received."""
        body = json.dumps(message).encode("utf-8")
        request = urllib.request.Request(self.url, data=body, headers=self.headers(), method="POST")
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            sid = response.headers.get("Mcp-Session-Id")
            if sid:
                self.session_id = sid
            proto = (message.get("params") or {}).get("protocolVersion")
            if message.get("method") == "initialize" and proto:
                self.protocol = proto
            content_type = response.headers.get("Content-Type", "")
            raw = response.read()
            if response.status == 202 or not raw:
                return []
            if "text/event-stream" in content_type:
                return parse_sse(raw.decode("utf-8", "replace"))
            try:
                return [json.loads(raw.decode("utf-8"))]
            except ValueError:
                return []


def parse_sse(text: str) -> list[dict]:
    """Collect every `data:` payload from a text/event-stream body."""
    messages: list[dict] = []
    data_lines: list[str] = []

    def flush() -> None:
        if not data_lines:
            return
        payload = "\n".join(data_lines)
        data_lines.clear()
        try:
            messages.append(json.loads(payload))
        except ValueError:
            pass

    for line in text.splitlines():
        if line == "":
            flush()
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
    flush()
    return messages


def error_response(request_id, message: str) -> dict:
    return {"jsonrpc": "2.0", "id": request_id,
            "error": {"code": -32000, "message": message}}


def main() -> int:
    url = os.environ.get("REPOWISE_CLOUD_MCP_URL", DEFAULT_URL)
    max_bytes = _env_int("REPOWISE_CTX_MAX_BYTES", 0) or 65536
    max_items = _env_int("REPOWISE_CTX_MAX_ITEMS", 0) or 40
    timeout = _env_int("REPOWISE_CLOUD_TIMEOUT_S", 120)
    session = Session(url, timeout)
    out = sys.stdout

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except ValueError:
            continue
        request_id = message.get("id")
        try:
            replies = session.post(message)
        except (urllib.error.URLError, http.client.HTTPException, OSError) as exc:
            if request_id is not None:
                out.write(json.dumps(error_response(
                    request_id, f"cloud RepoWise unreachable at {url}: {exc}")) + "\n")
                out.flush()
            continue
        for reply in replies:
            capped, _stats = cap_response(reply, max_bytes, max_items)
            out.write(json.dumps(capped) + "\n")
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
