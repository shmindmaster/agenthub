#!/usr/bin/env python3
"""Validate the private runtime application-answer profile."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, FormatChecker


EXPECTED_PRECEDENCE = [
    "current_explicit_owner_answer",
    "latest_verified_submitted_equivalent",
    "confirmed_canonical_profile",
    "verified_career_or_supporting_record",
    "meaning_preserving_deterministic_normalization",
    "ask_once_if_unresolved_conflicting_stale_or_materially_different",
]

REQUIRED_KEYS = {
    "work_authorization_us",
    "citizenship_us",
    "current_security_clearance",
    "willing_to_obtain_clearance",
    "clearance_legal_eligibility",
}

REQUIRED_NON_INFERENCE_RULES = {
    "work_authorization_us_does_not_imply_citizenship_us",
    "willingness_or_eligibility_does_not_imply_active_clearance",
    "sponsorship_answer_does_not_cross_jurisdictions",
}


def _load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def _normalized_alias(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.casefold()).strip()


def _semantic_errors(profile: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    if profile.get("resolution_precedence") != EXPECTED_PRECEDENCE:
        errors.append("resolution_precedence does not match the canonical six-step order")

    rules = set(profile.get("non_inference_rules", []))
    missing_rules = sorted(REQUIRED_NON_INFERENCE_RULES - rules)
    if missing_rules:
        errors.append(f"missing non-inference rules: {', '.join(missing_rules)}")

    answers = profile.get("answers", [])
    keys = [answer.get("key") for answer in answers if isinstance(answer, dict)]
    duplicate_keys = sorted({key for key in keys if key and keys.count(key) > 1})
    if duplicate_keys:
        errors.append(f"duplicate answer keys: {', '.join(duplicate_keys)}")

    missing_keys = sorted(REQUIRED_KEYS - set(keys))
    if missing_keys:
        errors.append(f"missing required answer keys: {', '.join(missing_keys)}")

    aliases: dict[str, str] = {}
    for answer in answers:
        if not isinstance(answer, dict):
            continue
        key = answer.get("key", "<unknown>")
        status = answer.get("status")
        value = answer.get("value")
        source = answer.get("source")
        if status == "confirmed" and (value is None or not isinstance(source, dict)):
            errors.append(f"confirmed answer {key} requires a non-null value and source")
        if status == "unresolved" and (value is not None or source is not None):
            errors.append(f"unresolved answer {key} must have null value and source")
        for alias in [key, *answer.get("aliases", [])]:
            normalized = _normalized_alias(str(alias))
            previous = aliases.get(normalized)
            if normalized and previous and previous != key:
                errors.append(f"ambiguous alias '{alias}' is shared by {previous} and {key}")
            elif normalized:
                aliases[normalized] = key

    compensation = profile.get("preferences", {}).get("compensation", {})
    if compensation.get("hard_floor_total_comp_usd") != 250000:
        errors.append("hard_floor_total_comp_usd must be 250000")
    if compensation.get("primary_min_total_comp_usd") != 300000:
        errors.append("primary_min_total_comp_usd must be 300000")
    geography = profile.get("preferences", {}).get("geography", {})
    if geography.get("primary_worldwide") is not True:
        errors.append("primary_worldwide must be true")
    if geography.get("secondary_primarily_us") is not True:
        errors.append("secondary_primarily_us must be true")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("profile", type=Path)
    parser.add_argument(
        "--schema",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "schemas"
        / "application-answer-profile.schema.yaml",
    )
    args = parser.parse_args()

    try:
        profile = _load_yaml(args.profile)
        schema = _load_yaml(args.schema)
    except (OSError, yaml.YAMLError) as exc:
        print(f"INVALID: unable to load YAML: {exc}", file=sys.stderr)
        return 2

    if not isinstance(profile, dict) or not isinstance(schema, dict):
        print("INVALID: profile and schema roots must be mappings", file=sys.stderr)
        return 2

    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = [
        f"{'.'.join(str(part) for part in error.absolute_path) or '<root>'}: {error.message}"
        for error in sorted(validator.iter_errors(profile), key=lambda item: list(item.absolute_path))
    ]
    errors.extend(_semantic_errors(profile))

    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 1

    print(f"PASS: application answer profile is valid: {args.profile}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
