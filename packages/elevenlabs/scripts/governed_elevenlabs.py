"""ElevenLabs adapter for Media Studio's local, shared content ledger."""
from __future__ import annotations

import hashlib
import hmac
import importlib.util
import json
import os
import pathlib
import re
import sqlite3
import time
import urllib.parse
from contextlib import closing
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
    recovery = getattr(args, "recovery_epoch_manifest", None)
    request = speech_request(args, voice_id, model_id, output_format, payload, with_timestamps)
    ledger = (runtime_module().recovery_epoch_ledger(recovery, args.cache_workspace, args.text, model_id, request=request)
              if recovery else new_ledger())
    with ledger.session() as ledger:
        return _generate(ledger, cli, args, voice_id, model_id, output_format, payload, with_timestamps)


def speech_request(args, voice_id, model_id, output_format, payload, with_timestamps=False):
    request = {"provider": "elevenlabs/rest/v1", "voice_id": voice_id,
               "model_id": model_id, "output_format": output_format,
               "revision": args.cache_revision, "payload": payload,
               "quality_policy": "owner-voice-five-gates-v1"}
    if with_timestamps:
        request["endpoint"] = "with-timestamps"
    return request


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
    request = speech_request(args, voice_id, model_id, output_format, payload, with_timestamps)
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
                preflight = cli.tts_preflight(voice_id, model_id, args.text, row["maximum"])
                if recovery_epoch := getattr(ledger, "recovery_epoch", None):
                    if preflight.get("can_extend_character_limit") is not False:
                        raise RuntimeError("Recovery epoch requires live overages disabled")
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
            except BaseException as exc:
                if getattr(exc, "status", None) == 429:
                    # 429 is a rate/concurrency refusal before generation: nothing was produced or billed.
                    ledger.reject(row)
                    raise RuntimeError("ElevenLabs rate limited the request (HTTP 429); nothing was generated and the "
                                       "reservation was released. Retry the same request later.") from None
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
                         **({"recovery_epoch": ledger.recovery_epoch,
                             "historical_accounting": "UNKNOWN", "historical_requests": "FENCED"}
                            if getattr(ledger, "recovery_epoch", None) else {}),
                         "acceptance_state": row["state"], "acceptance": json.loads(row["acceptance"] or "null"),
                         "reused": reused, "text_sha256": hashlib.sha256(args.text.encode()).hexdigest()}
        if row["state"] == "unknown":
            raise RuntimeError("Existing submission unresolved; recover its provider receipt. No repeat purchase allowed.")
        if time.monotonic() >= deadline:
            raise RuntimeError("Existing generation is still in progress; no repeat purchase allowed")
        time.sleep(.05)


def reconciliation_epoch_parent(existing=None):
    """Select existing original accounting without creating or relocating it."""
    runtime = runtime_module()
    if existing is not None:
        parent = pathlib.Path(existing)
        # Check lexical ancestors before resolve can hide a symlink/junction.
        if (not parent.is_absolute() or not parent.is_dir()
                or any(runtime.linked_path(path) for path in (parent, *parent.parents))):
            raise RuntimeError("Reconciliation requires an absolute existing unlinked epoch parent")
        return parent.resolve()
    base = os.environ.get("LOCALAPPDATA") if runtime.running_on_windows() else str(pathlib.Path.home() / ".local/share")
    if not base:
        raise RuntimeError("Cannot resolve private local runtime directory")
    return (pathlib.Path(base) / "AgentHub/runtime/content-recovery-epochs").resolve()


def reconciliation_epoch(args):
    """Open intact original epoch accounting; never initialize or authorize speech."""
    runtime = runtime_module()
    manifest = pathlib.Path(args.recovery_epoch_manifest)
    if not manifest.is_absolute() or not manifest.is_file() or runtime.linked_path(manifest):
        raise RuntimeError("Reconciliation requires the original absolute epoch authorization")
    raw = manifest.read_bytes()
    policy = json.loads(raw)
    epoch = policy.get("epoch_id", "")
    if (not isinstance(epoch, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", epoch)
            or policy.get("workspace") != args.cache_workspace
            or not policy.get("owner_authorization")
            or type(policy.get("maximum_credits")) is not int or policy["maximum_credits"] <= 0
            or policy.get("historical_accounting") != "UNKNOWN"
            or policy.get("historical_requests") != "FENCED"):
        raise RuntimeError("Reconciliation epoch authorization/workspace mismatch")
    root = reconciliation_epoch_parent(getattr(args, "existing_epoch_parent", None)) / epoch
    if any(runtime.linked_path(path) for path in (root, *root.parents)):
        raise RuntimeError("Reconciliation refuses linked epoch accounting")
    files = [root / name for name in ("authorization.json", "ledger.sqlite3", "namespace-salt")]
    if (not root.is_dir() or not all(path.is_file() and not runtime.linked_path(path) for path in files)
            or not (root / "assets").is_dir() or runtime.linked_path(root / "assets")):
        raise RuntimeError("Existing epoch accounting incomplete; restore originals without initialization")
    authorization, database, salt_path = files
    salt = salt_path.read_bytes()
    if authorization.read_bytes() != raw or len(salt) != 32:
        raise RuntimeError("Existing epoch authorization or namespace salt mismatch")
    credential = os.environ.get("ELEVENLABS_API_KEY", "")
    if not credential or not args.cache_workspace:
        raise RuntimeError("Explicit credential and authorized cache workspace required")
    namespace = hmac.new(salt, (credential + "\0" + args.cache_workspace).encode(), hashlib.sha256).hexdigest()
    if namespace != args.namespace:
        raise RuntimeError("Recovery credential/workspace does not match this request namespace")
    # Inspect with SQLite read-only first: Ledger's constructor must not repair
    # a missing schema, create a budget, or replace a missing accounting file.
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as con:
        if con.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise RuntimeError("Existing epoch ledger failed integrity check")
        budget = con.execute("SELECT ceiling FROM budgets WHERE bucket='elevenlabs/credits'").fetchone()
        row = con.execute("SELECT bucket,receipt,state FROM requests WHERE namespace=? AND key=?",
                          (args.namespace, args.cache_key)).fetchone()
        if budget != (policy["maximum_credits"],):
            raise RuntimeError("Existing epoch ceiling does not match immutable authorization")
        if not row or row[0] != "elevenlabs/credits" or not row[1] or row[2] not in ("submitted", "unknown", "pending", "accepted"):
            raise RuntimeError("Recovery requires an existing receipt-bound epoch submission")
    return new_ledger(root)


def reconcile(cli, args):
    """Provider GET-only reconciliation; settles existing local accounting."""
    epoch = getattr(args, "recovery_epoch_manifest", None)
    if getattr(args, "existing_epoch_parent", None) is not None and not epoch:
        raise RuntimeError("An existing epoch parent requires the original epoch authorization")
    ledger = reconciliation_epoch(args) if epoch else new_ledger()
    if not epoch and ledger.namespace(os.environ.get("ELEVENLABS_API_KEY", ""), args.cache_workspace) != args.namespace:
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
