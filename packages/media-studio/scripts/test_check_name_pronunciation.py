"""Offline tests for the name-pronunciation checker. No network, no Azure SDK, no spend."""
import unittest

import check_name_pronunciation as chk


def word(text, start, dur, kind="SpeechSynthesisBoundaryType.Word"):
    return {"text": text, "start_seconds": start, "duration_seconds": dur, "boundary_type": kind}


def azure_result(word_text, accuracy, error="None", phones=()):
    return {"NBest": [{"Lexical": word_text.lower(), "Words": [{
        "Word": word_text, "PronunciationAssessment": {"AccuracyScore": accuracy, "ErrorType": error},
        "Phonemes": [{"Phoneme": p, "PronunciationAssessment": {
            "AccuracyScore": s, "NBestPhonemes": [{"Phoneme": b, "Score": bs} for b, bs in nb]}} for p, s, nb in phones]}]}]}


GOOD = azure_result("Sarosh", 92, phones=[("s", 95, [("s", 95)]), ("ʃ", 90, [("ʃ", 90), ("dʒ", 10)])])
BAD_END = azure_result("Sarosh", 85, phones=[("s", 95, [("s", 95)]), ("ʃ", 80, [("dʒ", 85), ("ʃ", 40)])])


class OccurrenceTests(unittest.TestCase):
    def test_finds_names_from_the_synthesizer_clock_and_ignores_punctuation(self):
        receipts = {"d1": {"duration_seconds": 7.2, "word_boundaries": [
            word("Sarosh", 0.05, 0.67), word(",", 0.83, 0.1, "SpeechSynthesisBoundaryType.Punctuation"),
            word("hello", 1.0, 0.3), word("sarosh", 2.0, 0.5)]}, "d2": {"word_boundaries": []}}
        found = chk.find_occurrences(receipts, ["Sarosh", "Penske"])
        self.assertEqual([(o["take"], o["name"]) for o in found], [("d1", "Sarosh"), ("d1", "Sarosh")])
        self.assertAlmostEqual(found[0]["end"], 0.72)

    def test_clip_window_is_padded_clamped_and_never_tiny(self):
        self.assertEqual(chk.clip_window(0.05, 0.72, 7.2), (0.0, 1.07))
        a, b = chk.clip_window(7.0, 7.1, 7.2)
        self.assertLessEqual(b, 7.2)
        self.assertGreater(b - a, 0.5)


class PhoneTests(unittest.TestCase):
    def test_phone_normalisation_ignores_stress_and_spelling_variants(self):
        self.assertEqual(chk.norm_phone("ˈɹ"), chk.norm_phone("r"))
        self.assertEqual(chk.norm_phone("ʧ"), "tʃ")


class JudgeTests(unittest.TestCase):
    def test_good_name_passes(self):
        j = chk.judge_clip(chk.parse_assessment(GOOD), "ʃ")
        self.assertTrue(j["ok"], j["reasons"])

    def test_wrong_final_sound_fails_even_with_a_decent_word_score(self):
        j = chk.judge_clip(chk.parse_assessment(BAD_END), "ʃ")
        self.assertFalse(j["ok"])
        self.assertTrue(any("final sound" in r for r in j["reasons"]))

    def test_miscue_low_score_and_nothing_recognized_fail(self):
        self.assertFalse(chk.judge_clip(chk.parse_assessment(azure_result("Sarosh", 90, "Mispronunciation")))["ok"])
        self.assertFalse(chk.judge_clip(chk.parse_assessment(azure_result("Sarosh", 40)))["ok"])
        self.assertFalse(chk.judge_clip(None)["ok"])
        self.assertIsNone(chk.parse_assessment({}))

    def test_low_phoneme_fails(self):
        r = azure_result("Sarosh", 90, phones=[("s", 20, [("s", 20)])])
        self.assertFalse(chk.judge_clip(chk.parse_assessment(r))["ok"])


class LineContextTests(unittest.TestCase):
    def test_reads_the_nth_occurrence_of_the_name_from_whole_line_results(self):
        words = [{"Word": "Penske"}, {"Word": "declined"}, {"Word": "penske"}]
        self.assertIs(chk.name_word(words, "Penske", 0), words[0])
        self.assertIs(chk.name_word(words, "Penske", 1), words[2])
        self.assertIsNone(chk.name_word(words, "Penske", 2))
        self.assertIsNone(chk.parse_word(None))

    def test_parse_word_matches_clip_parsing(self):
        word = GOOD["NBest"][0]["Words"][0]
        self.assertEqual(chk.parse_word(word)["accuracy"], 92.0)
        self.assertTrue(chk.judge_clip(chk.parse_word(word), "ʃ")["ok"])

    def test_swap_replaces_only_the_requested_occurrence(self):
        self.assertEqual(chk.swap_nth("Penske, then Penske again.", "Penske", "Forman", 1), "Penske, then Forman again.")


class VerdictTests(unittest.TestCase):
    ok = {"ok": True}

    def test_confirmed_needs_every_check_and_a_confirmed_lexicon_entry(self):
        v = chk.verdict_for_name([self.ok], {"status": "confirmed"}, [True], {"attempts": 2, "correctlyFailed": 2})
        self.assertEqual(v["verdict"], "CONFIRMED")
        v = chk.verdict_for_name([self.ok], {"status": "unconfirmed"}, [True], {"attempts": 2, "correctlyFailed": 2})
        self.assertEqual(v["verdict"], "AUTOMATED_PASS_UNCONFIRMED")

    def test_missing_anchor_is_skipped_never_passed(self):
        v = chk.verdict_for_name([self.ok], {"status": "confirmed"}, None, {"attempts": 2, "correctlyFailed": 2})
        self.assertEqual(v["checkC"], "skipped")
        self.assertNotEqual(v["verdict"], "CONFIRMED")

    def test_a_check_that_cannot_fail_is_reported_as_such(self):
        v = chk.verdict_for_name([self.ok], {"status": "confirmed"}, [True], {"attempts": 2, "correctlyFailed": 0})
        self.assertEqual(v["verdict"], "CHECK_NOT_DISCRIMINATING")

    def test_any_failed_clip_or_anchor_mismatch_fails_and_no_clips_fails(self):
        self.assertEqual(chk.verdict_for_name([self.ok, {"ok": False}], {}, None, None)["verdict"], "FAIL")
        self.assertEqual(chk.verdict_for_name([self.ok], {}, [False], None)["verdict"], "FAIL")
        self.assertEqual(chk.verdict_for_name([], {}, None, None)["verdict"], "FAIL")


if __name__ == "__main__":
    unittest.main()
