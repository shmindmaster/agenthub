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

    def respond(self, raw, content_type="application/json", lost=False):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw) + (100 if lost else 0)))
        self.send_header("request-id", "fixture-request")
        self.end_headers()
        self.wfile.write(raw)
        self.close_connection = True

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with self.lock:
            type(self).posts += 1
        time.sleep(.15)
        self.respond(RAW, "audio/mpeg", payload["text"] == "lost")


def invoke(root, url, number, revision="v1", text="hello"):
    argv = ["cli", "tts", "--voice-id", "fixture", "--model-id", "fixture", "--text", text,
            "--output", str(root / f"take-{number}.mp3"), "--max-credits", "10",
            "--cache-workspace", "synthetic-project", "--cache-revision", revision,
            "--stability", ".5", "--similarity-boost", ".75", "--style", "0", "--speed", "1",
            "--use-speaker-boost", "--text-normalization", "auto"]
    with patch.object(cli, "BASE_URL", url), patch.object(cli.sys, "argv", argv), \
         patch.object(governed, "new_ledger", return_value=governed.runtime_module().Ledger(root / "runtime")), \
         patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture"}), \
         contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return cli.main()


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
        results = []
        for process in processes:
            out, err = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, err)
            results.append(json.loads(out))
        return results

    def test_eight_cli_processes_purchase_once_and_return_identical_bytes(self):
        results = self.workers()
        self.assertTrue(all(result == 0 for result in results))
        self.assertEqual(Handler.posts, 1)
        self.assertEqual(len({hashlib.sha256(path.read_bytes()).hexdigest() for path in self.root.glob("*.mp3")}), 1)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def test_eight_cli_processes_cannot_oversubscribe_cap(self):
        results = self.workers(distinct=True)
        self.assertEqual(results.count(0), 2)
        self.assertEqual(Handler.posts, 2)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 20)

    def test_lost_body_preserves_header_receipt_and_recovers_without_purchase(self):
        self.assertEqual(invoke(self.root, self.url, "lost", text="lost"), 2)
        self.assertEqual(invoke(self.root, self.url, "retry", text="lost"), 2)
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
        self.assertEqual(invoke(self.root, self.url, "recovered", text="lost"), 0)
        self.assertEqual(Handler.posts, 1)
        self.assertEqual((self.root / "take-recovered.mp3").read_bytes(), RAW)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 5)


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
        print(json.dumps(invoke(pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5])))
    elif len(sys.argv) > 1 and sys.argv[1] == "--benchmark":
        benchmark(pathlib.Path(sys.argv[2]))
    else:
        unittest.main()
