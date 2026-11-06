"""Offline tests for the picture-relevance gate."""
import json
from pathlib import Path
import tempfile
import unittest

import check_picture_relevance as gate

LINE = "Penske declined our request for four 26-foot box trucks, with pickup on November 19."
GOOD = {"id": "s4", "title": "Trucks", "kicker": "YOU", "bullets": [], "visual": {"kind": "table", "headers": ["Item", "Status"], "rows": [
    {"cells": ["Four 26-foot box trucks", "Penske declined"], "mark": "risk"}, {"cells": ["Pickup requested", "November 19"]}]}}
CARD_ONLY = {"id": "s4", "title": "Penske denial, plan", "kicker": "YOU", "bullets": []}
GENERIC = {"id": "s4", "title": "Trucks", "bullets": [], "visual": {"kind": "hero", "title": "Our plan", "sub": "going forward"}}


PHOTO = {"id": "s4", "title": "Declined", "bullets": [], "visual": {"kind": "still", "layout": "bleed", "focus": "center", "src": "stills/x/s4.png",
         "prompt": "Four empty 26-foot box trucks parked in a row outside a rental depot at dawn"}}
PHOTO_OFF_TOPIC = {"id": "s4", "title": "Declined", "bullets": [], "visual": {"kind": "still", "layout": "bleed", "focus": "center", "src": "stills/x/s4.png",
                   "prompt": "A calm mountain lake at sunrise with mist over the water"}}


class RelevanceTests(unittest.TestCase):
    def test_a_visual_built_from_the_line_passes(self):
        r = gate.judge_scene(GOOD, LINE)
        self.assertTrue(r["ok"], r)
        self.assertIn("penske", r["overlap"])
        self.assertIn("19", r["overlap"])

    def test_a_title_card_fails_even_when_the_title_names_the_topic(self):
        r = gate.judge_scene(CARD_ONLY, LINE)
        self.assertFalse(r["ok"])
        self.assertTrue(any("no visual body" in x for x in r["reasons"]))

    def test_a_generic_visual_with_no_shared_content_fails(self):
        self.assertFalse(gate.judge_scene(GENERIC, LINE)["ok"])

    def test_numbers_and_percent_signs_count(self):
        scene = {"id": "x", "visual": {"kind": "stat", "value": "37%", "label": "of the heavy bulk volume"}}
        r = gate.judge_scene(scene, "We handle more than 37 percent of the heavy bulk volume in this building.")
        self.assertTrue(r["ok"], r)

    def test_svg_counts_only_its_visible_text_not_tag_names(self):
        scene = {"id": "x", "visual": {"kind": "svg", "groups": [{"at": 0.5, "svg": '<rect width="10" fill="red"/><text x="1">Penske declined</text>'}]}}
        r = gate.judge_scene(scene, "Penske declined our request, then drew a line and a rect.")
        self.assertEqual(r["overlap"], ["declined", "penske"])
        only_shapes = {"id": "x", "visual": {"kind": "svg", "groups": [{"svg": '<rect width="10"/><line x1="0"/>'}]}}
        self.assertFalse(gate.judge_scene(only_shapes, "A rect and a line.")["ok"])

    def test_chart_labels_and_values_count(self):
        scene = {"id": "x", "visual": {"kind": "chart", "form": "bars", "unit": "%", "items": [{"label": "Heavy bulk volume", "value": 37}]}}
        self.assertTrue(gate.judge_scene(scene, "We handle 37 percent of the heavy bulk volume.")["ok"])

    def test_runs_on_a_picture_plan_and_a_screenplay_before_any_voice_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = Path(tmp) / "plan.json"
            sp = Path(tmp) / "screenplay.json"
            scene = {"id": "s4", "visual": {"kind": "svg", "groups": [{"at": "@declined", "svg": "<text>Penske declined</text>"}, {"at": "@November+0.2", "svg": "<text>November 19</text>"}]}}
            plan.write_text(json.dumps({"scenes": [scene]}), encoding="utf-8")
            sp.write_text(json.dumps({"scenes": [{"id": "s4", "narration": LINE}]}), encoding="utf-8")
            self.assertEqual(gate.main([str(plan), str(sp)]), 0)

    def test_whole_run_requires_every_line_to_have_a_scene(self):
        with tempfile.TemporaryDirectory() as tmp:
            props = Path(tmp) / "p.json"
            cues = Path(tmp) / "c.json"
            props.write_text(json.dumps({"scenes": [GOOD]}), encoding="utf-8")
            cues.write_text(json.dumps({"cues": [{"id": "s4", "text": LINE}, {"id": "s5", "text": "Another line."}]}), encoding="utf-8")
            self.assertEqual(gate.main([str(props), str(cues)]), 1)
            cues.write_text(json.dumps({"cues": [{"id": "s4", "text": LINE}]}), encoding="utf-8")
            self.assertEqual(gate.main([str(props), str(cues)]), 0)

    def test_a_photo_is_judged_by_its_prompt_against_the_line(self):
        r = gate.judge_scene(PHOTO, LINE)
        self.assertTrue(r["ok"], r)
        self.assertIn("trucks", r["overlap"])

    def test_a_photo_prompt_about_something_else_fails(self):
        self.assertFalse(gate.judge_scene(PHOTO_OFF_TOPIC, LINE)["ok"])

    def test_layout_and_lane_words_do_not_count_as_content(self):
        scene = {"id": "s1", "title": "t", "bullets": [], "visual": {"kind": "still", "layout": "bleed", "focus": "center", "lane": "azure-image",
                 "size": "1536x1024", "quality": "medium", "src": "bleed/center.png", "prompt": "A quiet harbour"}}
        self.assertEqual(gate.judge_scene(scene, "The bleed center azure image medium quality.")["overlap"], [])


if __name__ == "__main__":
    unittest.main()
