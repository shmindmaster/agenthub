#!/usr/bin/env python
"""Retrieve layered evidence to augment a document being written.

Logic only. Every layer definition, rendering rule, descriptor and piece of
guidance lives in config/evidence-layers.json. Nothing domain-specific is
hard-coded here.

This returns material. It does not score an opportunity, rank it, or advise
whether to pursue it.
"""
import argparse
import json
import os
import sys
import urllib.request

PKG_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CONFIG = os.path.join(PKG_ROOT, "config", "evidence-layers.json")


def load_config(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def post(url, body, timeout=180):
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as fh:
        return json.load(fh)


def embed(cfg, text):
    body = {"model": cfg["models"]["query"], "input": [text], "encoding_format": "float"}
    return post(cfg["services"]["embeddings"], body)["data"][0]["embedding"]


def rendering_mode(cfg, payload, source_root):
    rules = cfg["renderingRules"]
    sensitivity = payload.get("sensitivity")

    for flag in rules["excludeIfFlagged"]:
        if payload.get(flag) is True:
            return "EXCLUDE"
    if sensitivity in rules["hardExcludeSensitivity"]:
        return "EXCLUDE"

    for prefix, mode in rules["byRootPrefix"].items():
        if str(source_root).startswith(prefix):
            return mode
    for flag, mode in rules["byFlag"].items():
        if payload.get(flag) is True:
            return mode
    if sensitivity in rules["bySensitivity"]:
        return rules["bySensitivity"][sensitivity]
    return rules["default"]


def describe_anonymously(cfg, payload):
    spec = cfg["anonymousDescriptors"]
    subsector = payload.get("subsector")
    if subsector and subsector in spec["bySubsector"]:
        return spec["bySubsector"][subsector]

    def phrase(raw):
        words = raw.replace("_", " ").lower()
        article = "an " if words[:1] in "aeiou" else "a "
        return f"{article}{words} {spec['fallbackSuffix']}"

    if subsector:
        return phrase(subsector)
    industry = (payload.get("industry") or "").split("_", 1)
    if len(industry) > 1 and industry[1]:
        return phrase(industry[1])
    return spec["unknown"]


def retrieve(cfg, source_root, shapes, pool):
    seen, found = set(), []
    for shape in shapes:
        body = {
            "query": embed(cfg, shape),
            "using": "dense",
            "limit": pool,
            "filter": {
                "must": [{"key": "source_root", "match": {"value": source_root}}],
                "must_not": [{"key": flag, "match": {"value": True}}
                             for flag in cfg["renderingRules"]["excludeIfFlagged"]],
            },
            "with_payload": {"include": [
                "title", "client", "project", "sensitivity", "never_name",
                "do_not_send", "industry", "subsector", "text", "document_id"]},
        }
        url = f"{cfg['services']['qdrant']}/collections/{cfg['collection']}/points/query"
        for point in post(url, body)["result"]["points"]:
            payload = point["payload"]
            text = (payload.get("text") or "").strip()
            if not text:
                continue
            key = (str(payload.get("title")), text[:110])
            if key in seen:
                continue
            seen.add(key)
            found.append({"payload": payload, "text": text})
    return found


def rerank(cfg, intent, candidates, keep):
    if not candidates:
        return []
    tuning = cfg["retrieval"]
    scored = []
    for start in range(0, len(candidates), tuning["rerankBatchSize"]):
        batch = candidates[start:start + tuning["rerankBatchSize"]]
        result = post(cfg["services"]["rerank"], {
            "model": cfg["models"]["rerank"],
            "query": intent,
            "documents": [c["text"][:tuning["rerankCharLimit"]] for c in batch],
        })["results"]
        for entry in result:
            candidate = batch[entry["index"]]
            candidate["relevance"] = entry["relevance_score"]
            scored.append(candidate)

    scored.sort(key=lambda c: -c["relevance"])
    picked, per_document = [], {}
    for candidate in scored:
        title = str(candidate["payload"].get("title"))
        if per_document.get(title, 0) >= tuning["maxChunksPerDocument"]:
            continue
        per_document[title] = per_document.get(title, 0) + 1
        picked.append(candidate)
        if len(picked) >= keep:
            break
    return picked


def collect_shapes(args):
    shapes = list(args.shape or [])
    if args.shapes_file:
        with open(args.shapes_file, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    shapes.append(line)
    return shapes


def build_report(cfg, label, shapes, results):
    tuning = cfg["retrieval"]
    lines = [f"# Evidence augmentation - {label}", "", "Problem shapes used:"]
    lines += [f"- {s}" for s in shapes]
    lines += [""]

    for layer in cfg["layers"]:
        items = results.get(layer["id"], [])
        lines += [f"## {layer['id']} - {layer['purpose']}", ""]
        if not items:
            lines += ["_no material returned for these shapes_", ""]
            continue
        for item in items:
            who = item["render_as"]
            citation = item["title"]
            if item.get("project"):
                citation += f" | {item['project']}"
            heading = (f"**[{item['mode']}]** {citation}" if who is None
                       else f"**[{item['mode']}] {who}** - {citation}")
            lines += [heading, "", f"> {item['text'][:tuning['quoteCharLimit']].strip()}", ""]

    lines += ["---", "**Rendering modes**", ""]
    lines += [f"- `{mode}` - {text}" for mode, text in cfg["renderingModes"].items()]
    lines += ["", cfg["invariant"]]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True,
                        help="what you are writing, e.g. 'Netflix - Sr EM, Agent Platform'")
    parser.add_argument("--shape", action="append",
                        help="problem-shape primitive (repeatable): the STRUCTURE, not the job title")
    parser.add_argument("--shapes-file",
                        help="file of shapes, one per line; '#' comments ignored")
    parser.add_argument("--per-layer", type=int, default=5)
    parser.add_argument("--pool", type=int)
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument("--out", default="evidence-augmentation")
    args = parser.parse_args()

    cfg = load_config(args.config)
    shapes = collect_shapes(args)
    if not shapes:
        parser.error("supply at least one --shape or a --shapes-file")

    pool = args.pool or cfg["retrieval"]["poolPerShape"]
    intent = args.label + " | " + " | ".join(shapes)
    results, record = {}, {"label": args.label, "shapes": shapes, "layers": {}}

    for layer in cfg["layers"]:
        candidates = retrieve(cfg, layer["sourceRoot"], shapes, pool)
        items = []
        for candidate in rerank(cfg, intent, candidates, args.per_layer):
            payload = candidate["payload"]
            mode = rendering_mode(cfg, payload, layer["sourceRoot"])
            if mode == "EXCLUDE":
                continue
            if mode in ("METHOD_OWN", "CITE_ONLY", "VOICE_ONLY"):
                who = None
            elif mode == "ANONYMIZE":
                who = describe_anonymously(cfg, payload)
            else:
                who = payload.get("client") or None
            items.append({
                "mode": mode, "render_as": who,
                "title": payload.get("title"), "project": payload.get("project"),
                "client_raw": payload.get("client"), "sensitivity": payload.get("sensitivity"),
                "document_id": payload.get("document_id"),
                "relevance": round(candidate["relevance"], 3),
                "text": candidate["text"][:cfg["retrieval"]["storedTextCharLimit"]],
            })
        results[layer["id"]] = items
        record["layers"][layer["id"]] = items
        print(f"  {layer['id']:<10} pooled {len(candidates):>4} -> kept {len(items)}", file=sys.stderr)

    with open(f"{args.out}.md", "w", encoding="utf-8") as fh:
        fh.write(build_report(cfg, args.label, shapes, results))
    with open(f"{args.out}.json", "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=1)
    print(f"\nwrote {args.out}.md / {args.out}.json", file=sys.stderr)


if __name__ == "__main__":
    main()
