"""Synthetic, offline checks for spending and diagnostic boundaries."""
import base64
import contextlib
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

import elevenlabs_cli as cli
import governed_elevenlabs as governed
import os

# The content ledger refuses linked directories by design. Resolve the temp root once so
# fixtures stay valid when TMPDIR sits under a junction (e.g. %LOCALAPPDATA%\AgentHub).
tempfile.tempdir = os.path.realpath(tempfile.gettempdir())


class SpendingBoundaries(unittest.TestCase):
    def setUp(self):
        self.subscription = {"status": "active", "character_count": 10, "character_limit": 100}
        self.voice = {"category": "professional", "fine_tuning": {"state": {"ready": "fine_tuned"}}}
        self.model = {"model_id": "ready", "can_do_text_to_speech": True,
                      "model_rates": {"character_cost_multiplier": .5}}
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = pathlib.Path(folder.name)
        self.ledger = governed.new_ledger(self.root / "runtime")
        self.ledger.configure("elevenlabs/credits", 20)
        self.patch = patch.object(governed, "new_ledger", return_value=self.ledger)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.env = patch.dict(cli.os.environ, {"ELEVENLABS_API_KEY": "synthetic-credential"})
        self.env.start()
        self.addCleanup(self.env.stop)


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

    def test_v4_turbo_is_priced_from_live_inventory(self):
        self.voice = {"category": "premade"}
        self.model["model_id"] = "eleven_v4_turbo"
        self.assertEqual(self.check(model="eleven_v4_turbo")["estimated_credits"], 3)

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
                "--text", "hello", "--output", str(target),
                "--stability", "0.5", "--similarity-boost", "0.75", "--style", "0",
                "--speed", "1", "--use-speaker-boost", "--text-normalization", "auto",
                *([] if "--governed" in extra else ["--cache-workspace", "fixture-project", "--cache-revision", "locked-voice-model-v1"]), *extra]
        with patch.object(cli.sys, "argv", argv), patch.object(cli, "_get_json", side_effect=self.metadata), contextlib.redirect_stdout(io.StringIO()):
            return cli.main()

    def test_dry_run_never_posts_or_writes(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(cli, "_request_full") as post:
            target = pathlib.Path(folder)/"take.mp3"
            self.assertEqual(self.invoke(target, ["--dry-run"]), 0)
            self.assertFalse(target.exists())
            post.assert_not_called()

    def test_cli_exact_request_hash_preserves_parsed_numeric_types(self):
        captured = {}
        def intercept(_cli, args, voice_id, model_id, output_format, payload, with_timestamps=False):
            captured['request'] = governed.speech_request(args, voice_id, model_id, output_format, payload, with_timestamps)
            raise RuntimeError('Synthetic offline request capture')
        with patch.object(governed, 'generate', side_effect=intercept), \
                patch.object(cli, '_request_full') as post, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.invoke(self.root/'capture.mp3', ['--max-credits','10','--with-timestamps']), 2)
            post.assert_not_called()
        actual = captured['request']
        self.assertIs(type(actual['payload']['voice_settings']['style']), float)
        self.assertIs(type(actual['payload']['voice_settings']['speed']), float)
        expected = {**actual, 'payload':{**actual['payload'], 'voice_settings':{
            'stability':0.5, 'similarity_boost':0.75, 'style':0.0, 'speed':1.0, 'use_speaker_boost':True}}}
        self.assertEqual(governed.runtime_module().request_key(actual), governed.runtime_module().request_key(expected))
        integers = {**actual, 'payload':{**actual['payload'], 'voice_settings':{
            **actual['payload']['voice_settings'], 'style':0, 'speed':1}}}
        self.assertNotEqual(governed.runtime_module().request_key(actual), governed.runtime_module().request_key(integers))
        self.assertEqual(actual['endpoint'], 'with-timestamps')
        self.assertFalse((self.root/'capture.mp3').exists())

    def v4_invoke(self, extra):
        argv = ['cli', 'tts', '--voice-id', 'fixture', '--model-id', 'eleven_v4',
                '--text', 'hello', '--output', str(self.root/'v4.mp3'), '--max-credits', '10',
                '--cache-workspace', 'fixture', '--cache-revision', 'locked', *extra]
        with patch.object(cli.sys, 'argv', argv), patch.object(cli, '_get_json', side_effect=self.metadata), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cli.main()

    def test_v4_clone_strength_payload_is_exact_and_unsupported_controls_refused(self):
        self.voice["fine_tuning"]["state"]["eleven_v4"] = "fine_tuned"
        captured = {}
        def intercept(_cli, args, voice_id, model_id, output_format, payload, with_timestamps=False):
            captured.update(payload)
            raise RuntimeError('Synthetic offline capture')
        with patch.object(governed, 'generate', side_effect=intercept) as generate, patch.object(cli, '_request_full') as post:
            self.assertEqual(self.v4_invoke(['--clone-strength', '0', '--stability', '.5', '--similarity-boost', '.75']), 2)
            self.assertEqual(captured['voice_settings'], {'clone_strength': 0.0, 'stability': .5, 'similarity_boost': .75})
            self.assertIs(type(captured['voice_settings']['clone_strength']), float)
            self.assertEqual(captured['model_id'], 'eleven_v4')
            generate.reset_mock()
            for flags in (['--speed', '.88'], ['--style', '.15'], ['--use-speaker-boost'], ['--no-use-speaker-boost'],
                          ['--clone-strength', 'nan'], ['--clone-strength', '1.1'], ['--clone-strength', '-.1']):
                with self.subTest(flags=flags): self.assertEqual(self.v4_invoke(flags), 2)
            generate.assert_not_called(); post.assert_not_called()

    def test_v4_missing_professional_readiness_denies_before_post(self):
        with patch.object(cli, '_request_full') as post:
            self.assertEqual(self.v4_invoke(['--clone-strength', '0']), 2)
            post.assert_not_called()

    def test_clone_strength_nonprofessional_denied_before_reservation_or_post(self):
        self.model["model_id"] = "eleven_v4"
        for category in ("instant", "generated", "premade", None):
            self.voice = {"category": category, "fine_tuning": {"state": {"eleven_v4": "fine_tuned"}}}
            with self.subTest(category=category), patch.object(governed, "generate") as generate, patch.object(cli, "_request_full") as post:
                self.assertEqual(self.v4_invoke(["--clone-strength", "0"]), 2)
                generate.assert_not_called(); post.assert_not_called()

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

    def test_recovery_epoch_refuses_unknown_or_enabled_overages_before_post(self):
        self.ledger.recovery_epoch = "synthetic-authorized-epoch"
        for value in (None, True):
            self.subscription["can_extend_character_limit"] = value
            with patch.object(cli, "_request_full") as post, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.invoke(self.root / "blocked.mp3"), 2)
                post.assert_not_called()
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 0)

    def test_recovery_epoch_checks_live_allowance_before_post(self):
        self.ledger.recovery_epoch = "synthetic-authorized-epoch"
        self.subscription.update(can_extend_character_limit=False, character_limit=10)
        with patch.object(cli, "_request_full") as post, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.invoke(self.root / "blocked.mp3"), 2)
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


class GovernedRouting(unittest.TestCase):
    """Exercise the actual adapter with an isolated synthetic ledger and HTTP stub."""
    setUp = SpendingBoundaries.setUp
    invoke = SpendingBoundaries.invoke
    metadata = SpendingBoundaries.metadata

    def governed(self, target, revision="locked-voice-model-v1", extra=()):
        return self.invoke(target, ["--governed", "--cache-workspace", "fixture-project",
                                   "--cache-revision", revision, "--max-credits", "10", *extra])

    def test_missing_adapter_fails_without_provider_submission(self):
        import builtins
        original = builtins.__import__
        def guarded(name, *args, **kwargs):
            if name == "governed_elevenlabs":
                raise ImportError("synthetic private path")
            return original(name, *args, **kwargs)
        with patch("builtins.__import__", side_effect=guarded), patch.object(cli, "_request_full") as post, \
             contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(self.governed(self.root / "a.mp3"), 2)
            self.assertNotIn("synthetic private path", errors.getvalue())
            post.assert_not_called()

    def test_exact_repeat_reuses_pending_bytes_without_second_post(self):
        with patch.object(cli, "_request_full", return_value=(200, "audio/mpeg", b"synthetic audio", {"request-id": "fixture-request"})) as post:
            a, b = self.root / "a.mp3", self.root / "b.mp3"
            self.assertEqual(self.governed(a), 0)
            self.assertEqual(self.governed(b), 0)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            receipt = json.loads(b.with_suffix(".mp3.provenance.json").read_text())
            self.assertEqual(receipt["acceptance_state"], "pending")
            self.assertTrue(receipt["reused"])
            self.assertEqual(post.call_count, 1)
            self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def test_revision_change_invalidates_and_reserves_separately(self):
        with patch.object(cli, "_request_full", return_value=(200, "audio/mpeg", b"synthetic audio", {"request-id": "fixture-request"})) as post:
            self.assertEqual(self.governed(self.root / "a.mp3"), 0)
            self.assertEqual(self.governed(self.root / "b.mp3", "v2"), 0)
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.governed(self.root / "c.mp3", "v3"), 2)
            self.assertEqual(post.call_count, 2)

    def test_ambiguous_failure_never_retries_or_releases_budget(self):
        with patch.object(cli, "_request_full", side_effect=RuntimeError("synthetic lost response")) as post:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.governed(self.root / "a.mp3"), 2)
                self.assertEqual(self.governed(self.root / "b.mp3"), 2)
            self.assertEqual(post.call_count, 1)
            self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def timestamped(self, audio=b"synthetic audio"):
        alignment = {"characters": list("hi"), "character_start_times_seconds": [0.0, 0.1],
                     "character_end_times_seconds": [0.1, 0.2]}
        body = json.dumps({"audio_base64": base64.b64encode(audio).decode(), "alignment": alignment,
                           "normalized_alignment": alignment}).encode()
        return (200, "application/json", body, {"request-id": "fixture-request"})

    def test_timestamps_write_audio_alignment_and_bound_receipt(self):
        with patch.object(cli, "_request_full", return_value=self.timestamped()) as post:
            target = self.root / "a.mp3"
            self.assertEqual(self.governed(target, extra=["--with-timestamps"]), 0)
            self.assertIn("/text-to-speech/fixture/with-timestamps?output_format=", post.call_args.args[0])
            self.assertEqual(target.read_bytes(), b"synthetic audio")
            alignment_file = target.with_suffix(".mp3.alignment.json")
            alignment = json.loads(alignment_file.read_text())
            self.assertEqual(alignment["alignment"]["characters"], ["h", "i"])
            self.assertEqual(alignment["normalized_alignment"]["character_end_times_seconds"], [0.1, 0.2])
            receipt = json.loads(target.with_suffix(".mp3.provenance.json").read_text())
            self.assertEqual(receipt["output_sha256"], cli.hashlib.sha256(b"synthetic audio").hexdigest())
            self.assertEqual(receipt["alignment_sha256"], cli.hashlib.sha256(alignment_file.read_bytes()).hexdigest())
            self.assertEqual(receipt["ledger_asset_sha256"], cli.hashlib.sha256(self.timestamped()[2]).hexdigest())

    def test_timestamps_flag_is_part_of_the_cache_key(self):
        with patch.object(cli, "_request_full", return_value=(200, "audio/mpeg", b"synthetic audio", {"request-id": "plain"})):
            self.assertEqual(self.governed(self.root / "a.mp3"), 0)
        with patch.object(cli, "_request_full", return_value=self.timestamped()) as post:
            self.assertEqual(self.governed(self.root / "b.mp3", extra=["--with-timestamps"]), 0)
            self.assertEqual(self.governed(self.root / "c.mp3", extra=["--with-timestamps"]), 0)
            self.assertEqual(post.call_count, 1)
        self.assertTrue(self.root.joinpath("c.mp3.alignment.json").exists())
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 20)

    def test_existing_alignment_path_never_posts(self):
        self.root.joinpath("a.mp3.alignment.json").write_text("{}")
        with patch.object(cli, "_request_full") as post, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.governed(self.root / "a.mp3", extra=["--with-timestamps"]), 2)
            post.assert_not_called()

    def test_untimed_timestamp_response_retains_reservation(self):
        with patch.object(cli, "_request_full", return_value=(200, "audio/mpeg", b"synthetic audio", {"request-id": "fixture"})) as post:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.governed(self.root / "a.mp3", extra=["--with-timestamps"]), 2)
                self.assertEqual(self.governed(self.root / "b.mp3", extra=["--with-timestamps"]), 2)
            self.assertEqual(post.call_count, 1)
        self.assertFalse(self.root.joinpath("a.mp3").exists())
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def test_rate_limit_releases_reservation_and_allows_the_same_request_again(self):
        limited = cli.ProviderHTTPError("ElevenLabs API returned HTTP 429 (rate_limited)", 429)
        with patch.object(cli, "_request_full", side_effect=limited) as post, contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(self.governed(self.root / "a.mp3", extra=["--with-timestamps"]), 2)
        self.assertIn("reservation was released", errors.getvalue())
        self.assertEqual(post.call_count, 1)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 0)
        with patch.object(cli, "_request_full", return_value=self.timestamped()) as post:
            self.assertEqual(self.governed(self.root / "a.mp3", extra=["--with-timestamps"]), 0)
            self.assertEqual(post.call_count, 1)

    def test_other_http_errors_stay_unresolved(self):
        with patch.object(cli, "_request_full", side_effect=cli.ProviderHTTPError("ElevenLabs API returned HTTP 500", 500)) as post:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.governed(self.root / "a.mp3"), 2)
                self.assertEqual(self.governed(self.root / "b.mp3"), 2)
            self.assertEqual(post.call_count, 1)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 10)

    def test_unversioned_dictionary_and_missing_revision_never_post(self):
        with patch.object(cli, "_request_full") as post, contextlib.redirect_stderr(io.StringIO()):
            extra = ["--governed", "--cache-workspace", "fixture", "--max-credits", "10"]
            self.assertEqual(self.invoke(self.root / "a.mp3", extra), 2)
            self.assertEqual(self.invoke(self.root / "b.mp3", extra + ["--cache-revision", "v1", "--pronunciation-dictionary", "unversioned"]), 2)
            post.assert_not_called()


if __name__ == "__main__":
    unittest.main()
