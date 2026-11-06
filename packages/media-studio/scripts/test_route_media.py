"""Offline tests for the media lane router and the shape of the routing policy."""
import unittest

import route_media as r

POLICY = r.load()
IDS = [l["id"] for l in POLICY["lanes"]]


class PolicyShape(unittest.TestCase):
    def test_ids_unique_and_statuses_known(self):
        self.assertEqual(len(IDS), len(set(IDS)))
        for l in POLICY["lanes"]:
            self.assertIn(l["status"], r.ORDER, l["id"])
            for k in ("needs", "cost", "identity", "how"):
                self.assertIn(k, l, l["id"])

    def test_no_secret_values_in_policy(self):
        text = open(r.POLICY, encoding="utf-8").read().lower()
        for bad in ("api_key=", "sk-", "bearer ", "password"):
            self.assertNotIn(bad, text)


class Routing(unittest.TestCase):
    def test_free_lane_beats_paid_for_a_diagram(self):
        lanes = r.route(POLICY, ["diagram"])
        self.assertTrue(lanes and r.is_free(lanes[0]))

    def test_video_generation_has_funded_lanes_led_by_irukadark_and_the_paid_ones_stay_frozen(self):
        usable = r.route(POLICY, ["video-generation"])
        self.assertEqual(usable[0]["id"], "irukadark")
        self.assertEqual({l["id"] for l in usable}, {"irukadark", "runware-video", "manus-browser"})
        self.assertTrue(all(l["status"] == "conditional" for l in usable))
        self.assertEqual(usable[0]["creditsPerClip"], 232)
        frozen = {l["id"] for l in r.route(POLICY, ["video-generation"], include_blocked=True) if l["status"] == "frozen"}
        self.assertEqual(frozen, {"higgsfield", "runway", "google-vertex"})
        self.assertEqual(r.main(["video-generation"]), 0)

    def test_every_lane_has_a_known_mode_and_the_catalog_lists_every_lane(self):
        for l in POLICY["lanes"]:
            self.assertIn(r.mode_of(l), r.MODES, l["id"])
        text = r.catalog(POLICY)
        for l in POLICY["lanes"]:
            self.assertIn(f"### {l['id']}  [{l['status']}, {r.mode_of(l)}", text)
        self.assertEqual(r.mode_of(next(l for l in POLICY["lanes"] if l["id"] == "irukadark")), "browser")
        self.assertIn("Frozen, skipped or disabled", text)
        self.assertEqual(r.main(["--catalog"]), 0)

    def test_frozen_music_and_sfx_is_listed_with_what_unfreezes_it(self):
        lane = next(l for l in POLICY["lanes"] if l["id"] == "elevenlabs-music-sfx")
        self.assertEqual(lane["status"], "frozen")
        self.assertIn("lifts that rule", lane["notes"])
        self.assertEqual(r.route(POLICY, ["music"]), [])

    def test_irukadark_is_by_hand_and_never_outranks_the_scripted_image_lanes(self):
        lane = next(l for l in POLICY["lanes"] if l["id"] == "irukadark")
        self.assertIn("Chrome", lane["how"])
        self.assertIn("irukadark.com/ai/video", lane["how"])
        for identity in ("mahumtech", "abacare", "any"):
            self.assertNotEqual(r.route(POLICY, ["image"], identity=identity)[0]["id"], "irukadark")
        self.assertEqual(r.route(POLICY, ["image"], identity="mahumtech")[0]["id"], "azure-image")

    def test_images_have_two_ready_lanes_and_azure_leads(self):
        for identity in ("mahumtech", "abacare", "any"):
            lanes = [l["id"] for l in r.route(POLICY, ["image"], identity=identity)]
            self.assertIn("runware-image", lanes, identity)
        mahumtech = r.route(POLICY, ["image"], identity="mahumtech")
        self.assertEqual(mahumtech[0]["id"], "azure-image")
        self.assertEqual(mahumtech[0]["status"], "ready")
        self.assertEqual(next(l for l in POLICY["lanes"] if l["id"] == "runware-image")["status"], "ready")

    def test_a_lane_tied_to_another_identity_is_not_offered(self):
        stt = [l["id"] for l in r.route(POLICY, ["word-clock"], identity="mahumtech")]
        self.assertNotIn("assemblyai-stt", stt)
        self.assertIn("assemblyai-stt", [l["id"] for l in r.route(POLICY, ["word-clock"], identity="abacare")])

    def test_voice_has_no_desktop_or_free_lane(self):
        usable = [l["id"] for l in r.route(POLICY, ["voice"])]
        self.assertEqual(usable, ["azure-speech", "elevenlabs-speech"])
        self.assertTrue(all(not r.is_free(l) for l in r.route(POLICY, ["narration"])))
        desk = next(l for l in r.route(POLICY, ["voice"], include_blocked=True) if l["id"] == "windows-narrator")
        self.assertEqual(desk["status"], "disabled")
        self.assertNotIn("windows-narrator", usable)
        rules = " ".join(POLICY["rules"])
        self.assertIn("Voice has no free lane", rules)
        self.assertIn("Windows Narrator", rules)
        self.assertIn("silent", rules)

    def test_image_generation_video_lanes_stay_frozen(self):
        for lane_id in ("higgsfield", "runway"):
            self.assertEqual(next(l for l in POLICY["lanes"] if l["id"] == lane_id)["status"], "frozen")

    def test_ready_before_conditional_and_azure_speech_first_for_voice(self):
        lanes = r.route(POLICY, ["voice"])
        self.assertEqual(lanes[0]["id"], "azure-speech")

    def test_local_ai_and_webreel_are_never_picked(self):
        self.assertEqual(r.route(POLICY, ["local-model"]), [])
        self.assertEqual(r.route(POLICY, ["quick-gif"]), [])

    def test_notebooklm_is_draft_only(self):
        lane = next(l for l in POLICY["lanes"] if l["id"] == "notebooklm-draft")
        self.assertTrue(lane.get("draftOnly"))


if __name__ == "__main__":
    unittest.main()
