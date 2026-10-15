#!/usr/bin/env python3
"""Fail-closed package parity check for the canonical elevenlabs capability."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "1.2.0"
MANIFESTS = (
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    ".cursor-plugin/plugin.json",
)
REQUIRED_TTS_FLAGS = (
    "--dry-run",
    "--max-credits",
    "--stability",
    "--similarity-boost",
    "--style",
    "--speed",
    "--use-speaker-boost",
    "--no-use-speaker-boost",
    "--text-normalization",
    "--previous-text",
    "--next-text",
    "--previous-request-id",
    "--next-request-id",
    "--output-format",
    "--pronunciation-dictionary",
)


def main() -> int:
    failures: list[str] = []
    for relative_path in MANIFESTS:
        path = ROOT / relative_path
        try:
            manifest = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            failures.append(f"{relative_path}: unreadable JSON ({error})")
            continue
        if manifest.get("name") != "elevenlabs":
            failures.append(f"{relative_path}: plugin name must be elevenlabs")
        if manifest.get("version") != EXPECTED_VERSION:
            failures.append(f"{relative_path}: version must be {EXPECTED_VERSION}")

    portable_path = ROOT / "plugin.json"
    try:
        portable = json.loads(portable_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        failures.append(f"plugin.json: unreadable JSON ({error})")
    else:
        if portable.get("name") != "elevenlabs":
            failures.append("plugin.json: plugin name must be elevenlabs")
        # Root plugin.json is the portable version authority (scripts/Bump-PackageVersion.ps1).
        if set(portable) - {"$schema", "name", "version", "description"}:
            failures.append("plugin.json: must stay within the portable Agent Plugins manifest fields")
        if portable.get("version") != EXPECTED_VERSION:
            failures.append(f"plugin.json: version must be {EXPECTED_VERSION}")

    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "elevenlabs_cli.py"), "tts", "--help"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        failures.append("elevenlabs_cli.py tts --help failed")
    for flag in REQUIRED_TTS_FLAGS:
        if flag not in result.stdout:
            failures.append(f"canonical TTS adapter is missing {flag}")

    help_result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "elevenlabs_cli.py"), "--help"],
        check=False,
        capture_output=True,
        text=True,
    )
    if "models" not in help_result.stdout:
        failures.append("elevenlabs_cli.py is missing the read-only models subcommand")

    narration_skill = (ROOT / "skills" / "elevenlabs-tts" / "SKILL.md").read_text(encoding="utf-8")
    if "shared CLI owns the provider request" not in narration_skill:
        failures.append("ElevenLabs TTS skill does not declare canonical provider ownership")

    # Loose-skill hosts receive SKILL.md without the package scripts/ directory, so a bare
    # relative `scripts/elevenlabs_cli.py` does not resolve there. Every skill that invokes
    # the CLI must name the resolvable package path.
    for skill_md in sorted((ROOT / "skills").glob("*/SKILL.md")):
        text = skill_md.read_text(encoding="utf-8")
        if "elevenlabs_cli.py" in text and "packages/elevenlabs/scripts/elevenlabs_cli.py" not in text.replace("\\", "/"):
            failures.append(f"{skill_md.parent.name}: invokes elevenlabs_cli.py without the resolvable package path")

    if failures:
        print(f"elevenlabs package validation FAILED ({len(failures)}):", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(
        f"PASS: elevenlabs {EXPECTED_VERSION} has one manifest identity and canonical TTS adapter."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
