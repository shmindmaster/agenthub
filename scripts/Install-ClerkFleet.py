#!/usr/bin/env python3
"""Install Clerk's official plugin, never an AgentHub republication.

Default is a read-only plan. --apply installs only Clerk; no login, account
creation, secret resolution, removal, or coding-agent session is performed.
Runtime receipts distinguish installation from authenticated tool/session QA.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import hashlib
from datetime import datetime, timezone

REPO = Path(__file__).resolve().parents[1]
URL = "https://mcp.clerk.com/mcp"
NATIVE = {
    "claude": [["claude", "plugin", "marketplace", "add", "clerk/skills"],
               ["claude", "plugin", "install", "clerk@clerk-skills", "--scope", "user"]],
    "codex": [["codex", "plugin", "marketplace", "add", "clerk/skills"],
              ["codex", "plugin", "add", "clerk@clerk"]],
    "copilot": [["copilot", "plugin", "marketplace", "add", "clerk/skills"],
                ["copilot", "plugin", "install", "clerk@clerk-skills"]],
    "factory": [["droid", "plugin", "marketplace", "add", "clerk/skills"],
                ["droid", "plugin", "install", "clerk@skills", "--scope", "user"]],
    "qoder": [["qodercli", "plugins", "marketplace", "add", "https://github.com/clerk/skills"],
              ["qodercli", "plugins", "install", "clerk@clerk-skills", "--scope", "user"]],
    "devin": [["devin", "plugins", "install", "clerk/skills", "--yes", "--local"]],
    "grok": [["grok", "plugin", "install", "{upstream}", "--trust"]],
    "antigravity": [["agy", "plugin", "install", "{upstream}"]],
}
BRIDGES = {"cursor", "cline", "amp", "opencode", "warp", "gemini", "vscode-insiders"}
ALIASES = {"cursor-agent": "cursor", "opencode-desktop": "opencode",
           "antigravity-desktop": "antigravity", "antigravity-ide": "antigravity"}


def audit(upstream, home):
    patterns = {
        "claude": ".claude/plugins/cache/clerk-skills/clerk/*",
        "codex": ".codex/plugins/cache/clerk/clerk/*",
        "copilot": ".copilot/installed-plugins/clerk-skills/clerk",
        "factory": ".factory/plugins/cache/skills-*/clerk-*/*",
        "qoder": ".qoder/plugins/cache/clerk-skills/clerk/*",
        "grok": ".grok/installed-plugins/upstream-*",
        "antigravity": ".gemini/config/plugins/clerk",
        "cursor": ".cursor/plugins/local/clerk",
        "cline": ".agents/plugins/clerk",
        "amp": ".config/amp/plugins/clerk",
    }
    rows = {}
    # Native installers can normalize Git checkout line endings on Windows.
    expected = {p.parent.name: hashlib.sha256(p.read_text(encoding="utf-8").encode()).hexdigest()
                for p in (upstream / "skills").glob("*/SKILL.md")}
    for host in sorted(set(NATIVE) | BRIDGES):
        if host == "devin":
            roots = list((Path(os.environ["APPDATA"]) / "devin/cli/plugins/cache").glob("github.com_clerk_skills-*/*"))
        elif host == "vscode-insiders":
            roots = [home / patterns["copilot"]]
        elif host in patterns:
            roots = list(home.glob(patterns[host]))
        else:
            roots = [home / {"opencode": ".config/opencode", "warp": ".warp", "gemini": ".gemini"}[host]]
        matches = []
        for root in roots:
            if all((root / "skills" / name / "SKILL.md").is_file() and hashlib.sha256(
                (root / "skills" / name / "SKILL.md").read_text(encoding="utf-8").encode()).hexdigest() == digest
                   for name, digest in expected.items()):
                matches.append(root)
        remote = False
        for root in matches:
            for name in (".mcp.json", "mcp.json", "skills/clerk/mcp.json"):
                path = root / name
                if path.is_file() and has_remote(path):
                    remote = True
        direct = {
            "cline": home / ".cline/data/settings/cline_mcp_settings.json",
            "opencode": home / ".config/opencode/opencode.json",
            "warp": home / ".warp/.mcp.json",
            "gemini": home / ".gemini/settings.json",
            "vscode-insiders": Path(os.environ["APPDATA"]) / "Code - Insiders/User/mcp.json",
        }.get(host)
        if direct and direct.is_file():
            remote = has_remote(direct)
        rows[host] = {"matchingOfficialSkills": len(expected) if matches else 0,
                      "remoteConfigured": remote, "freshSession": "not verified",
                      "authenticatedMcp": "not verified"}
    for alias, host in ALIASES.items():
        rows[alias] = {**rows[host], "configurationOwner": host}
    return rows


def has_remote(path):
    data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    for key in ("mcpServers", "servers", "mcp"):
        if isinstance(data.get(key), dict):
            data = data[key]
            break
    entry = data.get("clerk", {})
    return entry.get("url", entry.get("httpUrl")) == URL


def run(args):
    executable = shutil.which(args[0])
    if not executable:
        raise RuntimeError(f"Executable unavailable: {args[0]}")
    # cmd wrappers require cmd.exe on Windows, without shell=True/string interpolation.
    command = [executable, *args[1:]]
    if os.name == "nt" and executable.lower().endswith((".cmd", ".bat")):
        command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", *command]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=180,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    # Do not persist command stdout: future vendor CLIs may disclose auth state.
    if result.returncode:
        if "marketplace" in args and "add" in args and "already" in (result.stdout + result.stderr).lower():
            return "Marketplace already registered"
        if "plugin" in args and "install" in args and "already installed" in (result.stdout + result.stderr).lower():
            return "Plugin already installed; version readback still required"
        raise RuntimeError(f"{args[0]} {' '.join(args[1:3])}: exit {result.returncode}")
    return result.stdout.strip()


def merge_mcp(path, key="mcpServers", remote_type="http", disabled=True):
    path = Path(path)
    data = json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
    entry = data.setdefault(key, {}).setdefault("clerk", {})
    if entry.get("url", URL) != URL:
        raise RuntimeError(f"Conflicting Clerk endpoint at {path}")
    entry.update({"type": remote_type, "url": URL})
    if disabled:
        entry.setdefault("disabled", True)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def copy_official(source, destination):
    destination = Path(destination)
    # A host's skills directory can be a junction to the retired shared library.
    # Refuse to install through any such parent rather than leaking skills fleet-wide.
    shared = (Path.home() / ".agents/skills").resolve()
    if destination.resolve().is_relative_to(shared):
        raise RuntimeError("Refusing shared ~/.agents/skills destination")
    if destination.is_symlink() or destination.is_junction():
        raise RuntimeError(f"Refusing linked plugin destination: {destination}")
    shutil.copytree(source, destination, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".git", "node_modules"))


def bridge(host, upstream, home):
    if host == "cursor":
        copy_official(upstream, home / ".cursor/plugins/local/clerk")
    elif host == "cline":
        copy_official(upstream, home / ".agents/plugins/clerk")
        config = home / ".cline/data/settings/cline_mcp_settings.json"
        merge_mcp(config, remote_type="streamableHttp")
        data = json.loads(config.read_text(encoding="utf-8"))
        data["mcpServers"]["clerk"].setdefault("autoApprove", [])
        config.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    elif host == "amp":
        target = home / ".config/amp/plugins/clerk"
        copy_official(upstream / "skills", target / "skills")
        skills = sorted(p.name for p in (target / "skills").iterdir() if (p / "SKILL.md").exists())
        (target / "index.ts").write_text(
            "// Runtime adapter for the official clerk/skills checkout.\n"
            "export default async function (amp: any) {\n" + "".join(
                f"  await amp.registerSkill({{ path: 'skills/{s}' }})\n" for s in skills) + "}\n",
            encoding="utf-8")
        (target / "skills/clerk/mcp.json").write_text(
            json.dumps({"clerk": {"url": URL}}, indent=2) + "\n", encoding="utf-8")
    elif host == "vscode-insiders":
        # Copilot reads its official installed-plugin catalog. Insiders needs its
        # own documented MCP config (the Clerk CLI's vscode target is stable VS Code).
        merge_mcp(Path(os.environ["APPDATA"]) / "Code - Insiders/User/mcp.json", "servers", disabled=False)
    else:
        folders = {"opencode": ".config/opencode/skills", "warp": ".warp/skills", "gemini": ".gemini/skills"}
        for skill in (upstream / "skills").iterdir():
            if (skill / "SKILL.md").exists():
                copy_official(skill, home / folders[host] / skill.name)
        if host == "gemini":
            # The CLI installer declines undetected/unlicensed Gemini clients.
            # Settings can still be prepared; this does not establish a usable CLI.
            path = home / ".gemini/settings.json"
            data = json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
            entry = data.setdefault("mcpServers", {}).setdefault("clerk", {})
            if entry.get("httpUrl", URL) != URL:
                raise RuntimeError("Conflicting Gemini Clerk endpoint")
            entry.update({"httpUrl": URL})
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        else:
            run(["clerk", "mcp", "install", "--client", host, "--json"])
            if host == "opencode":
                # Official CLI uses APPDATA on Windows; this fleet also retains
                # the documented XDG path. Converge only Clerk in both files.
                paths = [home / ".config/opencode/opencode.json"]
                if os.name == "nt":
                    paths.append(Path(os.environ["APPDATA"]) / "opencode/opencode.json")
                for path in paths:
                    merge_mcp(path, "mcp", "remote", disabled=False)
                    data = json.loads(path.read_text(encoding="utf-8"))
                    data["mcp"]["clerk"].setdefault("enabled", False)
                    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--audit", action="store_true", help="Read back official skill hashes and remote config, without starting hosts")
    parser.add_argument("--host", action="append", choices=sorted(set(NATIVE) | BRIDGES | set(ALIASES)))
    parser.add_argument("--runtime", type=Path, default=Path(os.environ.get("LOCALAPPDATA", Path.home() / ".local/share")) / "AgentHub/clerk")
    args = parser.parse_args()
    if args.audit:
        rows = audit(args.runtime / "upstream", Path.home())
        print(json.dumps(rows, indent=2))
        raise SystemExit(0 if all(r["matchingOfficialSkills"] == 20 and r["remoteConfigured"] for r in rows.values()) else 1)
    hosts = sorted({ALIASES.get(h, h) for h in (args.host or [*NATIVE, *BRIDGES])})
    if not args.apply:
        print(json.dumps({"upstream": "https://github.com/clerk/skills", "hosts": hosts,
                          "mode": "plan", "auth": "not attempted"}, indent=2))
        return
    args.runtime.mkdir(parents=True, exist_ok=True)
    upstream = args.runtime / "upstream"
    if not upstream.exists():
        run(["git", "clone", "--depth", "1", "https://github.com/clerk/skills.git", str(upstream)])
    if run(["git", "-C", str(upstream), "remote", "get-url", "origin"]) != "https://github.com/clerk/skills.git":
        raise RuntimeError("Unexpected upstream origin")
    if run(["git", "-C", str(upstream), "status", "--porcelain"]):
        raise RuntimeError("Upstream checkout dirty; preserve and review manually")
    run(["git", "-C", str(upstream), "pull", "--ff-only"])
    receipt = {"observedAt": datetime.now(timezone.utc).isoformat(), "upstreamCommit": run(
        ["git", "-C", str(upstream), "rev-parse", "HEAD"]), "hosts": {}}
    for host in hosts:
        try:
            if host in NATIVE:
                for command in NATIVE[host]:
                    run([arg.replace("{upstream}", upstream.as_posix()) for arg in command])
                if host in {"grok", "antigravity", "copilot"}:
                    run([{"grok": "grok", "antigravity": "agy", "copilot": "copilot"}[host], "mcp", "disable", "clerk"])
                if host == "codex":
                    config = Path.home() / ".codex/config.toml"
                    text = config.read_text(encoding="utf-8")
                    table = '[plugins."clerk@clerk".mcp_servers.clerk]'
                    if table not in text:
                        config.write_text(text + f"\n{table}\nenabled = false\n", encoding="utf-8")
            else:
                bridge(host, upstream, Path.home())
            receipt["hosts"][host] = {"installation": "completed", "freshSession": "not verified", "authenticatedMcp": "not verified"}
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
            receipt["hosts"][host] = {"installation": "blocked", "reason": str(exc)}
    (args.runtime / "latest-rollout.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))
    if any(row["installation"] == "blocked" for row in receipt["hosts"].values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
