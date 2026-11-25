#!/usr/bin/env node
// Build the Briefing composition props from a picture plan, with every reveal pinned to the spoken word.
//
//   node build-picture.mjs <jobRoot> [--plan story/picture-plan.json] [--out picture/briefing-props.json] [--fps 30]
//
// Inputs (all under the job root):
//   story/cue-sheet.json         cues[{id,start,end,gapAfter,text}], totalSeconds  (the word clock's cue sheet)
//   takes/<cueId>.receipt.json   word_boundaries[{text,start_seconds,boundary_type}] from the synthesizer
//   story/picture-plan.json      { scenes: [{ id, kicker?, title, accent?, visualScale?, visual }] }
//
// Anchors: any `at` field anywhere inside a scene's `visual` may be a number (seconds from scene start) or a string
//   "@word"        first spoken occurrence of the word in that scene's line
//   "@word#2"      third occurrence (zero-based)
//   "@word+0.3"    0.3 s after the word ("-0.2" also works)
// A synthesizer boundary can merge words ("November 19"); the first word of a merged boundary matches.
// An anchor that finds no word is an error and the build fails: a reveal that cannot be placed is never guessed.
// Scene length comes from the cue edges, so the picture is exactly as long as the program audio.
//
// Writes the props and <out>.report.json (anchors resolved, scale hints). Exit 1 on any error. No network, no spend.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { anchorSeconds, parseAnchor, sceneEdges, wordsOf } from "../kit/explainer/anchor.mjs";
import { SLIDE_BOX, diagramLayout } from "../kit/explainer/diagram.mjs";

export { parseAnchor, sceneEdges };

const args = process.argv.slice(2);
const isMain = Boolean(process.argv[1]) && resolve(process.argv[1]).split("\\").join("/").endsWith("build-picture.mjs");
const flag = (n, d) => { const i = args.indexOf(n); return i === -1 ? d : args[i + 1]; };
const JOB = args.find((a) => !a.startsWith("--"));
if (isMain && !JOB) { console.error("Usage: node build-picture.mjs <jobRoot> [--plan P] [--out P] [--fps N]"); process.exit(1); }
const FPS = Number(flag("--fps", 30));
const planPath = JOB ? resolve(JOB, flag("--plan", "story/picture-plan.json")) : "";
const outPath = JOB ? resolve(JOB, flag("--out", "picture/briefing-props.json")) : "";
const errors = [];

const readJson = (p) => JSON.parse(readFileSync(p, "utf8").replace(/^﻿/, ""));

// Default zoom per visual kind, so short bodies fill the 1600x1000 frame. A scene can override with visualScale.
export const DEFAULT_SCALE = { svg: 1.15, sequence: 1.5, flow: 1.4, diagram: 1.0, chart: 1.0, lottie: 1.0, layers: 1.5, checklist: 1.9,
  proof: 1.9, timeline: 1.7, split: 1.8, stat: 1.15, hero: 1.6, table: 1.6, cta: 1.6 };

export function makeResolver(cs, receipts, edges, fps = FPS) {
  const info = {};
  cs.cues.forEach((c, i) => {
    const words = wordsOf(receipts[c.id] || []);
    info[c.id] = { cue: c, words, start: Math.round(edges[i] * fps) / fps };
  });
  return (id, spec) => {
    const s = info[id];
    if (!s || !s.words.length) throw new Error(`no word boundaries for ${id}`);
    return anchorSeconds({ spec, cueStart: s.cue.start ?? 0, words: s.words, sceneStart: s.start, fps });
  };
}


export function resolveAnchors(node, sceneId, resolve1, counter) {
  if (Array.isArray(node)) return node.map((n) => resolveAnchors(n, sceneId, resolve1, counter));
  if (node && typeof node === "object") {
    const out = {};
    for (const [k, v] of Object.entries(node)) {
      if (k === "at" && typeof v === "string") {
        try { out[k] = resolve1(sceneId, v); counter.resolved++; } catch (e) { errors.push(e.message); out[k] = 0.4; }
      } else out[k] = resolveAnchors(v, sceneId, resolve1, counter);
    }
    return out;
  }
  return node;
}

// The kinds the composition plays from a file. Broll and screen-in-context take a still or a recorded take.
const STILL = /\.(png|jpe?g|webp|gif)$/i;
const VIDEO = /\.(webm|mp4|mov|m4v)$/i;
export function checkMediaSource(visual) {
  if (!visual || !["broll", "screen-in-context"].includes(visual.kind)) return null;
  const src = String(visual.src ?? "");
  if (!src) return `${visual.kind} has no src`;
  if (!STILL.test(src) && !VIDEO.test(src)) return `${visual.kind} src "${src}" is neither a still (png, jpg, webp, gif) nor a video (webm, mp4, mov, m4v)`;
  return null;
}
export function build(JOBROOT) {
  const cs = readJson(join(JOBROOT, "story/cue-sheet.json"));
  const plan = readJson(planPath);
  const receipts = {};
  for (const c of cs.cues) {
    const p = join(JOBROOT, "takes", `${c.id}.receipt.json`);
    receipts[c.id] = existsSync(p) ? readJson(p).word_boundaries || [] : [];
  }
  const edges = sceneEdges(cs);
  const resolve1 = makeResolver(cs, receipts, edges);
  const byId = Object.fromEntries((plan.scenes || []).map((s) => [s.id, s]));
  const counter = { resolved: 0 };
  const scenes = cs.cues.map((c, i) => {
    const d = byId[c.id];
    if (!d) { errors.push(`no scene in the picture plan for cue ${c.id}`); return null; }
    if (!d.visual || !d.visual.kind) errors.push(`scene ${c.id} has no visual.kind`);
    const mediaError = checkMediaSource(d.visual);
    if (mediaError) errors.push(`scene ${c.id}: ${mediaError}`);
    const visual = resolveAnchors(d.visual, c.id, resolve1, counter);
    // A diagram with a bad icon, arrow or cell draws nothing, so it is refused here rather than shipped blank.
    if (visual?.kind === "diagram") for (const p of diagramLayout(visual, SLIDE_BOX).problems) errors.push(`scene ${c.id}: ${p.code}: ${p.message}`);
    return { id: c.id, kicker: d.kicker ?? "", title: d.actionTitle ?? d.title ?? "", bullets: [], accent: d.accent ?? "#3DDC84", visual,
      visualScale: d.visualScale ?? DEFAULT_SCALE[visual?.kind] ?? 1,
      durationSeconds: +((Math.round(edges[i + 1] * FPS) - Math.round(edges[i] * FPS)) / FPS).toFixed(6) };
  }).filter(Boolean);
  for (const id of Object.keys(byId)) if (!cs.cues.some((c) => c.id === id)) errors.push(`picture plan scene ${id} has no cue`);
  return { scenes, counter, totalFrames: Math.round(edges[edges.length - 1] * FPS) };
}

if (process.argv[1] && resolve(process.argv[1]).replace(/\\/g, "/").endsWith("build-picture.mjs")) {
  const { scenes, counter, totalFrames } = build(resolve(JOB));
  const report = { schema: "media-studio/picture-build/1", ok: errors.length === 0, scenes: scenes.length, anchorsResolved: counter.resolved,
    totalFrames, seconds: +(totalFrames / FPS).toFixed(3), errors };
  if (errors.length === 0) {
    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, JSON.stringify({ scenes }, null, 2) + "\n");
  }
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath.replace(/\.json$/, "") + ".report.json", JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify(report));
  process.exit(report.ok ? 0 : 1);
}
