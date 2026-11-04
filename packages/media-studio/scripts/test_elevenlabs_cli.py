"""Synthetic, offline checks for the owner-authorized speech adapter. No request ever leaves this process."""
import contextlib
import email.message
import hashlib
import io
import json
import os
import pathlib
import socket
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
import urllib.response
from types import SimpleNamespace
from unittest.mock import Mock, patch

# Whatever launched this test, the real provider credential is gone before the adapter loads.
os.environ.pop("ELEVENLABS_API_KEY", None)

import content_runtime
import elevenlabs_cli as cli
import governed_elevenlabs as governed

# The content ledger refuses linked directories by design. Resolve the temp root once so
# fixtures stay valid when TMPDIR sits under a junction (e.g. %LOCALAPPDATA%\AgentHub).
tempfile.tempdir = os.path.realpath(tempfile.gettempdir())

REAL_BUILD_OPENER = urllib.request.build_opener
REAL_PIN = content_runtime.runtime_pin
REAL_LOCAL_APP_DATA = content_runtime.local_app_data
VOICE = "fixture-professional-clone"
WORKSPACE = "fixture-film-workspace"
REVISION = "locked-voice-model-v1"
EPOCH = "elevenlabs-project-fixture"
TEXT = "A synthetic fixture line."
FORMAT = "mp3_44100_192"
# The wording recovery_epoch_ledger requires; the adapter never grants or changes it.
APPROVAL = "Approve 4,200 existing credits"
V4_SETTINGS = ("--stability", "0.5", "--similarity-boost", "0.75", "--text-normalization", "auto")
V2_SETTINGS = (*V4_SETTINGS, "--style", "0", "--speed", "1", "--use-speaker-boost")


def refuse_network(*_args, **_kwargs):
    raise AssertionError("A test attempted a network connection")


class RedirectingHop(urllib.request.HTTPHandler, urllib.request.HTTPSHandler):
    """The last hop of a real opener: no socket, every hop recorded, always a redirect to a plain http origin."""

    def __init__(self):
        super().__init__()
        self.seen = []

    def respond(self, request):
        self.seen.append((request.full_url, request.get_header("Xi-api-key")))
        headers = email.message.Message()
        headers["Location"] = "http://other-origin.invalid/fixture"
        reply = urllib.response.addinfourl(io.BytesIO(b"{}"), headers, request.full_url, 302)
        reply.msg = "Found"
        return reply

    http_open = https_open = respond


class OfflineCase(unittest.TestCase):
    """Private runtime root, no provider credential, and sockets that fail the test."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = pathlib.Path(folder.name)
        self.epochs = self.root / "AgentHub/runtime/content-recovery-epochs"
        self.epochs.mkdir(parents=True)
        for guard in (patch.object(socket.socket, "connect", refuse_network),
                      patch.object(socket, "create_connection", refuse_network),
                      patch.object(cli.urllib.request, "urlopen", refuse_network),
                      patch.object(cli.urllib.request, "build_opener", refuse_network),
                      patch.object(content_runtime, "runtime_pin", return_value=str(self.epochs.parent)),
                      patch.object(content_runtime, "local_app_data", return_value=self.root / "known-local-app-data"),
                      patch.object(content_runtime, "running_on_windows", return_value=True)):
            guard.start()
            self.addCleanup(guard.stop)
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ.pop("ELEVENLABS_VOICE_ID", None)

    def credential(self):
        guard = patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-credential"})
        guard.start()
        self.addCleanup(guard.stop)

    def invoke(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = cli.main(list(argv))
            except SystemExit as stop:
                code = stop.code
        self.out, self.err = out.getvalue(), err.getvalue()
        return code

    def tts(self, target, *extra, voice=VOICE, model="eleven_v4", workspace=WORKSPACE, text=TEXT, settings=V4_SETTINGS):
        return self.invoke("tts", "--voice-id", voice, "--model-id", model, "--text", text, "--output", str(target),
                           "--cache-workspace", workspace, "--cache-revision", REVISION, *settings, *extra)

    def quote(self, voice=VOICE, model="eleven_v4", workspace=WORKSPACE, text=TEXT, settings=V4_SETTINGS):
        code = self.invoke("quote", "--voice-id", voice, "--model-id", model, "--text", text,
                           "--cache-workspace", workspace, "--cache-revision", REVISION, *settings)
        self.assertEqual(code, 0, self.err)
        return json.loads(self.out)

    def authorize(self, texts=(TEXT,), voice=VOICE, workspace=WORKSPACE, model="eleven_v4", settings=V4_SETTINGS,
                  name="authorization.json", **changes):
        """An owner manifest built from offline `quote` output, as the owner would."""
        quotes = [self.quote(voice, model, workspace, text, settings) for text in texts]
        digests = [q["text_sha256"] for q in quotes]
        proof = {"kind": "elevenlabs-new-input-inventory", "enumerated_scopes": ["Synthetic fixture inventory"],
                 "new_text_sha256": digests, "historical_text_sha256": [], "ambiguous_text_sha256": []}
        inventory = self.root / ("inventory-" + name)
        inventory.write_text(json.dumps(proof))
        policy = {"kind": "elevenlabs-owner-authorized-project-epoch-v2", "epoch_id": EPOCH,
                  "maximum_credits": 4200, "owner_authorized_maximum_credits": 4200, "owner_authorization": APPROVAL,
                  "workspace": workspace, "historical_accounting": "UNKNOWN", "historical_requests": "FENCED",
                  "voice_id": voice, "model_id": model, "output_format": FORMAT, "request_revision": REVISION,
                  "pronunciation_locators_sha256": quotes[0]["pronunciation_locators_sha256"],
                  "allowed_text_sha256": digests,
                  "allowed_requests": [{"text_sha256": q["text_sha256"], "request_sha256": q["request_sha256"]} for q in quotes],
                  "inventory_proof": {"path": str(inventory), "sha256": hashlib.sha256(inventory.read_bytes()).hexdigest()},
                  **changes}
        manifest = self.root / name
        manifest.write_text(json.dumps(policy))
        return manifest

    def assert_nothing_happened(self):
        """No accounting was created: the refusal came before any ledger, reservation or request."""
        self.assertEqual(list(self.epochs.iterdir()), [])


class WithoutOwnerAuthorization(OfflineCase):
    def test_paid_call_refuses_before_any_network_or_ledger(self):
        with patch.object(cli, "_request_full") as provider:
            self.assertEqual(self.tts(self.root / "take.mp3", "--max-credits", "10"), 2)
        provider.assert_not_called()
        self.assertIn("owner authorization", self.err)
        self.assert_nothing_happened()

    def test_refusal_is_the_same_when_a_credential_is_present(self):
        self.credential()
        with patch.object(cli, "_request_full") as provider:
            self.assertEqual(self.tts(self.root / "take.mp3", "--max-credits", "10"), 2)
        provider.assert_not_called()
        self.assert_nothing_happened()

    def test_dry_run_also_refuses_before_any_network(self):
        self.credential()
        with patch.object(cli, "_get_json") as provider:
            self.assertEqual(self.tts(self.root / "take.mp3", "--dry-run"), 2)
        provider.assert_not_called()
        self.assert_nothing_happened()

    def test_an_owner_configured_default_budget_is_not_authorization(self):
        self.credential()
        ledger = content_runtime.Ledger(self.root / "default-ledger")
        ledger.configure("elevenlabs/credits", 1000)
        with patch.object(content_runtime, "default_root", return_value=ledger.root), \
                patch.object(cli, "_request_full") as provider:
            self.assertEqual(self.tts(self.root / "take.mp3", "--max-credits", "10"), 2)
        provider.assert_not_called()
        self.assertEqual(ledger.status()["budgets"][0]["committed"], 0)

    def test_a_missing_relative_or_linked_manifest_refuses(self):
        self.credential()
        real = self.authorize()
        with patch.object(cli, "_request_full") as provider:
            for manifest in (str(self.root / "absent.json"), "relative.json"):
                with self.subTest(manifest=manifest):
                    self.assertEqual(self.tts(self.root / "take.mp3", "--authorization-manifest", manifest,
                                              "--max-credits", "10"), 2)
            with patch.object(content_runtime, "linked_path", side_effect=lambda path: path == real):
                self.assertEqual(self.tts(self.root / "take.mp3", "--authorization-manifest", str(real),
                                          "--max-credits", "10"), 2)
        provider.assert_not_called()
        self.assert_nothing_happened()


class SpeechOnly(OfflineCase):
    def test_the_cli_implements_no_other_provider_surface(self):
        for command in ("sfx", "music", "transcribe", "voices", "models", "account", "health", "voice-status"):
            with self.subTest(command=command):
                self.assertEqual(self.invoke(command, "--text", "a", "--output", "b"), 2)
                self.assertIn("invalid choice", self.err)


class VoiceAllowlist(OfflineCase):
    def setUp(self):
        super().setUp()
        self.credential()

    def assert_refused(self, manifest, pattern, **call):
        with patch.object(cli, "_request_full") as provider, patch.object(cli, "_get_json") as metadata:
            for extra in (("--max-credits", "10"), ("--dry-run",)):
                with self.subTest(extra=extra):
                    self.assertEqual(self.tts(self.root / "take.mp3", "--authorization-manifest", str(manifest), *extra, **call), 2)
                    self.assertRegex(self.err, pattern)
        provider.assert_not_called()
        metadata.assert_not_called()
        self.assert_nothing_happened()

    def test_a_manifest_for_another_voice_refuses(self):
        self.assert_refused(self.authorize(voice="fixture-other-voice"), "exact voice")

    def test_a_manifest_for_another_job_workspace_refuses(self):
        self.assert_refused(self.authorize(workspace="fixture-other-workspace"), "exact voice")

    def test_a_manifest_naming_no_voice_refuses(self):
        self.assert_refused(self.authorize(voice_id=None), "exact voice")
        self.assert_refused(self.authorize(name="empty.json", voice_id=""), "exact voice", voice="")

    def test_a_manifest_pinning_another_model_refuses(self):
        self.assert_refused(self.authorize(model="eleven_multilingual_v2", settings=V2_SETTINGS), "different model")

    def test_epoch_kinds_that_pin_no_voice_never_authorize_speech(self):
        for kind in ("elevenlabs-owner-authorized-project-epoch-v1", None, "something-else"):
            with self.subTest(kind=kind):
                self.assert_refused(self.authorize(kind=kind), "project manifest")

    def test_a_non_object_manifest_refuses(self):
        manifest = self.root / "list.json"
        manifest.write_text("[]")
        self.assert_refused(manifest, "project manifest")

    def correction(self, parent, **changes):
        amendment = {"kind": governed.CORRECTION_KIND, "model_id": "eleven_v4",
                     "parent_authorization": {"path": str(parent), "sha256": hashlib.sha256(parent.read_bytes()).hexdigest()},
                     **changes}
        path = self.root / "correction.json"
        path.write_text(json.dumps(amendment))
        return path

    def test_a_correction_takes_voice_and_workspace_from_its_hash_bound_parent(self):
        parent = self.authorize(voice="fixture-other-voice")
        self.assert_refused(self.correction(parent), "exact voice")
        same = self.authorize(name="same.json")
        correction = self.correction(same)
        checked, policy = governed.authorized_policy(correction, VOICE, WORKSPACE, "eleven_v4")
        self.assertEqual((checked, policy["voice_id"]), (correction.read_bytes(), VOICE))

    def test_a_correction_whose_parent_changed_refuses(self):
        parent = self.authorize()
        path = self.correction(parent)
        parent.write_text(parent.read_text() + " ")
        self.assert_refused(path, "parent authorization hash")

    def test_a_correction_with_no_absolute_parent_refuses(self):
        path = self.root / "orphan.json"
        path.write_text(json.dumps({"kind": governed.CORRECTION_KIND, "model_id": "eleven_v4"}))
        self.assert_refused(path, "project manifest")


class ModelSettings(OfflineCase):
    def test_v4_payload_carries_only_stability_and_similarity(self):
        with patch.object(governed, "speech_request", wraps=governed.speech_request) as built:
            self.quote()
        payload = built.call_args.args[4]
        self.assertEqual(payload["voice_settings"], {"stability": 0.5, "similarity_boost": 0.75})
        self.assertEqual(payload["model_id"], "eleven_v4")

    def test_v4_refuses_style_speed_and_speaker_boost_before_anything_else(self):
        self.credential()
        manifest = self.authorize()
        for flags in (("--style", "0"), ("--speed", "1"), ("--use-speaker-boost",), ("--no-use-speaker-boost",)):
            with self.subTest(flags=flags), patch.object(cli, "_request_full") as provider, patch.object(cli, "_get_json") as metadata:
                self.assertEqual(self.tts(self.root / "take.mp3", "--authorization-manifest", str(manifest), "--max-credits", "10", *flags), 2)
                self.assertIn("v4", self.err)
                provider.assert_not_called()
                metadata.assert_not_called()
        self.assert_nothing_happened()

    def test_clone_strength_is_not_a_setting(self):
        self.assertEqual(self.tts(self.root / "take.mp3", "--clone-strength", "0"), 2)
        self.assertIn("unrecognized arguments", self.err)

    def test_other_models_need_every_setting_explicitly(self):
        for missing in ("--style", "--speed"):
            settings = list(V2_SETTINGS)
            index = settings.index(missing)
            del settings[index:index + 2]
            with self.subTest(missing=missing):
                self.assertEqual(self.invoke("quote", "--voice-id", VOICE, "--model-id", "eleven_multilingual_v2", "--text", TEXT,
                                             "--cache-workspace", WORKSPACE, "--cache-revision", REVISION, *settings), 2)
                self.assertIn("explicit voice settings", self.err)

    def test_missing_normalization_refuses(self):
        self.assertEqual(self.invoke("quote", "--voice-id", VOICE, "--model-id", "eleven_v4", "--text", TEXT,
                                     "--cache-workspace", WORKSPACE, "--cache-revision", REVISION,
                                     "--stability", "0.5", "--similarity-boost", "0.75"), 2)

    def test_unversioned_or_excess_dictionaries_refuse(self):
        manifest = self.authorize()
        for extra in (("--pronunciation-dictionary", "unversioned"),
                      tuple(flag for n in range(4) for flag in ("--pronunciation-dictionary", f"d{n}:v1"))):
            self.assertEqual(self.tts(self.root / "take.mp3", "--authorization-manifest", str(manifest), *extra), 2)
            self.assertIn("dictionar", self.err)

    def test_quote_is_offline_and_hashes_the_exact_request(self):
        result = self.quote()
        payload = {"text": TEXT, "model_id": "eleven_v4", "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
                   "apply_text_normalization": "auto"}
        request = {"provider": "elevenlabs/rest/v1", "voice_id": VOICE, "model_id": "eleven_v4", "output_format": FORMAT,
                   "revision": REVISION, "payload": payload, "quality_policy": "owner-voice-five-gates-v1"}
        self.assertEqual(result["request_sha256"], content_runtime.request_key(request))
        self.assertEqual(result["text_sha256"], hashlib.sha256(TEXT.encode()).hexdigest())
        self.assertEqual(result["pronunciation_locators_sha256"], content_runtime.request_key([]))
        self.assert_nothing_happened()


class Preflight(OfflineCase):
    def setUp(self):
        super().setUp()
        self.credential()
        self.subscription = {"status": "active", "character_count": 10, "character_limit": 100, "can_extend_character_limit": False}
        self.voice = {"category": "professional", "fine_tuning": {"state": {"eleven_v4": "fine_tuned"}}}
        self.model = {"model_id": "eleven_v4", "can_do_text_to_speech": True, "model_rates": {"character_cost_multiplier": .5}}

    def metadata(self, path):
        return {"/user/subscription": self.subscription, "/voices/" + VOICE: self.voice, "/models": [self.model]}[path]

    def check(self, model="eleven_v4", budget=10):
        with patch.object(cli, "_get_json", side_effect=self.metadata):
            return cli.tts_preflight(VOICE, model, "hello", budget)

    def test_estimate_rounds_up(self):
        self.assertEqual(self.check()["estimated_credits"], 3)

    def test_unready_clone_fails_before_model_or_post(self):
        self.voice["fine_tuning"]["state"]["eleven_v4"] = "training"
        with self.assertRaisesRegex(RuntimeError, "fine_tuned"):
            self.check()

    def test_a_clone_with_no_state_for_v4_is_not_ready(self):
        self.voice["fine_tuning"]["state"] = {"eleven_multilingual_v2": "fine_tuned"}
        with self.assertRaisesRegex(RuntimeError, "fine_tuned"):
            self.check()

    def test_unknown_rate_fails(self):
        self.model.pop("model_rates")
        with self.assertRaisesRegex(RuntimeError, "unknown"):
            self.check()

    def test_absent_model_fails(self):
        self.model["can_do_text_to_speech"] = False
        with self.assertRaisesRegex(RuntimeError, "model inventory"):
            self.check()

    def test_text_over_the_model_limit_fails(self):
        self.model["maximum_text_length_per_request"] = 3
        with self.assertRaisesRegex(RuntimeError, "request limit"):
            self.check()

    def test_quota_and_budget_fail(self):
        with self.assertRaisesRegex(RuntimeError, "max-credits"):
            self.check(budget=2)
        self.subscription["character_limit"] = 11
        with self.assertRaisesRegex(RuntimeError, "remaining quota"):
            self.check()

    def test_inactive_subscription_fails(self):
        self.subscription["status"] = "past_due"
        with self.assertRaisesRegex(RuntimeError, "active subscription"):
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

    def test_account_summary_carries_no_identity_or_keys(self):
        result = cli._account_summary({**self.subscription, "email": "private@example.invalid",
                                       "api_key": "synthetic-secret", "payment_method": "private"})
        self.assertNotIn("private", json.dumps(result))
        self.assertNotIn("secret", json.dumps(result))

    def test_http_errors_do_not_echo_private_text(self):
        body = io.BytesIO(json.dumps({"detail": {"status": "missing_permissions", "message": "private submitted text"}}).encode())
        error = urllib.error.HTTPError("https://example.invalid", 401, "private reason", {}, body)
        with patch.object(cli.urllib.request, "build_opener", return_value=SimpleNamespace(open=Mock(side_effect=error))):
            with self.assertRaisesRegex(RuntimeError, r"HTTP 401 \(missing_permissions\)") as caught:
                cli._request_full("/fixture")
        self.assertNotIn("private", str(caught.exception))

    def test_non_speech_posts_are_disabled_at_the_transport(self):
        for path in ("/sound-generation", "/music", "/speech-to-text", "/forced-alignment"):
            with self.subTest(path=path), patch.object(cli.urllib.request, "build_opener") as sent:
                with self.assertRaisesRegex(RuntimeError, "disabled"):
                    cli._request_full(path, method="POST", governed_submission=True)
                sent.assert_not_called()

    def test_ungoverned_speech_post_is_disabled_at_the_transport(self):
        with patch.object(cli.urllib.request, "build_opener") as sent, self.assertRaisesRegex(RuntimeError, "disabled"):
            cli._request_full("/text-to-speech/fixture", method="POST")
        sent.assert_not_called()

    def test_the_credential_never_follows_a_redirect(self):
        for call in ({"path": "/fixture"}, {"path": "/text-to-speech/fixture", "method": "POST", "governed_submission": True}):
            with self.subTest(call=call):
                hop = RedirectingHop()
                build = lambda *handlers: REAL_BUILD_OPENER(*handlers, hop)
                with patch.object(cli.urllib.request, "build_opener", build), \
                        self.assertRaisesRegex(cli.ProviderHTTPError, "HTTP 302"):
                    cli._request_full(**call)
                self.assertEqual([url for url, _ in hop.seen], [cli.BASE_URL + call["path"]])

    def test_dry_run_reads_metadata_and_writes_nothing(self):
        manifest = self.authorize()
        target = self.root / "take.mp3"
        with patch.object(cli, "_get_json", side_effect=self.metadata), patch.object(cli, "_request_full") as provider:
            self.assertEqual(self.tts(target, "--authorization-manifest", str(manifest), "--dry-run"), 0, self.err)
        provider.assert_not_called()
        self.assertTrue(json.loads(self.out)["dry_run"])
        self.assertEqual(json.loads(self.out)["estimated_credits"], 13)
        self.assertFalse(target.exists())
        self.assert_nothing_happened()


AUDIO = (200, "audio/mpeg", b"synthetic audio", {"request-id": "fixture-request"})


class PaidFixture(OfflineCase):
    """The real adapter and real ledger; only the two provider functions are stubbed."""

    def setUp(self):
        super().setUp()
        self.credential()
        self.subscription = {"status": "active", "character_count": 0, "character_limit": 5000, "can_extend_character_limit": False}
        self.voice = {"category": "professional", "fine_tuning": {"state": {"eleven_v4": "fine_tuned", "eleven_multilingual_v2": "fine_tuned"}}}
        self.models = [{"model_id": m, "can_do_text_to_speech": True, "model_rates": {"character_cost_multiplier": 1}}
                       for m in ("eleven_v4", "eleven_multilingual_v2")]
        guard = patch.object(cli, "_get_json", side_effect=self.metadata)
        self.metadata_calls = guard.start()
        self.addCleanup(guard.stop)

    def metadata(self, path):
        return {"/user/subscription": self.subscription, "/voices/" + VOICE: self.voice, "/models": self.models}[path]

    @property
    def ledger(self):
        return content_runtime.Ledger(self.epochs / EPOCH)

    def committed(self):
        return self.ledger.status()["budgets"][0]["committed"]

    def speak(self, name="a.mp3", manifest=None, max_credits="100", **call):
        return self.tts(self.root / name, "--authorization-manifest", str(manifest or self.manifest),
                        "--max-credits", max_credits, **call)

    def paid(self, provider=None, **patched):
        return patch.object(cli, "_request_full", **({"side_effect": provider} if provider else {"return_value": AUDIO}), **patched)


class StableRoot(PaidFixture):
    def test_the_environment_never_selects_the_ledger(self):
        with patch.dict(os.environ, {"LOCALAPPDATA": str(self.root / "elsewhere"), "HOME": str(self.root / "elsewhere")}):
            self.assertEqual(content_runtime.stable_epoch_parent(), self.epochs)

    def test_a_changed_localappdata_gets_no_fresh_accounting_for_a_fenced_request(self):
        self.manifest = self.authorize()
        with self.paid(RuntimeError("synthetic lost response")) as post:
            self.assertEqual(self.speak("a.mp3"), 2)
            other = self.root / "elsewhere"
            other.mkdir()
            with patch.dict(os.environ, {"LOCALAPPDATA": str(other)}):
                self.assertEqual(self.speak("b.mp3"), 2)
        self.assertIn("No repeat purchase", self.err)
        self.assertEqual(post.call_count, 1)
        self.assertEqual(list(other.iterdir()), [])

    def assert_refused_before_state(self, pattern):
        self.manifest = self.authorize()
        with self.paid() as post:
            self.assertEqual(self.speak(), 2)
        self.assertRegex(self.err, pattern)
        post.assert_not_called()
        self.assert_nothing_happened()

    def test_an_unset_pin_refuses_before_any_state(self):
        with patch.object(content_runtime, "runtime_pin", return_value=None):
            self.assert_refused_before_state("RuntimeRoot")

    def test_a_pin_inside_local_app_data_refuses_because_windows_virtualizes_it(self):
        inside = self.root / "known-local-app-data" / "AgentHub" / "runtime" / "content-recovery-epochs"
        inside.mkdir(parents=True)
        for pin in (str(inside.parent), str(inside.parent).upper()):
            with self.subTest(pin=pin), patch.object(content_runtime, "runtime_pin", return_value=pin):
                self.assert_refused_before_state("outside LocalAppData")

    def test_a_relative_absent_or_linked_pin_refuses(self):
        for pin in ("relative/runtime", str(self.root / "absent")):
            with self.subTest(pin=pin), patch.object(content_runtime, "runtime_pin", return_value=pin):
                self.assert_refused_before_state("RuntimeRoot")
        with patch.object(content_runtime, "linked_path", side_effect=lambda path: path == self.epochs.parent):
            self.assert_refused_before_state("RuntimeRoot")

    def test_the_pin_is_read_from_the_user_registry(self):
        opened = []

        class Key:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

        fake = SimpleNamespace(HKEY_CURRENT_USER="hkcu", OpenKey=lambda hive, name: opened.append((hive, name)) or Key(),
                               QueryValueEx=lambda _key, name: opened.append(name) or ("D:/pinned/runtime", 1))
        with patch.dict(sys.modules, {"winreg": fake}):
            self.assertEqual(REAL_PIN(), "D:/pinned/runtime")
        self.assertEqual(opened, [("hkcu", r"Software\AgentHub"), "RuntimeRoot"])

    def test_a_missing_registry_value_is_no_pin(self):
        def absent(*_args):
            raise FileNotFoundError

        with patch.dict(sys.modules, {"winreg": SimpleNamespace(HKEY_CURRENT_USER="hkcu", OpenKey=absent)}):
            self.assertIsNone(REAL_PIN())

    def test_posix_root_comes_from_the_account_not_home(self):
        account = SimpleNamespace(pw_dir=str(self.root / "account"))
        with patch.object(content_runtime, "running_on_windows", return_value=False), \
                patch.dict(sys.modules, {"pwd": SimpleNamespace(getpwuid=lambda _uid: account)}), \
                patch.object(content_runtime.os, "getuid", return_value=1000, create=True), \
                patch.dict(os.environ, {"HOME": str(self.root / "elsewhere")}):
            self.assertEqual(content_runtime.stable_epoch_parent(),
                             self.root / "account/.local/share/AgentHub/runtime/content-recovery-epochs")

    @unittest.skipUnless(os.name == "nt", "Windows known-folder API")
    def test_local_app_data_comes_from_the_known_folder_not_the_environment(self):
        with patch.dict(os.environ, {"LOCALAPPDATA": str(self.root / "elsewhere")}):
            found = REAL_LOCAL_APP_DATA()
        self.assertNotEqual(found, self.root / "elsewhere")
        self.assertTrue(found.is_dir())


class PaidSpeech(PaidFixture):
    def test_voice_never_comes_from_the_environment(self):
        manifest = self.authorize()
        with patch.dict(os.environ, {"ELEVENLABS_VOICE_ID": VOICE}), self.paid() as provider:
            code = self.invoke("tts", "--model-id", "eleven_v4", "--text", TEXT, "--output", str(self.root / "take.mp3"),
                               "--max-credits", "10", "--cache-workspace", WORKSPACE, "--cache-revision", REVISION,
                               *V4_SETTINGS, "--authorization-manifest", str(manifest))
        self.assertEqual(code, 2)
        self.assertIn("--voice-id", self.err)
        provider.assert_not_called()

    def test_the_receipt_is_bound_before_the_real_transport_reads_the_body(self):
        self.manifest = self.authorize()
        order, case = [], self
        headers = email.message.Message()
        headers["Content-Type"], headers["request-id"] = "audio/mpeg", "fixture-request"

        class Response:
            status = 200

            def __init__(self):
                self.headers = headers

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self):
                with case.ledger.connect() as con:
                    order.append(("body", con.execute("SELECT receipt FROM requests").fetchone()[0]))
                return AUDIO[2]

        class Opener:
            def open(self, request, timeout):
                order.append(("post", request.get_method(), timeout))
                return Response()

        with patch.object(cli.urllib.request, "build_opener", return_value=Opener()) as build:
            self.assertEqual(self.speak(), 0, self.err)
        self.assertEqual(order, [("post", "POST", 300), ("body", "fixture-request")])
        self.assertIsInstance(build.call_args.args[0], cli._NoRedirect)
        self.assertIsNone(build.call_args.args[0].redirect_request(None, None, 302, "", {}, "https://example.invalid"))

    def test_the_maximum_is_reserved_before_the_provider_is_called(self):
        self.manifest = self.authorize()
        seen = {}

        def provider(*_args, **_kwargs):
            with self.ledger.connect() as con:
                seen.update(dict(con.execute("SELECT state,maximum FROM requests").fetchone()))
            seen["committed"] = self.committed()
            return AUDIO

        with self.paid(provider) as post:
            self.assertEqual(self.speak(), 0, self.err)
        self.assertEqual(seen, {"state": "submitted", "maximum": 100, "committed": 100})
        self.assertEqual(post.call_count, 1)

    def test_the_posted_request_is_exactly_the_authorized_v4_body(self):
        self.manifest = self.authorize()
        with self.paid() as post:
            self.assertEqual(self.speak(), 0, self.err)
        path, sent = post.call_args.args[0], json.loads(post.call_args.kwargs["body"])
        self.assertEqual(path, f"/text-to-speech/{VOICE}?output_format={FORMAT}")
        self.assertEqual(sent, {"text": TEXT, "model_id": "eleven_v4", "apply_text_normalization": "auto",
                                "voice_settings": {"stability": 0.5, "similarity_boost": 0.75}})

    def test_the_v2_model_still_runs_with_its_own_settings(self):
        self.manifest = self.authorize(model="eleven_multilingual_v2", settings=V2_SETTINGS)
        with self.paid() as post:
            self.assertEqual(self.speak(model="eleven_multilingual_v2", settings=V2_SETTINGS), 0, self.err)
        self.assertEqual(json.loads(post.call_args.kwargs["body"])["voice_settings"],
                         {"stability": 0.5, "similarity_boost": 0.75, "style": 0.0, "speed": 1.0, "use_speaker_boost": True})

    def test_receipt_binds_bytes_and_serves_the_speech_caller(self):
        self.manifest = self.authorize()
        target = self.root / "a.mp3"
        with self.paid() as post:
            self.assertEqual(self.speak(), 0, self.err)
            result = json.loads(self.out)
            receipt = json.loads(target.with_suffix(".mp3.provenance.json").read_text())
            self.assertEqual(self.speak(), 2)
        self.assertEqual(post.call_count, 1)
        self.assertEqual(result, {"ok": True, "output": str(target), "acceptance_state": "pending", "reused": False})
        self.assertEqual(receipt["output_sha256"], hashlib.sha256(target.read_bytes()).hexdigest())
        self.assertEqual(receipt["request_id"], "fixture-request")
        self.assertEqual(receipt["maximum_reserved_credits"], 100)
        self.assertEqual(receipt["recovery_epoch"], EPOCH)
        self.assertEqual(receipt["voice_id"], VOICE)
        self.assertIsNone(receipt["actual_credits"])
        self.assertNotIn('"text":', json.dumps(receipt))

    def test_exact_repeat_reuses_pending_bytes_without_a_second_purchase(self):
        self.manifest = self.authorize()
        with self.paid() as post:
            self.assertEqual(self.speak("a.mp3"), 0, self.err)
            self.assertEqual(self.speak("b.mp3"), 0, self.err)
        self.assertEqual((self.root / "a.mp3").read_bytes(), (self.root / "b.mp3").read_bytes())
        self.assertTrue(json.loads((self.root / "b.mp3.provenance.json").read_text())["reused"])
        self.assertEqual(post.call_count, 1)
        self.assertEqual(self.committed(), 100)

    def test_text_outside_the_allowlist_refuses_before_any_reservation(self):
        self.manifest = self.authorize()
        with self.paid() as post:
            self.assertEqual(self.speak(text="A different sentence."), 2)
        post.assert_not_called()
        self.metadata_calls.assert_not_called()
        self.assert_nothing_happened()

    def test_a_changed_setting_is_a_different_unauthorized_request(self):
        self.manifest = self.authorize()
        changed = ("--stability", "0.6", "--similarity-boost", "0.75", "--text-normalization", "auto")
        with self.paid() as post:
            self.assertEqual(self.speak(settings=changed), 2)
        post.assert_not_called()
        self.assert_nothing_happened()

    def test_the_manifest_cannot_change_after_first_use(self):
        self.manifest = self.authorize(texts=(TEXT, "A second line."))
        with self.paid() as post:
            self.assertEqual(self.speak(), 0, self.err)
            self.manifest.write_text(self.manifest.read_text() + " ")
            self.assertEqual(self.speak("b.mp3", text="A second line."), 2)
        self.assertIn("immutable", self.err)
        self.assertEqual(post.call_count, 1)

    def test_a_reservation_over_the_epoch_ceiling_never_reaches_the_provider(self):
        self.manifest = self.authorize(texts=(TEXT, "A second line."))
        with self.paid() as post:
            self.assertEqual(self.speak(max_credits="4100"), 0, self.err)
            self.assertEqual(self.speak("b.mp3", max_credits="101", text="A second line."), 2)
        self.assertIn("ceiling", self.err)
        self.assertEqual(post.call_count, 1)
        self.assertEqual(self.committed(), 4100)

    def test_missing_or_fractional_budget_never_reserves_or_posts(self):
        self.manifest = self.authorize()
        with self.paid() as post:
            self.assertEqual(self.tts(self.root / "a.mp3", "--authorization-manifest", str(self.manifest)), 2)
            for value in ("10.5", "0", "-1", "nan", "inf"):
                with self.subTest(value=value):
                    self.assertEqual(self.speak(max_credits=value), 2)
        post.assert_not_called()
        self.metadata_calls.assert_not_called()

    def test_a_missing_credential_refuses_before_any_accounting(self):
        self.manifest = self.authorize()
        with patch.dict(os.environ), self.paid() as post:
            os.environ.pop("ELEVENLABS_API_KEY")
            self.assertEqual(self.speak(), 2)
        self.assertIn("credential", self.err)
        post.assert_not_called()
        self.assertFalse((self.epochs / EPOCH).exists())

    def test_ambiguous_failure_keeps_the_reservation_and_never_retries(self):
        self.manifest = self.authorize()
        with self.paid(RuntimeError("synthetic lost response")) as post:
            self.assertEqual(self.speak("a.mp3"), 2)
            self.assertIn("reservation retained", self.err)
            self.assertEqual(self.speak("b.mp3"), 2)
            self.assertIn("No repeat purchase", self.err)
        self.assertEqual(post.call_count, 1)
        self.assertEqual(self.committed(), 100)
        self.assertFalse((self.root / "a.mp3").exists())

    def test_rate_limit_keeps_the_reservation_like_every_other_failure(self):
        self.manifest = self.authorize()
        limited = cli.ProviderHTTPError("ElevenLabs API returned HTTP 429 (rate_limited)")
        with self.paid(limited) as post:
            self.assertEqual(self.speak("a.mp3"), 2)
            self.assertIn("HTTP 429", self.err)
            self.assertIn("reservation retained", self.err)
            self.assertEqual(self.speak("b.mp3"), 2)
        self.assertEqual(post.call_count, 1)
        self.assertEqual(self.committed(), 100)
        with self.ledger.connect() as con:
            self.assertEqual(con.execute("SELECT state FROM requests").fetchone()[0], "unknown")

    def test_the_failure_message_names_the_cache_key_to_report(self):
        self.manifest = self.authorize()
        with self.paid(RuntimeError("synthetic lost response")):
            self.assertEqual(self.speak(), 2)
        with self.ledger.connect() as con:
            key = con.execute("SELECT key FROM requests").fetchone()[0]
        self.assertIn(key, self.err)

    def test_a_response_with_no_audio_or_no_request_id_keeps_the_reservation(self):
        for name, response in (("empty", (200, "audio/mpeg", b"", {"request-id": "fixture-request"})),
                               ("json", (200, "application/json", b"{}", {"request-id": "fixture-request"})),
                               ("unbound", (200, "audio/mpeg", b"synthetic audio", {}))):
            with self.subTest(response=name):
                line = f"A synthetic {name} fixture line."
                self.manifest = self.authorize(texts=(line,), name=name + ".json", workspace=name, voice=VOICE, epoch_id=f"{EPOCH}-{name}")
                with patch.object(cli, "_request_full", return_value=response) as post:
                    self.assertEqual(self.speak(name + ".mp3", workspace=name, text=line), 2)
                self.assertEqual(post.call_count, 1)
                self.assertFalse((self.root / (name + ".mp3")).exists())

    def test_the_ledger_uses_the_bytes_the_gate_checked(self):
        self.manifest = self.authorize()
        checked = self.manifest.read_bytes()
        real_gate = governed.authorized_policy

        def gate_then_swap(*args):
            result = real_gate(*args)
            self.manifest.write_text(json.dumps({"epoch_id": "elevenlabs-swapped", "maximum_credits": 1000, "workspace": WORKSPACE,
                                                 "owner_authorization": "swapped", "historical_accounting": "UNKNOWN",
                                                 "historical_requests": "FENCED", "allowed_text_sha256": []}))
            return result

        with self.paid(), patch.object(governed, "authorized_policy", side_effect=gate_then_swap):
            self.assertEqual(self.speak(), 0, self.err)
        self.assertEqual((self.epochs / EPOCH / "authorization.json").read_bytes(), checked)
        self.assertEqual(sorted(path.name for path in self.epochs.iterdir()), [EPOCH])

    def test_preflight_failure_releases_only_a_never_submitted_reservation(self):
        self.manifest = self.authorize()
        self.voice["fine_tuning"]["state"]["eleven_v4"] = "training"
        with self.paid() as post:
            self.assertEqual(self.speak(), 2)
        self.assertIn("fine_tuned", self.err)
        post.assert_not_called()
        self.assertEqual(self.committed(), 0)

    def test_overages_must_be_provably_off_before_the_provider_is_called(self):
        self.manifest = self.authorize()
        for value in (None, True):
            with self.subTest(value=value), self.paid() as post:
                self.subscription["can_extend_character_limit"] = value
                self.assertEqual(self.speak(), 2)
                self.assertIn("overages disabled", self.err)
                post.assert_not_called()
        self.assertEqual(self.committed(), 0)

    def test_existing_output_or_receipt_never_posts(self):
        self.manifest = self.authorize()
        for existing in ("a.mp3", "a.mp3.provenance.json"):
            path = self.root / existing
            path.write_text("taken")
            with self.subTest(existing=existing), self.paid() as post:
                self.assertEqual(self.speak(), 2)
                post.assert_not_called()
            path.unlink()
        self.assert_nothing_happened()

    def test_unwritable_destination_never_posts(self):
        self.manifest = self.authorize()
        with self.paid() as post, patch.object(pathlib.Path, "open", side_effect=OSError("synthetic denied")):
            self.assertEqual(self.speak(), 2)
        post.assert_not_called()


if __name__ == "__main__":
    unittest.main()
