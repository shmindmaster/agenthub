"""production_status.py deliverable forms and the requirements gate. Synthetic evidence, offline."""
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest

import check_requirements as cr
import production_status as ps
import studio_init as si

CASE = "# Case: T\n## Audience\nOperators of a small shop\n## Promise\nKnow what to do next\n## Logline\nA clerk finds the fix.\n## Names to pronounce\nNone\n## Success check\nThe fix is on screen.\n"


def w(root, rel, obj):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(obj if isinstance(obj, str) else json.dumps(obj), encoding="utf-8")
    return p


class Forms(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = si.init("Forms", self.tmp.name, today=date(2026, 11, 6))

    def tearDown(self):
        self.tmp.cleanup()

    def declare(self, form, **extra):
        job = json.loads((self.root / "job.json").read_text(encoding="utf-8"))
        job.update(deliverable=form, **extra)
        w(self.root, "job.json", job)

    def state(self, phase):
        return next(p for p in ps.status(self.root)["phases"] if p["phase"] == phase)

    def develop_files(self, scenes):
        w(self.root, "case/case.md", CASE)
        w(self.root, "story/treatment.md", "A clerk opens the app and finds the fix. " * 10)
        w(self.root, "story/beat-sheet.json", {"beats": [{"id": "b1", "role": "hook", "summary": "x", "picture": "y"}]})
        w(self.root, "story/screenplay.json", {"title": "T", "scenes": scenes})
        ps.approve(self.root, "case")
        ps.approve(self.root, "screenplay")

    def plan_files(self):
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "a", "visual": {"kind": "svg", "groups": []}}]})
        w(self.root, "plan/breakdown.json", {"ok": True})
        w(self.root, "qa/picture-relevance.json", {"ok": True})
        w(self.root, "qa/visual-variety.json", {"ok": True})
        w(self.root, "story/storyboard.json", {"beats": []})
        w(self.root, "story/visual-bible.json", {})
        ps.approve(self.root, "plan")

    def test_an_undeclared_job_derives_narrated_video_and_audio_only_derives_audio(self):
        self.assertEqual(ps.status(self.root)["deliverable"], "narrated-video")
        w(self.root, "job.json", {"kind": "audio-only"})
        self.assertEqual(ps.status(self.root)["deliverable"], "audio")
        w(self.root, "job.json", {"kind": "briefing", "filmType": "non-narrative"})
        self.assertEqual(ps.status(self.root)["deliverable"], "narrated-video")

    def test_unknown_value_and_audio_only_with_a_picture_form_fail_develop_with_one_message(self):
        self.declare("hologram")
        reasons = self.state("develop")["reasons"]
        self.assertEqual(len(reasons), 1)
        self.assertIn("hologram", reasons[0])
        w(self.root, "job.json", {"kind": "audio-only", "deliverable": "silent-video"})
        reasons = self.state("develop")["reasons"]
        self.assertEqual(len(reasons), 1)
        self.assertIn("audio-only", reasons[0])

    def test_silent_video_accepts_scenes_with_an_action_but_not_empty_ones(self):
        self.declare("silent-video")
        self.develop_files([{"id": "a", "action": "The clerk taps Export."}, {"id": "b", "narration": ""}])
        self.assertTrue(any("neither narration nor an action" in r for r in self.state("develop")["reasons"]))
        self.develop_files([{"id": "a", "action": "The clerk taps Export."}, {"id": "b", "picture": "The file lands."}])
        self.assertEqual(self.state("develop")["state"], "PASS")  # no narration check required
        self.declare("narrated-video")
        self.assertTrue(self.state("develop")["reasons"])  # the same scenes fail a narrated film

    def test_silent_video_walk_needs_no_voice_cue_sheet_word_sync_or_captions(self):
        self.declare("silent-video")
        self.develop_files([{"id": "a", "action": "The clerk taps Export."}])
        self.plan_files()
        w(self.root, "picture/briefing-props.report.json", {"ok": True})
        self.assertIn("missing picture/video.mp4", self.state("production")["reasons"])
        w(self.root, "picture/video.mp4", "x")
        self.assertEqual(self.state("production")["state"], "PASS")
        self.assertIn("no finished file in out/", self.state("post")["reasons"])
        w(self.root, "out/film.mp4", "x")
        self.assertIn("missing frame-integrity.json", self.state("post")["reasons"])
        self.assertNotIn("missing word-sync.json", self.state("post")["reasons"])
        w(self.root, "qa/frame-integrity.json", {"ok": True})
        w(self.root, "qa/story-experience-review.json", {"pass": True})
        self.assertEqual(self.state("post")["state"], "PASS")
        ps.approve(self.root, "delivered")
        self.assertTrue(ps.status(self.root)["complete"])

    def test_audio_needs_takes_and_an_audio_file_but_no_picture_gates(self):
        self.declare("audio")
        self.develop_files([{"id": "a", "narration": "One line."}])
        w(self.root, "qa/narration-check.json", {"ok": True})
        w(self.root, "plan/breakdown.json", {"ok": True})
        ps.approve(self.root, "plan")
        self.assertEqual(self.state("preproduction")["state"], "PASS")
        self.assertIn("picture plan", self.state("preproduction")["notRequired"])
        self.assertEqual(self.state("production")["reasons"], ["no voice take for scene(s): a"])
        w(self.root, "takes/a.receipt.json", {})
        self.assertEqual(self.state("production")["state"], "PASS")
        w(self.root, "qa/story-experience-review.json", {"pass": True})
        w(self.root, "out/film.mp4", "x")
        self.assertEqual(self.state("post")["reasons"], ["no finished file in out/ (wav/mp3/m4a)"])
        w(self.root, "out/film.m4a", "x")
        self.assertEqual(self.state("post")["state"], "PASS")
        ps.approve(self.root, "delivered")
        self.assertTrue(ps.status(self.root)["complete"])

    def test_stills_skip_production_and_need_a_still_file(self):
        self.declare("stills")
        self.develop_files([{"id": "a", "action": "A poster."}])
        self.plan_files()
        self.assertEqual(self.state("production")["state"], "NOT_REQUIRED")
        self.assertEqual(ps.status(self.root)["current"], "post")
        w(self.root, "out/poster.png", "x")
        self.assertEqual(self.state("post")["state"], "PASS")
        ps.approve(self.root, "delivered")
        self.assertTrue(ps.status(self.root)["complete"])

    def test_storyboard_needs_the_storyboard_file_and_the_later_phases_are_not_required(self):
        self.declare("storyboard", intent="internal")
        self.develop_files([{"id": "a", "action": "A frame."}])
        self.plan_files()
        (self.root / "story/storyboard.json").unlink()
        self.assertIn("storyboard deliverable needs story/storyboard.json", self.state("preproduction")["reasons"])
        w(self.root, "story/storyboard.json", {"beats": []})
        s = ps.status(self.root)  # no delegation: today's rule still asks for the delivery record
        self.assertEqual([p["state"] for p in s["phases"]], ["PASS", "PASS", "NOT_REQUIRED", "NOT_REQUIRED", "FAIL"])
        self.assertIn("owner review 'delivered' is required and not recorded", s["phases"][4]["reasons"])
        ps.approve(self.root, "delivered")
        self.assertTrue(ps.status(self.root)["complete"])

    def delegate(self, reserved=()):
        prod = json.loads((self.root / "production.json").read_text(encoding="utf-8"))
        prod.update(reviewAuthority="delegated", requiredReviews=list(reserved))
        w(self.root, "production.json", prod)

    def test_a_storyboard_with_delegated_authority_and_no_reservation_is_complete_without_delivery(self):
        self.declare("storyboard")
        self.delegate()
        self.develop_files([{"id": "a", "action": "A frame."}])
        self.plan_files()
        s = ps.status(self.root)
        self.assertEqual([p["state"] for p in s["phases"]][2:], ["NOT_REQUIRED"] * 3)
        self.assertTrue(s["complete"])

    def test_a_reserved_review_still_fails_a_not_required_phase(self):
        self.declare("storyboard")
        self.delegate(["delivered"])
        self.develop_files([{"id": "a", "action": "A frame."}])
        self.plan_files()
        self.assertEqual(self.state("delivery")["state"], "FAIL")
        ps.approve(self.root, "delivered")
        self.assertTrue(ps.status(self.root)["complete"])

    def test_not_required_never_blocks_the_next_phase(self):
        self.declare("stills")
        self.develop_files([{"id": "a", "action": "A poster."}])
        self.assertEqual(self.state("production")["state"], "BLOCKED")  # preproduction still fails
        self.plan_files()
        self.assertEqual(self.state("post")["state"], "FAIL")


class RequirementsGate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = si.init("Req", self.tmp.name, today=date(2026, 11, 6))
        w(self.root, "case/case.md", CASE)
        w(self.root, "story/treatment.md", "A clerk opens the app and finds the fix. " * 10)
        w(self.root, "story/beat-sheet.json", {"beats": [{"id": "b1", "role": "hook", "summary": "x", "picture": "y"}]})
        w(self.root, "story/screenplay.json", {"title": "T", "scenes": [{"id": "a", "narration": "Export the report."}]})
        w(self.root, "qa/narration-check.json", {"ok": True})
        ps.approve(self.root, "case")
        ps.approve(self.root, "screenplay")

    def tearDown(self):
        self.tmp.cleanup()

    def develop(self):
        return ps.status(self.root)["phases"][0]["reasons"]

    def write_req(self):
        w(self.root, cr.REQ, {"schema": cr.SCHEMA, "requirements": [
            {"id": "r1", "type": "feature", "text": "export", "scenes": ["a"], "match": ["export"], "check": "script"}]})

    def test_no_requirements_file_leaves_develop_unchanged(self):
        self.assertEqual(self.develop(), [])

    def test_develop_needs_a_passing_fresh_check(self):
        self.write_req()
        self.assertIn(f"missing {cr.REPORT}: run check_requirements.py", self.develop())
        self.assertEqual(cr.main([str(self.root)]), 0)
        self.assertEqual(self.develop(), [])
        w(self.root, "story/screenplay.json", {"title": "T", "scenes": [{"id": "a", "narration": "Export the file."}]})
        self.assertTrue(any("stale" in r for r in self.develop()))  # same mtime window, different hash
        self.assertEqual(cr.main([str(self.root)]), 0)
        self.assertEqual(self.develop(), [])

    def test_a_failing_check_blocks_develop(self):
        self.write_req()
        w(self.root, "story/screenplay.json", {"title": "T", "scenes": [{"id": "a", "narration": "Nothing relevant."}]})
        self.assertEqual(cr.main([str(self.root)]), 1)
        self.assertTrue(any("did not pass" in r for r in self.develop()))

    def test_post_needs_the_check_run_on_the_current_finished_file_and_its_record(self):
        self.write_req()
        cr.main([str(self.root)])
        film = w(self.root, "out/film.mp4", "x")
        digest = hashlib.sha256(film.read_bytes()).hexdigest()
        for rep in ("word-sync", "frame-integrity"):
            w(self.root, f"qa/{rep}.json", {"ok": True})
        w(self.root, "qa/story-experience-review.json", {"pass": True})
        reasons = ps.check_post(self.root, {})
        self.assertTrue(any("not run on the current finished file" in r for r in reasons), reasons)
        report = json.loads((self.root / cr.REPORT).read_text(encoding="utf-8"))
        report["candidate"] = {"path": "out/film.mp4", "sha256": digest}
        w(self.root, cr.REPORT, report)
        reasons = ps.check_post(self.root, {})
        self.assertTrue(any("finished-film.json is missing" in r for r in reasons), reasons)
        req_sha = cr.sha256(self.root / cr.REQ)
        record = {"schema": "media-studio/finished-film/1", "ok": True, "sha256": digest, "deliverable": "narrated-video", "requirementsSha256": req_sha}
        w(self.root, cr.FINISHED, {**record, "sha256": "0" * 64})
        self.assertTrue(any("finished-film.json is missing" in r for r in ps.check_post(self.root, {})))
        w(self.root, cr.FINISHED, {**record, "deliverable": "silent-video"})
        self.assertTrue(any("deliverable" in r for r in ps.check_post(self.root, {})))
        w(self.root, cr.FINISHED, {**record, "requirementsSha256": "1" * 64})
        self.assertTrue(any("requirements" in r and "current" in r for r in ps.check_post(self.root, {})))
        w(self.root, cr.FINISHED, record)
        self.assertEqual(ps.check_post(self.root, {}), [])
        film.write_text("recut", encoding="utf-8")
        self.assertTrue(ps.check_post(self.root, {}))


    def test_removing_requirements_json_after_a_check_fails_develop(self):
        self.write_req()
        cr.main([str(self.root)])
        (self.root / cr.REQ).unlink()
        self.assertTrue(any("requirements.json removed" in r for r in self.develop()))

    def test_picture_plan_is_not_develop_freshness_but_preproduction_needs_it_current(self):
        w(self.root, cr.REQ, {"schema": cr.SCHEMA, "requirements": [
            {"id": "r1", "type": "feature", "text": "x", "scenes": ["a"], "match": ["export"], "evidence": "both", "check": "c"}]})
        self.assertEqual(cr.main([str(self.root)]), 0)  # no plan yet: the picture side is unverified, not an error
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "a", "title": "Export", "visual": {"kind": "svg", "groups": []}}]})
        self.assertEqual(self.develop(), [])  # the plan arriving does not stale develop
        self.assertTrue(any("picture plan" in r for r in ps.check_pre(self.root, {"approvals": {"plan": "x"}})))
        self.assertEqual(cr.main([str(self.root)]), 0)
        self.assertFalse(any("picture plan" in r for r in ps.check_pre(self.root, {"approvals": {"plan": "x"}})))
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "a", "title": "Export now", "visual": {"kind": "svg", "groups": []}}]})
        self.assertTrue(any("picture plan" in r for r in ps.check_pre(self.root, {"approvals": {"plan": "x"}})))

    def test_stills_post_needs_no_finished_film_record(self):
        w(self.root, "job.json", {"kind": "briefing", "deliverable": "stills"})
        self.write_req()
        cr.main([str(self.root)])
        png = w(self.root, "out/poster.png", "x")
        report = json.loads((self.root / cr.REPORT).read_text(encoding="utf-8"))
        report["candidate"] = {"path": "out/poster.png", "sha256": hashlib.sha256(png.read_bytes()).hexdigest()}
        w(self.root, cr.REPORT, report)
        self.assertEqual(ps.check_post(self.root, {}), [])

    def test_a_pinned_finished_file_wins_over_newest_and_cannot_escape_out(self):
        w(self.root, "out/a.mp4", "a")
        w(self.root, "out/b.mp4", "b")
        os.utime(self.root / "out/a.mp4", (1, 1))
        prod = json.loads((self.root / "production.json").read_text(encoding="utf-8"))
        w(self.root, "production.json", {**prod, "finishedFile": "out/a.mp4"})
        self.assertEqual(ps.finished_files(self.root, "narrated-video"), ([self.root / "out/a.mp4"], None))
        w(self.root, "production.json", {**prod, "finishedFile": "../x.mp4"})
        files, err = ps.finished_files(self.root, "narrated-video")
        self.assertIn("finishedFile", err)
        self.assertTrue(any("finishedFile" in r for r in ps.check_post(self.root, {})))


class ReviewFreshness(unittest.TestCase):
    def test_a_candidate_review_does_not_make_develop_stale_but_changing_it_makes_post_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            w(root, "story/screenplay.json", {"scenes": [{"id": "a", "narration": "Export it."}]})
            w(root, cr.REQ, {"schema": cr.SCHEMA, "requirements": [{"id": "v", "type": "state", "text": "x", "scenes": ["a"], "check": "c"}]})
            film = w(root, "out/film.mp4", "x")
            digest = hashlib.sha256(film.read_bytes()).hexdigest()
            w(root, cr.REVIEW, {"schema": cr.REVIEW_SCHEMA, "candidateSha256": digest, "reviewer": "qa", "items": []})
            w(root, cr.REPORT, {"ok": True, "inputs": {**cr.input_hashes(root), cr.REVIEW: cr.sha256(root / cr.REVIEW)}, "candidate": {"sha256": digest}})
            self.assertEqual(ps.requirements_reasons(root, "develop"), [])
            w(root, cr.REVIEW, {"schema": cr.REVIEW_SCHEMA, "candidateSha256": digest, "reviewer": "other", "items": []})
            self.assertTrue(any("stale" in r for r in ps.requirements_reasons(root, "develop")))


class ScreenplaySchema(unittest.TestCase):
    def test_a_scene_needs_one_of_narration_action_or_picture(self):
        scene = json.loads((Path(__file__).parent.parent / "schemas/screenplay.schema.json").read_text(encoding="utf-8"))["$defs"]["scene"]
        self.assertEqual(scene["required"], ["id"])
        self.assertEqual(scene["anyOf"], [{"required": ["narration"]}, {"required": ["action"]}, {"required": ["picture"]}])
        self.assertEqual(scene["properties"]["narration"]["minLength"], 1)
        self.assertIn("picture", scene["properties"])


class Scaffold(unittest.TestCase):
    def test_flags_are_optional_and_the_default_scaffold_is_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            plain = si.init("Plain", tmp, today=date(2026, 11, 6))
            job = json.loads((plain / "job.json").read_text(encoding="utf-8"))
            self.assertNotIn("deliverable", job)
            self.assertFalse((plain / "story/requirements.json").exists())
            both = si.init("Both", tmp, today=date(2026, 11, 6), deliverable="stills", requirements=True)
            self.assertEqual(json.loads((both / "job.json").read_text(encoding="utf-8"))["deliverable"], "stills")
            self.assertIn("TODO", (both / "story/requirements.json").read_text(encoding="utf-8"))
            self.assertFalse(cr.check(both)["ok"])  # the TODO scaffold cannot pass
            with self.assertRaises(SystemExit):
                si.init("Bad", tmp, today=date(2026, 11, 6), deliverable="hologram")


if __name__ == "__main__":
    unittest.main()
