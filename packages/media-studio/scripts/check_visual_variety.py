#!/usr/bin/env python3
"""Report picture variety and repeated sources for editorial review.

    check_visual_variety.py <briefing-props.json> [--min-picture 0.4] [--max-text 0.25] [--max-same 0.4] [--out PATH]

Free and offline. Run it on the storyboard's props BEFORE rendering. Every scene's visual kind falls in one class:

  picture       a drawing, motion, real image or captured screen: flow, layers, sequence, timeline, beforeafter, map,
                chart, svg, lottie, still, broll, screen-in-context, code
  typographic   words arranged as a figure: stat, table, split, proof
  text          words on a card: hero, quote, checklist, cta, sidecar, chapter, lower-third (or no visual)

Flags when: fewer than --min-picture of the scenes are pictures; more than --max-text are text cards; three scenes in a
row are not pictures; one visual kind fills more than --max-same of a program of five or more scenes;
or a picture source returns without a documented editorial purpose.

This counts what kind of thing is on screen. check_picture_relevance.py judges whether it is about the line, and the
review vision pass judges whether it looks good. Use --enforce-style when the brief requires these thresholds.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import posixpath
import sys
from urllib.parse import urlsplit, urlunsplit

PICTURE = {"flow", "layers", "sequence", "timeline", "beforeafter", "map", "chart", "svg", "lottie", "still", "broll", "screen-in-context", "code"}
TYPOGRAPHIC = {"stat", "table", "split", "proof"}
SOURCE_KINDS = {"broll", "still", "screen-in-context"}


def repeated_sources(scenes):
    first_use = {}
    for scene in scenes:
        visual = scene.get("visual") or {}
        if visual.get("kind") not in SOURCE_KINDS:
            continue
        keys = []
        asset = visual.get("sourceAssetId")
        if isinstance(asset, str) and asset.strip():
            keys.append(("asset", asset.strip()))
        src = visual.get("src")
        if isinstance(src, str) and src.strip():
            # Ignore cache keys and relative-path spellings when identifying source footage.
            url = urlsplit(src.strip().replace("\\", "/"))
            source = urlunsplit((url.scheme, url.netloc, posixpath.normpath(url.path or "/"), "", ""))
            keys.append(("path", source))
        previous = next((key for key in keys if key in first_use), None)
        reason = visual.get("reuseReason")
        if previous and (not isinstance(reason, str) or not reason.strip()):
            yield f"scene {scene.get('id')} reuses {previous[1]} from {first_use[previous]} without a visual reuseReason"
        for key in keys:
            first_use.setdefault(key, scene.get("id"))


def classify(scene):
    kind = (scene.get("visual") or {}).get("kind")
    if kind in PICTURE:
        return "picture"
    if kind in TYPOGRAPHIC:
        return "typographic"
    return "text"


def judge(scenes, min_picture=0.4, max_text=0.25, max_same=0.4, *, enforce_style=False):
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
    reasons.extend(repeated_sources(scenes))
    return {"ok": not (enforce_style and reasons), "reasons": reasons if enforce_style else [],
            "advisories": [] if enforce_style else reasons, "classes": classes, "kinds": kinds,
            "counts": {c: classes.count(c) for c in ("picture", "typographic", "text")}, "pictureShare": round(pic, 3), "textShare": round(txt, 3)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("props")
    ap.add_argument("--min-picture", type=float, default=0.4)
    ap.add_argument("--max-text", type=float, default=0.25)
    ap.add_argument("--max-same", type=float, default=0.4)
    ap.add_argument("--enforce-style", action="store_true")
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    scenes = json.loads(Path(args.props).read_text(encoding="utf-8")).get("scenes") or []
    rep = judge(scenes, args.min_picture, args.max_text, args.max_same, enforce_style=args.enforce_style)
    rep = {"schema": "media-studio/visual-variety/1", **rep}
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
    print("scenes:", ", ".join(f"{s.get('id')}={k}/{c}" for s, k, c in zip(scenes, rep.get("kinds", []), rep["classes"])))
    print("counts:", rep["counts"])
    for r in rep["reasons"]:
        print("FAIL:", r)
    for note in rep.get("advisories", []):
        print("REVIEW:", note)
    print("RESULT:", "ok" if rep["ok"] else "FAILED")
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
