#!/usr/bin/env python3
"""Script breakdown, budget and schedule for a production: the pre-production step between screenplay and shoot.

    screenplay_breakdown.py <jobRoot> [--wpm 150] [--hd-voices Ava,Andrew] [--out plan/breakdown.json] [--json]

Reads story/screenplay.json (schemas/screenplay.schema.json) and, when present, story/picture-plan.json. For every scene it
records the speaker, the words and seconds, the picture kind and the funded lane that can make it (policy/provider-routing.json).
Then it totals the cast, the assets that must exist, a priced budget and a build order. Free and offline: it estimates, it never
calls a provider.

Prices are the documented eastus2 list rates in skills/generate/references/azure.md: standard neural $15 per 1M characters, HD
$22 per 1M, transcription check $0.36 per hour. A generated still is priced by generate_stills.estimate_usd (an upper bound, at
medium quality and 1536x1024 unless the scene says otherwise). A generated clip (broll) is counted in provider credits, not dollars:
the lane's creditsPerClip per clipSeconds (IrukaDark), shown as clips and clipCredits. A lane with no known unit price is counted and marked unpriced,
never guessed. A scene with no picture, a still with no prompt, or a picture that needs a frozen lane is an error and exits 1.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import generate_stills
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
        if kind == "still":
            if not (visual.get("prompt") or "").strip():
                errors.append(f"scene {sc['id']}: still has no prompt; say what the photograph shows")
            row["prompt"] = visual.get("prompt")
        if kind:
            need = KIND_NEED.get(kind, "title")
            lanes = route_media.route(policy, [need], identity)
            if lanes:
                row["lane"] = lanes[0]["id"]
                if kind == "broll":
                    per_clip, clip_s = lanes[0].get("creditsPerClip"), lanes[0].get("clipSeconds") or 5
                    if per_clip:
                        want = float(visual.get("seconds") or clip_s)
                        row["clips"] = max(1, -(-int(want * 1000) // int(clip_s * 1000)))
                        row["clipCredits"] = row["clips"] * per_clip
                if kind == "still":
                    lane_id = visual.get("lane") or lanes[0]["id"]
                    try:
                        row["imageUsd"] = generate_stills.estimate_usd(lane_id, visual.get("size") or "1536x1024", visual.get("quality") or "medium")
                        row["lane"] = lane_id
                    except generate_stills.StillsError as e:
                        errors.append(f"scene {sc['id']}: {e}")
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
    stills_usd = sum(r.get("imageUsd", 0.0) for r in rows)
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
            "budget": {"speechUsd": round(speech, 4), "transcriptionCheckUsd": round(asr, 4), "stillsUsd": round(stills_usd, 4), "stills": images,
                       "pricedUsd": round(speech + asr + stills_usd, 4), "unpriced": [],
                       "clips": sum(r.get("clips", 0) for r in rows), "clipCredits": sum(r.get("clipCredits", 0) for r in rows),
                       "basis": "azure.md eastus2 list rates for speech; generate_stills upper-bound quote for pictures (actual cost is recorded when they are made); an estimate, not a bill"},
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
        print(f"budget (priced): ${rep['budget']['pricedUsd']}  of which stills ${rep['budget']['stillsUsd']} ({rep['budget']['stills']} pictures)  clips: {rep['budget']['clips']} = {rep['budget']['clipCredits']} IrukaDark credits  unpriced: {[u['item'] for u in rep['budget']['unpriced']] or 'none'}")
        print("lanes:", rep["lanes"], " assets:", len(rep["assets"]))
        for e in rep["errors"]:
            print("ERROR:", e)
        print("RESULT:", "ok" if rep["ok"] else "FAILED")
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
