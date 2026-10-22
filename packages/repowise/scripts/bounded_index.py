"""One local, index-only RepoWise update under an already-owned atomic lease."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from shared_server import configure_local_embedder
from source_fence import source_fence
from windows_job import free_memory, run

GIB = 1024**3
LEASE_OWNER = "AgentHub bounded RepoWise index"


def require_lease(path: Path, token: str) -> None:
    lease = json.loads(path.read_text(encoding="utf-8-sig"))
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
    remaining = (end - datetime.now(timezone.utc)).total_seconds()
    if remaining <= 0:
        raise RuntimeError("Admission deadline has passed")
    return min(limit, remaining)


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
    if not (repo / ".repowise" / "state.json").is_file():
        raise RuntimeError("Refusing initialization: an existing index is required")


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
    require_lease(args.lease, args.lease_token)
    remaining_seconds(args.timeout_seconds, args.deadline)
    validate_paths(workspace, repo, output)
    if free_memory() <= args.minimum_free_gib * GIB:
        raise RuntimeError("Insufficient free physical RAM; child not started")
    executable = shutil.which("repowise")
    if not executable:
        raise RuntimeError("Existing RepoWise CLI not found; refusing installation")
    output.mkdir(parents=True, exist_ok=False)
    receipt = {"accepted": False, "headBefore": git_head(repo),
               "lastSyncCommitBefore": state_commit(repo),
               "sourceBefore": source_fence(repo), "mode": "index-only"}
    try:
        # Reuse the shared server's loopback-only validation and actual embedding
        # probe. Never inherit a paid endpoint or forward a real key locally.
        configure_local_embedder("http://127.0.0.1:8790/v1", "text-embedding-3-small")
        require_lease(args.lease, args.lease_token)
        result = run(
            [executable, "update", "--no-workspace", "--index-only",
             "--concurrency", "1", "--no-agents", "--progress", "json"],
            cwd=repo, output=output / "child",
            memory_bytes=args.memory_gib * GIB,
            timeout_seconds=remaining_seconds(args.timeout_seconds, args.deadline),
            minimum_free_bytes=int(args.minimum_free_gib * GIB),
            environment=dict(os.environ))
        receipt["child"] = result
    finally:
        # No source rollback: concurrent/user changes are preserved and make
        # acceptance fail. The Job Object reconciles only its own descendants.
        receipt.update(headAfter=git_head(repo), lastSyncCommitAfter=state_commit(repo),
                       sourceAfter=source_fence(repo))
        child = receipt.get("child", {})
        receipt["accepted"] = (
            child.get("exitCode") == 0 and child.get("reason") == "exited"
            and child.get("activeProcessesAfterCleanup") == 0
            and receipt["headBefore"] == receipt["headAfter"]
            and receipt["sourceBefore"] == receipt["sourceAfter"]
            and receipt["lastSyncCommitAfter"] == receipt["headAfter"])
        (output / "acceptance.json").write_text(
            json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps({"accepted": receipt["accepted"],
                      "receipt": str(output / "acceptance.json")}))
    return 0 if receipt["accepted"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Raw CLI output is restricted to the external job folder. Exceptions
        # may contain repository names or provider response data.
        print("Bounded indexing failed; inspect the external receipt/logs.", file=sys.stderr)
        sys.exit(1)
