"""Exercise independent MCP sessions against the real SDK ASGI transport."""
from contextlib import asynccontextmanager
import importlib.util
import json
from pathlib import Path
import unittest

from mcp.server.fastmcp import FastMCP, Context
from starlette.testclient import TestClient

spec = importlib.util.spec_from_file_location(
    'shared_server', Path(__file__).parents[1] / 'scripts/shared_server.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)


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
