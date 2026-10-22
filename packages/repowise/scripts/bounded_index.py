"""One local, index-only RepoWise update under an already-owned atomic lease."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from shared_server import configure_local_embedder
from source_fence import source_fence
from windows_job import LeaseRetentionError, free_memory, run

GIB = 1024**3
LEASE_OWNER = "AgentHub bounded RepoWise index"
# Terminate, reconcile and re-fence need time inside the caller's deadline.
CLEANUP_RESERVE_SECONDS = 30
# Distinct exit status: owned processes may still be alive, so the wrapper must
# leave the admission lease on disk for an operator.
LEASE_RETENTION_EXIT = 3


def require_lease(path: Path, token: str) -> None:
    if os.name == "nt":
        import ctypes as C
        from ctypes import wintypes as W
        import msvcrt
        kernel = C.WinDLL("kernel32", use_last_error=True)
        kernel.CreateFileW.argtypes = [
            W.LPCWSTR, W.DWORD, W.DWORD, C.c_void_p, W.DWORD, W.DWORD, W.HANDLE]
        kernel.CreateFileW.restype = W.HANDLE
        kernel.CloseHandle.argtypes = [W.HANDLE]
        kernel.CloseHandle.restype = W.BOOL
        # The parent owns DELETE access through DeleteOnClose. Ordinary Python
        # open() denies delete sharing and cannot read that live lease.
        handle = kernel.CreateFileW(str(path), 0x80000000, 7, None, 3, 0, None)
        if handle == C.c_void_p(-1).value:
            raise C.WinError(C.get_last_error())
        try:
            descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY)
        except Exception:
            kernel.CloseHandle(handle)
            raise
        with os.fdopen(descriptor, "r", encoding="utf-8-sig") as stream:
            body = stream.read(65537)
    else:
        body = path.read_text(encoding="utf-8-sig")
    if len(body) > 65536:
        raise ValueError("Admission lease exceeds its size limit")
    lease = json.loads(body)
    if (lease.get("pid") != os.getppid() or lease.get("token") != token
            or lease.get("owner") != LEASE_OWNER):
        raise RuntimeError("Admission lease is not owned by the calling parent")


def git_head(repo: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).strip()


def state_commit(repo: Path) -> str | None:
    path = repo / ".repowise" / "state.json"
    return json.loads(path.read_text(encoding="utf-8-sig")).get("last_sync_commit")


def remaining_seconds(limit: int, deadline: str | None) -> float:
    if not deadline:
        return limit
    end = datetime.fromisoformat(deadline.replace("Z", "+00:00"))
    if end.tzinfo is None:
        raise ValueError("Deadline must include a timezone")
    remaining = (end - datetime.now(timezone.utc)).total_seconds() - CLEANUP_RESERVE_SECONDS
    if remaining <= 0:
        raise RuntimeError("Admission deadline has passed")
    return min(limit, remaining)


def allowed_output_root() -> Path:
    """Receipts and raw child logs live only beneath %LOCALAPPDATA%\\AgentHub."""
    base = os.environ.get("LOCALAPPDATA")
    if not base:
        raise RuntimeError("LOCALAPPDATA is not set; cannot place receipts under AgentHub")
    return (Path(base) / "AgentHub").resolve()


def output_permitted(output: Path) -> bool:
    """True when the fully resolved output (junctions and symlinks followed) is
    strictly inside the AgentHub runtime root."""
    root = allowed_output_root()
    resolved = output.resolve()
    return resolved != root and resolved.is_relative_to(root)


def _editor_files_settings(text: str) -> dict:
    try:
        import yaml
    except ImportError:
        yaml = None
    if yaml is not None:
        value = (yaml.safe_load(text) or {}).get("editor_files") if text.strip() else None
        return value if isinstance(value, dict) else {}
    # Fallback for an interpreter without PyYAML: block or flow mapping only.
    settings = {}
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"editor_files:\s*(\{.*\})?\s*(#.*)?$", line)
        if not match:
            continue
        pairs = [(match.group(1) or "")]
        for follower in lines[index + 1:]:
            if follower.strip() and not follower.startswith((" ", "\t")):
                break
            pairs.append(follower)
        for key, value in re.findall(r"([A-Za-z_]+)\s*:\s*(true|false)\b", "\n".join(pairs), re.I):
            settings[key] = value.lower() == "true"
    return settings


def require_editor_files_opt_out(repo: Path) -> None:
    """Refuse a run whose child would rewrite managed instruction files.

    RepoWise 0.58.0's `update` regenerates `.claude/CLAUDE.md` unless
    `editor_files.claude_md` is false, and AGENTS.md when `editor_files.agents_md`
    is true. It has no per-run switch: `--no-agents` writes the opt-out into
    `.repowise/config.yaml`, which would leave the repository permanently
    configured. The regenerated block carries the indexed date and commit, so
    the source fence would reject the run after the write anyway. Fail closed
    before launch; the opt-out is an owner decision made outside this run.
    """
    config = repo / ".repowise" / "config.yaml"
    text = config.read_text(encoding="utf-8-sig") if config.is_file() else ""
    settings = _editor_files_settings(text)
    if settings.get("claude_md") is not False or settings.get("agents_md") is True:
        raise RuntimeError(
            "Refusing: this RepoWise update regenerates managed instruction files with no "
            "per-run opt-out (--no-agents would rewrite .repowise/config.yaml). The "
            "repository's config must already set editor_files.claude_md: false and not "
            "enable editor_files.agents_md; set that deliberately outside this run.")


def validate_paths(workspace: Path, repo: Path, output: Path) -> None:
    if not (workspace / ".repowise-workspace.yaml").is_file():
        raise RuntimeError("Expected an existing RepoWise workspace")
    if not repo.is_relative_to(workspace) or repo == workspace:
        raise RuntimeError("Repository must be a member below the workspace")
    root = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "--show-toplevel"], text=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).strip()
    if Path(root).resolve() != repo:
        raise RuntimeError("Repository must be its own Git root")
    if output.is_relative_to(workspace):
        raise RuntimeError("Receipts must be outside the source workspace")
    if not output_permitted(output):
        raise RuntimeError("Receipts must be beneath the AgentHub runtime root (%LOCALAPPDATA%\\AgentHub)")
    if not (repo / ".repowise" / "state.json").is_file():
        raise RuntimeError("Refusing initialization: an existing index is required")


def write_admission_failure(workspace: Path, output: Path, error: Exception) -> None:
    """Leave a minimal non-accepted receipt for a failure before the job began.

    Only the exception class is recorded: messages can carry repository names.
    Receipts never go into the source workspace and never overwrite a prior one.
    """
    try:
        if output.is_relative_to(workspace) or not output_permitted(output):
            return
        output.mkdir(parents=True, exist_ok=True)
        with (output / "acceptance.json").open("x", encoding="utf-8") as stream:
            json.dump({"accepted": False, "failure": type(error).__name__,
                       "stage": "admission"}, stream)
    except OSError:
        pass


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--lease", type=Path, required=True)
    parser.add_argument("--lease-token", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--memory-gib", type=int, choices=range(1, 9), default=8)
    parser.add_argument("--timeout-seconds", type=int, choices=range(1, 901), default=900)
    parser.add_argument("--minimum-free-gib", type=float, default=8)
    parser.add_argument("--deadline")
    args = parser.parse_args(argv)
    if not 4 <= args.minimum_free_gib <= 64:
        raise ValueError("At least 4 GiB free physical RAM is required")
    workspace, repo, output = (p.resolve() for p in
                               (args.workspace, args.repo_root, args.output))
    try:
        require_lease(args.lease, args.lease_token)
        remaining_seconds(args.timeout_seconds, args.deadline)
        validate_paths(workspace, repo, output)
        require_editor_files_opt_out(repo)
        if free_memory() <= args.minimum_free_gib * GIB:
            raise RuntimeError("Insufficient free physical RAM; child not started")
        executable = shutil.which("repowise")
        if not executable:
            raise RuntimeError("Existing RepoWise CLI not found; refusing installation")
        output.mkdir(parents=True, exist_ok=False)
        receipt = {"accepted": False, "headBefore": git_head(repo),
                   "lastSyncCommitBefore": state_commit(repo),
                   "sourceBefore": source_fence(repo), "mode": "index-only"}
    except Exception as error:
        write_admission_failure(workspace, output, error)
        raise
    receipt_error = None
    try:
        # Reuse the shared server's loopback-only validation and actual embedding
        # probe. Never inherit a paid endpoint or forward a real key locally.
        configure_local_embedder("http://127.0.0.1:8790/v1", "text-embedding-3-small")
        require_lease(args.lease, args.lease_token)
        result = run(
            [executable, "update", "--no-workspace", "--index-only",
             "--concurrency", "1", "--progress", "json"],
            cwd=repo, output=output / "child",
            memory_bytes=args.memory_gib * GIB,
            timeout_seconds=remaining_seconds(args.timeout_seconds, args.deadline),
            minimum_free_bytes=int(args.minimum_free_gib * GIB),
            environment=dict(os.environ), parent_pid=os.getppid())
        receipt["child"] = result
    except BaseException as error:
        receipt["failure"] = type(error).__name__
        raise
    finally:
        # No source rollback: concurrent/user changes are preserved and make
        # acceptance fail. The Job Object reconciles only its own descendants.
        try:
            receipt.update(headAfter=git_head(repo), lastSyncCommitAfter=state_commit(repo),
                           sourceAfter=source_fence(repo))
        except Exception as error:
            receipt.setdefault("failure", type(error).__name__)
        child = receipt.get("child", {})
        receipt["accepted"] = (
            "failure" not in receipt
            and child.get("exitCode") == 0 and child.get("reason") == "exited"
            and child.get("activeProcessesBeforeCleanup") == 0
            and child.get("activeProcessesAfterCleanup") == 0
            and receipt["headBefore"] == receipt.get("headAfter")
            and receipt["sourceBefore"] == receipt.get("sourceAfter")
            and receipt.get("lastSyncCommitAfter") == receipt.get("headAfter"))
        try:
            (output / "acceptance.json").write_text(
                json.dumps(receipt, indent=2), encoding="utf-8")
        except OSError as write_error:
            # A receipt failure must never mask an in-flight failure (notably
            # LeaseRetentionError, which keeps the lease on disk): report it,
            # then let the original exception continue.
            receipt_error = write_error
            print(f"Could not write acceptance.json ({type(write_error).__name__}).",
                  file=sys.stderr)
    if receipt_error is not None:
        return 1
    print(json.dumps({"accepted": receipt["accepted"],
                      "receipt": str(output / "acceptance.json")}))
    return 0 if receipt["accepted"] else 1


def cli(argv=None) -> int:
    try:
        return main(argv)
    except LeaseRetentionError:
        # Owned processes may still be alive: the wrapper must keep the lease.
        print("Owned processes were not proven gone; keep the admission lease.", file=sys.stderr)
        return LEASE_RETENTION_EXIT
    except Exception:
        # Raw CLI output is restricted to the external job folder. Exceptions
        # may contain repository names or provider response data.
        print("Bounded indexing failed; inspect the external receipt/logs.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(cli())
