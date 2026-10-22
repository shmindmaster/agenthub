import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))

"""Synthetic negative controls; does not invoke RepoWise or touch an index."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import windows_job
from windows_job import LeaseRetentionError, run


@unittest.skipUnless(os.name == 'nt', 'Windows Job Objects required')
class BoundedJobTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def execute(self, source, **kwargs):
        script = self.root / 'child.py'
        script.write_text(source, encoding='utf-8')
        return run([sys.executable, str(script)], cwd=self.root,
                   output=self.root/'run', memory_bytes=128*1024**2,
                   timeout_seconds=10, minimum_free_bytes=0, **kwargs)

    def test_success_redirection_argument_and_unicode_environment(self):
        result = self.execute("import os,sys; print(os.environ['SYNTHETIC_VALUE']); print('private diagnostic',file=sys.stderr)",
                              environment={**os.environ, 'SYNTHETIC_VALUE': 'synthetic Ω with spaces'})
        self.assertEqual(result['exitCode'], 0)
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)
        self.assertIn('synthetic', (self.root/'run/stdout.log').read_text())
        self.assertIn('private diagnostic', (self.root/'run/stderr.log').read_text())
        self.assertNotIn('SYNTHETIC_VALUE', (self.root/'run/receipt.json').read_text())

    def test_kernel_limit_blocks_allocation(self):
        result = self.execute("import json,sys\nx=[]\ntry:\n while len(x)<16: x.append(bytearray(16*1024**2))\nexcept MemoryError:\n print(json.dumps({'allocatedBytes':len(x)*16*1024**2}),flush=True)\n raise")
        self.assertNotEqual(result['exitCode'], 0)
        self.assertEqual(result['installedMemoryLimitBytes'], 128*1024**2)
        self.assertLess(json.loads((self.root/'run/stdout.log').read_text())['allocatedBytes'], 128*1024**2)
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)
        self.assertIn('MemoryError', (self.root/'run/stderr.log').read_text())

    def test_same_allocation_succeeds_with_larger_limit(self):
        source = self.root/'allocate.py'
        source.write_text("x=[bytearray(16*1024**2) for _ in range(16)]; print('allocated256MiB')", encoding='utf-8')
        result = run([sys.executable, str(source)], cwd=self.root, output=self.root/'run',
                     memory_bytes=384*1024**2, timeout_seconds=10, minimum_free_bytes=0)
        self.assertEqual(result['exitCode'], 0)
        self.assertIn('allocated256MiB', (self.root/'run/stdout.log').read_text())
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)

    def test_timeout_cleans_descendant(self):
        source = self.root/'sleep.py'
        source.write_text('import time; time.sleep(60)', encoding='utf-8')
        parent = self.root/'parent.py'
        parent.write_text("import subprocess,sys,time; subprocess.Popen([sys.executable, 'sleep.py']); time.sleep(60)", encoding='utf-8')
        result = run([sys.executable, str(parent)], cwd=self.root, output=self.root/'run',
                     memory_bytes=256*1024**2, timeout_seconds=1, minimum_free_bytes=0)
        self.assertEqual(result['reason'], 'timeout')
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)
        self.assertLess(result['elapsedSeconds'], 12)

    def test_parent_exit_terminates_job(self):
        source = self.root/'sleep.py'
        source.write_text('import time; time.sleep(60)', encoding='utf-8')
        child = self.root/'child.py'
        child.write_text("import subprocess,sys,time; subprocess.Popen([sys.executable, 'sleep.py']); time.sleep(60)", encoding='utf-8')
        parent = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(1.5)'],
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            result = run([sys.executable, str(child)], cwd=self.root, output=self.root/'run',
                         memory_bytes=256*1024**2, timeout_seconds=30, minimum_free_bytes=0,
                         parent_pid=parent.pid)
        finally:
            parent.kill()
            parent.wait()
        self.assertEqual(result['reason'], 'parent-exited')
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)
        self.assertLess(result['elapsedSeconds'], 12)

    def test_detached_grandchild_is_recorded_before_cleanup(self):
        (self.root/'sleep.py').write_text('import time; time.sleep(60)', encoding='utf-8')
        result = self.execute("import subprocess,sys; subprocess.Popen([sys.executable, 'sleep.py'])")
        self.assertEqual(result['exitCode'], 0)
        self.assertGreaterEqual(result['activeProcessesBeforeCleanup'], 1)
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)

    def test_clean_exit_records_no_active_processes_before_cleanup(self):
        result = self.execute("print('done')")
        self.assertEqual(result['activeProcessesBeforeCleanup'], 0)

    def test_failed_cleanup_keeps_receipt_and_demands_lease_retention(self):
        real = windows_job.C.WinDLL

        class Failing:
            def __init__(self, *args, **kwargs):
                self.kernel = real(*args, **kwargs)
                self.TerminateJobObject = self

            argtypes = restype = None

            def __getattr__(self, name):
                return getattr(self.kernel, name)

            def __call__(self, *args):
                return 0

        with patch.object(windows_job.C, 'WinDLL', Failing):
            with self.assertRaises(LeaseRetentionError):
                self.execute("print('done')")
        receipt = json.loads((self.root/'run/receipt.json').read_text())
        self.assertIn('cleanupError', receipt)
        self.assertTrue(receipt['leaseRetained'])

    def test_low_ram_refuses_before_child(self):
        with self.assertRaisesRegex(RuntimeError, 'child not started'):
            run([sys.executable, '-c', "raise AssertionError('must not start')"],
                cwd=self.root, output=self.root/'run', memory_bytes=128*1024**2,
                timeout_seconds=1, minimum_free_bytes=2**63)
        self.assertFalse((self.root/'run').exists())


if __name__ == '__main__':
    unittest.main()
