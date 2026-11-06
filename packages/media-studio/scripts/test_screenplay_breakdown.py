"""Offline tests for the screenplay breakdown, budget and schedule."""
import json
from pathlib import Path
import tempfile
import unittest

import screenplay_breakdown as bd

SP = {"title": "T", "scenes": [
    {"id": "a", "narration": "Penske declined four trucks.", "speaker": "debbie"},
    {"id": "b", "narration": "We handle 37 percent of the volume in this building.", "speaker": "sarosh"}]}
PLAN = {"scenes": [
    {"id": "a", "visual": {"kind": "svg", "groups": []}},
    {"id": "b", "visual": {"kind": "chart", "form": "waffle", "items": []}}]}


class Breakdown(unittest.TestCase):
    def test_counts_cast_seconds_and_prices_speech_from_documented_rates(self):
        r = bd.summarize(SP, PLAN, wpm=150)
        self.assertTrue(r["ok"], r["errors"])
        self.assertEqual({c["speaker"] for c in r["cast"]}, {"debbie", "sarosh"})
        n = sum(len(s["narration"].encode()) for s in SP["scenes"])
        self.assertAlmostEqual(r["budget"]["speechUsd"], round(n * 15e-6, 4), places=4)

    def test_hd_voice_costs_more_than_standard(self):
        std = bd.summarize(SP, PLAN)["budget"]["speechUsd"]
        hd = bd.summarize(SP, PLAN, hd_voices=["debbie", "sarosh"])["budget"]["speechUsd"]
        self.assertGreater(hd, std)

    def test_a_scene_with_no_picture_is_an_error(self):
        r = bd.summarize(SP, {"scenes": [PLAN["scenes"][0]]})
        self.assertFalse(r["ok"])
        self.assertTrue(any("scene b has no picture" in e for e in r["errors"]))

    def test_a_generated_clip_is_routed_to_irukadark_and_counted_in_credits(self):
        plan = {"scenes": [{"id": "a", "visual": {"kind": "broll", "src": "clips/a.mp4"}},
                           {"id": "b", "visual": {"kind": "broll", "src": "clips/b.mp4", "seconds": 8}}]}
        r = bd.summarize(SP, plan)
        self.assertTrue(r["ok"], r["errors"])
        self.assertEqual({s["lane"] for s in r["scenes"]}, {"irukadark"})
        self.assertEqual([s["clips"] for s in r["scenes"]], [1, 2])
        self.assertEqual(r["budget"]["clips"], 3)
        self.assertEqual(r["budget"]["clipCredits"], 3 * 232)
        self.assertEqual(r["budget"]["pricedUsd"], round(r["budget"]["speechUsd"] + r["budget"]["transcriptionCheckUsd"], 4))

    def test_a_picture_with_no_usable_lane_is_an_error_not_a_guess(self):
        import route_media
        real = route_media.route
        route_media.route = lambda *a, **k: []
        try:
            r = bd.summarize(SP, {"scenes": [{"id": "a", "visual": {"kind": "broll", "src": "x.mp4"}}, PLAN["scenes"][1]]})
        finally:
            route_media.route = real
        self.assertFalse(r["ok"])
        self.assertTrue(any("video-generation" in e for e in r["errors"]))

    def test_stills_are_priced_from_the_image_quote_and_routed_to_a_ready_lane(self):
        plan = {"scenes": [{"id": "a", "visual": {"kind": "still", "src": "stills/a.png", "prompt": "Four trucks idling at a dock at dawn"}}, PLAN["scenes"][1]]}
        r = bd.summarize(SP, plan, identity="mahumtech")
        self.assertTrue(r["ok"], r["errors"])
        self.assertEqual(r["budget"]["stills"], 1)
        self.assertGreater(r["budget"]["stillsUsd"], 0)
        self.assertEqual(r["budget"]["unpriced"], [])
        self.assertEqual(r["scenes"][0]["lane"], "azure-image")
        self.assertAlmostEqual(r["budget"]["pricedUsd"], r["budget"]["speechUsd"] + r["budget"]["transcriptionCheckUsd"] + r["budget"]["stillsUsd"], places=3)
        self.assertEqual(r["assets"], [{"kind": "still", "src": "stills/a.png"}])

    def test_a_still_with_no_prompt_is_an_error(self):
        plan = {"scenes": [{"id": "a", "visual": {"kind": "still", "src": "stills/a.png"}}, PLAN["scenes"][1]]}
        r = bd.summarize(SP, plan, identity="mahumtech")
        self.assertFalse(r["ok"])
        self.assertTrue(any("still has no prompt" in e for e in r["errors"]))

    def test_schedule_runs_voice_in_parallel_with_a_limit(self):
        t2 = bd.summarize(SP, PLAN)["schedule"][1]
        self.assertTrue(t2["parallel"])
        self.assertEqual(t2["limit"], 5)

    def test_cli_writes_the_breakdown_and_exit_code_follows_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "story").mkdir()
            (root / "story/screenplay.json").write_text(json.dumps(SP), encoding="utf-8")
            (root / "story/picture-plan.json").write_text(json.dumps(PLAN), encoding="utf-8")
            self.assertEqual(bd.main([str(root)]), 0)
            self.assertTrue((root / "plan/breakdown.json").exists())
            (root / "story/picture-plan.json").write_text(json.dumps({"scenes": []}), encoding="utf-8")
            self.assertEqual(bd.main([str(root)]), 1)


if __name__ == "__main__":
    unittest.main()
