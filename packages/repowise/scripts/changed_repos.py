"""List the RepoWise workspace entries whose indexed files moved. Read-only.

An entry is a folder, and a monorepo holds several, so a commit only counts for
the entry whose folder it touched. Prints JSON; never opens file contents.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys

MEMBER_PATH = re.compile(r"^\s*-?\s*path:\s*['\"]?([^'\"\n#]+?)['\"]?\s*$", re.M)


def workspace_members(workspace: Path) -> list[Path]:
    text = (workspace / ".repowise-workspace.yaml").read_text(encoding="utf-8-sig")
    return [(workspace / found.strip()).resolve() for found in MEMBER_PATH.findall(text)]


def git(repo: Path, *args: str) -> str | None:
    result = subprocess.run(["git", "--no-optional-locks", "-C", str(repo), *args],
                            capture_output=True, text=True, encoding="utf-8", errors="replace",
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    return result.stdout.strip() if result.returncode == 0 else None


def classify(repo: Path) -> dict:
    entry = {"path": str(repo)}
    if not repo.is_dir():
        return {**entry, "status": "missing"}
    state = repo / ".repowise" / "state.json"
    if not state.is_file():
        return {**entry, "status": "not-indexed"}
    try:
        synced = json.loads(state.read_text(encoding="utf-8-sig")).get("last_sync_commit")
    except (OSError, ValueError, AttributeError):
        return {**entry, "status": "attention", "reason": "state.json is unreadable"}
    head = git(repo, "rev-parse", "HEAD")
    if not head or not synced:
        return {**entry, "status": "attention", "reason": "no commit to compare"}
    if head == synced:
        return {**entry, "status": "unchanged"}
    if git(repo, "cat-file", "-e", f"{synced}^{{commit}}") is None:
        return {**entry, "status": "attention", "reason": "last sync commit is not in this clone"}
    names = git(repo, "diff", "--relative", "--name-only", f"{synced}..{head}", "--", ".")
    if names is None:
        return {**entry, "status": "attention", "reason": "git diff failed"}
    files = len(names.splitlines())
    if not files:
        return {**entry, "status": "unchanged"}
    return {**entry, "status": "changed", "files": files}


def survey(workspace: Path) -> dict:
    entries = [classify(repo) for repo in workspace_members(workspace)]
    changed = sorted((item for item in entries if item["status"] == "changed"),
                     key=lambda item: item["files"])
    return {"entries": len(entries), "counts": dict(Counter(item["status"] for item in entries)),
            "changed": changed,
            "other": [item for item in entries if item["status"] not in ("changed", "unchanged")]}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    args = parser.parse_args(argv)
    print(json.dumps(survey(args.workspace.resolve())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
