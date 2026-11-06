#!/usr/bin/env python3
"""Words-only gate: a film must show things, not just present words well.

    check_visual_variety.py <briefing-props.json> [--min-picture 0.4] [--max-text 0.25] [--max-same 0.4] [--out PATH]

Free and offline. Run it on the storyboard's props BEFORE rendering. Every scene's visual kind falls in one class:

  picture       a drawing, motion, real image or captured screen: flow, layers, sequence, timeline, beforeafter, map,
                chart, svg, lottie, still, broll, screen-in-context, code
  typographic   words arranged as a figure: stat, table, split, proof
  text          words on a card: hero, quote, checklist, cta, sidecar, chapter, lower-third (or no visual)

Fails when: fewer than --min-picture of the scenes are pictures; more than --max-text are text cards; three scenes in a
row are not pictures; or one visual kind fills more than --max-same of a run of five or more scenes.

This counts what kind of thing is on screen. check_picture_relevance.py judges whether it is about the line, and the
review vision pass judges whether it looks good. Passing here proves variety, not quality.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

PICTURE = {"flow", "layers", "sequence", "timeline", "beforeafter", "map", "chart", "svg", "lottie", "still", "broll", "screen-in-context", "code"}
TYPOGRAPHIC = {"stat", "table", "split", "proof"}


def classify(scene):
    kind = (scene.get("visual") or {}).get("kind")
    if kind in PICTURE:
        return "picture"
    if kind in TYPOGRAPHIC:
        return "typographic"
    return "text"


def judge(scenes, min_picture=0.4, max_text=0.25, max_same=0.4):
    n = len(scenes)
    classes = [classify(s) for s in scenes]
    kinds = [(s.get("visual") or {}).get("kind") or "none" for s in scenes]
    reasons = []
    if n == 0:
        return {"ok": False, "reasons": ["no scenes"], "classes": [], "counts": {}}
    pic = classes.count("picture") / n
    txt = classes.count("text") / n
    if pic < min_picture:
        reasons.append(f"only {pic:.0%} of scenes are pictures, need {min_picture:.0%}")
    if txt > max_text:
        reasons.append(f"{txt:.0%} of scenes are text cards, limit {max_text:.0%}")
    run = 0
    for i, c in enumerate(classes):
        run = run + 1 if c != "picture" else 0
        if run == 3:
            reasons.append(f"scenes {scenes[i - 2].get('id')}..{scenes[i].get('id')} are three in a row with no picture")
    if n >= 5:
        for k in sorted(set(kinds)):
            if kinds.count(k) / n > max_same:
                reasons.append(f"'{k}' fills {kinds.count(k)} of {n} scenes, limit {max_same:.0%}")
    return {"ok": not reasons, "reasons": reasons, "classes": classes, "kinds": kinds,
            "counts": {c: classes.count(c) for c in ("picture", "typographic", "text")}, "pictureShare": round(pic, 3), "textShare": round(txt, 3)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("props")
    ap.add_argument("--min-picture", type=float, default=0.4)
    ap.add_argument("--max-text", type=float, default=0.25)
    ap.add_argument("--max-same", type=float, default=0.4)
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    scenes = json.loads(Path(args.props).read_text(encoding="utf-8")).get("scenes") or []
    rep = judge(scenes, args.min_picture, args.max_text, args.max_same)
    rep = {"schema": "media-studio/visual-variety/1", **rep}
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
    print("scenes:", ", ".join(f"{s.get('id')}={k}/{c}" for s, k, c in zip(scenes, rep.get("kinds", []), rep["classes"])))
    print("counts:", rep["counts"])
    for r in rep["reasons"]:
        print("FAIL:", r)
    print("RESULT:", "ok" if rep["ok"] else "FAILED")
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
