#!/usr/bin/env python3
"""Check a film against the requirements its brief asked for.

    check_requirements.py <jobRoot> [--candidate out/film.mp4]

Reads story/requirements.json (schema media-studio/requirements/1, see schemas/requirements.schema.json) and writes
qa/requirements-check.json: {ok, errors, warnings, unverified, inputs:{path:sha256}, candidate}.

Without --candidate it checks the script: valid shape, no TODO, every requirement mapped to real scenes, every `match` term
present in the narration and/or picture-plan text of those scenes, the CTA on a real scene, and declared languages that do not
contradict a language declared in job.json, the screenplay or the capture plan.

With --candidate it also measures the file with ffprobe (duration range, aspect ratio) and reads qa/finished-film.json for the
final hold. ffprobe missing is an error, not a pass. Anything declared but not measured is listed in `unverified` and, with
--candidate, makes ok false: an unmeasured claim is never counted as a pass. That covers a duration, aspect or final hold before a
candidate exists, a narrationLanguage or uiLanguage that nothing else in the job declares, a required CTA scene with no text, and a
requirement with no `match`; a passing item with that id in qa/requirements-review.json (ids narrationLanguage, uiLanguage, cta) clears it. Stdlib only, free and offline.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import unicodedata

SCHEMA = "media-studio/requirements/1"
TYPES = ("feature", "state", "language", "other")
EVIDENCE = ("narration", "picture", "both")
ASPECTS = {"16x9": 16 / 9, "9x16": 9 / 16, "4x5": 4 / 5, "1x1": 1.0}
BCP47 = re.compile(r"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$")
CAPTURE_PLANS = ("plan/capture-plan.json", "story/capture-plan.json", "capture/capture-plan.json", "capture/receipt.json")
REQ = "story/requirements.json"
REPORT = "qa/requirements-check.json"
FINISHED = "qa/finished-film.json"
PLAN = "story/picture-plan.json"
STILL_EXT = ("png", "jpg", "jpeg", "pdf", "pptx")
PROBE_STILL_EXT = ("png", "jpg", "jpeg")
# Fields of a picture-plan or screenplay scene that hold words a viewer can see. Ids, kinds, paths and colours are not evidence.
TEXT_KEYS = {"title", "kicker", "subtitle", "headline", "heading", "onScreen", "onScreenText", "caption", "label", "text", "name", "value",
             "action", "picture", "body", "quote", "description", "line", "cta", "prompt", "alt"}
LIST_KEYS = {"items", "lines", "bullets", "labels", "steps", "groups", "nodes", "rows", "cells", "children", "events"}
REVIEW = "qa/requirements-review.json"
REVIEW_SCHEMA = "media-studio/requirements-review/1"


def jload(p):
    return json.loads(Path(p).read_text(encoding="utf-8-sig"))


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def input_paths(root):
    """The files whose content decides the result, relative to the job root."""
    root = Path(root)
    rels = [REQ, "job.json", "story/screenplay.json", *CAPTURE_PLANS]
    found = [r for r in rels if (root / r).is_file()]
    return found + ([PLAN] if plan_ready(root) else [])


def plan_ready(root):
    """The picture plan exists and is not a scaffold placeholder."""
    p = Path(root) / PLAN
    return p.is_file() and "TODO" not in p.read_text(encoding="utf-8-sig")


def input_hashes(root):
    """Hashes of what decides develop freshness. The candidate review is added only by a candidate run, never here."""
    return {r: sha256(Path(root) / r) for r in input_paths(root)}


def visible_text(node, wanted=False):
    """Strings in text-bearing fields (and lists under list-like fields), not ids, kinds or paths."""
    if isinstance(node, str):
        if wanted:
            yield node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield from visible_text(v, k in TEXT_KEYS or k in LIST_KEYS)
    elif isinstance(node, list):
        for v in node:
            yield from visible_text(v, wanted)


def norm(s):
    return unicodedata.normalize("NFC", unicodedata.normalize("NFC", str(s)).casefold())


def has_term(hay, term):
    return re.search(r"(?<!\w)" + re.escape(norm(term)) + r"(?!\w)", hay) is not None


def primary(tag):
    return re.split(r"[-_]", str(tag))[0].lower()


def ffprobe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type,width,height",
                        "-of", "json", str(path)], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or "ffprobe failed")
    return json.loads(r.stdout)


def contradicts(want, have):
    if want == "TODO":
        return False
    if "none" in (want, have):
        return want != have
    return primary(want) != primary(have)


def language_errors(root, req):
    """(errors, compared): a declared language that contradicts one declared elsewhere in the job, and the declared fields that have at
    least one counterpart to compare with. A field with none is a claim nothing measures."""
    root, errs, compared = Path(root), [], set()

    def load(rel):
        try:
            return jload(root / rel) if (root / rel).is_file() else {}
        except Exception:
            return {}

    pairs = [("narrationLanguage", "job.json", "narrationLanguage"), ("uiLanguage", "job.json", "uiLanguage"),
             ("narrationLanguage", "story/screenplay.json", "narrationLanguage"), ("narrationLanguage", "story/screenplay.json", "language"),
             ("uiLanguage", "story/screenplay.json", "uiLanguage")]
    pairs += [("uiLanguage", rel, key) for rel in CAPTURE_PLANS for key in ("uiLanguage", "locale")]
    for field, rel, key in pairs:
        want, have = req.get(field), load(rel).get(key)
        if isinstance(want, str) and isinstance(have, str) and have.strip():
            compared.add(field)
            if contradicts(want, have):
                errs.append(f"{field} '{want}' contradicts {rel} {key} '{have}'")
    return errs, compared


def check(root, candidate=None):
    root = Path(root)
    errors, warnings, unverified = [], [], []
    out = {"schema": "media-studio/requirements-check/1", "ok": False, "errors": errors, "warnings": warnings,
           "unverified": unverified, "inputs": input_hashes(root), "candidate": None}
    path = root / REQ
    try:
        req = jload(path)
        if not isinstance(req, dict):
            raise ValueError("not an object")
    except FileNotFoundError:
        errors.append(f"missing {REQ}")
        return finish(out)
    except Exception as e:
        errors.append(f"{REQ} is not valid JSON: {e}")
        return finish(out)
    if "TODO" in path.read_text(encoding="utf-8-sig"):
        errors.append(f"{REQ} still has TODO")
    if req.get("schema") != SCHEMA:
        errors.append(f"{REQ} schema must be {SCHEMA}")
    for f in ("narrationLanguage", "uiLanguage"):
        v = req.get(f)
        if v is not None and (not isinstance(v, str) or not (v == "none" or BCP47.match(v) or v == "TODO")):
            errors.append(f"{f} must be a BCP-47 tag or 'none'")
    dur = req.get("durationSeconds")
    if dur is not None:
        if not (isinstance(dur, dict) and all(isinstance(dur.get(k), (int, float)) and not isinstance(dur.get(k), bool) for k in ("min", "max"))
                and 0 <= dur["min"] <= dur["max"]):
            errors.append("durationSeconds needs numeric min <= max")
            dur = None
    asp = req.get("aspect")
    if asp is not None and asp not in ASPECTS:
        errors.append(f"aspect must be one of {', '.join(ASPECTS)}")
    hold = req.get("finalHoldSeconds")
    if hold is not None and (not isinstance(hold, (int, float)) or isinstance(hold, bool) or hold < 0):
        errors.append("finalHoldSeconds must be a number >= 0")
        hold = None
    cta = req.get("cta")
    if cta is not None and not (isinstance(cta, dict) and isinstance(cta.get("required"), bool)):
        errors.append("cta needs required (true or false)")
        cta = None
    items = req.get("requirements")
    if not isinstance(items, list):
        errors.append("requirements must be a list")
        items = []
    elif not items:
        errors.append("requirements needs at least one requirement")

    def load_opt(rel):
        try:
            return jload(root / rel) if (root / rel).is_file() else None
        except Exception:
            errors.append(f"{rel} is not valid JSON")
            return None

    sp, pp = load_opt("story/screenplay.json"), load_opt("story/picture-plan.json")
    scenes = {s["id"]: s for s in (sp or {}).get("scenes", []) if isinstance(s, dict) and isinstance(s.get("id"), str)}
    plan = {s["id"]: s for s in (pp or {}).get("scenes", []) if isinstance(s, dict) and isinstance(s.get("id"), str)}
    plan_ok = pp is not None and plan_ready(root)
    if sp is None:
        errors.append("missing story/screenplay.json: requirements cannot be mapped to scenes")

    def text(ids, kind):
        parts = []
        for i in ids:
            if kind in ("narration", "both"):
                parts.append(str(scenes.get(i, {}).get("narration") or ""))
            if kind == "picture":
                parts.extend(visible_text(plan.get(i, {})))
                parts.extend(str(scenes.get(i, {}).get(k) or "") for k in ("onScreen", "action", "picture"))
        return norm("\n".join(parts))

    def terms_in(ids, terms, where, label):
        hay = text(ids, where)
        for t in terms:
            if not has_term(hay, t):
                errors.append(f"{label}: '{t}' not found in the {'narration' if where == 'narration' else 'picture plan'} of scene(s) {', '.join(ids)}")

    seen, visual = set(), {}
    for n, r in enumerate(items):
        rid = r.get("id") if isinstance(r, dict) else None
        label = f"requirement {rid if isinstance(rid, str) and rid else n + 1}"
        if not isinstance(r, dict):
            errors.append(f"{label} is not an object")
            continue
        if not isinstance(rid, str) or not rid.strip():
            errors.append(f"{label} has no id")
            continue
        if rid in seen:
            errors.append(f"duplicate requirement id '{rid}'")
        seen.add(rid)
        if r.get("type") not in TYPES:
            errors.append(f"{label}: type must be one of {', '.join(TYPES)}")
        for f in ("text", "check"):
            if not (isinstance(r.get(f), str) and r[f].strip()):
                errors.append(f"{label}: {f} is empty")
        ids = r.get("scenes")
        if not isinstance(ids, list) or not ids:
            errors.append(f"{label} maps to no scenes")
            continue
        if not all(isinstance(i, str) and i.strip() for i in ids):
            errors.append(f"{label}: scene ids must be non-empty strings")
            continue
        bad = [i for i in ids if i not in scenes]
        if bad and sp is not None:
            errors.append(f"{label}: unknown scene id(s) {', '.join(map(str, bad))}")
            continue
        where = r.get("evidence", "narration")
        if where not in EVIDENCE:
            errors.append(f"{label}: evidence must be one of {', '.join(EVIDENCE)}")
            continue
        terms = r.get("match")
        if terms is None:
            visual[rid] = (f"{label}: no match terms, so nothing checks it against the script",
                           f"{label}: no match terms and no passing item in {REVIEW} for this file")
        elif not (isinstance(terms, list) and terms and all(isinstance(t, str) and t.strip() for t in terms)):
            errors.append(f"{label}: match must be a non-empty list of terms")
        elif sp is not None:
            if where in ("narration", "both"):
                terms_in(ids, terms, "narration", label)
            if where in ("picture", "both"):
                if plan_ok:
                    terms_in(ids, terms, "picture", label)
                else:
                    unverified.append(f"{label}: story/picture-plan.json is missing or a placeholder, so the picture evidence is not checked yet")

    if cta and cta["required"]:
        cid = cta.get("scene")
        if not cid:
            errors.append("cta.required is true but cta names no scene")
        elif not isinstance(cid, str):
            errors.append("cta.scene must be a scene id")
        elif sp is not None and cid not in scenes:
            errors.append(f"cta.scene '{cid}' is not a scene")
        elif cta.get("text") and sp is not None and not (has_term(text([cid], "narration"), cta["text"])
                                                           or (plan_ok and has_term(text([cid], "picture"), cta["text"]))):
            errors.append(f"cta text '{cta['text']}' not found in scene {cid}")
        elif not cta.get("text"):
            visual["cta"] = (f"cta: scene {cid} is named but no text, so nothing checks it against the script",
                             f"cta: no text to match and no passing 'cta' item in {REVIEW} for this file")
    lang_errors, compared = language_errors(root, req)
    errors.extend(lang_errors)
    for f in ("narrationLanguage", "uiLanguage"):
        if isinstance(req.get(f), str) and req[f] != "TODO" and f not in compared:
            visual[f] = (f"{f}: nothing in the job, screenplay or capture plan declares one to compare with, so it is not checked",
                         f"{f}: nothing else declares one and there is no passing '{f}' item in {REVIEW} for this file")

    job = load_opt("job.json") or {}
    suffix = Path(candidate).suffix.lower().lstrip(".") if candidate is not None else ""
    still = (job.get("deliverable") if isinstance(job, dict) else None) == "stills" or suffix in STILL_EXT
    if still:
        dur = hold = None  # a still has no duration and no final hold to measure
    if candidate is None:
        unverified.extend(v[0] for v in visual.values())
    if candidate is not None:
        length = measure(root, Path(candidate), out, dur, asp, hold, still)
        ids = set(seen) | set(visual)
        if still and asp and suffix not in PROBE_STILL_EXT:
            visual["framing"] = ("", "framing: the aspect of a pdf or pptx cannot be measured; it needs a passing `framing` item in " + REVIEW)
            ids.add("framing")
        review(root, out, visual, ids, length)
    else:
        unverified.extend(f"{name} is measured only with --candidate"
                          for name, v in (("durationSeconds", dur), ("aspect", asp), ("finalHoldSeconds", hold)) if v is not None)
    return finish(out, candidate is not None)


def measure(root, cand, out, dur, asp, hold, still=False):
    errors, unverified = out["errors"], out["unverified"]
    cand = cand if cand.is_absolute() else root / cand
    if not cand.is_file():
        errors.append(f"candidate {cand.name} does not exist")
        return None
    digest = sha256(cand)
    out["candidate"] = {"path": cand.relative_to(root).as_posix() if cand.is_relative_to(root) else str(cand), "sha256": digest}
    if still and cand.suffix.lower().lstrip(".") not in PROBE_STILL_EXT:
        return None
    try:
        probe = ffprobe(cand)
    except FileNotFoundError:
        errors.append("ffprobe is not installed, so the candidate cannot be measured")
        probe = None
    except Exception as e:
        errors.append(f"ffprobe could not read the candidate: {e}")
        probe = None
    length = None
    if probe is not None:
        length = float(probe.get("format", {}).get("duration") or 0)
        if dur and not dur["min"] <= length <= dur["max"]:
            errors.append(f"duration {length:.1f}s is outside {dur['min']} to {dur['max']} seconds")
        video = next((s for s in probe.get("streams", []) if s.get("codec_type") == "video" and s.get("width")), None)
        if asp:
            if video is None:
                unverified.append("aspect could not be measured: the candidate has no picture")
            else:
                ratio = video["width"] / video["height"]
                if abs(ratio - ASPECTS[asp]) / ASPECTS[asp] > 0.02:
                    errors.append(f"aspect {video['width']}x{video['height']} is not {asp}")
    if hold is None:
        return length
    fp = root / FINISHED
    try:
        fin = jload(fp) if fp.is_file() else None
    except Exception:
        fin = None
    if not fin:
        unverified.append(f"finalHoldSeconds {hold}: {FINISHED} is missing or unreadable")
    elif fin.get("sha256") != digest:
        unverified.append(f"finalHoldSeconds {hold}: {FINISHED} describes a different file than the candidate")
    elif fin.get("ok") is not True:
        errors.append(f"{FINISHED} did not pass")
    else:
        seen_still = (fin.get("ending") or {}).get("stillSeconds")
        if not isinstance(seen_still, (int, float)):
            unverified.append(f"finalHoldSeconds {hold}: {FINISHED} has no ending.stillSeconds")
        elif seen_still < hold - 0.25:
            errors.append(f"final hold {seen_still}s is shorter than the required {hold}s")
    return length


def seconds(at):
    """Seconds from a number or mm:ss (or h:mm:ss); None when it is neither."""
    if isinstance(at, bool):
        return None
    if isinstance(at, (int, float)):
        return float(at)
    if isinstance(at, str) and re.fullmatch(r"\d+(:\d{1,2}){1,2}(\.\d+)?", at.strip()):
        t = 0.0
        for part in at.strip().split(":"):
            t = t * 60 + float(part)
        return t
    return None


def review(root, out, visual, ids, length):
    """A person's pass or fail on the exact candidate, for what no script can measure. Requirements with no match terms need it."""
    errors, unverified = out["errors"], out["unverified"]
    digest = (out["candidate"] or {}).get("sha256")
    items = {}
    rp = root / REVIEW
    if rp.is_file() and digest:
        out["inputs"][REVIEW] = sha256(rp)
        try:
            doc = jload(rp)
            if not isinstance(doc, dict) or doc.get("schema") != REVIEW_SCHEMA or not isinstance(doc.get("items"), list):
                raise ValueError(f"schema must be {REVIEW_SCHEMA} with an items list")
            if not (isinstance(doc.get("reviewer"), str) and doc["reviewer"].strip()):
                raise ValueError("reviewer is empty")
        except Exception as e:
            errors.append(f"{REVIEW} is unusable: {e}")
            doc = None
        if doc and doc.get("candidateSha256") != digest:
            errors.append(f"{REVIEW} is stale: it reviewed a different file than the candidate")
        elif doc:
            for it in doc["items"]:
                rid = it.get("id") if isinstance(it, dict) else None
                if not isinstance(rid, str) or rid not in ids:
                    errors.append(f"{REVIEW} item '{rid}' is not a requirement id")
                elif it.get("verdict") == "fail":
                    errors.append(f"requirement {rid} failed review: {it.get('note') or 'no note'}")
                elif it.get("verdict") != "pass":
                    errors.append(f"{REVIEW} item '{rid}' verdict must be pass or fail")
                else:
                    at = seconds(it.get("at"))
                    if at is None or at < 0 or (length is not None and at > length):
                        errors.append(f"{REVIEW} item '{rid}' needs an `at` inside the film (mm:ss or seconds)")
                    else:
                        items[rid] = it
    for rid, msg in visual.items():
        if rid not in items:
            unverified.append(msg[1])


def finish(out, with_candidate=False):
    out["ok"] = not out["errors"] and not (with_candidate and out["unverified"])
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("job")
    ap.add_argument("--candidate")
    a = ap.parse_args(argv)
    res = check(a.job, a.candidate)
    dest = Path(a.job) / REPORT
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(res, indent=2) + "\n", encoding="utf-8")
    print("requirements:", "ok" if res["ok"] else "NOT ok")
    for k in ("errors", "warnings", "unverified"):
        for m in res[k]:
            print(f"  {k[:-1] if k != 'unverified' else k}: {m}")
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
