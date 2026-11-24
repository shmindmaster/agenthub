"""check_requirements.py: script-level checks and candidate measurement, on synthetic fixtures. Offline."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

import check_requirements as cr


def w(root, rel, obj):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(obj if isinstance(obj, str) else json.dumps(obj), encoding="utf-8")
    return p


def good():
    return {"schema": cr.SCHEMA, "narrationLanguage": "en-US", "uiLanguage": "es-MX", "durationSeconds": {"min": 5, "max": 60},
            "aspect": "16x9", "finalHoldSeconds": 2, "cta": {"required": True, "text": "Start free", "scene": "s2"},
            "requirements": [
                {"id": "r1", "type": "feature", "text": "shows export", "scenes": ["s1"], "match": ["export"], "evidence": "narration", "check": "script"},
                {"id": "r2", "type": "state", "text": "dark mode", "scenes": ["s1"], "match": ["dark"], "evidence": "picture", "check": "plan"}]}


class Script(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        w(self.root, "story/screenplay.json", {"scenes": [{"id": "s1", "narration": "Export the report."}, {"id": "s2", "narration": "Start free today."}]})
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "s1", "title": "Dark theme export", "visual": {"kind": "svg"}}, {"id": "s2", "title": "Done"}]})
        self.req = good()

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self, req=None, **kw):
        w(self.root, cr.REQ, self.req if req is None else req)
        return cr.check(self.root, **kw)

    def has(self, res, text):
        self.assertTrue(any(text in e for e in res["errors"]), res["errors"])

    def test_a_correct_file_passes_the_script_check_and_records_input_hashes(self):
        res = self.run_check()
        self.assertEqual(res["errors"], [], res)
        self.assertTrue(res["ok"])
        self.assertEqual(res["inputs"]["story/requirements.json"], hashlib.sha256((self.root / cr.REQ).read_bytes()).hexdigest())
        self.assertIn("finalHoldSeconds", " ".join(res["unverified"]))

    def test_missing_and_malformed_files_fail(self):
        self.assertFalse(cr.check(self.root)["ok"])
        w(self.root, cr.REQ, "{nope")
        self.has(cr.check(self.root), "not valid JSON")

    def test_duplicate_ids_empty_scenes_and_unknown_scenes_fail(self):
        self.req["requirements"][1]["id"] = "r1"
        self.has(self.run_check(), "duplicate requirement id")
        self.req = good()
        self.req["requirements"][0]["scenes"] = []
        self.has(self.run_check(), "maps to no scenes")
        self.req = good()
        self.req["requirements"][0]["scenes"] = ["zz"]
        self.has(self.run_check(), "unknown scene id")

    def test_a_match_term_must_appear_where_the_evidence_says(self):
        self.req["requirements"][0]["match"] = ["import"]
        self.has(self.run_check(), "'import' not found in the narration")
        self.req = good()
        self.req["requirements"][1]["match"] = ["light"]
        self.has(self.run_check(), "'light' not found in the picture plan")
        self.req = good()
        self.req["requirements"][1].update(match=["dark"], evidence="narration")
        self.has(self.run_check(), "'dark' not found in the narration")
        self.req = good()
        self.req["requirements"][1].update(match=["dark"], evidence="both")
        self.has(self.run_check(), "'dark' not found in the narration")

    def test_a_requirement_without_match_terms_is_unverified_not_passed(self):
        del self.req["requirements"][0]["match"]
        res = self.run_check()
        self.assertTrue(any("r1" in u for u in res["unverified"]))

    def test_todo_anywhere_fails(self):
        self.req["requirements"][0]["text"] = "TODO"
        self.has(self.run_check(), "TODO")

    def test_a_required_cta_needs_a_real_scene_and_its_text(self):
        del self.req["cta"]["scene"]
        self.has(self.run_check(), "names no scene")
        self.req = good()
        self.req["cta"]["scene"] = "nope"
        self.has(self.run_check(), "is not a scene")
        self.req = good()
        self.req["cta"]["text"] = "Buy now"
        self.has(self.run_check(), "cta text")

    def test_declared_languages_may_not_contradict_the_job_the_screenplay_or_the_capture(self):
        w(self.root, "job.json", {"narrationLanguage": "fr-FR"})
        self.has(self.run_check(), "narrationLanguage 'en-US' contradicts job.json")
        w(self.root, "job.json", {"narrationLanguage": "en-GB", "uiLanguage": "es-ES"})
        self.assertEqual(self.run_check()["errors"], [])  # same primary language
        w(self.root, "job.json", {"uiLanguage": "none"})
        self.has(self.run_check(), "uiLanguage 'es-MX' contradicts job.json")
        w(self.root, "job.json", {})
        w(self.root, "plan/capture-plan.json", {"locale": "en-US"})
        self.has(self.run_check(), "contradicts plan/capture-plan.json")
        (self.root / "plan/capture-plan.json").unlink()
        w(self.root, "story/screenplay.json", {"language": "de", "scenes": [{"id": "s1", "narration": "Export it."}, {"id": "s2", "narration": "Start free."}]})
        self.has(self.run_check(), "contradicts story/screenplay.json")

    def test_narration_and_ui_language_are_independent(self):
        self.req.update(narrationLanguage="en-US", uiLanguage="ja-JP")
        w(self.root, "job.json", {"narrationLanguage": "en", "uiLanguage": "ja"})
        self.assertEqual(self.run_check()["errors"], [])

    def unverified(self):
        return " | ".join(self.run_check()["unverified"])

    def test_a_cta_with_a_scene_but_no_text_is_unverified_not_passed(self):
        self.req["cta"] = {"required": True, "scene": "s2"}
        self.assertIn("cta", self.unverified())
        self.req["cta"] = {"required": True, "scene": "s2", "text": "Start free"}
        self.assertNotIn("cta", self.unverified())
        self.req["cta"] = {"required": False}
        self.assertNotIn("cta", self.unverified())

    def test_a_language_with_no_counterpart_anywhere_is_unverified_not_passed(self):
        self.assertIn("narrationLanguage", self.unverified())
        self.assertIn("uiLanguage", self.unverified())
        w(self.root, "job.json", {"narrationLanguage": "en"})
        text = self.unverified()
        self.assertNotIn("narrationLanguage", text)
        self.assertIn("uiLanguage", text)
        w(self.root, "plan/capture-plan.json", {"locale": "es_MX"})
        self.assertNotIn("uiLanguage", self.unverified())

    def test_a_blank_counterpart_does_not_verify_a_language(self):
        w(self.root, "job.json", {"narrationLanguage": "  ", "uiLanguage": 7})
        text = self.unverified()
        self.assertIn("narrationLanguage", text)
        self.assertIn("uiLanguage", text)

    def test_duration_and_aspect_are_listed_unverified_without_a_candidate(self):
        text = self.unverified()
        self.assertIn("durationSeconds", text)
        self.assertIn("aspect", text)

    def test_the_input_hashes_change_when_the_script_changes(self):
        first = self.run_check()["inputs"]
        w(self.root, "story/screenplay.json", {"scenes": [{"id": "s1", "narration": "Export it."}, {"id": "s2", "narration": "Start free today."}]})
        self.assertNotEqual(first, cr.check(self.root)["inputs"])


class Hardening(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        w(self.root, "story/screenplay.json", {"scenes": [{"id": "s1", "narration": "Exportar el informe, ESTÁ listo. Straße."}]})
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "s1", "title": "Plain", "visual": {"kind": "svg", "src": "dark/x.svg"}}]})
        self.req = {"schema": cr.SCHEMA, "requirements": [{"id": "r1", "type": "feature", "text": "x", "scenes": ["s1"], "match": ["listo"], "check": "c"}]}

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self, **kw):
        w(self.root, cr.REQ, self.req)
        return cr.check(self.root, **kw)

    def errs(self):
        return self.run_check()["errors"]

    def test_an_empty_requirements_list_is_an_error(self):
        self.req["requirements"] = []
        self.assertTrue(any("at least one requirement" in e for e in self.errs()))

    def test_unhashable_ids_give_clean_errors(self):
        self.req["requirements"][0]["id"] = ["a"]
        self.assertTrue(self.errs())
        self.req["requirements"][0].update(id="r1", scenes=[["s1"], {"a": 1}])
        self.assertTrue(self.errs())
        self.req["requirements"][0]["scenes"] = ["s1"]
        self.req["cta"] = {"required": True, "scene": ["s1"]}
        self.assertTrue(any("cta" in e for e in self.errs()))

    def test_matching_is_nfc_casefolded_and_whole_word(self):
        decomposed = "esta" + chr(0x301)
        self.req["requirements"][0]["match"] = [decomposed]
        self.assertEqual(self.errs(), [])
        self.req["requirements"][0]["match"] = ["strasse"]
        self.assertEqual(self.errs(), [])
        self.req["requirements"][0]["match"] = ["port"]
        self.assertTrue(any("'port' not found" in e for e in self.errs()))
        self.req["requirements"][0]["match"] = ["ESTÁ"]
        self.assertEqual(self.errs(), [])

    def test_picture_evidence_reads_text_fields_not_ids_paths_or_kinds(self):
        self.req["requirements"][0].update(match=["dark"], evidence="picture")
        self.assertTrue(any("'dark' not found in the picture plan" in e for e in self.errs()))
        self.req["requirements"][0].update(match=["svg"])
        self.assertTrue(self.errs())
        self.req["requirements"][0].update(match=["plain"])
        self.assertEqual(self.errs(), [])

    def test_locale_with_an_underscore_compares_by_primary_language(self):
        self.req.update(uiLanguage="es-MX")
        w(self.root, "plan/capture-plan.json", {"locale": "es_MX"})
        self.assertEqual(self.errs(), [])
        w(self.root, "plan/capture-plan.json", {"locale": "en_US"})
        self.assertTrue(any("contradicts" in e for e in self.errs()))

    def test_picture_evidence_waits_for_the_plan_without_failing(self):
        (self.root / "story/picture-plan.json").unlink()
        self.req["requirements"][0].update(match=["plain"], evidence="picture")
        res = self.run_check()
        self.assertEqual(res["errors"], [])
        self.assertTrue(any("picture-plan.json" in u for u in res["unverified"]))
        self.assertNotIn("story/picture-plan.json", res["inputs"])
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "s1", "title": "TODO"}]})
        res = self.run_check()
        self.assertEqual(res["errors"], [])
        self.assertNotIn("story/picture-plan.json", res["inputs"])
        w(self.root, "story/picture-plan.json", {"scenes": [{"id": "s1", "title": "Plain"}]})
        res = self.run_check()
        self.assertEqual((res["errors"], res["unverified"]), ([], []))
        self.assertIn("story/picture-plan.json", res["inputs"])

    def test_the_scaffold_fields_follow_the_deliverable(self):
        import studio_init as si
        base = si.requirements_scaffold(None)
        self.assertIn("aspect", base)
        audio = si.requirements_scaffold("audio")
        self.assertNotIn("aspect", audio)
        self.assertNotIn("finalHoldSeconds", audio)
        stills = si.requirements_scaffold("stills")
        self.assertNotIn("finalHoldSeconds", stills)
        self.assertIn("aspect", stills)


@unittest.skipUnless(shutil.which("ffprobe") and shutil.which("ffmpeg"), "ffmpeg not installed")
class Stills(unittest.TestCase):
    def setUp(self):
        import subprocess
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        w(self.root, "story/screenplay.json", {"scenes": [{"id": "s1", "narration": "Export it."}]})
        (self.root / "out").mkdir()
        self.png = self.root / "out/poster.png"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=320x180", "-frames:v", "1", str(self.png)], check=True)
        self.req = {"schema": cr.SCHEMA, "durationSeconds": {"min": 5, "max": 7}, "aspect": "16x9", "finalHoldSeconds": 3,
                    "requirements": [{"id": "r1", "type": "feature", "text": "x", "scenes": ["s1"], "match": ["export"], "check": "c"}]}

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self, f):
        w(self.root, cr.REQ, self.req)
        return cr.check(self.root, candidate=f)

    def test_a_png_is_measured_for_aspect_only(self):
        res = self.run_check(self.png)
        self.assertTrue(res["ok"], res)
        self.req["aspect"] = "9x16"
        self.assertTrue(any("aspect" in e for e in self.run_check(self.png)["errors"]))

    def test_a_pdf_aspect_needs_a_framing_review_item(self):
        pdf = w(self.root, "out/deck.pdf", "%PDF")
        res = self.run_check(pdf)
        self.assertFalse(res["ok"])
        self.assertTrue(any("framing" in u for u in res["unverified"]))
        digest = hashlib.sha256(pdf.read_bytes()).hexdigest()
        w(self.root, cr.REVIEW, {"schema": cr.REVIEW_SCHEMA, "candidateSha256": digest, "reviewer": "qa",
                                 "items": [{"id": "framing", "verdict": "pass", "at": 0, "note": "16:9 pages"}]})
        res = self.run_check(pdf)
        self.assertTrue(res["ok"], res)


@unittest.skipUnless(shutil.which("ffprobe") and shutil.which("ffmpeg"), "ffmpeg not installed")
class Candidate(unittest.TestCase):
    def setUp(self):
        import subprocess
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        w(self.root, "story/screenplay.json", {"scenes": [{"id": "s1", "narration": "Export it."}]})
        self.mp4 = self.root / "out/film.mp4"
        self.mp4.parent.mkdir()
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=320x180:d=6:r=10", "-pix_fmt", "yuv420p", str(self.mp4)], check=True)
        self.req = {"schema": cr.SCHEMA, "durationSeconds": {"min": 5, "max": 7}, "aspect": "16x9",
                    "requirements": [{"id": "r1", "type": "feature", "text": "x", "scenes": ["s1"], "match": ["export"], "check": "script"}]}

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self):
        w(self.root, cr.REQ, self.req)
        return cr.check(self.root, candidate=self.mp4)

    def test_duration_and_aspect_are_measured(self):
        res = self.run_check()
        self.assertTrue(res["ok"], res)
        self.assertEqual(res["candidate"]["sha256"], hashlib.sha256(self.mp4.read_bytes()).hexdigest())
        self.req["durationSeconds"] = {"min": 10, "max": 20}
        self.assertTrue(any("duration" in e for e in self.run_check()["errors"]))
        self.req.update(durationSeconds={"min": 5, "max": 7}, aspect="9x16")
        self.assertTrue(any("aspect" in e for e in self.run_check()["errors"]))

    def test_the_requirements_file_validate_finished_film_reads_is_accepted_here_too(self):
        shared = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "requirements-shared.json"
        self.req = json.loads(shared.read_text(encoding="utf-8"))
        res = self.run_check()
        self.assertEqual(res["errors"], [], res)
        self.assertTrue(res["ok"], res)

    def test_a_declared_hold_with_no_finished_film_record_is_unverified_and_blocks_ok(self):
        self.req["finalHoldSeconds"] = 2
        res = self.run_check()
        self.assertFalse(res["ok"])
        self.assertTrue(res["unverified"])
        digest = hashlib.sha256(self.mp4.read_bytes()).hexdigest()
        w(self.root, cr.FINISHED, {"schema": "media-studio/finished-film/1", "ok": True, "sha256": "0" * 64, "ending": {"stillSeconds": 3}})
        self.assertFalse(self.run_check()["ok"])  # a record for another file does not count
        w(self.root, cr.FINISHED, {"schema": "media-studio/finished-film/1", "ok": True, "sha256": digest, "ending": {"stillSeconds": 3}})
        self.assertTrue(self.run_check()["ok"])
        w(self.root, cr.FINISHED, {"schema": "media-studio/finished-film/1", "ok": True, "sha256": digest, "ending": {"stillSeconds": 1.8}})
        self.assertTrue(self.run_check()["ok"])  # the gate's own 0.25 s tolerance
        w(self.root, cr.FINISHED, {"schema": "media-studio/finished-film/1", "ok": True, "sha256": digest, "ending": {"stillSeconds": 1}})
        self.assertTrue(any("final hold" in e for e in self.run_check()["errors"]))


    def visual_req(self):
        self.req["requirements"].append({"id": "v1", "type": "state", "text": "dark mode is shown", "scenes": ["s1"], "check": "watch"})

    def review(self, sha=None, verdict="pass", at="00:03", rid="v1"):
        sha = sha or hashlib.sha256(self.mp4.read_bytes()).hexdigest()
        w(self.root, cr.REVIEW, {"schema": cr.REVIEW_SCHEMA, "candidateSha256": sha, "reviewer": "qa",
                                 "items": [{"id": rid, "verdict": verdict, "at": at, "note": "seen"}]})

    def test_a_requirement_without_match_terms_needs_a_passing_review_of_this_file(self):
        self.visual_req()
        res = self.run_check()
        self.assertFalse(res["ok"])
        self.assertTrue(any("v1" in u for u in res["unverified"]))
        self.review()
        res = self.run_check()
        self.assertTrue(res["ok"], res)
        self.assertIn(cr.REVIEW, res["inputs"])
        self.assertNotIn(cr.REVIEW, cr.input_hashes(self.root))

    def test_an_unmeasured_language_or_cta_claim_needs_a_passing_review_item(self):
        self.req.update(narrationLanguage="en", uiLanguage="en", cta={"required": True, "scene": "s1"})
        res = self.run_check()
        self.assertFalse(res["ok"], res)
        text = " | ".join(res["unverified"])
        for claim in ("narrationLanguage", "uiLanguage", "cta"):
            self.assertIn(claim, text)
        digest = hashlib.sha256(self.mp4.read_bytes()).hexdigest()
        w(self.root, cr.REVIEW, {"schema": cr.REVIEW_SCHEMA, "candidateSha256": digest, "reviewer": "qa",
                                 "items": [{"id": i, "verdict": "pass", "at": 2, "note": "seen"} for i in ("narrationLanguage", "uiLanguage", "cta")]})
        res = self.run_check()
        self.assertEqual((res["errors"], res["unverified"]), ([], []), res)
        self.assertTrue(res["ok"])

    def test_a_failed_stale_or_out_of_range_review_does_not_count(self):
        self.visual_req()
        self.review(verdict="fail")
        self.assertTrue(any("failed review" in e for e in self.run_check()["errors"]))
        self.review(sha="0" * 64)
        res = self.run_check()
        self.assertTrue(any("stale" in e for e in res["errors"]))
        self.assertFalse(res["ok"])
        self.review(at="09:00")
        self.assertTrue(any("inside the film" in e for e in self.run_check()["errors"]))
        self.review(at=3.5)
        self.assertTrue(self.run_check()["ok"])
        self.review(at="soon")
        self.assertFalse(self.run_check()["ok"])


class NoFfprobe(unittest.TestCase):
    def test_missing_ffprobe_is_an_error_not_a_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            w(root, "story/screenplay.json", {"scenes": [{"id": "s1", "narration": "Export it."}]})
            w(root, cr.REQ, {"schema": cr.SCHEMA, "durationSeconds": {"min": 1, "max": 9},
                             "requirements": [{"id": "r1", "type": "feature", "text": "x", "scenes": ["s1"], "match": ["export"], "check": "c"}]})
            film = w(root, "out/film.mp4", "x")
            with mock.patch.object(cr.subprocess, "run", side_effect=FileNotFoundError):
                res = cr.check(root, candidate=film)
            self.assertFalse(res["ok"])
            self.assertTrue(any("ffprobe is not installed" in e for e in res["errors"]))


if __name__ == "__main__":
    unittest.main()
