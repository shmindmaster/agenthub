#!/usr/bin/env python3
"""Build Amp directory plugins from AgentHub packages.

Amp loads <plugins>/<name>/index.ts. Skills are registered from inside that folder and a skill's
sibling mcp.json carries its servers. Links out of the plugin folder are rejected, so each package
is copied. Rerun after a package changes.

usage: Install-AmpPlugins.py [--target DIR] [name ...]
"""
import argparse
import json
import os
import shutil
import subprocess

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Public packages are repo-relative. Private packages resolve through the same
# overlay roots CapabilityGraph uses: AGENTHUB_OVERLAY, overlays/personal, then
# the sibling agenthub-private clone (overlay.json marker).
_PUBLIC_PACKAGES = {
    "ah-product": "packages/product",
    "ah-media-studio": "packages/media-studio",
    "ah-assemblyai": "packages/assemblyai",
    "ah-browser": "packages/browser",
    "ah-coding-agent-dispatch": "packages/coding-agent-dispatch",
    "ah-funding": "packages/funding",
    "ah-research": "packages/research",
}
_PRIVATE_PACKAGES = ("ah-sarosh", "ah-docwise")


def _overlay_root():
    explicit = os.environ.get("AGENTHUB_OVERLAY", "").strip()
    if explicit.lower() == "off":
        return None
    if explicit:
        root = os.path.abspath(explicit)
        if not os.path.isdir(root):
            raise SystemExit(f"AGENTHUB_OVERLAY is '{root}' but that directory does not exist")
        return root
    default = os.path.join(REPO, "overlays", "personal")
    if os.path.isdir(default):
        return default
    sibling = os.path.abspath(os.path.join(os.path.dirname(REPO), "agenthub-private"))
    if os.path.isfile(os.path.join(sibling, "overlay.json")):
        return sibling
    return None


def _package_paths():
    """Return plugin -> (read_path, canonical_source).

    read_path is where files are copied from (may be the sibling clone).
    canonical_source is the registry form Sync-Plugins compares against
    (.source.json package field must equal capability.canonicalSource).
    """
    packages = {}
    for name, rel in _PUBLIC_PACKAGES.items():
        packages[name] = (rel, rel)
    overlay = _overlay_root()
    for name in _PRIVATE_PACKAGES:
        folder = name[len("ah-"):]
        canonical = f"overlays/personal/packages/{folder}"
        if overlay:
            read_path = os.path.relpath(
                os.path.join(overlay, "packages", folder), REPO
            ).replace("\\", "/")
            packages[name] = (read_path, canonical)
        # Absent overlay: omit the private plugin rather than crash the public build.
    return packages


PACKAGES = _package_paths()
# Package folders Amp must not read: host manifests, tests, agents, render scratch.
SKIP_TOP = {
    ".claude-plugin", ".codex-plugin", ".cursor-plugin", ".antigravity-plugin", ".pytest_cache",
    "tests", "agents", ".mcp.json", "mcp.json", "mcp.codex.json", "mcp_config.json",
    "plugin.json",
    "logs", "dist", "coverage",
}
# Amp expands ${VAR}. It sends ${env:VAR} literally (loopback test, 2026-11-04).
HEADERS = {
    "exa": {"x-api-key": "${EXA_API_KEY}"},
    "context7": {"CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}", "Authorization": "Bearer ${CONTEXT7_API_KEY}"},
}
URLS = {}
# Amp has no per-server off switch, so a local server is left out of the plugin: nothing here may start
# a process with a session. Remote servers start no process and stay.
LOCAL_SERVERS_LEFT_OUT = {"aws-mcp"}


def servers(pkg):
    for name in (".mcp.json", "mcp.json"):
        path = os.path.join(pkg, name)
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
            return data.get("mcpServers", data) or {}
    return {}


def amp_entry(name, cfg):
    if cfg.get("url"):
        entry = {"url": URLS.get(name, cfg["url"])}
        if name in HEADERS:
            entry["headers"] = HEADERS[name]
        return entry
    entry = {"command": cfg["command"], "args": cfg.get("args", [])}
    if cfg.get("env"):
        entry["env"] = cfg["env"]
    return entry


def head(path):
    try:
        result = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"], capture_output=True, text=True,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return result.stdout.strip() or None
    except OSError:
        return None


def build(target, plugin, package_spec):
    rel, canonical = package_spec if isinstance(package_spec, tuple) else (package_spec, package_spec)
    pkg = os.path.join(REPO, rel.replace("/", os.sep))
    dest = os.path.join(target, plugin)
    if os.path.lexists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    for item in os.listdir(pkg):
        if item in SKIP_TOP or item.startswith(".cloud-render-chunks-"):
            continue
        src = os.path.join(pkg, item)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, item),
                            ignore=shutil.ignore_patterns(
                                "__pycache__", ".pytest_cache", "node_modules",
                                "logs", "dist", "coverage", ".cloud-render-chunks-*"))
        else:
            shutil.copy2(src, os.path.join(dest, item))
    skills = sorted(d for d in os.listdir(os.path.join(dest, "skills"))
                    if os.path.exists(os.path.join(dest, "skills", d, "SKILL.md")))
    carried = {n: amp_entry(n, c) for n, c in servers(pkg).items() if n not in LOCAL_SERVERS_LEFT_OUT}
    if carried:
        if len(skills) != 1:
            raise SystemExit(f"{plugin}: servers need exactly one carrier skill, found {skills}")
        with open(os.path.join(dest, "skills", skills[0], "mcp.json"), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(carried, handle, indent=2)
            handle.write("\n")
    lines = [f"// Generated by Install-AmpPlugins.py from {canonical}. Edit the package, then rerun.",
             "export default async function (amp: any) {"]
    lines += [f"  await amp.registerSkill({{ path: 'skills/{s}' }})" for s in skills]
    lines.append("}")
    with open(os.path.join(dest, "index.ts"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    with open(os.path.join(pkg, "plugin.json"), encoding="utf-8") as handle:
        version = json.load(handle)["version"]
    with open(os.path.join(dest, ".source.json"), "w", encoding="utf-8", newline="\n") as handle:
        # package must equal registry canonicalSource (Sync-Plugins Amp check)
        json.dump({"package": canonical, "head": head(REPO), "version": version}, handle, indent=2)
        handle.write("\n")
    print(f"{plugin}: {len(skills)} skills, servers {sorted(carried)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", default=os.path.join(os.path.expanduser("~"), ".config", "amp", "plugins"))
    parser.add_argument("names", nargs="*", help="plugins to build; default is all")
    args = parser.parse_args()
    os.makedirs(args.target, exist_ok=True)
    for name in args.names or list(PACKAGES):
        build(args.target, name, PACKAGES[name])


if __name__ == "__main__":
    main()
