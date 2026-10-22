"""Run one hidden Windows process tree within kernel-enforced resource limits.

The child is created suspended and assigned before its first instruction. Closing
the job terminates descendants, including on cancellation or parent failure.
No pre-existing process is ever assigned to this job.
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
import os
from pathlib import Path
import subprocess
import time


class LeaseRetentionError(RuntimeError):
    """Owned processes may still be alive: the caller must keep its admission lease."""


class Limits(C.Structure):
    _fields_ = [("ProcessTime", C.c_int64), ("JobTime", C.c_int64),
                ("Flags", W.DWORD), ("MinWorkingSet", C.c_size_t),
                ("MaxWorkingSet", C.c_size_t), ("ActiveProcesses", W.DWORD),
                ("Affinity", C.c_size_t), ("Priority", W.DWORD),
                ("Scheduling", W.DWORD)]


class ExtendedLimits(C.Structure):
    _fields_ = [("Basic", Limits), ("Io", C.c_uint64 * 6),
                ("ProcessMemory", C.c_size_t), ("JobMemory", C.c_size_t),
                ("PeakProcessMemory", C.c_size_t), ("PeakJobMemory", C.c_size_t)]


class Startup(C.Structure):
    _fields_ = [("cb", W.DWORD), ("reserved", W.LPWSTR),
                ("desktop", W.LPWSTR), ("title", W.LPWSTR),
                ("x", W.DWORD), ("y", W.DWORD), ("width", W.DWORD),
                ("height", W.DWORD), ("charsX", W.DWORD), ("charsY", W.DWORD),
                ("fill", W.DWORD), ("flags", W.DWORD), ("show", W.WORD),
                ("reservedSize", W.WORD), ("reservedBytes", C.c_void_p),
                ("stdin", W.HANDLE), ("stdout", W.HANDLE), ("stderr", W.HANDLE)]


class ProcessInfo(C.Structure):
    _fields_ = [("process", W.HANDLE), ("thread", W.HANDLE),
                ("pid", W.DWORD), ("tid", W.DWORD)]


class MemoryStatus(C.Structure):
    _fields_ = [("length", W.DWORD), ("load", W.DWORD)] + [
        (name, C.c_uint64) for name in
        ("totalPhysical", "availablePhysical", "totalPage", "availablePage",
         "totalVirtual", "availableVirtual", "availableExtended")]


class Accounting(C.Structure):
    _fields_ = [(name, C.c_int64) for name in ("user", "kernel", "periodUser", "periodKernel")] + [
        (name, W.DWORD) for name in ("pageFaults", "totalProcesses", "activeProcesses", "terminatedProcesses")]


def free_memory() -> int:
    if os.name != "nt":
        raise OSError("Windows Job Objects are required")
    kernel = C.WinDLL("kernel32", use_last_error=True)
    memory = MemoryStatus(length=C.sizeof(MemoryStatus))
    if not kernel.GlobalMemoryStatusEx(C.byref(memory)):
        raise C.WinError(C.get_last_error())
    return memory.availablePhysical


def run(command: list[str], *, cwd: Path, output: Path, memory_bytes: int,
        timeout_seconds: float, minimum_free_bytes: int,
        environment: dict[str, str] | None = None,
        parent_pid: int | None = None) -> dict:
    """Run `command` in a Job Object. When `parent_pid` is given, the job is
    terminated as soon as that process exits, so the caller's lease can never
    outlive-or-undercut the work it protects."""
    if os.name != "nt":
        raise OSError("Windows Job Objects are required")
    if memory_bytes < 32 * 1024**2 or timeout_seconds <= 0:
        raise ValueError("Invalid resource limits")
    if free_memory() < minimum_free_bytes:
        raise RuntimeError("Free RAM below admission limit; child not started")
    import msvcrt
    kernel = C.WinDLL("kernel32", use_last_error=True)
    signatures = {
        "CreateJobObjectW": ([C.c_void_p, W.LPCWSTR], W.HANDLE),
        "SetInformationJobObject": ([W.HANDLE, C.c_int, C.c_void_p, W.DWORD], W.BOOL),
        "QueryInformationJobObject": ([W.HANDLE, C.c_int, C.c_void_p, W.DWORD, C.c_void_p], W.BOOL),
        "CreateProcessW": ([W.LPCWSTR, W.LPWSTR, C.c_void_p, C.c_void_p,
                            W.BOOL, W.DWORD, C.c_void_p, W.LPCWSTR,
                            C.POINTER(Startup), C.POINTER(ProcessInfo)], W.BOOL),
        "AssignProcessToJobObject": ([W.HANDLE, W.HANDLE], W.BOOL),
        "ResumeThread": ([W.HANDLE], W.DWORD),
        "WaitForSingleObject": ([W.HANDLE, W.DWORD], W.DWORD),
        "WaitForMultipleObjects": ([W.DWORD, C.POINTER(W.HANDLE), W.BOOL, W.DWORD], W.DWORD),
        "OpenProcess": ([W.DWORD, W.BOOL, W.DWORD], W.HANDLE),
        "GetExitCodeProcess": ([W.HANDLE, C.POINTER(W.DWORD)], W.BOOL),
        "TerminateProcess": ([W.HANDLE, W.UINT], W.BOOL),
        "TerminateJobObject": ([W.HANDLE, W.UINT], W.BOOL),
        "CloseHandle": ([W.HANDLE], W.BOOL),
    }
    for name, (arguments, result) in signatures.items():
        function = getattr(kernel, name)
        function.argtypes, function.restype = arguments, result

    def check(ok):
        if not ok:
            raise C.WinError(C.get_last_error())
        return ok

    parent = None
    if parent_pid is not None:
        parent = check(kernel.OpenProcess(0x00100000, False, parent_pid))  # SYNCHRONIZE
        if kernel.WaitForSingleObject(parent, 0) != 258:
            kernel.CloseHandle(parent)
            raise RuntimeError("Parent process already exited; child not started")
    output.mkdir(parents=True, exist_ok=False)
    job = check(kernel.CreateJobObjectW(None, None))
    info = ProcessInfo()
    assigned = False
    started = time.monotonic()
    def terminate_owned():
        check(kernel.TerminateJobObject(job, 124))
        if kernel.WaitForSingleObject(info.process, 10000) != 0:
            result["leaseRetained"] = True
            raise LeaseRetentionError("Owned process did not terminate; retain admission lease")

    def active_processes() -> int:
        accounting = Accounting()
        check(kernel.QueryInformationJobObject(job, 1, C.byref(accounting), C.sizeof(accounting), None))
        return accounting.activeProcesses

    result = {"startedUtc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "memoryLimitBytes": memory_bytes, "timeoutSeconds": timeout_seconds,
              "pid": None, "exitCode": None, "reason": "launch-failed", "peakJobBytes": 0}
    try:
        limits = ExtendedLimits()
        limits.Basic.Flags = 0x200 | 0x2000  # JOB_MEMORY | KILL_ON_JOB_CLOSE
        limits.JobMemory = memory_bytes
        check(kernel.SetInformationJobObject(job, 9, C.byref(limits), C.sizeof(limits)))
        installed = ExtendedLimits()
        check(kernel.QueryInformationJobObject(job, 9, C.byref(installed), C.sizeof(installed), None))
        if installed.JobMemory != memory_bytes or installed.Basic.Flags & 0x2200 != 0x2200:
            raise RuntimeError("Kernel did not install both memory and cleanup limits")
        result["installedMemoryLimitBytes"] = installed.JobMemory
        with open(os.devnull, "rb") as stdin, (output / "stdout.log").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
            handles = [msvcrt.get_osfhandle(f.fileno()) for f in (stdin, stdout, stderr)]
            for handle in handles:
                os.set_handle_inheritable(handle, True)
            startup = Startup(cb=C.sizeof(Startup), flags=0x100,
                              stdin=handles[0], stdout=handles[1], stderr=handles[2])
            env_buffer = None
            if environment is not None:
                pairs = [f"{key}={value}" for key, value in sorted(environment.items(), key=lambda pair: pair[0].upper())]
                env_buffer = C.create_unicode_buffer("\0".join(pairs) + "\0\0")
            try:
                check(kernel.CreateProcessW(command[0], C.create_unicode_buffer(subprocess.list2cmdline(command)),
                      None, None, True, 0x4 | 0x08000000 | 0x400,  # suspended, no window, unicode env
                      env_buffer, str(cwd), C.byref(startup), C.byref(info)))
            finally:
                for handle in handles:
                    os.set_handle_inheritable(handle, False)
            result["pid"] = info.pid
            check(kernel.AssignProcessToJobObject(job, info.process))
            assigned = True
            if kernel.ResumeThread(info.thread) == 0xFFFFFFFF:
                raise C.WinError(C.get_last_error())
            result["reason"] = "exited"
            with (output / "resource-samples.jsonl").open("w", encoding="utf-8") as samples:
                waitable = [info.process] + ([parent] if parent else [])
                waitables = (W.HANDLE * len(waitable))(*waitable)
                while True:
                    wait = kernel.WaitForMultipleObjects(len(waitable), waitables, False, 500)
                    if wait not in (0, 1, 258) or (wait == 1 and not parent):
                        raise C.WinError(C.get_last_error())
                    measured = ExtendedLimits()
                    check(kernel.QueryInformationJobObject(job, 9, C.byref(measured), C.sizeof(measured), None))
                    result["peakJobBytes"] = max(result["peakJobBytes"], measured.PeakJobMemory)
                    elapsed = time.monotonic() - started
                    available = free_memory()
                    samples.write(json.dumps({"elapsedSeconds": round(elapsed, 3), "peakJobBytes": measured.PeakJobMemory,
                                              "freePhysicalBytes": available, "stdoutBytes": stdout.tell()}) + "\n")
                    samples.flush()
                    if wait == 0:
                        break
                    if wait == 1:
                        result["reason"] = "parent-exited"
                        terminate_owned()
                        break
                    if elapsed >= timeout_seconds or available < minimum_free_bytes:
                        result["reason"] = "timeout" if elapsed >= timeout_seconds else "low-ram"
                        terminate_owned()
                        break
                exit_code = W.DWORD()
                check(kernel.GetExitCodeProcess(info.process, C.byref(exit_code)))
                result["exitCode"] = exit_code.value
    finally:
        retain = None
        try:
            # A failed assignment still leaves the owned child suspended: terminate it.
            if info.process and not assigned:
                kernel.TerminateProcess(info.process, 125)
                if kernel.WaitForSingleObject(info.process, 10000) != 0:
                    raise LeaseRetentionError("Owned process did not terminate; retain admission lease")
            if assigned:
                # A launcher can exit while a detached descendant keeps running.
                # Record that before the cleanup below hides it.
                settle = time.monotonic() + 0.25
                result["activeProcessesBeforeCleanup"] = active_processes()
                while result["activeProcessesBeforeCleanup"] and time.monotonic() < settle:
                    time.sleep(0.025)
                    result["activeProcessesBeforeCleanup"] = active_processes()
                # Reconcile the entire owned job before the caller releases its
                # heavy-work lease.
                check(kernel.TerminateJobObject(job, 125))
                deadline = time.monotonic() + 10
                while True:
                    if active_processes() == 0:
                        result["activeProcessesAfterCleanup"] = 0
                        break
                    if time.monotonic() >= deadline:
                        raise LeaseRetentionError("Owned descendants not reconciled; retain admission lease")
                    time.sleep(0.05)
        except Exception as error:
            # Never lose the receipt or leak handles; the caller must keep its
            # lease because the owned tree is not proven gone.
            result["cleanupError"] = type(error).__name__
            result["leaseRetained"] = True
            retain = error
        finally:
            for handle in (job, parent, info.thread, info.process):
                if handle:
                    kernel.CloseHandle(handle)
            result["elapsedSeconds"] = round(time.monotonic() - started, 3)
            (output / "receipt.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        if retain is not None:
            if isinstance(retain, LeaseRetentionError):
                raise retain
            raise LeaseRetentionError("Owned process tree not proven gone; retain admission lease") from retain
    return result
