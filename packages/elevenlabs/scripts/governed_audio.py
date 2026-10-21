"""Governed ElevenLabs sound-effect and music generation for Media Studio marketing ads.

Same contract as governed_elevenlabs.generate (TTS): every paid call reserves credits in the shared content ledger,
binds the provider receipt, caches the exact bytes and never repeats a purchase for an identical request.
"""
from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.parse

import governed_elevenlabs as governed

AUDIO_ROUTES = {"sound-generation": "/sound-generation", "music": "/music"}
AUDIO_GATES = ("artifact",)


def estimate_audio_credits(route, payload):
    """Conservative integer reservation.

    Sound effects: the docs quote 40 credits/s and the pricing page 200 per generation; take the larger.
    Music: 900 credits/min plus a 15% margin. A request with no explicit length is refused, never guessed.
    """
    if route == "sound-generation":
        seconds = payload.get("duration_seconds")
        if not isinstance(seconds, (int, float)) or isinstance(seconds, bool) or not 0.5 <= seconds <= 30:
            raise RuntimeError("Sound effects require an explicit duration_seconds between 0.5 and 30")
        return max(200, int(-(-seconds * 40 // 1)))
    if route == "music":
        ms = payload.get("music_length_ms")
        if type(ms) is not int or not 3000 <= ms <= 600000:
            raise RuntimeError("Music requires an explicit music_length_ms between 3000 and 600000")
        return int(-(-ms * 900 * 1.15 // 60000))
    raise RuntimeError("Unknown governed audio route")


def generate_audio(cli, args, route, model_id, output_format, payload):
    """Return (raw bytes, receipt). Needs --cache-workspace, --cache-revision and an integer --max-credits."""
    if route not in AUDIO_ROUTES:
        raise RuntimeError("Unknown governed audio route")
    with governed.new_ledger().session() as ledger:
        return _generate_audio(ledger, cli, args, route, model_id, output_format, payload)


def _generate_audio(ledger, cli, args, route, model_id, output_format, payload):
    if not args.cache_workspace or not args.cache_revision:
        raise RuntimeError("Paid generation requires --cache-workspace and --cache-revision")
    if args.max_credits is None or not float(args.max_credits).is_integer() or args.max_credits <= 0:
        raise RuntimeError("Governed generation requires a positive integer --max-credits")
    estimate = estimate_audio_credits(route, payload)
    if estimate > args.max_credits:
        raise RuntimeError("Estimated credits exceed --max-credits")
    namespace = ledger.namespace(os.environ.get("ELEVENLABS_API_KEY", ""), args.cache_workspace)
    key = governed.runtime_module().request_key({
        "provider": "elevenlabs/rest/v1", "route": route, "model_id": model_id, "output_format": output_format,
        "revision": args.cache_revision, "payload": payload, "quality_policy": "marketing-audio-artifact-v1"})
    maximum = int(args.max_credits)
    deadline = time.monotonic() + 610
    reused = True
    while True:
        row = ledger.claim(namespace, key, "elevenlabs/credits", maximum, required_gates=AUDIO_GATES)
        if row["state"] == "leader":
            try:
                before = cli._account_summary(cli._get_json("/user/subscription"))
                if before["status"] != "active":
                    raise RuntimeError("An active subscription must be established before generation")
                if before["credits_remaining"] is None or row["maximum"] > before["credits_remaining"]:
                    raise RuntimeError("Reservation exceeds remaining quota or quota is unknown")
            except BaseException:
                ledger.cancel_prepared(row)
                raise
            ledger.submitted(row)
            reused = False

            def received(headers):
                receipt = headers.get("request-id") or headers.get("song-id")
                if receipt:
                    ledger.bind_receipt(row, receipt)

            try:
                query = urllib.parse.urlencode({"output_format": output_format})
                _, ctype, raw, headers = cli._request_full(
                    f"{AUDIO_ROUTES[route]}?{query}", method="POST", body=json.dumps(payload).encode("utf-8"),
                    content_type="application/json", timeout=300, on_headers=received, governed_submission=True)
                received(headers)
                if not raw or not (ctype.startswith("audio/") or ctype == "application/octet-stream"):
                    raise RuntimeError("Provider returned no audio")
                receipt = headers.get("request-id") or headers.get("song-id")
                if not receipt:
                    # No provider id on this route: bind a content-derived id so reuse and audit still work.
                    receipt = "no-provider-id:" + hashlib.sha256(raw).hexdigest()[:32]
                    ledger.bind_receipt(row, receipt)
                actual = None
                try:
                    after = cli._account_summary(cli._get_json("/user/subscription"))
                    spent = after["character_count"] - before["character_count"]
                    if type(spent) is int and 0 < spent <= 2 * row["maximum"]:
                        actual = spent
                except Exception:  # noqa: BLE001 - settlement stays at the reserved maximum
                    actual = None
                row = ledger.complete(row, raw, ctype, receipt, actual)
            except BaseException:
                if not ledger.unknown(row):
                    raise RuntimeError("Submission state changed; inspect its existing receipt before any retry.") from None
                raise RuntimeError("Submission unresolved; reservation retained. Recover provider history before retrying.") from None
        if row["state"] in ("pending", "accepted"):
            raw = ledger.read_asset(row)
            return raw, {
                "provider": "elevenlabs", "route": route, "namespace": namespace, "cache_key": key,
                "request_id": row["receipt"], "model_id": model_id, "output_format": output_format,
                "output_sha256": row["sha256"], "content_type": row["content_type"], "output_bytes": len(raw),
                "maximum_reserved_credits": row["maximum"], "estimated_credits": estimate,
                "actual_credits": row["actual"], "acceptance_state": row["state"], "reused": reused,
                "payload_sha256": hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()}
        if row["state"] == "unknown":
            raise RuntimeError("Existing submission unresolved; recover its provider receipt. No repeat purchase allowed.")
        if time.monotonic() >= deadline:
            raise RuntimeError("Existing generation is still in progress; no repeat purchase allowed")
        time.sleep(.05)
