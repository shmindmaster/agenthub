"""Read-only Codex SessionStart index check; stdlib only, never refreshes indexes."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys

WORKSPACE = Path("C:/Repos")
MAX_CONTEXT = 600
MAX_INPUT = 65536
MAX_STATE = 2 * 1024 * 1024


def git(root: Path, *args: str) -> str:
    env = os.environ.copy()
    env["GIT_OPTIONAL_LOCKS"] = "0"
    result = subprocess.run(
        ["git", "--no-optional-locks", "-c", "core.fsmonitor=false", "-C", str(root), *args],
        capture_output=True, text=True, timeout=1, check=True, env=env,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    return result.stdout.strip()


def context(payload: object, workspace: Path = WORKSPACE) -> str | None:
    if not isinstance(payload, dict) or payload.get("hook_event_name") != "SessionStart":
        return None
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd or not Path(cwd).is_absolute():
        return None
    boundary, current = workspace.resolve(), Path(cwd).resolve()
    if not current.is_relative_to(boundary) or not current.is_dir():
        return None
    if current == boundary:
        if (boundary / ".repowise-workspace" / "workspace.db").is_file():
            return "[RepoWise] Workspace index is present. Member repository freshness was not checked. No server or refresh was started."
        return None
    root = current
    while not (root / ".git").exists():
        if root == boundary:
            return None
        root = root.parent
    state_path = root / ".repowise" / "state.json"
    if not state_path.is_file():
        return None
    with state_path.open(encoding="utf-8-sig") as state_file:
        raw_state = state_file.read(MAX_STATE + 1)
    if len(raw_state) > MAX_STATE:
        return None
    state = json.loads(raw_state)
    indexed = state.get("last_sync_commit") if isinstance(state, dict) else None
    if not isinstance(indexed, str) or not re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", indexed):
        return None
    head = git(root, "rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", head):
        return None
    dirty = bool(git(root, "status", "--porcelain=v1", "--untracked-files=no"))
    status = "matches HEAD" if indexed.lower() == head.lower() else "differs from HEAD; indexed context may be stale"
    tree = "Tracked working tree has changes; index coverage of them is unknown." if dirty else "Tracked working tree is clean."
    return (f"[RepoWise] Recorded index commit {status}. {tree} Index availability and coverage are unverified. Untracked files were not checked. "
            "Verify indexed claims against source; refresh only through Invoke-RepoWiseBoundedIndex.ps1 when needed. "
            "No server or refresh was started.")[:MAX_CONTEXT]


def main() -> None:
    try:
        raw = sys.stdin.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            return
        message = context(json.loads(raw))
        if message:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "SessionStart", "additionalContext": message[:MAX_CONTEXT]
            }}))
    except (OSError, ValueError, subprocess.SubprocessError):
        pass  # Invalid input, unavailable metadata or git must never block Codex.


if __name__ == "__main__":
    main()
