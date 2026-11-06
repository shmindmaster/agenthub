#!/usr/bin/env python3
"""Picture-relevance gate: every scene's on-screen content must come from what its line says.

    check_picture_relevance.py <props-or-picture-plan.json> <cue-sheet-or-screenplay.json> [--min-overlap 2] [--out PATH]

Free and offline. Run it on the picture plan and the screenplay BEFORE any voice or image spend (a cue sheet and built props work too). For each scene it takes the
words of the scene's visual body and bullets (the title and kicker do not count: a label is not content) and the words of
the narration line with the same id, drops filler words, and counts the shared content words and numbers. A scene with
fewer than --min-overlap shared terms fails, and so does a scene with no visual body at all. Exits 1 on any failure.

This catches what the frame checks cannot: a perfectly clean frame that shows nothing about the topic (speaker cards with a
headline, a generic title slide). It does not judge design quality, layout or taste; the review vision pass owns that.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

STOP = set("""a an and are as at be been but by can could did do does for from had has have he her his i if in into is it its
just me my no not of on or our out she so than that the their them then there these they this those to up us was we were
what when where which who why will with would you your yours am about also all any more most some such only own same too
very how now one two once again here s t don should shall may might must let""".split())
SKIP_KEYS = {"kind", "src", "mark", "revealFrom", "at", "lang", "viewBox", "form", "unit", "max", "loop", "playbackRate", "layout", "focus", "lane", "size", "quality", "seconds"}


def tokens(text):
    out = []
    for t in re.findall(r"[A-Za-z0-9][A-Za-z0-9'%-]*", (text or "").lower()):
        t = t.strip("'-").replace("%", "")
        t = re.sub(r"'s$", "", t)
        if not t or t in STOP:
            continue
        if t.isdigit() or len(t) >= 3:
            out.append(t)
    return out


def svg_text(markup):
    """Only the words a viewer can read in an SVG fragment: text between tags, never tag or attribute names."""
    return " ".join(t.strip() for t in re.findall(r">([^<>]+)<", f">{markup}<") if t.strip())


def _strings(node, skip=SKIP_KEYS):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for k, v in node.items():
            if k == "svg" and isinstance(v, str):
                yield svg_text(v)
            elif k not in skip:
                yield from _strings(v, skip)
    elif isinstance(node, list):
        for v in node:
            yield from _strings(v, skip)


def scene_content_text(scene):
    """The words a viewer reads that carry content: the visual body and bullets, never the title or kicker."""
    parts = list(_strings(scene.get("visual") or {}))
    parts += [b.get("text", "") for b in scene.get("bullets") or [] if isinstance(b, dict)]
    return " ".join(parts)


def judge_scene(scene, narration, min_overlap=2):
    content = scene_content_text(scene)
    if not content.strip():
        return {"id": scene.get("id"), "ok": False, "overlap": [], "reasons": ["no visual body: a title alone shows nothing"]}
    shared = sorted(set(tokens(content)) & set(tokens(narration)))
    ok = len(shared) >= min_overlap
    reasons = [] if ok else [f"only {len(shared)} shared term(s), need {min_overlap}"]
    return {"id": scene.get("id"), "ok": ok, "overlap": shared, "reasons": reasons}


def load_lines(path):
    """Narration by scene id from a cue sheet ({cues:[{id,text}]}) or a screenplay ({scenes:[{id,narration}]})."""
    data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if data.get("cues"):
        return {c["id"]: c.get("text", "") for c in data["cues"]}
    return {s["id"]: s.get("narration", "") for s in data.get("scenes") or []}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("props")
    ap.add_argument("cues")
    ap.add_argument("--min-overlap", type=int, default=2)
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    scenes = json.loads(Path(args.props).read_text(encoding="utf-8")).get("scenes") or []
    cues = load_lines(Path(args.cues))
    results = []
    for sc in scenes:
        if sc.get("id") not in cues:
            results.append({"id": sc.get("id"), "ok": False, "overlap": [], "reasons": ["no narration line with this id"]})
        else:
            results.append(judge_scene(sc, cues[sc["id"]], args.min_overlap))
    missing = [i for i in cues if i not in {s.get("id") for s in scenes}]
    for i in missing:
        results.append({"id": i, "ok": False, "overlap": [], "reasons": ["narration line has no scene"]})
    report = {"schema": "media-studio/picture-relevance/1", "minOverlap": args.min_overlap,
              "ok": bool(results) and all(r["ok"] for r in results), "scenes": results}
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for r in results:
        print(f"{'PASS' if r['ok'] else 'FAIL'} {r['id']}: {', '.join(r['overlap'][:6]) or '-'}" + ("" if r["ok"] else "  <- " + "; ".join(r["reasons"])))
    print("RESULT:", "ok" if report["ok"] else "FAILED")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
