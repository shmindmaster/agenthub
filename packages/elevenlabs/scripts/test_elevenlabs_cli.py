"""Synthetic, offline checks for spending and diagnostic boundaries."""
import contextlib
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

import elevenlabs_cli as cli


class SpendingBoundaries(unittest.TestCase):
    def setUp(self):
        self.subscription = {"status": "active", "character_count": 10, "character_limit": 100}
        self.voice = {"category": "professional", "fine_tuning": {"state": {"ready": "fine_tuned"}}}
        self.model = {"model_id": "ready", "can_do_text_to_speech": True,
                      "model_rates": {"character_cost_multiplier": .5}}

    def metadata(self, path):
        return {"/user/subscription": self.subscription, "/voices/fixture": self.voice,
                "/models": [self.model]}[path]

    def check(self, model="ready", budget=10):
        with patch.object(cli, "_get_json", side_effect=self.metadata):
            return cli.tts_preflight("fixture", model, "hello", budget)

    def test_estimate_rounds_up(self):
        self.assertEqual(self.check()["estimated_credits"], 3)

    def test_unready_clone_fails_before_model_or_post(self):
        with self.assertRaisesRegex(RuntimeError, "fine_tuned"):
            self.check(model="newest")

    def test_unknown_rate_fails(self):
        self.model.pop("model_rates")
        with self.assertRaisesRegex(RuntimeError, "unknown"):
            self.check()

    def test_dialogue_only_model_never_calls_rest(self):
        with patch.object(cli, "_get_json") as get:
            with self.assertRaisesRegex(RuntimeError, "WebSocket"):
                cli.tts_preflight("fixture", "eleven_v4_turbo", "hello", 10)
            get.assert_not_called()

    def test_quota_and_budget_fail(self):
        with self.assertRaisesRegex(RuntimeError, "max-credits"):
            self.check(budget=2)
        self.subscription["character_limit"] = 11
        with self.assertRaisesRegex(RuntimeError, "remaining quota"):
            self.check()

    def test_unknown_balance_is_not_zero(self):
        self.assertIsNone(cli._account_summary({})["credits_remaining"])
        self.assertIsNone(cli._voice_summary({})["model_states"])

    def test_verification_blocks(self):
        self.voice["voice_verification"] = {"requires_verification": True}
        with self.assertRaisesRegex(RuntimeError, "verification"):
            self.check()

    def test_invalid_budget_blocks(self):
        for budget in (-1, 0, float("nan"), float("inf")):
            with self.assertRaisesRegex(RuntimeError, "positive finite"):
                self.check(budget=budget)

    def test_account_allowlist_excludes_identity_and_keys(self):
        result = cli._account_summary({**self.subscription, "email": "private@example.invalid",
                                      "api_key": "synthetic-secret", "payment_method": "private"})
        self.assertNotIn("private", json.dumps(result))
        self.assertNotIn("secret", json.dumps(result))

    def test_http_errors_do_not_echo_private_text(self):
        body = io.BytesIO(json.dumps({"detail": {"status": "missing_permissions",
                                                "message": "private submitted text"}}).encode())
        error = urllib.error.HTTPError("https://example.invalid", 401, "private reason", {}, body)
        with patch.dict(cli.os.environ, {"ELEVENLABS_API_KEY": "synthetic"}), patch.object(cli.urllib.request, "urlopen", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, r"HTTP 401 \(missing_permissions\)") as caught:
                cli._request_full("/fixture")
        self.assertNotIn("private", str(caught.exception))

    def invoke(self, target, extra=("--max-credits", "10")):
        argv = ["cli", "tts", "--voice-id", "fixture", "--model-id", "ready",
                "--text", "hello", "--output", str(target), *extra]
        with patch.object(cli.sys, "argv", argv), patch.object(cli, "_get_json", side_effect=self.metadata), contextlib.redirect_stdout(io.StringIO()):
            return cli.main()

    def test_dry_run_never_posts_or_writes(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(cli, "_request_full") as post:
            target = pathlib.Path(folder)/"take.mp3"
            self.assertEqual(self.invoke(target, ["--dry-run"]), 0)
            self.assertFalse(target.exists())
            post.assert_not_called()

    def test_render_receipt_binds_bytes(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(cli, "_request_full", return_value=(200, "audio/mpeg", b"synthetic audio", {"request-id": "fixture-request"})) as post:
            target = pathlib.Path(folder)/"take.mp3"
            self.assertEqual(self.invoke(target), 0)
            receipt = json.loads(target.with_suffix(".mp3.provenance.json").read_text())
            self.assertEqual(receipt["output_sha256"], cli.hashlib.sha256(target.read_bytes()).hexdigest())
            self.assertNotIn('"text":', json.dumps(receipt))
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.invoke(target), 2)
            self.assertEqual(post.call_count, 1)

    def test_missing_budget_never_posts(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(cli, "_request_full") as post:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.invoke(pathlib.Path(folder)/"take.mp3", []), 2)
            post.assert_not_called()

    def test_missing_explicit_model_never_posts(self):
        argv = ["cli", "tts", "--voice-id", "fixture", "--text", "hello",
                "--output", "unused.mp3", "--max-credits", "10"]
        with patch.dict(cli.os.environ, {}, clear=True), patch.object(cli.sys, "argv", argv), patch.object(cli, "_request_full") as post:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(cli.main(), 2)
            post.assert_not_called()

    def test_unwritable_destination_never_posts(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(cli, "_request_full") as post:
            target = pathlib.Path(folder)/"take.mp3"
            with patch.object(pathlib.Path, "mkdir", side_effect=OSError("synthetic denied")), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.invoke(target), 2)
            post.assert_not_called()

    def test_stitch_validation_precedes_network(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(cli, "_get_json") as get:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.invoke(pathlib.Path(folder)/"take.mp3", ["--previous-text", "hello", "--previous-request-id", "fixture"]), 2)
            get.assert_not_called()


if __name__ == "__main__":
    unittest.main()
