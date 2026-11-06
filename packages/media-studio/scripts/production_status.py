#!/usr/bin/env python3
"""Where a production stands, phase by phase, and what the next action is.

    production_status.py <jobRoot> [--json] [--strict]
    production_status.py <jobRoot> --approve case|screenplay|plan|delivered      (record the owner's yes)

The filmmaking phases, each with deliverables a file proves:

  develop         case.md, treatment.md, beat-sheet.json, screenplay.json, narration check, owner approves case and screenplay
  preproduction   breakdown.json (cast, assets, budget, schedule), picture plan, relevance and variety gates, owner approves the plan
  production      voice takes for every scene, cue sheet, built props, rendered picture
  post            the finished file, word sync, frame integrity, the review verdict
  delivery        captions sidecar and the owner's delivered record

A phase is PASS, FAIL (its own checks fail) or BLOCKED (an earlier phase has not passed). Files are evidence, not claims: a
placeholder (TODO) is a fail, a report older than the thing it checks is stale, a missing approval is a fail. --approve records
`approvals.<name>` with today's date; run it only after the owner has said yes in the conversation. Free and offline; never calls
a provider. Exit 0 always, 1 with --strict when any phase is not PASS.
"""
from __future__ import annotations

import argparse
from datetime import date
import json
from pathlib import Path
import re
import sys

PHASES = ["develop", "preproduction", "production", "post", "delivery"]
NEXT = {
    "develop": "Use the develop skill: fill the case, treatment, beat sheet and screenplay, run validate-narration.mjs, then ask the owner to approve.",
    "preproduction": "Use the plan skill: write the picture plan, run screenplay_breakdown.py, check_picture_relevance.py and check_visual_variety.py, show the owner the picture table and the cost.",
    "production": "Use generate, visuals and compose: voice takes, assets, build-picture.mjs, render the picture.",
    "post": "Use compose and review: mix, finish loudness, run the gates on the exact file, review the frames.",
    "delivery": "Use compose to deliver: captions sidecar and library copy, then record the owner's delivered approval.",
}


def jload(p):
    return json.loads(Path(p).read_text(encoding="utf-8-sig"))


def ok_report(p):
    if not p.exists():
        return f"missing {p.name}"
    try:
        r = jload(p)
    except Exception:
        return f"{p.name} is not valid JSON"
    return None if r.get("ok") is True or r.get("pass") is True else f"{p.name} did not pass"


def newer(a, b):
    return a.exists() and b.exists() and a.stat().st_mtime + 1 < b.stat().st_mtime


def has_todo(p):
    return "TODO" in p.read_text(encoding="utf-8")


def section(text, name):
    m = re.search(rf"^##\s+{re.escape(name)}\s*\n(.*?)(?=^##\s|\Z)", text, re.M | re.S)
    return (m.group(1).strip() if m else "")


def check_develop(root, prod):
    r = []
    case = root / "case/case.md"
    if not case.exists():
        r.append("missing case/case.md")
    else:
        t = case.read_text(encoding="utf-8")
        if "TODO" in t:
            r.append("case/case.md still has TODO")
        for h in ("Audience", "Promise", "Logline", "Names to pronounce", "Success check"):
            if len(section(t, h)) < 3:
                r.append(f"case/case.md section '{h}' is empty")
    tr = root / "story/treatment.md"
    if not tr.exists():
        r.append("missing story/treatment.md")
    elif has_todo(tr) or len(tr.read_text(encoding="utf-8").split()) < 80:
        r.append("story/treatment.md is a placeholder or under 80 words")
    bs = root / "story/beat-sheet.json"
    if not bs.exists():
        r.append("missing story/beat-sheet.json")
    else:
        beats = jload(bs).get("beats") or []
        if len(beats) < 3 or any(not (b.get("id") and b.get("role") and b.get("summary") and b.get("picture")) for b in beats) or "TODO" in bs.read_text(encoding="utf-8"):
            r.append("story/beat-sheet.json needs 3+ beats with id, role, summary and picture, and no TODO")
    sp = root / "story/screenplay.json"
    if not sp.exists():
        r.append("missing story/screenplay.json")
    else:
        sc = jload(sp).get("scenes") or []
        ids = [s.get("id") for s in sc]
        if not sc or any(not (s.get("narration") or "").strip() for s in sc) or "TODO" in sp.read_text(encoding="utf-8"):
            r.append("story/screenplay.json has no scenes, an empty line or a TODO")
        if len(ids) != len(set(ids)):
            r.append("story/screenplay.json has duplicate scene ids")
        if sp.exists() and newer(root / "qa/narration-check.json", sp):
            r.append("qa/narration-check.json is older than the screenplay: rerun validate-narration.mjs")
    e = ok_report(root / "qa/narration-check.json")
    if e:
        r.append(e)
    for a in ("case", "screenplay"):
        if not prod["approvals"].get(a):
            r.append(f"owner has not approved the {a}")
    return r


def check_pre(root, prod):
    r = []
    bd = root / "plan/breakdown.json"
    e = ok_report(bd)
    if e:
        r.append(e)
    elif newer(bd, root / "story/screenplay.json") or newer(bd, root / "story/picture-plan.json"):
        r.append("plan/breakdown.json is older than the screenplay or picture plan: rerun screenplay_breakdown.py")
    pp = root / "story/picture-plan.json"
    if not pp.exists() or "TODO" in pp.read_text(encoding="utf-8"):
        r.append("story/picture-plan.json is missing or a placeholder")
    for rep in ("qa/picture-relevance.json", "qa/visual-variety.json"):
        e = ok_report(root / rep)
        if e:
            r.append(e)
        elif newer(root / rep, pp):
            r.append(f"{rep} is older than the picture plan: rerun the gate")
    job = jload(root / "job.json") if (root / "job.json").exists() else {}
    if job.get("intent") == "viewer-facing":
        for need in ("story/storyboard.json", "story/visual-bible.json"):
            if not (root / need).exists():
                r.append(f"viewer-facing job needs {need}")
    if not prod["approvals"].get("plan"):
        r.append("owner has not approved the plan (picture table and cost)")
    return r


def check_prod(root, prod):
    r = []
    sp = root / "story/screenplay.json"
    ids = [s["id"] for s in jload(sp).get("scenes", [])] if sp.exists() else []
    gone = [i for i in ids if not (root / "takes" / f"{i}.receipt.json").exists()]
    if gone:
        r.append(f"no voice take for scene(s): {', '.join(gone[:6])}")
    if not (root / "story/cue-sheet.json").exists():
        r.append("missing story/cue-sheet.json")
    e = ok_report(root / "picture/briefing-props.report.json")
    if e:
        r.append(e)
    if not (root / "picture/video.mp4").exists():
        r.append("missing picture/video.mp4")
    return r


def check_post(root, prod):
    r = []
    mp4s = sorted((root / "out").glob("*.mp4"), key=lambda p: p.stat().st_mtime) if (root / "out").exists() else []
    if not mp4s:
        r.append("no finished file in out/")
    for rep in ("qa/word-sync.json", "qa/frame-integrity.json"):
        e = ok_report(root / rep)
        if e:
            r.append(e)
        elif mp4s and newer(root / rep, mp4s[-1]):
            r.append(f"{rep} is older than the finished file: rerun the gate on it")
    job = jload(root / "job.json") if (root / "job.json").exists() else {}
    if job.get("intent") == "viewer-facing":
        e = ok_report(root / "qa/story-experience-review.json")
        if e:
            r.append(e)
    return r


def check_delivery(root, prod):
    r = []
    if not list((root / "out").glob("*.srt")):
        r.append("no captions sidecar (.srt) in out/")
    if not prod["approvals"].get("delivered"):
        r.append("owner has not recorded delivery")
    return r


CHECKS = {"develop": check_develop, "preproduction": check_pre, "production": check_prod, "post": check_post, "delivery": check_delivery}


def status(root):
    root = Path(root)
    prod = jload(root / "production.json")
    prod.setdefault("approvals", {})
    out, blocked = [], False
    for ph in PHASES:
        if blocked:
            out.append({"phase": ph, "state": "BLOCKED", "reasons": ["an earlier phase has not passed"]})
            continue
        reasons = CHECKS[ph](root, prod)
        out.append({"phase": ph, "state": "PASS" if not reasons else "FAIL", "reasons": reasons})
        blocked = bool(reasons)
    cur = next((p for p in out if p["state"] != "PASS"), None)
    return {"title": prod.get("title"), "phases": out, "current": cur["phase"] if cur else None,
            "next": NEXT[cur["phase"]] if cur else "All phases pass.", "complete": cur is None}


def approve(root, name):
    p = Path(root) / "production.json"
    prod = jload(p)
    if name not in prod.get("approvals", {}):
        raise SystemExit(f"unknown approval '{name}'; one of {', '.join(prod.get('approvals', {}))}")
    prod["approvals"][name] = date.today().isoformat()
    p.write_text(json.dumps(prod, indent=2) + "\n", encoding="utf-8")
    return prod["approvals"]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("job")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--approve")
    a = ap.parse_args(argv)
    if a.approve:
        print("approvals:", approve(a.job, a.approve))
        return 0
    s = status(a.job)
    if a.json:
        print(json.dumps(s, indent=2))
    else:
        print(f"{s['title']}")
        for p in s["phases"]:
            print(f"  {p['state']:7} {p['phase']}")
            for r in p["reasons"][:6]:
                print(f"            - {r}")
        print("next:", s["next"])
    return 1 if (a.strict and not s["complete"]) else 0


if __name__ == "__main__":
    sys.exit(main())
