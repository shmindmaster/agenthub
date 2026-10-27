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
import struct
import uuid
import urllib.parse
import urllib.request
import wave
from functools import lru_cache

BUCKET = "deepgram/usd-micros"
PRICE_POLICY = "flux-payg-2026-10-24-45-microusd-per-utf8-byte"
PRICE_VALID_THROUGH = datetime.date(2026, 11, 24)
ENDPOINT = "https://api.deepgram.com/v2/speak"
MAX_RESPONSE_BYTES = 64 * 1024 * 1024


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
        raw = response.read(MAX_RESPONSE_BYTES + 1)
        # The caller quarantines these bounded bytes before body/format checks.
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


def _prepare_audio(raw, content_type):
    """Finalize only the evidenced 44-byte PCM streaming-header convention.

    A completed HTTP read establishes the payload boundary, not its audible
    quality. All five acceptance gates still apply to this finalized output.
    Ordinary WAVs (including truncated declared lengths) retain strict checks.
    """
    normalized = raw
    convention = None
    if (len(raw) >= 44 and raw[:4] == b"RIFF" and raw[8:12] == b"WAVE"
            and struct.unpack_from("<I", raw, 4)[0] == 0x7FFF0024):
        expected_header = (b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, 48000, 96000, 2, 16)
                           + b"data" + struct.pack("<I", 0x7FFF0000))
        pcm_bytes = len(raw) - 44
        if raw[12:44] != expected_header or not 0 < pcm_bytes <= MAX_RESPONSE_BYTES - 44 or pcm_bytes % 2:
            raise RuntimeError("Malformed streaming WAV")
        normalized = (raw[:4] + struct.pack("<I", len(raw) - 8) + raw[8:40]
                      + struct.pack("<I", pcm_bytes) + raw[44:])
        convention = "pcm48k-mono16-streaming-7fff0000-v1"
    _audio(normalized, content_type)
    return normalized, convention


def _evidence_directory(ledger, namespace, key):
    path = ledger.root / "response-evidence" / namespace / key
    runtime_module().secure_directory(path)
    return path


def _durable_evidence(path, raw):
    """Atomic private runtime evidence; never an accepted asset or a retry."""
    if any(runtime_module().linked_path(p) for p in (path, *path.parents)):
        raise RuntimeError("Linked response evidence refused")
    temporary = path.with_name(uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("xb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _write_diagnostic(directory, diagnostic):
    _durable_evidence(directory / "diagnostic.json",
                      json.dumps(diagnostic, sort_keys=True).encode("utf-8"))


def _safe_mime(value):
    # No arbitrary headers or provider error bodies in diagnostics.
    mime = value.split(";", 1)[0].strip().lower() if isinstance(value, str) else ""
    return mime if re.fullmatch(r"[a-z0-9.+-]{1,64}/[a-z0-9.+-]{1,64}", mime) else "unrecognized"


def _linked(path):
    return any(runtime_module().linked_path(p) for p in (path, *path.parents))


def _epoch_policy(raw, workspace):
    runtime = runtime_module()
    policy = json.loads(raw)
    if not isinstance(policy, dict):
        raise RuntimeError("Object authorization required")
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
    if not proof_path.is_absolute() or _linked(proof_path):
        raise RuntimeError("Absolute unlinked inventory proof required")
    proof_raw = proof_path.read_bytes()
    if hashlib.sha256(proof_raw).hexdigest() != proof_ref.get("sha256"):
        raise RuntimeError("Inventory proof changed")
    proof = json.loads(proof_raw)
    def scope(value):
        if isinstance(value, str):
            return bool(value.strip())
        # The immutable first-epoch inventory used structured enumeration
        # receipts. Preserve that exact legacy shape only for the parent;
        # additional batches retain the canonical string-scope contract.
        return ("additional_batch_id" not in policy and isinstance(value, dict)
                and set(value) == {"path", "exists", "enumeration", "filesEnumerated", "deepgramEvidenceFiles"}
                and all(isinstance(value[k], str) and value[k].strip() for k in ("path", "enumeration"))
                and type(value["exists"]) is bool
                and all(type(value[k]) is int and value[k] >= 0
                        for k in ("filesEnumerated", "deepgramEvidenceFiles"))
                and value["deepgramEvidenceFiles"] <= value["filesEnumerated"])
    old, ambiguous, new = (proof.get(k) for k in ("historical_rendered_text_sha256", "ambiguous_rendered_text_sha256", "new_rendered_text_sha256"))
    if (proof.get("kind") != "deepgram-new-input-inventory" or not isinstance(proof.get("enumerated_scopes"), list)
            or not proof["enumerated_scopes"]
            or not all(scope(v) for v in proof["enumerated_scopes"])
            or not all(hashes(v) for v in (old, ambiguous, new))
            or not set(texts) <= set(new) or set(texts) & (set(old) | set(ambiguous))):
        raise RuntimeError("Inventory must establish new inputs disjoint from cached or ambiguous history")
    return policy, proof


def _proof_sets(policy, proof):
    # All enumerated prior inputs are fenced, including allowed-but-unsubmitted
    # and cached words, regardless of a later request's settings or credential.
    return (set(proof["historical_rendered_text_sha256"])
            | set(proof["new_rendered_text_sha256"])
            | {a["text_sha256"] for a in policy["allowed_requests"]},
            set(proof["ambiguous_rendered_text_sha256"]))


def _batch_parent(policy, original, original_raw):
    batch = policy.get("additional_batch_id")
    if (not isinstance(batch, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", batch)
            or policy.get("parent_authorization_sha256") != hashlib.sha256(original_raw).hexdigest()
            or "additional_batch_id" in original or "parent_authorization_sha256" in original):
        raise RuntimeError("Additional batch must bind the immutable original authorization")
    varying = {"allowed_requests", "inventory_proof", "additional_batch_id", "parent_authorization_sha256"}
    if {k: v for k, v in policy.items() if k not in varying} != {k: v for k, v in original.items() if k not in varying}:
        raise RuntimeError("Additional batch cannot change authorization, workspace, history, price or ceiling")
    return batch


def _register_batch(root, raw, policy, proof, original_raw, workspace):
    original, original_proof = _epoch_policy(original_raw, workspace)
    batch = _batch_parent(policy, original, original_raw)
    guard = root / "batch-registration.lock"
    if _linked(guard):
        raise RuntimeError("Linked registration refused")
    try:
        handle = guard.open("xb")
    except FileExistsError:
        raise RuntimeError("Batch registration busy or interrupted; inspect existing state") from None
    try:
        directory = root / "additional-batches"
        if _linked(directory):
            raise RuntimeError("Linked registration directory refused")
        index_path = root / "additional-batches.index.json"
        if _linked(index_path):
            raise RuntimeError("Linked registration index refused")
        if index_path.exists():
            index = json.loads(index_path.read_bytes())
            if (not isinstance(index, dict) or index.get("kind") != "deepgram-additional-batches-v1"
                    or index.get("parent_authorization_sha256") != hashlib.sha256(original_raw).hexdigest()
                    or not isinstance(index.get("batches"), dict)):
                raise RuntimeError("Registration index changed")
            registered = index["batches"]
            if any(not isinstance(k, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", k)
                   or not isinstance(v, str) or not re.fullmatch(r"[a-f0-9]{64}", v)
                   for k, v in registered.items()):
                raise RuntimeError("Registration index changed")
            if not directory.is_dir():
                raise RuntimeError("Incomplete registered batch directory; no reconstruction")
        else:
            registered = {}
        if directory.exists():
            entries = list(directory.iterdir())
            expected = {name + suffix for name in registered for suffix in (".json", ".sha256")}
            if {p.name for p in entries} != expected:
                raise RuntimeError("Incomplete or unrecognized batch registration; no reconstruction")
            if any(_linked(p) or not p.is_file() for p in entries):
                raise RuntimeError("Linked or invalid batch registration")
        runtime_module().secure_directory(directory)
        known, ambiguous = _proof_sets(original, original_proof)
        original_known, original_ambiguous = known.copy(), ambiguous.copy()
        prior = []
        current = None
        for entry in sorted(directory.glob("*.json")):
            stored = entry.read_bytes()
            stored_hash = hashlib.sha256(stored).hexdigest()
            if (entry.with_suffix(".sha256").read_bytes() != stored_hash.encode("ascii")
                    or registered.get(entry.stem) != stored_hash):
                raise RuntimeError("Registered batch changed")
            previous, previous_proof = _epoch_policy(stored, workspace)
            if _batch_parent(previous, original, original_raw) != entry.stem:
                raise RuntimeError("Registered batch identity changed")
            previous_new = set(previous_proof["new_rendered_text_sha256"])
            if (not original_known <= set(previous_proof["historical_rendered_text_sha256"])
                    or not original_ambiguous <= set(previous_proof["ambiguous_rendered_text_sha256"])
                    or previous_new & (original_known | original_ambiguous)):
                raise RuntimeError("Registered inventory does not cover original history")
            if entry.stem == batch:
                if stored != raw:
                    raise RuntimeError("Additional batch authorization is immutable")
                current = stored
            prior.append((entry.stem, previous, previous_proof))
        # Validate every registration, even when using an older batch. Each
        # inventory's new set must be disjoint from every other batch's inputs.
        for index, (_, previous, previous_proof) in enumerate(prior):
            previous_new = set(previous_proof["new_rendered_text_sha256"])
            for _, other, other_proof in prior[index + 1:]:
                if (previous_new & (set(other_proof["new_rendered_text_sha256"])
                                    | set(other_proof["ambiguous_rendered_text_sha256"]))
                        or set(other_proof["new_rendered_text_sha256"])
                        & set(previous_proof["ambiguous_rendered_text_sha256"])):
                    raise RuntimeError("Registered batch inputs overlap or contradict ambiguity")
            old, uncertain = _proof_sets(previous, previous_proof)
            known.update(old)
            ambiguous.update(uncertain)
        if current is None:
            new = set(proof["new_rendered_text_sha256"])
            if known & set(proof["ambiguous_rendered_text_sha256"]):
                raise RuntimeError("Inventory contradicts previously known inputs; reconcile history first")
            if (new & (known | ambiguous)
                    or not known <= set(proof["historical_rendered_text_sha256"])
                    or not ambiguous <= set(proof["ambiguous_rendered_text_sha256"])):
                raise RuntimeError("Complete inventory must fence all original and registered inputs")
            # Exclusive files + a durable digest: interrupted pairs remain
            # blocked; neither a missing digest nor a stale lock is repaired.
            for path, content in ((directory / (batch + ".json"), raw),
                                  (directory / (batch + ".sha256"), hashlib.sha256(raw).hexdigest().encode("ascii"))):
                with path.open("xb") as output:
                    output.write(content)
                    output.flush()
                    os.fsync(output.fileno())
            registered[batch] = hashlib.sha256(raw).hexdigest()
            _durable_evidence(index_path, json.dumps({"kind": "deepgram-additional-batches-v1",
                "parent_authorization_sha256": hashlib.sha256(original_raw).hexdigest(),
                "batches": registered}, sort_keys=True).encode("utf-8"))
    finally:
        handle.close()
        guard.unlink()


def recovery_epoch_ledger(manifest_path, workspace, planned):
    """An immutable epoch or disjoint additional batch sharing its accounting."""
    runtime = runtime_module()
    manifest_path = pathlib.Path(manifest_path).absolute()
    if _linked(manifest_path):
        raise RuntimeError("Linked authorization refused")
    raw = manifest_path.read_bytes()
    policy, proof = _epoch_policy(raw, workspace)
    ceiling, epoch = policy["maximum_usd_micros"], policy["epoch_id"]
    text_hash = hashlib.sha256(planned["request"]["text"].encode()).hexdigest()
    if {"text_sha256": text_hash, "cache_key": planned["cache_key"]} not in policy["allowed_requests"]:
        raise RuntimeError("Input/settings outside exact new/unsubmitted allowlist")
    base = os.environ.get("LOCALAPPDATA") if runtime.running_on_windows() else str(pathlib.Path.home() / ".local/share")
    if not base:
        raise RuntimeError("Private local runtime root unavailable")
    # Resolve the established OS runtime relocation, then reject further links.
    root = (pathlib.Path(base) / "AgentHub/runtime/content-recovery-epochs").resolve() / epoch
    lock = root / "authorization.json"
    batch = "additional_batch_id" in policy or "parent_authorization_sha256" in policy
    original_raw = raw
    if batch:
        if not root.is_dir() or _linked(root) or _linked(lock) or not lock.is_file():
            raise RuntimeError("Additional batch requires an intact existing epoch")
        original_raw = lock.read_bytes()
        original, _ = _epoch_policy(original_raw, workspace)
        _batch_parent(policy, original, original_raw)
    if root.exists():
        if _linked(lock) or not lock.is_file() or lock.read_bytes() != original_raw:
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
    if batch:
        _register_batch(root, raw, policy, proof, original_raw, workspace)
    ledger.recovery_epoch = epoch
    ledger.deepgram_epoch_namespace = "deepgram-recovery-epoch:" + hashlib.sha256(original_raw).hexdigest()
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
        try:
            directory = _evidence_directory(ledger, namespace, key)
            diagnostic = {"namespace": namespace, "cache_key": key, "stage": "before_submission"}
            _write_diagnostic(directory, diagnostic)
        except BaseException:
            # This worker has not crossed submitted or called transport.
            ledger.cancel_prepared(row)
            raise RuntimeError("Private response evidence unavailable; no submission made.") from None
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
            diagnostic.update(request_id=value, stage="response_headers_received",
                              content_type=_safe_mime(headers.get("content-type", "")))
            _write_diagnostic(directory, diagnostic)
        try:
            diagnostic["stage"] = "transport"
            _write_diagnostic(directory, diagnostic)
            headers, raw = send(planned["request"], credential, received)
            received(headers)
            ctype = headers.get("content-type", "")
            diagnostic.update(stage="response_quarantine", response_bytes=len(raw),
                              response_sha256=hashlib.sha256(raw).hexdigest())
            _write_diagnostic(directory, diagnostic)
            _durable_evidence(directory / "response.bin", raw)
            diagnostic["stage"] = "http_body_validation"
            length = headers.get("content-length")
            valid_length = isinstance(length, str) and re.fullmatch(r"[0-9]{1,20}", length)
            diagnostic["declared_response_bytes"] = int(length) if valid_length else (None if length is None else "invalid")
            _write_diagnostic(directory, diagnostic)
            if len(raw) > MAX_RESPONSE_BYTES:
                raise RuntimeError("Audio response exceeded limit")
            if length is not None and (not valid_length or int(length) != len(raw)):
                raise RuntimeError("Incomplete HTTP audio response")
            diagnostic["stage"] = "audio_validation"
            _write_diagnostic(directory, diagnostic)
            finalized, normalization = _prepare_audio(raw, ctype)
            diagnostic.update(stage="asset_persistence", normalization=normalization,
                              output_sha256=hashlib.sha256(finalized).hexdigest())
            _write_diagnostic(directory, diagnostic)
            row = ledger.complete(row, finalized, ctype, receipt, actual=None)
        except BaseException:
            ledger.unknown(row)
            raise RuntimeError("Submission unresolved at " + diagnostic["stage"]
                               + "; reservation retained. No automatic retry or repeat purchase.") from None
        # Completion is authoritative. A later diagnostic-write failure must
        # never relabel a successfully persisted pending asset as UNKNOWN.
        diagnostic["stage"] = "pending"
        try:
            _write_diagnostic(directory, diagnostic)
        except Exception:
            pass
    if row["state"] not in ("pending", "accepted"):
        raise RuntimeError("Existing submission is active or unresolved; no repeat purchase allowed")
    raw = ledger.read_asset(row)
    provenance = None
    evidence_path = ledger.root / "response-evidence" / namespace / key / "diagnostic.json"
    if not any(runtime_module().linked_path(p) for p in (evidence_path, *evidence_path.parents)):
        try:
            evidence = json.loads(evidence_path.read_bytes())
            if (isinstance(evidence, dict) and evidence.get("namespace") == namespace and evidence.get("cache_key") == key
                    and evidence.get("request_id") == row["receipt"]
                    and evidence.get("output_sha256") == row["sha256"]):
                provenance = {k: evidence[k] for k in ("response_sha256", "response_bytes", "output_sha256", "normalization")}
        except (OSError, ValueError, KeyError, TypeError):
            pass
    return raw, {"provider": "deepgram", "model": "flux-sienna-en", "namespace": namespace,
                 "cache_key": key, "request_id": row["receipt"], "reused": reused,
                 "output_sha256": hashlib.sha256(raw).hexdigest(), "content_type": row["content_type"],
                 "text_sha256": hashlib.sha256(planned["request"]["text"].encode()).hexdigest(),
                 "maximum_reserved_usd_micros": row["maximum"], "actual_usd_micros": row["actual"],
                 "acceptance_state": row["state"], "acceptance": json.loads(row["acceptance"] or "null"),
                 "price_policy": PRICE_POLICY,
                 "response_provenance": provenance,
                 **({"recovery_epoch": ledger.recovery_epoch, "historical_accounting": "UNKNOWN",
                     "historical_requests": "FENCED"} if hasattr(ledger, "recovery_epoch") else {})}
