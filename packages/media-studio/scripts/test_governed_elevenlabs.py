"""Offline recovery, acceptance and independent-process checks for the speech adapter. No sockets, even loopback."""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from test_elevenlabs_cli import AUDIO, EPOCH, TEXT, V4_SETTINGS, VOICE, WORKSPACE, REVISION
import test_elevenlabs_cli as fixtures
import content_control
import content_runtime
import elevenlabs_cli as cli

RAW = AUDIO[2]
HISTORY = "fixture-history"
# Located through the known folder: the Python harness points LOCALAPPDATA at a sandbox.
ALIAS = content_runtime.local_app_data() / "Microsoft/WindowsApps/python.exe" if os.name == "nt" else None
GOOD_HISTORY = {"request_id": "fixture-request", "history_item_id": HISTORY,
                "character_count_change_from": 0, "character_count_change_to": 5}


class EpochCase(fixtures.PaidFixture):
    def purchase_lost_after_receipt(self):
        """The provider accepted the request and bound its id, then the response was lost."""
        self.manifest = self.authorize()

        def provider(*_args, on_headers=None, **_kwargs):
            on_headers({"request-id": "fixture-request"})
            raise RuntimeError("synthetic lost response")

        with self.paid(provider):
            self.assertEqual(self.speak(), 2)
        return self.request_row()

    def purchase_complete(self):
        self.manifest = self.authorize()
        with self.paid():
            self.assertEqual(self.speak(), 0, self.err)
        return self.request_row()

    def request_row(self):
        with self.ledger.connect() as con:
            return dict(con.execute("SELECT * FROM requests").fetchone())


class Reconcile(EpochCase):
    def reconcile(self, row, *changes, history=None, manifest=None):
        """Provider metadata comes from GOOD_HISTORY unless a test replaces it."""
        args = ["reconcile", "--authorization-manifest", str(manifest or self.manifest), "--namespace", row["namespace"],
                "--cache-key", row["key"], "--cache-workspace", WORKSPACE, "--history-id", HISTORY, *changes]
        with patch.object(cli, "_get_json", return_value=history or GOOD_HISTORY) as metadata, \
                patch.object(cli, "_request_full", return_value=(200, "audio/mpeg", RAW, {})) as audio:
            self.history_calls, self.audio_calls = metadata, audio
            return self.invoke(*args)

    def test_a_lost_response_recovers_without_a_second_purchase(self):
        row = self.purchase_lost_after_receipt()
        self.assertEqual(self.reconcile(row), 0, self.err)
        self.assertEqual(json.loads(self.out), {"reconciled": True, "actual_credits": 5, "acceptance_state": "pending"})
        self.assertEqual(self.audio_calls.call_args.args, (f"/history/{HISTORY}/audio",))
        self.assertEqual(self.committed(), 5)
        with self.paid() as post:
            self.assertEqual(self.speak("recovered.mp3"), 0, self.err)
        post.assert_not_called()
        self.assertEqual((self.root / "recovered.mp3").read_bytes(), RAW)

    def test_settling_a_completed_request_keeps_its_bytes(self):
        row = self.purchase_complete()
        self.assertEqual(self.reconcile(row), 0, self.err)
        self.assertEqual(self.request_row()["actual"], 5)
        self.assertEqual(self.request_row()["sha256"], row["sha256"])
        self.audio_calls.assert_not_called()

    def test_reconcile_requires_the_manifest_before_any_network(self):
        with patch.object(cli, "_get_json") as metadata:
            code = self.invoke("reconcile", "--namespace", "n", "--cache-key", "k", "--cache-workspace", WORKSPACE, "--history-id", HISTORY)
        self.assertEqual(code, 2)
        metadata.assert_not_called()

    def test_provider_mismatch_or_unknown_billing_retains_the_maximum(self):
        row = self.purchase_lost_after_receipt()
        for change in ({"request_id": "wrong"}, {"history_item_id": "wrong"},
                       {"character_count_change_to": None}, {"character_count_change_to": -1}):
            with self.subTest(change=change):
                self.assertEqual(self.reconcile(row, history={**GOOD_HISTORY, **change}), 2)
                self.audio_calls.assert_not_called()
                self.assertEqual(self.committed(), 100)

    def test_a_different_credential_or_workspace_never_reaches_the_provider(self):
        row = self.purchase_lost_after_receipt()
        with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "different-synthetic-credential"}):
            self.assertEqual(self.reconcile(row), 2)
        self.assertIn("namespace", self.err)
        self.history_calls.assert_not_called()

    def test_missing_accounting_fails_closed_and_is_never_recreated(self):
        row = self.purchase_lost_after_receipt()
        root = self.epochs / EPOCH
        for name in ("namespace-salt", "authorization.json"):
            missing = root / name
            original = missing.read_bytes()
            missing.unlink()
            try:
                self.assertEqual(self.reconcile(row), 2)
                self.assertIn("incomplete", self.err)
                self.assertFalse(missing.exists())
                self.history_calls.assert_not_called()
            finally:
                missing.write_bytes(original)

    def test_a_changed_manifest_fails_closed(self):
        row = self.purchase_lost_after_receipt()
        self.manifest.write_text(self.manifest.read_text() + " ")
        self.assertEqual(self.reconcile(row), 2)
        self.assertIn("mismatch", self.err)
        self.history_calls.assert_not_called()


class Accept(EpochCase):
    def gates(self, digest, passed=True):
        evidence = self.root / "evidence.txt"
        evidence.write_text("synthetic review evidence")
        record = {"pass": passed, "output_sha256": digest, "evidence_path": str(evidence),
                  "evidence_sha256": hashlib.sha256(evidence.read_bytes()).hexdigest(), "reviewer": "fixture-reviewer"}
        path = self.root / "gates.json"
        path.write_text(json.dumps({name: record for name in ("content", "pronunciation", "listening", "artifact")}))
        return path

    def accept(self, row, gates):
        return self.invoke("accept", "--authorization-manifest", str(self.manifest), "--namespace", row["namespace"],
                           "--cache-key", row["key"], "--cache-workspace", WORKSPACE, "--gates", str(gates))

    def test_passing_gates_accept_the_exact_epoch_bytes(self):
        row = self.purchase_complete()
        with self.paid() as provider:
            self.assertEqual(self.accept(row, self.gates(row["sha256"])), 0, self.err)
        provider.assert_not_called()
        self.assertEqual(json.loads(self.out), {"acceptance_state": "accepted", "output_sha256": row["sha256"]})
        self.assertEqual(self.request_row()["state"], "accepted")
        with self.paid() as post:
            self.assertEqual(self.speak("again.mp3"), 0, self.err)
        post.assert_not_called()
        self.assertEqual(json.loads((self.root / "again.mp3.provenance.json").read_text())["acceptance_state"], "accepted")

    def test_a_failed_or_wrong_bytes_gate_leaves_the_take_pending(self):
        row = self.purchase_complete()
        for gates in (self.gates(row["sha256"], passed=False), self.gates("0" * 64)):
            self.assertEqual(self.accept(row, gates), 2)
            self.assertEqual(self.request_row()["state"], "pending")

    def test_the_default_ledger_never_holds_epoch_speech(self):
        row = self.purchase_complete()
        default = content_runtime.Ledger(self.root / "default-ledger")
        with self.assertRaisesRegex(RuntimeError, "pending"):
            content_control.accept_manifest(default, row["namespace"], row["key"], self.gates(row["sha256"]))


def worker(root, number, text, known_folder="fixture"):
    """One independent CLI process: real ledger, stubbed provider. Purchases are counted in a file."""
    posts = pathlib.Path(root) / "posts.log"

    def provider(*_args, on_headers=None, **_kwargs):
        with posts.open("a") as handle:
            handle.write("post\n")
        time.sleep(.15)
        return AUDIO

    metadata = {"/user/subscription": {"status": "active", "character_count": 0, "character_limit": 100000, "can_extend_character_limit": False},
                f"/voices/{VOICE}": {"category": "professional", "fine_tuning": {"state": {"eleven_v4": "fine_tuned"}}},
                "/models": [{"model_id": "eleven_v4", "can_do_text_to_speech": True, "model_rates": {"character_cost_multiplier": 1}}]}
    argv = ["tts", "--voice-id", VOICE, "--model-id", "eleven_v4", "--text", text, "--output", str(pathlib.Path(root) / f"take-{number}.mp3"),
            "--cache-workspace", WORKSPACE, "--cache-revision", REVISION, *V4_SETTINGS,
            "--authorization-manifest", str(pathlib.Path(root) / "authorization.json"), "--max-credits", "1500"]
    known = content_runtime.local_app_data if known_folder == "real" else lambda: pathlib.Path(root) / "known-local-app-data"
    with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-credential"}), \
            patch.object(content_runtime, "running_on_windows", return_value=True), \
            patch.object(content_runtime, "runtime_pin", return_value=str(pathlib.Path(root) / "AgentHub/runtime")), \
            patch.object(content_runtime, "local_app_data", known), \
            patch.object(cli, "_request_full", side_effect=provider), \
            patch.object(cli, "_get_json", side_effect=lambda path: metadata[path]):
        return cli.main(argv)


class Processes(EpochCase):
    def workers(self, texts):
        processes = [subprocess.Popen([sys.executable, __file__, "worker", str(self.root), str(i), text],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                      creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)) for i, text in enumerate(texts)]
        codes = []
        for process in processes:
            _, err = process.communicate(timeout=60)
            codes.append((process.returncode, err.strip()))
        return codes

    def seed(self, texts):
        """Open the epoch once, so the workers race on purchases rather than on its initialization."""
        self.manifest = self.authorize(texts=(TEXT, *texts))
        with self.paid():
            self.assertEqual(self.speak("seed.mp3", max_credits="100"), 0, self.err)

    def posts(self):
        path = self.root / "posts.log"
        return len(path.read_text().splitlines()) if path.exists() else 0

    def test_eight_processes_purchase_once_and_return_identical_bytes(self):
        line = "A concurrent fixture line."
        self.seed((line,))
        codes = self.workers([line] * 8)
        self.assertTrue(all(code == 0 for code, _ in codes), codes)
        self.assertEqual(self.posts(), 1)
        self.assertEqual({path.read_bytes() for path in self.root.glob("take-*.mp3")}, {RAW})
        self.assertEqual(self.committed(), 1600)

    def test_eight_processes_cannot_oversubscribe_the_ceiling(self):
        lines = [f"Concurrent fixture line {n}." for n in range(8)]
        self.seed(lines)
        codes = self.workers(lines)
        self.assertEqual([code for code, _ in codes].count(0), 2, codes)
        self.assertEqual(self.posts(), 2)
        self.assertEqual(self.committed(), 3100)

    @unittest.skipUnless(ALIAS and ALIAS.exists(), "Needs the Windows python.exe alias; checked absent on this host")
    def test_both_launch_routes_buy_once_and_share_one_directory(self):
        # Under the scripts folder, not TEMP: TEMP can sit in LocalAppData, which the alias route virtualizes.
        folder = tempfile.TemporaryDirectory(dir=pathlib.Path(__file__).parent, prefix="launch-route-")
        self.addCleanup(folder.cleanup)
        line = "A launch route fixture line."
        with patch.object(self, "root", pathlib.Path(folder.name)):
            (self.root / "AgentHub/runtime/content-recovery-epochs").mkdir(parents=True)
            self.manifest = self.authorize(texts=(line,))
            codes = []
            for number, interpreter in enumerate((ALIAS, pathlib.Path(sys.executable))):
                # The alias launcher itself needs the real value; the real interpreter gets a decoy to prove it is not read.
                env = {**os.environ, "LOCALAPPDATA": str(ALIAS.parents[2] if interpreter == ALIAS else self.root / "decoy")}
                run = subprocess.run([str(interpreter), __file__, "worker", str(self.root), str(number), line, "real"], capture_output=True,
                                     text=True, env=env, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                codes.append((run.returncode, run.stderr.strip()[-300:]))
            self.assertEqual([code for code, _ in codes], [0, 0], codes)
            self.assertEqual(self.posts(), 1)
            self.assertEqual((self.root / "take-0.mp3").read_bytes(), (self.root / "take-1.mp3").read_bytes())
            self.assertFalse((self.root / "decoy").exists())

    def test_a_first_use_race_fails_closed_without_a_purchase_on_the_loser(self):
        line = "A first use fixture line."
        self.manifest = self.authorize(texts=(line,))
        codes = self.workers([line] * 4)
        self.assertGreaterEqual([code for code, _ in codes].count(0), 1, codes)
        self.assertEqual(self.posts(), 1, codes)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "worker":
        raise SystemExit(worker(*sys.argv[2:]))
    unittest.main()
