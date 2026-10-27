"""Offline tests for governed sound-effect and music generation; a local fixture server, no paid calls."""
import contextlib
import http.server
import io
import json
import os
import pathlib
import tempfile
import threading
import unittest
from unittest.mock import patch

import elevenlabs_cli as cli
import governed_audio
import governed_elevenlabs as governed

# The content ledger refuses linked directories by design. Resolve the temp root once so
# fixtures stay valid when TMPDIR sits under a junction (e.g. %LOCALAPPDATA%\AgentHub).
tempfile.tempdir = os.path.realpath(tempfile.gettempdir())

RAW = b"synthetic sound fixture -- not a real effect or composition"


class Handler(http.server.BaseHTTPRequestHandler):
    posts = []
    spend = 0

    def log_message(self, *_):
        pass

    def respond(self, raw, content_type="application/json", headers=None):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/user/subscription":
            return self.respond(json.dumps({"status": "active", "character_count": type(self).spend,
                                            "character_limit": 100000}).encode())
        self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        type(self).posts.append((self.path, body))
        if self.path.startswith("/sound-generation"):
            type(self).spend += 40
            return self.respond(RAW, "audio/mpeg", {"request-id": "sfx-request"})
        if self.path.startswith("/music"):
            type(self).spend += 300
            return self.respond(RAW, "audio/mpeg", {"song-id": "song-1"})
        self.send_error(404)


class GovernedAudioTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = pathlib.Path(folder.name)
        self.ledger = governed.runtime_module().Ledger(self.root / "runtime")
        self.ledger.configure("elevenlabs/credits", 2000)
        Handler.posts = []
        Handler.spend = 0
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def run_cli(self, *argv):
        full = ["cli", *argv]
        with patch.object(cli, "BASE_URL", self.url), patch.object(cli.sys, "argv", full), \
             patch.object(governed, "new_ledger", return_value=self.ledger), \
             patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture"}), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cli.main()

    def sfx(self, name, text="soft click", seconds="1", maximum="250", revision="r1"):
        return self.run_cli("sfx", "--text", text, "--duration-seconds", seconds, "--output", str(self.root / name),
                            "--max-credits", maximum, "--cache-workspace", "synthetic-project", "--cache-revision", revision)

    def test_estimates_are_conservative_and_require_explicit_length(self):
        self.assertEqual(governed_audio.estimate_audio_credits("sound-generation", {"duration_seconds": 1}), 200)
        self.assertEqual(governed_audio.estimate_audio_credits("sound-generation", {"duration_seconds": 10}), 400)
        self.assertEqual(governed_audio.estimate_audio_credits("music", {"music_length_ms": 60000}), 1035)
        with self.assertRaises(RuntimeError):
            governed_audio.estimate_audio_credits("music", {})
        with self.assertRaises(RuntimeError):
            governed_audio.estimate_audio_credits("sound-generation", {"duration_seconds": True})

    def test_sfx_posts_once_binds_receipt_and_reuses_bytes(self):
        self.assertEqual(self.sfx("a.mp3"), 0)
        self.assertEqual(self.sfx("b.mp3"), 0)
        self.assertEqual(len(Handler.posts), 1)
        self.assertEqual(Handler.posts[0][0].split("?")[0], "/sound-generation")
        self.assertEqual((self.root / "b.mp3").read_bytes(), RAW)
        receipt = json.loads((self.root / "a.mp3.provenance.json").read_text())
        self.assertEqual(receipt["request_id"], "sfx-request")
        self.assertEqual(receipt["actual_credits"], 40)
        self.assertFalse(receipt["reused"])
        self.assertTrue(json.loads((self.root / "b.mp3.provenance.json").read_text())["reused"])

    def test_music_uses_song_id_and_instrumental_only(self):
        code = self.run_cli("music", "--prompt", "calm", "--length-ms", "20000", "--output", str(self.root / "m.mp3"),
                            "--max-credits", "400", "--cache-workspace", "synthetic-project", "--cache-revision", "r1")
        self.assertEqual(code, 0)
        path, body = Handler.posts[0]
        self.assertTrue(path.startswith("/music"))
        self.assertIs(body["force_instrumental"], True)
        self.assertEqual(json.loads((self.root / "m.mp3.provenance.json").read_text())["request_id"], "song-1")

    def test_budget_and_missing_controls_never_post(self):
        self.assertEqual(self.sfx("c.mp3", maximum="100"), 2)  # estimate 200 > 100
        self.assertEqual(self.run_cli("sfx", "--text", "x", "--duration-seconds", "1", "--output", str(self.root / "d.mp3"),
                                      "--max-credits", "250"), 2)  # no cache workspace/revision
        self.ledger.configure("elevenlabs/credits", 250)
        self.assertEqual(self.sfx("e.mp3", revision="a"), 0)
        self.assertEqual(self.sfx("f.mp3", revision="b"), 2)  # ceiling would be exceeded
        self.assertEqual(len(Handler.posts), 1)

    def test_other_post_routes_stay_disabled(self):
        with patch.object(cli, "BASE_URL", self.url), patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-fixture"}):
            with self.assertRaises(RuntimeError):
                cli._request_full("/voices/add", method="POST", body=b"{}", governed_submission=True)
            with self.assertRaises(RuntimeError):
                cli._request_full("/music", method="POST", body=b"{}")  # not flagged governed


if __name__ == "__main__":
    unittest.main()
