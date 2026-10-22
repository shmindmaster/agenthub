"""Read-only content fence for Git-visible source and known agent config paths."""
from hashlib import sha256
import os
from pathlib import Path
import subprocess


def source_fence(repo: Path) -> dict:
    def git(*args):
        return subprocess.check_output(["git", "--no-optional-locks", "-C", str(repo), *args],
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    names = set(git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0"))
    names.discard(b"")
    names.update(os.fsencode(name) for name in
                 (".vscode/mcp.json", ".mcp.json", "AGENTS.md", "CLAUDE.md",
                  ".claude/CLAUDE.md", ".repowise/config.yaml"))
    digest = sha256(git("status", "--porcelain=v1", "-z", "--untracked-files=all"))
    staged = git("ls-files", "--stage", "-z")
    digest.update(staged)
    gitlinks = {}
    for entry in staged.split(b"\0"):
        meta, _, name = entry.partition(b"\t")
        fields = meta.split()
        if len(fields) == 3 and fields[0] == b"160000":
            gitlinks[name] = fields[1]
    for name in sorted(names):
        path = repo / os.fsdecode(name)
        content = sha256()
        if name in gitlinks:
            # A submodule is a directory in the work tree but a commit in the
            # index: fence the recorded gitlink commit and what is checked out.
            kind = b"gitlink"
            content.update(gitlinks[name] + b"\0")
            if (path / ".git").exists():
                content.update(subprocess.check_output(
                    ["git", "--no-optional-locks", "-C", str(path), "rev-parse", "HEAD"],
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).strip())
            else:
                content.update(b"uninitialized")
        elif path.is_symlink():
            kind = b"symlink"
            content.update(os.fsencode(os.readlink(path)))
        elif path.is_file():
            kind = b"file"
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    content.update(chunk)
        elif not path.exists():
            kind = b"absent"
        else:
            raise RuntimeError("Unsupported Git source entry; no indexing acceptance permitted")
        digest.update(name + b"\0" + kind + b"\0" + content.digest())
    return {"sha256": digest.hexdigest(), "entries": len(names),
            "scope": "tracked, nonignored untracked, known agent config and index configuration"}
