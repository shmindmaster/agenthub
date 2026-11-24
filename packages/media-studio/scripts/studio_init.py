#!/usr/bin/env python3
"""Start a production: one workspace per film, laid out by filmmaking phase, with a state file and templates.

    studio_init.py "<title>" [--root D:/Media-Studio] [--kind briefing] [--identity mahumtech] [--deliverable silent-video] [--requirements] [--force]

Creates <root>/<slug>-<yyyymmdd>/ with case/, story/, plan/, voice/, takes/, picture/, assets/, qa/, review/, out/ and writes
production.json (phase approvals), job.json (the contract every later script reads) and starter templates:

  case/case.md            the case: audience, promise, logline, stakes, tone, constraints   (develop)
  story/treatment.md      the story in prose                                               (develop)
  story/beat-sheet.json   the beats and what each is for                                   (develop)
  story/screenplay.json   scenes: id, speaker, narration                                   (develop)
  story/picture-plan.json one picture per scene, with word anchors                         (pre-production)

--deliverable records job.json `deliverable` (narrated-video, silent-video, audio, stills, storyboard) so the status asks only for what
that form produces. --requirements scaffolds story/requirements.json with TODO fields; fill it from the brief and run
check_requirements.py. Without either flag the scaffold is unchanged.

Nothing outside the new folder is touched. The product repositories stay read-only inputs. Free and offline.
"""
from __future__ import annotations

import argparse
from datetime import date
import json
import os
from pathlib import Path
import re
import sys

FORMS = ("narrated-video", "silent-video", "audio", "stills", "storyboard")
DIRS = ["case", "story", "plan", "voice", "takes", "picture", "assets", "qa", "review", "out"]
APPROVALS = ["case", "screenplay", "plan", "delivered"]

CASE = """# Case: {title}

## Audience
TODO who watches, where it plays, what they already know

## Promise
TODO what the viewer can do or stop doing after the film (one sentence)

## Logline
TODO one sentence: who, wants what, against what, with what at stake

## Why it matters now
TODO the stakes, in the viewer's terms

## Tone and form
TODO tone; form and length; voices

## Facts and sources
TODO each locked fact and where it comes from

## Names to pronounce
TODO every person, brand and acronym said aloud

## Constraints
TODO what is out of scope, what must not be shown or said

## Success check
TODO what the owner sees in the first five seconds and at the end
"""
TREATMENT = """# Treatment: {title}

TODO the story in present-tense prose, 150 to 400 words: the opening image, the turn, the proof, the close.
"""
BEATS = {"schema": "media-studio/beat-sheet/1", "beats": [
    {"id": "b1", "role": "hook", "summary": "TODO the opening that carries the pain or the payoff", "picture": "TODO what the viewer sees"},
    {"id": "b2", "role": "tension", "summary": "TODO", "picture": "TODO"},
    {"id": "b3", "role": "payoff", "summary": "TODO", "picture": "TODO"}]}
SCREENPLAY = {"title": "{title}", "kind": "{kind}", "scenes": [{"id": "s1", "speaker": "narrator", "narration": "TODO"}]}
REQUIREMENTS = {"schema": "media-studio/requirements/1", "narrationLanguage": "TODO", "uiLanguage": "TODO",
                "durationSeconds": {"min": 0, "max": 0}, "aspect": "16x9", "finalHoldSeconds": 0, "cta": {"required": False},
                "requirements": [{"id": "r1", "type": "feature", "text": "TODO what the brief asked for", "scenes": ["s1"],
                                  "match": ["TODO"], "evidence": "narration", "check": "TODO how it is checked"}]}


def requirements_scaffold(deliverable=None):
    """Only the fields the form can be checked against: no aspect or final hold for audio, no hold or duration for stills."""
    r = json.loads(json.dumps(REQUIREMENTS))
    drop = {"audio": ("aspect", "finalHoldSeconds"), "stills": ("finalHoldSeconds", "durationSeconds")}.get(deliverable, ())
    for k in drop:
        r.pop(k, None)
    return r


PICTURE_PLAN = {"scenes": [{"id": "s1", "kicker": "", "title": "TODO", "accent": "#3DDC84", "visual": {"kind": "svg", "groups": []}}]}


def slugify(s):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", s.lower())).strip("-")[:48] or "film"


def init(title, root, kind="briefing", identity="mahumtech", force=False, today=None, deliverable=None, requirements=False):
    if deliverable and deliverable not in FORMS:
        raise SystemExit(f"unknown deliverable '{deliverable}'; one of {', '.join(FORMS)}")
    if deliverable and kind == "audio-only" and deliverable != "audio":
        raise SystemExit(f"kind audio-only cannot deliver '{deliverable}'")
    stamp = (today or date.today()).strftime("%Y%m%d")
    work = Path(root) / f"{slugify(title)}-{stamp}"
    if work.exists() and any(work.iterdir()) and not force:
        raise SystemExit(f"{work} already exists and is not empty; pass --force only to add missing files")
    for d in DIRS:
        (work / d).mkdir(parents=True, exist_ok=True)

    def put(rel, text):
        p = work / rel
        if not p.exists():
            p.write_text(text, encoding="utf-8")

    fmt = lambda o: json.loads(json.dumps(o).replace("{title}", title).replace("{kind}", kind))
    put("case/case.md", CASE.format(title=title))
    put("story/treatment.md", TREATMENT.format(title=title))
    put("story/beat-sheet.json", json.dumps(BEATS, indent=2) + "\n")
    put("story/screenplay.json", json.dumps(fmt(SCREENPLAY), indent=2) + "\n")
    put("story/picture-plan.json", json.dumps(PICTURE_PLAN, indent=2) + "\n")
    put("production.json", json.dumps({"schema": "media-studio/production/1", "title": title, "slug": work.name, "kind": kind,
                                       "identity": identity, "created": stamp, "approvals": {a: None for a in APPROVALS}}, indent=2) + "\n")
    job = {"kind": kind, "title": title, "workspace": str(work.resolve()).replace(os.sep, "/"),
           "repositoryWritePolicy": "read-only", "intent": "viewer-facing", "craftScoreMin": 85}
    if deliverable:
        job["deliverable"] = deliverable
    put("job.json", json.dumps(job, indent=2) + "\n")
    if requirements:
        put("story/requirements.json", json.dumps(requirements_scaffold(deliverable), indent=2) + "\n")
    return work


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("title")
    ap.add_argument("--root", default=os.environ.get("MEDIA_STUDIO_ROOT", "D:/Media-Studio"))
    ap.add_argument("--kind", default="briefing")
    ap.add_argument("--identity", default="mahumtech", choices=["mahumtech", "abacare", "any"])
    ap.add_argument("--deliverable", choices=FORMS)
    ap.add_argument("--requirements", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args(argv)
    work = init(a.title, a.root, a.kind, a.identity, a.force, deliverable=a.deliverable, requirements=a.requirements)
    print(f"created {work}")
    print("next: fill case/case.md, then run: py -3 scripts/production_status.py", str(work))
    return 0


if __name__ == "__main__":
    sys.exit(main())
