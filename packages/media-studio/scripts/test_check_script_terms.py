"""Offline tests for the upfront term gate."""
import unittest

import check_script_terms as gate

LEX = {"entries": {"Sarosh": {"ipa": "x"}, "FedEx": {"ipa": "y"}}, "plain": ["Debbie", "K"]}


def kinds(text):
    return {t["term"]: t["kind"] for t in gate.find_terms(text)}


class TermTests(unittest.TestCase):
    def test_flags_each_kind(self):
        k = kinds("Sarosh, call the FAQ team about Schedule K and FedEx. We met Penske on Monday.")
        self.assertEqual(k["Sarosh"], "addressed name")
        self.assertEqual(k["FAQ"], "acronym")
        self.assertEqual(k["K"], "single capital")
        self.assertEqual(k["FedEx"], "internal capital")
        self.assertEqual(k["Penske"], "capitalized in sentence")
        self.assertEqual(k["Schedule"], "capitalized in sentence")
        self.assertNotIn("Monday", k)

    def test_ordinary_sentence_start_and_pronoun_i_are_not_flagged(self):
        self.assertEqual(kinds("Then I went home. The answer came late. A plan helps."), {})

    def test_possessive_maps_to_the_base_term(self):
        self.assertIn("Penske", kinds("We used Penske's trucks."))

    def test_resolution_splits_pinned_plain_and_unresolved(self):
        terms = gate.find_terms("Sarosh, tell Debbie the FAQ is on FedEx with Schedule K.")
        pin, unresolved = gate.resolve(terms, LEX)
        self.assertEqual(pin, ["FedEx", "Sarosh"])
        self.assertEqual(sorted(u["term"] for u in unresolved), ["FAQ", "Schedule"])

    def test_lexicon_names_are_found_even_when_they_open_a_sentence(self):
        text = "Penske declined. Call Sarosh."
        self.assertEqual(gate.pinned_in_text(text, {"entries": {"Penske": {}, "Sarosh": {}, "Forman": {}}}),
                         ["Penske", "Sarosh"])

    def test_counts_repeats(self):
        t = gate.find_terms("Call Penske. Then call Penske again.")
        self.assertEqual(t[0]["count"], 2)


if __name__ == "__main__":
    unittest.main()
