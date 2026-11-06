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

    def test_a_frozen_lane_is_an_error_not_a_guess(self):
        plan = {"scenes": [{"id": "a", "visual": {"kind": "broll", "src": "x.mp4"}}, PLAN["scenes"][1]]}
        r = bd.summarize(SP, plan)
        self.assertFalse(r["ok"])
        self.assertTrue(any("video-generation" in e for e in r["errors"]))

    def test_stills_are_counted_and_left_unpriced(self):
        plan = {"scenes": [{"id": "a", "visual": {"kind": "still", "src": "stills/a.png"}}, PLAN["scenes"][1]]}
        r = bd.summarize(SP, plan, identity="mahumtech")
        self.assertEqual(r["budget"]["unpriced"][0]["count"], 1)
        self.assertEqual(r["assets"], [{"kind": "still", "src": "stills/a.png"}])

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
