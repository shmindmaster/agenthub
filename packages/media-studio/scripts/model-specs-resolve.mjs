#!/usr/bin/env node
// Deterministic resolver for model-written layers (skills/produce/references/model-written-specs.md). The model names a
// region and an anchor; this code does the timing and the geometry. Anchors are a cue-sheet beat plus a recorded action
// label (timed by its program action_time) or a range of that beat's word indexes (timed by the aligner's words). Regions
// are a fixed vocabulary laid out on the delivery frame. Anything it cannot place is rejected, never guessed.
//
// Usage: node model-specs-resolve.mjs <jobRoot> [--frame 1600x1000] [--out plan/model-specs/timed-graphics.json]
// Reads plan/cue-sheet.json and plan/model-specs/{overlays,diagram}.json; writes the overlays in the renderer contract
// (schemas/timed-graphics.schema.json, unchanged), zooms excepted. Exit 1 when anything was rejected or there are no layer
// files (nothing is written then), 2 on usage. Nothing consumes this file automatically: compose-screencast.mjs reads
// story/timed-graphics.json and needs a rendered asset per item in job.json campaign.assets.
// The frame is --frame, else job.json deliveryProfile through campaign-contract frameFor (default briefing-board).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const LAYERS = ['moments', 'overlays', 'captions', 'diagram'];
export const LIST_FIELD = { moments: 'moments', overlays: 'overlays', captions: 'chunks', diagram: 'diagrams' };
export const REGIONS = ['top-left', 'top-right', 'bottom-left', 'bottom-right', 'left-panel', 'right-panel', 'lower-third', 'fullscreen'];
export const TIMING = Object.freeze({ actionLeadSeconds: 0.2, actionHoldSeconds: 2.5, minHoldSeconds: 1.5 });
export const TEXT_LIMITS = Object.freeze({ overlays: 48, captions: 84, diagram: 160 });

const round3 = (v) => Math.round(v * 1000) / 1000;

/** The named region as an integer rectangle on the frame: a 4% safe margin, corners 30% x 16%, panels 32% wide, lower third 60% x 18%. */
export function regionRect(region, frame) {
  const W = frame.width, H = frame.height, m = Math.round(0.04 * Math.min(W, H));
  const cw = Math.round(0.30 * W), ch = Math.round(0.16 * H), pw = Math.round(0.32 * W);
  const rects = {
    'top-left': [m, m, cw, ch], 'top-right': [W - m - cw, m, cw, ch],
    'bottom-left': [m, H - m - ch, cw, ch], 'bottom-right': [W - m - cw, H - m - ch, cw, ch],
    'left-panel': [m, m, pw, H - 2 * m], 'right-panel': [W - m - pw, m, pw, H - 2 * m],
    'lower-third': [m, Math.round(0.70 * H), Math.round(0.60 * W), Math.round(0.18 * H)],
    fullscreen: [0, 0, W, H],
  };
  const r = rects[region];
  return r ? { x: r[0], y: r[1], width: r[2], height: r[3] } : null;
}

export const normWord = (w) => String(w ?? '').toLowerCase().replace(/[^\p{L}\p{N}']/gu, '');

/** The subset of JSON Schema the model-facing schemas use: object, array, string, integer, enum. */
export function schemaErrors(value, schema, path = '$') {
  const errs = [];
  if (schema.type === 'object') {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return [`${path} must be an object`];
    const props = schema.properties || {};
    for (const k of schema.required || []) if (!(k in value)) errs.push(`${path}.${k} is missing`);
    if (schema.additionalProperties === false) for (const k of Object.keys(value)) if (!(k in props)) errs.push(`${path}.${k} is not allowed`);
    for (const [k, v] of Object.entries(value)) if (props[k]) errs.push(...schemaErrors(v, props[k], `${path}.${k}`));
  } else if (schema.type === 'array') {
    if (!Array.isArray(value)) return [`${path} must be an array`];
    value.forEach((v, i) => errs.push(...schemaErrors(v, schema.items || {}, `${path}[${i}]`)));
  } else if (schema.type === 'string' && typeof value !== 'string') errs.push(`${path} must be a string`);
  else if (schema.type === 'integer' && !Number.isInteger(value)) errs.push(`${path} must be an integer`);
  if (schema.enum && !schema.enum.includes(value)) errs.push(`${path} must be one of ${schema.enum.join(', ')}`);
  return errs;
}

const beatWords = (beat) => beat?.narration?.words || [];
const findAction = (beat, label) => (beat?.actions || []).find((a) => a.label && String(a.label).toLowerCase() === String(label || '').toLowerCase());

/** Where an anchor lands in the beat: { start, end, at } in program seconds, or { error }. */
export function anchorWindow(item, beat, where) {
  if (!beat) return { error: `${where}: beatId ${item.beatId} is not a beat in the cue sheet` };
  if (item.anchor === 'action') {
    const action = findAction(beat, item.actionLabel);
    const labels = (beat.actions || []).filter((a) => a.label).map((a) => a.label);
    if (!action) return { error: `${where}: action "${item.actionLabel}" is not a recorded action of ${beat.beat} (recorded: ${labels.join(', ') || 'none'})` };
    if (!Number.isFinite(action.action_time)) return { error: `${where}: action "${item.actionLabel}" in ${beat.beat} has no program time (build the cue sheet in mapped mode after compose)` };
    return { start: round3(action.action_time - TIMING.actionLeadSeconds), end: round3(action.action_time + TIMING.actionHoldSeconds), at: action.action_time, action };
  }
  const words = beatWords(beat);
  const { fromWord: lo, toWord: hi } = item;
  if (!(Number.isInteger(lo) && Number.isInteger(hi) && lo >= 0 && lo <= hi && hi < words.length)) return { error: `${where}: words ${lo}-${hi} are outside ${beat.beat}, which has words 0-${words.length - 1}` };
  const start = Number(words[lo].start), end = Number(words[hi].end);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return { error: `${where}: words ${lo}-${hi} of ${beat.beat} have no times on the word clock` };
  return { start: round3(start), end: round3(Math.max(end, start + TIMING.minHoldSeconds)), at: start };
}

/** The beat window an item must sit inside: its beat's screen slot, or from beatId to toBeatId for a diagram. */
export function beatSpan(sheet, item) {
  const beats = sheet.beats || [];
  const i = beats.findIndex((b) => b.beat === item.beatId);
  const j = item.toBeatId === undefined ? i : beats.findIndex((b) => b.beat === item.toBeatId);
  if (i < 0 || j < i) return null;
  return { start: Number(beats[i].slot_start), end: Number(beats[j].slot_end), label: i === j ? beats[i].beat : `${beats[i].beat}-${beats[j].beat}` };
}

/**
 * Resolve every layer into placements (overlays and diagrams, with a frame rectangle), timed caption chunks and
 * rejections. A placement's end is trimmed to its beat span when it starts inside it; one that starts outside is left
 * as computed so the gate reports it.
 */
export function resolveLayers({ sheet, layers, frame }) {
  const byId = new Map((sheet.beats || []).map((b) => [b.beat, b]));
  const placements = [], captions = [], anchored = [], rejected = [];
  for (const layer of LAYERS) {
    const items = layers[layer]?.output?.[LIST_FIELD[layer]] || [];
    items.forEach((item, n) => {
      const id = `${layer}[${n}]`;
      const beat = byId.get(item.beatId);
      if (layer === 'captions') {
        const words = beatWords(beat);
        if (!beat) { rejected.push({ id, layer, error: `${id}: beatId ${item.beatId} is not a beat in the cue sheet` }); return; }
        const w = anchorWindow({ ...item, anchor: 'words' }, beat, id);
        if (w.error) { rejected.push({ id, layer, error: w.error }); return; }
        captions.push({ id, layer, beatId: item.beatId, fromWord: item.fromWord, toWord: item.toWord, text: item.text, emphasis: item.emphasis || [],
          startSeconds: round3(Number(words[item.fromWord].start)), endSeconds: round3(Number(words[item.toWord].end)) });
        return;
      }
      const w = anchorWindow(item, beat, id);
      if (w.error) { rejected.push({ id, layer, error: w.error }); return; }
      if (layer === 'diagram' && !beatSpan(sheet, item)) { rejected.push({ id, layer, error: `${id}: toBeatId ${item.toBeatId} must be ${item.beatId} or a later beat in the cue sheet` }); return; }
      const span = beatSpan(sheet, item);
      // Trim both ends to the beat span when the anchor itself is inside it; an anchor outside is left for the gate to report.
      let start = w.start, end = layer === 'diagram' ? span.end : w.end;
      if (w.at >= span.start - 1e-3 && w.at < span.end) { start = Math.max(start, span.start); end = Math.min(end, span.end); }
      if (layer === 'moments') { anchored.push({ id, layer, beatId: item.beatId, startSeconds: round3(start), endSeconds: round3(end) }); return; }
      const region = layer === 'diagram' ? item.placement : item.region;
      const rect = REGIONS.includes(region) && !(layer === 'overlays' && region === 'fullscreen') ? regionRect(region, frame) : null;
      if (!rect) { rejected.push({ id, layer, error: `${id}: region ${region} is not a named region this layer may use` }); return; }
      placements.push({ id, layer, kind: layer === 'diagram' ? 'diagram' : item.kind, beatId: item.beatId, toBeatId: item.toBeatId ?? item.beatId, clip: beat.screen?.clip ?? null,
        region, rect, fullscreen: region === 'fullscreen', startSeconds: round3(start), endSeconds: round3(end), text: layer === 'diagram' ? item.caption : item.text });
    });
  }
  return { placements, captions, anchored, rejected };
}

/**
 * Placements in the renderer contract (schemas/timed-graphics.schema.json): integer pixels, seconds, an asset id per item.
 * Zooms are left out: the compositor lays every timed graphic over its rectangle (compose-screencast.mjs overlay filter),
 * which would hide the footage a zoom is meant to magnify, and no crop renderer exists yet.
 */
export function timedGraphics(placements) {
  return { overlays: placements.filter((p) => p.kind !== 'zoom').map((p) => ({ assetId: `model-specs-${p.id.replace(/\W+/g, '-').replace(/-$/, '')}-${p.kind}`, x: p.rect.x, y: p.rect.y, width: p.rect.width, height: p.rect.height,
    startSeconds: Math.max(0, p.startSeconds), endSeconds: p.endSeconds, ...(p.text ? { visibleLabel: p.text } : {}) })) };
}

export function parseFrame(text) {
  const m = /^(\d+)x(\d+)$/.exec(String(text || ''));
  return m ? { width: Number(m[1]), height: Number(m[2]) } : null;
}

/** --frame, else the job's delivery profile (campaign-contract frameFor), the same frame the release gate checks. */
export async function jobFrame(root, flagValue, scriptDir) {
  if (flagValue) { const f = parseFrame(flagValue); if (!f) throw new Error('--frame must be WIDTHxHEIGHT'); return { ...f, source: '--frame' }; }
  const helper = [join(scriptDir, 'campaign-contract.mjs'), join(scriptDir, '..', 'kit', 'screencast', 'campaign-contract.mjs')].find(existsSync);
  const { frameFor } = await import(pathToFileURL(helper).href);
  const jobPath = join(root, 'job.json');
  const job = existsSync(jobPath) ? JSON.parse(readFileSync(jobPath, 'utf8').replace(/^﻿/, '')) : {};
  const f = frameFor(job);
  return { width: f.width, height: f.height, source: `deliveryProfile ${f.profile}` };
}

export function readLayers(root) {
  const dir = join(root, 'plan', 'model-specs');
  const layers = {};
  for (const layer of LAYERS) {
    const p = join(dir, `${layer}.json`);
    if (existsSync(p)) layers[layer] = JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, ''));
  }
  return layers;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const argv = process.argv.slice(2);
  const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
  const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
  if (!pos[0]) { console.error('Usage: node model-specs-resolve.mjs <jobRoot> [--frame 1600x1000] [--out plan/model-specs/timed-graphics.json]'); process.exit(2); }
  const root = resolve(pos[0]);
  const sheetPath = join(root, 'plan', 'cue-sheet.json');
  if (!existsSync(sheetPath)) { console.error('plan/cue-sheet.json is required'); process.exit(2); }
  let frame;
  try { frame = await jobFrame(root, flag('--frame'), dirname(fileURLToPath(import.meta.url))); } catch (e) { console.error(e.message); process.exit(2); }
  const sheet = JSON.parse(readFileSync(sheetPath, 'utf8').replace(/^﻿/, ''));
  const layers = readLayers(root);
  if (!Object.keys(layers).length) { console.error(`no model-written layers in plan/model-specs/ (${LAYERS.join(', ')}); nothing written, so the release requirement stays off`); process.exit(1); }
  const { placements, rejected } = resolveLayers({ sheet, layers, frame });
  const outPath = resolve(root, flag('--out', 'plan/model-specs/timed-graphics.json'));
  if (!rejected.length) { mkdirSync(dirname(outPath), { recursive: true }); writeFileSync(outPath, JSON.stringify(timedGraphics(placements), null, 2) + '\n'); }
  console.log(JSON.stringify({ ok: !rejected.length, out: rejected.length ? null : relative(root, outPath).replace(/\\/g, '/'), frame, overlays: placements.length, rejected: rejected.map((r) => r.error) }, null, 2));
  process.exit(rejected.length ? 1 : 0);
}
