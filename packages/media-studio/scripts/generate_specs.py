#!/usr/bin/env python3
"""Write model-written layer specs for a film: quoted first, spent only on --run, never paid for twice.

    generate_specs.py <jobRoot> [--layers moments,overlays,captions,diagram] [--beats S01,S02] [--effort low|medium]
                      [--model claude-haiku-5-5] [--max-usd 0.50] [--max-requests 12]
                      [--key-env ANTHROPIC_API_KEY_BACKUP] [--run] [--json]

Lane claude-haiku-specs (policy/provider-routing.json; skills/visuals/references/model-written-specs.md). The layers
augment a real screen recording, its narration and its cue sheet; they never replace them. Each layer is its own request
with its own schema under schemas/model-specs/:

    moments   where the recording needs help, with a reason (an empty list is a valid answer). The default layer.
    overlays  callouts, step captions, term cards, zoom regions and chapter cards in named regions
    captions  chunk boundaries and emphasis by word index, never times
    diagram   Mermaid or D2 source with a one-sentence caption and the beat range it supports

Reads plan/cue-sheet.json (beats, spoken words, labelled actions, expected UI state) and, when present,
story/model-specs-brief.json ({"style": "...", "examples": {"<layer>": [...]}}: the house style and worked examples the
producing agent set and the owner approved). Every generated item is anchored to a cue-sheet beat plus a recorded action
label or a range of that beat's word indexes; scripts/model-specs-resolve.mjs places them and
scripts/validate-model-specs.mjs is the gate.

Without --run it only prints the quote: one row per layer with its estimated upper-bound dollars. With --run it sends each
request that has not been paid for before, writes plan/model-specs/<layer>.json, caches the answer under
plan/model-specs/cache/<requestSha256>.json and appends one line per request to qa/spend-ledger.jsonl. The request hash
covers the whole request (model, system prefix, schema, beat data, effort, max_tokens), so an identical request never pays
twice. A refusal is recorded and never resent unchanged. Truncation or an invalid answer gets one automatic retry (with the
validation error included); after that the layer is listed in plan/model-specs/fallback-needed.json and the exit is
non-zero: a person writes a simpler kit visual. Never a silent fallback.

The key is read by NAME from ANTHROPIC_API_KEY_BACKUP (or --key-env) and passed explicitly in the request header. It is
never printed or stored. ANTHROPIC_ADMIN_KEY only reports cost and is refused here; ANTHROPIC_API_KEY (the SDK default) is
refused too. Direct HTTPS to the Messages API with the standard library; no SDK and no CLI.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import route_media

SCHEMA = "media-studio/model-specs/1"
GENERATOR = "media-studio/generate-specs"
LANE = "claude-haiku-specs"
MESSAGES_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"
DEFAULT_MODEL = "claude-haiku-5-5"
DEFAULT_KEY_ENV = "ANTHROPIC_API_KEY_BACKUP"
REFUSED_KEY_ENVS = {
    "ANTHROPIC_ADMIN_KEY": "the Admin key only reports what a run cost and never generates",
    "ANTHROPIC_API_KEY": "SDKs read it by default; this lane uses its own key, passed explicitly",
}
LAYERS = ("moments", "overlays", "captions", "diagram")
LIST_FIELD = {"moments": "moments", "overlays": "overlays", "captions": "chunks", "diagram": "diagrams"}
EFFORTS = ("low", "medium")
VISUAL_LAYERS = ("overlays", "diagram")
REGIONS = ("top-left", "top-right", "bottom-left", "bottom-right", "left-panel", "right-panel", "lower-third", "fullscreen")
SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schemas" / "model-specs"
# Claude Haiku 5.5 list prices per million tokens on prompts up to 100,000 tokens, read from the Claude Platform docs on
# 2026-11-10. The cache-write rate is not in the lane note: 1.25x input (the 5-minute cache multiplier) is an assumption.
USD_PER_MTOK = {"input": 0.10, "output": 0.50, "cache_read": 0.01, "cache_write": 0.125}
USD_BASIS = "actual usage from the response at the Claude Haiku 5.5 list prices (cache writes at 1.25x input, assumed)"
MAX_TOKENS_FACTOR = 4          # hidden thinking counts toward max_tokens
MAX_TOKENS_FLOOR = 1024
MAX_TOKENS_CAP = 32000
RETRY_MAX_TOKENS_CAP = 64000
CHARS_PER_TOKEN = 3            # deliberately pessimistic; the quote is an upper bound
TEXT_LIMITS = {"overlays": 48, "captions": 84, "diagram": 160}   # ranges live in code, not in the model-facing schema

SYSTEM_PREFIX = """You write layer data for a film that is built on a real screen recording, its real narration and its cue sheet.
What you write is added on top of the recording to make it easier to follow. It must never replace the recording, retime it or hide it.

Rules:
1. Anchor every item to a beat in the data: beatId, plus either a recorded action label of that beat (anchor "action", copy the label exactly) or a range of that beat's spoken word indexes (anchor "words"). Word indexes are 0-based positions in the beat's words list. When anchor is "action", set fromWord and toWord to 0; when anchor is "words", set actionLabel to "".
2. Never write times, durations, pixels or coordinates. Code does timing and layout.
3. Positions are named regions only: top-left, top-right, bottom-left, bottom-right, left-panel, right-panel, lower-third, and fullscreen where the schema allows it. Choose a region away from where the action happens; never cover the pointer, the active element or the next click target.
4. Explain or label only what the recording shows and what was said. Never show a feature, result or step the recording does not contain.
5. Less is a valid answer. Most seconds of a good recording need nothing. Return an empty list when nothing needs help.
6. Keep text to a few words. The note field is one short sentence for the reviewer. There is no reasoning field; do not add one.
"""

LAYER_RULES = {
    "moments": "Layer: moments. Say where a viewer needs help: a fast run of actions (pace), a term used without explanation (jargon), a small or low-contrast target (target), something important out of frame (offscreen), a long wait (wait). One moment per place. Do not propose visuals here.",
    "overlays": "Layer: overlays. Callouts, step captions, term cards (when jargon is first spoken), zoom regions (a crop of the real footage) and chapter cards. One explanatory overlay at a time. Text of a few words; a zoom has empty text.",
    "captions": "Layer: captions. Split each beat's spoken words into readable chunks: at most two lines of 42 characters, 84 characters in all. text is exactly the words fromWord to toWord in order; you may fix punctuation and line breaks, never reword. emphasis lists word indexes inside the chunk. Cover every spoken word once, in order.",
    "approved": "approvedMoments lists the moments a person approved. Write items only for those moments.",
    "diagram": "Layer: diagram. Only where a beat explains structure, a flow or a mechanism the recording cannot show. One question per diagram, about 7 to 12 nodes, labels of a few words, Mermaid or D2 source in the source field, and a one-sentence caption. Prefer a side panel; fullscreen only at a natural pause with no action in it.",
}


class SpecsError(Exception):
    pass


# ---- money and size

def estimate_tokens(text):
    return math.ceil(len(text) / CHARS_PER_TOKEN)


def expected_output_tokens(layer, beats):
    n = len(beats)
    spoken = sum(len((b.get("narration") or {}).get("words") or []) for b in beats)
    return {"moments": 60 + 80 * n, "overlays": 80 + 120 * n, "captions": 60 + 12 * spoken, "diagram": 150 + 200 * n}[layer]


def max_tokens_for(layer, beats):
    return min(MAX_TOKENS_CAP, max(MAX_TOKENS_FLOOR, MAX_TOKENS_FACTOR * expected_output_tokens(layer, beats)))


def quote_usd(input_tokens, max_tokens):
    """Upper bound for one request: every input token uncached, every allowed output token spent."""
    return round((input_tokens * USD_PER_MTOK["input"] + max_tokens * USD_PER_MTOK["output"]) / 1e6, 8)


def actual_usd(usage):
    u = usage or {}
    total = (int(u.get("input_tokens") or 0) * USD_PER_MTOK["input"] + int(u.get("output_tokens") or 0) * USD_PER_MTOK["output"]
             + int(u.get("cache_read_input_tokens") or 0) * USD_PER_MTOK["cache_read"]
             + int(u.get("cache_creation_input_tokens") or 0) * USD_PER_MTOK["cache_write"])
    return round(total / 1e6, 10)


# ---- request

def model_schema(layer):
    schema = json.loads((SCHEMA_DIR / f"{layer}.schema.json").read_text(encoding="utf-8"))
    schema.pop("$schema", None)
    schema.pop("$id", None)
    return schema


def structured_output_fields(schema, effort):
    """UNVERIFIED against the live API docs in this change: the Messages API field names for structured outputs and
    effort. Every other part of the request is the long-standing Messages shape. If the API names them differently,
    change only this function (and its test)."""
    return {"output_config": {"effort": effort, "format": {"type": "json_schema", "schema": schema}}}


def beat_data(beat):
    narration = beat.get("narration") or {}
    actions = [{"label": a["label"], "kind": a.get("kind"), "target": a.get("target")} for a in beat.get("actions") or [] if a.get("label")]
    return {"beatId": beat["beat"], "seconds": round(float(beat.get("slot_end", 0)) - float(beat.get("slot_start", 0)), 2),
            "screen": (beat.get("screen") or {}).get("kind"), "text": narration.get("text", ""),
            "words": [w.get("w", "") for w in narration.get("words") or []], "actions": actions,
            "expectedState": beat.get("expected_ui_state")}


def system_text(layer, brief, approved=False):
    parts = [SYSTEM_PREFIX, LAYER_RULES[layer]] + ([LAYER_RULES["approved"]] if approved else [])
    if brief.get("style"):
        parts.append("House style: " + str(brief["style"]).strip())
    examples = (brief.get("examples") or {}).get(layer)
    if examples:
        parts.append("Worked examples for this layer (the pattern to follow, not content to copy):\n" + json.dumps(examples, indent=1, sort_keys=True))
    return "\n\n".join(parts)


def build_body(layer, beats, brief, model, effort, approved=None):
    data = {"layer": layer, "regions": list(REGIONS), "beats": [beat_data(b) for b in beats]}
    if approved is not None:
        data["approvedMoments"] = approved
    return {
        "model": model,
        "max_tokens": max_tokens_for(layer, beats),
        "system": [{"type": "text", "text": system_text(layer, brief, approved is not None), "cache_control": {"type": "ephemeral"}}],
        "messages": [{"role": "user", "content": json.dumps(data, sort_keys=True)}],
        **structured_output_fields(model_schema(layer), effort),
    }


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def request_key(body):
    return sha256_text(canonical({"url": MESSAGES_URL, "anthropicVersion": ANTHROPIC_VERSION, "body": body}))


def body_text(body):
    return "".join(s["text"] for s in body["system"]) + "".join(m["content"] for m in body["messages"])


def http_post_json(url, headers, body, timeout=240):
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers={**headers, "content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        detail = e.read()[:300].decode("utf-8", "replace")
        raise SpecsError(f"Messages API returned HTTP {e.code}: {detail}") from None
    except (urllib.error.URLError, TimeoutError) as e:
        raise SpecsError(f"Messages API request failed: {type(e).__name__}") from None


# ---- validation of an answer

def schema_errors(value, schema, path="$"):
    """The subset of JSON Schema the model-facing schemas use: object, array, string, integer, enum."""
    kind = schema.get("type")
    errs = []
    if kind == "object":
        if not isinstance(value, dict):
            return [f"{path} must be an object"]
        props = schema.get("properties", {})
        errs += [f"{path}.{k} is missing" for k in schema.get("required", []) if k not in value]
        if schema.get("additionalProperties") is False:
            errs += [f"{path}.{k} is not allowed" for k in value if k not in props]
        for k, v in value.items():
            if k in props:
                errs += schema_errors(v, props[k], f"{path}.{k}")
    elif kind == "array":
        if not isinstance(value, list):
            return [f"{path} must be an array"]
        for i, v in enumerate(value):
            errs += schema_errors(v, schema.get("items", {}), f"{path}[{i}]")
    elif kind == "string" and not isinstance(value, str):
        errs.append(f"{path} must be a string")
    elif kind == "integer" and (not isinstance(value, int) or isinstance(value, bool)):
        errs.append(f"{path} must be an integer")
    if "enum" in schema and value not in schema["enum"]:
        errs.append(f"{path} must be one of {', '.join(schema['enum'])}")
    return errs


def norm_word(word):
    return "".join(ch for ch in str(word).lower() if ch.isalnum() or ch == "'")


def anchor_errors(item, beat, where):
    words = (beat.get("narration") or {}).get("words") or []
    if item.get("anchor") == "action":
        labels = [str(a.get("label")) for a in beat.get("actions") or [] if a.get("label")]
        if str(item.get("actionLabel", "")).lower() not in [l.lower() for l in labels]:
            return [f"{where}: action \"{item.get('actionLabel')}\" is not a recorded action of {beat['beat']} (recorded: {', '.join(labels) or 'none'})"]
        return []
    return word_range_errors(item, words, beat["beat"], where)


def word_range_errors(item, words, beat_id, where):
    lo, hi = item.get("fromWord"), item.get("toWord")
    if not (isinstance(lo, int) and isinstance(hi, int) and 0 <= lo <= hi < len(words)):
        return [f"{where}: words {lo}-{hi} are outside {beat_id}, which has words 0-{len(words) - 1}"]
    return []


def semantic_errors(layer, output, beats):
    by_id = {b["beat"]: b for b in beats}
    order = [b["beat"] for b in beats]
    errs = []
    for i, item in enumerate(output.get(LIST_FIELD[layer], [])):
        where = f"{LIST_FIELD[layer]}[{i}]"
        beat = by_id.get(item.get("beatId"))
        if not beat:
            errs.append(f"{where}: beatId {item.get('beatId')} is not a beat in the data (beats: {', '.join(order)})")
            continue
        if layer == "captions":
            words = (beat.get("narration") or {}).get("words") or []
            rng = word_range_errors(item, words, beat["beat"], where)
            errs += rng
            if rng:
                continue
            spoken = [norm_word(w.get("w")) for w in words[item["fromWord"]:item["toWord"] + 1]]
            written = [t for t in (norm_word(t) for t in str(item.get("text", "")).split()) if t]
            if spoken != written:
                errs.append(f"{where}: text must be the spoken words {item['fromWord']}-{item['toWord']} of {beat['beat']} in order ({' '.join(spoken)}); punctuation may change, words may not")
            outside = [e for e in item.get("emphasis", []) if not item["fromWord"] <= e <= item["toWord"]]
            if outside:
                errs.append(f"{where}: emphasis {outside} is outside the chunk's words {item['fromWord']}-{item['toWord']}")
        else:
            errs += anchor_errors(item, beat, where)
        if layer == "diagram":
            if item.get("toBeatId") not in by_id or order.index(item["toBeatId"]) < order.index(beat["beat"]):
                errs.append(f"{where}: toBeatId {item.get('toBeatId')} must be {beat['beat']} or a later beat in the data")
        limit = TEXT_LIMITS.get(layer)
        field = "caption" if layer == "diagram" else "text"
        if limit and len(str(item.get(field, ""))) > limit:
            errs.append(f"{where}: {field} is {len(str(item.get(field, '')))} characters; at most {limit}")
    return errs


def answer_text(resp):
    return "".join(block.get("text", "") for block in resp.get("content") or [] if block.get("type") == "text")


# ---- files

def load_json(path, default=None):
    p = Path(path)
    if not p.exists():
        return default
    return json.loads(p.read_text(encoding="utf-8-sig"))


def write_json(path, data):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return hashlib.sha256(p.read_bytes()).hexdigest()


def file_ref(job, rel):
    p = job / rel
    return {"path": rel, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} if p.exists() else None


def append_ledger(job, entry):
    path = job / "qa" / "spend-ledger.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry) + "\n")


def specs_dir(job):
    return job / "plan" / "model-specs"


def record_fallback(job, entries, cleared):
    path = specs_dir(job) / "fallback-needed.json"
    current = (load_json(path, {}) or {}).get("entries", [])
    keep = [e for e in current if e["layer"] not in cleared and e["layer"] not in {x["layer"] for x in entries}]
    merged = keep + entries
    if merged:
        write_json(path, {"schema": SCHEMA, "generator": GENERATOR,
                          "rule": "Each listed layer needs a simpler kit visual written by a person, or a changed request. Never a silent fallback.",
                          "entries": merged})
    elif path.exists():
        path.unlink()


# ---- the run

def check_key_name(name):
    if name in REFUSED_KEY_ENVS:
        raise SpecsError(f"--key-env {name} is refused: {REFUSED_KEY_ENVS[name]}. Use {DEFAULT_KEY_ENV}.")


def lane_status(policy):
    lane = next((l for l in policy["lanes"] if l["id"] == LANE), None)
    if not lane:
        raise SpecsError(f"lane {LANE} is not in policy/provider-routing.json")
    if lane["status"] not in route_media.USABLE:
        raise SpecsError(f"lane {LANE} is {lane['status']} in policy/provider-routing.json; nothing is sent")
    return lane["status"]


def plan_work(job, args, policy):
    check_key_name(args.key_env)
    layers = [l for l in (args.layers or "").split(",") if l]
    unknown = [l for l in layers if l not in LAYERS]
    if unknown or not layers:
        raise SpecsError(f"unknown layer {', '.join(unknown) or '(none)'}; layers are {', '.join(LAYERS)}")
    status = lane_status(policy)
    sheet = load_json(job / "plan" / "cue-sheet.json")
    if not sheet or not sheet.get("beats"):
        raise SpecsError("plan/cue-sheet.json is missing or has no beats; build it with build-cue-sheet.mjs first")
    beats = sheet["beats"]
    only = [b for b in (args.beats or "").split(",") if b]
    if only:
        missing = [b for b in only if b not in {x["beat"] for x in beats}]
        if missing:
            raise SpecsError(f"beat {', '.join(missing)} is not in plan/cue-sheet.json")
        beats = [b for b in beats if b["beat"] in only]
    brief = load_json(job / "story" / "model-specs-brief.json", {}) or {}
    approved = approved_moments(job)
    rows, problems = [], []
    for layer in layers:
        body = build_body(layer, beats, brief, args.model, args.effort, approved if layer in VISUAL_LAYERS else None)
        key = request_key(body)
        cached = load_json(specs_dir(job) / "cache" / f"{key}.json")
        if cached and cached.get("refused"):
            problems.append(f"{layer}: this exact request was refused before (request {key[:12]}); change the input or the brief before sending it again")
        hit = bool(cached and "output" in cached)
        est = quote_usd(estimate_tokens(body_text(body)), body["max_tokens"])
        rows.append({"layer": layer, "model": args.model, "effort": args.effort, "maxTokens": body["max_tokens"], "key": key,
                     "cached": hit, "estimateUsd": 0.0 if hit else est, "body": body})
    return sheet, beats, rows, problems, status


def approved_moments(job):
    """The moments layer once a person has reviewed it and set approvedBy; until then visual layers see every beat."""
    doc = load_json(specs_dir(job) / "moments.json", {}) or {}
    if not str(doc.get("approvedBy") or "").strip():
        return None
    return (doc.get("output") or {}).get("moments", [])


def layer_document(job, row, output, now):
    inputs = {"cueSheet": file_ref(job, "plan/cue-sheet.json")}
    brief = file_ref(job, "story/model-specs-brief.json")
    if brief:
        inputs["brief"] = brief
    if row["layer"] in VISUAL_LAYERS and approved_moments(job) is not None:
        inputs["moments"] = file_ref(job, "plan/model-specs/moments.json")
    return {"schema": SCHEMA, "generator": GENERATOR, "layer": row["layer"], "lane": LANE, "model": row["model"],
            "effort": row["effort"], "requestSha256": row["key"], "createdAt": now, "inputs": inputs, "output": output}


def send(job, row, beats, post, headers, budget, stamp):
    """One request and at most one automatic retry. Returns (output or None, fallback entry or None, spent)."""
    body = row["body"]
    schema = body["output_config"]["format"]["schema"] if "output_config" in body else model_schema(row["layer"])
    spent = 0.0
    prompt_sha = sha256_text(body_text(body))
    for attempt in (1, 2):
        if attempt == 2:
            retry_quote = quote_usd(estimate_tokens(body_text(body)), body["max_tokens"])
            if budget["spent"] + retry_quote > budget["cap"]:
                return None, {"reason": "cap", "detail": f"the retry (~${retry_quote:.6f}) would pass --max-usd {budget['cap']}"}, spent
        try:
            resp = post(MESSAGES_URL, headers, body)
        except SpecsError as e:
            return None, {"reason": "error", "detail": str(e)}, spent
        usage = resp.get("usage") or {}
        usd = actual_usd(usage)
        spent += usd
        budget["spent"] += usd
        stop = resp.get("stop_reason")
        line = {"at": stamp, "kind": "spec", "lane": LANE, "layer": row["layer"], "model": resp.get("model") or row["model"],
                "effort": row["effort"], "attempt": attempt, "stopReason": stop, "maxTokens": body["max_tokens"], "usd": usd,
                "usdBasis": USD_BASIS, "usage": usage, "requestSha256": row["key"], "promptSha256": prompt_sha, "fileSha256": None}
        if stop == "refusal":
            append_ledger(job, line)
            write_json(specs_dir(job) / "cache" / f"{row['key']}.json", {"refused": True, "at": stamp, "layer": row["layer"]})
            return None, {"reason": "refusal", "detail": "the model refused; the request is not resent unchanged"}, spent
        if stop == "max_tokens":
            append_ledger(job, line)
            if attempt == 1:
                body = {**body, "max_tokens": min(RETRY_MAX_TOKENS_CAP, body["max_tokens"] * 2)}
                continue
            return None, {"reason": "truncated", "detail": f"truncated at max_tokens {body['max_tokens']} twice"}, spent
        if stop not in ("end_turn", "stop_sequence"):
            append_ledger(job, line)
            return None, {"reason": "unexpected", "detail": f"stop_reason {stop}"}, spent
        text = answer_text(resp)
        try:
            output = json.loads(text)
            errs = schema_errors(output, schema)
            if not errs:
                errs = semantic_errors(row["layer"], output, beats)
        except json.JSONDecodeError as e:
            output, errs = None, [f"the answer is not JSON: {e.msg}"]
        if errs:
            append_ledger(job, line)
            if attempt == 1:
                feedback = "That answer failed validation:\n- " + "\n- ".join(errs[:20]) + "\nReturn the whole corrected object."
                body = {**body, "messages": body["messages"] + [{"role": "assistant", "content": text or "{}"},
                                                                 {"role": "user", "content": feedback}]}
                continue
            return None, {"reason": "invalid", "detail": "; ".join(errs[:5])}, spent
        doc = layer_document(job, row, output, stamp)
        line["fileSha256"] = write_json(specs_dir(job) / f"{row['layer']}.json", doc)
        append_ledger(job, line)
        write_json(specs_dir(job) / "cache" / f"{row['key']}.json", {"layer": row["layer"], "at": stamp, "output": output})
        return output, None, spent
    return None, {"reason": "invalid", "detail": "no answer"}, spent


def run(job, args, env=None, post=None, now=None, policy=None):
    job, env, post = Path(job), env if env is not None else os.environ, post or http_post_json
    policy = policy or route_media.load()
    sheet, beats, rows, problems, status = plan_work(job, args, policy)
    todo = [r for r in rows if not r["cached"]]
    total = round(sum(r["estimateUsd"] for r in todo), 8)
    key_set = bool((env.get(args.key_env) or "").strip())
    report = {"schema": SCHEMA, "job": str(job), "lane": LANE, "laneStatus": status, "mode": "run" if args.run else "quote",
              "key": {"env": args.key_env, "set": key_set},
              "requests": [{k: v for k, v in r.items() if k != "body"} for r in rows], "problems": problems,
              "estimateUsd": total, "capUsd": args.max_usd, "generated": [], "fallbackNeeded": [], "actualUsd": 0.0}
    if problems or not args.run:
        report["ok"] = not problems
        return report
    if todo and not key_set:
        raise SpecsError(f"{args.key_env} is not set; nothing was sent")
    if len(todo) > args.max_requests:
        raise SpecsError(f"{len(todo)} requests exceeds --max-requests {args.max_requests}")
    if total > args.max_usd:
        raise SpecsError(f"estimate ${total} exceeds --max-usd {args.max_usd}; raise it only after the owner has seen the quote")
    stamp = (now or datetime.now(timezone.utc)).isoformat(timespec="seconds")
    headers = {"x-api-key": (env.get(args.key_env) or "").strip(), "anthropic-version": ANTHROPIC_VERSION} if todo else {}
    budget = {"spent": 0.0, "cap": args.max_usd}
    fallbacks, cleared = [], set()
    for row in rows:
        if row["cached"]:
            cached = load_json(specs_dir(job) / "cache" / f"{row['key']}.json")
            current = load_json(specs_dir(job) / f"{row['layer']}.json", {}) or {}
            if current.get("requestSha256") != row["key"] or current.get("output") != cached["output"]:
                write_json(specs_dir(job) / f"{row['layer']}.json", layer_document(job, row, cached["output"], stamp))
            cleared.add(row["layer"])
            continue
        output, fallback, spent = send(job, row, beats, post, headers, budget, stamp)
        report["actualUsd"] = round(report["actualUsd"] + spent, 10)
        if fallback:
            entry = {"layer": row["layer"], "requestSha256": row["key"], "at": stamp, **fallback}
            fallbacks.append(entry)
            append_ledger(job, {"at": stamp, "kind": "fallback-needed", "lane": LANE, **{k: entry[k] for k in ("layer", "reason", "detail", "requestSha256")}})
        else:
            cleared.add(row["layer"])
            report["generated"].append({"layer": row["layer"], "file": f"plan/model-specs/{row['layer']}.json",
                                        "items": len(output.get(LIST_FIELD[row["layer"]], []))})
    if fallbacks or (specs_dir(job) / "fallback-needed.json").exists():
        record_fallback(job, fallbacks, cleared)
    report["fallbackNeeded"] = fallbacks
    report["ok"] = not fallbacks
    return report


def exit_code(report):
    return 0 if report.get("ok") else 1


def print_report(report):
    print(f"{report['mode'].upper()}  lane {report['lane']} ({report['laneStatus']})  job {report['job']}")
    print(f"  key {report['key']['env']}: {'set' if report['key']['set'] else 'NOT SET'}")
    for r in report["requests"]:
        state = "cached" if r["cached"] else f"~${r['estimateUsd']:.6f}"
        print(f"  {r['layer']:9} {r['model']:18} effort {r['effort']:6} max_tokens {r['maxTokens']:6} {state}")
    for p in report["problems"]:
        print("  PROBLEM:", p)
    print(f"estimate for new requests: ${report['estimateUsd']:.6f}  (cap ${report['capUsd']:.2f}; an upper bound, actual cost is recorded)")
    for g in report["generated"]:
        print(f"  wrote {g['file']} ({g['items']} items)")
    for f in report["fallbackNeeded"]:
        print(f"  FALLBACK NEEDED {f['layer']}: {f['reason']}: {f['detail']}")
    if report["mode"] == "run":
        print(f"actual spend: ${report['actualUsd']:.6f}")
    elif report["requests"] and not report["problems"]:
        print("nothing spent. Add --run to send.")
    print("RESULT:", "ok" if report["ok"] else "FAILED")


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("job")
    ap.add_argument("--layers", default="moments", help=f"comma-separated: {', '.join(LAYERS)}")
    ap.add_argument("--beats", help="comma-separated beat ids from the cue sheet (default: every beat)")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--effort", choices=EFFORTS, default="low")
    ap.add_argument("--max-usd", type=float, default=0.5)
    ap.add_argument("--max-requests", type=int, default=12)
    ap.add_argument("--key-env", default=DEFAULT_KEY_ENV, help="NAME of the variable holding the key; never the value")
    ap.add_argument("--run", action="store_true", help="spend: send the requests that have not been paid for")
    ap.add_argument("--json", action="store_true")
    return ap


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        report = run(args.job, args)
    except SpecsError as e:
        print("ERROR:", e)
        return 1
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report)
    return exit_code(report)


if __name__ == "__main__":
    sys.exit(main())
