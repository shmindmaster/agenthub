"""ElevenLabs adapter for Media Studio's local, shared content ledger."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import pathlib
import time
import urllib.parse
from functools import lru_cache


@lru_cache(maxsize=1)
def runtime_module():
    hub = pathlib.Path(__file__).resolve().parents[3]
    source = hub / "packages/media-studio/scripts/content_runtime.py"
    if not source.is_file():
        raise RuntimeError("Canonical Media Studio content runtime is required; paid generation disabled")
    spec = importlib.util.spec_from_file_location("agenthub_content_runtime", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def new_ledger(root=None):
    return runtime_module().Ledger(root)


def generate(cli, args, voice_id, model_id, output_format, payload, with_timestamps=False):
    with new_ledger().session() as ledger:
        return _generate(ledger, cli, args, voice_id, model_id, output_format, payload, with_timestamps)


def _generate(ledger, cli, args, voice_id, model_id, output_format, payload, with_timestamps=False):
    if not args.cache_workspace or not args.cache_revision:
        raise RuntimeError("Paid generation requires --cache-workspace and --cache-revision")
    if args.max_credits is None or not args.max_credits.is_integer() or args.max_credits <= 0:
        raise RuntimeError("Governed generation requires a positive integer --max-credits")
    for locator in payload.get("pronunciation_dictionary_locators", []):
        if not locator.get("pronunciation_dictionary_id") or not locator.get("version_id"):
            raise RuntimeError("Governed generation requires versioned pronunciation dictionaries")
    required = {"stability", "similarity_boost"}
    if not model_id.startswith("eleven_v4"):
        required |= {"style", "speed", "use_speaker_boost"}
    if not required <= payload.get("voice_settings", {}).keys() or "apply_text_normalization" not in payload:
        raise RuntimeError("Governed generation requires explicit voice settings and text normalization")
    namespace = ledger.namespace(os.environ.get("ELEVENLABS_API_KEY", ""), args.cache_workspace)
    request = {"provider": "elevenlabs/rest/v1", "voice_id": voice_id,
               "model_id": model_id, "output_format": output_format,
               "revision": args.cache_revision, "payload": payload,
               "quality_policy": "owner-voice-five-gates-v1"}
    if with_timestamps:
        # Added only when set, so every existing audio-only key keeps resolving to its saved bytes.
        request["endpoint"] = "with-timestamps"
    key = runtime_module().request_key(request)
    maximum = int(args.max_credits)
    deadline = time.monotonic() + 610
    reused = True
    while True:
        row = ledger.claim(namespace, key, "elevenlabs/credits", maximum)
        if row["state"] == "leader":
            try:
                # A replacement of a never-submitted lease inherits its original
                # reservation, even if this caller offers a larger maximum.
                cli.tts_preflight(voice_id, model_id, args.text, row["maximum"])
            except BaseException:
                ledger.cancel_prepared(row)
                raise
            ledger.submitted(row)
            reused = False
            def received(headers):
                if headers.get("request-id"):
                    ledger.bind_receipt(row, headers.get("request-id"))
            try:
                query = urllib.parse.urlencode({"output_format": output_format})
                suffix = "/with-timestamps" if with_timestamps else ""
                _, ctype, raw, headers = cli._request_full(
                    f"/text-to-speech/{urllib.parse.quote(voice_id, safe='')}{suffix}?{query}",
                    method="POST", body=json.dumps(payload).encode("utf-8"),
                    content_type="application/json", timeout=300, on_headers=received,
                    governed_submission=True)
                received(headers)
                if with_timestamps:
                    if ctype != "application/json":
                        raise RuntimeError("Provider returned no timestamped audio")
                    cli.split_timestamped_response(raw)
                elif not raw or not (ctype.startswith("audio/") or ctype == "application/octet-stream"):
                    raise RuntimeError("Provider returned no audio")
                row = ledger.complete(row, raw, ctype, headers.get("request-id"))
            except BaseException:
                if not ledger.unknown(row):
                    raise RuntimeError("Submission state changed; inspect its existing receipt before any retry.") from None
                raise RuntimeError("Submission unresolved; reservation retained. Recover provider history before retrying.") from None
        if row["state"] in ("pending", "accepted"):
            raw = ledger.read_asset(row)
            return raw, {"provider": "elevenlabs", "namespace": namespace, "cache_key": key,
                         "request_id": row["receipt"], "model_id": model_id, "voice_id": voice_id,
                         "output_format": output_format, "output_sha256": row["sha256"],
                         "content_type": row["content_type"], "output_bytes": len(raw),
                         "maximum_reserved_credits": row["maximum"], "actual_credits": row["actual"],
                         "acceptance_state": row["state"], "acceptance": json.loads(row["acceptance"] or "null"),
                         "reused": reused, "text_sha256": hashlib.sha256(args.text.encode()).hexdigest()}
        if row["state"] == "unknown":
            raise RuntimeError("Existing submission unresolved; recover its provider receipt. No repeat purchase allowed.")
        if time.monotonic() >= deadline:
            raise RuntimeError("Existing generation is still in progress; no repeat purchase allowed")
        time.sleep(.05)


def reconcile(cli, args):
    """Read-only provider reconciliation; no POST and no similarity-based matching."""
    ledger = new_ledger()
    if ledger.namespace(os.environ.get("ELEVENLABS_API_KEY", ""), args.cache_workspace) != args.namespace:
        raise RuntimeError("Recovery credential/workspace does not match this request namespace")
    row = ledger.lookup(args.namespace, args.cache_key)
    if not row or not row["receipt"]:
        raise RuntimeError("Recovery requires a request ID saved during submission; unknown IDs cannot be retried")
    history = cli._get_json("/history/" + urllib.parse.quote(args.history_id, safe=""))
    if history.get("request_id") != row["receipt"] or history.get("history_item_id") != args.history_id:
        raise RuntimeError("Provider history does not match the saved request ID")
    before, after = history.get("character_count_change_from"), history.get("character_count_change_to")
    actual = after - before if type(before) is int and type(after) is int and after >= before else None
    if actual is None:
        raise RuntimeError("Provider billing is unknown; reservation retained")
    if row["state"] in ("submitted", "unknown"):
        _, ctype, raw = cli.request("/history/" + urllib.parse.quote(args.history_id, safe="") + "/audio")
        if not ctype.startswith("audio/"):
            raise RuntimeError("Provider history returned no audio")
        ledger.recover(args.namespace, args.cache_key, raw, ctype, row["receipt"], actual)
    else:
        ledger.settle(args.namespace, args.cache_key, actual, row["receipt"])
    print(json.dumps({"reconciled": True, "actual_credits": actual, "acceptance_state": "pending" if row["state"] in ("submitted", "unknown") else row["state"]}))
    return 0
