import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parseAnchor, sceneEdges, makeResolver } from "../scripts/build-picture.mjs";

const script = fileURLToPath(new URL("../scripts/build-picture.mjs", import.meta.url));
const W = (text, start) => ({ text, start_seconds: start, boundary_type: "SpeechSynthesisBoundaryType.Word" });

function job(plan) {
  const root = mkdtempSync(join(tmpdir(), "bp-"));
  mkdirSync(join(root, "story"), { recursive: true });
  mkdirSync(join(root, "takes"), { recursive: true });
  const cs = { totalSeconds: 12, cues: [
    { id: "a", start: 0.5, end: 5, gapAfter: 0.5, text: "Penske declined four trucks on November 19." },
    { id: "b", start: 6, end: 11.5, gapAfter: 0.5, text: "We handle 37 percent of the volume." } ] };
  writeFileSync(join(root, "story/cue-sheet.json"), JSON.stringify(cs));
  writeFileSync(join(root, "takes/a.receipt.json"), JSON.stringify({ word_boundaries: [W("Penske", 0.05), W("declined", 0.6), W("four", 1.2), W("trucks", 1.6), W("on", 2.2), W("November 19", 2.5)] }));
  writeFileSync(join(root, "takes/b.receipt.json"), JSON.stringify({ word_boundaries: [W("We", 0.05), W("handle", 0.3), W("37 percent", 0.8), W("of", 1.4), W("the", 1.5), W("volume", 1.7)] }));
  writeFileSync(join(root, "story/picture-plan.json"), JSON.stringify(plan));
  return root;
}
const run = (root) => spawnSync(process.execPath, [script, root], { encoding: "utf8", windowsHide: true });

test("anchor syntax", () => {
  assert.deepEqual(parseAnchor("@Penske"), { word: "Penske", nth: 0, offset: 0 });
  assert.deepEqual(parseAnchor("@trucks#1+0.25"), { word: "trucks", nth: 1, offset: 0.25 });
  assert.deepEqual(parseAnchor("@four-0.2"), { word: "four", nth: 0, offset: -0.2 });
  assert.equal(parseAnchor("Penske"), null);
});

test("scene edges follow the cue ends plus the gap and finish at the program length", () => {
  const e = sceneEdges({ totalSeconds: 12, cues: [{ end: 5, gapAfter: 0.5 }, { end: 11.5, gapAfter: 0.5 }] });
  assert.deepEqual(e, [0, 5.5, 12]);
});

test("a resolver places a merged-boundary word and a percent number", () => {
  const cs = { totalSeconds: 12, cues: [{ id: "a", start: 0.5, end: 5, gapAfter: 0.5 }] };
  const r = makeResolver(cs, { a: [W("Penske", 0.05), W("November 19", 2.5)] }, [0, 12]);
  assert.ok(r("a", "@November") > 2);
});

test("builds props with word-anchored reveals and exact scene lengths", () => {
  const root = job({ scenes: [
    { id: "a", title: "Trucks", visual: { kind: "svg", groups: [{ at: "@declined", svg: "<text>Penske declined</text>" }, { at: "@November", svg: "<text>November 19</text>" }] } },
    { id: "b", title: "Share", visual: { kind: "chart", form: "waffle", items: [{ label: "of the volume", value: 37, at: "@37" }] } } ] });
  const r = run(root);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const props = JSON.parse(readFileSync(join(root, "picture/briefing-props.json"), "utf8"));
  assert.equal(props.scenes.length, 2);
  const g = props.scenes[0].visual.groups;
  assert.ok(g[0].at < g[1].at, "reveals follow the order the words are spoken");
  assert.equal(typeof g[0].at, "number");
  assert.equal(props.scenes[0].durationSeconds + props.scenes[1].durationSeconds, 12);
  assert.equal(props.scenes[0].visualScale, 1.15);
});

test("an anchor that finds no spoken word fails the build and writes no props", () => {
  const root = job({ scenes: [
    { id: "a", title: "x", visual: { kind: "svg", groups: [{ at: "@zeppelin", svg: "<text>x</text>" }] } },
    { id: "b", title: "y", visual: { kind: "stat", value: "1", label: "y" } } ] });
  const r = run(root);
  assert.equal(r.status, 1);
  assert.ok(!existsSync(join(root, "picture/briefing-props.json")));
  assert.match(r.stdout, /zeppelin/);
});

test("a cue with no scene, and a scene with no cue, both fail", () => {
  const root = job({ scenes: [{ id: "a", title: "x", visual: { kind: "stat", value: "1", label: "x" } }, { id: "zz", title: "q", visual: { kind: "stat", value: "1", label: "q" } }] });
  const r = run(root);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /cue b/);
  assert.match(r.stdout, /zz/);
});
