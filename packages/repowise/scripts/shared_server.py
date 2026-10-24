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
import json
import math
import os
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener


def configure_local_embedder(base_url: str, model: str) -> None:
    """Pin the query process to the same local provider used by indexing.

    A provider constructor can succeed with an invalid remote key. Probe a real
    embedding before serving; never trust that constructor as retrieval health.
    This process must not inherit a remote endpoint or send its key locally.
    """
    parsed = urlsplit(base_url)
    if (parsed.scheme != 'http' or parsed.hostname not in
            {'127.0.0.1', 'localhost', '::1'} or parsed.username or
            parsed.password or parsed.query or parsed.fragment or
            parsed.path.rstrip('/') != '/v1'):
        raise ValueError('RepoWise embeddings require a loopback HTTP /v1 endpoint')
    endpoint = base_url.rstrip('/')
    request = Request(endpoint + '/embeddings', data=json.dumps({
        'model': model, 'input': ['RepoWise local retrieval readiness']
    }).encode(), headers={'Content-Type': 'application/json',
                         'Authorization': 'Bearer local-retrieval'})
    try:
        # Local requests must not leave the machine through an inherited proxy.
        with build_opener(ProxyHandler({})).open(request, timeout=30) as response:
            payload = json.load(response)
        vector = payload['data'][0]['embedding']
        if (not isinstance(vector, list) or len(vector) < 2 or
                any(type(v) not in (int, float) or not math.isfinite(v)
                    for v in vector) or not any(vector)):
            raise ValueError('invalid embedding')
    except Exception:
        # Never echo response bodies, headers, keys or inherited configuration.
        raise RuntimeError('Local embedding request failed; refusing to serve') from None
    # The local model alias need not have OpenAI's default width. Pin both
    # supported overrides so stale inherited settings cannot resize queries.
    os.environ.update(OPENAI_BASE_URL=endpoint, OPENAI_API_KEY='local-retrieval',
                      REPOWISE_EMBEDDER='openai', REPOWISE_EMBEDDING_MODEL=model,
                      REPOWISE_EMBEDDING_DIMS=str(len(vector)),
                      REPOWISE_EMBEDDING_DECLARED_DIMS=str(len(vector)))


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
    parser.add_argument('--embedding-base-url', default='http://127.0.0.1:8790/v1')
    parser.add_argument('--embedding-model', default='text-embedding-3-small')
    args = parser.parse_args()
    # This fleet endpoint is loopback-only. Never silently bypass the vendor's
    # bearer/principal middleware if an operator later enables HTTP auth.
    if os.environ.get('REPOWISE_API_KEY') or os.environ.get('REPOWISE_HTTP_PRINCIPALS'):
        raise RuntimeError('Authenticated serving requires the vendor HTTP gateway')
    configure_local_embedder(args.embedding_base_url, args.embedding_model)
    from repowise.server.mcp_server import create_mcp_server
    import uvicorn
    upstream = create_mcp_server(repo_path=args.workspace, workspace_mode=True)
    app = create_app(upstream, server_version=version('repowise'))
    uvicorn.run(app, host='127.0.0.1', port=args.port)


if __name__ == '__main__':
    main()
