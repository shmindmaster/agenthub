import asyncio
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / 'skills/use-arxiv-research/scripts'
sys.path.insert(0, str(SCRIPTS))
import arxiv_client as client


class LockTests(unittest.TestCase):
    def test_another_process_is_denied_and_release_allows_next_session(self):
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / 'session.lock'
            code = 'import sys; from pathlib import Path; from arxiv_client import session_lock;\nwith session_lock(Path(sys.argv[1])): print("admitted")'
            env = {**os.environ, 'PYTHONPATH':str(SCRIPTS), 'PYTHONDONTWRITEBYTECODE':'1'}
            kwargs = {'capture_output':True, 'text':True, 'env':env, 'timeout':10}
            if os.name == 'nt':
                kwargs['creationflags'] = subprocess.CREATE_NO_WINDOW
            with client.session_lock(lock):
                denied = subprocess.run([sys.executable,'-c',code,str(lock)], **kwargs)
                self.assertNotEqual(denied.returncode, 0)
                self.assertIn('shared lock', denied.stderr)
            allowed = subprocess.run([sys.executable,'-c',code,str(lock)], **kwargs)
            self.assertEqual(allowed.returncode, 0, allowed.stderr)
            self.assertIn('admitted', allowed.stdout)

    def test_invalid_or_empty_plan_is_rejected(self):
        for plan in ([], {}, [{'operation':'invented'}], [{'operation':'call'}], [{'operation':'tools','arguments':[]}], [{}] * 31):
            with self.subTest(plan=plan), self.assertRaises(client.ResearchError):
                client.validate_plan(plan)


@unittest.skipUnless(importlib.util.find_spec('mcp'), 'Install the pinned MCP environment for protocol/lifecycle tests')
class ProtocolTests(unittest.TestCase):
    def invoke(self, plan, timeout=12):
        from mcp import StdioServerParameters
        params = StdioServerParameters(command=sys.executable, args=[str(Path(__file__).with_name('server_fixture.py'))])
        with tempfile.TemporaryFile(mode='w+', encoding='utf-8') as log:
            return asyncio.run(client.execute(plan, params, log, timeout))

    def test_real_stdio_discovery_and_tool_call(self):
        payload = self.invoke([{'operation':'tools'},{'operation':'call','name':'identify'}])
        self.assertTrue(payload['ok'])
        self.assertIn('identify', [item['name'] for item in payload['results'][0]['result']['tools']])
        self.assertIn('fixture', payload['results'][1]['result']['content'][0]['text'])

    def test_tool_failure_is_not_success_and_stops_the_plan(self):
        payload = self.invoke([{'operation':'call','name':'fail'},{'operation':'call','name':'identify'}])
        self.assertFalse(payload['ok'])
        self.assertEqual(len(payload['results']), 1)
        self.assertTrue(payload['results'][0]['result']['isError'])

    def test_deadline_rejects_hung_server(self):
        import time
        started = time.monotonic()
        with self.assertRaises((TimeoutError, BaseExceptionGroup)):
            self.invoke([{'operation':'call','name':'wait'}], timeout=2)
        self.assertLess(time.monotonic() - started, 10)


if __name__ == '__main__':
    unittest.main(verbosity=2)
