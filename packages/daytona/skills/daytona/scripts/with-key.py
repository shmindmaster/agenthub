"""Run one Daytona job with an explicitly selected credential, without persistence."""
import argparse
import os
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", choices=("DAYTONA_API_KEY", "DAYTONA_API_KEY1"),
                        default="DAYTONA_API_KEY")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("provide a command after --")
    key = os.environ.get(args.key)
    if not key or not key.strip():
        parser.error(f"{args.key} is unavailable; no other key was selected")
    env = os.environ.copy()
    env["DAYTONA_API_KEY"] = key
    # Pin the selected reference for receipts; never log the value.
    env["DAYTONA_KEY_REF"] = args.key
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        return subprocess.call(command, env=env, creationflags=flags)
    except OSError:
        print("Could not start the requested Daytona job", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
