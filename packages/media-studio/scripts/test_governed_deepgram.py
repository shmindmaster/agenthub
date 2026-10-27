"""Offline synthetic fixtures only. Never contact a provider or the real ledger."""
import hashlib
import contextlib
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
import os

# The content ledger refuses linked directories by design. Resolve the temp root once so
# fixtures stay valid when TMPDIR sits under a junction (e.g. %LOCALAPPDATA%\AgentHub).
tempfile.tempdir = os.path.realpath(tempfile.gettempdir())


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

    @contextlib.contextmanager
    def epoch_environment(self):
        with patch.dict("os.environ", {"LOCALAPPDATA": str(self.root)}), patch.object(self.runtime, "running_on_windows", return_value=True):
            yield

    def test_legacy_parent_scope_receipts_preserved_but_not_new_batches(self):
        p, new = plan(), plan("New words after a structured parent inventory.")
        original, policy, proof, proof_path = self.policy(p)
        legacy = {"path": str(self.root), "exists": True, "enumeration": "Complete synthetic enumeration",
                  "filesEnumerated": 4, "deepgramEvidenceFiles": 1}
        proof["enumerated_scopes"] = [legacy]
        proof_path.write_text(json.dumps(proof), encoding="utf-8")
        policy["inventory_proof"]["sha256"] = hashlib.sha256(proof_path.read_bytes()).hexdigest()
        original.write_text(json.dumps(policy), encoding="utf-8")
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            parent_bytes = (ledger.root / "authorization.json").read_bytes()
            proof_bytes = proof_path.read_bytes()
            batch, batch_policy = self.batch_policy(original, new)
            adapter.recovery_epoch_ledger(batch, "synthetic-test", new)
            self.assertEqual((ledger.root / "authorization.json").read_bytes(), parent_bytes)
            self.assertEqual(proof_path.read_bytes(), proof_bytes)
            batch_proof_path = pathlib.Path(batch_policy["inventory_proof"]["path"])
            batch_proof = json.loads(batch_proof_path.read_bytes())
            batch_proof["enumerated_scopes"] = [legacy]
            batch_proof_path.write_text(json.dumps(batch_proof), encoding="utf-8")
            batch_policy["inventory_proof"]["sha256"] = hashlib.sha256(batch_proof_path.read_bytes()).hexdigest()
            with self.assertRaises(RuntimeError):
                adapter._epoch_policy(json.dumps(batch_policy).encode(), "synthetic-test")
        for invalid in ({}, {**legacy, "exists": 1}, {**legacy, "path": " "},
                        {**legacy, "enumeration": ""}, {**legacy, "filesEnumerated": -1},
                        {**legacy, "deepgramEvidenceFiles": True},
                        {**legacy, "deepgramEvidenceFiles": 5}, {**legacy, "extra": "unrecognized"}):
            with self.subTest(invalid=invalid):
                proof["enumerated_scopes"] = [invalid]
                proof_path.write_text(json.dumps(proof), encoding="utf-8")
                policy["inventory_proof"]["sha256"] = hashlib.sha256(proof_path.read_bytes()).hexdigest()
                with self.assertRaises(RuntimeError):
                    adapter._epoch_policy(json.dumps(policy).encode(), "synthetic-test")

    def test_inherited_historical_ambiguity_empty_registration_recovery(self):
        p, new = plan(), plan("New words after conservative historical ambiguity.")
        original, policy, proof, proof_path = self.policy(p)
        historical = hashlib.sha256(b"historical uncertain content").hexdigest()
        proof["historical_rendered_text_sha256"] = [historical]
        proof["ambiguous_rendered_text_sha256"] = [historical]
        proof_path.write_text(json.dumps(proof), encoding="utf-8")
        policy["inventory_proof"]["sha256"] = hashlib.sha256(proof_path.read_bytes()).hexdigest()
        original.write_text(json.dumps(policy), encoding="utf-8")
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            parent_bytes = (ledger.root / "authorization.json").read_bytes()
            proof_bytes = proof_path.read_bytes()
            batch, batch_policy = self.batch_policy(original, new)
            # Preserve a real first-attempt failure's empty directory. No
            # index/pair/reservation was written; recovery must be append-only.
            directory = ledger.root / "additional-batches"
            directory.mkdir()
            adapter.recovery_epoch_ledger(batch, "synthetic-test", new)
            self.assertEqual((ledger.root / "authorization.json").read_bytes(), parent_bytes)
            self.assertEqual(proof_path.read_bytes(), proof_bytes)
            self.assertEqual(len(list(directory.iterdir())), 2)
            self.assertTrue((ledger.root / "additional-batches.index.json").is_file())
            # Prior allowed/unsubmitted input cannot newly become ambiguous.
            next_plan = plan("Second new input.")
            next_batch, next_policy = self.batch_policy(original, next_plan, batch="later", prior=(batch,))
            next_proof_path = pathlib.Path(next_policy["inventory_proof"]["path"])
            next_proof = json.loads(next_proof_path.read_bytes())
            next_proof["ambiguous_rendered_text_sha256"].append(hashlib.sha256(new["request"]["text"].encode()).hexdigest())
            next_proof_path.write_text(json.dumps(next_proof), encoding="utf-8")
            next_policy["inventory_proof"]["sha256"] = hashlib.sha256(next_proof_path.read_bytes()).hexdigest()
            next_batch.write_text(json.dumps(next_policy), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "contradicts"):
                adapter.recovery_epoch_ledger(next_batch, "synthetic-test", next_plan)
            self.assertFalse((directory / "later.json").exists())

    def batch_policy(self, parent, p, batch="new-words", prior=()):
        original = json.loads(parent.read_bytes())
        original_proof = json.loads(pathlib.Path(original["inventory_proof"]["path"]).read_bytes())
        historical = set(original_proof["historical_rendered_text_sha256"])
        ambiguous = set(original_proof["ambiguous_rendered_text_sha256"])
        historical.update(r["text_sha256"] for r in original["allowed_requests"])
        for previous in prior:
            previous_policy = json.loads(previous.read_bytes())
            previous_proof = json.loads(pathlib.Path(previous_policy["inventory_proof"]["path"]).read_bytes())
            historical.update(previous_proof["historical_rendered_text_sha256"])
            historical.update(r["text_sha256"] for r in previous_policy["allowed_requests"])
            ambiguous.update(previous_proof["ambiguous_rendered_text_sha256"])
        text_hash = hashlib.sha256(p["request"]["text"].encode()).hexdigest()
        proof = {"kind": "deepgram-new-input-inventory", "enumerated_scopes": ["complete isolated synthetic fixtures"],
                 "historical_rendered_text_sha256": sorted(historical), "ambiguous_rendered_text_sha256": sorted(ambiguous),
                 "new_rendered_text_sha256": [text_hash]}
        proof_path = self.root / (batch + ".proof.json")
        proof_path.write_text(json.dumps(proof), encoding="utf-8")
        policy = {**original, "additional_batch_id": batch,
                  "parent_authorization_sha256": hashlib.sha256(parent.read_bytes()).hexdigest(),
                  "allowed_requests": [{"text_sha256": text_hash, "cache_key": p["cache_key"]}],
                  "inventory_proof": {"path": str(proof_path), "sha256": hashlib.sha256(proof_path.read_bytes()).hexdigest()}}
        manifest = self.root / (batch + ".manifest.json")
        manifest.write_text(json.dumps(policy), encoding="utf-8")
        return manifest, policy

    def test_additional_batch_preserves_original_namespace_salt_cap_and_unknown(self):
        p, new = plan(), plan("A genuinely new synthetic passage.", revision="test-2")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            namespace = ledger.namespace(ledger.deepgram_epoch_namespace, "synthetic-test")
            claim = ledger.claim(namespace, p["cache_key"], adapter.BUCKET, p["maximum_usd_micros"])
            ledger.submitted(claim)
            ledger.unknown(claim)
            before = {name: (ledger.root / name).read_bytes() for name in ("authorization.json", "namespace-salt")}
            manifest, _ = self.batch_policy(original, new)
            batch_ledger = adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertEqual(batch_ledger.root, ledger.root)
            self.assertEqual(batch_ledger.deepgram_epoch_namespace, ledger.deepgram_epoch_namespace)
            _, receipt = adapter._generate(batch_ledger, new, "synthetic-test", "different-credential", self.send)
            self.assertEqual(receipt["namespace"], namespace)
            self.assertEqual(batch_ledger.lookup(namespace, p["cache_key"])["state"], "unknown")
            self.assertEqual(batch_ledger.status()["budgets"][0]["ceiling"], 3_000_000)
            self.assertEqual(batch_ledger.status()["budgets"][0]["committed"], p["maximum_usd_micros"] + new["maximum_usd_micros"])
            for name, raw in before.items():
                self.assertEqual((ledger.root / name).read_bytes(), raw)
            again = adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            _, reused = adapter._generate(again, new, "synthetic-test", "another-credential", lambda *a: self.fail("repurchase"))
            self.assertTrue(reused["reused"])

    def test_additional_batch_never_initializes_absent_or_incomplete_epoch(self):
        p, new = plan(), plan("Never initialize a batch epoch.")
        original, _, _, _ = self.policy(p)
        manifest, _ = self.batch_policy(original, new)
        root = self.root / "AgentHub/runtime/content-recovery-epochs/deepgram-offline-test"
        with self.epoch_environment(), self.assertRaises(RuntimeError):
            adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
        self.assertFalse(root.exists())
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            (root / "namespace-salt").unlink()
            with self.assertRaises(RuntimeError):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertFalse((root / "namespace-salt").exists())
            self.assertFalse((ledger.root / "additional-batches").exists())

    def test_additional_batch_budget_exhausted_does_not_submit_or_reset(self):
        p, new = plan(), plan("No extra budget.")
        original, policy, _, _ = self.policy(p)
        policy["maximum_usd_micros"] = p["maximum_usd_micros"]
        original.write_text(json.dumps(policy), encoding="utf-8")
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            adapter._generate(ledger, p, "synthetic-test", "fake", self.send)
            manifest, _ = self.batch_policy(original, new)
            batch = adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            with self.assertRaises(RuntimeError):
                adapter._generate(batch, new, "synthetic-test", "other", lambda *a: self.fail("over cap"))
            self.assertEqual(batch.status()["budgets"][0]["committed"], p["maximum_usd_micros"])
            self.assertEqual(batch.status()["budgets"][0]["ceiling"], p["maximum_usd_micros"])

    def test_additional_batch_fences_unsubmitted_original_and_prior_batch_under_new_settings(self):
        p, new, newer = plan(), plan("New batch words."), plan("Later batch words.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            for text in (p["request"]["text"],):
                changed = plan(text, expressivity=1)
                manifest, _ = self.batch_policy(original, changed, "overlap-original")
                with self.assertRaises(RuntimeError):
                    adapter.recovery_epoch_ledger(manifest, "synthetic-test", changed)
            first, _ = self.batch_policy(original, new, "first")
            adapter.recovery_epoch_ledger(first, "synthetic-test", new)
            changed = plan(new["request"]["text"], dictionary_revision="changed")
            overlap, _ = self.batch_policy(original, changed, "overlap-prior", prior=(first,))
            with self.assertRaises(RuntimeError):
                adapter.recovery_epoch_ledger(overlap, "synthetic-test", changed)
            omitted, _ = self.batch_policy(original, newer, "omitted-prior")
            with self.assertRaises(RuntimeError):
                adapter.recovery_epoch_ledger(omitted, "synthetic-test", newer)
            second, _ = self.batch_policy(original, newer, "second", prior=(first,))
            adapter.recovery_epoch_ledger(second, "synthetic-test", newer)
            adapter.recovery_epoch_ledger(first, "synthetic-test", new)  # old immutable batch still reusable
            self.assertEqual(ledger.status()["budgets"][0]["committed"], 0)

    def test_additional_batch_changed_parent_policy_proof_and_registration_refused(self):
        p, new = plan(), plan("Tamper check words.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            manifest, policy = self.batch_policy(original, new)
            raw = manifest.read_bytes()
            for field, value in (("parent_authorization_sha256", "0" * 64),
                                 ("maximum_usd_micros", 2_000_000),
                                 ("owner_authorization", "Changed authorization")):
                manifest.write_text(json.dumps({**policy, field: value}), encoding="utf-8")
                with self.assertRaises(RuntimeError):
                    adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            manifest.write_bytes(raw)
            adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            manifest.write_bytes(raw + b" ")
            with self.assertRaisesRegex(RuntimeError, "immutable"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            manifest.write_bytes(raw)
            stored = ledger.root / "additional-batches/new-words.json"
            stored.write_bytes(raw + b" ")
            with self.assertRaisesRegex(RuntimeError, "changed"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            stored.write_bytes(raw)
            proof = pathlib.Path(policy["inventory_proof"]["path"])
            proof.write_bytes(proof.read_bytes() + b" ")
            with self.assertRaisesRegex(RuntimeError, "proof changed"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)

    def test_additional_batch_checks_other_registrations_and_interrupted_pair(self):
        p, new, newer = plan(), plan("First isolated batch."), plan("Second isolated batch.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            first, _ = self.batch_policy(original, new, "first")
            adapter.recovery_epoch_ledger(first, "synthetic-test", new)
            second, _ = self.batch_policy(original, newer, "second", prior=(first,))
            adapter.recovery_epoch_ledger(second, "synthetic-test", newer)
            digest = ledger.root / "additional-batches/second.sha256"
            digest.unlink()
            with self.assertRaisesRegex(RuntimeError, "Incomplete"):
                adapter.recovery_epoch_ledger(first, "synthetic-test", new)
            self.assertFalse(digest.exists())

    def test_additional_batch_registration_serialization_and_stale_lock(self):
        p, new = plan(), plan("Concurrent batch registration.")
        original, _, _, _ = self.policy(p)
        entered, release = threading.Event(), threading.Event()
        failures = []
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            manifest, _ = self.batch_policy(original, new)
            secure = self.runtime.secure_directory
            def paused(path):
                if path.name == "additional-batches":
                    entered.set()
                    if not release.wait(5):
                        raise RuntimeError("test timeout")
                return secure(path)
            def register():
                try:
                    adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
                except Exception as error:
                    failures.append(error)
            with patch.object(self.runtime, "secure_directory", side_effect=paused):
                thread = threading.Thread(target=register)
                thread.start()
                try:
                    self.assertTrue(entered.wait(5))
                    with self.assertRaisesRegex(RuntimeError, "busy or interrupted"):
                        adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
                finally:
                    release.set()
                    thread.join(5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(failures, [])
            guard = ledger.root / "batch-registration.lock"
            guard.write_bytes(b"interrupted")
            with self.assertRaisesRegex(RuntimeError, "busy or interrupted"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertEqual(guard.read_bytes(), b"interrupted")

    def test_additional_batch_rejects_linked_inventory_ancestor_before_registration(self):
        p, new = plan(), plan("Linked inventory test.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            manifest, policy = self.batch_policy(original, new)
            proof_parent = pathlib.Path(policy["inventory_proof"]["path"]).parent
            with patch.object(self.runtime, "linked_path", side_effect=lambda path: path == proof_parent):
                with self.assertRaises(RuntimeError):
                    adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertFalse((ledger.root / "additional-batches").exists())

    def test_additional_batch_missing_pair_directory_or_index_mismatch_blocks_reuse(self):
        p, new = plan(), plan("Registry completeness check.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            manifest, _ = self.batch_policy(original, new)
            adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            directory = ledger.root / "additional-batches"
            raw_pair = {path.name: path.read_bytes() for path in directory.iterdir()}
            for path in directory.iterdir():
                path.unlink()
            with self.assertRaisesRegex(RuntimeError, "Incomplete"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            for name, raw in raw_pair.items():
                (directory / name).write_bytes(raw)
            moved = ledger.root / "removed-batch-directory"
            directory.rename(moved)
            with self.assertRaisesRegex(RuntimeError, "Incomplete"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertFalse(directory.exists())
            moved.rename(directory)
            index = ledger.root / "additional-batches.index.json"
            raw_index = index.read_bytes()
            data = json.loads(raw_index)
            data["batches"]["new-words"] = "0" * 64
            index.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "changed"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            index.write_bytes(raw_index)
            index.unlink()
            with self.assertRaisesRegex(RuntimeError, "Incomplete"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertFalse(index.exists())

    def test_additional_batch_interrupted_index_write_is_not_reconstructed(self):
        p, new = plan(), plan("Interrupted registration check.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            manifest, _ = self.batch_policy(original, new)
            with patch.object(adapter, "_durable_evidence", side_effect=OSError("synthetic interruption")):
                with self.assertRaises(OSError):
                    adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertTrue((ledger.root / "additional-batches/new-words.json").exists())
            self.assertFalse((ledger.root / "additional-batches.index.json").exists())
            with self.assertRaisesRegex(RuntimeError, "Incomplete"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertEqual(ledger.status()["budgets"][0]["committed"], 0)

    def test_additional_batch_missing_database_mutated_original_and_ceiling_fail_closed(self):
        p, new = plan(), plan("Accounting intact check.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            manifest, _ = self.batch_policy(original, new)
            auth = ledger.root / "authorization.json"
            original_raw = auth.read_bytes()
            auth.write_bytes(original_raw + b" ")
            with self.assertRaises(RuntimeError):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            auth.write_bytes(original_raw)
            db = ledger.root / "ledger.sqlite3"
            removed = ledger.root / "removed-ledger.sqlite3"
            db.rename(removed)
            with self.assertRaisesRegex(RuntimeError, "Restore intact"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertFalse(db.exists())
            removed.rename(db)
            with ledger.connect() as con:
                con.execute("UPDATE budgets SET ceiling=1 WHERE bucket=?", (adapter.BUCKET,))
            with self.assertRaisesRegex(RuntimeError, "ceiling differs"):
                adapter.recovery_epoch_ledger(manifest, "synthetic-test", new)
            self.assertFalse((ledger.root / "additional-batches").exists())

    def test_additional_batch_cannot_reclassify_prior_unsubmitted_text_as_ambiguous(self):
        p, new, newer = plan(), plan("Previously permitted but never submitted."), plan("Separate new passage.")
        original, _, _, _ = self.policy(p)
        with self.epoch_environment():
            ledger = adapter.recovery_epoch_ledger(original, "synthetic-test", p)
            first, _ = self.batch_policy(original, new, "first")
            adapter.recovery_epoch_ledger(first, "synthetic-test", new)
            second, policy = self.batch_policy(original, newer, "second", prior=(first,))
            proof_path = pathlib.Path(policy["inventory_proof"]["path"])
            proof = json.loads(proof_path.read_bytes())
            proof["ambiguous_rendered_text_sha256"] = [hashlib.sha256(new["request"]["text"].encode()).hexdigest()]
            proof_path.write_text(json.dumps(proof), encoding="utf-8")
            policy["inventory_proof"]["sha256"] = hashlib.sha256(proof_path.read_bytes()).hexdigest()
            second.write_text(json.dumps(policy), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "contradicts previously known"):
                adapter.recovery_epoch_ledger(second, "synthetic-test", newer)
            self.assertFalse((ledger.root / "additional-batches/second.json").exists())
            self.assertIsNone(ledger.lookup(ledger.namespace(ledger.deepgram_epoch_namespace, "synthetic-test"), new["cache_key"]))


if __name__ == "__main__":
    unittest.main()
