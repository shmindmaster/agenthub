"""Offline HTTP/process integration and synthetic latency benchmark; no paid calls."""
import contextlib
import hashlib
import http.server
import io
import json
import os
import pathlib
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import elevenlabs_cli as cli
import governed_elevenlabs as governed

# The content ledger refuses linked directories by design. Resolve the temp root once so
# fixtures stay valid when TMPDIR sits under a junction (e.g. %LOCALAPPDATA%\AgentHub).
tempfile.tempdir = os.path.realpath(tempfile.gettempdir())


RAW = b"synthetic exact content -- not an owner voice or listening-quality sample"


class Handler(http.server.BaseHTTPRequestHandler):
    posts = 0
    lock = threading.Lock()

    def log_message(self, *_):
        pass

    def do_GET(self):
        data = {"/user/subscription": {"status": "active", "character_count": 0, "character_limit": 10000},
                "/voices/fixture": {"category": "professional", "fine_tuning": {"state": {"fixture": "fine_tuned"}}},
                "/models": [{"model_id": "fixture", "can_do_text_to_speech": True,
                             "model_rates": {"character_cost_multiplier": 1}}]}
        if self.path.startswith("/history/"):
            if self.path.endswith("/audio"):
                return self.respond(RAW, "audio/mpeg")
            return self.respond(json.dumps({"request_id": "fixture-request", "history_item_id": "fixture-history",
                                            "character_count_change_from": 0, "character_count_change_to": 5}).encode())
        self.respond(json.dumps(data[self.path]).encode())

    def respond(self, raw, content_type="application/json", lost=False, status=200, receipt=True):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw) + (100 if lost else 0)))
        if receipt:
            self.send_header("request-id", "fixture-request")
        self.end_headers()
        self.wfile.write(raw)
        self.close_connection = True

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with self.lock:
            type(self).posts += 1
        time.sleep(.15)
        if payload["text"] == "http-error":
            return self.respond(b'{"detail":{"status":"fixture_error"}}', status=500)
        self.respond(RAW, "audio/mpeg", payload["text"] == "lost", receipt=payload["text"] != "no-id")


def invoke(root, url, number, revision="v1", text="hello", errors=None):
    argv = ["cli", "tts", "--voice-id", "fixture", "--model-id", "fixture", "--text", text,
            "--output", str(root / f"take-{number}.mp3"), "--max-credits", "10",
            "--cache-workspace", "synthetic-project", "--cache-revision", revision,
            "--stability", ".5", "--similarity-boost", ".75", "--style", "0", "--speed", "1",
            "--use-speaker-boost", "--text-normalization", "auto"]
    stderr = io.StringIO()
    try:
        with patch.object(cli, "BASE_URL", url), patch.object(cli.sys, "argv", argv), \
             patch.object(governed, "new_ledger", return_value=governed.runtime_module().Ledger(root / "runtime")), \
             patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture"}), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            return cli.main()
    finally:
        if errors is not None:
            errors.append(stderr.getvalue())


class ProcessTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = pathlib.Path(folder.name)
        self.ledger = governed.new_ledger(self.root / "runtime")
        self.ledger.configure("elevenlabs/credits", 20)
        Handler.posts = 0
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def workers(self, distinct=False):
        processes = [subprocess.Popen([sys.executable, __file__, "worker", str(self.root), self.url, str(i),
                                       str(i) if distinct else "v1"], stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True,
                                      creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)) for i in range(8)]
        results, self.worker_errors = [], []
        for process in processes:
            out, err = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, err)
            reply = json.loads(out)
            results.append(reply["code"])
            self.worker_errors.append(reply["stderr"])
        return results

    def test_eight_cli_processes_purchase_once_and_return_identical_bytes(self):
        results = self.workers()
        self.assertTrue(all(result == 0 for result in results),
                        [(code, err) for code, err in zip(results, self.worker_errors) if code != 0])
        self.assertEqual(Handler.posts, 1)
        self.assertEqual(len({hashlib.sha256(path.read_bytes()).hexdigest() for path in self.root.glob("*.mp3")}), 1)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def test_eight_cli_processes_cannot_oversubscribe_cap(self):
        results = self.workers(distinct=True)
        self.assertEqual(results.count(0), 2)
        self.assertEqual(Handler.posts, 2)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 20)

    def test_lost_body_preserves_header_receipt_and_recovers_without_purchase(self):
        self.assert_recovery("lost")

    def test_http_error_preserves_header_receipt_and_recovers_without_purchase(self):
        self.assert_recovery("http-error")

    def test_missing_request_id_blocks_reuse_and_another_purchase(self):
        self.assertEqual(invoke(self.root, self.url, "missing", text="no-id"), 2)
        self.assertEqual(invoke(self.root, self.url, "retry", text="no-id"), 2)
        self.assertEqual(Handler.posts, 1)
        with self.ledger.connect() as con:
            row = dict(con.execute("SELECT * FROM requests").fetchone())
        self.assertEqual(row["state"], "unknown")
        self.assertIsNone(row["receipt"])
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def assert_recovery(self, text):
        self.assertEqual(invoke(self.root, self.url, "lost", text=text), 2)
        self.assertEqual(invoke(self.root, self.url, "retry", text=text), 2)
        self.assertEqual(Handler.posts, 1)
        with self.ledger.connect() as con:
            row = dict(con.execute("SELECT * FROM requests").fetchone())
        self.assertEqual(row["receipt"], "fixture-request")
        args = cli.argparse.Namespace(namespace=row["namespace"], cache_key=row["key"],
                                     cache_workspace="synthetic-project", history_id="fixture-history")
        with patch.object(cli, "BASE_URL", self.url), patch.object(governed, "new_ledger", return_value=self.ledger), \
             patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture"}), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(governed.reconcile(cli, args), 0)
            with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "different-synthetic-key"}):
                with self.assertRaisesRegex(RuntimeError, "namespace"):
                    governed.reconcile(cli, args)
        self.assertEqual(invoke(self.root, self.url, "recovered", text=text), 0)
        self.assertEqual(Handler.posts, 1)
        self.assertEqual((self.root / "take-recovered.mp3").read_bytes(), RAW)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 5)


class EpochReconciliationTests(unittest.TestCase):
    setUp = ProcessTests.setUp

    def epoch(self, state="unknown"):
        self.epoch_parent = self.root / "epochs"
        self.epoch_root = self.epoch_parent / "fixture-original"
        self.ledger = governed.new_ledger(self.epoch_root)
        self.ledger.configure("elevenlabs/credits", 20)
        namespace = self.ledger.namespace("synthetic-fixture", "synthetic-project")
        claim = self.ledger.claim(namespace, "fixture-key", "elevenlabs/credits", 10)
        self.ledger.submitted(claim)
        self.ledger.bind_receipt(claim, "fixture-request")
        if state == "pending":
            self.ledger.complete(claim, RAW, "audio/mpeg", "fixture-request")
        else:
            self.ledger.unknown(claim)
        policy = {"epoch_id": "fixture-original", "workspace": "synthetic-project",
                  "owner_authorization": "Synthetic existing authorization", "maximum_credits": 20,
                  "historical_accounting": "UNKNOWN", "historical_requests": "FENCED"}
        self.manifest = self.root / "original-authorization.json"
        self.manifest.write_text(json.dumps(policy))
        (self.epoch_root / "authorization.json").write_bytes(self.manifest.read_bytes())
        return cli.argparse.Namespace(namespace=namespace, cache_key="fixture-key", cache_workspace="synthetic-project",
                                      history_id="fixture-history", recovery_epoch_manifest=str(self.manifest))

    def reconcile(self, args):
        with patch.object(cli, "BASE_URL", self.url), \
             patch.object(governed, "reconciliation_epoch_parent", return_value=self.epoch_parent), \
             patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture"}), contextlib.redirect_stdout(io.StringIO()):
            return governed.reconcile(cli, args)

    def test_existing_epoch_recovers_without_purchase_or_primary_initialization(self):
        args = self.epoch()
        salt = (self.epoch_root / "namespace-salt").read_bytes()
        with patch.object(governed, "new_ledger", wraps=governed.new_ledger) as opened:
            self.assertEqual(self.reconcile(args), 0)
        opened.assert_called_once_with(self.epoch_root)
        self.assertEqual(Handler.posts, 0)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 5)
        self.assertEqual((self.epoch_root / "namespace-salt").read_bytes(), salt)
        row = self.ledger.lookup(args.namespace, args.cache_key)
        self.assertEqual(self.ledger.read_asset(row), RAW)
        self.assertEqual(row["state"], "pending")

    def test_pending_epoch_settlement_preserves_asset_and_authorization(self):
        args = self.epoch("pending")
        before = self.ledger.lookup(args.namespace, args.cache_key)
        authorization = (self.epoch_root / "authorization.json").read_bytes()
        self.assertEqual(self.reconcile(args), 0)
        after = self.ledger.lookup(args.namespace, args.cache_key)
        self.assertEqual(after["sha256"], before["sha256"])
        self.assertEqual(after["actual"], 5)
        self.assertEqual((self.epoch_root / "authorization.json").read_bytes(), authorization)
        self.assertEqual(Handler.posts, 0)

    def test_missing_original_files_fail_before_ledger_or_provider(self):
        args = self.epoch()
        for name in ("ledger.sqlite3", "namespace-salt", "authorization.json"):
            missing = self.epoch_root / name
            original = missing.read_bytes()
            missing.unlink()
            try:
                with patch.object(governed, "new_ledger") as opened, patch.object(cli, "_get_json") as provider:
                    with self.assertRaisesRegex(RuntimeError, "incomplete"):
                        self.reconcile(args)
                opened.assert_not_called()
                provider.assert_not_called()
                self.assertFalse(missing.exists())
            finally:
                missing.write_bytes(original)

    def test_authorization_salt_workspace_namespace_and_budget_mismatches_fail_closed(self):
        args = self.epoch()
        authorization = self.epoch_root / "authorization.json"
        salt = self.epoch_root / "namespace-salt"
        cases = [(authorization, b"{}"), (salt, b"partial"), (salt, b"z" * 32)]
        for path, replacement in cases:
            original = path.read_bytes()
            path.write_bytes(replacement)
            try:
                with patch.object(governed, "new_ledger") as opened, patch.object(cli, "_get_json") as provider:
                    with self.assertRaises(RuntimeError):
                        self.reconcile(args)
                opened.assert_not_called()
                provider.assert_not_called()
                self.assertEqual(path.read_bytes(), replacement)
            finally:
                path.write_bytes(original)
        for field in ("cache_workspace", "namespace", "cache_key"):
            bad = cli.argparse.Namespace(**{**vars(args), field: "incorrect"})
            with patch.object(cli, "_get_json") as provider:
                with self.assertRaises(RuntimeError):
                    self.reconcile(bad)
            provider.assert_not_called()
        self.ledger.configure("elevenlabs/credits", 21)
        with patch.object(cli, "_get_json") as provider:
            with self.assertRaisesRegex(RuntimeError, "ceiling"):
                self.reconcile(args)
        provider.assert_not_called()
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def test_provider_mismatch_or_unknown_billing_retains_maximum(self):
        args = self.epoch()
        good = {"request_id": "fixture-request", "history_item_id": "fixture-history",
                "character_count_change_from": 0, "character_count_change_to": 5}
        for change in ({"request_id": "wrong"}, {"history_item_id": "wrong"},
                       {"character_count_change_to": None}, {"character_count_change_to": -1}):
            with patch.object(cli, "_get_json", return_value={**good, **change}), patch.object(cli, "request") as audio:
                with self.assertRaises(RuntimeError):
                    self.reconcile(args)
            audio.assert_not_called()
            self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)
            self.assertIsNone(self.ledger.lookup(args.namespace, args.cache_key)["actual"])
        self.assertEqual(Handler.posts, 0)

    def test_missing_receipt_and_linked_accounting_fail_before_provider(self):
        args = self.epoch()
        runtime = governed.runtime_module()
        with patch.object(runtime, "linked_path", side_effect=lambda path: path == self.epoch_root / "ledger.sqlite3"), \
             patch.object(cli, "_get_json") as provider:
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                self.reconcile(args)
        provider.assert_not_called()
        with self.ledger.connect(True) as con:
            con.execute("UPDATE requests SET receipt=NULL")
        with patch.object(cli, "_get_json") as provider:
            with self.assertRaisesRegex(RuntimeError, "receipt-bound"):
                self.reconcile(args)
        provider.assert_not_called()
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def test_cli_routes_original_epoch_manifest(self):
        args = self.epoch()
        argv = ["cli", "reconcile", "--namespace", args.namespace, "--cache-key", args.cache_key,
                "--cache-workspace", args.cache_workspace, "--history-id", args.history_id,
                "--recovery-epoch-manifest", args.recovery_epoch_manifest,
                "--existing-epoch-parent", str(self.epoch_parent)]
        with patch.object(cli.sys, "argv", argv), patch.object(governed, "reconcile", return_value=0) as call:
            self.assertEqual(cli.main(), 0)
        self.assertEqual(call.call_args.args[1].recovery_epoch_manifest, str(self.manifest))
        self.assertEqual(call.call_args.args[1].existing_epoch_parent, str(self.epoch_parent))

    def test_explicit_original_parent_reconciles_without_default_root(self):
        args = self.epoch("pending")
        args.existing_epoch_parent = str(self.epoch_parent)
        salt = (self.epoch_root / "namespace-salt").read_bytes()
        with patch.object(cli, "BASE_URL", self.url), \
             patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture", "LOCALAPPDATA": str(self.root / "absent")}), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(governed.reconcile(cli, args), 0)
        self.assertEqual(self.ledger.lookup(args.namespace, args.cache_key)["actual"], 5)
        self.assertEqual((self.epoch_root / "namespace-salt").read_bytes(), salt)
        self.assertFalse((self.root / "absent").exists())
        self.assertEqual(Handler.posts, 0)

    def test_explicit_parent_requires_existing_absolute_unlinked_directory(self):
        args = self.epoch()
        runtime = governed.runtime_module()
        for parent in ("relative-epochs", str(self.root / "absent"), str(self.manifest)):
            args.existing_epoch_parent = parent
            with patch.object(governed, "new_ledger") as opened, patch.object(cli, "_get_json") as provider:
                with self.assertRaisesRegex(RuntimeError, "absolute existing unlinked"):
                    governed.reconcile(cli, args)
            opened.assert_not_called()
            provider.assert_not_called()
        self.assertFalse((self.root / "absent").exists())
        args.existing_epoch_parent = str(self.epoch_parent)
        for linked in (self.epoch_parent, self.root):
            with patch.object(runtime, "linked_path", side_effect=lambda path: path == linked), \
                 patch.object(governed, "new_ledger") as opened, patch.object(cli, "_get_json") as provider:
                with self.assertRaisesRegex(RuntimeError, "absolute existing unlinked"):
                    governed.reconcile(cli, args)
            opened.assert_not_called()
            provider.assert_not_called()

    def test_explicit_parent_without_authorization_never_opens_primary(self):
        args = self.epoch()
        args.recovery_epoch_manifest = None
        args.existing_epoch_parent = str(self.epoch_parent)
        with patch.object(governed, "new_ledger") as opened, patch.object(cli, "_get_json") as provider:
            with self.assertRaisesRegex(RuntimeError, "requires the original"):
                governed.reconcile(cli, args)
        opened.assert_not_called()
        provider.assert_not_called()


def benchmark(destination):
    fixture = ProcessTests()
    fixture.setUp()
    try:
        fixture.ledger.configure("elevenlabs/credits", 1000)
        samples = {"baseline_preflight_post_save_ms": [], "governed_cold_ms": [], "exact_reuse_ms": []}
        def baseline(i):
            start = time.perf_counter()
            with patch.object(cli, "BASE_URL", fixture.url), patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture"}):
                cli.tts_preflight("fixture", "fixture", "hello", 10)
                payload = {"text": "hello", "model_id": "fixture", "apply_text_normalization": "auto",
                           "voice_settings": {"stability": .5, "similarity_boost": .75, "style": 0,
                                              "speed": 1, "use_speaker_boost": True}}
                _, _, raw, _ = cli._request_full("/text-to-speech/fixture?output_format=mp3_44100_192", method="POST", body=json.dumps(payload).encode(), governed_submission=True)
                (fixture.root / f"baseline-{i}.mp3").write_bytes(raw)
                (fixture.root / f"baseline-{i}.json").write_text(json.dumps({"output_sha256": hashlib.sha256(raw).hexdigest()}))
            samples["baseline_preflight_post_save_ms"].append((time.perf_counter() - start) * 1000)

        for i in range(30):
            # Alternate paired order to avoid always giving one group a warm host.
            if i % 2 == 0:
                baseline(i)
            for name, number in (("governed_cold_ms", f"cold-{i}"), ("exact_reuse_ms", f"warm-{i}")):
                start = time.perf_counter()
                if invoke(fixture.root, fixture.url, number, revision=str(i)) != 0:
                    raise RuntimeError("Synthetic benchmark failed")
                samples[name].append((time.perf_counter() - start) * 1000)
                if (fixture.root / f"take-{number}.mp3").read_bytes() != RAW:
                    raise RuntimeError("Exact reuse changed bytes")
            if i % 2:
                baseline(i)
        def describe(values):
            return {"n": len(values), "p50_ms": round(statistics.median(values), 3),
                    "p95_ms": round(sorted(values)[28], 3)}
        result = {"synthetic_only": True, "upstream_fixture_delay_ms": 150,
                  "latency": {key: describe(value) for key, value in samples.items()},
                  "http_posts": Handler.posts, "repeat_requests": 30, "repeat_posts_avoided": 30,
                  "governed_workload_requests": 60, "governed_workload_posts": 30,
                  "byte_equality": True, "live_spend": 0,
                  "limits": "No acoustic quality test, provider performance or invoiced savings claim. 30 samples per group; alternating paired order; p95 nearest rank."}
        destination.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result))
    finally:
        fixture.doCleanups()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "worker":
        worker_errors = []
        code = invoke(pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5], errors=worker_errors)
        print(json.dumps({"code": code, "stderr": worker_errors[0][-2000:]}))
    elif len(sys.argv) > 1 and sys.argv[1] == "--benchmark":
        benchmark(pathlib.Path(sys.argv[2]))
    else:
        unittest.main()
