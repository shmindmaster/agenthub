"""Offline tests for the model-written specs adapter. No provider is called: every request goes through a fake."""
import argparse
import contextlib
import copy
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import generate_specs as g

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schemas" / "model-specs"
LAYERS = ("moments", "overlays", "captions", "diagram")
REGIONS = {"top-left", "top-right", "bottom-left", "bottom-right", "left-panel", "right-panel", "lower-third", "fullscreen"}
RANGE_OR_LENGTH = {"minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength", "maxLength",
                   "minItems", "maxItems", "minProperties", "maxProperties"}
NO_REASONING = ("reason" + "ing", "rationale", "thinking", "thought", "explanation", "chain")
NO_PIXELS_OR_TIMES = {"x", "y", "width", "height", "left", "top", "start", "end", "seconds", "startSeconds", "endSeconds", "time", "at"}


def load_schema(layer):
    return json.loads((SCHEMA_DIR / f"{layer}.schema.json").read_text(encoding="utf-8"))


def walk(node, depth=0, path="$"):
    """Yield (path, node, object depth) for every schema node."""
    if isinstance(node, dict):
        if node.get("type") == "object":
            depth += 1
        yield path, node, depth
        for key, value in node.get("properties", {}).items():
            yield from walk(value, depth, f"{path}.{key}")
        if "items" in node:
            yield from walk(node["items"], depth, f"{path}[]")


def item_schema(layer):
    root = load_schema(layer)
    (array,) = root["properties"].values()
    return array["items"]


class ModelFacingSchemas(unittest.TestCase):
    def test_one_schema_per_layer(self):
        self.assertEqual(sorted(p.name for p in SCHEMA_DIR.glob("*.schema.json")), sorted(f"{l}.schema.json" for l in LAYERS))

    def test_every_object_closes_and_requires_every_property(self):
        for layer in LAYERS:
            for path, node, _ in walk(load_schema(layer)):
                if node.get("type") == "object":
                    self.assertIs(node.get("additionalProperties"), False, f"{layer} {path}")
                    self.assertEqual(sorted(node.get("required", [])), sorted(node.get("properties", {})), f"{layer} {path}")

    def test_no_range_or_length_keywords_and_shallow_nesting(self):
        for layer in LAYERS:
            for path, node, depth in walk(load_schema(layer)):
                self.assertFalse(RANGE_OR_LENGTH & set(node), f"{layer} {path}: {RANGE_OR_LENGTH & set(node)}")
                self.assertLessEqual(depth, 2, f"{layer} {path} nests objects too deep")

    def test_enums_are_lowercase_words(self):
        for layer in LAYERS:
            for path, node, _ in walk(load_schema(layer)):
                for value in node.get("enum", []):
                    # Lowercase, no spaces; region names keep the hyphen of the brief's vocabulary (top-left), d2 keeps its digit.
                    self.assertRegex(value, r"^[a-z][a-z0-9]*(-[a-z]+)?$", f"{layer} {path}")

    def test_a_note_but_never_a_reasoning_field(self):
        for layer in LAYERS:
            props = item_schema(layer)["properties"]
            self.assertIn("note", props, layer)
            for path, node, _ in walk(load_schema(layer)):
                for key in node.get("properties", {}):
                    self.assertFalse(any(bad in key.lower() for bad in NO_REASONING), f"{layer} {path}.{key}")

    def test_positions_are_named_regions_and_nothing_is_a_pixel_or_a_time(self):
        for layer in LAYERS:
            for path, node, _ in walk(load_schema(layer)):
                for key, value in node.get("properties", {}).items():
                    self.assertNotIn(key, NO_PIXELS_OR_TIMES, f"{layer} {path}.{key}")
                    if key in ("region", "placement"):
                        self.assertTrue(set(value["enum"]) <= REGIONS, f"{layer} {path}.{key}")
        self.assertNotIn("fullscreen", item_schema("overlays")["properties"]["region"]["enum"])
        self.assertIn("fullscreen", item_schema("diagram")["properties"]["placement"]["enum"])

    def test_every_item_carries_an_anchor_into_the_cue_sheet(self):
        for layer in LAYERS:
            props = item_schema(layer)["properties"]
            self.assertIn("beatId", props, layer)
            self.assertTrue({"fromWord", "toWord"} <= set(props), layer)
            if layer != "captions":
                self.assertEqual(props["anchor"]["enum"], ["action", "words"], layer)
                self.assertIn("actionLabel", props, layer)
        caption = item_schema("captions")["properties"]
        self.assertEqual(caption["emphasis"]["items"]["type"], "integer")
        diagram = item_schema("diagram")["properties"]
        self.assertEqual(diagram["format"]["enum"], ["mermaid", "d2"])
        self.assertTrue({"source", "caption", "toBeatId"} <= set(diagram))


# ---- synthetic job: two beats of a made-up queue screen, shaped like build-cue-sheet.mjs output

def words(text, start, step=0.3):
    out = []
    for i, w in enumerate(text.split()):
        out.append({"w": w, "start": round(start + i * step, 3), "end": round(start + i * step + 0.25, 3)})
    return out


def cue_sheet():
    return {
        "generator": "media-studio/build-cue-sheet", "schemaVersion": "1.0.0", "mode": "mapped", "durationSeconds": 12.0,
        "beats": [
            {"beat": "S01", "t_start": 0.4, "t_end": 2.85, "slot_start": 0, "slot_end": 6.0,
             "narration": {"text": "Open the queue and pick the first request.", "words": words("Open the queue and pick the first request.", 0.4), "precision": "word"},
             "screen": {"clip": "C1", "kind": "screen"},
             "actions": [{"kind": "click", "label": "Open queue", "target": "Open queue", "action_time": 1.2, "receipt_event_index": 3, "cursor": {"x": 800, "y": 500}},
                         {"kind": "click", "label": None, "target": "row", "action_time": 2.0, "receipt_event_index": 6, "cursor": {"x": 820, "y": 540}}],
             "expected_ui_state": "The queue lists two requests"},
            {"beat": "S02", "t_start": 6.2, "t_end": 8.3, "slot_start": 6.0, "slot_end": 12.0,
             "narration": {"text": "Approve it and the status turns green.", "words": words("Approve it and the status turns green.", 6.2), "precision": "word"},
             "screen": {"clip": "C1", "kind": "screen"},
             "actions": [{"kind": "click", "label": "Approve", "target": "Approve", "action_time": 6.5, "receipt_event_index": 9, "cursor": {"x": 1200, "y": 300}}],
             "expected_ui_state": "Status reads Approved"},
        ],
    }


KEY = "test-key-value-0000"
ENV = {"ANTHROPIC_API_KEY_BACKUP": KEY}


def make_job(root, sheet=None, brief=None):
    job = Path(root) / "film-20261110"
    (job / "plan").mkdir(parents=True)
    (job / "plan" / "cue-sheet.json").write_text(json.dumps(sheet or cue_sheet()), encoding="utf-8")
    if brief:
        (job / "story").mkdir(parents=True, exist_ok=True)
        (job / "story" / "model-specs-brief.json").write_text(json.dumps(brief), encoding="utf-8")
    return job


def args(**kw):
    base = dict(job=None, layers="moments", beats=None, model=g.DEFAULT_MODEL, effort="low", max_usd=0.5, max_requests=12,
                key_env=g.DEFAULT_KEY_ENV, run=False, json=False, retry_fallbacks=False)
    base.update(kw)
    return argparse.Namespace(**base)


def message(payload, stop="end_turn", usage=None):
    text = payload if isinstance(payload, str) else json.dumps(payload)
    return {"id": "msg_test", "type": "message", "role": "assistant", "content": [{"type": "text", "text": text}],
            "stop_reason": stop, "usage": usage or {"input_tokens": 900, "output_tokens": 120, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}


def empty_for(body):
    """A valid "nothing here" answer for whichever layer the request's schema asks for."""
    (name,) = body["output_config"]["format"]["schema"]["properties"]
    return message({name: []})


class FakeMessages:
    def __init__(self, *responses):
        self.calls = []
        self.responses = list(responses)

    def __call__(self, url, headers, body):
        self.calls.append({"url": url, "headers": headers, "body": copy.deepcopy(body)})
        if self.responses:
            nxt = self.responses.pop(0)
            return nxt(body) if callable(nxt) else nxt
        return empty_for(body)


def ledger(job):
    path = job / "qa" / "spend-ledger.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


def all_keys(node):
    if isinstance(node, dict):
        for k, v in node.items():
            yield k
            yield from all_keys(v)
    elif isinstance(node, list):
        for v in node:
            yield from all_keys(v)


class Quote(unittest.TestCase):
    def test_quote_spends_nothing_makes_no_call_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            rep = g.run(job, args(layers="moments,overlays,captions,diagram"), env=ENV, post=fake)
            self.assertEqual(fake.calls, [])
            self.assertEqual(rep["mode"], "quote")
            self.assertTrue(rep["ok"])
            self.assertEqual([r["layer"] for r in rep["requests"]], ["moments", "overlays", "captions", "diagram"])
            self.assertTrue(all(r["estimateUsd"] > 0 for r in rep["requests"]))
            self.assertFalse((job / "plan" / "model-specs").exists())
            self.assertFalse((job / "qa").exists())

    def test_quote_names_the_key_variable_and_never_its_value(self):
        with tempfile.TemporaryDirectory() as d:
            rep = g.run(make_job(d), args(), env=ENV, post=FakeMessages())
            self.assertEqual(rep["key"], {"env": "ANTHROPIC_API_KEY_BACKUP", "set": True})
            self.assertNotIn(KEY, json.dumps(rep))

    def test_the_default_layer_is_moments_so_help_is_asked_for_before_any_visual(self):
        self.assertEqual(g.build_parser().parse_args(["job"]).layers, "moments")
        self.assertEqual(g.build_parser().parse_args(["job"]).model, "claude-haiku-5-5")
        self.assertEqual(g.build_parser().parse_args(["job"]).effort, "low")
        self.assertEqual(g.EFFORTS, ("low", "medium"))

    def test_a_missing_cue_sheet_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            job = Path(d) / "empty"
            job.mkdir()
            with self.assertRaises(g.SpecsError):
                g.run(job, args(), env=ENV, post=FakeMessages())

    def test_an_unknown_layer_or_beat_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            with self.assertRaises(g.SpecsError):
                g.run(job, args(layers="lottie"), env=ENV, post=FakeMessages())
            with self.assertRaises(g.SpecsError):
                g.run(job, args(beats="S09"), env=ENV, post=FakeMessages())

    def test_a_lane_that_is_not_usable_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            policy = g.route_media.load()
            for lane in policy["lanes"]:
                if lane["id"] == "claude-haiku-specs":
                    lane["status"] = "frozen"
            with self.assertRaises(g.SpecsError):
                g.run(make_job(d), args(run=True), env=ENV, post=FakeMessages(), policy=policy)


class KeyNames(unittest.TestCase):
    def test_the_admin_key_name_is_refused_before_anything_even_a_quote(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            with self.assertRaises(g.SpecsError) as cm:
                g.run(job, args(key_env="ANTHROPIC_ADMIN_KEY"), env={"ANTHROPIC_ADMIN_KEY": KEY}, post=fake)
            self.assertIn("ANTHROPIC_ADMIN_KEY", str(cm.exception))
            self.assertEqual(fake.calls, [])
            self.assertNotEqual(g.main([str(job), "--key-env", "ANTHROPIC_ADMIN_KEY"]), 0)

    def test_the_sdk_default_key_name_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(g.SpecsError):
                g.run(make_job(d), args(key_env="ANTHROPIC_API_KEY"), env={"ANTHROPIC_API_KEY": KEY}, post=FakeMessages())

    def test_a_missing_key_stops_a_run_before_any_call(self):
        with tempfile.TemporaryDirectory() as d:
            fake = FakeMessages()
            with self.assertRaises(g.SpecsError) as cm:
                g.run(make_job(d), args(run=True), env={"ANTHROPIC_API_KEY": KEY}, post=fake)
            self.assertIn("ANTHROPIC_API_KEY_BACKUP", str(cm.exception))
            self.assertEqual(fake.calls, [])


class Request(unittest.TestCase):
    def test_one_structured_request_per_layer_with_the_key_passed_in_the_header(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            rep = g.run(job, args(run=True, layers="moments,captions"), env=ENV, post=fake)
            self.assertTrue(rep["ok"], rep)
            self.assertEqual(len(fake.calls), 2)
            call = fake.calls[0]
            self.assertEqual(call["url"], "https://api.anthropic.com/v1/messages")
            self.assertEqual(call["headers"]["x-api-key"], KEY)
            self.assertEqual(call["headers"]["anthropic-version"], "2023-06-01")
            body = call["body"]
            self.assertEqual(body["model"], "claude-haiku-5-5")
            self.assertEqual(body["output_config"]["effort"], "low")
            self.assertEqual(body["output_config"]["format"]["type"], "json_schema")
            schema = load_schema("moments")
            schema.pop("$schema"), schema.pop("$id")
            self.assertEqual(body["output_config"]["format"]["schema"], schema)
            self.assertEqual(fake.calls[1]["body"]["output_config"]["format"]["schema"]["required"], ["chunks"])

    def test_no_sampling_parameters_and_no_prefill(self):
        with tempfile.TemporaryDirectory() as d:
            fake = FakeMessages()
            g.run(make_job(d), args(run=True, layers="moments,overlays,captions,diagram"), env=ENV, post=fake)
            for call in fake.calls:
                keys = set(all_keys(call["body"]))
                for banned in ("temperature", "top_p", "top_k"):
                    self.assertNotIn(banned, keys)
                self.assertEqual(call["body"]["messages"][-1]["role"], "user")

    def test_reusable_material_first_and_the_beat_data_last(self):
        with tempfile.TemporaryDirectory() as d:
            fake = FakeMessages()
            g.run(make_job(d, brief={"style": "Flat, two tones, labels of three words.", "examples": {"moments": [{"beatId": "X"}]}}),
                  args(run=True), env=ENV, post=fake)
            body = fake.calls[0]["body"]
            system = body["system"][0]
            self.assertEqual(system["cache_control"], {"type": "ephemeral"})
            self.assertIn("Flat, two tones", system["text"])
            self.assertIn("never replace", system["text"])
            data = json.loads(body["messages"][0]["content"])
            self.assertEqual([b["beatId"] for b in data["beats"]], ["S01", "S02"])
            self.assertEqual(data["beats"][0]["words"][2], "queue")
            self.assertEqual([a["label"] for a in data["beats"][0]["actions"]], ["Open queue"])

    def test_medium_effort_and_max_tokens_several_times_the_expected_output(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            g.run(job, args(run=True, layers="captions", effort="medium"), env=ENV, post=fake)
            body = fake.calls[0]["body"]
            self.assertEqual(body["output_config"]["effort"], "medium")
            expected = g.expected_output_tokens("captions", cue_sheet()["beats"])
            self.assertGreaterEqual(body["max_tokens"], 4 * expected)

    def test_visual_layers_carry_only_the_moments_a_person_approved(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            moment = {"beatId": "S02", "anchor": "action", "actionLabel": "Approve", "fromWord": 0, "toWord": 0, "reason": "target", "note": "small button"}
            g.run(job, args(run=True), env=ENV, post=FakeMessages(message({"moments": [moment]})))
            fake = FakeMessages()
            g.run(job, args(run=True, layers="overlays"), env=ENV, post=fake)
            self.assertNotIn("approvedMoments", json.loads(fake.calls[0]["body"]["messages"][0]["content"]))
            path = job / "plan" / "model-specs" / "moments.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            doc["approvedBy"] = "owner"
            path.write_text(json.dumps(doc), encoding="utf-8")
            g.run(job, args(run=True, layers="overlays"), env=ENV, post=fake)
            data = json.loads(fake.calls[1]["body"]["messages"][0]["content"])
            self.assertEqual(data["approvedMoments"], [moment])
            layer = json.loads((job / "plan" / "model-specs" / "overlays.json").read_text(encoding="utf-8"))
            self.assertEqual(layer["inputs"]["moments"]["path"], "plan/model-specs/moments.json")

    def test_the_layer_file_records_its_inputs_and_output(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            g.run(job, args(run=True), env=ENV, post=FakeMessages())
            layer = json.loads((job / "plan" / "model-specs" / "moments.json").read_text(encoding="utf-8"))
            self.assertEqual(layer["generator"], "media-studio/generate-specs")
            self.assertEqual(layer["layer"], "moments")
            self.assertEqual(layer["output"], {"moments": []})
            self.assertEqual(layer["inputs"]["cueSheet"]["path"], "plan/cue-sheet.json")
            self.assertEqual(len(layer["inputs"]["cueSheet"]["sha256"]), 64)
            self.assertEqual(len(layer["requestSha256"]), 64)
            self.assertNotIn(KEY, json.dumps(layer))


class Cache(unittest.TestCase):
    def test_an_identical_request_never_pays_twice(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            g.run(job, args(run=True), env=ENV, post=fake)
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 1)
            self.assertTrue(again["requests"][0]["cached"])
            self.assertEqual(again["estimateUsd"], 0)
            self.assertEqual(len(ledger(job)), 1)
            quote = g.run(job, args(), env=ENV, post=fake)
            self.assertTrue(quote["requests"][0]["cached"])

    def test_a_changed_setting_or_input_is_a_new_request(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            g.run(job, args(run=True), env=ENV, post=fake)
            g.run(job, args(run=True, effort="medium"), env=ENV, post=fake)
            sheet = cue_sheet()
            sheet["beats"][0]["expected_ui_state"] = "The queue lists three requests"
            (job / "plan" / "cue-sheet.json").write_text(json.dumps(sheet), encoding="utf-8")
            g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 3)


class Ledger(unittest.TestCase):
    def test_one_ledger_line_per_request_in_the_stills_shape(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            g.run(job, args(run=True), env=ENV, post=FakeMessages())
            (line,) = ledger(job)
            for key in ("at", "kind", "lane", "model", "usd", "usdBasis", "promptSha256", "fileSha256"):
                self.assertIn(key, line)
            self.assertEqual(line["kind"], "spec")
            self.assertEqual(line["lane"], "claude-haiku-specs")
            self.assertEqual(line["layer"], "moments")
            self.assertEqual(line["stopReason"], "end_turn")
            self.assertEqual(line["attempt"], 1)
            self.assertAlmostEqual(line["usd"], 900 * 0.10 / 1e6 + 120 * 0.50 / 1e6, places=9)
            self.assertIn("usage", line["usdBasis"])
            self.assertNotIn(KEY, json.dumps(line))

    def test_estimate_over_the_cap_stops_before_any_call(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            with self.assertRaises(g.SpecsError) as cm:
                g.run(job, args(run=True, layers="moments,overlays,captions,diagram", max_usd=0.0001), env=ENV, post=fake)
            self.assertIn("--max-usd", str(cm.exception))
            self.assertEqual(fake.calls, [])
            self.assertEqual(ledger(job), [])


class StopReasons(unittest.TestCase):
    def fallback(self, job):
        return json.loads((job / "plan" / "model-specs" / "fallback-needed.json").read_text(encoding="utf-8"))["entries"]

    def test_truncation_is_retried_once_with_more_room(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages(message('{"moments": [', stop="max_tokens"))
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertTrue(rep["ok"], rep)
            self.assertEqual(len(fake.calls), 2)
            self.assertGreater(fake.calls[1]["body"]["max_tokens"], fake.calls[0]["body"]["max_tokens"])
            self.assertEqual([l["stopReason"] for l in ledger(job)], ["max_tokens", "end_turn"])

    def test_truncated_twice_records_fallback_needed_and_fails(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            cut = message('{"moments": [', stop="max_tokens")
            fake = FakeMessages(cut, cut)
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertFalse(rep["ok"])
            self.assertEqual(len(fake.calls), 2)
            self.assertEqual([(f["layer"], f["reason"]) for f in rep["fallbackNeeded"]], [("moments", "truncated")])
            self.assertEqual(self.fallback(job)[0]["layer"], "moments")
            self.assertEqual(ledger(job)[-1]["kind"], "fallback-needed")
            self.assertFalse((job / "plan" / "model-specs" / "moments.json").exists())

    def test_a_refusal_is_recorded_and_never_resent_unchanged(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            refusal = message("", stop="refusal")
            refusal["stop_details"] = {"type": "refusal", "category": "cyber"}
            fake = FakeMessages(refusal)
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertFalse(rep["ok"])
            self.assertEqual(len(fake.calls), 1)
            self.assertEqual(rep["fallbackNeeded"][0]["reason"], "refusal")
            self.assertEqual([l["stopReason"] for l in ledger(job) if l["kind"] == "spec"], ["refusal"])
            self.assertEqual(ledger(job)[0]["stopDetails"], {"type": "refusal", "category": "cyber"})
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 1)
            self.assertFalse(again["ok"])
            self.assertIn("refused", " ".join(again["problems"]))

    def test_invalid_output_is_retried_once_with_the_validation_error(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            bad = {"moments": [{"beatId": "S09", "anchor": "words", "actionLabel": "", "fromWord": 0, "toWord": 1, "reason": "jargon", "note": ""}]}
            fake = FakeMessages(message(bad))
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertTrue(rep["ok"], rep)
            self.assertEqual(len(fake.calls), 2)
            retry = fake.calls[1]["body"]["messages"]
            self.assertEqual([m["role"] for m in retry], ["user", "assistant", "user"])
            self.assertIn("S09", retry[-1]["content"])

    def test_invalid_twice_records_fallback_needed_and_main_exits_non_zero(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            bad = message({"moments": [{"beatId": "S01"}]})
            fake = FakeMessages(bad, bad)
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertFalse(rep["ok"])
            self.assertEqual(len(fake.calls), 2)
            self.assertEqual(rep["fallbackNeeded"][0]["reason"], "invalid")
            self.assertEqual(g.exit_code(rep), 1)

    def test_a_caption_that_rewords_the_speech_is_invalid(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            reworded = {"chunks": [{"beatId": "S01", "fromWord": 0, "toWord": 2, "text": "Open a queue", "emphasis": [2], "note": ""}]}
            fake = FakeMessages(message(reworded))
            g.run(job, args(run=True, layers="captions"), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertIn("words", fake.calls[1]["body"]["messages"][-1]["content"])

    def test_a_retry_that_would_pass_the_cap_is_not_sent(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            quote = g.run(job, args(), env=ENV, post=FakeMessages())
            cap = quote["estimateUsd"] * 1.01
            fake = FakeMessages(message({"moments": [{"beatId": "S01"}]}, usage={"input_tokens": 900, "output_tokens": 900}))
            rep = g.run(job, args(run=True, max_usd=cap), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 1)
            self.assertFalse(rep["ok"])
            self.assertEqual(rep["fallbackNeeded"][0]["reason"], "cap")

    def test_overlay_text_over_its_limit_is_invalid(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            long = {"overlays": [{"kind": "callout", "beatId": "S01", "anchor": "action", "actionLabel": "Open queue", "fromWord": 0, "toWord": 0,
                                  "region": "top-left", "text": "This label is far too long to read while the pointer is already moving on", "note": ""}]}
            fake = FakeMessages(message(long))
            g.run(job, args(run=True, layers="overlays"), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertIn("at most 48", fake.calls[1]["body"]["messages"][-1]["content"])

    def test_a_later_success_clears_the_fallback_entry(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            cut = message('{"moments": [', stop="max_tokens")
            g.run(job, args(run=True), env=ENV, post=FakeMessages(cut, cut))
            rep = g.run(job, args(run=True, effort="medium"), env=ENV, post=FakeMessages())
            self.assertTrue(rep["ok"], rep)
            self.assertFalse((job / "plan" / "model-specs" / "fallback-needed.json").exists())


def specs(job, name):
    return json.loads((job / "plan" / "model-specs" / f"{name}.json").read_text(encoding="utf-8"))


class ReviewFixes(unittest.TestCase):
    """Fixes from the independent review of b7ba9509."""

    def test_the_budget_is_checked_before_every_attempt_across_layers(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            quote = g.run(job, args(layers="moments,captions"), env=ENV, post=FakeMessages())
            cap = quote["estimateUsd"] * 1.05
            # The first layer costs far more than its quote, so the second layer's first attempt would pass the cap.
            costly = message({"moments": []}, usage={"input_tokens": 99_000, "output_tokens": 10})
            fake = FakeMessages(costly)
            rep = g.run(job, args(run=True, layers="moments,captions", max_usd=cap), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 1)
            self.assertEqual([(f["layer"], f["reason"]) for f in rep["fallbackNeeded"]], [("captions", "cap")])
            self.assertAlmostEqual(rep["actualUsd"], (99_000 * 0.10 + 10 * 0.50) / 1e6, places=10)

    def test_a_cached_answer_is_rebound_after_a_timing_only_cue_sheet_change(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            g.run(job, args(run=True), env=ENV, post=fake)
            sheet = cue_sheet()
            sheet["beats"][0]["narration"]["words"][0]["start"] = 0.45   # a rebuilt word clock; nothing the model sees changes
            (job / "plan" / "cue-sheet.json").write_text(json.dumps(sheet), encoding="utf-8")
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 1)
            self.assertTrue(rep["requests"][0]["cached"])
            current = hashlib.sha256((job / "plan" / "cue-sheet.json").read_bytes()).hexdigest()
            self.assertEqual(specs(job, "moments")["inputs"]["cueSheet"]["sha256"], current)

    def test_a_run_holds_an_exclusive_lock_and_never_removes_someone_elses(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            lock = job / "qa" / "generate-specs.lock"
            lock.parent.mkdir(parents=True)
            lock.write_text(json.dumps({"pid": os.getpid(), "startedAt": "2026-11-10T00:00:00+00:00"}), encoding="utf-8")
            fake = FakeMessages()
            with self.assertRaises(g.SpecsError) as cm:
                g.run(job, args(run=True), env=ENV, post=fake)
            self.assertIn(str(os.getpid()), str(cm.exception))
            self.assertIn("still running", str(cm.exception))
            self.assertEqual(fake.calls, [])
            self.assertTrue(lock.exists())
            dead = subprocess.run([sys.executable, "-c", "import os; print(os.getpid())"], capture_output=True, text=True).stdout.strip()
            lock.write_text(json.dumps({"pid": int(dead), "startedAt": "2026-11-10T00:00:00+00:00"}), encoding="utf-8")
            with self.assertRaises(g.SpecsError) as cm:
                g.run(job, args(run=True), env=ENV, post=fake)
            self.assertIn("not running", str(cm.exception))
            self.assertTrue(lock.exists())
            lock.unlink()
            g.run(job, args(run=True), env=ENV, post=fake)
            self.assertFalse(lock.exists())

    def test_the_lock_is_released_when_a_run_fails(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)

            def boom(url, headers, body):
                raise RuntimeError("unexpected")
            with self.assertRaises(RuntimeError):
                g.run(job, args(run=True), env=ENV, post=boom)
            self.assertFalse((job / "qa" / "generate-specs.lock").exists())

    def test_a_pending_fallback_stops_an_identical_resend_unless_asked(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            cut = message('{"moments": [', stop="max_tokens")
            fake = FakeMessages(cut, cut)
            g.run(job, args(run=True), env=ENV, post=fake)
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertFalse(again["ok"])
            self.assertIn("--retry-fallbacks", " ".join(again["problems"]))
            retried = g.run(job, args(run=True, retry_fallbacks=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 3)
            self.assertTrue(retried["ok"], retried)
            self.assertTrue(g.build_parser().parse_args(["job", "--retry-fallbacks"]).retry_fallbacks)

    def test_key_names_are_refused_in_any_case(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            for name in ("anthropic_api_key", "Anthropic_Admin_Key", " ANTHROPIC_API_KEY", "ANTHROPIC_ADMIN_KEY "):
                with self.assertRaises(g.SpecsError):
                    g.run(job, args(key_env=name), env={name: KEY}, post=FakeMessages())

    def test_a_prompt_over_90000_tokens_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            sheet = cue_sheet()
            sheet["beats"][0]["expected_ui_state"] = "x" * 300_000
            rep = g.run(make_job(d, sheet), args(), env=ENV, post=FakeMessages())
            self.assertFalse(rep["ok"])
            self.assertIn("90,000", " ".join(rep["problems"]))

    def test_long_prompts_are_priced_at_the_long_context_rates(self):
        short = g.actual_usd({"input_tokens": 100_000, "output_tokens": 1000})
        self.assertAlmostEqual(short, (100_000 * 0.10 + 1000 * 0.50) / 1e6, places=10)
        long = g.actual_usd({"input_tokens": 90_000, "cache_read_input_tokens": 20_000, "output_tokens": 1000})
        self.assertAlmostEqual(long, (90_000 * 0.50 + 20_000 * 0.05 + 1000 * 2.50) / 1e6, places=10)

    def test_a_broken_response_is_ledgered_and_earlier_fallbacks_survive(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            calls = []

            def post(url, headers, body):
                calls.append(body)
                if len(calls) == 1:
                    return message("", stop="refusal")
                raise g.SpecsError("Messages API response could not be read: ValueError")
            rep = g.run(job, args(run=True, layers="moments,captions"), env=ENV, post=post)
            self.assertEqual([f["reason"] for f in rep["fallbackNeeded"]], ["refusal", "error"])
            lines = [l for l in ledger(job) if l["kind"] == "spec"]
            self.assertEqual([l["layer"] for l in lines], ["moments", "captions"])
            self.assertIsNone(lines[1]["usd"])
            self.assertIn("may have been billed", lines[1]["usdBasis"])
            self.assertEqual(len(json.loads((job / "plan" / "model-specs" / "fallback-needed.json").read_text(encoding="utf-8"))["entries"]), 2)

    def test_the_transport_converts_unreadable_bodies(self):
        class Body:
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

            def read(self):
                return b"<html>not json</html>"
        real = g.urllib.request.urlopen
        g.urllib.request.urlopen = lambda req, timeout: Body()
        try:
            with self.assertRaises(g.SpecsError):
                g.http_post_json("https://example.invalid", {}, {})
        finally:
            g.urllib.request.urlopen = real

    def test_a_paid_answer_is_ledgered_and_cached_before_the_layer_file(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            real = g.write_json

            def flaky(path, data):
                if Path(path).name == "moments.json":
                    raise OSError("disk full")
                return real(path, data)
            g.write_json = flaky
            try:
                with self.assertRaises(OSError):
                    g.run(job, args(run=True), env=ENV, post=FakeMessages())
            finally:
                g.write_json = real
            (line,) = ledger(job)
            self.assertEqual(len(line["fileSha256"]), 64)
            self.assertEqual(len(list((job / "plan" / "model-specs" / "cache").glob("*.json"))), 1)

    def test_the_quote_prices_the_cached_prefix_at_the_write_rate_and_counts_the_schema(self):
        with tempfile.TemporaryDirectory() as d:
            rep = g.run(make_job(d), args(), env=ENV, post=FakeMessages())
            body = g.build_body("moments", cue_sheet()["beats"], {}, g.DEFAULT_MODEL, "low")
            system = g.estimate_tokens(body["system"][0]["text"])
            rest = g.estimate_tokens(body["messages"][0]["content"]) + g.estimate_tokens(json.dumps(body["output_config"]["format"]["schema"]))
            want = (system * 0.125 + rest * 0.10 + body["max_tokens"] * 0.50) / 1e6
            self.assertAlmostEqual(rep["requests"][0]["estimateUsd"], want, places=9)

    def test_a_rerun_never_overwrites_approved_moments(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            moment = {"beatId": "S02", "anchor": "action", "actionLabel": "Approve", "fromWord": 0, "toWord": 0, "reason": "target", "note": "small"}
            g.run(job, args(run=True), env=ENV, post=FakeMessages(message({"moments": [moment, dict(moment, beatId="S01", actionLabel="Open queue")]})))
            path = job / "plan" / "model-specs" / "moments.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            doc["approvedBy"] = "owner"
            doc["output"]["moments"] = [moment]                       # the person kept one of two
            path.write_text(json.dumps(doc), encoding="utf-8")
            sheet = cue_sheet()
            sheet["beats"][0]["expected_ui_state"] = "The queue lists three requests"
            (job / "plan" / "cue-sheet.json").write_text(json.dumps(sheet), encoding="utf-8")
            fake = FakeMessages()
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(fake.calls, [])
            self.assertIn("approved", " ".join(rep["problems"]))
            kept = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual((kept["approvedBy"], kept["output"]["moments"]), ("owner", [moment]))

    def test_approved_moments_are_rebound_when_only_timing_changed(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            g.run(job, args(run=True), env=ENV, post=FakeMessages())
            path = job / "plan" / "model-specs" / "moments.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            doc["approvedBy"] = "owner"
            path.write_text(json.dumps(doc), encoding="utf-8")
            sheet = cue_sheet()
            sheet["beats"][1]["narration"]["words"][2]["end"] = 6.9
            (job / "plan" / "cue-sheet.json").write_text(json.dumps(sheet), encoding="utf-8")
            rep = g.run(job, args(run=True), env=ENV, post=FakeMessages())
            self.assertTrue(rep["ok"], rep)
            kept = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(kept["approvedBy"], "owner")
            self.assertEqual(kept["inputs"]["cueSheet"]["sha256"], hashlib.sha256((job / "plan" / "cue-sheet.json").read_bytes()).hexdigest())

    def test_thinking_blocks_before_the_text_block_are_skipped(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            reply = message({"moments": []})
            reply["content"].insert(0, {"type": "thinking", "thinking": "Looking at the beats.", "signature": "sig"})
            rep = g.run(job, args(run=True), env=ENV, post=FakeMessages(reply))
            self.assertTrue(rep["ok"], rep)
            self.assertEqual(specs(job, "moments")["output"], {"moments": []})

    def test_the_api_shape_is_no_longer_marked_unverified(self):
        self.assertNotIn("UNVERIFIED", Path(g.__file__).read_text(encoding="utf-8"))


class SecondReviewFixes(unittest.TestCase):
    """Fixes from the second review (of 500cf186)."""

    def test_a_failed_request_stays_marked_after_the_person_removes_its_fallback_entry(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            cut = message('{"moments": [', stop="max_tokens")
            fake = FakeMessages(cut, cut)
            g.run(job, args(run=True), env=ENV, post=fake)
            (job / "plan" / "model-specs" / "fallback-needed.json").unlink()   # a person wrote a kit visual
            fake.responses = [cut, cut]
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertFalse(again["ok"])
            self.assertIn("--retry-fallbacks", " ".join(again["problems"]))

    def test_a_successful_subset_run_does_not_unmark_the_failed_full_request(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            cut = message('{"moments": [', stop="max_tokens")
            fake = FakeMessages(cut, cut)
            g.run(job, args(run=True), env=ENV, post=fake)
            g.run(job, args(run=True, beats="S01"), env=ENV, post=fake)
            fake.responses = [cut, cut]
            g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 3)

    def test_a_cap_fallback_was_never_sent_so_a_higher_cap_alone_sends_it(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            quote = g.run(job, args(layers="moments,captions"), env=ENV, post=FakeMessages())
            costly = message({"moments": []}, usage={"input_tokens": 99_000, "output_tokens": 10})
            fake = FakeMessages(costly)
            first = g.run(job, args(run=True, layers="moments,captions", max_usd=quote["estimateUsd"] * 1.05), env=ENV, post=fake)
            self.assertEqual(first["fallbackNeeded"][0]["reason"], "cap")
            self.assertNotIn("pay for it again", first["fallbackNeeded"][0]["detail"])
            again = g.run(job, args(run=True, layers="captions", max_usd=0.5), env=ENV, post=fake)
            self.assertTrue(again["ok"], again)
            self.assertEqual(len(fake.calls), 2)

    def test_the_prompt_limit_holds_for_the_retry_and_the_echoed_answer_is_capped(self):
        with tempfile.TemporaryDirectory() as d:
            sheet = cue_sheet()
            sheet["beats"][0]["expected_ui_state"] = "x" * 1000
            job = make_job(d, sheet)
            sent = []

            def post(url, headers, body):
                sent.append(body)
                if len(sent) == 1:
                    return message('{"moments": "' + "y" * 90_000 + '"}')
                return empty_for(body)
            g.run(job, args(run=True), env=ENV, post=post)
            self.assertEqual(len(sent), 2)
            echoed = sent[1]["messages"][1]["content"]
            self.assertLessEqual(len(echoed), g.ECHO_MAX_CHARS + 40)
            self.assertIn("truncated", echoed)
        with tempfile.TemporaryDirectory() as d:
            base = g.run(make_job(d), args(), env=ENV, post=FakeMessages())
            del base
            sheet = cue_sheet()
            body = g.build_body("moments", sheet["beats"], {}, g.DEFAULT_MODEL, "low")
            room = g.MAX_PROMPT_TOKENS - sum(g.prompt_tokens(body))
            sheet["beats"][0]["expected_ui_state"] = "x" * int((room - 50) * g.CHARS_PER_TOKEN)
            job = make_job(Path(d) / "near", sheet)
            sent = []

            def post2(url, headers, body):
                sent.append(sum(g.prompt_tokens(body)))
                return message({"moments": [{"beatId": "S01"}]})
            rep = g.run(job, args(run=True), env=ENV, post=post2)
            self.assertEqual(len(sent), 1, sent)
            self.assertLessEqual(sent[0], g.MAX_PROMPT_TOKENS)
            self.assertEqual(rep["fallbackNeeded"][0]["reason"], "too-long")

    def test_an_unreadable_response_is_charged_its_quote(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)

            def post(url, headers, body):
                raise g.SpecsError("Messages API response could not be read: ValueError")
            quote = g.run(job, args(), env=ENV, post=FakeMessages())["estimateUsd"]
            rep = g.run(job, args(run=True), env=ENV, post=post)
            self.assertEqual(rep["actualUsd"], 0.0)
            self.assertAlmostEqual(rep["budgetChargedUsd"], quote, places=9)

    def test_the_lock_is_released_only_when_this_run_still_owns_it(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            lock = job / "qa" / "generate-specs.lock"

            def post(url, headers, body):
                lock.unlink()
                lock.write_text(json.dumps({"pid": 99999, "startedAt": "another run"}), encoding="utf-8")
                return empty_for(body)
            g.run(job, args(run=True), env=ENV, post=post)
            self.assertTrue(lock.exists())
            self.assertEqual(json.loads(lock.read_text(encoding="utf-8"))["startedAt"], "another run")

    def test_a_mistyped_job_path_creates_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            missing = Path(d) / "film-typo"
            with self.assertRaises(g.SpecsError):
                g.run(missing, args(run=True), env=ENV, post=FakeMessages())
            self.assertFalse(missing.exists())

    def test_the_token_estimate_is_cautious(self):
        self.assertEqual(g.CHARS_PER_TOKEN, 2.5)
        self.assertEqual(g.estimate_tokens("x" * 25), 10)


def http_error(status, body=b'{"type": "error"}'):
    return g.urllib.error.HTTPError("https://example.invalid", status, "error", {}, io.BytesIO(body))


@contextlib.contextmanager
def transport_raising(exc):
    """The real transport, with urlopen replaced so nothing leaves the machine."""
    real = g.urllib.request.urlopen

    def urlopen(req, timeout):
        raise exc
    g.urllib.request.urlopen = urlopen
    try:
        yield lambda url, headers, body: g.http_post_json("https://example.invalid", headers, body)
    finally:
        g.urllib.request.urlopen = real


def main_output(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = g.main(argv)
    return code, out.getvalue() + err.getvalue()


class ThirdReviewFixes(unittest.TestCase):
    """Fixes from the third review (of 57cf7da8)."""

    def test_a_paid_first_attempt_is_marked_before_the_retry_so_an_interrupted_run_never_pays_it_again(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            cut = message('{"moments": [', stop="max_tokens")

            def interrupt(body):
                raise KeyboardInterrupt
            fake = FakeMessages(cut, interrupt)
            with self.assertRaises(KeyboardInterrupt):
                g.run(job, args(run=True), env=ENV, post=fake)
            self.assertFalse((job / "qa" / "generate-specs.lock").exists())
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertFalse(again["ok"])
            self.assertIn("--retry-fallbacks", " ".join(again["problems"]))

    def test_an_invalid_first_answer_is_marked_before_the_retry(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)

            def interrupt(body):
                raise KeyboardInterrupt
            fake = FakeMessages(message("not json"), interrupt)
            with self.assertRaises(KeyboardInterrupt):
                g.run(job, args(run=True), env=ENV, post=fake)
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertIn("--retry-fallbacks", " ".join(again["problems"]))

    def test_a_timeout_is_charged_and_marked_inside_send(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            _, beats, rows, _, _ = g.plan_work(job, args(run=True), g.route_media.load())
            budget = {"spent": 0.0, "cap": 0.5}
            with transport_raising(TimeoutError()) as post:
                out, fallback, _ = g.send(job, rows[0], beats, post, {}, budget, "2026-11-10T00:00:00+00:00")
            self.assertIsNone(out)
            self.assertEqual(fallback["reason"], "error")
            self.assertAlmostEqual(budget["spent"], rows[0]["estimateUsd"], places=9)
            marker = json.loads((job / "plan" / "model-specs" / "cache" / f"{rows[0]['key']}.json").read_text(encoding="utf-8"))
            self.assertEqual(marker["failed"], "error")

    def test_a_pasted_key_value_is_refused_and_never_echoed(self):
        pasted = "sk" + "-ant-api03-FAKE"
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            with self.assertRaises(g.SpecsError) as cm:
                g.run(job, args(key_env=pasted), env={pasted: KEY}, post=fake)
            self.assertNotIn(pasted, str(cm.exception))
            self.assertNotIn("FAKE", str(cm.exception))
            self.assertEqual(fake.calls, [])
            for extra in ([], ["--json"], ["--run"]):
                code, text = main_output([str(job), "--key-env", pasted, *extra])
                self.assertNotEqual(code, 0)
                self.assertNotIn(pasted, text)
                self.assertNotIn("FAKE", text)
            for name in ("MY KEY", "1KEY", "A-B", "", "KEY\n"):
                with self.assertRaises(g.SpecsError):
                    g.run(job, args(key_env=name), env={name: KEY}, post=fake)
            self.assertFalse((job / "qa").exists())
            ok = g.run(job, args(key_env="MY_SPECS_KEY_2"), env={"MY_SPECS_KEY_2": KEY}, post=fake)
            self.assertEqual(ok["key"], {"env": "MY_SPECS_KEY_2", "set": True})

    def test_any_admin_key_name_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            for name in ("ANTHROPIC_ADMIN_API_KEY", "my_admin_key", "XADMINX"):
                with self.assertRaises(g.SpecsError):
                    g.run(job, args(key_env=name), env={name: KEY}, post=FakeMessages())

    def test_an_admin_key_value_is_refused_at_run_time_without_printing_it(self):
        admin = "sk" + "-ant-admin01-FAKE"
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)
            fake = FakeMessages()
            with self.assertRaises(g.SpecsError) as cm:
                g.run(job, args(run=True), env={"ANTHROPIC_API_KEY_BACKUP": admin}, post=fake)
            self.assertEqual(fake.calls, [])
            for part in (admin, "admin01", "FAKE", "sk" + "-ant"):
                self.assertNotIn(part, str(cm.exception))
            self.assertFalse((job / "qa" / "generate-specs.lock").exists())
            self.assertEqual(ledger(job), [])

    def test_the_transport_reports_the_http_status(self):
        with transport_raising(http_error(529)) as post:
            with self.assertRaises(g.SpecsError) as cm:
                post("u", {}, {})
        self.assertEqual(getattr(cm.exception, "status", None), 529)
        with transport_raising(TimeoutError()) as post:
            with self.assertRaises(g.SpecsError) as cm:
                post("u", {}, {})
        self.assertIsNone(getattr(cm.exception, "status", None))

    def test_an_http_error_status_is_not_charged_and_a_plain_rerun_retries_it(self):
        for status in (401, 403, 429, 500, 529):
            with tempfile.TemporaryDirectory() as d:
                job = make_job(d)
                with transport_raising(http_error(status)) as post:
                    rep = g.run(job, args(run=True), env=ENV, post=post)
                self.assertEqual(rep["budgetChargedUsd"], 0.0, status)
                self.assertEqual(rep["fallbackNeeded"][0]["reason"], "http-status", status)
                self.assertIn(str(status), rep["fallbackNeeded"][0]["detail"])
                line = [l for l in ledger(job) if l["kind"] == "spec"][0]
                self.assertEqual(line["usd"], None if status == 500 else 0.0, status)
                self.assertIn("unknown" if status == 500 else "not billed", line["usdBasis"], status)
                fake = FakeMessages()
                again = g.run(job, args(run=True), env=ENV, post=fake)
                self.assertEqual(len(fake.calls), 1, status)
                self.assertTrue(again["ok"], again)


class FourthReviewFixes(unittest.TestCase):
    """Leftovers from the third review (of af56409b)."""

    def test_an_http_error_after_a_paid_attempt_names_the_marker_not_a_plain_rerun(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d)

            def busy(body):
                raise g.HttpStatusError(429, "Messages API returned HTTP 429: busy")
            fake = FakeMessages(message('{"moments": [', stop="max_tokens"), busy)
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            detail = rep["fallbackNeeded"][0]["detail"]
            self.assertNotIn("a plain rerun sends it again", detail)
            self.assertIn("--retry-fallbacks", detail)
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertIn("--retry-fallbacks", " ".join(again["problems"]))

    def test_a_server_error_records_an_unknown_cost_and_api_refusals_record_zero(self):
        for status, usd in ((500, None), (502, None), (503, None), (401, 0.0), (429, 0.0), (529, 0.0)):
            with tempfile.TemporaryDirectory() as d:
                job = make_job(d)
                with transport_raising(http_error(status)) as post:
                    g.run(job, args(run=True), env=ENV, post=post)
                line = [l for l in ledger(job) if l["kind"] == "spec"][0]
                self.assertEqual(line["usd"], usd, status)
                self.assertIn("unknown" if usd is None else "not billed", line["usdBasis"], status)


if __name__ == "__main__":
    unittest.main()
