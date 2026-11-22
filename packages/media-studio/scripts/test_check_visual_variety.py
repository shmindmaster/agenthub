"""Offline tests for the words-only gate."""
import json
from pathlib import Path
import tempfile
import unittest

import check_visual_variety as gate


def scenes(*kinds):
    return [{"id": f"s{i}", "visual": ({"kind": k} if k else None)} for i, k in enumerate(kinds)]


class VarietyTests(unittest.TestCase):
    def test_a_mix_with_real_pictures_passes(self):
        r = gate.judge(scenes("flow", "stat", "chart", "checklist", "svg", "timeline"))
        self.assertTrue(r["ok"], r["reasons"])

    def test_a_deck_of_cards_fails_on_share_and_run(self):
        r = gate.judge(scenes("hero", "checklist", "quote", "cta", "checklist"))
        self.assertFalse(r["ok"])
        joined = " ".join(r["reasons"])
        self.assertIn("are pictures", joined)
        self.assertIn("three in a row", joined)

    def test_no_visual_counts_as_text(self):
        self.assertEqual(gate.classify({"id": "x"}), "text")

    def test_one_kind_cannot_fill_the_run(self):
        r = gate.judge(scenes("flow", "flow", "flow", "chart", "svg"))
        self.assertTrue(any("'flow' fills" in x for x in r["reasons"]))

    def test_the_fedex_picture_v2_shape_is_flagged(self):
        # 14 beats: 3 flow, 2 timeline, 4 checklist, then proof/stat/hero/table/split/cta and no drawing or capture
        kinds = ["proof", "timeline", "timeline", "split", "checklist", "stat", "hero", "table", "flow", "checklist", "flow", "checklist", "flow", "cta"]
        r = gate.judge(scenes(*kinds))
        self.assertFalse(r["ok"])

    def test_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "p.json"
            p.write_text(json.dumps({"scenes": scenes("flow", "chart")}), encoding="utf-8")
            self.assertEqual(gate.main([str(p)]), 0)
            p.write_text(json.dumps({"scenes": scenes("hero", "cta")}), encoding="utf-8")
            self.assertEqual(gate.main([str(p)]), 1)

    def test_same_source_in_different_picture_kinds_is_flagged(self):
        pictures = scenes("broll", "flow", "screen-in-context")
        pictures[0]["visual"]["src"] = "./takes/board.mp4"
        pictures[2]["visual"]["src"] = "takes/board.mp4?revision=2"
        r = gate.judge(pictures)
        self.assertFalse(r["ok"])
        self.assertIn("scene s2 reuses takes/board.mp4 from s0", r["reasons"][0])

    def test_recrops_need_a_reason_and_deliberate_callbacks_pass(self):
        pictures = scenes("still", "broll")
        pictures[0]["visual"].update(src="whole.jpg", sourceAssetId="approved-portrait")
        pictures[1]["visual"].update(src="crop.jpg", sourceAssetId="approved-portrait", reuseReason="   ")
        self.assertFalse(gate.judge(pictures)["ok"])
        pictures[1]["visual"]["reuseReason"] = "Return to the photograph to identify the person introduced earlier."
        self.assertTrue(gate.judge(pictures)["ok"])

    def test_asset_id_does_not_hide_a_repeated_path(self):
        pictures = scenes("still", "broll")
        pictures[0]["visual"].update(src="board.jpg", sourceAssetId="board")
        pictures[1]["visual"]["src"] = "board.jpg"
        self.assertIn("reuses board.jpg from s0", gate.judge(pictures)["reasons"][0])

    def test_planned_sources_are_detected_before_files_exist(self):
        pictures = scenes("still", "broll")
        for pic in pictures:
            pic["visual"]["sourceAssetId"] = "planned-portrait"
        self.assertIn("reuses planned-portrait from s0", gate.judge(pictures)["reasons"][0])


if __name__ == "__main__":
    unittest.main()
