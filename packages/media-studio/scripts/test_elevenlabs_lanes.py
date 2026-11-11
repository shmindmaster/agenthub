"""Synthetic, offline checks for the owner-authorized dialogue, sfx and music lanes.

Same fixture discipline as test_elevenlabs_cli: no request ever leaves this process.
"""
import hashlib
import json
import pathlib
import re
from unittest.mock import patch

from test_elevenlabs_cli import AUDIO, FORMAT, REVISION, WORKSPACE
import test_elevenlabs_cli as fixtures
import content_runtime
import elevenlabs_cli as cli

VOICE_A, VOICE_B = "fixture-voice-a", "fixture-voice-b"
TURNS = ((VOICE_A, "A synthetic opening line."), (VOICE_B, "A synthetic reply."))
SFX_PROMPT = "synthetic rain on glass"
MUSIC_PROMPT = "synthetic dark synth loop"
PLAN = {"chunks": [{"text": "synthetic verse", "duration_ms": 30000, "positive_styles": ["ambient"]}]}
EPOCHS = {"dialogue": "elevenlabs-dialogue-fixture", "sfx": "elevenlabs-sfx-fixture", "music": "elevenlabs-music-fixture"}
KINDS = {"dialogue": "elevenlabs-owner-authorized-dialogue-epoch-v1",
         "sfx": "elevenlabs-owner-authorized-sfx-epoch-v1",
         "music": "elevenlabs-owner-authorized-music-epoch-v1"}
MODELS = {"dialogue": "eleven_v4", "sfx": "eleven_text_to_sound_v3", "music": "music_v2_5"}
LIMITS = {"dialogue": 4200, "sfx": 4000, "music": 9000}


class LaneArgv(fixtures.OfflineCase):
    def lane_argv(self, lane, *extra, turns=TURNS, prompt=None, plan=None, model=None):
        argv = ["--model-id", model or MODELS[lane], "--cache-workspace", WORKSPACE, "--cache-revision", REVISION]
        if lane == "dialogue":
            for voice, text in turns:
                argv += ["--turn", voice, text]
        elif lane == "sfx":
            argv += ["--prompt", prompt or SFX_PROMPT]
        else:
            if plan:
                argv += ["--composition-plan", str(plan)]
            else:
                argv += ["--prompt", prompt or MUSIC_PROMPT]
                if "--music-length-ms" not in extra:
                    argv += ["--music-length-ms", "30000"]
        return [*argv, *extra]

    def plan_file(self, plan=PLAN):
        path = self.root / "plan.json"
        path.write_text(json.dumps(plan))
        return path

    def lane_quote(self, lane, *flags, **kwargs):
        code = self.invoke(f"{lane}-quote", *self.lane_argv(lane, *flags, **kwargs))
        self.assertEqual(code, 0, self.err)
        return json.loads(self.out)


class LaneQuoting(LaneArgv):
    def test_quotes_are_offline_deterministic_and_carry_both_hashes(self):
        for lane in EPOCHS:
            with self.subTest(lane=lane):
                first, second = self.lane_quote(lane), self.lane_quote(lane)
                self.assertEqual(first, second)
                self.assertRegex(first["text_sha256"], r"^[0-9a-f]{64}$")
                self.assertRegex(first["request_sha256"], r"^[0-9a-f]{64}$")
                self.assertEqual(first["model_id"], MODELS[lane])
                self.assert_nothing_happened()

    def test_every_output_field_changes_the_request_hash(self):
        base = self.lane_quote("dialogue")
        changed = self.lane_quote("dialogue", turns=((VOICE_A, "A synthetic opening line."), (VOICE_B, "Changed.")))
        self.assertNotEqual(base["request_sha256"], changed["request_sha256"])
        seeded = self.lane_quote("dialogue", "--seed", "7")
        self.assertNotEqual(base["request_sha256"], seeded["request_sha256"])
        effected = self.lane_quote("dialogue", "--environment-id", "small_room", "--send-level", "0.5")
        self.assertNotEqual(base["request_sha256"], effected["request_sha256"])
        sfx = self.lane_quote("sfx")
        for flags in (("--duration-seconds", "4"), ("--prompt-influence", "0.5"), ("--loop",)):
            with self.subTest(flags=flags):
                self.assertNotEqual(sfx["request_sha256"], self.lane_quote("sfx", *flags)["request_sha256"])
        music = self.lane_quote("music", prompt=MUSIC_PROMPT)
        longer = self.lane_quote("music", "--music-length-ms", "60000", prompt=MUSIC_PROMPT)
        self.assertNotEqual(music["request_sha256"], longer["request_sha256"])
        self.assertNotEqual(music["request_sha256"],
                            self.lane_quote("music", prompt="another prompt")["request_sha256"])

    def test_dialogue_payload_limits_match_the_api(self):
        over = (VOICE_A, "x" * 2001)
        self.assertEqual(self.invoke("dialogue-quote", *self.lane_argv("dialogue", turns=(over,))), 2)
        self.assertIn("2000", self.err)
        many = tuple((f"voice-{n}", "hi") for n in range(11))
        self.assertEqual(self.invoke("dialogue-quote", *self.lane_argv("dialogue", turns=many)), 2)
        self.assertIn("10", self.err)
        self.assertEqual(self.invoke("dialogue-quote", "--model-id", "eleven_v4",
                                     "--cache-workspace", WORKSPACE, "--cache-revision", REVISION), 2)
        self.assertIn("turn", self.err)

    def test_effect_and_seed_ranges_refuse_offline(self):
        for flags, pattern in ((("--distance", "2"), "distance"), (("--send-level", "-0.1"), "send_level"),
                               (("--pan", "2"), "pan"), (("--seed", "-1"), "Seed")):
            with self.subTest(flags=flags):
                self.assertEqual(self.invoke("dialogue-quote", *self.lane_argv("dialogue", *flags)), 2)
                self.assertIn(pattern, self.err)

    def test_sfx_payload_limits_match_the_api(self):
        for flags, pattern in ((("--duration-seconds", "0.1"), "0.5 and 30"),
                               (("--duration-seconds", "31"), "0.5 and 30"),
                               (("--prompt-influence", "1.5"), "0 and 1")):
            with self.subTest(flags=flags):
                self.assertEqual(self.invoke("sfx-quote", *self.lane_argv("sfx", *flags)), 2)
                self.assertIn(pattern, self.err)

    def test_music_prompt_and_plan_are_exclusive(self):
        for extra, pattern in ((("--prompt", "x", "--composition-plan", "y"), "exactly one"),
                               (("--prompt", "x", "--seed", "1"), "seed"),
                               (("--prompt", "x", "--music-length-ms", "100"), "3000 and 600000"),
                               (("--prompt", "x", "--music-length-ms", "600001"), "3000 and 600000")):
            with self.subTest(extra=extra):
                argv = ["--model-id", "music_v2_5", "--cache-workspace", WORKSPACE,
                        "--cache-revision", REVISION, *extra]
                self.assertEqual(self.invoke("music-quote", *argv), 2)
                self.assertIn(pattern, self.err)

    def test_a_composition_plan_is_refused_so_music_stays_instrumental(self):
        lyrics = self.plan_file({"chunks": [{"text": "[Verse 1]\nWe close the case tonight", "duration_ms": 30000,
                                             "positive_styles": ["female lead vocal"], "negative_styles": []}]})
        for plan in (lyrics, self.plan_file()):
            with self.subTest(plan=plan):
                self.assertEqual(self.invoke("music-quote", *self.lane_argv("music", plan=plan)), 2)
                self.assertIn("Composition plans are refused", self.err)
                self.assertNotIn("request_sha256", self.out)


class LaneManifests(LaneArgv):
    def setUp(self):
        super().setUp()
        self.credential()
        self.subscription = {"status": "active", "character_count": 0, "character_limit": 50000,
                             "can_extend_character_limit": False}
        self.voices = {v: {"category": "premade"} for v in (VOICE_A, VOICE_B)}
        self.models = [{"model_id": m, "can_do_text_to_speech": True}
                       for m in ("eleven_v4", "eleven_text_to_sound_v3", "music_v2_5")]
        guard = patch.object(cli, "_get_json", side_effect=self.metadata)
        self.metadata_calls = guard.start()
        self.addCleanup(guard.stop)

    def metadata(self, path):
        if path == "/user/subscription":
            return self.subscription
        if path == "/models":
            return self.models
        return self.voices[path.rsplit("/", 1)[-1]]

    def authorize(self, lane, quotes=None, name="authorization.json", **changes):
        """An owner lane manifest built from offline lane-quote output, as the owner would."""
        quotes = quotes if quotes is not None else [self.lane_quote(lane)]
        digests = [q["text_sha256"] for q in quotes]
        proof = {"kind": "elevenlabs-new-input-inventory", "enumerated_scopes": ["Synthetic fixture inventory"],
                 "new_text_sha256": digests, "historical_text_sha256": [], "ambiguous_text_sha256": []}
        inventory = self.root / ("inventory-" + name)
        inventory.write_text(json.dumps(proof))
        ceiling = LIMITS[lane]
        policy = {"kind": KINDS[lane], "epoch_id": EPOCHS[lane],
                  "maximum_credits": ceiling, "owner_authorized_maximum_credits": ceiling,
                  "owner_authorization": f"Approve {ceiling:,} existing credits",
                  "workspace": WORKSPACE, "historical_accounting": "UNKNOWN", "historical_requests": "FENCED",
                  "model_id": MODELS[lane], "output_format": quotes[0]["output_format"],
                  "request_revision": REVISION,
                  "pronunciation_locators_sha256": quotes[0]["pronunciation_locators_sha256"],
                  "allowed_text_sha256": digests,
                  "allowed_requests": [{"text_sha256": q["text_sha256"], "request_sha256": q["request_sha256"]}
                                       for q in quotes],
                  "inventory_proof": {"path": str(inventory),
                                      "sha256": hashlib.sha256(inventory.read_bytes()).hexdigest()},
                  **changes}
        if lane == "dialogue":
            policy.setdefault("voice_ids", [VOICE_A, VOICE_B])
        manifest = self.root / name
        manifest.write_text(json.dumps(policy))
        return manifest

    def run_lane(self, lane, name="a.mp3", manifest=None, max_credits="500", flags=(), **kwargs):
        return self.invoke(lane, *self.lane_argv(lane, *flags, **kwargs), "--output", str(self.root / name),
                           "--authorization-manifest", str(manifest), "--max-credits", max_credits)

    def paid(self, provider=None):
        return patch.object(cli, "_request_full",
                            **({"side_effect": provider} if provider else {"return_value": AUDIO}))

    def committed(self, lane):
        ledger = content_runtime.Ledger(self.epochs / EPOCHS[lane])
        return ledger.status()["budgets"][0]["committed"]


class LaneGate(LaneManifests):
    """Every manifest or request failure refuses before any reservation or provider call."""

    def assert_refused(self, lane, pattern, manifest=None, **kwargs):
        manifest = manifest or self.authorize(lane)
        with self.paid() as post:
            self.assertEqual(self.run_lane(lane, manifest=manifest, **kwargs), 2)
        self.assertRegex(self.err, pattern)
        post.assert_not_called()
        self.assert_nothing_happened()

    def test_no_manifest_refuses_like_speech(self):
        for lane in EPOCHS:
            with self.subTest(lane=lane), self.paid() as post:
                self.assertEqual(self.invoke(lane, *self.lane_argv(lane), "--output",
                                             str(self.root / "a.mp3"), "--max-credits", "10"), 2)
                self.assertIn("owner authorization", self.err)
                post.assert_not_called()
        self.assert_nothing_happened()

    def test_wrong_kind_workspace_model_and_epoch_refuse(self):
        for lane in EPOCHS:
            with self.subTest(lane=lane, change="kind"):
                self.assert_refused(lane, "lane manifest",
                                    manifest=self.authorize(lane, kind="elevenlabs-owner-authorized-project-epoch-v2"))
            with self.subTest(lane=lane, change="workspace"):
                self.assert_refused(lane, "workspace",
                                    manifest=self.authorize(lane, workspace="other", name="w.json"))
            with self.subTest(lane=lane, change="model"):
                self.assert_refused(lane, "model",
                                    manifest=self.authorize(lane, model_id="eleven_flash_v2_5", name="m.json"))
            with self.subTest(lane=lane, change="epoch"):
                self.assert_refused(lane, "pinned request",
                                    manifest=self.authorize(lane, epoch_id="elevenlabs-other-epoch", name="e.json"))

    def test_an_undeclared_dialogue_voice_refuses(self):
        manifest = self.authorize("dialogue", voice_ids=[VOICE_A])
        self.assert_refused("dialogue", "voice", manifest=manifest)

    def test_voice_fields_on_voiceless_lanes_refuse(self):
        for lane in ("sfx", "music"):
            for field in ("voice_ids", "voice_id"):
                with self.subTest(lane=lane, field=field):
                    self.assert_refused(lane, "voice",
                                        manifest=self.authorize(lane, name=field + ".json", **{field: [VOICE_A] if field == "voice_ids" else VOICE_A}))

    def test_a_request_outside_the_allowlist_refuses(self):
        self.assert_refused("sfx", "allowlist", prompt="an unauthorized prompt")

    def test_an_unpinnable_request_change_refuses(self):
        manifest = self.authorize("dialogue")
        self.assert_refused("dialogue", "allowlist", manifest=manifest,
                            turns=((VOICE_A, "A synthetic opening line."), (VOICE_B, "Unlisted reply.")))

    def test_a_changed_manifest_is_immutable(self):
        for lane in EPOCHS:
            with self.subTest(lane=lane):
                manifest = self.authorize(lane)
                with self.paid() as post:
                    self.assertEqual(self.run_lane(lane, name=lane + "a.mp3", manifest=manifest), 0, self.err)
                    manifest.write_text(manifest.read_text() + " ")
                    self.assertEqual(self.run_lane(lane, name=lane + "b.mp3", manifest=manifest), 2)
                self.assertIn("immutable", self.err)
                self.assertEqual(post.call_count, 1)


class LanePaid(LaneManifests):
    """The real adapter and real ledger against the fake provider, per lane."""

    def test_dialogue_reserves_posts_exact_body_and_binds_receipt(self):
        manifest = self.authorize("dialogue", quotes=[self.lane_quote("dialogue", "--seed", "7")])
        seen = {}

        def provider(path, on_headers=None, **kwargs):
            with content_runtime.Ledger(self.epochs / EPOCHS["dialogue"]).connect() as con:
                seen["row"] = dict(con.execute("SELECT state,maximum FROM requests").fetchone())
            return AUDIO

        with self.paid(provider) as post:
            self.assertEqual(self.run_lane("dialogue", manifest=manifest, flags=("--seed", "7")), 0, self.err)
        self.assertEqual(seen["row"], {"state": "submitted", "maximum": 500})
        path, sent = post.call_args.args[0], json.loads(post.call_args.kwargs["body"])
        self.assertEqual(path, f"/text-to-dialogue?output_format={FORMAT}")
        self.assertEqual(sent, {"inputs": [{"text": t, "voice_id": v} for v, t in TURNS],
                                "model_id": "eleven_v4", "seed": 7})
        receipt = json.loads((self.root / "a.mp3.provenance.json").read_text())
        self.assertEqual(receipt["request_id"], "fixture-request")
        self.assertEqual(receipt["operation"], "text-to-dialogue")
        self.assertEqual(receipt["voice_ids"], [VOICE_A, VOICE_B])
        self.assertEqual(receipt["recovery_epoch"], EPOCHS["dialogue"])

    def test_sfx_and_music_post_exact_bodies(self):
        sfx_flags = ("--duration-seconds", "4", "--loop")
        music_flags = ("--music-length-ms", "60000")
        sfx = self.authorize("sfx", name="sfx.json", quotes=[self.lane_quote("sfx", *sfx_flags)])
        music = self.authorize("music", name="music.json",
                               quotes=[self.lane_quote("music", *music_flags, prompt=MUSIC_PROMPT)])
        with self.paid() as post:
            self.assertEqual(self.run_lane("sfx", manifest=sfx, flags=sfx_flags), 0, self.err)
        path, sent = post.call_args.args[0], json.loads(post.call_args.kwargs["body"])
        self.assertEqual(path, f"/sound-generation?output_format={FORMAT}")
        self.assertEqual(sent, {"text": SFX_PROMPT, "model_id": "eleven_text_to_sound_v3",
                                "duration_seconds": 4.0, "loop": True})
        with self.paid() as post:
            self.assertEqual(self.run_lane("music", name="b.mp3", manifest=music, max_credits="900",
                                           prompt=MUSIC_PROMPT, flags=music_flags), 0, self.err)
        path, sent = post.call_args.args[0], json.loads(post.call_args.kwargs["body"])
        self.assertEqual(path, "/music?output_format=auto")
        self.assertEqual(sent, {"model_id": "music_v2_5", "prompt": MUSIC_PROMPT,
                                "force_instrumental": True, "music_length_ms": 60000})

    def test_exact_repeat_reuses_pending_bytes_without_a_second_purchase(self):
        manifest = self.authorize("sfx")
        with self.paid() as post:
            self.assertEqual(self.run_lane("sfx", "a.mp3", manifest), 0, self.err)
            self.assertEqual(self.run_lane("sfx", "b.mp3", manifest), 0, self.err)
        self.assertEqual((self.root / "a.mp3").read_bytes(), (self.root / "b.mp3").read_bytes())
        self.assertTrue(json.loads((self.root / "b.mp3.provenance.json").read_text())["reused"])
        self.assertEqual(post.call_count, 1)
        self.assertEqual(self.committed("sfx"), 500)

    def test_failure_keeps_the_reservation_and_never_retries(self):
        for lane in EPOCHS:
            with self.subTest(lane=lane):
                manifest = self.authorize(lane, name=lane + ".json")
                with self.paid(RuntimeError("synthetic lost response")) as post:
                    self.assertEqual(self.run_lane(lane, manifest=manifest), 2)
                    self.assertIn("reservation retained", self.err)
                    self.assertEqual(self.run_lane(lane, name="b.mp3", manifest=manifest), 2)
                    self.assertIn("No repeat purchase", self.err)
                self.assertEqual(post.call_count, 1)
                self.assertEqual(self.committed(lane), 500)

    def test_lane_receipt_ids_bind_from_documented_headers(self):
        for header in ("request-id", "song-id", "history-item-id"):
            prompt = f"synthetic {header} loop"
            flags = ("--music-length-ms", "30000")
            with self.subTest(header=header):
                manifest = self.authorize("music", name=header + ".json",
                                          epoch_id=f"elevenlabs-music-{header}",
                                          quotes=[self.lane_quote("music", *flags, prompt=prompt)])
                audio = (200, "audio/mpeg", b"synthetic audio", {header: "fixture-receipt"})
                with patch.object(cli, "_request_full", return_value=audio):
                    self.assertEqual(self.run_lane("music", name=header + ".mp3", manifest=manifest,
                                                   flags=flags, prompt=prompt), 0, self.err)
                receipt = json.loads((self.root / (header + ".mp3.provenance.json")).read_text())
                self.assertEqual(receipt["request_id"], "fixture-receipt")

    def test_paid_audio_without_a_receipt_is_kept_unaccepted(self):
        flags = ("--music-length-ms", "30000")
        manifest = self.authorize("music", quotes=[self.lane_quote("music", *flags, prompt=MUSIC_PROMPT)])
        audio = (200, "audio/mpeg", b"synthetic unbound audio", {})
        with patch.object(cli, "_request_full", return_value=audio) as post:
            self.assertEqual(self.run_lane("music", manifest=manifest, flags=flags, prompt=MUSIC_PROMPT), 2)
        self.assertEqual(post.call_count, 1)
        self.assertIn("reservation retained", self.err)
        self.assertIn("Unbound audio kept", self.err)
        held = re.search(r"kept for inspection at (.+?) \(sha256", self.err).group(1)
        kept = list(pathlib.Path(held).glob("*.bin"))
        self.assertEqual([k.read_bytes() for k in kept], [b"synthetic unbound audio"])
        self.assertFalse((self.root / "a.mp3").exists())

    def test_a_lane_reservation_over_the_epoch_ceiling_never_posts(self):
        manifest = self.authorize("sfx", quotes=[self.lane_quote("sfx"),
                                                 self.lane_quote("sfx", prompt="a second prompt")])
        with self.paid() as post:
            self.assertEqual(self.run_lane("sfx", manifest=manifest, max_credits="3900"), 0, self.err)
            self.assertEqual(self.run_lane("sfx", "b.mp3", manifest, max_credits="3900",
                                           prompt="a second prompt"), 2)
        self.assertIn("ceiling", self.err)
        self.assertEqual(post.call_count, 1)
        self.assertEqual(self.committed("sfx"), 3900)

    def test_dry_run_checks_credits_and_writes_nothing(self):
        flags = ("--music-length-ms", "60000")
        manifest = self.authorize("music", quotes=[self.lane_quote("music", *flags, prompt=MUSIC_PROMPT)])
        with self.paid() as post:
            self.assertEqual(self.invoke("music", *self.lane_argv("music", *flags, prompt=MUSIC_PROMPT),
                                         "--output", str(self.root / "a.mp3"),
                                         "--authorization-manifest", str(manifest), "--dry-run"), 0, self.err)
        post.assert_not_called()
        result = json.loads(self.out)
        self.assertEqual((result["dry_run"], result["estimated_credits"]), (True, 900))
        self.assert_nothing_happened()


if __name__ == "__main__":
    unittest.main()
