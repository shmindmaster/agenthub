#!/usr/bin/env python3
"""Prepare isolated, on-demand Clerk CLI management configuration.

No host, browser, model, login, or credential store is started or accessed.
The default only describes the plan. --apply creates exact private config files;
it never edits global host settings or the installed vendor plugin.
"""
import argparse
import json
import os
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def canonical_url():
    registry = json.loads((REPO / "registry/mcps.json").read_text(encoding="utf-8-sig"))
    rows = [row for row in registry["mcpServers"] if row["id"] == "clerk"]
    if len(rows) != 1 or rows[0].get("transport") != "http" or rows[0].get("credentialPolicy") != "oauth":
        raise RuntimeError("Expected one canonical remote OAuth Clerk server")
    url = rows[0]["url"]
    if url != "https://mcp.clerk.com/mcp":
        raise RuntimeError("Unexpected Clerk endpoint; review vendor ownership first")
    return url


def layout(runtime, host):
    root = Path(runtime).absolute() / "clerk" / "management"
    url = canonical_url()
    if host == "cursor":
        cwd = root / "cursor"
        path = cwd / ".cursor" / "mcp.json"
        config = {"mcpServers": {"clerk": {"url": url}}}
        commands = [["cursor-agent", "mcp", "enable", "clerk"],
                    ["cursor-agent", "mcp", "login", "clerk"],
                    ["cursor-agent", "mcp", "list-tools", "clerk"]]
    elif host == "amp":
        cwd = root / "amp"
        path = cwd / "settings.json"
        config = {"amp.mcpServers": {"clerk": {"url": url}}}
        base = ["amp", "--settings-file", str(path)]
        commands = [base + ["mcp", "oauth", "status", "clerk"],
                    base + ["mcp", "doctor", "clerk"]]
    else:
        raise ValueError("Only Cursor and Amp need this isolated management bridge")
    return {"host": host, "cwd": str(cwd), "configPath": str(path), "config": config,
            "commands": commands, "execution": "not-started", "oauth": "not-verified",
            "loginBlocker": ("Amp's local mcp oauth login requires a vendor-supported client ID, "
                             "and an arbitrary ID or another host's token is not a repair. Use Amp's own "
                             "personal remote server instead: amp mcp remote check Clerk --personal. "
                             "Measured 2026-11-05 it reports connected with 29 tools, so this host is not "
                             "blocked; the isolated local directory below is a second, optional route."
                             if host == "amp" else None),
            "scope": "isolated CLI management; does not prove IDE plugin authentication"}


def prepare(plan):
    path = Path(plan["configPath"])
    # Check every existing ancestor, including runtime roots; do not follow links
    # into global settings, another owner's directory, or a credential store.
    for item in (path, *path.parents):
        if item.is_symlink() or (hasattr(item, "is_junction") and item.is_junction()):
            raise RuntimeError("Refusing linked management destination")
    expected = plan["config"]
    if path.exists():
        if json.loads(path.read_text(encoding="utf-8-sig")) != expected:
            raise RuntimeError("Management config differs; preserving existing file")
        return "unchanged"
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive create also preserves a file installed concurrently.
    with path.open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(expected, indent=2) + "\n")
    return "created"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", choices=("cursor", "amp"), required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        parser.error("LOCALAPPDATA is required; no repository/global config fallback")
    plan = layout(Path(local) / "AgentHub", args.host)
    plan["result"] = prepare(plan) if args.apply else "plan-only"
    print(json.dumps(plan, indent=2))


if __name__ == "__main__":
    main()
