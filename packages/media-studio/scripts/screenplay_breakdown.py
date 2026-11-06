#!/usr/bin/env python3
"""Script breakdown, budget and schedule for a production: the pre-production step between screenplay and shoot.

    screenplay_breakdown.py <jobRoot> [--wpm 150] [--hd-voices Ava,Andrew] [--out plan/breakdown.json] [--json]

Reads story/screenplay.json (schemas/screenplay.schema.json) and, when present, story/picture-plan.json. For every scene it
records the speaker, the words and seconds, the picture kind and the funded lane that can make it (policy/provider-routing.json).
Then it totals the cast, the assets that must exist, a priced budget and a build order. Free and offline: it estimates, it never
calls a provider.

Prices are the documented eastus2 list rates in skills/generate/references/azure.md: standard neural $15 per 1M characters, HD
$22 per 1M, transcription check $0.36 per hour. A lane with no known unit price (images) is counted and marked unpriced, never
guessed. A scene with no picture, or a picture that needs a frozen lane, is an error and exits 1.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import route_media

STANDARD_USD_PER_BYTE = 15e-6
HD_USD_PER_BYTE = 22e-6
ASR_USD_PER_HOUR = 0.36
KIND_NEED = {"svg": "diagram", "flow": "diagram", "layers": "diagram", "sequence": "diagram", "map": "diagram", "timeline": "diagram",
             "chart": "chart", "stat": "stat", "table": "diagram", "split": "diagram", "beforeafter": "diagram", "code": "code",
             "lottie": "motion", "still": "image", "broll": "video-generation", "screen-in-context": "screen",
             "hero": "title", "quote": "title", "proof": "title", "checklist": "title", "cta": "title", "sidecar": "title",
             "chapter": "title", "lower-third": "lower-third"}
ASSET_KINDS = {"still", "broll", "screen-in-context", "lottie"}


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def scene_rows(screenplay, plan, wpm, hd_voices, identity):
    policy = route_media.load()
    plan_by_id = {s["id"]: s for s in (plan or {}).get("scenes", [])}
    rows, errors = [], []
    for sc in screenplay["scenes"]:
        text = sc.get("narration", "")
        words = len(text.split())
        speaker = sc.get("speaker") or "narrator"
        visual = (plan_by_id.get(sc["id"]) or {}).get("visual") or {}
        kind = visual.get("kind")
        row = {"id": sc["id"], "speaker": speaker, "words": words, "seconds": round(words / wpm * 60, 1) if words else 0.0,
               "bytes": len(text.encode("utf-8")), "visualKind": kind, "lane": None, "asset": visual.get("src")}
        if plan is not None and sc["id"] not in plan_by_id:
            errors.append(f"scene {sc['id']} has no picture in picture-plan.json")
        elif plan is not None and not kind:
            errors.append(f"scene {sc['id']} has no visual.kind")
        if kind:
            need = KIND_NEED.get(kind, "title")
            lanes = route_media.route(policy, [need], identity)
            if lanes:
                row["lane"] = lanes[0]["id"]
            else:
                errors.append(f"scene {sc['id']}: {kind} needs a '{need}' lane and none is usable today (frozen or not allowed for this identity)")
        row["tier"] = "hd" if speaker.lower() in {v.lower() for v in hd_voices} else "standard"
        rows.append(row)
    return rows, errors


def summarize(screenplay, plan, wpm=150, hd_voices=(), identity="any"):
    rows, errors = scene_rows(screenplay, plan, wpm, hd_voices, identity)
    cast = {}
    for r in rows:
        c = cast.setdefault(r["speaker"], {"speaker": r["speaker"], "scenes": 0, "words": 0, "tier": r["tier"]})
        c["scenes"] += 1
        c["words"] += r["words"]
    seconds = round(sum(r["seconds"] for r in rows), 1)
    speech = sum(r["bytes"] * (HD_USD_PER_BYTE if r["tier"] == "hd" else STANDARD_USD_PER_BYTE) for r in rows)
    asr = seconds / 3600 * ASR_USD_PER_HOUR
    assets = sorted({(r["visualKind"], r["asset"]) for r in rows if r["visualKind"] in ASSET_KINDS and r["asset"]})
    images = sum(1 for r in rows if r["visualKind"] == "still")
    lanes = {}
    for r in rows:
        if r["lane"]:
            lanes[r["lane"]] = lanes.get(r["lane"], 0) + 1
    schedule = [
        {"task": "T1 lock the script and pin names", "needs": [], "parallel": False},
        {"task": "T2 voice takes, one per scene", "needs": ["T1"], "parallel": True, "limit": 5, "note": "Azure renders stall above about five at once"},
        {"task": "T3 assets: stills, Lottie, captures", "needs": ["T1"], "parallel": True},
        {"task": "T4 word clock and cue sheet", "needs": ["T2"], "parallel": False},
        {"task": "T5 build props and render the picture", "needs": ["T3", "T4"], "parallel": False},
        {"task": "T6 mix, finish loudness, run the gates", "needs": ["T5"], "parallel": False},
        {"task": "T7 review the encoded file and deliver", "needs": ["T6"], "parallel": False},
    ]
    return {"schema": "media-studio/breakdown/1", "title": screenplay.get("title"), "scenes": rows, "cast": list(cast.values()),
            "estimatedSeconds": seconds, "assets": [{"kind": k, "src": s} for k, s in assets], "lanes": lanes,
            "budget": {"speechUsd": round(speech, 4), "transcriptionCheckUsd": round(asr, 4), "pricedUsd": round(speech + asr, 4),
                       "unpriced": ([{"item": "generated stills", "count": images, "note": "no documented unit price; quote before running"}] if images else []),
                       "basis": "azure.md eastus2 list rates; an estimate, not a bill"},
            "schedule": schedule, "errors": errors, "ok": not errors}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("job")
    ap.add_argument("--wpm", type=float, default=150)
    ap.add_argument("--hd-voices", default="")
    ap.add_argument("--identity", default="any")
    ap.add_argument("--out", default="plan/breakdown.json")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    root = Path(a.job)
    screenplay = load(root / "story" / "screenplay.json")
    plan_path = root / "story" / "picture-plan.json"
    plan = load(plan_path) if plan_path.exists() else None
    rep = summarize(screenplay, plan, a.wpm, [v for v in a.hd_voices.split(",") if v], a.identity)
    out = root / a.out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
    if a.json:
        print(json.dumps(rep, indent=2))
    else:
        print(f"{rep['title']}: {len(rep['scenes'])} scenes, about {rep['estimatedSeconds']} s, cast {', '.join(c['speaker'] for c in rep['cast'])}")
        print(f"budget (priced): ${rep['budget']['pricedUsd']}  unpriced: {[u['item'] for u in rep['budget']['unpriced']] or 'none'}")
        print("lanes:", rep["lanes"], " assets:", len(rep["assets"]))
        for e in rep["errors"]:
            print("ERROR:", e)
        print("RESULT:", "ok" if rep["ok"] else "FAILED")
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
