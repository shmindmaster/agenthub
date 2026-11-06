"""Offline tests for the adapter-owned pronunciation lexicon. No network, no spend."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import governed_azure_speech as az

KW = dict(workspace="synthetic-job", revision="v1", dictionary_revision="v1",
          voice="en-US-GuyNeural", style="friendly")
SAROSH = '<phoneme alphabet="ipa" ph="səˈroʊʃ">Sarosh</phoneme>'


class LexiconTests(unittest.TestCase):
    def test_wraps_whole_word_only_and_case_sensitively(self):
        plan = az.quote("Sarosh met Saroshi and sarosh and Sarosh-Corp.", pronunciations=["Sarosh"], **KW)
        ssml = plan["request"]["ssml"]
        self.assertEqual(ssml.count(SAROSH), 1)
        self.assertIn("Saroshi", ssml)
        self.assertIn(" sarosh ", ssml)
        self.assertIn("Sarosh-Corp", ssml)
        self.assertEqual(plan["request"]["pronunciation"]["entries"], {"Sarosh": "səˈroʊʃ"})
        self.assertEqual(plan["request"]["pronunciation"]["alphabet"], "ipa")

    def test_applies_inside_every_paragraph(self):
        plan = az.quote("Sarosh spoke. Then Penske replied. Sarosh left.", paragraphs=[
            "Sarosh spoke.", "Then Penske replied.", "Sarosh left."], pronunciations=["Sarosh", "Penske"], **KW)
        ssml = plan["request"]["ssml"]
        self.assertEqual(ssml.count(SAROSH), 2)
        self.assertEqual(ssml.count('ph="ˈpɛnski">Penske</phoneme>'), 1)
        self.assertIn('bookmark mark="paragraph-3"', ssml)

    def test_text_markup_stays_escaped_and_caller_cannot_add_phoneme(self):
        plan = az.quote('Sarosh said <phoneme ph="x">hi</phoneme> & left.', pronunciations=["Sarosh"], **KW)
        ssml = plan["request"]["ssml"]
        self.assertIn("&lt;phoneme ph=", ssml)
        self.assertEqual(ssml.count("<phoneme "), 1)

    def test_refuses_unknown_missing_hd_and_malformed(self):
        for bad in (["Nobody"], ["Penske"], "Sarosh", [], ["Sarosh", "Sarosh"], [1]):
            with self.assertRaises(ValueError, msg=repr(bad)):
                az.quote("Sarosh spoke.", pronunciations=bad, **KW)
        with self.assertRaises(ValueError):  # Dragon HD voices are outside the phoneme allowlist
            az.quote("Sarosh spoke.", workspace="j", revision="1", dictionary_revision="1", pronunciations=["Sarosh"])

    def test_cache_key_changes_only_when_used_and_cost_counts_added_markup(self):
        base = az.quote("Sarosh spoke.", **KW)
        again = az.quote("Sarosh spoke.", **KW)
        used = az.quote("Sarosh spoke.", pronunciations=["Sarosh"], **KW)
        self.assertEqual(base["cache_key"], again["cache_key"])
        self.assertNotIn("pronunciation", base["request"])
        self.assertNotEqual(base["cache_key"], used["cache_key"])
        self.assertGreater(used["maximum_usd_micros"], base["maximum_usd_micros"])
        self.assertEqual(used["maximum_usd_micros"], len(used["request"]["ssml"].encode()) * 15)
        # an existing standard request is byte-identical to what it was before the lexicon existed
        self.assertNotIn("phoneme", base["request"]["ssml"])

    def test_lexicon_file_is_valid_and_every_entry_is_inert_markup(self):
        revision, entries = az.load_lexicon()
        self.assertTrue(revision)
        self.assertTrue({"Sarosh", "Penske", "Forman"} <= set(entries))

    def test_hostile_lexicon_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            for ipa in ('a"b', "a<b", "a&b", "a'b", "", "x" * 61):
                path = Path(tmp) / "lex.json"
                path.write_text(json.dumps({"revision": "r", "alphabet": "ipa", "entries": {"Name": {"ipa": ipa}}}),
                                encoding="utf-8")
                with self.assertRaises(RuntimeError, msg=repr(ipa)):
                    az.load_lexicon(path)
            path.write_text(json.dumps({"revision": "r", "alphabet": "ipa",
                                        "entries": {"bad name": {"ipa": "abc"}}}), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                az.load_lexicon(path)
            path.write_text(json.dumps({"revision": "r", "alphabet": "arpabet",
                                        "entries": {"Name": {"ipa": "abc"}}}), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                az.load_lexicon(path)

    def test_quote_fails_closed_when_the_lexicon_is_hostile(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "lex.json"
            path.write_text(json.dumps({"revision": "r", "alphabet": "ipa",
                                        "entries": {"Sarosh": {"ipa": 'x"/><audio src="y'}}}), encoding="utf-8")
            with patch.object(az, "LEXICON_PATH", path):
                with self.assertRaises(RuntimeError):
                    az.quote("Sarosh spoke.", pronunciations=["Sarosh"], **KW)


if __name__ == "__main__":
    unittest.main()
