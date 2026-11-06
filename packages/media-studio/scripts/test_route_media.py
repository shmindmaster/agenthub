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

    def test_video_generation_is_frozen_so_nothing_usable(self):
        self.assertEqual(r.route(POLICY, ["video-generation"]), [])
        blocked = r.route(POLICY, ["video-generation"], include_blocked=True)
        self.assertTrue(blocked and all(l["status"] == "frozen" for l in blocked))
        self.assertEqual(r.main(["video-generation"]), 1)

    def test_abacare_credit_never_serves_a_personal_film(self):
        personal = [l["id"] for l in r.route(POLICY, ["image"], identity="mahumtech")]
        self.assertNotIn("runware-image", personal)
        self.assertIn("azure-image", personal)
        abacare = [l["id"] for l in r.route(POLICY, ["image"], identity="abacare")]
        self.assertIn("runware-image", abacare)

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
