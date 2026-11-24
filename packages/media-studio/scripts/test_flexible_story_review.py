"""Offline smoke tests for form-aware Media Studio pre-capture story lint."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("write-story-review.py")


def fixture(root, mode="future-vision", disclose=True, verdict="pass"):
    job = {"kind": "animation", "creativeMode": mode, "craftScoreMin": 85}
    if disclose:
        job["conceptDisclosure"] = "Envisioned future technology, not shipping today"
    (root / "job.json").write_text(json.dumps(job), encoding="utf-8")
    (root / "story").mkdir()
    (root / "qa").mkdir()
    (root / "story" / "screenplay.json").write_text(json.dumps({
        "title": "A future day with imagined care",
        "scenes": [{"id": "F01", "sceneRole": "reveal", "narration": "A future family can imagine a new way of planning care together."}]
    }), encoding="utf-8")
    (root / "story" / "storyboard.json").write_text(json.dumps({
        "beats": [{"id": "F01", "sceneRole": "reveal", "visualMode": "animation",
                   "onScreen": "Clear, readable hypothetical care UI with a fictional child and clinician."}]
    }), encoding="utf-8")
    judgments = {"schema": "media-studio/story-judgments/1", "reviewer": "fixture reviewer",
                 "judgments": {key: {"verdict": verdict, "evidence": "F01: visual continuity and intent reviewed"}
                               for key in ("audience", "form-fit", "visual-story", "representation")}}
    (root / "qa" / "story-judgments.json").write_text(json.dumps(judgments), encoding="utf-8")


class CreativeFormReviewTest(unittest.TestCase):
    def invoke(self, root):
        proc = subprocess.run([sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True)
        report = json.loads((root / "qa" / "story-review.json").read_text(encoding="utf-8"))
        return proc, report

    def test_future_vision_with_nonstandard_plot_passes_form_aware_preflight(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root)
            proc, r = self.invoke(root)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertEqual(r["status"], "COMPLETE")
            self.assertTrue(r["pass"])
            self.assertEqual(r["score"], 100)
            self.assertNotIn("one-hero", r["checks"])
            self.assertIn("encoded candidate still requires critic", r["reason"].lower())

    def test_training_without_a_creative_mode_uses_form_aware_review(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root, disclose=False)
            (root / "job.json").write_text(json.dumps({"kind": "training"}), encoding="utf-8")
            proc, report = self.invoke(root)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("training", report["reason"])
            self.assertNotIn("one-hero", report["checks"])
            self.assertNotIn("trust", report["checks"])

    def test_default_marketing_jobs_keep_the_marketing_review(self):
        for job in ({"kind": "teaser"}, {"kind": "explainer", "marketing": True},
                    {"kind": "explainer", "programForm": "campaign-short"}):
            with self.subTest(job=job), tempfile.TemporaryDirectory() as d:
                root = Path(d)
                fixture(root, disclose=False)
                (root / "job.json").write_text(json.dumps(job), encoding="utf-8")
                proc, report = self.invoke(root)
                self.assertNotEqual(proc.returncode, 0)
                self.assertIn("hook", report["checks"])
                self.assertIn("no-fluff", report["checks"])

    def test_training_keeps_independent_blocking_findings(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root, disclose=False)
            (root / "job.json").write_text(json.dumps({"kind": "training"}), encoding="utf-8")
            judgments = root / "qa" / "story-judgments.json"
            data = json.loads(judgments.read_text(encoding="utf-8"))
            data["findings"] = [{
                "id": "J-1", "severity": "block", "location": "F01",
                "evidence": "The answer key conflicts with the slide.", "fix": "Correct the answer.",
            }]
            judgments.write_text(json.dumps(data), encoding="utf-8")
            proc, report = self.invoke(root)
            self.assertNotEqual(proc.returncode, 0)
            self.assertFalse(report["pass"])
            self.assertEqual(report["findings"][0]["id"], "J-1")

    def test_missing_concept_status_fails_without_pretending_current_feature(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root, disclose=False)
            proc, r = self.invoke(root)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(r["status"], "MALFORMED_INPUT")
            self.assertTrue(any("conceptDisclosure" in x for x in r["missingEvidence"]))

    def test_failed_form_fit_does_not_pass_at_threshold(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root, verdict="fail")
            proc, r = self.invoke(root)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(r["status"], "COMPLETE")
            self.assertFalse(r["pass"])

    def test_missing_film_review_is_not_success(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root)
            (root / "qa" / "story-judgments.json").unlink()
            proc, r = self.invoke(root)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(r["status"], "MALFORMED_INPUT")


if __name__ == "__main__":
    unittest.main()
