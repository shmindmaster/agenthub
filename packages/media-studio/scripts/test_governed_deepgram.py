"""Offline synthetic fixtures only. Never contact a provider or the real ledger."""
import hashlib
import io
import json
import pathlib
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
