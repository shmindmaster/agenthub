"""Offline lifecycle test: scaffold a production and walk it through every phase with fabricated evidence."""
from datetime import date
import json
import os
from pathlib import Path
import tempfile
import time
import unittest

import production_status as ps
import studio_init as si


def w(root, rel, text):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text if isinstance(text, str) else json.dumps(text), encoding="utf-8")
    return p


CASE = """# Case: T
## Audience
Operations leads at a regional carrier
## Promise
Know exactly what to send before Monday
## Logline
A manager must answer a hard question and does it in writing.
## Names to pronounce
Penske
## Success check
The first five seconds show the question and the date.
"""


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = si.init("Peak Call", self.tmp.name, today=date(2026, 11, 6))

    def tearDown(self):
        self.tmp.cleanup()

    def state(self, phase):
        return next(p for p in ps.status(self.root)["phases"] if p["phase"] == phase)

    def test_scaffold_layout_and_contract(self):
        for d in si.DIRS:
            self.assertTrue((self.root / d).is_dir(), d)
        job = json.loads((self.root / "job.json").read_text(encoding="utf-8"))
        self.assertEqual(job["repositoryWritePolicy"], "read-only")
        self.assertTrue(job["workspace"].endswith("peak-call-20261106"))
        self.assertEqual(self.root.name, "peak-call-20261106")

    def test_refuses_a_non_empty_workspace_without_force(self):
        with self.assertRaises(SystemExit):
            si.init("Peak Call", self.tmp.name, today=date(2026, 11, 6))

    def test_fresh_scaffold_fails_develop_on_placeholders_and_blocks_the_rest(self):
        s = ps.status(self.root)
        self.assertEqual(s["current"], "develop")
        self.assertEqual(s["phases"][0]["state"], "FAIL")
        self.assertTrue(any("TODO" in r for r in s["phases"][0]["reasons"]))
        self.assertTrue(all(p["state"] == "BLOCKED" for p in s["phases"][1:]))

    def fill_develop(self):
        w(self.root, "case/case.md", CASE)
        w(self.root, "story/treatment.md", "The call opens on a date and a question. " * 12)
        w(self.root, "story/beat-sheet.json", {"beats": [{"id": f"b{i}", "role": "hook", "summary": "x", "picture": "y"} for i in range(3)]})
        w(self.root, "story/screenplay.json", {"title": "T", "scenes": [{"id": "a", "narration": "One line."}, {"id": "b", "narration": "Two."}]})
        w(self.root, "qa/narration-check.json", {"ok": True})

    def test_develop_needs_the_owner_to_approve_case_and_screenplay(self):
        self.fill_develop()
        reasons = self.state("develop")["reasons"]
        self.assertEqual(sorted(reasons), ["owner has not approved the case", "owner has not approved the screenplay"])
        ps.approve(self.root, "case")
        ps.approve(self.root, "screenplay")
        self.assertEqual(self.state("develop")["state"], "PASS")
        self.assertEqual(ps.status(self.root)["current"], "preproduction")

    def test_a_narration_check_older_than_the_screenplay_is_stale(self):
        self.fill_develop()
        old = time.time() - 600
        os.utime(self.root / "qa/narration-check.json", (old, old))
        self.assertTrue(any("older than the screenplay" in r for r in self.state("develop")["reasons"]))

    def test_unknown_approval_is_refused(self):
        with self.assertRaises(SystemExit):
            ps.approve(self.root, "shipit")

    def test_full_walk_to_complete(self):
        self.fill_develop()
        for a in ("case", "screenplay"):
            ps.approve(self.root, a)
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "a", "visual": {"kind": "svg", "groups": []}}, {"id": "b", "visual": {"kind": "chart", "items": []}}]})
        w(self.root, "plan/breakdown.json", {"ok": True})
        w(self.root, "qa/picture-relevance.json", {"ok": True})
        w(self.root, "qa/visual-variety.json", {"ok": True})
        self.assertTrue(any("storyboard" in r for r in self.state("preproduction")["reasons"]))
        w(self.root, "story/storyboard.json", {"beats": []})
        w(self.root, "story/visual-bible.json", {})
        ps.approve(self.root, "plan")
        self.assertEqual(self.state("preproduction")["state"], "PASS")
        self.assertTrue(any("no voice take" in r for r in self.state("production")["reasons"]))
        for i in ("a", "b"):
            w(self.root, f"takes/{i}.receipt.json", {})
        w(self.root, "story/cue-sheet.json", {})
        w(self.root, "picture/briefing-props.report.json", {"ok": True})
        w(self.root, "picture/video.mp4", "x")
        self.assertEqual(self.state("production")["state"], "PASS")
        mp4 = w(self.root, "out/film.mp4", "x")
        for rep in ("word-sync", "frame-integrity"):
            w(self.root, f"qa/{rep}.json", {"ok": True})
        w(self.root, "qa/story-experience-review.json", {"pass": True})
        t = time.time() + 5
        os.utime(mp4, (t, t))
        self.assertTrue(any("older than the finished file" in r for r in self.state("post")["reasons"]))
        for rep in ("word-sync", "frame-integrity"):
            os.utime(self.root / f"qa/{rep}.json", (t + 5, t + 5))
        self.assertEqual(self.state("post")["state"], "PASS")
        w(self.root, "out/film.srt", "1")
        ps.approve(self.root, "delivered")
        s = ps.status(self.root)
        self.assertTrue(s["complete"], s)

    def test_strict_exit_code(self):
        self.assertEqual(ps.main([str(self.root)]), 0)
        self.assertEqual(ps.main([str(self.root), "--strict"]), 1)


if __name__ == "__main__":
    unittest.main()
