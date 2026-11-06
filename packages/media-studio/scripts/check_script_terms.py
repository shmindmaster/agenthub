#!/usr/bin/env python3
"""Upfront term gate: refuse to synthesize a script that holds a name, acronym or brand nobody has decided how to say.

    check_script_terms.py <locked-script.txt> [--lexicon PATH] [--json]

Free and offline. Run it on the locked script BEFORE any paid speech call. Every flagged term must be either

  * an entry in pronunciation_lexicon.json "entries" (pinned IPA; pass the printed `pin` list to
    governed_azure_speech.generate(pronunciations=...)), or
  * listed in the lexicon's "plain" array (an ordinary word or common first name the voice reads correctly by default).

Anything else is unresolved and the script exits 1, so spend never starts with an undecided term. This is a heuristic
reader, not a dictionary: it flags ALL-CAPS acronyms, single stray capitals (Schedule K), internal capitals (FedEx),
capitalized words inside a sentence, and a capitalized word opening a sentence only when a comma follows it (a name
being addressed). It cannot see an ordinary lowercase word the voice reads wrongly; the post-synthesis check
(check_name_pronunciation.py) is the verifier for that, and for whether a pinned entry actually came out right.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

LEXICON_PATH = Path(__file__).with_name("pronunciation_lexicon.json")
_TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9'’-]*")
_ALWAYS_OK = {"I", "A", "I'm", "I'll", "I've", "I'd", "I’m", "I’ll", "I’ve", "I’d"} | {
    "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
    "December", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}


_OPENERS = {"Both", "Then", "Yes", "No", "Well", "Okay", "Also", "However", "First", "Second", "Third", "Finally",
            "Sure", "Thanks", "Please", "Meanwhile", "Still", "Next", "Today", "Now", "So", "And", "But", "Right"}


def _base(term):
    return re.sub(r"['’]s$", "", term)


def find_terms(text):
    """Return [{term, kind, line, count}] for every token that needs a decision, in first-seen order."""
    found = {}
    for lineno, line in enumerate(text.splitlines(), 1):
        for m in _TOKEN.finditer(line):
            tok = _base(m.group(0)).strip("-'’")
            if not tok or tok in _ALWAYS_OK:
                continue
            before = line[: m.start()].rstrip()
            starts_sentence = not before or before[-1] in ".?!:\"“"
            after = line[m.end():].lstrip()
            kind = None
            if len(tok) >= 2 and tok.isalpha() and tok.isupper():
                kind = "acronym"
            elif len(tok) == 1 and tok.isupper():
                kind = "single capital"
            elif re.search(r"[a-z][A-Z]", tok):
                kind = "internal capital"
            elif tok[0].isupper() and not starts_sentence:
                kind = "capitalized in sentence"
            elif tok[0].isupper() and starts_sentence and after.startswith(",") and tok not in _OPENERS:
                kind = "addressed name"
            if kind:
                rec = found.setdefault(tok, {"term": tok, "kind": kind, "line": lineno, "count": 0})
                rec["count"] += 1
    return list(found.values())


def resolve(terms, lexicon):
    entries = set((lexicon.get("entries") or {}))
    plain = set(lexicon.get("plain") or [])
    pin, unresolved = [], []
    for t in terms:
        if t["term"] in entries:
            pin.append(t["term"])
        elif t["term"] not in plain:
            unresolved.append(t)
    return sorted(pin), unresolved


def pinned_in_text(text, lexicon):
    """Lexicon names present anywhere in the text, including sentence openers the heuristic cannot classify."""
    return sorted(n for n in (lexicon.get("entries") or {}) if re.search(r"(?<![A-Za-z0-9'-])" + re.escape(n) + r"(?![A-Za-z0-9'-])", text))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("script")
    ap.add_argument("--lexicon", default=str(LEXICON_PATH))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    lexicon = json.loads(Path(args.lexicon).read_text(encoding="utf-8"))
    text = Path(args.script).read_text(encoding="utf-8")
    terms = find_terms(text)
    pin, unresolved = resolve(terms, lexicon)
    pin = sorted(set(pin) | set(pinned_in_text(text, lexicon)))
    report = {"lexiconRevision": lexicon.get("revision"), "checked": len(terms), "pin": pin, "unresolved": unresolved,
              "ok": not unresolved}
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(f"{len(terms)} terms need a decision; pin={pin or 'none'}")
        for u in unresolved:
            print(f"UNRESOLVED  {u['term']}  ({u['kind']}, line {u['line']}, x{u['count']})")
        if unresolved:
            print("Add each to pronunciation_lexicon.json as an entry (pinned IPA) or to \"plain\", then rerun. No speech call may start.")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
