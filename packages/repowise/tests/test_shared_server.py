"""Exercise independent MCP sessions against the real SDK ASGI transport."""
from contextlib import asynccontextmanager
import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch, Mock
from types import SimpleNamespace
import asyncio
from io import BytesIO

from mcp.server.fastmcp import FastMCP, Context
from starlette.testclient import TestClient

spec = importlib.util.spec_from_file_location(
    'shared_server', Path(__file__).parents[1] / 'scripts/shared_server.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)


class LocalEmbeddingTest(unittest.TestCase):
    def test_query_embedder_uses_probed_width_despite_stale_overrides(self):
        from repowise.core.providers.embedding.openai import OpenAIEmbedder

        vector = [1.0] + [0.0] * 1023
        with patch.dict(os.environ, {'REPOWISE_EMBEDDING_DIMS': '1536',
                                    'REPOWISE_EMBEDDING_DECLARED_DIMS': '3072'}):
            with patch.object(shared, 'build_opener') as factory:
                factory.return_value.open.return_value = BytesIO(json.dumps({
                    'data': [{'embedding': vector}]}).encode())
                shared.configure_local_embedder('http://localhost:8790/v1',
                                                'text-embedding-3-small')
            embedder = OpenAIEmbedder()
            embedder._client = Mock()
            embedder._client.embeddings.create.return_value = SimpleNamespace(
                data=[SimpleNamespace(embedding=vector)])
            result = asyncio.run(embedder.embed(['synthetic query']))
            self.assertEqual(embedder.dimensions, 1024)
            self.assertEqual(len(result[0]), 1024)
            self.assertEqual(embedder._client.embeddings.create.call_args.kwargs[
                'dimensions'], 1024)

    def test_actual_request_overrides_inherited_remote_route_and_key(self):
        with patch.dict(os.environ, {'OPENAI_BASE_URL': 'https://api.openai.com/v1',
                                    'OPENAI_API_KEY': 'fixture-remote-key'}):
            with patch.object(shared, 'build_opener') as factory:
                factory.return_value.open.return_value = BytesIO(json.dumps({
                    'data': [{'embedding': [0.2, -0.7]}]}).encode())
                shared.configure_local_embedder('http://127.0.0.1:8790/v1/', 'fixture')
                request = factory.return_value.open.call_args.args[0]
                self.assertEqual(request.full_url, 'http://127.0.0.1:8790/v1/embeddings')
                self.assertNotIn('fixture-remote-key', str(request.headers))
                self.assertEqual(os.environ['OPENAI_BASE_URL'], 'http://127.0.0.1:8790/v1')
                self.assertEqual(os.environ['OPENAI_API_KEY'], 'local-retrieval')
                self.assertEqual(os.environ['REPOWISE_EMBEDDER'], 'openai')
                self.assertEqual(os.environ['REPOWISE_EMBEDDING_MODEL'], 'fixture')

    def test_remote_and_credential_urls_are_rejected_without_network(self):
        for url in ('https://api.openai.com/v1', 'http://example.com/v1',
                    'http://127.0.0.1.evil.test/v1', 'http://u:p@localhost/v1',
                    'http://localhost/v1?secret=x', 'http://localhost/other'):
            with self.subTest(url=url), patch.object(shared, 'build_opener') as factory:
                with self.assertRaises(ValueError):
                    shared.configure_local_embedder(url, 'fixture')
                factory.assert_not_called()

    def test_failure_or_bad_vectors_fail_closed_and_preserve_environment(self):
        for payload in ({}, {'data': [{'embedding': [0, 0]}]},
                        {'data': [{'embedding': [float('nan'), 1]}]},
                        {'data': [{'embedding': ['secret', 1]}]}):
            with self.subTest(payload=payload), patch.dict(os.environ, {}, clear=True):
                with patch.object(shared, 'build_opener') as factory:
                    factory.return_value.open.return_value = BytesIO(json.dumps(payload).encode())
                    with self.assertRaisesRegex(RuntimeError, 'refusing to serve'):
                        shared.configure_local_embedder('http://localhost:8790/v1', 'fixture')
                    self.assertNotIn('OPENAI_BASE_URL', os.environ)
        with patch.object(shared, 'build_opener', side_effect=RuntimeError('private-response')):
            with self.assertRaises(RuntimeError) as error:
                shared.configure_local_embedder('http://localhost:8790/v1', 'fixture')
            self.assertNotIn('private-response', str(error.exception))


class SharedLifetimeTest(unittest.TestCase):
    def test_disconnect_and_reconnect_preserve_application_resources(self):
        state = {'entered': 0, 'closed': 0, 'alive': False}

        @asynccontextmanager
        async def lifespan(server):
            state['entered'] += 1
            state['alive'] = True
            try:
                yield state
            finally:
                state['alive'] = False
                state['closed'] += 1

        upstream = FastMCP('fixture', lifespan=lifespan)

        @upstream.tool()
        async def probe(value: str, ctx: Context) -> dict:
            if not state['alive']:
                raise RuntimeError('registry closed')
            # A forwarded tool must still receive the actual request context.
            return {'value': value, 'request_id': str(ctx.request_id)}

        @upstream.resource('fixture://ready')
        def resource() -> str:
            return 'ready'

        app = shared.create_app(upstream, server_version='test')
        with TestClient(app, base_url='http://127.0.0.1:8000') as client:
            def request(method, session=None, params=None, number=1):
                headers = {'Accept': 'application/json, text/event-stream'}
                if session:
                    headers['Mcp-Session-Id'] = session
                msg = {'jsonrpc': '2.0', 'id': number, 'method': method}
                if params is not None:
                    msg['params'] = params
                response = client.post('/mcp', headers=headers, json=msg)
                self.assertEqual(response.status_code, 200, response.text)
                lines = [s[5:].strip() for s in response.text.splitlines()
                         if s.startswith('data:')]
                return response, json.loads(lines[-1] if lines else response.text)

            def connect():
                r, data = request('initialize', params={
                    'protocolVersion': '2025-06-18', 'capabilities': {},
                    'clientInfo': {'name': 'fixture', 'version': '1'}})
                self.assertEqual(data['result']['serverInfo']['version'], 'test')
                sid = r.headers['Mcp-Session-Id']
                client.post('/mcp', headers={
                    'Accept': 'application/json, text/event-stream',
                    'Mcp-Session-Id': sid}, json={
                    'jsonrpc': '2.0', 'method': 'notifications/initialized'})
                return sid

            def disconnect(sid):
                self.assertEqual(client.delete('/mcp', headers={
                    'Mcp-Session-Id': sid}).status_code, 200)

            a, b = connect(), connect()
            self.assertNotEqual(a, b)
            self.assertEqual(state['entered'], 1)
            _, tools = request('tools/list', b)
            self.assertEqual(tools['result']['tools'][0]['name'], 'probe')
            for sid in (a, b):
                _, result = request('tools/call', sid, {
                    'name': 'probe', 'arguments': {'value': 'known'}}, 42)
                self.assertFalse(result['result'].get('isError', False))
                self.assertIn('known', json.dumps(result))
                self.assertIn('42', json.dumps(result))
            disconnect(a)
            _, survivor = request('tools/call', b, {
                'name': 'probe', 'arguments': {'value': 'after-disconnect'}})
            self.assertIn('after-disconnect', json.dumps(survivor))
            _, bad = request('tools/call', b, {'name': 'probe', 'arguments': {}})
            self.assertTrue(bad['result']['isError'])
            _, resources = request('resources/list', b)
            self.assertIn('fixture://ready', json.dumps(resources))
            disconnect(b)
            self.assertTrue(state['alive'])
            c = connect()
            _, result = request('tools/call', c, {
                'name': 'probe', 'arguments': {'value': 'reconnected'}})
            self.assertIn('reconnected', json.dumps(result))
            disconnect(c)
            self.assertEqual(state['entered'], 1)
            self.assertEqual(state['closed'], 0)
        self.assertEqual(state['closed'], 1)
        self.assertFalse(state['alive'])


if __name__ == '__main__':
    unittest.main()
