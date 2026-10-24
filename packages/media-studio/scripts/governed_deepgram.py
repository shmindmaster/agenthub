"""Narrow Flux Sienna TTS adapter for Media Studio's shared paid ledger."""
from __future__ import annotations

import datetime
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import re
import sqlite3
import urllib.parse
import urllib.request
import wave
from functools import lru_cache

BUCKET = "deepgram/usd-micros"
PRICE_POLICY = "flux-payg-2026-10-24-45-microusd-per-utf8-byte"
PRICE_VALID_THROUGH = datetime.date(2026, 11, 24)
ENDPOINT = "https://api.deepgram.com/v2/speak"


@lru_cache(maxsize=1)
def runtime_module():
    source = pathlib.Path(__file__).with_name("content_runtime.py")
    spec = importlib.util.spec_from_file_location("deepgram_content_runtime", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def quote(text, *, workspace, revision, dictionary_revision, expressivity):
    if (not isinstance(text, str) or not text.strip() or len(text) > 2000
            or not all(isinstance(x, str) and x.strip() for x in
                       (workspace, revision, dictionary_revision))):
        raise ValueError("Explicit workspace, revision, dictionary revision and 1-2000 input characters required")
    if type(expressivity) not in (int, float) or not 0 <= expressivity <= 1:
        raise ValueError("Explicit finite expressivity in [0,1] required")
    if datetime.datetime.now(datetime.timezone.utc).date() > PRICE_VALID_THROUGH:
        raise RuntimeError("TTS price policy expired; verify official pricing before updating it")
    request = {"provider": "deepgram/rest/v2/speak", "model": "flux-sienna-en",
               "encoding": "linear16", "container": "wav", "sample_rate": 48000,
               "expressivity": float(expressivity), "mip_opt_out": True,
               "text": text, "revision": revision, "dictionary_revision": dictionary_revision,
               "price_policy": PRICE_POLICY, "quality_policy": "owner-voice-five-gates-v1"}
    maximum = len(text.encode("utf-8")) * 45
    return {"request": request, "cache_key": runtime_module().request_key(request),
            "bucket": BUCKET, "maximum_usd_micros": maximum,
            "maximum_usd": maximum / 1_000_000,
            "pricing_source": "https://deepgram.com/pricing",
            "counting": "UTF-8 bytes conservatively reserved at 45 microdollars each; not invoice settlement"}


def existing_ledger(root=None):
    """Refuse absent storage BEFORE invoking the runtime's creating constructor."""
    runtime = runtime_module()
    root = (runtime.canonical_default_root(runtime.default_root()) if root is None
            else pathlib.Path(root).absolute())
    if str(root).startswith(("\\\\", "//")) or any(runtime.linked_path(p) for p in (root, *root.parents)):
        raise RuntimeError("Existing local, unlinked shared ledger required")
    db, salt = root / "ledger.sqlite3", root / "namespace-salt"
    if (not db.is_file() or not salt.is_file() or runtime.linked_path(db)
            or runtime.linked_path(salt) or len(salt.read_bytes()) != 32):
        raise RuntimeError("Restore intact shared ledger and namespace salt; no fresh accounting is created")
    try:
        with contextlib.closing(sqlite3.connect(db.as_uri() + "?mode=ro", uri=True)) as con:
            con.execute("SELECT namespace,key,bucket,maximum,actual,state,receipt FROM requests LIMIT 0")
            row = con.execute("SELECT ceiling FROM budgets WHERE bucket=?", (BUCKET,)).fetchone()
            if not row:
                raise RuntimeError("Shared Deepgram aggregate budget unset; paid generation disabled")
    except sqlite3.Error:
        raise RuntimeError("Existing shared ledger is unreadable; restore accounting before generation") from None
    return runtime.Ledger(root)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def transport(request, credential, received):
    """Fixed origin, no redirects, no SDK retry; receipt bound before reading audio."""
    query = {k: request[k] for k in ("model", "encoding", "container", "sample_rate", "expressivity")}
    query.update(mip_opt_out="true", tag="agenthub-media-studio")
    req = urllib.request.Request(ENDPOINT + "?" + urllib.parse.urlencode(query),
        data=json.dumps({"text": request["text"]}, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": "Token " + credential, "Content-Type": "application/json"}, method="POST")
    with urllib.request.build_opener(_NoRedirect()).open(req, timeout=300) as response:
        headers = {k.lower(): v for k, v in response.headers.items()}
        received(headers)
        raw = response.read(64 * 1024 * 1024 + 1)
        if len(raw) > 64 * 1024 * 1024:
            raise RuntimeError("Audio response exceeded limit")
        return headers, raw


def _audio(raw, content_type):
    if content_type.split(";", 1)[0].strip() not in ("audio/wav", "audio/x-wav", "audio/wave"):
        raise RuntimeError("Expected WAV audio")
    with wave.open(io.BytesIO(raw), "rb") as audio:
        if audio.getframerate() != 48000 or audio.getsampwidth() != 2 or audio.getnchannels() != 1:
            raise RuntimeError("Unexpected WAV format")
        expected = audio.getnframes() * 2
        if not expected or len(audio.readframes(audio.getnframes())) != expected:
            raise RuntimeError("Empty or truncated WAV")


def recovery_epoch_ledger(manifest_path, workspace, planned):
    """Explicit owner-bounded new epoch; old spend stays UNKNOWN and requests FENCED."""
    runtime = runtime_module()
    manifest_path = pathlib.Path(manifest_path).absolute()
    if runtime.linked_path(manifest_path):
        raise RuntimeError("Linked authorization refused")
    raw = manifest_path.read_bytes()
    policy = json.loads(raw)
    ceiling = runtime.integer(policy.get("maximum_usd_micros"))
    epoch = policy.get("epoch_id", "")
    if (not re.fullmatch(r"deepgram-[a-z0-9][a-z0-9-]{0,54}", epoch) or ceiling > 3_000_000
            or policy.get("historical_accounting") != "UNKNOWN"
            or policy.get("historical_requests") != "FENCED"
            or not isinstance(policy.get("owner_authorization"), str)
            or not policy["owner_authorization"].strip()
            or policy.get("workspace") != workspace or policy.get("price_policy") != PRICE_POLICY):
        raise RuntimeError("Explicit bounded Sienna epoch authorization with fenced history required")
    allowed = policy.get("allowed_requests", [])
    if not isinstance(allowed, list) or not 1 <= len(allowed) <= 256:
        raise RuntimeError("Bounded exact request allowlist required")
    def hashes(values):
        return isinstance(values, list) and all(isinstance(v, str) and re.fullmatch(r"[a-f0-9]{64}", v) for v in values)
    if any(not isinstance(a, dict) or not hashes([a.get("text_sha256"), a.get("cache_key")]) for a in allowed):
        raise RuntimeError("Invalid exact request allowlist")
    texts = [a["text_sha256"] for a in allowed]
    if len(set(texts)) != len(texts):
        raise RuntimeError("One exact request per new text required")
    proof_ref = policy.get("inventory_proof", {})
    proof_path = pathlib.Path(proof_ref.get("path", ""))
    if not proof_path.is_absolute() or runtime.linked_path(proof_path):
        raise RuntimeError("Absolute unlinked inventory proof required")
    proof_raw = proof_path.read_bytes()
    if hashlib.sha256(proof_raw).hexdigest() != proof_ref.get("sha256"):
        raise RuntimeError("Inventory proof changed")
    proof = json.loads(proof_raw)
    old, ambiguous, new = (proof.get(k) for k in ("historical_rendered_text_sha256", "ambiguous_rendered_text_sha256", "new_rendered_text_sha256"))
    if (proof.get("kind") != "deepgram-new-input-inventory" or not proof.get("enumerated_scopes")
            or not all(hashes(v) for v in (old, ambiguous, new))
            or not set(texts) <= set(new) or set(texts) & (set(old) | set(ambiguous))):
        raise RuntimeError("Inventory must establish new inputs disjoint from cached or ambiguous history")
    text_hash = hashlib.sha256(planned["request"]["text"].encode()).hexdigest()
    if {"text_sha256": text_hash, "cache_key": planned["cache_key"]} not in allowed:
        raise RuntimeError("Input/settings outside exact new/unsubmitted allowlist")
    base = os.environ.get("LOCALAPPDATA") if runtime.running_on_windows() else str(pathlib.Path.home() / ".local/share")
    if not base:
        raise RuntimeError("Private local runtime root unavailable")
    # Resolve the established OS runtime relocation, then reject further links.
    root = (pathlib.Path(base) / "AgentHub/runtime/content-recovery-epochs").resolve() / epoch
    lock = root / "authorization.json"
    if root.exists():
        if runtime.linked_path(lock) or not lock.is_file() or lock.read_bytes() != raw:
            raise RuntimeError("Epoch authorization is immutable; no cap/allowlist reset")
        ledger = existing_ledger(root)
        with ledger.connect() as con:
            row = con.execute("SELECT ceiling FROM budgets WHERE bucket=?", (BUCKET,)).fetchone()
        if not row or row[0] != ceiling:
            raise RuntimeError("Epoch ceiling differs; no accounting reset")
    else:
        # This path is reachable only through explicit --execute + owner manifest.
        # An interrupted initialization is fenced by the existing-root branch.
        root.mkdir(parents=True, exist_ok=False)
        runtime.secure_directory(root)
        with lock.open("xb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        ledger = runtime.Ledger(root)
        ledger.namespace("deepgram-recovery-epoch:" + hashlib.sha256(raw).hexdigest(), workspace)
        ledger.configure(BUCKET, ceiling)
    ledger.recovery_epoch = epoch
    ledger.deepgram_epoch_namespace = "deepgram-recovery-epoch:" + hashlib.sha256(raw).hexdigest()
    return ledger


def generate(text, *, workspace, revision, dictionary_revision, expressivity, root=None, recovery_epoch_manifest=None):
    planned = quote(text, workspace=workspace, revision=revision,
                    dictionary_revision=dictionary_revision, expressivity=expressivity)
    credential = os.environ.get("DEEPGRAM_API_KEY", "")
    if not credential:
        raise RuntimeError("DEEPGRAM_API_KEY is unset")
    if root is not None and recovery_epoch_manifest is not None:
        raise ValueError("Choose intact primary ledger or authorized recovery epoch")
    ledger = (recovery_epoch_ledger(recovery_epoch_manifest, workspace, planned)
              if recovery_epoch_manifest else existing_ledger(root))
    with ledger.session():
        return _generate(ledger, planned, workspace, credential, transport)


def _generate(ledger, planned, workspace, credential, send):
    namespace = ledger.namespace(getattr(ledger, "deepgram_epoch_namespace", credential), workspace)
    key = planned["cache_key"]
    row = ledger.claim(namespace, key, BUCKET, planned["maximum_usd_micros"])
    reused = row["state"] != "leader"
    if row["state"] == "leader":
        ledger.submitted(row)
        receipt = None
        def received(headers):
            nonlocal receipt
            value = headers.get("dg-request-id")
            if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,128}", value):
                raise RuntimeError("Provider receipt absent or invalid")
            if receipt is not None and receipt != value:
                raise RuntimeError("Provider receipt changed")
            ledger.bind_receipt(row, value)
            receipt = value
        try:
            headers, raw = send(planned["request"], credential, received)
            received(headers)
            ctype = headers.get("content-type", "")
            _audio(raw, ctype)
            row = ledger.complete(row, raw, ctype, receipt, actual=None)
        except BaseException:
            ledger.unknown(row)
            raise RuntimeError("Submission unresolved; reservation retained. No automatic retry or repeat purchase.") from None
    if row["state"] not in ("pending", "accepted"):
        raise RuntimeError("Existing submission is active or unresolved; no repeat purchase allowed")
    raw = ledger.read_asset(row)
    return raw, {"provider": "deepgram", "model": "flux-sienna-en", "namespace": namespace,
                 "cache_key": key, "request_id": row["receipt"], "reused": reused,
                 "output_sha256": hashlib.sha256(raw).hexdigest(), "content_type": row["content_type"],
                 "text_sha256": hashlib.sha256(planned["request"]["text"].encode()).hexdigest(),
                 "maximum_reserved_usd_micros": row["maximum"], "actual_usd_micros": row["actual"],
                 "acceptance_state": row["state"], "acceptance": json.loads(row["acceptance"] or "null"),
                 "price_policy": PRICE_POLICY,
                 **({"recovery_epoch": ledger.recovery_epoch, "historical_accounting": "UNKNOWN",
                     "historical_requests": "FENCED"} if hasattr(ledger, "recovery_epoch") else {})}
