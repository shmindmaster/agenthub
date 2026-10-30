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


AZURE_URL = 'https://aoai-mrender-4e123a95.openai.azure.com/openai/v1/'
FIXTURE_KEY = 'fixture-azure-key'


def azure_env(**extra):
    env = {'FOUNDRY_OPENAI_BASE_URL': AZURE_URL, 'FOUNDRY_API_KEY': FIXTURE_KEY,
           'FOUNDRY_EMBEDDING_DEPLOYMENT': 'text-embedding-3-small'}
    env.update(extra)
    return env


class RemoteEmbeddingTest(unittest.TestCase):
    def test_query_embedder_uses_probed_width_despite_stale_overrides(self):
        from repowise.core.providers.embedding.openai import OpenAIEmbedder

        vector = [1.0] + [0.0] * 1535
        with patch.dict(os.environ, azure_env(REPOWISE_EMBEDDING_DIMS='1024',
                                              REPOWISE_EMBEDDING_DECLARED_DIMS='3072'),
                        clear=True):
            with patch.object(shared, 'build_opener') as factory:
                factory.return_value.open.return_value = BytesIO(json.dumps({
                    'data': [{'embedding': vector}]}).encode())
                shared.configure_remote_embedder()
            embedder = OpenAIEmbedder()
            embedder._client = Mock()
            embedder._client.embeddings.create.return_value = SimpleNamespace(
                data=[SimpleNamespace(embedding=vector)])
            result = asyncio.run(embedder.embed(['synthetic query']))
            self.assertEqual(embedder.dimensions, 1536)
            self.assertEqual(len(result[0]), 1536)
            self.assertEqual(embedder._client.embeddings.create.call_args.kwargs[
                'dimensions'], 1536)

    def test_probe_goes_only_to_azure_and_pins_the_environment(self):
        with patch.dict(os.environ, azure_env(OPENAI_BASE_URL='https://api.openai.com/v1',
                                              OPENAI_API_KEY='fixture-other-key'),
                        clear=True):
            with patch.object(shared, 'build_opener') as factory:
                factory.return_value.open.return_value = BytesIO(json.dumps({
                    'data': [{'embedding': [0.2, -0.7]}]}).encode())
                shared.configure_remote_embedder()
                factory.assert_called_once()
                request = factory.return_value.open.call_args.args[0]
                self.assertEqual(request.full_url, AZURE_URL + 'embeddings')
                self.assertEqual(request.headers['Authorization'], f'Bearer {FIXTURE_KEY}')
                self.assertNotIn('fixture-other-key', str(request.headers))
                self.assertEqual(json.loads(request.data)['model'], 'text-embedding-3-small')
                self.assertEqual(os.environ['OPENAI_BASE_URL'], AZURE_URL.rstrip('/'))
                self.assertEqual(os.environ['OPENAI_API_KEY'], FIXTURE_KEY)
                self.assertEqual(os.environ['REPOWISE_EMBEDDER'], 'openai')
                self.assertEqual(os.environ['REPOWISE_EMBEDDING_MODEL'], 'text-embedding-3-small')
                self.assertEqual(os.environ['REPOWISE_EMBEDDING_DIMS'], '2')
                self.assertEqual(os.environ['REPOWISE_EMBEDDING_DECLARED_DIMS'], '2')

    def test_second_key_name_is_accepted_and_azure_openai_env_is_never_read(self):
        env = azure_env(AZURE_AI_SERVICES_KEY='fixture-services-key')
        env.pop('FOUNDRY_API_KEY')
        with patch.dict(os.environ, env, clear=True), \
                patch.object(shared, 'build_opener') as factory:
            factory.return_value.open.return_value = BytesIO(json.dumps({
                'data': [{'embedding': [0.2, -0.7]}]}).encode())
            shared.configure_remote_embedder()
            self.assertEqual(os.environ['OPENAI_API_KEY'], 'fixture-services-key')
        client_only = {'FOUNDRY_OPENAI_BASE_URL': AZURE_URL,
                       'FOUNDRY_EMBEDDING_DEPLOYMENT': 'text-embedding-3-small',
                       'AZURE_OPENAI_API_KEY': 'fixture-client-key',
                       'AZURE_OPENAI_ENDPOINT': 'https://client-pndh.openai.azure.com/'}
        with patch.dict(os.environ, client_only, clear=True), \
                patch.object(shared, 'build_opener') as factory:
            with self.assertRaises(ValueError):
                shared.configure_remote_embedder()
            factory.assert_not_called()

    def test_missing_environment_is_rejected_without_network(self):
        for missing in ('FOUNDRY_OPENAI_BASE_URL', 'FOUNDRY_API_KEY',
                        'FOUNDRY_EMBEDDING_DEPLOYMENT'):
            env = azure_env()
            env.pop(missing)
            with self.subTest(missing=missing), patch.dict(os.environ, env, clear=True), \
                    patch.object(shared, 'build_opener') as factory:
                with self.assertRaises(ValueError) as error:
                    shared.configure_remote_embedder()
                self.assertNotIn(FIXTURE_KEY, str(error.exception))
                factory.assert_not_called()

    def test_other_hosts_and_credential_urls_are_rejected_without_network(self):
        for url in ('https://api.openai.com/v1',
                    'http://aoai-mrender-4e123a95.openai.azure.com/openai/v1',
                    'https://aoai.openai.azure.com.evil.test/openai/v1',
                    'https://evil-openai.azure.com/openai/v1x',
                    'https://pndh-aoai.openai.azure.com/openai/v1',
                    'https://.openai.azure.com/openai/v1',
                    'https://aoai-mrender-4e123a95.openai.azure.com:8443/openai/v1',
                    'https://u:p@aoai-mrender-4e123a95.openai.azure.com/openai/v1',
                    'https://aoai-mrender-4e123a95.openai.azure.com/openai/v1?api-version=x',
                    'https://aoai-mrender-4e123a95.openai.azure.com/openai/other',
                    'https://127.0.0.1/openai/v1'):
            with self.subTest(url=url), \
                    patch.dict(os.environ, azure_env(FOUNDRY_OPENAI_BASE_URL=url), clear=True), \
                    patch.object(shared, 'build_opener') as factory:
                with self.assertRaises(ValueError) as error:
                    shared.configure_remote_embedder()
                self.assertNotIn(FIXTURE_KEY, str(error.exception))
                factory.assert_not_called()

    def test_failure_or_bad_vectors_fail_closed_and_preserve_environment(self):
        for payload in ({}, {'data': [{'embedding': [0, 0]}]},
                        {'data': [{'embedding': [float('nan'), 1]}]},
                        {'data': [{'embedding': ['secret', 1]}]}):
            with self.subTest(payload=payload), patch.dict(os.environ, azure_env(), clear=True):
                with patch.object(shared, 'build_opener') as factory:
                    factory.return_value.open.return_value = BytesIO(json.dumps(payload).encode())
                    with self.assertRaisesRegex(RuntimeError, 'refusing to serve'):
                        shared.configure_remote_embedder()
                    self.assertNotIn('OPENAI_BASE_URL', os.environ)
                    self.assertNotIn('OPENAI_API_KEY', os.environ)
        with patch.dict(os.environ, azure_env(), clear=True), \
                patch.object(shared, 'build_opener', side_effect=RuntimeError('private-response')):
            with self.assertRaises(RuntimeError) as error:
                shared.configure_remote_embedder()
            self.assertNotIn('private-response', str(error.exception))
            self.assertNotIn(FIXTURE_KEY, str(error.exception))

    def test_check_embedder_exits_2_without_starting_a_server(self):
        argv = ['shared_server.py', 'unused-workspace', '--check-embedder']
        with patch.dict(os.environ, {}, clear=True), patch.object(shared.sys, 'argv', argv):
            with self.assertRaises(SystemExit) as stop:
                shared.main()
            self.assertEqual(stop.exception.code, 2)
        with patch.dict(os.environ, azure_env(), clear=True), \
                patch.object(shared.sys, 'argv', argv), \
                patch.object(shared, 'build_opener') as factory:
            factory.return_value.open.return_value = BytesIO(json.dumps({
                'data': [{'embedding': [0.2, -0.7]}]}).encode())
            self.assertIsNone(shared.main())


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
