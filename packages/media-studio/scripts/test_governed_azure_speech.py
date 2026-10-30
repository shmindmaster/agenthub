"""Offline synthetic tests: no network, credentials or customer input."""
import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wave
import urllib.error
import types
import datetime

import governed_azure_speech as az


class AzureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name).resolve()
        self.env = patch.dict(os.environ, {"LOCALAPPDATA": str(self.base)})
        self.env.start()
        self.plan = az.quote("Synthetic rehearsal <answer> & example.", workspace="synthetic-job",
                             revision="v1", dictionary_revision="v1")
        self.policy = {"kind": "azure-speech-new-provider-job", "owner_authorization": az.APPROVAL,
            "maximum_usd_micros": 1_000_000, "workspace": "synthetic-job", "price_policy": az.PRICE_POLICY,
            "historical_accounting": "UNKNOWN_NOT_RESTORED", "authorized_at_utc": "2026-10-27T02:00:00Z",
            "allowed_cache_keys": [self.plan["cache_key"]]}
        self.manifest = self.base / "approval.json"
        self.save()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def save(self):
        self.manifest.write_text(json.dumps(self.policy))

    def ledger(self):
        return az.authorized_ledger(self.manifest, "synthetic-job", self.plan)

    @staticmethod
    def wav():
        buf = io.BytesIO()
        with wave.open(buf, "wb") as a:
            a.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
            a.writeframes(b"\0\0" * 4800)
        return buf.getvalue()

    def test_quote_escapes_and_counts_full_ssml(self):
        self.assertIn("&lt;answer&gt; &amp;", self.plan["request"]["ssml"])
        self.assertEqual(self.plan["maximum_usd_micros"], len(self.plan["request"]["ssml"].encode()) * 22)
        with self.assertRaises(ValueError):
            az.quote("x", workspace="j", revision="1", dictionary_revision="1", voice="unknown")

    def test_no_approval_no_ledger(self):
        self.policy["owner_authorization"] = "pending"
        self.save()
        with self.assertRaises(RuntimeError): self.ledger()
        self.assertFalse((self.base / "AgentHub").exists())

    def test_bounded_standard_exact_grant_and_immutable_ceiling(self):
        self.plan = az.quote("One. Two.", workspace="synthetic-job", revision="v1", dictionary_revision="v1",
                             voice="en-US-AriaNeural", style="narration-professional", paragraphs=["One.", "Two."])
        self.policy.update(kind="azure-speech-bounded-standard-job", owner_authorization="Authorize Azure, $0.15 total",
                           maximum_usd_micros=125_000, price_policy=az.STANDARD_PRICE_POLICY,
                           allowed_cache_keys=[self.plan["cache_key"]])
        self.save()
        ledger = self.ledger()
        with ledger.connect() as con:
            self.assertEqual(con.execute("SELECT ceiling FROM budgets WHERE bucket=?", (az.BUCKET,)).fetchone()[0], 125_000)
        self.policy["maximum_usd_micros"] = 150_001
        self.save()
        with self.assertRaises(RuntimeError): self.ledger()

    def test_structured_text_cannot_inject_markup_or_change_content(self):
        kw = dict(workspace="s", revision="v1", dictionary_revision="v1", voice="en-US-GuyNeural", style="friendly")
        plan = az.quote("One <audio>. Two.", paragraphs=["One <audio>.", "Two."], **kw)
        self.assertIn("&lt;audio&gt;", plan["request"]["ssml"])
        self.assertIn('bookmark mark="paragraph-2"', plan["request"]["ssml"])
        for extra in ({"paragraphs": ["Changed"]}, {"paragraphs": ["One <audio>.", "Two."], "pause_ms": 701},
                      {"paragraphs": ["One <audio>.", "Two."], "rate_percent": -11}):
            with self.assertRaises(ValueError): az.quote("One <audio>. Two.", **kw, **extra)
        with self.assertRaises(ValueError): az.quote("One.", style="excited", **{k:v for k,v in kw.items() if k != "style"})

    def test_manifest_immutable_and_missing_salt_fenced(self):
        ledger = self.ledger()
        self.policy["authorized_at_utc"] = "2026-10-27T02:01:00Z"
        self.save()
        with self.assertRaises(RuntimeError): self.ledger()
        self.policy["authorized_at_utc"] = "2026-10-27T02:00:00Z"
        self.save()
        (ledger.root / "namespace-salt").unlink()
        with self.assertRaises(RuntimeError): self.ledger()

    def test_request_id_bound_before_bytes_and_exact_reuse(self):
        ledger = self.ledger()
        calls = []
        def send(req, key, received):
            calls.append(1)
            headers = {"x-microsoft-requestid": "synthetic-id", "content-type": "audio/wav"}
            received(headers)
            namespace = ledger.namespace("azure-job:" + ledger.azure_authorization_hash, "synthetic-job")
            self.assertEqual(ledger.lookup(namespace, self.plan["cache_key"])["receipt"], "synthetic-id")
            return headers, self.wav()
        raw, receipt = az._generate(ledger, self.plan, "synthetic-job", "synthetic-not-a-key", send)
        raw2, receipt2 = az._generate(ledger, self.plan, "synthetic-job", "changed-not-a-key", send)
        self.assertEqual(len(calls), 1)
        self.assertEqual(raw, raw2)
        self.assertTrue(receipt2["reused"])
        self.assertEqual(receipt["duration_seconds"], .1)
        self.assertIsNone(receipt["word_boundaries"])

    def test_ambiguous_not_retried(self):
        ledger = self.ledger()
        calls = []
        def send(*args):
            calls.append(1)
            raise TimeoutError()
        for _ in range(2):
            with self.assertRaises(RuntimeError):
                az._generate(ledger, self.plan, "synthetic-job", "synthetic", send)
        self.assertEqual(len(calls), 1)
        with ledger.connect() as con:
            row = con.execute("SELECT state, maximum FROM requests").fetchone()
            self.assertEqual(row["state"], "unknown")
            self.assertEqual(row["maximum"], self.plan["maximum_usd_micros"])

    def test_no_receipt_or_invalid_audio_fenced(self):
        for i, headers in enumerate(({}, {"x-microsoft-requestid": "synthetic", "content-type": "audio/wav"})):
            plan = {**self.plan, "cache_key": hashlib.sha256(str(i).encode()).hexdigest()}
            ledger = self.ledger()
            def send(req, key, received):
                received(headers)
                return headers, b"not audio"
            with self.assertRaises(RuntimeError): az._generate(ledger, plan, "synthetic-job", "synthetic", send)

    def test_cap_and_singleflight(self):
        ledger = self.ledger()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            rows = list(pool.map(lambda _: ledger.claim("scope", "same", az.BUCKET, 600_000), range(4)))
        self.assertEqual(sum(r["state"] == "leader" for r in rows), 1)
        with self.assertRaises(RuntimeError): ledger.claim("other", "another", az.BUCKET, 600_000)

    def test_safe_failure_diagnostic_preserves_status_not_header_values(self):
        ledger = self.ledger()
        def send(req, key, received):
            received({"_http_status": "401", "content-type": "text/plain",
                      "x-private-detail": "synthetic-secret-must-not-persist"})
            self.fail("Missing request ID must fail before body read")
        with self.assertRaises(RuntimeError):
            az._generate(ledger, self.plan, "synthetic-job", "synthetic", send)
        diagnostics = list(ledger.root.rglob("diagnostic.json"))
        self.assertEqual(len(diagnostics), 1)
        raw = diagnostics[0].read_text()
        result = json.loads(raw)
        self.assertEqual(result["stage"], "response_headers")
        self.assertEqual(result["http_status"], "401")
        self.assertEqual(result["error_type"], "RuntimeError")
        self.assertIn("x-private-detail", result["response_header_names"])
        self.assertNotIn("synthetic-secret-must-not-persist", raw)
        self.assertFalse(list(ledger.root.rglob("response.bin")))

    def test_transport_receipt_before_read_and_no_redirect_handler(self):
        order = []
        class Response:
            headers = {"x-requestid": "synthetic", "content-type": "audio/wav"}
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, limit):
                order.append("body")
                return b"synthetic"
        class Opener:
            def open(self, request, timeout):
                order.append("post")
                return Response()
        with patch.object(az.urllib.request, "build_opener", return_value=Opener()) as build:
            az.transport(self.plan["request"], "synthetic", lambda h: order.append("receipt"))
        self.assertEqual(order, ["post", "receipt", "body"])
        self.assertIsInstance(build.call_args.args[0], az.shared._NoRedirect)
        self.assertIsNone(build.call_args.args[0].redirect_request(None, None, 302, "", {}, "https://example.com"))

    def test_http_error_id_saved_without_retry(self):
        class Opener:
            def open(self, *args, **kwargs):
                raise urllib.error.HTTPError("https://synthetic.invalid", 429, "synthetic",
                                             {"x-requestid": "refused-id"}, None)
        seen = []
        with patch.object(az.urllib.request, "build_opener", return_value=Opener()) as build:
            with self.assertRaises(RuntimeError):
                az.transport(self.plan["request"], "synthetic", lambda h: seen.append(h["x-requestid"]))
        self.assertEqual(seen, ["refused-id"])
        self.assertEqual(build.call_count, 1)

    def test_sdk_result_bound_before_audio_and_real_event_clock(self):
        order = []
        class Signal:
            def connect(self, fn): self.fn = fn
        class Result:
            result_id = "sdk-synthetic-id"
            reason = "complete"
            @property
            def audio_data(self):
                order.append("audio")
                return self_outer.wav()
        class Synth:
            def __init__(self, **kwargs):
                self_outer.assertIsNone(kwargs["audio_config"])
                self.synthesis_word_boundary = Signal()
            def speak_ssml_async(self, text):
                order.append("operation")
                self.synthesis_word_boundary.fn(types.SimpleNamespace(result_id="sdk-synthetic-id",
                    audio_offset=1_000_000, duration=datetime.timedelta(seconds=.2), text="Synthetic",
                    text_offset=0, word_length=9, boundary_type="Word"))
                return types.SimpleNamespace(get=lambda: Result())
        class Config:
            def __init__(self, **kwargs): pass
            def set_speech_synthesis_output_format(self, value): pass
            def set_property(self, key, value): pass
        self_outer = self
        sdk = types.SimpleNamespace(SpeechConfig=Config, SpeechSynthesizer=Synth, __version__="synthetic",
            SpeechSynthesisOutputFormat=types.SimpleNamespace(Riff48Khz16BitMonoPcm=1),
            PropertyId=types.SimpleNamespace(SpeechServiceResponse_RequestWordBoundary=1),
            ResultReason=types.SimpleNamespace(SynthesizingAudioCompleted="complete"))
        headers, audio = az.sdk_transport(self.plan["request"], "synthetic",
            lambda h: order.append("receipt"), sdk)
        self.assertEqual(order, ["operation", "receipt", "audio"])
        self.assertEqual(headers["_word_boundaries"][0]["start_seconds"], .1)
        self.assertEqual(headers["_word_boundaries"][0]["duration_seconds"], .2)

    def test_manual_retake_same_cap_original_fence_and_immutable_authority(self):
        second = az.quote("Second synthetic.", workspace="synthetic-job", revision="v1", dictionary_revision="v1")
        self.policy["allowed_cache_keys"].append(second["cache_key"])
        self.save()
        ledger = self.ledger()
        namespace = ledger.namespace("azure-job:" + ledger.azure_authorization_hash, "synthetic-job")
        for plan in (self.plan, second):
            row = ledger.claim(namespace, plan["cache_key"], az.BUCKET, plan["maximum_usd_micros"])
            ledger.submitted(row)
            ledger.unknown(row)
        grant = {"kind": "azure-two-manual-sdk-retakes", "workspace": "synthetic-job",
            "owner_answer": az.APPROVAL, "maximum_usd_micros": 1_000_000,
            "preserve_unknown_reservations": True, "original_question": "Synthetic up to $1 including retakes?",
            "latest_owner_direction": "Synthetic use authorized Azure", "interpretation": "Two manual retakes",
            "recorded_at_utc": "2026-10-27T00:00:00Z", "retakes": [
                {"parent_cache_key": p["cache_key"], "text_sha256": p["text_sha256"], "retake_id": "manual-"+str(i)}
                for i,p in enumerate((self.plan,second))]}
        supplemental = self.base / "supplemental.json"
        supplemental.write_text(json.dumps(grant))
        calls = []
        def send(request, credential, received):
            calls.append(1)
            headers = {"x-requestid": "manual-result", "content-type": "audio/wav"}
            received(headers)
            return headers, self.wav()
        kwargs = dict(authorization_manifest=self.manifest, supplemental_manifest=supplemental,
                      workspace="synthetic-job", revision="v1", dictionary_revision="v1")
        with patch.dict(os.environ, {"AZURE_SPEECH_KEY": "synthetic"}), patch.object(az, "sdk_transport", send):
            _, receipt = az.generate_manual_retake("Synthetic rehearsal <answer> & example.", **kwargs)
            az.generate_manual_retake("Synthetic rehearsal <answer> & example.", **kwargs)
            self.assertEqual(len(calls), 1)
            self.assertEqual(receipt["parent_unknown_cache_key"], self.plan["cache_key"])
            self.assertEqual(ledger.lookup(namespace, self.plan["cache_key"])["state"], "unknown")
            grant["interpretation"] = "Changed must not create new attempt"
            supplemental.write_text(json.dumps(grant))
            with self.assertRaises(RuntimeError):
                az.generate_manual_retake("Synthetic rehearsal <answer> & example.", **kwargs)
        with ledger.connect() as con:
            self.assertEqual(con.execute("SELECT COUNT(*) FROM requests").fetchone()[0], 3)
            self.assertEqual(con.execute("SELECT ceiling FROM budgets").fetchone()[0], 1_000_000)


class StandardExtensionTests(AzureTests):
    def standard(self):
        return az.quote("Synthetic friendly answer.", workspace="synthetic-job", revision="standard-v1",
                        dictionary_revision="v1", voice=az.STANDARD_VOICE, style="friendly")

    def extension(self, plan):
        entry = {"cache_key": plan["cache_key"], "text_sha256": plan["text_sha256"],
                 "ssml_utf8_bytes": len(plan["request"]["ssml"].encode()),
                 "maximum_usd_micros": plan["maximum_usd_micros"]}
        grant = {"kind": "azure-standard-same-ledger-extension", "owner_authorization": az.APPROVAL,
                 "workspace": "synthetic-job", "original_authorization_sha256": hashlib.sha256(self.manifest.read_bytes()).hexdigest(),
                 "maximum_aggregate_usd_micros": 1_000_000, "preserve_all_existing_reservations": True,
                 "price_policy": az.STANDARD_PRICE_POLICY, "authorized_at_utc": "2026-10-27T05:00:00Z",
                 "maximum_new_usd_micros": entry["maximum_usd_micros"], "requests": [entry]}
        path = self.base / "extension.json"
        path.write_text(json.dumps(grant))
        return path, grant

    def test_standard_quote_and_original_hd_key_stable(self):
        plan = self.standard()
        self.assertIn('mstts:express-as style="friendly"', plan["request"]["ssml"])
        self.assertEqual(plan["maximum_usd_micros"], len(plan["request"]["ssml"].encode()) * 15)
        self.assertEqual(self.plan, az.quote("Synthetic rehearsal <answer> & example.", workspace="synthetic-job", revision="v1", dictionary_revision="v1"))
        with self.assertRaises(ValueError):
            az.quote("x", workspace="j", revision="1", dictionary_revision="1", voice=az.STANDARD_VOICE)

    def test_standard_cannot_create_fresh_budget_or_use_original_authority(self):
        plan = self.standard()
        path, grant = self.extension(plan)
        with self.assertRaises(RuntimeError):
            az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)
        self.assertFalse((self.base / "AgentHub").exists())
        with self.assertRaises(RuntimeError):
            az.authorized_ledger(self.manifest, "synthetic-job", plan)

    def test_extension_reuses_ledger_preserves_unknown_and_immutable_grant(self):
        ledger = self.ledger()
        namespace = ledger.namespace("azure-job:" + ledger.azure_authorization_hash, "synthetic-job")
        row = ledger.claim(namespace, self.plan["cache_key"], az.BUCKET, 999_000)
        ledger.submitted(row)
        ledger.unknown(row)
        plan = self.standard()
        path, grant = self.extension(plan)
        original_bytes = (ledger.root / "authorization.json").read_bytes()
        extended = az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)
        self.assertEqual(extended.root, ledger.root)
        self.assertEqual(ledger.lookup(namespace, self.plan["cache_key"])["state"], "unknown")
        calls = []
        with self.assertRaises(Exception):
            az._generate(extended, plan, "synthetic-job", "synthetic", lambda *a: calls.append(a))
        self.assertEqual(calls, [])
        self.assertEqual((ledger.root / "authorization.json").read_bytes(), original_bytes)
        grant["authorized_at_utc"] = "2026-10-27T05:01:00Z"
        path.write_text(json.dumps(grant))
        with self.assertRaises(RuntimeError):
            az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)

    def test_extension_fences_changed_quote_and_overcap(self):
        self.ledger()
        plan = self.standard()
        path, grant = self.extension(plan)
        grant["requests"][0]["maximum_usd_micros"] += 1
        path.write_text(json.dumps(grant))
        with self.assertRaises(RuntimeError):
            az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)
        self.assertFalse((self.ledger().root / "standard-extension-authorization.json").exists())
        path, grant = self.extension(plan)
        grant["requests"][0].update(ssml_utf8_bytes=46001, maximum_usd_micros=690015)
        grant["maximum_new_usd_micros"] = 690015
        path.write_text(json.dumps(grant))
        with self.assertRaises(RuntimeError):
            az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)

    def test_chained_grant_pins_by_hash_preserves_parent_unknown_and_cap(self):
        ledger = self.ledger()
        plan = self.standard()
        path, _ = self.extension(plan)
        az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)
        parent = (ledger.root / "standard-extension-authorization.json").read_bytes()
        namespace = ledger.namespace("azure-job:" + ledger.azure_authorization_hash, "synthetic-job")
        row = ledger.claim(namespace, self.plan["cache_key"], az.BUCKET, 999_000)
        ledger.submitted(row)
        ledger.unknown(row)
        new = az.quote("Additional synthetic fact.", workspace="synthetic-job", revision="repair-v1",
                       dictionary_revision="v1", voice=az.STANDARD_VOICE, style="friendly")
        path, grant = self.extension(new)
        grant["parent_standard_extension_sha256"] = hashlib.sha256(parent).hexdigest()
        path.write_text(json.dumps(grant))
        raw = path.read_bytes()
        extended = az.authorized_standard_ledger(self.manifest, path, "synthetic-job", new)
        az.authorized_standard_ledger(self.manifest, path, "synthetic-job", new)
        pin = ledger.root / ("standard-extension-" + hashlib.sha256(raw).hexdigest() + ".json")
        self.assertEqual(pin.read_bytes(), raw)
        self.assertEqual((ledger.root / "standard-extension-authorization.json").read_bytes(), parent)
        self.assertEqual(ledger.lookup(namespace, self.plan["cache_key"])["state"], "unknown")
        calls = []
        with self.assertRaises(RuntimeError):
            az._generate(extended, new, "synthetic-job", "synthetic", lambda *a: calls.append(a))
        self.assertEqual(calls, [])
        with ledger.connect() as con:
            self.assertEqual(con.execute("SELECT ceiling FROM budgets").fetchone()[0], 1_000_000)

    def test_chained_grant_requires_exact_existing_original_parent(self):
        ledger = self.ledger()
        plan = self.standard()
        path, grant = self.extension(plan)
        parent_raw = path.read_bytes()
        grant["parent_standard_extension_sha256"] = hashlib.sha256(parent_raw).hexdigest()
        path.write_text(json.dumps(grant))
        with self.assertRaises(RuntimeError):
            az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)
        self.assertFalse((ledger.root / "standard-extension-authorization.json").exists())
        path.write_bytes(parent_raw)
        az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)
        for value in (None, "bad", "0" * 64):
            grant["parent_standard_extension_sha256"] = value
            path.write_text(json.dumps(grant))
            with self.assertRaises(RuntimeError):
                az.authorized_standard_ledger(self.manifest, path, "synthetic-job", plan)
        self.assertEqual((ledger.root / "standard-extension-authorization.json").read_bytes(), parent_raw)


if __name__ == "__main__":
    unittest.main()
