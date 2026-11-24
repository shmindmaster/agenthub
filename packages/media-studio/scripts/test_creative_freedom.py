import json
import tempfile
import unittest
from pathlib import Path

from production_status import check_develop, check_pre, approve
from check_picture_relevance import judge_scene
from check_visual_variety import judge


class CreativeFreedomTests(unittest.TestCase):
    def test_internal_delegation_does_not_require_owner_stamps(self):
        with tempfile.TemporaryDirectory() as workspace:
            root = Path(workspace)
            delegated = {"reviewAuthority": "delegated", "approvals": {}}
            required = {"reviewAuthority": "owner", "approvals": {}}
            self.assertFalse(any("approved" in issue for issue in check_develop(root, delegated)))
            self.assertFalse(any("approved" in issue for issue in check_pre(root, delegated)))
            self.assertIn("missing story/screenplay.json", check_develop(root, delegated))
            reserved = {**delegated, "requiredReviews": ["screenplay"]}
            self.assertIn("owner has not approved the screenplay", check_develop(root, reserved))
            self.assertNotIn("owner has not approved the case", check_develop(root, reserved))
            for production in (required, {"approvals": {}}, {"reviewAuthority": True, "approvals": {}}):
                self.assertIn("owner has not approved the screenplay", check_develop(root, production))
                self.assertIn("owner has not approved the plan (picture table and cost)", check_pre(root, production))

    def test_delegation_cannot_record_purchase_or_publication_approval(self):
        with tempfile.TemporaryDirectory() as workspace:
            root = Path(workspace)
            production = {"reviewAuthority": "delegated", "approvals": {"delivered": None, "purchase": None, "publish": None}}
            (root / "production.json").write_text(json.dumps(production), encoding="utf-8")
            for external_action in ("purchase", "publish"):
                with self.subTest(external_action=external_action), self.assertRaisesRegex(SystemExit, "unknown approval"):
                    approve(root, external_action)
            self.assertEqual(json.loads((root / "production.json").read_text(encoding="utf-8")), production)

    def test_math_picture_can_explain_without_repeating_narration(self):
        scene = {"id": "S1", "visual": {"kind": "svg", "groups": [{"svg": "<circle cx='2' cy='2' r='1'/>"}]}}
        self.assertTrue(judge_scene(scene, "Each dot represents a possible outcome.")["ok"])

    def test_text_exercises_can_repeat_the_same_layout(self):
        scenes = [{"id": f"S{i}", "title": "Predict the next outcome"} for i in range(5)]
        self.assertTrue(judge(scenes)["ok"])
        self.assertFalse(judge([])["ok"])
