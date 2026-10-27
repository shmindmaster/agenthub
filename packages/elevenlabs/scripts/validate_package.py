#!/usr/bin/env python3
"""Fail-closed package parity check for the canonical elevenlabs capability."""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "3.1.3"
MANIFESTS = (
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    ".cursor-plugin/plugin.json",
)
REQUIRED_TTS_FLAGS = (
    "--dry-run",
    "--cache-workspace",
    "--cache-revision",
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
    "--with-timestamps",
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
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
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
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        check=False,
        capture_output=True,
        text=True,
    )
    if "models" not in help_result.stdout:
        failures.append("elevenlabs_cli.py is missing the read-only models subcommand")

    skills_dir = ROOT / "skills"
    skill_dirs = sorted(path.name for path in skills_dir.iterdir() if path.is_dir())
    if skill_dirs != ["elevenlabs"]:
        failures.append(f"skills/ must hold exactly one skill, elevenlabs (found {skill_dirs})")
    skill_root = skills_dir / "elevenlabs"
    reference_names = ("tts", "account-health", "stt", "capabilities", "cost-controls")
    texts: dict[str, str] = {}
    for relative in ["SKILL.md"] + [f"references/{name}.md" for name in reference_names]:
        try:
            texts[relative] = (skill_root / relative).read_text(encoding="utf-8")
        except OSError as error:
            failures.append(f"skills/elevenlabs/{relative}: unreadable ({error})")

    skill_text = texts.get("SKILL.md", "")
    if not skill_text.startswith("---\nname: elevenlabs\ndescription: "):
        failures.append("skills/elevenlabs/SKILL.md: front matter must open with name: elevenlabs and a description")
    for name in reference_names:
        if f"references/{name}.md" not in skill_text:
            failures.append(f"skills/elevenlabs/SKILL.md does not route to references/{name}.md")
    flat_skill = " ".join(skill_text.lower().split())
    for phrase in ("governed paid route", "unset shared ceiling disables purchases", "never print keys"):
        if phrase not in flat_skill:
            failures.append(f"skills/elevenlabs/SKILL.md lost the rule: {phrase}")

    narration_skill = texts.get("references/tts.md", "")
    if "shared CLI owns the provider request" not in narration_skill:
        failures.append("ElevenLabs TTS reference does not declare canonical provider ownership")
    if "eleven_v4_turbo" not in narration_skill:
        failures.append("ElevenLabs TTS reference lost the eleven_v4_turbo endpoint note")
    if "--with-timestamps" not in narration_skill:
        failures.append("ElevenLabs TTS reference lost the --with-timestamps contract")
    if "--dry-run" not in narration_skill:
        failures.append("ElevenLabs TTS reference lost the dry-run rule")
    if "fails closed" not in texts.get("references/stt.md", ""):
        failures.append("ElevenLabs STT reference lost the fails-closed rule")

    # Loose-skill hosts receive SKILL.md without the package scripts/ directory, so a bare
    # relative `scripts/elevenlabs_cli.py` does not resolve there. Every file that invokes
    # the CLI must name the resolvable package path.
    secret_shapes = (
        re.compile(r"\bsk_[0-9a-f]{20,}\b"),
        re.compile(r"xi-api-key\s*[:=]\s*['\"]?[A-Za-z0-9_\-]{16,}"),
        re.compile(r"Bearer\s+[A-Za-z0-9_\-.]{20,}"),
        re.compile(r"ELEVENLABS_API_KEY\s*=\s*['\"]?[A-Za-z0-9_\-]{16,}"),
    )
    for relative, text in texts.items():
        if "elevenlabs_cli.py" in text and "packages/elevenlabs/scripts/elevenlabs_cli.py" not in text.replace("\\", "/"):
            failures.append(f"skills/elevenlabs/{relative}: invokes elevenlabs_cli.py without the resolvable package path")
        for shape in secret_shapes:
            if shape.search(text):
                failures.append(f"skills/elevenlabs/{relative}: contains a secret-shaped value")

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
