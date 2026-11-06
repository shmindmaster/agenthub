#!/usr/bin/env python3
"""Generate the real pictures for a film: quoted first, spent only on --run, never paid for twice.

    generate_stills.py <jobRoot> [--lane azure-image|runware-image] [--quality low|medium|high] [--size 1536x1024]
                       [--scenes s3,s5] [--max-usd 2.00] [--max-images 24] [--public-dir DIR] [--no-link] [--run] [--json]

Reads story/picture-plan.json. A scene is a generated picture when visual.kind is "still" and visual.prompt says what the
photograph shows (a place, an object, a mood). Without --run it only prints the quote: lane, model, size, estimated dollars
per picture and in total. With --run it generates every picture whose prompt, lane, size and quality have not been paid for
before, writes assets/stills/<scene>.png, records each one in assets/stills/manifest.json and qa/spend-ledger.jsonl, and sets
visual.src in the picture plan so the kit's still visual (layout "bleed" for a full-frame photograph) can show it.

Lanes (policy/provider-routing.json): azure-image is the default (MahumTech, gpt-image deployment on mt-foundary-resource);
runware-image is the cheap draft lane. A frozen lane is refused. Keys come from the environment by name and are never printed
or stored: AZURE_OPENAI_ENDPOINT with AZURE_OPENAI_API_KEY (or an Entra token from the Azure CLI), RUNWARE_API_KEY.

Prices are estimates and say so. Azure low and medium are quoted at the measured price plus 50% (about 1 and 2 cents); high is not measured yet, so it
is quoted at the worst case from the gpt-image-1 list meters ($0.04 per 1K output tokens). The real usage from each response is recorded. Runware reports the cost of every picture.
No text, logos or likenesses go in a generated picture: text is added by the kit.
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

import route_media

SCHEMA = "media-studio/stills/1"
AZURE_API_VERSION = "2025-04-01-preview"
AZURE_DEFAULT_DEPLOYMENT = "gpt-image-2.5-flare"
RUNWARE_URL = "https://api.runware.ai/v1"
RUNWARE_DEFAULT_MODEL = "runware:z-image@0"
RUNWARE_STEPS = 8
SIZES = ("1536x1024", "1024x1024", "1024x1536")
QUALITIES = ("low", "medium", "high")
LANES = {"azure-image": "azure", "runware-image": "runware"}
# gpt-image-1 output-token counts by size and quality, the only published meter; an upper bound for the 2.5 deployments.
AZURE_OUTPUT_TOKENS = {
    "1024x1024": {"low": 272, "medium": 1056, "high": 4160},
    "1536x1024": {"low": 408, "medium": 1584, "high": 6240},
    "1024x1536": {"low": 408, "medium": 1584, "high": 6240},
}
AZURE_OUT_USD_PER_1K = 0.04
AZURE_IN_USD_PER_1K = 0.01
AZURE_PROMPT_TOKENS_UPPER = 400
RUNWARE_USD_PER_IMAGE = 0.01  # measured 0.0062 for a 1536x1024 z-image on 2026-11-06; rounded up for the quote
DEFAULT_STYLE = "Photorealistic editorial photograph, natural light, one clear subject, uncluttered composition."
SAFETY = "No text, no letters, no logos, no watermarks, no recognisable real people."
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class StillsError(Exception):
    pass


def azure_cost_usd(output_tokens, input_tokens=0):
    return round(output_tokens / 1000 * AZURE_OUT_USD_PER_1K + input_tokens / 1000 * AZURE_IN_USD_PER_1K, 6)


# Real prices from the 2026-11-06 proof run, for a 1536x1024 picture on gpt-image-2.5-flare. Quotes use these with a 1.5x margin.
AZURE_MEASURED_USD = {"low": 0.0066, "medium": 0.0144}
QUOTE_MARGIN = 1.5


def estimate_usd(lane_id, size="1536x1024", quality="medium"):
    """Dollars to quote for one picture: measured price plus a margin where one exists, else a worst-case bound."""
    if lane_id == "azure-image":
        if quality in AZURE_MEASURED_USD:
            w, h = (int(n) for n in size.split("x"))
            return round(AZURE_MEASURED_USD[quality] * (w * h) / (1536 * 1024) * QUOTE_MARGIN, 4)
        tokens = AZURE_OUTPUT_TOKENS.get(size, AZURE_OUTPUT_TOKENS["1536x1024"])[quality]
        return round(azure_cost_usd(tokens, AZURE_PROMPT_TOKENS_UPPER), 4)
    if lane_id == "runware-image":
        return RUNWARE_USD_PER_IMAGE
    raise StillsError(f"no price known for lane {lane_id}")


def compose_prompt(prompt, style=None):
    """The subject, then the house style, then the rule that keeps text out of the picture."""
    parts = [prompt.strip().rstrip(".") + ".", (style or DEFAULT_STYLE).strip(), SAFETY]
    return " ".join(p for p in parts if p)


def cache_key(lane_id, model, size, quality, full_prompt):
    blob = json.dumps([lane_id, model, size, quality, full_prompt], sort_keys=True).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def png_size(data):
    if len(data) < 24 or data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise StillsError("provider output is not a PNG image")
    return struct.unpack(">II", data[16:24])


def http_post_json(url, headers, body, timeout=240):
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers={**headers, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        detail = e.read()[:300].decode("utf-8", "replace")
        raise StillsError(f"provider returned HTTP {e.code}: {detail}") from None
    except (urllib.error.URLError, TimeoutError) as e:
        raise StillsError(f"provider request failed: {type(e).__name__}") from None


def _env(env, name):
    return (env.get(name) or "").strip()


def azure_headers(env):
    key = _env(env, "AZURE_OPENAI_API_KEY")
    if key:
        return {"api-key": key}
    proc = subprocess.run(["az", "account", "get-access-token", "--resource", "https://cognitiveservices.azure.com", "--query", "accessToken", "-o", "tsv"],
                          capture_output=True, text=True, shell=(os.name == "nt"), timeout=60)
    token = proc.stdout.strip()
    if proc.returncode != 0 or not token:
        raise StillsError("no Azure credential: set AZURE_OPENAI_API_KEY or sign in with the Azure CLI")
    return {"Authorization": "Bearer " + token}


def generate_azure(full_prompt, size, quality, env, post):
    endpoint = _env(env, "AZURE_OPENAI_ENDPOINT").rstrip("/")
    if not endpoint:
        raise StillsError("AZURE_OPENAI_ENDPOINT is not set")
    deployment = _env(env, "MEDIA_STUDIO_AZURE_IMAGE_DEPLOYMENT") or AZURE_DEFAULT_DEPLOYMENT
    url = f"{endpoint}/openai/deployments/{deployment}/images/generations?api-version={AZURE_API_VERSION}"
    data = post(url, azure_headers(env), {"prompt": full_prompt, "size": size, "quality": quality, "n": 1})
    rows = data.get("data") or []
    if not rows or not rows[0].get("b64_json"):
        raise StillsError("Azure returned no image")
    usage = data.get("usage") or {}
    out_tokens, in_tokens = int(usage.get("output_tokens") or 0), int(usage.get("input_tokens") or 0)
    if out_tokens:
        usd, basis = azure_cost_usd(out_tokens, in_tokens), "actual tokens from the response at the gpt-image-1 list meters"
    else:
        usd, basis = estimate_usd("azure-image", size, quality), "estimate: the response carried no usage"
    return {"png": base64.b64decode(rows[0]["b64_json"]), "model": deployment, "usd": usd, "basis": basis,
            "usage": {"inputTokens": in_tokens, "outputTokens": out_tokens}}


def generate_runware(full_prompt, size, quality, env, post):
    key = _env(env, "RUNWARE_API_KEY")
    if not key:
        raise StillsError("RUNWARE_API_KEY is not set")
    width, height = (int(n) for n in size.split("x"))
    model = _env(env, "MEDIA_STUDIO_RUNWARE_IMAGE_MODEL") or RUNWARE_DEFAULT_MODEL
    task = {"taskType": "imageInference", "taskUUID": str(uuid.uuid4()), "model": model, "positivePrompt": full_prompt, "width": width,
            "height": height, "steps": RUNWARE_STEPS, "numberResults": 1, "outputType": "base64Data", "outputFormat": "PNG",
            "includeCost": True, "safety": {"checkContent": True}}
    data = post(RUNWARE_URL, {"Authorization": "Bearer " + key}, [task])
    if data.get("errors"):
        code = str((data["errors"][0] or {}).get("code", "provider-error"))
        raise StillsError(f"Runware error: {code}")
    rows = data.get("data") or []
    if not rows or not rows[0].get("imageBase64Data"):
        raise StillsError("Runware returned no image")
    if rows[0].get("NSFWContent") is True:
        raise StillsError("Runware flagged the picture as unsafe; rewrite the prompt")
    cost = rows[0].get("cost")
    usd, basis = (round(float(cost), 6), "cost reported by Runware") if isinstance(cost, (int, float)) else (RUNWARE_USD_PER_IMAGE, "estimate: no cost reported")
    return {"png": base64.b64decode(rows[0]["imageBase64Data"]), "model": model, "usd": usd, "basis": basis, "usage": {}}


ADAPTERS = {"azure-image": generate_azure, "runware-image": generate_runware}


def load_json(path, default=None):
    p = Path(path)
    if not p.exists():
        return default
    return json.loads(p.read_text(encoding="utf-8-sig"))


def write_json(path, data):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def pick_lane(visual, cli_lane, identity, policy):
    wanted = visual.get("lane") or cli_lane
    usable = {l["id"]: l for l in route_media.route(policy, ["image"], identity) if l["id"] in ADAPTERS}
    if wanted:
        if wanted in usable:
            return wanted
        status = next((l["status"] for l in policy["lanes"] if l["id"] == wanted), "unknown")
        raise StillsError(f"lane {wanted} is not usable for images today (status {status}); usable: {', '.join(usable) or 'none'}")
    if not usable:
        raise StillsError("no usable image lane for this identity; see scripts/route_media.py image --all")
    return next(iter(usable))


def plan_work(job, args, policy):
    """The quote: one row per generated picture, with whether it still needs paying for."""
    plan = load_json(job / "story" / "picture-plan.json")
    if not plan:
        raise StillsError("story/picture-plan.json is missing")
    production = load_json(job / "production.json", {}) or {}
    identity = args.identity or production.get("identity") or "any"
    bible = load_json(job / "story" / "visual-bible.json", {}) or {}
    style = bible.get("stillStyle")
    manifest = load_json(job / "assets" / "stills" / "manifest.json", {"stills": {}}) or {"stills": {}}
    only = {s for s in (args.scenes or "").split(",") if s}
    rows, problems = [], []
    for scene in plan.get("scenes", []):
        visual = scene.get("visual") or {}
        if visual.get("kind") != "still" or (only and scene.get("id") not in only):
            continue
        sid = scene.get("id")
        prompt = (visual.get("prompt") or "").strip()
        if not prompt:
            problems.append(f"{sid}: still has no prompt; say what the photograph shows")
            continue
        try:
            lane = pick_lane(visual, args.lane, identity, policy)
        except StillsError as e:
            problems.append(f"{sid}: {e}")
            continue
        size, quality = visual.get("size") or args.size, visual.get("quality") or args.quality
        if size not in SIZES or quality not in QUALITIES:
            problems.append(f"{sid}: size must be one of {', '.join(SIZES)} and quality one of {', '.join(QUALITIES)}")
            continue
        full = compose_prompt(prompt, style)
        model = (os.environ.get("MEDIA_STUDIO_AZURE_IMAGE_DEPLOYMENT") or AZURE_DEFAULT_DEPLOYMENT) if lane == "azure-image" else (os.environ.get("MEDIA_STUDIO_RUNWARE_IMAGE_MODEL") or RUNWARE_DEFAULT_MODEL)
        key = cache_key(lane, model, size, quality, full)
        have = (manifest.get("stills") or {}).get(sid) or {}
        cached = have.get("key") == key and (job / "assets" / "stills" / f"{sid}.png").exists()
        rows.append({"id": sid, "lane": lane, "model": model, "size": size, "quality": quality, "prompt": full, "key": key,
                     "cached": cached, "estimateUsd": 0.0 if cached else estimate_usd(lane, size, quality)})
    return plan, rows, problems, identity


def append_ledger(job, entry):
    path = job / "qa" / "spend-ledger.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry) + "\n")


def run(job, args, env=None, post=None, now=None):
    job, env, post = Path(job), env if env is not None else os.environ, post or http_post_json
    policy = route_media.load()
    plan, rows, problems, identity = plan_work(job, args, policy)
    todo = [r for r in rows if not r["cached"]]
    total = round(sum(r["estimateUsd"] for r in todo), 4)
    report = {"schema": SCHEMA, "job": str(job), "identity": identity, "mode": "run" if args.run else "quote",
              "scenes": [{k: v for k, v in r.items() if k != "prompt"} for r in rows], "problems": problems, "estimateUsd": total,
              "capUsd": args.max_usd, "generated": [], "failed": [], "actualUsd": 0.0}
    if problems or not args.run:
        report["ok"] = not problems
        return report
    if len(todo) > args.max_images:
        raise StillsError(f"{len(todo)} pictures to generate exceeds --max-images {args.max_images}")
    if total > args.max_usd:
        raise StillsError(f"estimate ${total} exceeds --max-usd {args.max_usd}; raise it only after the owner has seen the quote")
    manifest_path = job / "assets" / "stills" / "manifest.json"
    manifest = load_json(manifest_path, {"schema": SCHEMA, "stills": {}}) or {"schema": SCHEMA, "stills": {}}
    manifest.setdefault("stills", {})
    stamp = (now or datetime.now(timezone.utc)).isoformat(timespec="seconds")

    def one(row):
        adapter = ADAPTERS[row["lane"]]
        result = adapter(row["prompt"], row["size"], row["quality"], env, post)
        width, height = png_size(result["png"])
        want_w, want_h = (int(n) for n in row["size"].split("x"))
        if min(width, height) < 512:
            raise StillsError(f"picture is only {width}x{height}")
        return row, result, (width, height), (want_w, want_h)

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(4, len(todo)))) as pool:
        futures = {pool.submit(one, r): r for r in todo}
        for fut in concurrent.futures.as_completed(futures):
            row = futures[fut]
            try:
                row, result, dims, _ = fut.result()
            except StillsError as e:
                report["failed"].append({"id": row["id"], "lane": row["lane"], "error": str(e)})
                continue
            target = job / "assets" / "stills" / f"{row['id']}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            previous = (manifest["stills"].get(row["id"]) or {}).get("fileSha256")
            if target.exists() and previous:
                old = job / "assets" / "stills" / "superseded"
                old.mkdir(parents=True, exist_ok=True)
                shutil.move(str(target), str(old / f"{row['id']}-{previous[:8]}.png"))
            target.write_bytes(result["png"])
            file_sha = hashlib.sha256(result["png"]).hexdigest()
            prompt_sha = hashlib.sha256(row["prompt"].encode("utf-8")).hexdigest()
            entry = {"key": row["key"], "lane": row["lane"], "model": result["model"], "size": row["size"], "quality": row["quality"],
                     "width": dims[0], "height": dims[1], "bytes": len(result["png"]), "fileSha256": file_sha, "promptSha256": prompt_sha,
                     "usd": result["usd"], "usdBasis": result["basis"], "usage": result["usage"], "createdAt": stamp}
            manifest["stills"][row["id"]] = entry
            append_ledger(job, {"at": stamp, "kind": "image", "sceneId": row["id"], **{k: entry[k] for k in ("lane", "model", "size", "quality", "usd", "usdBasis", "promptSha256", "fileSha256")}})
            report["generated"].append({"id": row["id"], "lane": row["lane"], "model": result["model"], "usd": result["usd"], "file": f"assets/stills/{row['id']}.png", "sha256": file_sha})
            report["actualUsd"] = round(report["actualUsd"] + result["usd"], 6)
    write_json(manifest_path, manifest)
    if not args.no_link and (report["generated"] or rows):
        slug = job.name
        public = Path(args.public_dir) if args.public_dir else None
        changed = False
        for scene in plan.get("scenes", []):
            visual = scene.get("visual") or {}
            entry = manifest["stills"].get(scene.get("id"))
            if visual.get("kind") != "still" or not entry:
                continue
            src = f"stills/{slug}/{scene['id']}.png"
            if visual.get("src") != src:
                visual["src"] = src
                changed = True
            if public:
                dest = public / src
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(job / "assets" / "stills" / f"{scene['id']}.png", dest)
        if changed:
            write_json(job / "story" / "picture-plan.json", plan)
    report["ok"] = not report["failed"]
    return report


def print_report(report):
    print(f"{report['mode'].upper()}  identity {report['identity']}  job {report['job']}")
    for s in report["scenes"]:
        state = "cached" if s["cached"] else f"~${s['estimateUsd']:.4f}"
        print(f"  {s['id']:8} {s['lane']:14} {s['model']:24} {s['size']} {s['quality']:6} {state}")
    for p in report["problems"]:
        print("  PROBLEM:", p)
    print(f"estimate for new pictures: ${report['estimateUsd']:.4f}  (cap ${report['capUsd']:.2f}; an upper bound, actual cost is recorded)")
    for g in report["generated"]:
        print(f"  made {g['id']} on {g['lane']} ({g['model']}) ${g['usd']:.4f} -> {g['file']}")
    for f in report["failed"]:
        print(f"  FAILED {f['id']} on {f['lane']}: {f['error']}")
    if report["mode"] == "run":
        print(f"actual spend: ${report['actualUsd']:.4f}")
    elif report["scenes"] and not report["problems"]:
        print("nothing spent. Add --run to generate.")
    print("RESULT:", "ok" if report["ok"] else "FAILED")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("job")
    ap.add_argument("--lane", choices=sorted(LANES))
    ap.add_argument("--identity", choices=["mahumtech", "abacare", "any"])
    ap.add_argument("--quality", choices=QUALITIES, default="medium")
    ap.add_argument("--size", choices=SIZES, default="1536x1024")
    ap.add_argument("--scenes")
    ap.add_argument("--max-usd", type=float, default=2.0)
    ap.add_argument("--max-images", type=int, default=24)
    ap.add_argument("--public-dir")
    ap.add_argument("--no-link", action="store_true")
    ap.add_argument("--run", action="store_true", help="spend: generate the pictures that have not been paid for")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    try:
        report = run(args.job, args)
    except StillsError as e:
        print("ERROR:", e)
        return 1
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
