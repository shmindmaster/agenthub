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

A phase is PASS, FAIL (its own checks fail), BLOCKED (an earlier phase has not passed) or NOT_REQUIRED (nothing in it applies to the deliverable). Files are evidence, not claims: a
placeholder (TODO) is a fail, a report older than the thing it checks is stale, a missing required approval is a fail. --approve records
`approvals.<name>` with today's date; run it only after the owner has said yes in the conversation. A job may declare `deliverable` (narrated-video, silent-video, audio, stills, storyboard) in job.json; each form requires only
what it produces (references/phases.md), and a phase none of whose checks apply is NOT_REQUIRED and counts as complete. Undeclared
jobs derive narrated-video, or audio for kind audio-only. When story/requirements.json exists, develop needs a passing, fresh
qa/requirements-check.json and post needs it run on the current finished file plus a passing qa/finished-film.json. Free and offline; never calls
a provider. Record explicit internal delegation with reviewAuthority "delegated" in production.json. Keep owner
review for any named requiredReviews. This status does not authorize spend or external publication. Exit 0 always, 1 with --strict when any phase is not PASS.
"""
from __future__ import annotations

import argparse
import hashlib
from datetime import date
import json
from pathlib import Path
import re
import sys

import check_requirements as creq

INTERNAL_REVIEWS = ("case", "screenplay", "plan", "delivered")
PHASES = ["develop", "preproduction", "production", "post", "delivery"]
REVIEW_STAGES = {"develop": "Go/No-Go", "preproduction": "Pink", "production": "Red", "post": "Gold", "delivery": "Gold"}
NEXT = {
    "develop": "Use the script skill: fill the case, treatment, beat sheet and screenplay, run validate-narration.mjs, then resolve any required review.",
    "preproduction": "Use the script skill: write the picture plan, run screenplay_breakdown.py, check_picture_relevance.py and check_visual_variety.py, resolve required review and any spend approvals.",
    "production": "Use produce, then finish: voice takes, assets, build-picture.mjs, render the picture.",
    "post": "Use the finish skill: mix, finish loudness, run the gates on the exact file, review the frames.",
    "delivery": "Use the finish skill to deliver: captions sidecar and library copy, then resolve any required internal delivery review.",
}


FORMS = ("narrated-video", "silent-video", "audio", "stills", "storyboard")
PICTURE_FORMS = ("narrated-video", "silent-video", "stills", "storyboard")
FINISHED_EXT = {"narrated-video": ("mp4",), "silent-video": ("mp4",), "audio": ("wav", "mp3", "m4a"), "stills": ("png", "jpg", "jpeg", "pdf", "pptx")}
# What a form does not require, per phase. A phase in WHOLE has no applicable check: it is NOT_REQUIRED and never blocks.
NOT_REQUIRED = {
    "narrated-video": {},
    "silent-video": {"develop": ["narration text", "narration check"], "production": ["voice takes", "cue sheet"],
                     "post": ["word sync"], "delivery": ["captions sidecar"]},
    "audio": {"preproduction": ["picture plan", "picture relevance", "visual variety"], "production": ["cue sheet", "props report", "picture video"],
              "post": ["word sync", "frame integrity"], "delivery": ["captions sidecar"]},
    "stills": {"develop": ["narration text", "narration check"], "production": ["voice takes", "cue sheet", "props report", "picture video"],
               "post": ["word sync", "frame integrity", "story experience review"], "delivery": ["captions sidecar"]},
    "storyboard": {"develop": ["narration text", "narration check"], "production": ["voice takes", "cue sheet", "props report", "picture video"],
                   "post": ["finished file", "word sync", "frame integrity"], "delivery": ["captions sidecar", "owner delivery record"]},
}
PHASE_REVIEWS = {"develop": ("case", "screenplay"), "preproduction": ("plan",), "delivery": ("delivered",)}
WHOLE = {"stills": {"production"}, "storyboard": {"production", "post", "delivery"}}


def jload(p):
    return json.loads(Path(p).read_text(encoding="utf-8-sig"))


def deliverable(root):
    """(form, error): job.deliverable, else audio for kind audio-only, else narrated-video."""
    p = Path(root) / "job.json"
    job = jload(p) if p.exists() else {}
    declared = job.get("deliverable")
    if declared is None:
        return ("audio" if job.get("kind") == "audio-only" else "narrated-video"), None
    if declared not in FORMS:
        return None, f"job.json deliverable '{declared}' is not one of {', '.join(FORMS)}"
    if job.get("kind") == "audio-only" and declared in PICTURE_FORMS:
        return None, f"job.json kind audio-only cannot deliver '{declared}', which needs a picture"
    return declared, None


def err_value(root):
    p = Path(root) / "job.json"
    return jload(p).get("deliverable") if p.exists() else None


def form_of(root, form):
    return form or deliverable(root)[0] or "narrated-video"


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


def review_missing(prod, name):
    required = prod.get("requiredReviews", [])
    delegated = (
        prod.get("reviewAuthority") == "delegated"
        and isinstance(required, list)
        and all(item in INTERNAL_REVIEWS for item in required)
        and name not in required
    )
    return not delegated and not prod.get("approvals", {}).get(name)


def requirements_reasons(root, phase):
    """story/requirements.json is a contract. Develop needs a passing, fresh check (the picture plan is not part of that
    freshness), preproduction needs it run on the current picture plan, post needs it run on the current finished file and,
    except for stills, that file's own qa/finished-film.json for this form and these requirements."""
    rp = root / creq.REPORT
    if not (root / creq.REQ).exists():
        return [f"{creq.REQ} removed after {creq.REPORT} was written"] if rp.exists() else []
    if not rp.exists():
        return [f"missing {creq.REPORT}: run check_requirements.py"]
    try:
        rep = jload(rp)
    except Exception:
        return [f"{creq.REPORT} is not valid JSON"]
    if rep.get("ok") is not True:
        return [f"{creq.REPORT} did not pass"]
    recorded = dict(rep.get("inputs") or {})
    review = recorded.pop(creq.REVIEW, None)
    plan = recorded.pop(creq.PLAN, None)
    current = creq.input_hashes(root)
    current_plan = current.pop(creq.PLAN, None)
    if recorded != current or (review is not None and (not (root / creq.REVIEW).is_file() or review != creq.sha256(root / creq.REVIEW))):
        return [f"{creq.REPORT} is stale: the requirements, script or job changed since it ran"]
    if phase == "develop":
        return []
    if current_plan is not None and plan != current_plan:
        return [f"{creq.REPORT} was not run on the current picture plan: rerun check_requirements.py"]
    if phase != "post":
        return []
    r = []
    form = deliverable(root)[0] or "narrated-video"
    done, err = finished_files(root, form)
    if err:
        return [err]
    digest = creq.sha256(done[-1]) if done else None
    if (rep.get("candidate") or {}).get("sha256") != digest or not digest:
        r.append(f"{creq.REPORT} was not run on the current finished file: rerun check_requirements.py --candidate")
    if form == "stills":
        return r
    try:
        fin = jload(root / creq.FINISHED)
    except Exception:
        fin = {}
    if fin.get("ok") is not True or fin.get("sha256") != digest:
        r.append(f"{creq.FINISHED} is missing, failed or describes a different file than the current finished file")
    elif fin.get("deliverable") != form:
        r.append(f"{creq.FINISHED} deliverable '{fin.get('deliverable')}' is not this job's '{form}'")
    elif fin.get("requirementsSha256") != creq.sha256(root / creq.REQ):
        r.append(f"{creq.FINISHED} was written for other requirements than the current story/requirements.json")
    return r


def finished_files(root, form):
    """([files oldest first], error). production.json `finishedFile` (inside out/) pins the file; otherwise every file of the form."""
    out = root / "out"
    pinned = None
    pp = root / "production.json"
    if pp.exists():
        try:
            pinned = jload(pp).get("finishedFile")
        except Exception:
            pinned = None
    if pinned is not None:
        target = (root / str(pinned)).resolve()
        if not isinstance(pinned, str) or not target.is_relative_to(out.resolve()):
            return [], "production.json finishedFile must be a path inside out/"
        if not target.is_file():
            return [], f"production.json finishedFile {pinned} does not exist"
        if target.suffix.lower().lstrip(".") not in FINISHED_EXT.get(form, ()):
            return [], f"production.json finishedFile {pinned} is not a {'/'.join(FINISHED_EXT.get(form, ()))} file"
        return [root / str(pinned)], None
    exts = FINISHED_EXT.get(form, ())
    files = [p for p in out.iterdir() if p.is_file() and p.suffix.lower().lstrip(".") in exts] if out.exists() else []
    return sorted(files, key=lambda p: p.stat().st_mtime), None


def check_develop(root, prod, form=None):
    if form is None:
        form, err = deliverable(root)
        if err:
            return [err]
    narrated = form in ("narrated-video", "audio")
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
    elif has_todo(tr) or not tr.read_text(encoding="utf-8").strip():
        r.append("story/treatment.md is empty or a placeholder")
    bs = root / "story/beat-sheet.json"
    if not bs.exists():
        r.append("missing story/beat-sheet.json")
    else:
        beats = jload(bs).get("beats") or []
        if not beats or any(not (b.get("id") and b.get("role") and b.get("summary") and b.get("picture")) for b in beats) or "TODO" in bs.read_text(encoding="utf-8"):
            r.append("story/beat-sheet.json needs beats with id, role, summary and picture, and no TODO")
    sp = root / "story/screenplay.json"
    if not sp.exists():
        r.append("missing story/screenplay.json")
    else:
        sc = jload(sp).get("scenes") or []
        ids = [s.get("id") for s in sc]
        silent = lambda s: bool((s.get("action") or s.get("picture") or "").strip())
        if not sc or any(not (s.get("narration") or "").strip() and (narrated or not silent(s)) for s in sc) or "TODO" in sp.read_text(encoding="utf-8"):
            r.append("story/screenplay.json has no scenes, an empty line or a TODO" if narrated else
                     "story/screenplay.json has no scenes, a scene with neither narration nor an action, or a TODO")
        if len(ids) != len(set(ids)):
            r.append("story/screenplay.json has duplicate scene ids")
        if narrated and newer(root / "qa/narration-check.json", sp):
            r.append("qa/narration-check.json is older than the screenplay: rerun validate-narration.mjs")
    e = ok_report(root / "qa/narration-check.json") if narrated else None
    if e:
        r.append(e)
    r.extend(requirements_reasons(root, "develop"))
    for a in ("case", "screenplay"):
        if review_missing(prod, a):
            r.append(f"owner has not approved the {a}")
    return r


def check_pre(root, prod, form=None):
    form = form_of(root, form)
    r = []
    bd = root / "plan/breakdown.json"
    e = ok_report(bd)
    if e:
        r.append(e)
    elif newer(bd, root / "story/screenplay.json") or newer(bd, root / "story/picture-plan.json"):
        r.append("plan/breakdown.json is older than the screenplay or picture plan: rerun screenplay_breakdown.py")
    pp = root / "story/picture-plan.json"
    job = jload(root / "job.json") if (root / "job.json").exists() else {}
    if form != "audio":
        if not pp.exists() or "TODO" in pp.read_text(encoding="utf-8"):
            r.append("story/picture-plan.json is missing or a placeholder")
        for rep in ("qa/picture-relevance.json", "qa/visual-variety.json"):
            e = ok_report(root / rep)
            if e:
                r.append(e)
            elif newer(root / rep, pp):
                r.append(f"{rep} is older than the picture plan: rerun the gate")
        viewer = job.get("intent") == "viewer-facing"
        needs = ["story/storyboard.json", "story/visual-bible.json"] if viewer else (["story/storyboard.json"] if form == "storyboard" else [])
        for need in needs:
            if not (root / need).exists():
                r.append(f"{'viewer-facing job' if viewer else 'storyboard deliverable'} needs {need}")
    r.extend(requirements_reasons(root, "preproduction"))
    if review_missing(prod, "plan"):
        r.append("owner has not approved the plan (picture table and cost)")
    return r


def check_prod(root, prod, form=None):
    form = form_of(root, form)
    r = []
    sp = root / "story/screenplay.json"
    ids = [s["id"] for s in jload(sp).get("scenes", [])] if sp.exists() else []
    gone = [i for i in ids if not (root / "takes" / f"{i}.receipt.json").exists()]
    if form in ("narrated-video", "audio") and gone:
        r.append(f"no voice take for scene(s): {', '.join(gone[:6])}")
    if form == "narrated-video" and not (root / "story/cue-sheet.json").exists():
        r.append("missing story/cue-sheet.json")
    if form in ("narrated-video", "silent-video"):
        e = ok_report(root / "picture/briefing-props.report.json")
        if e:
            r.append(e)
        if not (root / "picture/video.mp4").exists():
            r.append("missing picture/video.mp4")
    return r


def check_post(root, prod, form=None):
    form = form_of(root, form)
    r = []
    mp4s, pin_err = finished_files(root, form)
    if pin_err:
        r.append(pin_err)
    elif not mp4s:
        r.append("no finished file in out/" + ("" if form in ("narrated-video", "silent-video") else f" ({'/'.join(FINISHED_EXT[form])})"))
    gates = {"narrated-video": ("qa/word-sync.json", "qa/frame-integrity.json"), "silent-video": ("qa/frame-integrity.json",)}.get(form, ())
    for rep in gates:
        e = ok_report(root / rep)
        if e:
            r.append(e)
        elif mp4s and newer(root / rep, mp4s[-1]):
            r.append(f"{rep} is older than the finished file: rerun the gate on it")
    job = jload(root / "job.json") if (root / "job.json").exists() else {}
    if job.get("intent") == "viewer-facing" and form != "stills":
        e = ok_report(root / "qa/story-experience-review.json")
        if e:
            r.append(e)
    r.extend(requirements_reasons(root, "post"))
    return r


def check_delivery(root, prod, form=None):
    form = form_of(root, form)
    r = []
    job = jload(root / "job.json") if (root / "job.json").exists() else {}
    policy = job.get("captionPolicy", {}).get("mode", "sidecar")
    if form != "narrated-video":
        pass
    elif policy == "sidecar" and not list((root / "out").glob("*.srt")):
        r.append("no captions sidecar (.srt) in out/")
    elif policy not in ("sidecar", "selectable", "open"):
        r.append("unknown captionPolicy mode")
    elif policy in ("selectable", "open"):
        review_path = root / "qa/story-experience-review.json"
        review = jload(review_path) if review_path.exists() else {}
        captions = review.get("captions", {})
        artifact = root / str(captions.get("artifactPath", ""))
        safe = artifact.resolve().is_relative_to(root.resolve())
        if not (safe and artifact.is_file() and captions.get("mode") == policy
                and captions.get("deliverySurface") == job.get("captionPolicy", {}).get("deliverySurface")
                and captions.get("verdict") == "PASS"
                and captions.get("sha256") == hashlib.sha256(artifact.read_bytes()).hexdigest()):
            r.append("consolidated story review needs a matching, exact-artifact caption/player check")
    if review_missing(prod, "delivered"):
        r.append("owner has not recorded delivery")
    return r


CHECKS = {"develop": check_develop, "preproduction": check_pre, "production": check_prod, "post": check_post, "delivery": check_delivery}


def status(root):
    root = Path(root)
    prod = jload(root / "production.json")
    prod.setdefault("approvals", {})
    form, err = deliverable(root)
    na = NOT_REQUIRED.get(form, {})
    out, blocked = [], False
    for ph in PHASES:
        if blocked:
            out.append({"phase": ph, "state": "BLOCKED", "reasons": ["an earlier phase has not passed"], "notRequired": na.get(ph, [])})
            continue
        if ph in WHOLE.get(form, ()):
            held = [f"owner review '{name}' is required and not recorded" for name in PHASE_REVIEWS.get(ph, ()) if review_missing(prod, name)]
            out.append({"phase": ph, "state": "FAIL" if held else "NOT_REQUIRED", "reasons": held, "notRequired": na.get(ph, [])})
            blocked = bool(held)
            continue
        reasons = CHECKS[ph](root, prod, form) if form else ([err] if ph == "develop" else [])
        out.append({"phase": ph, "state": "PASS" if not reasons else "FAIL", "reasons": reasons, "notRequired": na.get(ph, [])})
        blocked = bool(reasons)
    cur = next((p for p in out if p["state"] not in ("PASS", "NOT_REQUIRED")), None)
    for phase in out:
        phase["reviewStage"] = REVIEW_STAGES[phase["phase"]]
    return {"title": prod.get("title"), "deliverable": form or err_value(root), "phases": out, "current": cur["phase"] if cur else None,
            "next": NEXT[cur["phase"]] if cur else "All phases pass.", "complete": cur is None}


def approve(root, name):
    p = Path(root) / "production.json"
    prod = jload(p)
    if name not in INTERNAL_REVIEWS or name not in prod.get("approvals", {}):
        raise SystemExit(f"unknown approval '{name}'; one of {', '.join(INTERNAL_REVIEWS)}")
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
            print(f"  {p['state']:12} {p['phase']}")
            for r in p["reasons"][:6]:
                print(f"            - {r}")
        print("next:", s["next"])
    return 1 if (a.strict and not s["complete"]) else 0


if __name__ == "__main__":
    sys.exit(main())
