"""Offline tests for the stills generator. No provider is called: every request goes through a fake."""
import argparse
import base64
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

import generate_stills as g


def png(width=1536, height=1024):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\x80" * 3 for _ in range(1))  # one tiny row; dimensions come from IHDR
    return (g.PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class FakeProvider:
    def __init__(self, output_tokens=158, runware_cost=0.0062, runware_extra=None):
        self.calls = []
        self.output_tokens = output_tokens
        self.runware_cost = runware_cost
        self.runware_extra = runware_extra or {}

    def __call__(self, url, headers, body):
        self.calls.append({"url": url, "headers": headers, "body": body})
        if "openai.azure.com" in url or "/openai/deployments/" in url:
            return {"data": [{"b64_json": base64.b64encode(png()).decode()}], "usage": {"input_tokens": 33, "output_tokens": self.output_tokens}}
        row = {"taskType": "imageInference", "imageBase64Data": base64.b64encode(png()).decode(), "cost": self.runware_cost, **self.runware_extra}
        return {"data": [row]}


ENV = {"AZURE_OPENAI_ENDPOINT": "https://example.openai.azure.com/", "AZURE_OPENAI_API_KEY": "test-key", "RUNWARE_API_KEY": "test-key"}


def args(**kw):
    base = dict(job=None, lane=None, identity=None, quality="medium", size="1536x1024", scenes=None, max_usd=2.0, max_images=24,
                public_dir=None, no_link=False, run=False, json=False)
    base.update(kw)
    return argparse.Namespace(**base)


def make_job(root, scenes, identity="mahumtech", bible=None):
    job = Path(root) / "film-20261106"
    (job / "story").mkdir(parents=True)
    (job / "story" / "picture-plan.json").write_text(json.dumps({"scenes": scenes}), encoding="utf-8")
    (job / "production.json").write_text(json.dumps({"identity": identity}), encoding="utf-8")
    if bible:
        (job / "story" / "visual-bible.json").write_text(json.dumps(bible), encoding="utf-8")
    return job


def still(sid, prompt="A loaded freight truck backing into a warehouse dock at dawn", **extra):
    return {"id": sid, "title": "t", "visual": {"kind": "still", "src": "", "prompt": prompt, **extra}}


class Pricing(unittest.TestCase):
    def test_azure_cost_uses_the_list_meters(self):
        self.assertAlmostEqual(g.azure_cost_usd(158, 33), 0.00665, places=5)

    def test_quote_is_close_to_the_measured_price_not_a_worst_case(self):
        self.assertGreater(g.estimate_usd("azure-image", "1536x1024", "low"), g.azure_cost_usd(158, 33))
        self.assertLess(g.estimate_usd("azure-image", "1536x1024", "medium"), 0.03)
        self.assertGreater(g.estimate_usd("runware-image"), 0.0062)
        self.assertLess(g.estimate_usd("azure-image", "1024x1024", "medium"), g.estimate_usd("azure-image", "1536x1024", "medium"))

    def test_quality_and_size_raise_the_quote(self):
        low, med, high = (g.estimate_usd("azure-image", "1536x1024", q) for q in g.QUALITIES)
        self.assertLess(low, med)
        self.assertLess(med, high)
        self.assertLess(g.estimate_usd("azure-image", "1024x1024", "high"), g.estimate_usd("azure-image", "1536x1024", "high"))

    def test_unknown_lane_has_no_price(self):
        with self.assertRaises(g.StillsError):
            g.estimate_usd("higgsfield")


class Prompt(unittest.TestCase):
    def test_text_logos_and_likenesses_are_always_ruled_out(self):
        full = g.compose_prompt("A dock at dawn.")
        self.assertIn("No text", full)
        self.assertIn("logos", full)
        self.assertIn("real people", full)

    def test_house_style_comes_from_the_visual_bible(self):
        self.assertIn("flat paper-cut", g.compose_prompt("A dock", "flat paper-cut illustration"))


class Quote(unittest.TestCase):
    def test_quote_spends_nothing_and_makes_no_call(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1"), still("s2", "A pallet of parcels on a conveyor belt under warehouse lights")])
            fake = FakeProvider()
            rep = g.run(job, args(), env=ENV, post=fake)
            self.assertEqual(fake.calls, [])
            self.assertEqual(rep["mode"], "quote")
            self.assertEqual([s["lane"] for s in rep["scenes"]], ["azure-image", "azure-image"])
            self.assertGreater(rep["estimateUsd"], 0)
            self.assertFalse((job / "assets").exists())

    def test_a_still_without_a_prompt_is_a_problem_not_a_guess(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [{"id": "s1", "title": "t", "visual": {"kind": "still", "src": "x.png"}}])
            rep = g.run(job, args(), env=ENV, post=FakeProvider())
            self.assertFalse(rep["ok"])
            self.assertIn("no prompt", rep["problems"][0])

    def test_frozen_lane_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1", lane="google-vertex")])
            rep = g.run(job, args(), env=ENV, post=FakeProvider())
            self.assertFalse(rep["ok"])
            self.assertIn("not usable", rep["problems"][0])

    def test_non_still_scenes_are_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [{"id": "s1", "title": "t", "visual": {"kind": "chart", "form": "bars", "items": []}}])
            rep = g.run(job, args(), env=ENV, post=FakeProvider())
            self.assertEqual(rep["scenes"], [])


class Run(unittest.TestCase):
    def test_run_writes_the_picture_manifest_ledger_and_links_the_plan(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1")])
            fake = FakeProvider()
            rep = g.run(job, args(run=True, quality="low"), env=ENV, post=fake)
            self.assertTrue(rep["ok"])
            self.assertEqual(len(fake.calls), 1)
            self.assertEqual(fake.calls[0]["body"]["quality"], "low")
            self.assertEqual(fake.calls[0]["headers"], {"api-key": "test-key"})
            self.assertTrue((job / "assets" / "stills" / "s1.png").read_bytes().startswith(g.PNG_SIGNATURE))
            manifest = json.loads((job / "assets" / "stills" / "manifest.json").read_text())
            entry = manifest["stills"]["s1"]
            self.assertEqual((entry["width"], entry["height"]), (1536, 1024))
            self.assertAlmostEqual(entry["usd"], 0.00665, places=5)
            self.assertIn("actual tokens", entry["usdBasis"])
            ledger = [json.loads(l) for l in (job / "qa" / "spend-ledger.jsonl").read_text().splitlines()]
            self.assertEqual(ledger[0]["kind"], "image")
            self.assertNotIn("test-key", json.dumps(ledger) + json.dumps(manifest))
            plan = json.loads((job / "story" / "picture-plan.json").read_text())
            self.assertEqual(plan["scenes"][0]["visual"]["src"], "stills/film-20261106/s1.png")

    def test_never_pays_twice_for_the_same_prompt(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1")])
            fake = FakeProvider()
            g.run(job, args(run=True), env=ENV, post=fake)
            again = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 1)
            self.assertTrue(again["scenes"][0]["cached"])
            self.assertEqual(again["estimateUsd"], 0)

    def test_a_changed_prompt_is_paid_for_and_the_old_picture_is_kept(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1")])
            fake = FakeProvider()
            g.run(job, args(run=True), env=ENV, post=fake)
            plan = json.loads((job / "story" / "picture-plan.json").read_text())
            plan["scenes"][0]["visual"]["prompt"] = "A pallet of parcels on a conveyor belt under warehouse lights"
            (job / "story" / "picture-plan.json").write_text(json.dumps(plan), encoding="utf-8")
            g.run(job, args(run=True), env=ENV, post=fake)
            self.assertEqual(len(fake.calls), 2)
            self.assertEqual(len(list((job / "assets" / "stills" / "superseded").glob("s1-*.png"))), 1)

    def test_estimate_over_the_cap_stops_before_any_call(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still(f"s{i}", f"A distinct warehouse scene number {i} with pallets") for i in range(5)])
            fake = FakeProvider()
            with self.assertRaises(g.StillsError):
                g.run(job, args(run=True, quality="high", max_usd=0.5), env=ENV, post=fake)
            self.assertEqual(fake.calls, [])

    def test_runware_lane_records_the_reported_cost(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1", lane="runware-image")])
            fake = FakeProvider()
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertTrue(rep["ok"])
            self.assertEqual(fake.calls[0]["url"], g.RUNWARE_URL)
            self.assertEqual(fake.calls[0]["body"][0]["outputType"], "base64Data")
            self.assertEqual(rep["actualUsd"], 0.0062)

    def test_unsafe_provider_flag_fails_that_scene_only(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1", lane="runware-image"), still("s2", "A parcel scanner on a counter", lane="azure-image")])
            fake = FakeProvider(runware_extra={"NSFWContent": True})
            rep = g.run(job, args(run=True), env=ENV, post=fake)
            self.assertFalse(rep["ok"])
            self.assertEqual([f["id"] for f in rep["failed"]], ["s1"])
            self.assertEqual([x["id"] for x in rep["generated"]], ["s2"])

    def test_missing_key_fails_clearly_without_a_call(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1", lane="runware-image")])
            fake = FakeProvider()
            rep = g.run(job, args(run=True), env={}, post=fake)
            self.assertFalse(rep["ok"])
            self.assertIn("RUNWARE_API_KEY", rep["failed"][0]["error"])
            self.assertEqual(fake.calls, [])

    def test_public_dir_gets_a_copy_the_kit_can_serve(self):
        with tempfile.TemporaryDirectory() as d:
            job = make_job(d, [still("s1")])
            public = Path(d) / "public"
            g.run(job, args(run=True, public_dir=str(public)), env=ENV, post=FakeProvider())
            self.assertTrue((public / "stills" / "film-20261106" / "s1.png").exists())

    def test_a_non_png_is_rejected(self):
        with self.assertRaises(g.StillsError):
            g.png_size(b"<html>not an image</html>" * 4)


if __name__ == "__main__":
    unittest.main()
