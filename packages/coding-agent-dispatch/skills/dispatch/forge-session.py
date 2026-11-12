"""List or open a native operator session from a terminal already on Forge."""

import argparse
import json
import os
from pathlib import Path
import pwd
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true")
    mode.add_argument("--host")
    parser.add_argument("--cwd")
    args = parser.parse_args()
    home = Path("/srv/work/agenthub-runner")
    identity = pwd.getpwuid(os.getuid())
    if identity.pw_name != "agenthub-runner" or Path(identity.pw_dir) != home:
        parser.error("run on Forge as agenthub-runner")
    catalog = json.loads(Path(__file__).with_name("forge-hosts.json").read_text(encoding="utf-8"))
    if args.list:
        if args.cwd:
            parser.error("--list does not take --cwd")
        for host, route in catalog.items():
            executable = home / route["argv"][0]
            status = "interactive; installed, auth unverified" if os.access(executable, os.X_OK) else "refused; executable absent"
            print(f"{host}\t{status}")
        return
    if args.host not in catalog:
        parser.error("select a host from --list; Claude and Codex require a plan suffix")
    if not args.cwd or not re.fullmatch(r"/srv/work/agenthub-runner/worktrees/[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*", args.cwd):
        parser.error("--cwd must name a worktree under /srv/work/agenthub-runner/worktrees")
    cwd = Path(args.cwd)
    if not cwd.is_dir() or cwd.resolve() != cwd:
        parser.error("worktree must exist and use its physical path")
    if not all(stream.isatty() for stream in (sys.stdin, sys.stdout)):
        parser.error("open a terminal or attach a tmux pane for an interactive session")
    binary, *flags = catalog[args.host]["argv"]
    executable = home / binary
    if not os.access(executable, os.X_OK):
        parser.error(f"launcher is not installed for {args.host}")
    os.chdir(cwd)
    os.execve(executable, [str(executable), *flags], {
        "HOME": str(home),
        "PATH": f"{home}/.local/bin:/usr/bin:/bin",
        "TERM": os.environ.get("TERM") or "xterm-256color",
    })


if __name__ == "__main__":
    main()
