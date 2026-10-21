"""Serve RepoWise's public FastMCP surface with application-owned resources.

MCP SDK 1.x enters a low-level server lifespan for each HTTP session. RepoWise
0.58 keeps its registry in process globals, so one session's teardown invalidates
other sessions. Compose its public creation/call APIs with the SDK's ASGI host:
enter RepoWise's configured lifespan once around the HTTP session manager. No
installed module is patched and each client retains its own MCP session.
"""
from __future__ import annotations

import argparse
from contextlib import asynccontextmanager
from importlib.metadata import version
import os


def create_app(upstream, *, server_version: str):
    from mcp.server.lowlevel import Server
    from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
    from starlette.applications import Starlette
    from starlette.routing import Route

    lifespan = upstream.settings.lifespan
    if lifespan is None:
        raise RuntimeError("RepoWise must declare its resource lifespan")
    server = Server(upstream.name, version=server_version,
                    instructions=upstream.instructions)
    # Keep the vendor's schemas, conversion, progress context and structured
    # results. The SDK request ContextVar is shared by both server instances.
    server.list_tools()(upstream.list_tools)
    server.call_tool(validate_input=False)(upstream.call_tool)
    server.list_resources()(upstream.list_resources)
    server.read_resource()(upstream.read_resource)
    server.list_resource_templates()(upstream.list_resource_templates)
    server.list_prompts()(upstream.list_prompts)
    server.get_prompt()(upstream.get_prompt)
    manager = StreamableHTTPSessionManager(
        server, security_settings=upstream.settings.transport_security)

    @asynccontextmanager
    async def application_lifespan(app):
        async with lifespan(upstream):
            async with manager.run():
                yield

    class Endpoint:
        async def __call__(self, scope, receive, send):
            await manager.handle_request(scope, receive, send)

    return Starlette(routes=[Route('/mcp', Endpoint(),
                                  methods=['GET', 'POST', 'DELETE'])],
                     lifespan=application_lifespan)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace')
    parser.add_argument('--port', type=int, default=7339)
    args = parser.parse_args()
    # This fleet endpoint is loopback-only. Never silently bypass the vendor's
    # bearer/principal middleware if an operator later enables HTTP auth.
    if os.environ.get('REPOWISE_API_KEY') or os.environ.get('REPOWISE_HTTP_PRINCIPALS'):
        raise RuntimeError('Authenticated serving requires the vendor HTTP gateway')
    from repowise.server.mcp_server import create_mcp_server
    import uvicorn
    upstream = create_mcp_server(repo_path=args.workspace, workspace_mode=True)
    app = create_app(upstream, server_version=version('repowise'))
    uvicorn.run(app, host='127.0.0.1', port=args.port)


if __name__ == '__main__':
    main()
