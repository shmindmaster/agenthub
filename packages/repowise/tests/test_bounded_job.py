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

import ctypes
import windows_job
from windows_job import LeaseRetentionError, run


@unittest.skipUnless(os.name == 'nt', 'Windows Job Objects required')
class BoundedJobTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def wait_for_pid_file(self, name='descendant.pid'):
        path = self.root / name
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(path.exists(), 'fixture never recorded its descendant PID')
        return int(path.read_text())

    def assert_process_gone(self, pid):
        """Independent of the job's own accounting: ask the OS about the PID."""
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
        kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x00100000, 0, pid)  # SYNCHRONIZE
        if not handle:
            return  # no such process
        try:
            # Job accounting drops a process a moment before its handle is
            # signalled, so allow teardown a short, bounded grace period.
            self.assertEqual(kernel.WaitForSingleObject(handle, 3000), 0, f'descendant {pid} is still running')
        finally:
            kernel.CloseHandle(handle)

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
        parent.write_text("import subprocess,sys,time; p=subprocess.Popen([sys.executable, 'sleep.py']); open('descendant.pid','w').write(str(p.pid)); time.sleep(60)", encoding='utf-8')
        result = run([sys.executable, str(parent)], cwd=self.root, output=self.root/'run',
                     memory_bytes=256*1024**2, timeout_seconds=1, minimum_free_bytes=0)
        self.assertEqual(result['reason'], 'timeout')
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)
        self.assert_process_gone(self.wait_for_pid_file())
        self.assertLess(result['elapsedSeconds'], 12)

    def test_parent_exit_terminates_job(self):
        source = self.root/'sleep.py'
        source.write_text('import time; time.sleep(60)', encoding='utf-8')
        child = self.root/'child.py'
        child.write_text("import subprocess,sys,time; p=subprocess.Popen([sys.executable, 'sleep.py']); open('descendant.pid','w').write(str(p.pid)); time.sleep(60)", encoding='utf-8')
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
        self.assert_process_gone(self.wait_for_pid_file())
        self.assertLess(result['elapsedSeconds'], 12)

    def test_detached_grandchild_is_recorded_before_cleanup(self):
        (self.root/'sleep.py').write_text('import time; time.sleep(60)', encoding='utf-8')
        result = self.execute("import subprocess,sys; p=subprocess.Popen([sys.executable, 'sleep.py']); open('descendant.pid','w').write(str(p.pid))")
        self.assertEqual(result['exitCode'], 0)
        self.assertGreaterEqual(result['activeProcessesBeforeCleanup'], 1)
        self.assertEqual(result['activeProcessesAfterCleanup'], 0)
        self.assert_process_gone(self.wait_for_pid_file())

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

    def test_retention_error_survives_a_receipt_write_failure(self):
        real_write = Path.write_text
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

        def refuse(path, *args, **kwargs):
            if path.name == 'receipt.json':
                raise OSError('synthetic disk failure')
            return real_write(path, *args, **kwargs)

        with patch.object(windows_job.C, 'WinDLL', Failing), patch('pathlib.Path.write_text', refuse):
            with self.assertRaises(LeaseRetentionError):
                self.execute("print('done')")

    def test_low_ram_refuses_before_child(self):
        with self.assertRaisesRegex(RuntimeError, 'child not started'):
            run([sys.executable, '-c', "raise AssertionError('must not start')"],
                cwd=self.root, output=self.root/'run', memory_bytes=128*1024**2,
                timeout_seconds=1, minimum_free_bytes=2**63)
        self.assertFalse((self.root/'run').exists())


if __name__ == '__main__':
    unittest.main()
