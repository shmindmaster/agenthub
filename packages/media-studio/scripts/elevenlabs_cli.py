#!/usr/bin/env python3
"""Owner-authorized ElevenLabs speech for Media Studio. Speech only; dependency-free.

Every provider call needs an immutable owner manifest naming the exact voice and job workspace.
There is no default voice, model or budget. `quote` is offline and needs no credential.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

import governed_elevenlabs as governed

BASE_URL = "https://api.elevenlabs.io/v1"
DEFAULT_OUTPUT_FORMAT = "mp3_44100_192"
MAX_DICTIONARY_LOCATORS = 3
GOVERNED_POST_PREFIX = "/text-to-speech/"


class ProviderHTTPError(RuntimeError):
    """An HTTP error status from the provider; the message carries only the status and a sanitized code."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """The key is a request header, so a followed redirect would carry it to the new origin."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _request_full(path, method="GET", body=None, content_type=None, timeout=30, on_headers=None, governed_submission=False):
    if method != "GET" and not (governed_submission and method == "POST" and path.startswith(GOVERNED_POST_PREFIX)):
        raise RuntimeError("Paid requests require the governed speech route; this route is disabled")
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise RuntimeError("ELEVENLABS_API_KEY is not set")
    headers = {"xi-api-key": key, "Accept": "application/json"}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(BASE_URL + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.build_opener(_NoRedirect()).open(req, timeout=timeout) as response:
            if on_headers:
                on_headers(response.headers)
            return response.status, response.headers.get_content_type(), response.read(), response.headers
    except urllib.error.HTTPError as exc:
        if on_headers and exc.headers is not None:
            on_headers(exc.headers)
        # Error messages may echo submitted text or account details. Emit only a code.
        try:
            detail = json.loads(exc.read()).get("detail", {})
            code = detail.get("status", "") if isinstance(detail, dict) else ""
            code = code if re.fullmatch(r"[a-zA-Z0-9_\-]{1,80}", str(code)) else ""
        except Exception:  # noqa: BLE001 - detail is best-effort only
            code = ""
        raise ProviderHTTPError(f"ElevenLabs API returned HTTP {exc.code}" + (f" ({code})" if code else "")) from None
    except urllib.error.URLError as exc:
        raise RuntimeError("ElevenLabs API request failed") from exc


def _get_json(path):
    return json.loads(_request_full(path)[2])


def _account_summary(data):
    used, limit = data.get("character_count"), data.get("character_limit")
    return {"status": data.get("status"), "can_extend_character_limit": data.get("can_extend_character_limit"),
            "credits_remaining": max(0, limit - used) if isinstance(used, (int, float)) and isinstance(limit, (int, float)) else None}


def _voice_summary(data):
    tuning = data.get("fine_tuning") or {}
    verification = data.get("voice_verification") or {}
    return {"category": data.get("category"), "model_states": tuning.get("state"),
            "requires_verification": verification.get("requires_verification")}


def tts_preflight(voice_id, model_id, text, max_credits):
    summary = _account_summary(_get_json("/user/subscription"))
    if summary["status"] != "active":
        raise RuntimeError("An active subscription must be established before generation")
    voice = _voice_summary(_get_json("/voices/" + urllib.parse.quote(voice_id, safe="")))
    if voice["requires_verification"] is True:
        raise RuntimeError("Voice requires owner verification; generation stopped")
    if voice["category"] == "professional" and (voice["model_states"] or {}).get(model_id) != "fine_tuned":
        raise RuntimeError("Professional clone is not established as fine_tuned on the requested model; "
                           "select a ready model explicitly")
    model = next((m for m in _get_json("/models") if m.get("model_id") == model_id and m.get("can_do_text_to_speech")), None)
    if model is None:
        raise RuntimeError("Requested TTS model is absent from the live model inventory")
    maximum = model.get("maximum_text_length_per_request") or model.get("max_characters_request_subscribed_user")
    if maximum and len(text) > maximum:
        raise RuntimeError("Text exceeds this model's request limit; segment the locked script")
    rate = model.get("model_rates", {}).get("character_cost_multiplier")
    estimate = math.ceil(len(text) * rate) if isinstance(rate, (int, float)) and math.isfinite(rate) and rate > 0 else None
    if max_credits is not None and (not math.isfinite(max_credits) or max_credits <= 0):
        raise RuntimeError("--max-credits must be a positive finite number")
    if estimate is None or summary["credits_remaining"] is None:
        raise RuntimeError("Credit estimate or remaining quota is unknown; inspect the provider's current metering before spending")
    if estimate > summary["credits_remaining"]:
        raise RuntimeError("Estimated credits exceed remaining quota; billing changes are not automatic")
    if max_credits is not None and estimate > max_credits:
        raise RuntimeError("Estimated credits exceed --max-credits")
    return {"voice_id": voice_id, "model_id": model_id, "text_characters": len(text), "estimated_credits": estimate,
            "credits_remaining": summary["credits_remaining"],
            "can_extend_character_limit": summary["can_extend_character_limit"],
            "text_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()}


def _dictionary_locators(values):
    locators = []
    for value in values or []:
        dictionary_id, _, version_id = value.partition(":")
        if not dictionary_id or not version_id:
            raise RuntimeError("Governed generation requires versioned pronunciation dictionaries")
        locators.append({"pronunciation_dictionary_id": dictionary_id, "version_id": version_id})
    if len(locators) > MAX_DICTIONARY_LOCATORS:
        raise RuntimeError(f"At most {MAX_DICTIONARY_LOCATORS} pronunciation dictionary locators per request")
    return locators


def speech_payload(args):
    """The exact body sent to the provider. Offline, so `quote` hashes what `tts` will submit."""
    settings = {"stability": args.stability, "similarity_boost": args.similarity_boost}
    if args.model_id.startswith("eleven_v4"):
        if any(value is not None for value in (args.style, args.speed, args.use_speaker_boost)):
            raise RuntimeError("v4 accepts only stability and similarity_boost; omit --style, --speed and --use-speaker-boost")
    else:
        settings.update(style=args.style, speed=args.speed, use_speaker_boost=args.use_speaker_boost)
    if any(value is None for value in settings.values()) or not args.text_normalization:
        raise RuntimeError("Governed generation requires explicit voice settings and text normalization")
    locators = _dictionary_locators(args.pronunciation_dictionary)
    return {"text": args.text, "model_id": args.model_id, "voice_settings": settings,
            "apply_text_normalization": args.text_normalization,
            **({"previous_text": args.previous_text} if args.previous_text else {}),
            **({"next_text": args.next_text} if args.next_text else {}),
            **({"pronunciation_dictionary_locators": locators} if locators else {})}


def quote(args):
    print(json.dumps(governed.quote(args, args.voice_id, args.model_id, args.output_format, speech_payload(args))))
    return 0


def tts(args):
    if not args.authorization_manifest:
        raise RuntimeError("ElevenLabs speech requires an immutable owner authorization manifest; "
                           "nothing was reserved or requested")
    payload = speech_payload(args)
    authorized = governed.authorized_policy(args.authorization_manifest, args.voice_id, args.cache_workspace, args.model_id)
    if args.dry_run:
        print(json.dumps({"dry_run": True, **tts_preflight(args.voice_id, args.model_id, args.text, args.max_credits)}))
        return 0
    if args.max_credits is None or not args.max_credits.is_integer() or args.max_credits <= 0:
        raise RuntimeError("Paid generation requires a positive integer --max-credits")
    output = pathlib.Path(args.output).expanduser()
    receipt_path = output.with_suffix(output.suffix + ".provenance.json")
    if output.exists() or receipt_path.exists():
        raise RuntimeError("Output or receipt already exists; reuse it or choose a new take path")
    # Resolve a usable local destination before consuming provider credits.
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("xb"):
            pass
        output.unlink()
    except OSError:
        raise RuntimeError("Output destination is not writable; no generation was requested") from None
    raw, receipt = governed.generate(sys.modules[__name__], args, authorized, args.voice_id, args.model_id, args.output_format, payload)
    receipt["output"] = str(output.resolve())
    # Save the receipt first; a failed local save remains recoverable without repurchasing.
    with receipt_path.open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(receipt, indent=2) + "\n")
    with output.open("xb") as handle:
        handle.write(raw)
    print(json.dumps({"ok": True, "output": str(output), "acceptance_state": receipt["acceptance_state"], "reused": receipt["reused"]}))
    return 0


def speech_arguments(parser):
    parser.add_argument("--text", required=True)
    parser.add_argument("--voice-id", required=True)
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--cache-workspace", required=True, help="Job workspace the owner manifest names")
    parser.add_argument("--cache-revision", required=True, help="Locked voice/model/reference revision")
    parser.add_argument("--stability", type=float)
    parser.add_argument("--similarity-boost", type=float)
    parser.add_argument("--style", type=float)
    parser.add_argument("--speed", type=float)
    parser.add_argument("--use-speaker-boost", action=argparse.BooleanOptionalAction, default=None)
    parser.add_argument("--text-normalization", choices=["auto", "on", "off"])
    parser.add_argument("--previous-text")
    parser.add_argument("--next-text")
    parser.add_argument("--output-format", default=DEFAULT_OUTPUT_FORMAT)
    parser.add_argument("--pronunciation-dictionary", action="append", metavar="ID:VERSION",
                        help=f"Repeatable, max {MAX_DICTIONARY_LOCATORS}, applied in order")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p_quote = sub.add_parser("quote", help="Offline: print the hashes an owner manifest must carry; no credential, no request")
    speech_arguments(p_quote)
    p_quote.set_defaults(func=quote)
    p_tts = sub.add_parser("tts", help="Owner-authorized speech (ledger-reserved, receipt-bound)")
    speech_arguments(p_tts)
    p_tts.add_argument("--output", required=True)
    p_tts.add_argument("--max-credits", type=float, help="Integer reservation for this request")
    p_tts.add_argument("--authorization-manifest", help="Absolute immutable owner manifest naming this voice and workspace")
    p_tts.add_argument("--dry-run", action="store_true", help="Check credits and voice readiness without generating")
    p_tts.set_defaults(func=tts)
    p_reconcile = sub.add_parser("reconcile", help="Provider GET-only recovery of one epoch request; never resubmits")
    p_accept = sub.add_parser("accept", help="Offline: attach QA evidence to exact epoch bytes")
    for existing in (p_reconcile, p_accept):
        existing.add_argument("--authorization-manifest", required=True, help="The original project manifest, byte-identical")
        existing.add_argument("--namespace", required=True)
        existing.add_argument("--cache-workspace", required=True)
        existing.add_argument("--cache-key", required=True)
    p_reconcile.add_argument("--history-id", required=True)
    p_reconcile.set_defaults(func=lambda args: governed.reconcile(sys.modules[__name__], args))
    p_accept.add_argument("--gates", required=True, type=pathlib.Path, help="Private gate manifest, as content_control.py accept reads")
    p_accept.set_defaults(func=governed.accept)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except (OSError, ValueError, KeyError, TypeError, ImportError):
        print("Local validation/storage failed; inspect the ledger before retrying any generation", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
