#!/usr/bin/env node
// Gate for model-written layers (skills/visuals/references/model-written-specs.md): generated visuals augment a real
// recording, its narration and its cue sheet and never replace them. A job has model-written layers when it has a
// plan/model-specs/ directory; validate-viewer-release.mjs then requires this report as a PASS. Jobs without that
// directory are not affected.
//
// Usage: node validate-model-specs.mjs <jobRoot> [--cue-sheet plan/cue-sheet.json] [--out qa/model-specs-report.json] [--frame 1600x1000]
//
// Checks (each listed in checks.performed, or in checks.notPerformed with the reason; never a silent pass):
//   layer-files    every plan/model-specs/<layer>.json is from generate_specs.py, matches its schema
//                  (schemas/model-specs/) and was generated from the current cue sheet; no pending fallback-needed.json
//   anchors        every item names a cue-sheet beat plus a recorded action label or a word range of that beat
//   timing         resolved times sit inside the anchored beat's screen slot (a diagram: beatId to toBeatId)
//   geometry       no overlay rectangle intersects the pointer, the active element or the next click target, read from
//                  capture/receipt.json events (x, y, targetBox) and the beat result's targetBox; a zoom is a crop of
//                  the footage and is not a covering layer. Where the receipt has no geometry: "not checked: no geometry in receipt".
//                  Receipt pixels are mapped to the frame by uniform fit; Recast punch-in zoom is not modelled, hence the padding.
//   one-at-a-time  at most one explanatory overlay at a time besides captions; a fullscreen insert sits at a pause
//                  (no recorded action inside it) and never under an overlay
//   captions       caption words equal the aligned transcript words by index (punctuation may change), each word once
//   sources        the source recording equals the receipt's sha256 and each beat's audio equals its aligner report's take
//   density        share of runtime with any overlay and with a fullscreen insert (a summary, warned above half)
// Writes qa/model-specs-report.json bound to the cue sheet, receipt and every layer file. Exit 1 on any error, 2 on usage.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LAYERS, LIST_FIELD, TEXT_LIMITS, TIMING, beatSpan, jobFrame, normWord, readLayers, resolveLayers, schemaErrors } from './model-specs-resolve.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const USAGE = 'Usage: node validate-model-specs.mjs <jobRoot> [--cue-sheet plan/cue-sheet.json] [--out qa/model-specs-report.json] [--frame 1600x1000]';
const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
if (!pos[0]) { console.error(USAGE); process.exit(2); }
const root = resolve(pos[0]);
const outPath = resolve(root, flag('--out', 'qa/model-specs-report.json'));
const GEOMETRY_PAD_PX = 24;
const DENSITY_WARN_SHARE = 0.5;
const NO_GEOMETRY = 'not checked: no geometry in receipt';
const GENERATOR = 'media-studio/generate-specs';
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const ref = (p) => ({ path: relative(root, p).replace(/\\/g, '/'), sha256: sha(p) });
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, ''));
const errors = [], warnings = [], performed = new Set(), notPerformed = [], inputs = {};
const skip = (check, reason, item) => notPerformed.push({ check, reason, ...(item ? { item } : {}) });

function finish(extra = {}) {
  const ok = errors.length === 0;
  const report = { generator: 'media-studio/validate-model-specs', schemaVersion: '1.0.0', ok, errors, warnings, inputs,
    thresholds: { geometryPadPx: GEOMETRY_PAD_PX, densityWarnShare: DENSITY_WARN_SHARE, ...TIMING, textLimits: TEXT_LIMITS },
    checks: { performed: [...performed], notPerformed }, ...extra };
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok, out: relative(root, outPath).replace(/\\/g, '/'), errors, warnings, notPerformed: notPerformed.map((n) => `${n.check}${n.item ? ` ${n.item}` : ''}: ${n.reason}`) }, null, 2));
  process.exit(ok ? 0 : 1);
}

// ---- inputs
const sheetPath = resolve(root, flag('--cue-sheet', 'plan/cue-sheet.json'));
if (!existsSync(sheetPath)) { errors.push('plan/cue-sheet.json is required: model-written layers are anchored to it (build-cue-sheet.mjs)'); finish(); }
const sheet = readJson(sheetPath);
inputs.cueSheet = ref(sheetPath);
const specsDir = join(root, 'plan', 'model-specs');
const layers = existsSync(specsDir) ? readLayers(root) : {};
if (!Object.keys(layers).length) { errors.push(`no model-written layers in plan/model-specs/ (${LAYERS.join(', ')}); run generate_specs.py --run, or remove the directory`); finish(); }
for (const layer of Object.keys(layers)) inputs[`layer-${layer}`] = ref(join(specsDir, `${layer}.json`));
const receiptPath = join(root, 'capture', 'receipt.json');
const receipt = existsSync(receiptPath) ? readJson(receiptPath) : null;
if (receipt) inputs.receipt = ref(receiptPath);
let frame;
try { frame = await jobFrame(root, flag('--frame'), scriptDir); } catch (e) { console.error(`${e.message}\n${USAGE}`); process.exit(2); }

// ---- layer files
// The package keeps the schemas in schemas/model-specs; Sync-MediaStudioKit.ps1 deploys them beside the gate.
const schemaDir = [join(scriptDir, '..', 'schemas', 'model-specs'), join(scriptDir, 'model-specs-schemas')].find((d) => existsSync(join(d, 'moments.schema.json')));
if (!schemaDir) { errors.push('model-facing schemas not found (schemas/model-specs in the package, model-specs-schemas beside a deployed gate)'); finish(); }
const fallbackPath = join(specsDir, 'fallback-needed.json');
if (existsSync(fallbackPath)) {
  inputs.fallbackNeeded = ref(fallbackPath);
  for (const e of readJson(fallbackPath).entries || []) errors.push(`fallback needed for layer ${e.layer} (${e.reason}): a person writes a simpler kit visual or changes the request; then remove its entry from plan/model-specs/fallback-needed.json`);
}
for (const [layer, doc] of Object.entries(layers)) {
  const where = `plan/model-specs/${layer}.json`;
  if (doc.generator !== GENERATOR || doc.layer !== layer) errors.push(`${where} is not a ${layer} layer from generate_specs.py`);
  if (doc.inputs?.cueSheet?.sha256 !== inputs.cueSheet.sha256) errors.push(`${where} is stale: the cue sheet changed since it was generated; rerun generate_specs.py`);
  const schema = readJson(join(schemaDir, `${layer}.schema.json`));
  for (const e of schemaErrors(doc.output, schema)) errors.push(`${where}: ${e}`);
  const field = layer === 'diagram' ? 'caption' : 'text';
  (doc.output?.[LIST_FIELD[layer]] || []).forEach((item, n) => {
    if (TEXT_LIMITS[layer] && String(item?.[field] ?? '').length > TEXT_LIMITS[layer]) errors.push(`${layer}[${n}]: ${field} is ${String(item[field]).length} characters; at most ${TEXT_LIMITS[layer]}`);
  });
}
performed.add('layer-files');

// ---- anchors and timing
const { placements, captions, anchored, rejected } = resolveLayers({ sheet, layers, frame });
for (const r of rejected) errors.push(r.error);
performed.add('anchors');
const items = [];
const inside = (s, e, span) => s >= span.start - 1e-3 && e <= span.end + 1e-3 && e > s;
for (const p of [...placements, ...captions, ...anchored]) {
  const item = { id: p.id, layer: p.layer, beatId: p.beatId, startSeconds: p.startSeconds, endSeconds: p.endSeconds };
  const span = beatSpan(sheet, { beatId: p.beatId, ...(p.layer === 'diagram' ? { toBeatId: p.toBeatId } : {}) });
  if (!inside(p.startSeconds, p.endSeconds, span)) errors.push(`${p.id}: resolved ${p.startSeconds}-${p.endSeconds}s is outside ${span.label} (${span.start}-${span.end}s)`);
  items.push(Object.assign(p, { report: item }));
}
performed.add('timing');

// ---- geometry: the pointer, the active element and the next click target, from the receipt
const clipFrame = (rec) => rec?.videoSize || rec?.viewport || null;
function toFrame(rec) {
  const src = clipFrame(rec);
  if (!src?.width || !src?.height) return null;
  const k = Math.min(frame.width / src.width, frame.height / src.height);
  const ox = (frame.width - src.width * k) / 2, oy = (frame.height - src.height * k) / 2;
  return { point: (x, y) => ({ x: ox + x * k, y: oy + y * k }), box: (b) => ({ x: ox + b.x * k, y: oy + b.y * k, w: b.w * k, h: b.h * k }) };
}
const intersects = (r, b) => r.x < b.x + b.w && b.x < r.x + r.width && r.y < b.y + b.h && b.y < r.y + r.height;
const padded = (b) => ({ x: b.x - GEOMETRY_PAD_PX, y: b.y - GEOMETRY_PAD_PX, w: b.w + 2 * GEOMETRY_PAD_PX, h: b.h + 2 * GEOMETRY_PAD_PX });
/** Recorded actions and results on a clip, on the program clock, with whatever geometry the receipt holds. */
function clipTimeline(clip) {
  const rec = receipt?.clips?.[clip];
  const map = toFrame(rec);
  const out = [];
  for (const beat of sheet.beats || []) {
    if (beat.screen?.clip !== clip) continue;
    for (const a of beat.actions || []) {
      if (!Number.isFinite(a.action_time)) continue;
      const ev = rec?.actions?.[a.receipt_event_index];
      const shapes = [];
      if (map && Number.isFinite(ev?.x) && Number.isFinite(ev?.y)) { const pt = map.point(ev.x, ev.y); shapes.push({ what: 'the pointer', box: { x: pt.x, y: pt.y, w: 0, h: 0 } }); }
      if (map && ev?.targetBox && Number.isFinite(ev.targetBox.w)) shapes.push({ what: 'the active element', box: map.box(ev.targetBox) });
      out.push({ t: a.action_time, name: a.label || a.target || a.kind, beat: beat.beat, shapes, kind: 'action' });
    }
    const res = beat.result;
    const exp = Number.isInteger(res?.receipt_expectation_index) ? rec?.expectations?.[res.receipt_expectation_index] : null;
    if (map && Number.isFinite(res?.visible_at) && exp?.targetBox && Number.isFinite(exp.targetBox.w)) out.push({ t: res.visible_at, name: res.label, beat: beat.beat, shapes: [{ what: 'the result', box: map.box(exp.targetBox) }], kind: 'result' });
  }
  return out.sort((a, b) => a.t - b.t);
}
let geometryChecked = 0;
for (const p of placements) {
  if (p.kind === 'zoom') { p.report.geometry = 'not a covering layer: a zoom is a crop of the real footage'; continue; }
  const timeline = p.clip ? clipTimeline(p.clip) : [];
  const actions = timeline.filter((e) => e.kind === 'action');
  if (p.fullscreen) {
    const during = actions.filter((e) => e.t >= p.startSeconds && e.t <= p.endSeconds);
    for (const e of during) errors.push(`${p.id}: fullscreen insert ${p.startSeconds}-${p.endSeconds}s covers the recorded action ${e.name} at ${e.t}s; place it at a pause or use a side panel`);
    p.report.geometry = during.length ? 'covers an action' : 'at a pause';
    continue;
  }
  const before = actions.filter((e) => e.t <= p.startSeconds).at(-1);
  const within = actions.filter((e) => e.t > p.startSeconds && e.t <= p.endSeconds);
  const next = actions.find((e) => e.t > p.endSeconds);
  const results = timeline.filter((e) => e.kind === 'result' && e.t <= p.endSeconds);
  const relevant = [before, ...within, next, ...results].filter(Boolean);
  const shapes = relevant.flatMap((e) => e.shapes.map((s) => ({ ...s, e })));
  if (!shapes.length) { p.report.geometry = NO_GEOMETRY; skip('geometry', NO_GEOMETRY, p.id); continue; }
  geometryChecked++;
  const hits = shapes.filter((s) => intersects(p.rect, padded(s.box)));
  for (const h of hits) errors.push(`${p.id}: ${p.region} ${p.startSeconds}-${p.endSeconds}s covers ${h.what} at ${h.e.name} (${h.e.t}s, ${h.e === next ? 'the next click target' : h.e.kind === 'result' ? 'the result on screen' : 'during the overlay'}); choose a free region`);
  p.report.geometry = hits.length ? 'covers' : 'clear';
}
if (geometryChecked) performed.add('geometry');

// ---- one explanatory overlay at a time; fullscreen inserts never under an overlay
const overlaps = (a, b) => a.startSeconds < b.endSeconds - 1e-3 && b.startSeconds < a.endSeconds - 1e-3;
const explanatory = placements.filter((p) => p.layer === 'overlays');
for (let i = 0; i < explanatory.length; i++) for (let j = i + 1; j < explanatory.length; j++) {
  if (overlaps(explanatory[i], explanatory[j])) errors.push(`${explanatory[i].id} and ${explanatory[j].id} are on screen together (${explanatory[j].startSeconds}-${Math.min(explanatory[i].endSeconds, explanatory[j].endSeconds)}s): one explanatory overlay at a time besides captions`);
}
for (const f of placements.filter((p) => p.fullscreen)) for (const o of explanatory) if (overlaps(f, o)) errors.push(`${f.id} (fullscreen) and ${o.id} are on screen together: a fullscreen insert takes the frame alone`);
performed.add('one-at-a-time');

// ---- captions: the words actually spoken, by index, each once
const byBeat = new Map((sheet.beats || []).map((b) => [b.beat, b]));
const seen = new Map();
for (const c of captions) {
  const words = byBeat.get(c.beatId).narration.words;
  const spoken = words.slice(c.fromWord, c.toWord + 1).map((w) => normWord(w.w));
  const written = String(c.text).split(/\s+/).map(normWord).filter(Boolean);
  if (JSON.stringify(spoken) !== JSON.stringify(written)) errors.push(`${c.id}: caption text must be the spoken words ${c.fromWord}-${c.toWord} of ${c.beatId} (${spoken.join(' ')}); punctuation may change, words may not`);
  const outside = c.emphasis.filter((e) => e < c.fromWord || e > c.toWord);
  if (outside.length) errors.push(`${c.id}: emphasis ${outside.join(', ')} is outside its words ${c.fromWord}-${c.toWord}`);
  const used = seen.get(c.beatId) || new Set();
  for (let k = c.fromWord; k <= c.toWord; k++) { if (used.has(k)) { errors.push(`${c.id}: word ${k} of ${c.beatId} is captioned more than once`); break; } used.add(k); }
  seen.set(c.beatId, used);
}
if (layers.captions) {
  for (const [beatId, used] of seen) { const n = byBeat.get(beatId).narration.words.length; if (used.size < n) warnings.push(`captions cover ${used.size} of ${n} spoken words in ${beatId}`); }
  performed.add('captions');
} else skip('captions', 'no captions layer');

// ---- sources: the recording and the audio are untouched
const shownBeats = new Set([...placements, ...captions, ...anchored].flatMap((p) => {
  const span = beatSpan(sheet, { beatId: p.beatId, ...(p.layer === 'diagram' ? { toBeatId: p.toBeatId } : {}) });
  const ids = (sheet.beats || []).map((b) => b.beat);
  const i = ids.indexOf(p.beatId);
  const j = p.layer === 'diagram' ? ids.indexOf(p.toBeatId) : i;
  return span && i >= 0 ? ids.slice(i, j + 1) : [];
}));
const clips = new Set([...shownBeats].map((id) => byBeat.get(id)?.screen?.clip).filter(Boolean));
let sourcesChecked = 0;
if (!receipt && clips.size) skip('sources', 'not checked: no capture/receipt.json, so the recording hash cannot be compared');
for (const clip of clips) {
  const rec = receipt?.clips?.[clip];
  if (!receipt) break;
  if (!rec?.sha256 || !rec.file) { skip('sources', 'not checked: the receipt has no file and sha256 for this clip', clip); continue; }
  const file = resolve(root, 'capture', rec.file);
  if (!existsSync(file)) errors.push(`${clip}: source recording capture/${rec.file} is missing; the receipt binds it`);
  else if (sha(file) !== rec.sha256) errors.push(`${clip}: source recording capture/${rec.file} differs from the receipt sha256; the recording must stay byte-identical`);
  sourcesChecked++;
}
for (const id of shownBeats) {
  const source = byBeat.get(id)?.narration?.source;
  const reportPath = source && !/\s/.test(source) ? resolve(root, source) : null;
  const align = reportPath && existsSync(reportPath) ? readJson(reportPath) : null;
  if (!align?.take?.sha256 || !align.take.path) { skip('sources', 'not checked: no audio hash recorded for this beat', id); continue; }
  const take = isAbsolute(align.take.path) ? align.take.path : resolve(root, align.take.path);
  if (!existsSync(take)) errors.push(`${id}: narration audio ${align.take.path} is missing; ${source} binds it`);
  else if (sha(take) !== align.take.sha256) errors.push(`${id}: narration audio ${align.take.path} differs from ${source}; the audio must stay byte-identical`);
  sourcesChecked++;
}
if (sourcesChecked) performed.add('sources');

// ---- density
const union = (spans) => {
  const s = spans.map((p) => [Math.max(0, p.startSeconds), p.endSeconds]).filter(([a, b]) => b > a).sort((a, b) => a[0] - b[0]);
  let total = 0, cur = null;
  for (const [a, b] of s) { if (!cur || a > cur[1]) { if (cur) total += cur[1] - cur[0]; cur = [a, b]; } else cur[1] = Math.max(cur[1], b); }
  return cur ? total + cur[1] - cur[0] : 0;
};
const runtime = Number(sheet.durationSeconds) || Math.max(0, ...(sheet.beats || []).map((b) => Number(b.slot_end) || 0));
const density = runtime > 0
  ? { runtimeSeconds: runtime, overlaySeconds: round(union(placements)), overlayShare: round(union(placements) / runtime), fullscreenSeconds: round(union(placements.filter((p) => p.fullscreen))), fullscreenShare: round(union(placements.filter((p) => p.fullscreen)) / runtime), items: placements.length, captionChunks: captions.length }
  : null;
if (density && density.overlayShare > DENSITY_WARN_SHARE) warnings.push(`generated layers are on screen for ${Math.round(density.overlayShare * 100)}% of the runtime; the film is meant to be a recording with support`);
function round(v) { return Math.round(v * 1000) / 1000; }

finish({ frame, density, items: items.map((p) => p.report) });
