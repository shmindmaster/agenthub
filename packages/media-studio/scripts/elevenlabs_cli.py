#!/usr/bin/env python3
"""Owner-authorized ElevenLabs speech, dialogue, sound effects and music for Media Studio. Dependency-free.

Every provider call needs an immutable owner manifest naming the exact request and job workspace.
There is no default voice, model or budget. The quote subcommands are offline and need no credential.
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
GOVERNED_POST_PATHS = frozenset({"/text-to-dialogue", "/sound-generation", "/music"})
DIALOGUE_MAX_TEXT_CHARS = 2000
DIALOGUE_MAX_VOICES = 10
SEED_MAX = 4294967295
SFX_GENERATION_CREDITS = 200
MUSIC_CREDITS_PER_MINUTE = 900
MUSIC_LENGTH_RANGE = (3000, 600000)


class ProviderHTTPError(RuntimeError):
    """An HTTP error status from the provider; the message carries only the status and a sanitized code."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """The key is a request header, so a followed redirect would carry it to the new origin."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _request_full(path, method="GET", body=None, content_type=None, timeout=30, on_headers=None, governed_submission=False):
    allowed = path.startswith(GOVERNED_POST_PREFIX) or path.partition("?")[0] in GOVERNED_POST_PATHS
    if method != "GET" and not (governed_submission and method == "POST" and allowed):
        raise RuntimeError("Paid requests require the governed route; this route is disabled")
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


def _prepare_output(args):
    """Refuse before any spend when the destination or its receipt is taken or unwritable."""
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
    return output, receipt_path


def _write_output(output, receipt_path, raw, receipt):
    receipt["output"] = str(output.resolve())
    # Save the receipt first; a failed local save remains recoverable without repurchasing.
    with receipt_path.open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(receipt, indent=2) + "\n")
    with output.open("xb") as handle:
        handle.write(raw)
    print(json.dumps({"ok": True, "output": str(output), "acceptance_state": receipt["acceptance_state"], "reused": receipt["reused"]}))
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
    output, receipt_path = _prepare_output(args)
    raw, receipt = governed.generate(sys.modules[__name__], args, authorized, args.voice_id, args.model_id, args.output_format, payload)
    return _write_output(output, receipt_path, raw, receipt)


def _subscription():
    summary = _account_summary(_get_json("/user/subscription"))
    if summary["status"] != "active":
        raise RuntimeError("An active subscription must be established before generation")
    return summary


def _credit_gate(summary, estimate, max_credits):
    if max_credits is not None and (not math.isfinite(max_credits) or max_credits <= 0):
        raise RuntimeError("--max-credits must be a positive finite number")
    if estimate is None or summary["credits_remaining"] is None:
        raise RuntimeError("Credit estimate or remaining quota is unknown; inspect the provider's current metering before spending")
    if estimate > summary["credits_remaining"]:
        raise RuntimeError("Estimated credits exceed remaining quota; billing changes are not automatic")
    if max_credits is not None and estimate > max_credits:
        raise RuntimeError("Estimated credits exceed --max-credits")


def _effect_spec(args):
    """POST /v1/text-to-dialogue `audio_effects`: the same spec the speech endpoint documents."""
    effects = {}
    for name in ("filter_preset_id", "environment_id", "background_noise_id"):
        value = getattr(args, name, None)
        if value:
            effects[name] = value
    for name in ("distance", "send_level", "pan"):
        value = getattr(args, name, None)
        if value is not None:
            effects[name] = value
    if effects.get("distance") is not None and not 0 <= effects["distance"] <= 1:
        raise RuntimeError("Audio effect distance must be between 0 and 1")
    if effects.get("send_level") is not None and not 0 <= effects["send_level"] <= 1:
        raise RuntimeError("Audio effect send_level must be between 0 and 1")
    if effects.get("pan") is not None and not -1 <= effects["pan"] <= 1:
        raise RuntimeError("Audio effect pan must be between -1 and 1")
    codec = args.output_format.split("_")[0]
    if effects and codec in ("ulaw", "alaw", "pcm") and (
            effects.get("pan") or (effects.get("environment_id") and effects.get("send_level", 1) > 0)):
        raise RuntimeError("Reverb and pan are stereo; they are refused for ulaw, alaw and pcm output formats")
    return effects


def dialogue_payload(args):
    """The exact body sent to /v1/text-to-dialogue. Offline, so `dialogue-quote` hashes what `dialogue` submits."""
    turns = args.turn or []
    if not turns:
        raise RuntimeError("Dialogue requires at least one --turn VOICE_ID TEXT")
    inputs = []
    for voice_id, text in turns:
        if not voice_id or not text:
            raise RuntimeError("Every dialogue turn needs a voice ID and non-empty text")
        inputs.append({"text": text, "voice_id": voice_id})
    if len({item["voice_id"] for item in inputs}) > DIALOGUE_MAX_VOICES:
        raise RuntimeError(f"At most {DIALOGUE_MAX_VOICES} unique voices per dialogue request")
    if not 0 < sum(len(item["text"]) for item in inputs) <= DIALOGUE_MAX_TEXT_CHARS:
        raise RuntimeError(f"Dialogue input text must total at most {DIALOGUE_MAX_TEXT_CHARS} characters")
    if args.seed is not None and not 0 <= args.seed <= SEED_MAX:
        raise RuntimeError(f"Seed must be an integer between 0 and {SEED_MAX}")
    payload = {"inputs": inputs, "model_id": args.model_id}
    if args.seed is not None:
        payload["seed"] = args.seed
    effects = _effect_spec(args)
    if effects:
        payload["audio_effects"] = effects
    return payload


def dialogue_content(payload):
    """The canonical string an owner manifest's text_sha256 pins for a dialogue request."""
    return json.dumps(payload["inputs"], sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sfx_payload(args):
    """The exact body sent to /v1/sound-generation."""
    if not args.prompt:
        raise RuntimeError("Sound effects require a --prompt")
    payload = {"text": args.prompt, "model_id": args.model_id}
    if args.duration_seconds is not None:
        if not math.isfinite(args.duration_seconds) or not 0.5 <= args.duration_seconds <= 30:
            raise RuntimeError("--duration-seconds must be between 0.5 and 30")
        payload["duration_seconds"] = args.duration_seconds
    if args.prompt_influence is not None:
        if not math.isfinite(args.prompt_influence) or not 0 <= args.prompt_influence <= 1:
            raise RuntimeError("--prompt-influence must be between 0 and 1")
        payload["prompt_influence"] = args.prompt_influence
    if args.loop is not None:
        payload["loop"] = args.loop
    return payload


def _composition_plan(value):
    try:
        plan = json.loads(pathlib.Path(value).expanduser().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise RuntimeError("Composition plan must be a readable JSON file") from None
    if not isinstance(plan, dict) or not isinstance(plan.get("chunks"), list) or not plan["chunks"]:
        raise RuntimeError("A music_v2_5 composition plan is a JSON object with a non-empty chunks list")
    length = 0
    for chunk in plan["chunks"]:
        if (isinstance(chunk, dict) and isinstance(chunk.get("text"), str)
                and type(chunk.get("duration_ms")) is int and isinstance(chunk.get("positive_styles"), list)):
            if not 3000 <= chunk["duration_ms"] <= 120000:
                raise RuntimeError("Each generation chunk's duration_ms must be between 3000 and 120000")
            length += chunk["duration_ms"]
        elif isinstance(chunk, dict) and isinstance(chunk.get("song_id"), str) and isinstance(chunk.get("range"), dict):
            span = chunk["range"]
            if not (type(span.get("start_ms")) is int and type(span.get("end_ms")) is int
                    and 0 <= span["start_ms"] < span["end_ms"]):
                raise RuntimeError("Each audio reference chunk needs song_id and a valid range")
            length += span["end_ms"] - span["start_ms"]
        else:
            raise RuntimeError("Each plan chunk must be a generation chunk (text, duration_ms, positive_styles) "
                               "or an audio reference (song_id, range)")
    return plan, length


def music_payload(args):
    """The exact body sent to /v1/music, and the determinable song length in ms for the credit estimate."""
    if bool(args.prompt) == bool(args.composition_plan):
        raise RuntimeError("Music needs exactly one of --prompt or --composition-plan")
    payload = {"model_id": args.model_id}
    if args.prompt:
        if args.seed is not None:
            raise RuntimeError("The API accepts seed only with a composition plan, never with a prompt")
        payload["prompt"] = args.prompt
        payload["force_instrumental"] = True
        if args.music_length_ms is not None:
            if not MUSIC_LENGTH_RANGE[0] <= args.music_length_ms <= MUSIC_LENGTH_RANGE[1]:
                raise RuntimeError(f"--music-length-ms must be between {MUSIC_LENGTH_RANGE[0]} and {MUSIC_LENGTH_RANGE[1]}")
            payload["music_length_ms"] = args.music_length_ms
        return payload, args.music_length_ms
    if args.music_length_ms is not None:
        raise RuntimeError("The API applies --music-length-ms to a prompt only; a plan's length comes from its chunks")
    plan, length = _composition_plan(args.composition_plan)
    payload["composition_plan"] = plan
    if args.seed is not None:
        if not 0 <= args.seed <= SEED_MAX:
            raise RuntimeError(f"Seed must be an integer between 0 and {SEED_MAX}")
        payload["seed"] = args.seed
    return payload, length


def dialogue_preflight(inputs, model_id, max_credits):
    summary = _subscription()
    for item in inputs:
        voice = _voice_summary(_get_json("/voices/" + urllib.parse.quote(item["voice_id"], safe="")))
        if voice["requires_verification"] is True:
            raise RuntimeError("Voice requires owner verification; generation stopped")
        if voice["category"] == "professional" and (voice["model_states"] or {}).get(model_id) != "fine_tuned":
            raise RuntimeError("Professional clone is not established as fine_tuned on the requested model; "
                               "select a ready model explicitly")
    model = next((m for m in _get_json("/models") if m.get("model_id") == model_id and m.get("can_do_text_to_speech")), None)
    if model is None:
        raise RuntimeError("Requested dialogue model is absent from the live model inventory")
    total = sum(len(item["text"]) for item in inputs)
    _credit_gate(summary, total, max_credits)  # dialogue meters at one credit per input character
    return {"voice_ids": sorted({item["voice_id"] for item in inputs}), "model_id": model_id,
            "input_characters": total, "estimated_credits": total,
            "credits_remaining": summary["credits_remaining"],
            "can_extend_character_limit": summary["can_extend_character_limit"],
            "text_sha256": hashlib.sha256(dialogue_content({"inputs": inputs}).encode("utf-8")).hexdigest()}


def sfx_preflight(max_credits):
    summary = _subscription()
    _credit_gate(summary, SFX_GENERATION_CREDITS, max_credits)
    return {"estimated_credits": SFX_GENERATION_CREDITS,
            "credits_remaining": summary["credits_remaining"],
            "can_extend_character_limit": summary["can_extend_character_limit"]}


def music_preflight(length_ms, max_credits):
    summary = _subscription()
    estimate = (math.ceil(MUSIC_CREDITS_PER_MINUTE * length_ms / 60000)
                if type(length_ms) is int and length_ms > 0 else None)
    _credit_gate(summary, estimate, max_credits)
    return {"music_length_ms": length_ms, "estimated_credits": estimate,
            "credits_remaining": summary["credits_remaining"],
            "can_extend_character_limit": summary["can_extend_character_limit"]}


def _lane_paid(args, operation, content, payload, authorized, preflight, extra):
    if args.dry_run:
        print(json.dumps({"dry_run": True, **preflight(args.max_credits)}))
        return 0
    if args.max_credits is None or not args.max_credits.is_integer() or args.max_credits <= 0:
        raise RuntimeError("Paid generation requires a positive integer --max-credits")
    output, receipt_path = _prepare_output(args)
    raw, receipt = governed.generate_lane(sys.modules[__name__], args, authorized, operation,
                                          content, args.output_format, payload, preflight, extra)
    return _write_output(output, receipt_path, raw, receipt)


def dialogue_quote(args):
    payload = dialogue_payload(args)
    print(json.dumps(governed.lane_quote(args, "text-to-dialogue", dialogue_content(payload), args.output_format, payload)))
    return 0


def dialogue(args):
    if not args.authorization_manifest:
        raise RuntimeError("ElevenLabs dialogue requires an immutable owner authorization manifest; "
                           "nothing was reserved or requested")
    payload = dialogue_payload(args)
    voices = [item["voice_id"] for item in payload["inputs"]]
    authorized = governed.authorized_lane_policy(args.authorization_manifest, "text-to-dialogue",
                                                 args.cache_workspace, voices)
    return _lane_paid(args, "text-to-dialogue", dialogue_content(payload), payload, authorized,
                      lambda maximum: dialogue_preflight(payload["inputs"], args.model_id, maximum),
                      {"voice_ids": sorted(set(voices))})


def sfx_quote(args):
    payload = sfx_payload(args)
    print(json.dumps(governed.lane_quote(args, "sound-generation", payload["text"], args.output_format, payload)))
    return 0


def sfx(args):
    if not args.authorization_manifest:
        raise RuntimeError("ElevenLabs sound effects require an immutable owner authorization manifest; "
                           "nothing was reserved or requested")
    payload = sfx_payload(args)
    authorized = governed.authorized_lane_policy(args.authorization_manifest, "sound-generation", args.cache_workspace)
    return _lane_paid(args, "sound-generation", payload["text"], payload, authorized, sfx_preflight, {})


def _music_content(args, payload):
    if args.prompt:
        return args.prompt
    return json.dumps(payload["composition_plan"], sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def music_quote(args):
    payload, _length = music_payload(args)
    print(json.dumps(governed.lane_quote(args, "music", _music_content(args, payload), args.output_format, payload)))
    return 0


def music(args):
    if not args.authorization_manifest:
        raise RuntimeError("ElevenLabs music requires an immutable owner authorization manifest; "
                           "nothing was reserved or requested")
    payload, length = music_payload(args)
    authorized = governed.authorized_lane_policy(args.authorization_manifest, "music", args.cache_workspace)
    return _lane_paid(args, "music", _music_content(args, payload), payload, authorized,
                      lambda maximum: music_preflight(length, maximum), {})


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


def _lane_arguments(parser):
    parser.add_argument("--cache-workspace", required=True, help="Job workspace the owner manifest names")
    parser.add_argument("--cache-revision", required=True, help="Locked request/plan revision")


def dialogue_arguments(parser):
    _lane_arguments(parser)
    parser.add_argument("--turn", action="append", nargs=2, metavar=("VOICE_ID", "TEXT"),
                        help="One dialogue input; repeat per turn, max 10 unique voices")
    parser.add_argument("--model-id", required=True, choices=["eleven_v4"])
    parser.add_argument("--seed", type=int)
    parser.add_argument("--output-format", default=DEFAULT_OUTPUT_FORMAT)
    parser.add_argument("--filter-preset-id", help="Audio effect filter preset, e.g. phone")
    parser.add_argument("--environment-id", help="Audio effect reverb environment, e.g. small_room")
    parser.add_argument("--background-noise-id", help="Audio effect background noise bed, e.g. cafe")
    parser.add_argument("--distance", type=float)
    parser.add_argument("--send-level", type=float)
    parser.add_argument("--pan", type=float)


def sfx_arguments(parser):
    _lane_arguments(parser)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--model-id", required=True, choices=["eleven_text_to_sound_v3"])
    parser.add_argument("--duration-seconds", type=float)
    parser.add_argument("--prompt-influence", type=float)
    parser.add_argument("--loop", action=argparse.BooleanOptionalAction, default=None)
    parser.add_argument("--output-format", default=DEFAULT_OUTPUT_FORMAT)


def music_arguments(parser):
    _lane_arguments(parser)
    parser.add_argument("--prompt")
    parser.add_argument("--composition-plan", metavar="PATH",
                        help="JSON file: {chunks: [generation or audio-reference chunks]} for music_v2_5")
    parser.add_argument("--music-length-ms", type=int)
    parser.add_argument("--seed", type=int, help="Composition-plan requests only")
    parser.add_argument("--model-id", required=True, choices=["music_v2_5"])
    parser.add_argument("--output-format", default="auto")


def _paid_arguments(parser):
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-credits", type=float, help="Integer reservation for this request")
    parser.add_argument("--authorization-manifest", help="Absolute immutable owner manifest naming this request and workspace")
    parser.add_argument("--dry-run", action="store_true", help="Check credits and readiness without generating")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p_quote = sub.add_parser("quote", help="Offline: print the hashes an owner manifest must carry; no credential, no request")
    speech_arguments(p_quote)
    p_quote.set_defaults(func=quote)
    p_tts = sub.add_parser("tts", help="Owner-authorized speech (ledger-reserved, receipt-bound)")
    speech_arguments(p_tts)
    _paid_arguments(p_tts)
    p_tts.set_defaults(func=tts)
    for name, arg_fn, run_fn, op in (
            ("dialogue", dialogue_arguments, dialogue, "text-to-dialogue"),
            ("sfx", sfx_arguments, sfx, "sound-generation"),
            ("music", music_arguments, music, "music")):
        p_q = sub.add_parser(f"{name}-quote",
                             help=f"Offline: print the hashes an owner {name} manifest must carry")
        arg_fn(p_q)
        p_q.set_defaults(func={"dialogue": dialogue_quote, "sfx": sfx_quote, "music": music_quote}[name])
        p_run = sub.add_parser(name, help=f"Owner-authorized {op} generation (ledger-reserved, receipt-bound)")
        arg_fn(p_run)
        _paid_arguments(p_run)
        p_run.set_defaults(func=run_fn)
    p_adopt = sub.add_parser("adopt-old-epochs", help="Offline: copy pre-pin epoch ledgers under the pinned root")
    p_adopt.set_defaults(func=lambda args: print(json.dumps({"adopted": governed.adopt_old_epochs()})) or 0)
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
