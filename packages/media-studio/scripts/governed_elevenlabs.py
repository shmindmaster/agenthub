"""ElevenLabs speech against Media Studio's shared content ledger, owner-authorized jobs only."""
from __future__ import annotations

import contextlib
import hashlib
import hmac
import json
import os
import pathlib
import re
import sqlite3
import time
import urllib.parse

import content_control
import content_runtime as runtime

PROJECT_KIND = "elevenlabs-owner-authorized-project-epoch-v2"
CORRECTION_KIND = "elevenlabs-project-delivery-correction-v1"
BUCKET = "elevenlabs/credits"


def speech_request(args, voice_id, model_id, output_format, payload):
    return {"provider": "elevenlabs/rest/v1", "voice_id": voice_id, "model_id": model_id,
            "output_format": output_format, "revision": args.cache_revision, "payload": payload,
            "quality_policy": "owner-voice-five-gates-v1"}


def quote(args, voice_id, model_id, output_format, payload):
    """Everything an owner manifest pins for this exact request. No credential, no request, no state."""
    return {"voice_id": voice_id, "workspace": args.cache_workspace, "model_id": model_id,
            "output_format": output_format, "request_revision": args.cache_revision,
            "text_sha256": hashlib.sha256(args.text.encode("utf-8")).hexdigest(),
            "request_sha256": runtime.request_key(speech_request(args, voice_id, model_id, output_format, payload)),
            "pronunciation_locators_sha256": runtime.request_key(payload.get("pronunciation_dictionary_locators", []))}


def _manifest_bytes(path, refusal):
    path = pathlib.Path(path)
    if not path.is_absolute() or not path.is_file() or runtime.linked_path(path):
        raise RuntimeError(refusal)
    return path.read_bytes()


def authorized_policy(manifest, voice_id, workspace, model_id):
    """The one gate for every voice: the manifest must name this exact voice, workspace and model.

    project_v2_ledger still applies its own checks, to the checked bytes returned here. This gate refuses the
    epoch kinds that pin no voice, and it refuses before a dry run reaches the provider or a paid run creates
    any accounting.
    """
    refusal = "Owner authorization must be an absolute, unlinked project manifest"
    checked = _manifest_bytes(manifest, refusal)
    policy = json.loads(checked)
    pinned_model = None
    if isinstance(policy, dict) and policy.get("kind") == CORRECTION_KIND:
        pinned_model = policy.get("model_id")
        parent = policy.get("parent_authorization")
        parent = parent if isinstance(parent, dict) else {}
        raw = _manifest_bytes(parent.get("path", ""), refusal)
        if hashlib.sha256(raw).hexdigest() != parent.get("sha256"):
            raise RuntimeError("Correction parent authorization hash changed")
        policy = json.loads(raw)
    if not isinstance(policy, dict) or policy.get("kind") != PROJECT_KIND:
        raise RuntimeError(refusal)
    if not voice_id or policy.get("voice_id") != voice_id or policy.get("workspace") != workspace:
        raise RuntimeError("Owner authorization does not name this exact voice and job workspace")
    if (pinned_model or policy.get("model_id")) != model_id:
        raise RuntimeError("Owner authorization pins a different model")
    return checked, policy


def refuse_bought_elsewhere(key, own_epoch):
    """A request hash buys once under the stable root. Accounting that cannot be read refuses the purchase."""
    parent = runtime.stable_epoch_parent()
    if not parent.exists():  # A POSIX account's first epoch; Windows has already refused a missing root.
        return
    for root in sorted(parent.iterdir()):
        database = root / "ledger.sqlite3"
        if root.name == own_epoch or not (root.is_dir() or runtime.linked_path(root)):
            continue
        try:
            if runtime.linked_path(root) or runtime.linked_path(database):
                raise OSError("linked accounting")
            with contextlib.closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as con:
                found = con.execute("SELECT 1 FROM requests WHERE key=? LIMIT 1", (key,)).fetchone()
        except (OSError, sqlite3.Error):
            raise RuntimeError(f"Cannot read epoch {root.name} accounting; no purchase until it is intact") from None
        if found:
            raise RuntimeError(f"Request already exists in epoch {root.name} (cache_key {key}). No repeat purchase allowed.")


def generate(cli, args, authorized, voice_id, model_id, output_format, payload):
    """Return (raw bytes, receipt). Spend happens only inside the manifest's own epoch ledger: the default
    ledger is never opened here, so a ceiling configured there authorizes nothing."""
    request = speech_request(args, voice_id, model_id, output_format, payload)
    checked, policy = authorized
    refuse_bought_elsewhere(runtime.request_key(request), policy.get("epoch_id"))
    ledger = runtime.project_v2_ledger(checked, args.cache_workspace, args.text, model_id, request)
    with ledger.session() as ledger:
        return _generate(ledger, cli, args, voice_id, model_id, output_format, payload, request)


def _generate(ledger, cli, args, voice_id, model_id, output_format, payload, request):
    namespace = ledger.namespace(os.environ.get("ELEVENLABS_API_KEY", ""), args.cache_workspace)
    key = runtime.request_key(request)
    maximum = int(args.max_credits)
    deadline = time.monotonic() + 610
    reused = True
    while True:
        row = ledger.claim(namespace, key, BUCKET, maximum, fence_other_namespaces=True)
        if row["state"] == "leader":
            try:
                # A replacement of a never-submitted lease inherits its original
                # reservation, even if this caller offers a larger maximum.
                preflight = cli.tts_preflight(voice_id, model_id, args.text, row["maximum"])
                if preflight.get("can_extend_character_limit") is not False:
                    raise RuntimeError("Owner-authorized speech requires live overages disabled")
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
                _, ctype, raw, headers = cli._request_full(
                    f"/text-to-speech/{urllib.parse.quote(voice_id, safe='')}?{query}",
                    method="POST", body=json.dumps(payload).encode("utf-8"),
                    content_type="application/json", timeout=300, on_headers=received,
                    governed_submission=True)
                received(headers)
                if not raw or not (ctype.startswith("audio/") or ctype == "application/octet-stream"):
                    raise RuntimeError("Provider returned no audio")
                row = ledger.complete(row, raw, ctype, headers.get("request-id"))
            except BaseException as exc:
                # Every failure, HTTP 429 included, fences this request. Nothing here retries or releases it.
                status = f"{exc}. " if isinstance(exc, cli.ProviderHTTPError) else ""
                if not ledger.unknown(row):
                    raise RuntimeError("Submission state changed; inspect its existing receipt before any retry.") from None
                raise RuntimeError(f"{status}Submission unresolved (cache_key {key}); reservation retained. "
                                   "No automatic retry; report this and recover provider history.") from None
        if row["state"] in ("pending", "accepted"):
            raw = ledger.read_asset(row)
            return raw, {"provider": "elevenlabs", "namespace": namespace, "cache_key": key,
                         "request_id": row["receipt"], "model_id": model_id, "voice_id": voice_id,
                         "output_format": output_format, "output_sha256": row["sha256"],
                         "content_type": row["content_type"], "output_bytes": len(raw),
                         "maximum_reserved_credits": row["maximum"], "actual_credits": row["actual"],
                         "recovery_epoch": ledger.recovery_epoch,
                         "historical_accounting": "UNKNOWN", "historical_requests": "FENCED",
                         "acceptance_state": row["state"], "acceptance": json.loads(row["acceptance"] or "null"),
                         "reused": reused, "text_sha256": hashlib.sha256(args.text.encode("utf-8")).hexdigest()}
        if row["state"] == "unknown":
            raise RuntimeError(f"Existing submission unresolved (cache_key {key}); recover its provider receipt. "
                               "No repeat purchase allowed.")
        if time.monotonic() >= deadline:
            raise RuntimeError("Existing generation is still in progress; no repeat purchase allowed")
        time.sleep(.05)


def existing_epoch(args):
    """Open intact original epoch accounting. Never initializes an epoch or authorizes speech."""
    raw = _manifest_bytes(args.authorization_manifest, "Recovery requires the original absolute epoch authorization")
    policy = json.loads(raw)
    epoch = policy.get("epoch_id", "") if isinstance(policy, dict) else ""
    if (not isinstance(epoch, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", epoch)
            or policy.get("workspace") != args.cache_workspace
            or not policy.get("owner_authorization")
            or type(policy.get("maximum_credits")) is not int or policy["maximum_credits"] <= 0
            or policy.get("historical_accounting") != "UNKNOWN"
            or policy.get("historical_requests") != "FENCED"):
        raise RuntimeError("Epoch authorization/workspace mismatch")
    root = runtime.stable_epoch_parent().resolve() / epoch
    if any(runtime.linked_path(path) for path in (root, *root.parents)):
        raise RuntimeError("Recovery refuses linked epoch accounting")
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
        raise RuntimeError("Credential/workspace does not match this request namespace")
    # Inspect with SQLite read-only first: Ledger's constructor must not repair
    # a missing schema, create a budget, or replace a missing accounting file.
    with contextlib.closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as con:
        if con.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise RuntimeError("Existing epoch ledger failed integrity check")
        budget = con.execute("SELECT ceiling FROM budgets WHERE bucket=?", (BUCKET,)).fetchone()
        row = con.execute("SELECT bucket,receipt,state FROM requests WHERE namespace=? AND key=?",
                          (args.namespace, args.cache_key)).fetchone()
    if budget != (policy["maximum_credits"],):
        raise RuntimeError("Existing epoch ceiling does not match immutable authorization")
    if not row or row[0] != BUCKET or not row[1] or row[2] not in ("submitted", "unknown", "pending", "accepted"):
        raise RuntimeError("Recovery requires an existing receipt-bound epoch submission")
    return runtime.Ledger(root)


def reconcile(cli, args):
    """Provider GET-only recovery; settles existing epoch accounting and never resubmits."""
    ledger = existing_epoch(args)
    row = ledger.lookup(args.namespace, args.cache_key)
    history = cli._get_json("/history/" + urllib.parse.quote(args.history_id, safe=""))
    if history.get("request_id") != row["receipt"] or history.get("history_item_id") != args.history_id:
        raise RuntimeError("Provider history does not match the saved request ID")
    before, after = history.get("character_count_change_from"), history.get("character_count_change_to")
    actual = after - before if type(before) is int and type(after) is int and after >= before else None
    if actual is None:
        raise RuntimeError("Provider billing is unknown; reservation retained")
    if row["state"] in ("submitted", "unknown"):
        _, ctype, raw, _ = cli._request_full("/history/" + urllib.parse.quote(args.history_id, safe="") + "/audio")
        if not ctype.startswith("audio/"):
            raise RuntimeError("Provider history returned no audio")
        ledger.recover(args.namespace, args.cache_key, raw, ctype, row["receipt"], actual)
    else:
        ledger.settle(args.namespace, args.cache_key, actual, row["receipt"])
    print(json.dumps({"reconciled": True, "actual_credits": actual,
                      "acceptance_state": "pending" if row["state"] in ("submitted", "unknown") else row["state"]}))
    return 0


def accept(args):
    """Attach QA evidence to exact epoch bytes. Offline; content_control.py accept only reaches the default ledger."""
    row = content_control.accept_manifest(existing_epoch(args), args.namespace, args.cache_key, args.gates)
    print(json.dumps({"acceptance_state": row["state"], "output_sha256": row["sha256"]}))
    return 0
