"""Native Codex connector block for shared-budget mode. No daemon or integration.

Applies only to new/reloaded sessions. Does not intercept unrestricted shell/API
requests or cloud hosts; config readback alone is not proof of tool removal.
"""
import argparse
import json
import os
import pathlib
import re
import tempfile
import tomllib

# Official plugin .app.json declares this app ID. Plugin name is not the ID.
ELEVENLABS_APP = "asdk_app_6a8d784b60cc81919aeafbfaeda5fbcf"
SECTION = f"apps.{ELEVENLABS_APP}"


def blocked(text):
    return tomllib.loads(text).get("apps", {}).get(ELEVENLABS_APP, {}).get("enabled") is False


def codex_block(text):
    tomllib.loads(text)  # Refuse malformed existing configuration.
    header = re.compile(r"(?m)^\[" + re.escape(SECTION) + r"\][ \t]*(?:#.*)?$")
    match = header.search(text)
    if match:
        end = re.search(r"(?m)^\[", text[match.end():])
        stop = match.end() + end.start() if end else len(text)
        body = text[match.end():stop]
        assignment = re.compile(r"(?m)^enabled\s*=.*$")
        body = assignment.sub("enabled = false", body) if assignment.search(body) else "\nenabled = false\n" + body
        result = text[:match.end()] + body + text[stop:]
    else:
        # An unusual equivalent quoted/dotted layout needs a native structured
        # edit, rather than risking duplicate TOML tables or losing user fields.
        if ELEVENLABS_APP in tomllib.loads(text).get("apps", {}):
            raise RuntimeError("Existing app table uses a different TOML layout; merge enabled=false with native config tooling")
        result = text.rstrip() + f"\n\n# AgentHub shared content budget: paid native connector bypass blocked.\n[{SECTION}]\nenabled = false\n"
    if not blocked(result):
        raise RuntimeError("Codex connector block failed validation")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    config = pathlib.Path.home() / ".codex/config.toml"
    text = config.read_text(encoding="utf-8")
    if args.apply and not blocked(text):
        result = codex_block(text)
        # Same-directory replace; don't copy authentication/config into reports.
        descriptor, name = tempfile.mkstemp(prefix=".content-controls-", dir=config.parent)
        temporary = pathlib.Path(name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(result)
                handle.flush()
                os.fsync(handle.fileno())
            if config.read_text(encoding="utf-8") != text:
                raise RuntimeError("Config changed concurrently; retry the merge")
            os.replace(temporary, config)
        finally:
            temporary.unlink(missing_ok=True)
    print(json.dumps({"host": "codex-local", "app_id": ELEVENLABS_APP,
                      "configured_block": blocked(config.read_text(encoding="utf-8")),
                      "requires_new_session": True, "effective_tool_removal_verified": False}))


if __name__ == "__main__":
    main()
