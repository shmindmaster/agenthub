"""Bounded Azure HD rehearsal speech; explicit new-provider job accounting only.

No historical ledger is restored or reset. No retries, redirects, or provider
fallback. Generated WAVs remain pending substantive listening/identity QA.
"""
from __future__ import annotations

import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import re
import queue
import threading
import urllib.error
import urllib.request
import wave
from xml.sax.saxutils import escape

import governed_deepgram as shared

BUCKET = "azure-speech/usd-micros"
PRICE_POLICY = "azure-eastus2-neural-hd-20261026-22-microusd-per-utf8-byte"
VALID_THROUGH = datetime.date(2026, 11, 24)
MAX_BYTES = 64 * 1024 * 1024
VOICES = {"en-US-Ava:DragonHDLatestNeural", "en-US-Andrew:DragonHDLatestNeural"}
APPROVAL = "Authorize Azure, $1 total"


def quote(text, *, workspace, revision, dictionary_revision, voice="en-US-Ava:DragonHDLatestNeural"):
    if (not isinstance(text, str) or not text.strip() or len(text) > 6000
            or any(ord(c) < 32 and c not in "\n\r\t" for c in text)
            or not all(isinstance(v, str) and v.strip() for v in (workspace, revision, dictionary_revision))
            or voice not in VOICES):
        raise ValueError("Explicit workspace/revisions, allowlisted GA voice and 1-6000 text characters required")
    if datetime.datetime.now(datetime.timezone.utc).date() > VALID_THROUGH:
        raise RuntimeError("Price policy expired")
    ssml = ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">'
            '<voice name="' + voice + '">' + escape(text) + '</voice></speak>')
    request = {"provider": "azure-speech", "region": "eastus2", "voice": voice,
               "endpoint": "https://eastus2.tts.speech.microsoft.com/cognitiveservices/v1",
               "format": "riff-48khz-16bit-mono-pcm", "ssml": ssml,
               "revision": revision, "dictionary_revision": dictionary_revision,
               "workspace": workspace, "price_policy": PRICE_POLICY,
               "identity": "rehearsal-narrator-not-owner-voice"}
    return {"request": request, "cache_key": shared.runtime_module().request_key(request),
            "maximum_usd_micros": len(ssml.encode("utf-8")) * 22,
            "text_sha256": hashlib.sha256(text.encode()).hexdigest()}


def authorized_ledger(manifest, workspace, planned):
    """An immutable explicit $1 NEW Azure job, separate from lost accounting."""
    runtime = shared.runtime_module()
    path = Path(manifest).absolute()
    if any(runtime.linked_path(p) for p in (path, *path.parents)):
        raise RuntimeError("Authorization must be on an unlinked private local path")
    raw = path.read_bytes()
    policy = json.loads(raw)
    allowed = policy.get("allowed_cache_keys")
    if (policy.get("kind") != "azure-speech-new-provider-job"
            or policy.get("owner_authorization") != APPROVAL
            or policy.get("maximum_usd_micros") != 1_000_000
            or policy.get("workspace") != workspace
            or policy.get("price_policy") != PRICE_POLICY
            or policy.get("historical_accounting") != "UNKNOWN_NOT_RESTORED"
            or not isinstance(allowed, list) or not 1 <= len(allowed) <= 128
            or len(set(allowed)) != len(allowed)
            or any(not isinstance(k, str) or not re.fullmatch(r"[a-f0-9]{64}", k) for k in allowed)
            or planned["cache_key"] not in allowed):
        raise RuntimeError("Immutable exact-request $1 owner authorization required")
    try:
        stamp = datetime.datetime.fromisoformat(policy["authorized_at_utc"].replace("Z", "+00:00"))
        if stamp.utcoffset() != datetime.timedelta(0):
            raise ValueError()
    except (KeyError, ValueError, TypeError):
        raise RuntimeError("UTC owner authorization timestamp required") from None
    base = os.environ.get("LOCALAPPDATA")
    if not base:
        raise RuntimeError("Private local runtime unavailable")
    # Resolve the established AgentHub relocation, then forbid further links.
    parent = (Path(base) / "AgentHub/runtime/azure-speech-jobs").resolve()
    root = parent / hashlib.sha256(workspace.encode()).hexdigest()
    if any(runtime.linked_path(p) for p in (root, *root.parents)):
        raise RuntimeError("Linked job storage refused")
    lock = root / "authorization.json"
    if root.exists():
        if (any(runtime.linked_path(p) for p in (lock, root / "ledger.sqlite3", root / "namespace-salt"))
                or not lock.is_file() or lock.read_bytes() != raw
                or not (root / "ledger.sqlite3").is_file()
                or not (root / "namespace-salt").is_file()
                or len((root / "namespace-salt").read_bytes()) != 32):
            raise RuntimeError("Existing job incomplete or changed; no reset allowed")
        ledger = runtime.Ledger(root)
        with ledger.connect() as con:
            row = con.execute("SELECT ceiling FROM budgets WHERE bucket=?", (BUCKET,)).fetchone()
        if not row or row[0] != 1_000_000:
            raise RuntimeError("Existing budget changed; no reset allowed")
    else:
        root.mkdir(parents=True, exist_ok=False)
        runtime.secure_directory(root)
        shared._durable_evidence(lock, raw)
        ledger = runtime.Ledger(root)
        ledger.namespace("azure-job:" + hashlib.sha256(raw).hexdigest(), workspace)
        ledger.configure(BUCKET, 1_000_000)
    ledger.azure_authorization_hash = hashlib.sha256(raw).hexdigest()
    return ledger


def transport(request, credential, received):
    req = urllib.request.Request(request["endpoint"], data=request["ssml"].encode("utf-8"), method="POST",
        headers={"Ocp-Apim-Subscription-Key": credential, "Content-Type": "application/ssml+xml",
                 "X-Microsoft-OutputFormat": request["format"], "User-Agent": "AgentHub-MediaStudio"})
    try:
        response = urllib.request.build_opener(shared._NoRedirect()).open(req, timeout=180)
    except urllib.error.HTTPError as error:
        received({**{k.lower(): v for k, v in error.headers.items()}, "_http_status": str(error.code)})
        raise RuntimeError("Azure HTTP failure; no retry") from None
    with response:
        headers = {**{k.lower(): v for k, v in response.headers.items()},
                   "_http_status": str(getattr(response, "status", 200))}
        received(headers)  # Durable provider ID BEFORE touching body bytes.
        return headers, response.read(MAX_BYTES + 1)


def sdk_transport(request, credential, received, sdk=None):
    """One native SDK operation; SDK result ID precedes application audio access.

    No application retry, fallback, playback or audio output device is used.
    A result ID identifies synthesis, not a verified billing transaction.
    """
    if sdk is None:
        import azure.cognitiveservices.speech as sdk
    config = sdk.SpeechConfig(subscription=credential, region=request["region"])
    config.set_speech_synthesis_output_format(sdk.SpeechSynthesisOutputFormat.Riff48Khz16BitMonoPcm)
    config.set_property(sdk.PropertyId.SpeechServiceResponse_RequestWordBoundary, "true")
    synth = sdk.SpeechSynthesizer(speech_config=config, audio_config=None)
    boundaries, callback_errors = [], []
    def boundary(event):
        try:
            boundaries.append({"result_id": event.result_id, "audio_offset_ticks": int(event.audio_offset),
                "start_seconds": event.audio_offset / 10_000_000,
                "duration_seconds": event.duration.total_seconds(), "text": event.text,
                "text_offset": int(event.text_offset), "word_length": int(event.word_length),
                "boundary_type": str(event.boundary_type)})
        except Exception:
            callback_errors.append("invalid_boundary")
    synth.synthesis_word_boundary.connect(boundary)
    completed = queue.Queue(maxsize=1)
    def run():
        try:
            completed.put((True, synth.speak_ssml_async(request["ssml"]).get()))
        except BaseException as error:
            completed.put((False, type(error).__name__))
    threading.Thread(target=run, daemon=True).start()
    try:
        success, result = completed.get(timeout=180)
    except queue.Empty:
        synth.stop_speaking_async()
        raise TimeoutError("SDK synthesis timeout; no retry") from None
    if not success:
        raise RuntimeError("SDK synthesis exception; no retry")
    headers = {"x-microsoft-requestid": result.result_id, "content-type": "audio/wav",
               "_transport": "azure-speech-sdk", "_sdk_version": sdk.__version__}
    received(headers)  # Bind unique SDK result before accessing audio_data.
    if result.reason != sdk.ResultReason.SynthesizingAudioCompleted:
        raise RuntimeError("SDK synthesis not completed; no retry")
    if callback_errors or any(b["result_id"] != result.result_id for b in boundaries):
        raise RuntimeError("SDK boundary/result identity mismatch")
    headers["_word_boundaries"] = boundaries
    return headers, result.audio_data


def _generate(ledger, planned, workspace, credential, send=transport):
    namespace = ledger.namespace("azure-job:" + ledger.azure_authorization_hash, workspace)
    row = ledger.claim(namespace, planned["cache_key"], BUCKET, planned["maximum_usd_micros"])
    reused = row["state"] != "leader"
    if row["state"] == "leader":
        diagnostic = {"stage": "prepared", "cache_key": planned["cache_key"]}
        try:
            directory = shared._evidence_directory(ledger, namespace, planned["cache_key"])
            shared._write_diagnostic(directory, diagnostic)
        except BaseException:
            ledger.cancel_prepared(row)
            raise
        ledger.submitted(row)
        receipt = None
        def received(headers):
            nonlocal receipt
            diagnostic.update(stage="response_headers", http_status=headers.get("_http_status"),
                              response_header_names=sorted(headers))
            shared._write_diagnostic(directory, diagnostic)
            value = next((headers.get(k) for k in ("x-microsoft-requestid", "x-requestid", "apim-request-id") if headers.get(k)), None)
            if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", value):
                raise RuntimeError("Provider request ID absent/invalid")
            ledger.bind_receipt(row, value)
            receipt = value
            diagnostic["request_id"] = value
            shared._write_diagnostic(directory, diagnostic)
        try:
            diagnostic["stage"] = "transport"
            shared._write_diagnostic(directory, diagnostic)
            headers, raw = send(planned["request"], credential, received)
            received(headers)
            diagnostic.update(stage="response_quarantine", response_bytes=len(raw),
                              response_sha256=hashlib.sha256(raw).hexdigest())
            shared._write_diagnostic(directory, diagnostic)
            shared._durable_evidence(directory / "response.bin", raw)
            if "_word_boundaries" in headers:
                shared._durable_evidence(directory / "word-boundaries.json",
                    json.dumps({"request_id": receipt, "events": headers["_word_boundaries"]}).encode())
            if len(raw) > MAX_BYTES:
                raise RuntimeError("Response too large")
            length = headers.get("content-length")
            if length is not None and (not re.fullmatch(r"[0-9]{1,20}", length) or int(length) != len(raw)):
                raise RuntimeError("Incomplete response")
            shared._audio(raw, headers.get("content-type", ""))
            row = ledger.complete(row, raw, "audio/wav", receipt, actual=None)
        except BaseException as error:
            ledger.unknown(row)
            diagnostic["error_type"] = type(error).__name__
            try:
                shared._write_diagnostic(directory, diagnostic)
            except Exception:
                pass
            raise RuntimeError("Azure submission unresolved; full reservation retained, no automatic retry") from None
    if row["state"] not in ("pending", "accepted"):
        raise RuntimeError("Existing submission active or unresolved; no repeat purchase")
    raw = ledger.read_asset(row)
    with wave.open(io.BytesIO(raw), "rb") as audio:
        duration = audio.getnframes() / audio.getframerate()
    boundary_file = shared._evidence_directory(ledger, namespace, planned["cache_key"]) / "word-boundaries.json"
    clock = json.loads(boundary_file.read_bytes())["events"] if boundary_file.exists() else None
    return raw, {"provider": "azure-speech", "voice": planned["request"]["voice"],
                 "identity": "rehearsal-narrator-not-owner-voice", "cache_key": planned["cache_key"],
                 "namespace": namespace, "request_id": row["receipt"], "reused": reused,
                 "output_sha256": hashlib.sha256(raw).hexdigest(), "text_sha256": planned["text_sha256"],
                 "duration_seconds": duration, "sample_rate": 48000, "word_boundaries": clock,
                 "alignment_status": "AZURE_SDK_EVENTS" if clock else "NOT_PERFORMED", "acceptance_state": row["state"],
                 "maximum_reserved_usd_micros": row["maximum"], "actual_usd_micros": None,
                 "price_policy": PRICE_POLICY, "authorization_sha256": ledger.azure_authorization_hash,
                 "historical_accounting": "UNKNOWN_NOT_RESTORED"}


def generate(text, *, authorization_manifest, workspace, revision, dictionary_revision,
             voice="en-US-Ava:DragonHDLatestNeural", use_sdk=False):
    planned = quote(text, workspace=workspace, revision=revision, dictionary_revision=dictionary_revision, voice=voice)
    credential = os.environ.get("AZURE_SPEECH_KEY")
    if not credential:
        raise RuntimeError("AZURE_SPEECH_KEY unset")
    ledger = authorized_ledger(authorization_manifest, workspace, planned)
    with ledger.session():
        return _generate(ledger, planned, workspace, credential, sdk_transport if use_sdk else transport)


def generate_manual_retake(text, *, authorization_manifest, supplemental_manifest, workspace,
                           revision, dictionary_revision):
    """Exactly two owner-authorized manual replacements, never an automatic retry.

    Original unknown rows remain fully reserved. Supplemental authority is pinned
    once in the same ledger root; modifying it cannot create another attempt.
    """
    planned = quote(text, workspace=workspace, revision=revision, dictionary_revision=dictionary_revision)
    ledger = authorized_ledger(authorization_manifest, workspace, planned)
    path = Path(supplemental_manifest).absolute()
    runtime = shared.runtime_module()
    if any(runtime.linked_path(p) for p in (path, *path.parents)):
        raise RuntimeError("Linked retake authority refused")
    raw = path.read_bytes()
    grant = json.loads(raw)
    entries = grant.get("retakes", [])
    if (grant.get("kind") != "azure-two-manual-sdk-retakes" or grant.get("workspace") != workspace
            or grant.get("owner_answer") != APPROVAL or grant.get("maximum_usd_micros") != 1_000_000
            or grant.get("preserve_unknown_reservations") is not True
            or not all(isinstance(grant.get(k), str) and grant[k].strip()
                       for k in ("original_question", "latest_owner_direction", "interpretation", "recorded_at_utc"))
            or len(entries) != 2 or len({e.get("parent_cache_key") for e in entries}) != 2):
        raise RuntimeError("Exact two-take supplemental authority required")
    entry = next((e for e in entries if e.get("parent_cache_key") == planned["cache_key"]
                  and e.get("text_sha256") == planned["text_sha256"]), None)
    if not entry or not re.fullmatch(r"[a-z0-9-]{1,80}", entry.get("retake_id", "")):
        raise RuntimeError("Input not one of the two authorized replacements")
    with ledger.session():
        pinned = ledger.root / "manual-retake-authorization.json"
        if runtime.linked_path(pinned):
            raise RuntimeError("Linked pinned authority refused")
        if pinned.exists():
            if pinned.read_bytes() != raw:
                raise RuntimeError("Retake authority immutable; no replacement or reset")
        else:
            shared._durable_evidence(pinned, raw)
        namespace = ledger.namespace("azure-job:" + ledger.azure_authorization_hash, workspace)
        for e in entries:
            parent = ledger.lookup(namespace, e["parent_cache_key"])
            if not parent or parent["state"] != "unknown":
                raise RuntimeError("Both original unknown submissions must remain fenced")
        request = {**planned["request"], "manual_retake": entry["retake_id"],
                   "parent_unknown_cache_key": planned["cache_key"],
                   "supplemental_authorization_sha256": hashlib.sha256(raw).hexdigest()}
        retake = {**planned, "request": request, "cache_key": runtime.request_key(request)}
        credential = os.environ.get("AZURE_SPEECH_KEY")
        if not credential:
            raise RuntimeError("AZURE_SPEECH_KEY unset")
        audio, receipt = _generate(ledger, retake, workspace, credential, sdk_transport)
        receipt.update(parent_unknown_cache_key=planned["cache_key"], manual_retake_id=entry["retake_id"],
                       supplemental_authorization_sha256=hashlib.sha256(raw).hexdigest())
        return audio, receipt
