"""Offline synthetic fixtures only. Never contact a provider or the real ledger."""
import hashlib
import io
import json
import pathlib
import struct
import tempfile
import threading
import unittest
import wave
from unittest.mock import patch

import governed_deepgram as adapter
import deepgram_cli


def plan(text="A new clinical observation.", **changes):
    args = dict(workspace="synthetic-test", revision="test-1", dictionary_revision="literal-1", expressivity=0)
    args.update(changes)
    return adapter.quote(text, **args)


def audio():
    stream = io.BytesIO()
    with wave.open(stream, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(48000)
        w.writeframes(b"\0\0" * 100)
    return stream.getvalue()


def streaming_audio():
    raw = bytearray(audio())
    struct.pack_into("<I", raw, 4, 0x7FFF0024)
    struct.pack_into("<I", raw, 40, 0x7FFF0000)
    return bytes(raw)


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.runtime = adapter.runtime_module()

    def tearDown(self):
        self.tmp.cleanup()

    def ledger(self, ceiling=3_000_000):
        ledger = self.runtime.Ledger(self.root / "isolated-test-ledger")
        ledger.namespace("synthetic-credential", "synthetic-test")
        ledger.configure(adapter.BUCKET, ceiling)
        return ledger

    def send(self, request, credential, received):
        headers = {"dg-request-id": "synthetic-request-1", "content-type": "audio/wav"}
        received(headers)
        return headers, audio()

    def test_quote_never_creates_ledger_or_calls_transport(self):
        text = self.root / "text.txt"
        text.write_text("Fresh synthetic words.", encoding="utf-8")
        with patch.object(adapter, "generate", side_effect=AssertionError("must not execute")):
            self.assertEqual(deepgram_cli.main(["--text-file", str(text), "--workspace", "synthetic-test",
                "--revision", "1", "--dictionary-revision", "literal", "--expressivity", "0"]), 0)
        self.assertEqual(list(self.root.iterdir()), [text])

    def test_absent_incomplete_and_unbudgeted_primary_refused(self):
        absent = self.root / "missing"
        with self.assertRaises(RuntimeError):
            adapter.existing_ledger(absent)
        self.assertFalse(absent.exists())
        ledger = self.runtime.Ledger(self.root / "unbudgeted")
        with self.assertRaises(RuntimeError):
            adapter.existing_ledger(ledger.root)
        self.assertFalse((ledger.root / "namespace-salt").exists())
        ledger.namespace("fake", "test")
        with self.assertRaises(RuntimeError):
            adapter.existing_ledger(ledger.root)
        ledger.configure(adapter.BUCKET, 10000)
        self.assertEqual(adapter.existing_ledger(ledger.root).root, ledger.root)
        (ledger.root / "namespace-salt").write_bytes(b"bad")
        with self.assertRaises(RuntimeError):
            adapter.existing_ledger(ledger.root)

    def test_quote_keys_and_conservative_unicode_reservation(self):
        p = plan("é")
        self.assertEqual(p["maximum_usd_micros"], 90)
        self.assertNotEqual(plan()["cache_key"], plan(expressivity=1)["cache_key"])
        self.assertNotEqual(plan()["cache_key"], plan(dictionary_revision="literal-2")["cache_key"])
        for value in (float("nan"), float("inf"), True, -1, 2):
            with self.assertRaises(ValueError):
                plan(expressivity=value)

    def test_success_then_exact_cache_requires_zero_post_and_all_acceptance_gates(self):
        ledger, p = self.ledger(), plan()
        raw, first = adapter._generate(ledger, p, "synthetic-test", "fake", self.send)
        second_raw, second = adapter._generate(ledger, p, "synthetic-test", "fake",
                                              lambda *a: self.fail("cache repurchased"))
        self.assertEqual(raw, second_raw)
        self.assertTrue(second["reused"])
        self.assertIsNone(first["actual_usd_micros"])
        with self.assertRaises(RuntimeError):
            ledger.accept(first["namespace"], first["cache_key"], {})
        gates = {k: {"pass": True, "output_sha256": first["output_sha256"], "evidence_sha256": "a" * 64}
                 for k in self.runtime.VOICE_GATES}
        self.assertEqual(ledger.accept(first["namespace"], first["cache_key"], gates)["state"], "accepted")
        (ledger.assets / first["output_sha256"]).write_bytes(b"bad")
        with self.assertRaises(RuntimeError):
            adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("corrupt cache repurchased"))

    def test_receipt_before_body_and_unknown_fence(self):
        ledger, p = self.ledger(), plan()
        def failed(request, credential, received):
            namespace = ledger.namespace(credential, "synthetic-test")
            self.assertEqual(ledger.lookup(namespace, p["cache_key"])["state"], "submitted")
            received({"dg-request-id": "synthetic-request-2"})
            self.assertEqual(ledger.lookup(namespace, p["cache_key"])["receipt"], "synthetic-request-2")
            raise TimeoutError("provider/private detail must be suppressed")
        with self.assertRaisesRegex(RuntimeError, "unresolved"):
            adapter._generate(ledger, p, "synthetic-test", "fake", failed)
        with self.assertRaisesRegex(RuntimeError, "no repeat purchase"):
            adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("unknown repurchased"))
        self.assertEqual(ledger.status()["budgets"][0]["committed"], p["maximum_usd_micros"])
        directory = ledger.root / "response-evidence" / ledger.namespace("fake", "synthetic-test") / p["cache_key"]
        diagnostic = json.loads((directory / "diagnostic.json").read_text())
        self.assertEqual(diagnostic["stage"], "response_headers_received")
        self.assertEqual(diagnostic["request_id"], "synthetic-request-2")
        self.assertFalse((directory / "response.bin").exists())

    def test_streaming_header_normalization_preserves_pcm_and_raw_provenance(self):
        ledger, p = self.ledger(), plan()
        original = streaming_audio()
        def streaming(*args):
            headers, _ = self.send(*args)
            return headers, original
        finalized, receipt = adapter._generate(ledger, p, "synthetic-test", "fake", streaming)
        self.assertEqual(finalized, audio())
        self.assertEqual(finalized[44:], original[44:])
        directory = ledger.root / "response-evidence" / receipt["namespace"] / receipt["cache_key"]
        self.assertEqual((directory / "response.bin").read_bytes(), original)
        diagnostic = json.loads((directory / "diagnostic.json").read_text())
        self.assertEqual(diagnostic["response_sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual(diagnostic["output_sha256"], receipt["output_sha256"])
        self.assertEqual(diagnostic["normalization"], "pcm48k-mono16-streaming-7fff0000-v1")
        self.assertEqual(diagnostic["stage"], "pending")
        self.assertEqual(receipt["response_provenance"]["response_sha256"], diagnostic["response_sha256"])
        self.assertNotEqual(diagnostic["response_sha256"], diagnostic["output_sha256"])
        self.assertEqual(receipt["acceptance_state"], "pending")
        _, reused = adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("repurchased"))
        self.assertTrue(reused["reused"])
        self.assertEqual(reused["response_provenance"], receipt["response_provenance"])

    def test_pre_submission_evidence_failure_cancels_only_never_submitted_claim(self):
        ledger, p = self.ledger(), plan()
        with patch.object(adapter, "_write_diagnostic", side_effect=OSError("private")):
            with self.assertRaisesRegex(RuntimeError, "no submission made"):
                adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("must not submit"))
        self.assertIsNone(ledger.lookup(ledger.namespace("fake", "synthetic-test"), p["cache_key"]))
        self.assertEqual(ledger.status()["budgets"][0]["committed"], 0)

    def test_post_completion_diagnostic_failure_does_not_change_pending_asset(self):
        ledger, p = self.ledger(), plan()
        original_write = adapter._write_diagnostic
        def fail_pending(directory, diagnostic):
            if diagnostic["stage"] == "pending":
                raise OSError("private")
            return original_write(directory, diagnostic)
        with patch.object(adapter, "_write_diagnostic", side_effect=fail_pending):
            raw, receipt = adapter._generate(ledger, p, "synthetic-test", "fake", self.send)
        self.assertEqual(raw, audio())
        self.assertEqual(receipt["acceptance_state"], "pending")
        self.assertEqual(receipt["response_provenance"]["output_sha256"], receipt["output_sha256"])

    def test_streaming_and_finalized_malformed_audio_remain_rejected(self):
        bad = [audio()[:-2], streaming_audio()[:44], streaming_audio()[:-1]]
        for offset, fmt, value in ((40, "<I", 0x7FFF0001), (16, "<I", 18),
                                   (20, "<H", 3), (22, "<H", 2), (24, "<I", 44100),
                                   (28, "<I", 1), (32, "<H", 1), (34, "<H", 8)):
            raw = bytearray(streaming_audio())
            struct.pack_into(fmt, raw, offset, value)
            bad.append(bytes(raw))
        for raw in bad:
            with self.subTest(header=raw[:44]), self.assertRaises((RuntimeError, wave.Error, EOFError)):
                adapter._prepare_audio(raw, "audio/wav")
        with self.assertRaises(RuntimeError):
            adapter._prepare_audio(streaming_audio(), "application/octet-stream")
        with patch.object(adapter, "MAX_RESPONSE_BYTES", 128), self.assertRaises(RuntimeError):
            adapter._prepare_audio(streaming_audio(), "audio/wav")
        self.assertEqual(adapter._prepare_audio(audio(), "audio/wav"), (audio(), None))

    def test_invalid_mime_keeps_raw_response_and_unknown_without_retry(self):
        ledger, p = self.ledger(), plan()
        def wrong_mime(request, credential, received):
            headers = {"dg-request-id": "synthetic-mime", "content-type": "application/octet-stream"}
            received(headers)
            return headers, audio()
        with self.assertRaisesRegex(RuntimeError, "audio_validation"):
            adapter._generate(ledger, p, "synthetic-test", "fake", wrong_mime)
        namespace = ledger.namespace("fake", "synthetic-test")
        directory = ledger.root / "response-evidence" / namespace / p["cache_key"]
        self.assertEqual((directory / "response.bin").read_bytes(), audio())
        diagnostic = json.loads((directory / "diagnostic.json").read_text())
        self.assertEqual(diagnostic["content_type"], "application/octet-stream")
        self.assertEqual(ledger.lookup(namespace, p["cache_key"])["state"], "unknown")
        with self.assertRaisesRegex(RuntimeError, "no repeat purchase"):
            adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("repurchased"))

    def test_quarantine_write_failure_retains_receipt_and_reservation(self):
        ledger, p = self.ledger(), plan()
        original_write = adapter._durable_evidence
        def fail_raw(path, raw):
            if path.name == "response.bin":
                raise OSError("private diagnostic must not leak")
            return original_write(path, raw)
        with patch.object(adapter, "_durable_evidence", side_effect=fail_raw):
            with self.assertRaisesRegex(RuntimeError, "response_quarantine"):
                adapter._generate(ledger, p, "synthetic-test", "fake", self.send)
        row = ledger.lookup(ledger.namespace("fake", "synthetic-test"), p["cache_key"])
        self.assertEqual(row["state"], "unknown")
        self.assertEqual(row["receipt"], "synthetic-request-1")
        self.assertIsNone(row["sha256"])
        self.assertEqual(ledger.status()["budgets"][0]["committed"], p["maximum_usd_micros"])

    def test_transport_body_read_failure_binds_receipt_and_never_retries(self):
        ledger, p = self.ledger(), plan()
        class Response:
            headers = {"dg-request-id": "synthetic-interrupted", "content-type": "audio/wav"}
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def read(self, limit):
                raise ConnectionError("private provider detail")
        with patch.object(adapter.urllib.request, "build_opener") as factory:
            factory.return_value.open.return_value = Response()
            with self.assertRaisesRegex(RuntimeError, "response_headers_received"):
                adapter._generate(ledger, p, "synthetic-test", "fake", adapter.transport)
            self.assertEqual(factory.return_value.open.call_count, 1)
        row = ledger.lookup(ledger.namespace("fake", "synthetic-test"), p["cache_key"])
        self.assertEqual((row["state"], row["receipt"]), ("unknown", "synthetic-interrupted"))

    def test_asset_persistence_failure_keeps_quarantined_body_and_unknown(self):
        ledger, p = self.ledger(), plan()
        with patch.object(ledger, "complete", side_effect=OSError("private failure")):
            with self.assertRaisesRegex(RuntimeError, "asset_persistence"):
                adapter._generate(ledger, p, "synthetic-test", "fake", self.send)
        namespace = ledger.namespace("fake", "synthetic-test")
        directory = ledger.root / "response-evidence" / namespace / p["cache_key"]
        self.assertEqual((directory / "response.bin").read_bytes(), audio())
        self.assertEqual(ledger.lookup(namespace, p["cache_key"])["state"], "unknown")

    def test_transport_short_content_length_never_normalizes_partial_pcm(self):
        ledger, p = self.ledger(), plan()
        class Response:
            headers = {"dg-request-id": "synthetic-short-body", "content-type": "audio/wav",
                       "content-length": str(len(streaming_audio()) + 2)}
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def read(self, limit):
                return streaming_audio()
        with patch.object(adapter.urllib.request, "build_opener") as factory:
            factory.return_value.open.return_value = Response()
            with self.assertRaisesRegex(RuntimeError, "http_body_validation"):
                adapter._generate(ledger, p, "synthetic-test", "fake", adapter.transport)
        namespace = ledger.namespace("fake", "synthetic-test")
        row = ledger.lookup(namespace, p["cache_key"])
        self.assertEqual(row["state"], "unknown")
        self.assertIsNone(row["sha256"])
        directory = ledger.root / "response-evidence" / namespace / p["cache_key"]
        self.assertEqual((directory / "response.bin").read_bytes(), streaming_audio())
        diagnostic = json.loads((directory / "diagnostic.json").read_text())
        self.assertEqual(diagnostic["declared_response_bytes"], len(streaming_audio()) + 2)
        self.assertEqual(diagnostic["response_bytes"], len(streaming_audio()))
        self.assertEqual(diagnostic["response_sha256"], hashlib.sha256(streaming_audio()).hexdigest())
        with self.assertRaisesRegex(RuntimeError, "no repeat purchase"):
            adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("repurchased"))

    def test_cached_provenance_wrong_json_types_do_not_break_asset_reuse(self):
        ledger, p = self.ledger(), plan()
        _, receipt = adapter._generate(ledger, p, "synthetic-test", "fake", self.send)
        evidence_path = ledger.root / "response-evidence" / receipt["namespace"] / receipt["cache_key"] / "diagnostic.json"
        for value in (None, [], ["unexpected"], 12, "unexpected"):
            with self.subTest(value=value):
                evidence_path.write_text(json.dumps(value))
                raw, reused = adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("repurchased"))
                self.assertEqual(raw, audio())
                self.assertTrue(reused["reused"])
                self.assertIsNone(reused["response_provenance"])

    def test_cached_provenance_parent_link_is_not_read(self):
        ledger, p = self.ledger(), plan()
        _, receipt = adapter._generate(ledger, p, "synthetic-test", "fake", self.send)
        evidence_root = ledger.root / "response-evidence"
        original_linked = self.runtime.linked_path
        def linked(path):
            return pathlib.Path(path) == evidence_root or original_linked(path)
        with patch.object(self.runtime, "linked_path", side_effect=linked):
            raw, reused = adapter._generate(ledger, p, "synthetic-test", "fake", lambda *a: self.fail("repurchased"))
        self.assertEqual(raw, audio())
        self.assertTrue(reused["reused"])
        self.assertIsNone(reused["response_provenance"])

    def test_invalid_audio_missing_receipt_and_429_retain_reservation(self):
        for mode in ("audio", "receipt", "429"):
            with self.subTest(mode=mode):
                p, ledger = plan(mode), self.ledger()
                def bad(request, credential, received):
                    if mode == "429":
                        raise RuntimeError("429")
                    headers = {"content-type": "audio/wav"}
                    if mode != "receipt":
                        headers["dg-request-id"] = "synthetic-bad"
                    received(headers)
                    return headers, b"truncated"
                with self.assertRaisesRegex(RuntimeError, "unresolved"):
                    adapter._generate(ledger, p, "synthetic-test", mode, bad)
                self.assertEqual(ledger.lookup(ledger.namespace(mode, "synthetic-test"), p["cache_key"])["state"], "unknown")

    def test_global_ceiling_across_credentials(self):
        p = plan()
        ledger = self.ledger(p["maximum_usd_micros"])
        adapter._generate(ledger, p, "synthetic-test", "one", self.send)
        with self.assertRaises(RuntimeError):
            adapter._generate(ledger, plan("Other text."), "another-workspace", "two",
                              lambda *a: self.fail("over budget"))

    def test_concurrent_exact_request_has_only_one_submission(self):
        ledger, p = self.ledger(), plan()
        entered, release = threading.Event(), threading.Event()
        results, failures = [], []
        def slow(*args):
            entered.set()
            if not release.wait(5):
                raise RuntimeError("test release timed out")
            return self.send(*args)
        def leader():
            try:
                results.append(adapter._generate(ledger, p, "synthetic-test", "same", slow))
            except Exception as exc:
                failures.append(exc)
        worker = threading.Thread(target=leader)
        worker.start()
        try:
            self.assertTrue(entered.wait(5))
            with self.assertRaisesRegex(RuntimeError, "no repeat purchase"):
                adapter._generate(ledger, p, "synthetic-test", "same", lambda *a: self.fail("concurrent duplicate"))
        finally:
            release.set()
            worker.join(5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(failures, [])
        self.assertEqual(len(results), 1)

    def test_linked_primary_is_refused_before_constructor(self):
        with patch.object(self.runtime, "linked_path", return_value=True), patch.object(self.runtime, "Ledger", side_effect=AssertionError("must not construct")):
            with self.assertRaises(RuntimeError):
                adapter.existing_ledger(self.root / "linked")
        self.assertIsNone(adapter._NoRedirect().redirect_request(None, None, 302, None, {}, "https://other.invalid"))

    def policy(self, p):
        text_hash = hashlib.sha256(p["request"]["text"].encode()).hexdigest()
        proof = {"kind": "deepgram-new-input-inventory", "enumerated_scopes": ["isolated synthetic fixture"],
                 "historical_rendered_text_sha256": [], "ambiguous_rendered_text_sha256": [],
                 "new_rendered_text_sha256": [text_hash]}
        proof_path = self.root / "proof.json"
        proof_path.write_text(json.dumps(proof), encoding="utf-8")
        policy = {"epoch_id": "deepgram-offline-test", "maximum_usd_micros": 3_000_000,
                  "owner_authorization": "Synthetic test authorization only", "workspace": "synthetic-test",
                  "historical_accounting": "UNKNOWN", "historical_requests": "FENCED", "price_policy": adapter.PRICE_POLICY,
                  "allowed_requests": [{"text_sha256": text_hash, "cache_key": p["cache_key"]}],
                  "inventory_proof": {"path": str(proof_path), "sha256": hashlib.sha256(proof_path.read_bytes()).hexdigest()}}
        manifest = self.root / "authorization-input.json"
        manifest.write_text(json.dumps(policy), encoding="utf-8")
        return manifest, policy, proof, proof_path

    def test_epoch_exact_allowlist_immutable_cap_and_cross_credential_cache(self):
        p = plan()
        manifest, policy, _, _ = self.policy(p)
        with patch.dict("os.environ", {"LOCALAPPDATA": str(self.root)}), patch.object(self.runtime, "running_on_windows", return_value=True):
            ledger = adapter.recovery_epoch_ledger(manifest, "synthetic-test", p)
            _, first = adapter._generate(ledger, p, "synthetic-test", "credential-one", self.send)
            again = adapter.recovery_epoch_ledger(manifest, "synthetic-test", p)
            _, second = adapter._generate(again, p, "synthetic-test", "credential-two", lambda *a: self.fail("credential changed repurchase"))
            self.assertEqual(first["namespace"], second["namespace"])
            self.assertEqual(first["historical_requests"], "FENCED")
            with self.assertRaises(RuntimeError):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", plan(expressivity=1))
            policy["maximum_usd_micros"] = 2_000_000
            manifest.write_text(json.dumps(policy), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "immutable"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", p)
            self.assertFalse((self.root / "AgentHub/runtime/content-controls").exists())

    def test_epoch_historical_and_ambiguous_inputs_overcap_and_partial_state_refused(self):
        p = plan()
        manifest, policy, proof, proof_path = self.policy(p)
        with patch.dict("os.environ", {"LOCALAPPDATA": str(self.root)}), patch.object(self.runtime, "running_on_windows", return_value=True):
            for field in ("historical_rendered_text_sha256", "ambiguous_rendered_text_sha256"):
                proof[field] = proof["new_rendered_text_sha256"]
                proof_path.write_text(json.dumps(proof), encoding="utf-8")
                policy["inventory_proof"]["sha256"] = hashlib.sha256(proof_path.read_bytes()).hexdigest()
                manifest.write_text(json.dumps(policy), encoding="utf-8")
                with self.assertRaises(RuntimeError):
                    adapter.recovery_epoch_ledger(manifest, "synthetic-test", p)
                proof[field] = []
            manifest, policy, _, _ = self.policy(p)
            policy["maximum_usd_micros"] = 3_000_001
            manifest.write_text(json.dumps(policy), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", p)
            manifest, policy, _, _ = self.policy(p)
            root = self.root / "AgentHub/runtime/content-recovery-epochs/deepgram-offline-test"
            root.mkdir(parents=True)
            (root / "authorization.json").write_bytes(manifest.read_bytes())
            with self.assertRaisesRegex(RuntimeError, "Restore intact"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", p)
            self.assertFalse((root / "ledger.sqlite3").exists())


if __name__ == "__main__":
    unittest.main()
