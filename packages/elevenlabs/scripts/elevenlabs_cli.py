#!/usr/bin/env python3
"""Small, dependency-free ElevenLabs capability CLI."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import pathlib
import math
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE_URL = "https://api.elevenlabs.io/v1"


DEFAULT_TTS_MODEL = "eleven_flash_v2_5"
DEFAULT_OUTPUT_FORMAT = "mp3_44100_192"
MAX_STITCH_IDS = 3
MAX_DICTIONARY_LOCATORS = 3
# Governed paid POST routes: speech, sound effects, music. Everything else stays read-only.
GOVERNED_POST_PREFIXES = ("/text-to-speech/", "/sound-generation", "/music")


class ProviderHTTPError(RuntimeError):
    """An HTTP error status from the provider; the message carries only the status and a sanitized code."""

    def __init__(self, message: str, status: int):
        super().__init__(message)
        self.status = status


def _request_full(path: str, method: str = "GET", body: bytes | None = None, content_type: str | None = None, timeout: int = 30, on_headers=None, governed_submission=False):
    if method != "GET" and not (governed_submission and method == "POST" and path.startswith(GOVERNED_POST_PREFIXES)):
        raise RuntimeError("Paid/unmetered requests require the shared broker; this route is disabled")
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise RuntimeError("ELEVENLABS_API_KEY is not set")
    headers = {"xi-api-key": key, "Accept": "application/json"}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(BASE_URL + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
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
        raise ProviderHTTPError(f"ElevenLabs API returned HTTP {exc.code}" + (f" ({code})" if code else ""), exc.code) from None
    except urllib.error.URLError as exc:
        raise RuntimeError("ElevenLabs API request failed") from exc


def request(path: str, method: str = "GET", body: bytes | None = None, content_type: str | None = None, timeout: int = 30):
    status, ctype, raw, _ = _request_full(path, method, body, content_type, timeout)
    return status, ctype, raw


def health(_: argparse.Namespace) -> int:
    _, _, raw = request("/user")
    data = json.loads(raw)
    subscription = data.get("subscription") or {}
    print(json.dumps({
        "ok": True,
        "has_subscription": bool(subscription),
        "has_character_limit": "character_limit" in subscription,
        "has_voice_limit": "voice_limit" in subscription,
    }))
    return 0


def _get_json(path: str):
    return json.loads(request(path)[2])


def _account_summary(data: dict) -> dict:
    used, limit = data.get("character_count"), data.get("character_limit")
    return {
        **{key: data.get(key) for key in (
            "tier", "status", "character_count", "character_limit",
            "next_character_count_reset_unix", "can_extend_character_limit",
            "voice_count", "voice_slots_used", "voice_limit", "professional_voice_count",
            "professional_voice_slots_used", "professional_voice_limit",
            "can_use_instant_voice_cloning", "can_use_professional_voice_cloning",
        )},
        "credits_remaining": max(0, limit - used) if isinstance(used, (int, float)) and isinstance(limit, (int, float)) else None,
    }


def account(_: argparse.Namespace) -> int:
    print(json.dumps(_account_summary(_get_json("/user/subscription"))))
    return 0


def _voice_summary(data: dict) -> dict:
    tuning = data.get("fine_tuning") or {}
    verification = data.get("voice_verification") or {}
    return {
        "voice_id": data.get("voice_id"), "name": data.get("name"),
        "category": data.get("category"),
        "model_states": tuning.get("state"),
        "high_quality_base_model_ids": data.get("high_quality_base_model_ids"),
        "requires_verification": verification.get("requires_verification"),
        "is_verified": verification.get("is_verified"),
        "sample_count": len(data["samples"]) if isinstance(data.get("samples"), list) else None,
    }


def voice_status(args: argparse.Namespace) -> int:
    print(json.dumps(_voice_summary(_get_json("/voices/" + urllib.parse.quote(args.voice_id, safe="")))))
    return 0


def tts_preflight(voice_id: str, model_id: str, text: str, max_credits: float | None) -> dict:
    summary = _account_summary(_get_json("/user/subscription"))
    if summary["status"] != "active":
        raise RuntimeError("An active subscription must be established before generation")
    voice = _voice_summary(_get_json("/voices/" + urllib.parse.quote(voice_id, safe="")))
    if voice["requires_verification"] is True:
        raise RuntimeError("Voice requires owner verification; generation stopped")
    if voice["category"] == "professional":
        state = (voice["model_states"] or {}).get(model_id)
        if state != "fine_tuned":
            raise RuntimeError("Professional clone is not established as fine_tuned on the requested model; select a ready model explicitly")
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
    return {"voice_id": voice_id, "model_id": model_id, "text_characters": len(text),
            "estimated_credits": estimate, "credits_remaining": summary["credits_remaining"],
            "can_extend_character_limit": summary["can_extend_character_limit"],
            "text_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()}


def voices(_: argparse.Namespace) -> int:
    _, _, raw = request("/voices")
    data = json.loads(raw)
    voices = [{"voice_id": v.get("voice_id"), "name": v.get("name")} for v in data.get("voices", [])]
    print(json.dumps({"returned_count": len(voices), "scope": "GET /voices response", "voices": voices}, ensure_ascii=False))
    return 0


def models(_: argparse.Namespace) -> int:
    """Read-only: list the models this account can use right now (GET /v1/models)."""
    _, _, raw = request("/models")
    rows = []
    for m in json.loads(raw):
        rows.append({
            "model_id": m.get("model_id"),
            "name": m.get("name"),
            "can_do_text_to_speech": m.get("can_do_text_to_speech"),
            "maximum_text_length_per_request": m.get("maximum_text_length_per_request"),
            "languages": len(m.get("languages") or []),
            "model_rates": m.get("model_rates"),
        })
    print(json.dumps({"count": len(rows), "models": rows}, ensure_ascii=False))
    return 0


def _dictionary_locators(values: list[str] | None) -> list[dict[str, str]]:
    locators = []
    for value in values or []:
        dictionary_id, _, version_id = value.partition(":")
        locator = {"pronunciation_dictionary_id": dictionary_id}
        if version_id:
            locator["version_id"] = version_id
        locators.append(locator)
    if len(locators) > MAX_DICTIONARY_LOCATORS:
        raise RuntimeError(f"At most {MAX_DICTIONARY_LOCATORS} pronunciation dictionary locators per request")
    return locators


ALIGNMENT_KEYS = ("characters", "character_start_times_seconds", "character_end_times_seconds")


def _valid_alignment(value) -> bool:
    return (isinstance(value, dict) and all(isinstance(value.get(key), list) for key in ALIGNMENT_KEYS)
            and len({len(value[key]) for key in ALIGNMENT_KEYS}) == 1)


def split_timestamped_response(raw: bytes) -> tuple[bytes, dict]:
    """Split a /with-timestamps JSON body into audio bytes and its character alignment."""
    try:
        data = json.loads(raw)
        audio = base64.b64decode(data["audio_base64"], validate=True)
    except (ValueError, KeyError, TypeError):
        raise RuntimeError("Saved asset is not a timestamped response; no alignment can be rebuilt from it") from None
    normalized = data.get("normalized_alignment")
    if not audio or not _valid_alignment(data.get("alignment")) or not (normalized is None or _valid_alignment(normalized)):
        raise RuntimeError("Timestamped response is missing audio or a consistent character alignment")
    return audio, {"alignment": data["alignment"], "normalized_alignment": normalized}


def tts(args: argparse.Namespace) -> int:
    voice_id = args.voice_id or os.environ.get("ELEVENLABS_VOICE_ID")
    if not voice_id:
        raise RuntimeError("Provide --voice-id or set ELEVENLABS_VOICE_ID")
    # Request stitching: the live API rejected a body carrying both forms on 2026-10-13.
    if args.previous_request_id and args.previous_text:
        raise RuntimeError("Send --previous-request-id or --previous-text, never both")
    if args.next_request_id and args.next_text:
        raise RuntimeError("Send --next-request-id or --next-text, never both")
    for flag, ids in (("--previous-request-id", args.previous_request_id), ("--next-request-id", args.next_request_id)):
        if ids and len(ids) > MAX_STITCH_IDS:
            raise RuntimeError(f"{flag} accepts at most {MAX_STITCH_IDS} request ids")
    model_id = args.model_id or os.environ.get("ELEVENLABS_MODEL_TTS_DEFAULT", DEFAULT_TTS_MODEL)
    if not args.dry_run and not (args.model_id or os.environ.get("ELEVENLABS_MODEL_TTS_DEFAULT")):
        raise RuntimeError("Paid generation requires an explicitly selected --model-id or ELEVENLABS_MODEL_TTS_DEFAULT")
    output_format = args.output_format or os.environ.get("ELEVENLABS_OUTPUT_FORMAT", DEFAULT_OUTPUT_FORMAT)
    locators = _dictionary_locators(args.pronunciation_dictionary)
    if args.dry_run:
        preflight = tts_preflight(voice_id, model_id, args.text, args.max_credits)
        print(json.dumps({"dry_run": True, "with_timestamps": args.with_timestamps, **preflight}))
        return 0
    if args.max_credits is None:
        raise RuntimeError("Paid generation requires an explicit --max-credits budget")
    output = pathlib.Path(args.output).expanduser()
    alignment_path = output.with_suffix(output.suffix + ".alignment.json") if args.with_timestamps else None
    if output.exists() or output.with_suffix(output.suffix + ".provenance.json").exists() or (alignment_path and alignment_path.exists()):
        raise RuntimeError("Output, receipt or alignment already exists; reuse it or choose a new take path")
    # Resolve a usable local destination before consuming provider credits.
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("xb"):
            pass
        output.unlink()
    except OSError:
        raise RuntimeError("Output destination is not writable; no generation was requested") from None
    if model_id.startswith("eleven_v4") and (args.style is not None or args.speed is not None):
        # 2026-10-13 live A/B: v4 accepted style/use_speaker_boost silently with no measurable change.
        print("warning: eleven_v4 exposes only stability and similarity; --style/--speed have no verified effect", file=sys.stderr)
    voice_settings = {
        key: value
        for key, value in {
            "stability": args.stability,
            "similarity_boost": args.similarity_boost,
            "style": args.style,
            "speed": args.speed,
            "use_speaker_boost": args.use_speaker_boost,
        }.items()
        if value is not None
    }
    payload_object = {
        "text": args.text,
        "model_id": model_id,
        **({"voice_settings": voice_settings} if voice_settings else {}),
        **({"apply_text_normalization": args.text_normalization} if args.text_normalization else {}),
        **({"previous_text": args.previous_text} if args.previous_text else {}),
        **({"next_text": args.next_text} if args.next_text else {}),
        **({"previous_request_ids": args.previous_request_id} if args.previous_request_id else {}),
        **({"next_request_ids": args.next_request_id} if args.next_request_id else {}),
        **({"pronunciation_dictionary_locators": locators} if locators else {}),
        **({"language_code": args.language_code} if args.language_code else {}),
        **({"seed": args.seed} if args.seed is not None else {}),
    }
    import governed_elevenlabs
    raw, receipt = governed_elevenlabs.generate(sys.modules[__name__], args, voice_id, model_id, output_format,
                                                payload_object, with_timestamps=args.with_timestamps)
    receipt["output"] = str(output.resolve())
    alignment_bytes = None
    if args.with_timestamps:
        # The ledger asset is the provider's JSON body; acceptance binds ledger_asset_sha256, the file on disk is the decoded audio.
        raw, alignment = split_timestamped_response(raw)
        alignment_bytes = (json.dumps({"schema": "elevenlabs/tts-alignment/1", "request_id": receipt["request_id"],
                                       "model_id": model_id, "voice_id": voice_id, "output_format": output_format,
                                       "audio_sha256": hashlib.sha256(raw).hexdigest(), **alignment}, indent=1) + "\n").encode("utf-8")
        receipt.update({"with_timestamps": True, "ledger_asset_sha256": receipt["output_sha256"],
                        "output_sha256": hashlib.sha256(raw).hexdigest(), "output_bytes": len(raw),
                        "alignment_output": str(alignment_path.resolve()),
                        "alignment_sha256": hashlib.sha256(alignment_bytes).hexdigest()})
    # Save the receipt first; a failed local save remains recoverable without repurchasing.
    with output.with_suffix(output.suffix + ".provenance.json").open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(receipt, indent=2) + "\n")
    with output.open("xb") as handle:
        handle.write(raw)
    if alignment_bytes is not None:
        with alignment_path.open("xb") as handle:
            handle.write(alignment_bytes)
    print(json.dumps({"ok": True, "output": str(output), "acceptance_state": receipt["acceptance_state"], "reused": receipt["reused"],
                      **({"alignment": str(alignment_path)} if alignment_bytes is not None else {})}))
    return 0


def _audio_output_ready(args) -> None:
    output = pathlib.Path(args.output).expanduser()
    if output.exists() or output.with_suffix(output.suffix + ".provenance.json").exists():
        raise RuntimeError("Output or receipt already exists; reuse it or choose a new take path")
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("xb"):
            pass
        output.unlink()
    except OSError:
        raise RuntimeError("Output destination is not writable; no generation was requested") from None


def _write_governed_audio(args, raw: bytes, receipt: dict) -> int:
    output = pathlib.Path(args.output).expanduser()
    receipt["output"] = str(output.resolve())
    # Receipt first: a failed local save stays recoverable without repurchasing.
    with output.with_suffix(output.suffix + ".provenance.json").open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(receipt, indent=2) + "\n")
    with output.open("xb") as handle:
        handle.write(raw)
    print(json.dumps({"ok": True, "output": str(output), "acceptance_state": receipt["acceptance_state"],
                      "reused": receipt["reused"], "estimated_credits": receipt["estimated_credits"],
                      "actual_credits": receipt["actual_credits"]}))
    return 0


def sfx(args: argparse.Namespace) -> int:
    """Governed sound effect: POST /v1/sound-generation through the shared ledger."""
    import governed_audio
    payload = {"text": args.text, "duration_seconds": args.duration_seconds, "model_id": "eleven_text_to_sound_v2",
               **({"prompt_influence": args.prompt_influence} if args.prompt_influence is not None else {}),
               **({"loop": True} if args.loop else {})}
    if args.dry_run:
        print(json.dumps({"dry_run": True, "route": "sound-generation",
                          "estimated_credits": governed_audio.estimate_audio_credits("sound-generation", payload)}))
        return 0
    _audio_output_ready(args)
    raw, receipt = governed_audio.generate_audio(sys.modules[__name__], args, "sound-generation", payload["model_id"],
                                                 args.output_format or "mp3_44100_128", payload)
    return _write_governed_audio(args, raw, receipt)


def music(args: argparse.Namespace) -> int:
    """Governed instrumental music bed: POST /v1/music through the shared ledger."""
    import governed_audio
    model_id = args.model_id or "music_v2_5"
    payload = {"prompt": args.prompt, "music_length_ms": args.length_ms, "model_id": model_id, "force_instrumental": True}
    if args.dry_run:
        print(json.dumps({"dry_run": True, "route": "music",
                          "estimated_credits": governed_audio.estimate_audio_credits("music", payload)}))
        return 0
    _audio_output_ready(args)
    raw, receipt = governed_audio.generate_audio(sys.modules[__name__], args, "music", model_id,
                                                 args.output_format or "mp3_44100_128", payload)
    return _write_governed_audio(args, raw, receipt)


def multipart_file(fields: dict[str, str], file_field: str, file_path: pathlib.Path) -> tuple[bytes, str]:
    """Build a multipart payload without adding a third-party dependency."""
    boundary = f"----elevenlabs-{uuid.uuid4().hex}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
            value.encode("utf-8"),
            b"\r\n",
        ])
    content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    chunks.extend([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'.encode(),
        f"Content-Type: {content_type}\r\n\r\n".encode(),
        file_path.read_bytes(),
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def is_evidence_drive(path: pathlib.Path) -> bool:
    return str(path).upper().startswith("G:\\")


def transcribe(args: argparse.Namespace) -> int:
    raise RuntimeError("Paid STT is disabled until a conservative shared metering adapter is configured; use an authorized local route")



def main() -> int:
    parser = argparse.ArgumentParser(description="ElevenLabs capability CLI")
    sub = parser.add_subparsers(dest="command", required=True)
    p_health = sub.add_parser("health")
    p_health.set_defaults(func=health)
    p_account = sub.add_parser("account", help="Read-only credit and subscription summary; no identity or billing details")
    p_account.set_defaults(func=account)
    p_voice_status = sub.add_parser("voice-status", help="Read-only clone readiness; never downloads recordings")
    p_voice_status.add_argument("--voice-id", required=True)
    p_voice_status.set_defaults(func=voice_status)
    p_voices = sub.add_parser("voices")
    p_voices.set_defaults(func=voices)
    p_models = sub.add_parser("models", help="Read-only: list models available to this account (GET /v1/models)")
    p_models.set_defaults(func=models)
    p_tts = sub.add_parser("tts")
    p_tts.add_argument("--text", required=True)
    p_tts.add_argument("--output", required=True)
    p_tts.add_argument("--voice-id")
    p_tts.add_argument("--model-id")
    p_tts.add_argument("--dry-run", action="store_true", help="Check credits and model/clone readiness without generating")
    p_tts.add_argument("--max-credits", type=float, help="Refuse a request above this estimated credit budget")
    p_tts.add_argument("--governed", action="store_true", help="Compatibility flag; all paid TTS is governed")
    p_tts.add_argument("--cache-workspace", help="Authorized project/access boundary, required for paid TTS")
    p_tts.add_argument("--cache-revision", help="Locked voice/model/reference revision, required for paid TTS")
    p_tts.add_argument("--recovery-epoch-manifest", help="Explicit immutable bounded authorization when historical accounting is unavailable")
    p_tts.add_argument("--stability", type=float)
    p_tts.add_argument("--similarity-boost", type=float)
    p_tts.add_argument("--style", type=float)
    p_tts.add_argument("--speed", type=float)
    p_tts.add_argument(
        "--use-speaker-boost",
        action=argparse.BooleanOptionalAction,
        default=None,
    )
    p_tts.add_argument("--text-normalization", choices=["auto", "on", "off"])
    p_tts.add_argument("--previous-text")
    p_tts.add_argument("--next-text")
    p_tts.add_argument("--previous-request-id", action="append", help="Repeatable, max 3, oldest first; excludes --previous-text")
    p_tts.add_argument("--next-request-id", action="append", help="Repeatable, max 3, nearest first; excludes --next-text")
    p_tts.add_argument("--output-format", help=f"Query output_format (default {DEFAULT_OUTPUT_FORMAT} or ELEVENLABS_OUTPUT_FORMAT)")
    p_tts.add_argument("--pronunciation-dictionary", action="append", metavar="ID[:VERSION]", help="Repeatable, max 3, applied in order")
    p_tts.add_argument("--language-code")
    p_tts.add_argument("--seed", type=int)
    p_tts.add_argument("--with-timestamps", action="store_true",
                       help="POST /with-timestamps; also writes <output>.alignment.json (character alignment)")
    p_tts.set_defaults(func=tts)
    p_sfx = sub.add_parser("sfx", help="Governed sound effect (ledger-reserved, receipt-bound)")
    p_sfx.add_argument("--text", required=True)
    p_sfx.add_argument("--output", required=True)
    p_sfx.add_argument("--duration-seconds", type=float, required=True)
    p_sfx.add_argument("--prompt-influence", type=float)
    p_sfx.add_argument("--loop", action="store_true")
    p_sfx.add_argument("--output-format")
    p_sfx.add_argument("--dry-run", action="store_true", help="Print the credit reservation; no request")
    p_sfx.add_argument("--max-credits", type=float)
    p_sfx.add_argument("--cache-workspace")
    p_sfx.add_argument("--cache-revision")
    p_sfx.set_defaults(func=sfx)
    p_music = sub.add_parser("music", help="Governed instrumental music bed (ledger-reserved, receipt-bound)")
    p_music.add_argument("--prompt", required=True)
    p_music.add_argument("--output", required=True)
    p_music.add_argument("--length-ms", type=int, required=True)
    p_music.add_argument("--model-id")
    p_music.add_argument("--output-format")
    p_music.add_argument("--dry-run", action="store_true", help="Print the credit reservation; no request")
    p_music.add_argument("--max-credits", type=float)
    p_music.add_argument("--cache-workspace")
    p_music.add_argument("--cache-revision")
    p_music.set_defaults(func=music)
    p_transcribe = sub.add_parser("transcribe", help="Transcribe an explicitly approved, non-sensitive local file")
    p_transcribe.add_argument("--input", required=True)
    p_transcribe.add_argument("--output", required=True)
    p_transcribe.add_argument("--model-id")
    p_transcribe.add_argument("--language-code")
    p_transcribe.add_argument("--diarize", action="store_true")
    p_transcribe.add_argument("--tag-audio-events", action="store_true")
    p_transcribe.add_argument("--approve-cloud", action="store_true", help="Confirm this file is approved for cloud transcription")
    p_transcribe.set_defaults(func=transcribe)
    p_reconcile = sub.add_parser("reconcile", help="Provider GET-only history recovery/local settlement; never resubmits")
    p_reconcile.add_argument("--recovery-epoch-manifest", help="Select intact original epoch accounting by immutable authorization; never initializes an epoch")
    p_reconcile.add_argument("--existing-epoch-parent", help="Absolute existing original epoch parent for reconciliation only; requires --recovery-epoch-manifest")
    p_reconcile.add_argument("--namespace", required=True)
    p_reconcile.add_argument("--cache-workspace", required=True)
    p_reconcile.add_argument("--cache-key", required=True)
    p_reconcile.add_argument("--history-id", required=True)
    def reconcile(args):
        import governed_elevenlabs
        return governed_elevenlabs.reconcile(sys.modules[__name__], args)
    p_reconcile.set_defaults(func=reconcile)
    args = parser.parse_args()
    try:
        return args.func(args)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except (OSError, ValueError, ImportError):
        print("Local validation/storage failed; inspect the ledger before retrying any generation", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
