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
import sys
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener


#: Environment names the fleet embedder is read from. Values are never
#: persisted; AZURE_OPENAI_* is deliberately not read (that account is a client's).
EMBEDDER_BASE_URL_ENV = 'FOUNDRY_OPENAI_BASE_URL'
EMBEDDER_KEY_ENVS = ('FOUNDRY_API_KEY', 'AZURE_AI_SERVICES_KEY')
EMBEDDER_DEPLOYMENT_ENV = 'FOUNDRY_EMBEDDING_DEPLOYMENT'
EMBEDDER_HOST_SUFFIX = '.openai.azure.com'


def configure_remote_embedder(environ=None) -> None:
    """Pin the query process to the MahumTech Azure OpenAI embedding deployment.

    Reads FOUNDRY_OPENAI_BASE_URL (https, *.openai.azure.com, /openai/v1), the
    key from FOUNDRY_API_KEY or AZURE_AI_SERVICES_KEY, and the deployment name
    from FOUNDRY_EMBEDDING_DEPLOYMENT. A provider constructor can succeed with
    an invalid key, so probe a real embedding before serving; never trust that
    constructor as retrieval health. The key only ever goes to the validated
    Azure host, over https, and only into this process's environment.
    """
    env = os.environ if environ is None else environ
    base_url = (env.get(EMBEDDER_BASE_URL_ENV) or '').strip()
    key = next((env[name].strip() for name in EMBEDDER_KEY_ENVS
                if (env.get(name) or '').strip()), '')
    model = (env.get(EMBEDDER_DEPLOYMENT_ENV) or '').strip()
    if not (base_url and key and model):
        raise ValueError(f'RepoWise embeddings need {EMBEDDER_BASE_URL_ENV}, '
                         f'{" or ".join(EMBEDDER_KEY_ENVS)} and '
                         f'{EMBEDDER_DEPLOYMENT_ENV}')
    parsed = urlsplit(base_url)
    host = (parsed.hostname or '').lower()
    try:
        port = parsed.port
    except ValueError:
        port = -1
    if (parsed.scheme != 'https' or not host.endswith(EMBEDDER_HOST_SUFFIX) or
            len(host) == len(EMBEDDER_HOST_SUFFIX) or 'pndh' in host or
            port not in (None, 443) or parsed.username or parsed.password or
            parsed.query or parsed.fragment or
            parsed.path.rstrip('/') != '/openai/v1'):
        raise ValueError('RepoWise embeddings require an https Azure OpenAI '
                         '/openai/v1 endpoint')
    endpoint = base_url.rstrip('/')
    request = Request(endpoint + '/embeddings', data=json.dumps({
        'model': model, 'input': ['RepoWise retrieval readiness']
    }).encode(), headers={'Content-Type': 'application/json',
                         'Authorization': f'Bearer {key}'})
    try:
        # Direct connection to the validated host only; no inherited proxy.
        with build_opener(ProxyHandler({})).open(request, timeout=30) as response:
            payload = json.load(response)
        vector = payload['data'][0]['embedding']
        if (not isinstance(vector, list) or len(vector) < 2 or
                any(type(v) not in (int, float) or not math.isfinite(v)
                    for v in vector) or not any(vector)):
            raise ValueError('invalid embedding')
    except Exception:
        # Never echo response bodies, headers, keys or inherited configuration.
        raise RuntimeError('Remote embedding request failed; refusing to serve') from None
    # Pin both width overrides so stale inherited settings cannot resize queries.
    os.environ.update(OPENAI_BASE_URL=endpoint, OPENAI_API_KEY=key,
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
    parser.add_argument('--check-embedder', action='store_true',
                        help='probe the Azure embedder and exit 0, or 2 when it '
                             'is missing or failing (no server is started)')
    args = parser.parse_args()
    # This fleet endpoint is loopback-only. Never silently bypass the vendor's
    # bearer/principal middleware if an operator later enables HTTP auth.
    if os.environ.get('REPOWISE_API_KEY') or os.environ.get('REPOWISE_HTTP_PRINCIPALS'):
        raise RuntimeError('Authenticated serving requires the vendor HTTP gateway')
    if args.check_embedder:
        try:
            configure_remote_embedder()
        except (ValueError, RuntimeError) as error:
            print(f'FAIL-CLOSED: {error}', file=sys.stderr)
            raise SystemExit(2) from None
        return
    configure_remote_embedder()
    from repowise.server.mcp_server import create_mcp_server
    import uvicorn
    upstream = create_mcp_server(repo_path=args.workspace, workspace_mode=True)
    app = create_app(upstream, server_version=version('repowise'))
    uvicorn.run(app, host='127.0.0.1', port=args.port)


if __name__ == '__main__':
    main()
