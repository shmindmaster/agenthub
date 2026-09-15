#!/usr/bin/env python3
"""Fail-closed package parity check for the canonical elevenlabs capability."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "1.0.0"
MANIFESTS = (
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    ".cursor-plugin/plugin.json",
)
REQUIRED_TTS_FLAGS = (
    "--stability",
    "--similarity-boost",
    "--style",
    "--speed",
    "--use-speaker-boost",
    "--no-use-speaker-boost",
    "--text-normalization",
    "--previous-text",
    "--next-text",
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
        if set(portable) - {"name", "description"}:
            failures.append("plugin.json: must stay within the Antigravity manifest schema")

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

    narration_skill = (ROOT / "skills" / "elevenlabs-tts" / "SKILL.md").read_text(encoding="utf-8")
    if "shared CLI owns the provider request" not in narration_skill:
        failures.append("ElevenLabs TTS skill does not declare canonical provider ownership")

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
