#!/usr/bin/env node
// Pointer-path gate: the cursor moves with purpose. Reads the capture receipt's timestamped action log and fails any
// beat whose pointer flicks, goes up and down, wanders, travels far more than the direct path between the things the
// narration names, or scrolls past something and comes back. One direction per beat; nothing moves that the narration
// is not about; the eye is led along one flow. Owner standard 2026-10-20 (rule 4).
//
// Usage: node validate-pointer-path.mjs <jobRoot> [--cue-sheet plan/cue-sheet.json] [--out qa/pointer-path.json]
//          [--max-reversals 0] [--max-travel-ratio 1.35] [--max-scroll-reversals 0] [--max-unnamed-moves 0] [--turn-cos -0.5]
//
// Inputs (all under <jobRoot>; the product repository is never read):
//   capture/receipt.json   required. clips[id].actions from record-job.mjs / record-lib.mjs:
//                            move {x,y} (three per eased approach), wheel {dy} (six per smoothScroll), click / type / point
//                            {x,y,label,tStart}, tap {x,y,label,tStart} (touch: no moves, named like a click), goto, expect. A clip without an action log fails: "re-record".
//   story/cue-plan.json    optional. beats[id].pointer = per-beat allowance { maxReversals, maxTravelRatio,
//                          maxScrollReversals, maxUnnamedMoves, reason }. story/storyboard.json beats[].pointer is read the same
//                          way. Loosening a default without a non-empty `reason` is an error; tightening needs none.
//   plan/cue-sheet.json    optional. A 'mapped' sheet (build-cue-sheet.mjs, after compose) gives per-beat windows on the program
//                          clock: a raw action time t plays at clip time t - recastHeadTrimSeconds, at program time
//                          edl.startSeconds + the edit's clip->slot time (sync-lib clipToSlot), and belongs to the beat whose
//                          [slot_start, slot_end) holds it. Footage the edit drops is not on screen and is not judged.
//                          A 'plan' sheet or no sheet: one window per clip, named by the clip's segments.
//
// Per window, from the ordered events:
//   approaches   maximal runs of `move` events. Named when the next non-move event is click / type / point / tap (the thing the
//                narration names); otherwise unnamed (wandering). Naming is decided on the whole clip, so an approach split
//                across two beats is named in both halves.
//   reversals    pairs of consecutive displacement vectors (>= 24 px) whose cosine is below --turn-cos (default -0.5 = a turn
//                sharper than 120 degrees). Two readings, the larger counts: the moves inside each run (flicking, up and
//                down) and the end points of successive approaches (going back the way it came). The same turn shows in
//                both; it is counted once.
//   travelRatio  sum of move segment lengths / the polyline through the first pointer position and each named target
//                (a touch path of taps has travel 0).
//                1 when both are 0; Infinity (reported null, measured "Infinity") when nothing is named and the pointer moved.
//   scroll       wheel dy sign changes, plus a "scroll return": the running dy passes 60 px and comes back to within 20% of
//                where it started before the next named action (the ABACare W01 pattern: six +20 steps, then six -20).
//   unnamedMoves move events in unnamed approaches.
// Report qa/pointer-path.json is bound to the receipt (sha256), the cue plan, the storyboard and the cue sheet when read.
// Exit 1 on any error.
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const libPath = [join(scriptDir, 'sync-lib.mjs'), join(scriptDir, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
if (!libPath) { console.error('sync-lib.mjs not found beside this script or in ../kit/screencast'); process.exit(2); }
const L = await import(pathToFileURL(libPath).href);

const USAGE = 'Usage: node validate-pointer-path.mjs <jobRoot> [--cue-sheet plan/cue-sheet.json] [--out qa/pointer-path.json] [--max-reversals 0] [--max-travel-ratio 1.35] [--max-scroll-reversals 0] [--max-unnamed-moves 0] [--turn-cos -0.5]';
const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
if (!pos[0]) { console.error(USAGE); process.exit(1); }
const root = resolve(pos[0]);
const num = (name, d) => { const v = Number(flag(name, d)); if (!Number.isFinite(v)) { console.error(`${name} must be a number\n${USAGE}`); process.exit(2); } return v; };
const DEFAULTS = Object.freeze({
  maxReversals: num('--max-reversals', 0),
  maxTravelRatio: num('--max-travel-ratio', 1.35),
  maxScrollReversals: num('--max-scroll-reversals', 0),
  maxUnnamedMoves: num('--max-unnamed-moves', 0),
});
const TURN_COS = num('--turn-cos', -0.5);
const MIN_VECTOR_PX = 24;        // shorter displacements are jitter, not a direction
const SCROLL_RETURN_PX = 60;     // the running scroll must pass this before a return counts
const SCROLL_RETURN_FRACTION = 0.2;
const NAMED = new Set(['click', 'type', 'point', 'tap']);   // tap: a finger on a touch context, no approach moves

const outPath = resolve(root, flag('--out', 'qa/pointer-path.json'));
const readJson = (rel) => { const p = join(root, rel); return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, '')) : null; };
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const ref = (p) => ({ path: relative(root, p).replace(/\\/g, '/'), sha256: sha(p) });
const errors = [];
const warnings = [];
const inputs = {};

// ---- inputs
const receiptPath = join(root, 'capture', 'receipt.json');
let receipt = null;
if (!existsSync(receiptPath)) errors.push('capture/receipt.json is required: record the screen beats with record-job.mjs first');
else { receipt = readJson('capture/receipt.json'); inputs.receipt = ref(receiptPath); }
const clips = receipt?.clips && typeof receipt.clips === 'object' ? receipt.clips : {};
if (receipt && !Object.keys(clips).length) errors.push('capture/receipt.json has no clips');

const cuePlanPath = join(root, 'story', 'cue-plan.json');
const cuePlan = existsSync(cuePlanPath) ? readJson('story/cue-plan.json') : null;
if (cuePlan) inputs.cuePlan = ref(cuePlanPath);
const storyboardPath = join(root, 'story', 'storyboard.json');
const storyboard = existsSync(storyboardPath) ? readJson('story/storyboard.json') : null;
if (storyboard) inputs.storyboard = ref(storyboardPath);
const sbBeats = storyboard ? (storyboard.beats || storyboard.scenes || []) : [];

const sheetFlag = flag('--cue-sheet', null);
const sheetPath = sheetFlag ? resolve(root, sheetFlag) : join(root, 'plan', 'cue-sheet.json');
let sheet = null;
if (existsSync(sheetPath)) { sheet = JSON.parse(readFileSync(sheetPath, 'utf8').replace(/^﻿/, '')); inputs.cueSheet = ref(sheetPath); }
else if (sheetFlag) errors.push(`--cue-sheet ${sheetFlag} not found`);
const mapped = sheet?.mode === 'mapped' && Array.isArray(sheet.beats) && sheet.beats.length > 0;
if (sheet && sheet.mode === 'mapped' && !mapped) warnings.push('cue sheet is mapped but has no beats: judging per clip');

// ---- geometry
const dist = (a, b) => Math.hypot(b.x - a.x, b.y - a.y);
const round = (v, p = 3) => (Number.isFinite(v) ? Math.round(v * 10 ** p) / 10 ** p : v);

/** Pairs of consecutive displacement vectors (each >= MIN_VECTOR_PX) turning sharper than the cosine limit. */
function countTurns(points) {
  const vs = [];
  for (let i = 1; i < points.length; i++) {
    const dx = points[i].x - points[i - 1].x, dy = points[i].y - points[i - 1].y, len = Math.hypot(dx, dy);
    if (len >= MIN_VECTOR_PX) vs.push({ dx, dy, len });
  }
  let n = 0;
  for (let i = 1; i < vs.length; i++) if ((vs[i - 1].dx * vs[i].dx + vs[i - 1].dy * vs[i].dy) / (vs[i - 1].len * vs[i].len) < TURN_COS) n++;
  return n;
}

/** Wheel statistics: sign changes, and scroll returns (past SCROLL_RETURN_PX, back to within 20% of the start, before the next named action). */
function scrollStats(events) {
  let prevSign = 0, changes = 0, cum = 0, peak = 0, maxPeak = 0, returns = 0, returnPeak = 0;
  for (const e of events) {
    if (e.type === 'wheel' && Number.isFinite(e.dy) && e.dy !== 0) {
      const sign = Math.sign(e.dy);
      if (prevSign && sign !== prevSign) changes++;
      prevSign = sign;
      cum += e.dy;
      peak = Math.max(peak, Math.abs(cum));
      maxPeak = Math.max(maxPeak, peak);
      if (peak > SCROLL_RETURN_PX && Math.abs(cum) <= SCROLL_RETURN_FRACTION * peak) { returns++; returnPeak = Math.max(returnPeak, peak); cum = 0; peak = 0; }
    } else if (NAMED.has(e.type)) { cum = 0; peak = 0; }
  }
  return { changes, returns, peakPx: round(returns ? returnPeak : maxPeak, 1) };
}

/** Approaches over the whole clip, so an approach split across two beats keeps the name it has on the clip. */
function clipApproaches(events) {
  const byEvent = new Map();
  let cur = null, n = 0;
  for (const e of events) {
    if (e.type === 'move' && Number.isFinite(e.x) && Number.isFinite(e.y)) {
      if (!cur) cur = { id: n++, named: false };
      byEvent.set(e, cur);
    } else if (cur) { cur.named = NAMED.has(e.type); cur = null; }
  }
  return byEvent;
}

function measure(events, approachOf) {
  const runs = [];
  let prev = null;
  for (const e of events) {
    const a = e.type === 'move' ? approachOf.get(e) : null;
    if (a) {
      if (!prev || prev.a !== a) { prev = { a, pts: [] }; runs.push(prev); }
      prev.pts.push({ x: e.x, y: e.y });
    } else prev = null;
  }
  const all = runs.flatMap((r) => r.pts);
  let travelPx = 0;
  for (let i = 1; i < all.length; i++) travelPx += dist(all[i - 1], all[i]);
  const named = runs.filter((r) => r.a.named);
  // Direct path: the first pointer position, then every named target in order (click / point / tap coordinates). A touch path has
  // no approach moves, so it runs through the tap points alone and its travel is 0.
  const direct = [];
  if (all.length) direct.push(all[0]);
  for (const e of events) if (NAMED.has(e.type) && Number.isFinite(e.x) && Number.isFinite(e.y)) direct.push({ x: e.x, y: e.y });
  let directPx = 0;
  for (let i = 1; i < direct.length; i++) directPx += dist(direct[i - 1], direct[i]);
  const travelRatio = travelPx === 0 && directPx === 0 ? 1 : directPx === 0 ? Infinity : travelPx / directPx;
  const inRun = runs.reduce((n, r) => n + countTurns(r.pts), 0);
  const betweenApproaches = countTurns(runs.map((r) => r.pts.at(-1)));
  const scroll = scrollStats(events);
  return {
    events: events.length,
    approaches: runs.length,
    namedApproaches: named.length,
    reversals: Math.max(inRun, betweenApproaches),
    travelPx: round(travelPx, 1),
    directPx: round(directPx, 1),
    travelRatio: Number.isFinite(travelRatio) ? round(travelRatio) : null,
    scrollReversals: scroll.changes,
    scrollReturns: scroll.returns,
    scrollPeakPx: scroll.peakPx,
    unnamedMoves: runs.filter((r) => !r.a.named).reduce((n, r) => n + r.pts.length, 0),
  };
}

// ---- allowances
const ALLOWANCE_FIELDS = ['maxReversals', 'maxTravelRatio', 'maxScrollReversals', 'maxUnnamedMoves'];
function allowanceFor(ids, label) {
  let pointer = null, source = 'default';
  for (const id of ids) if (cuePlan?.beats?.[id]?.pointer && typeof cuePlan.beats[id].pointer === 'object') { pointer = cuePlan.beats[id].pointer; source = 'cue-plan'; break; }
  if (!pointer) for (const id of ids) { const b = sbBeats.find((x) => x.id === id || (x.segments || []).includes(id)); if (b?.pointer && typeof b.pointer === 'object') { pointer = b.pointer; source = 'storyboard'; break; } }
  const values = { ...DEFAULTS };
  const out = { ...values, source };
  if (!pointer) return out;
  const loosened = [];
  for (const f of ALLOWANCE_FIELDS) {
    if (pointer[f] === undefined) continue;
    const v = Number(pointer[f]);
    if (!Number.isFinite(v) || v < (f === 'maxTravelRatio' ? 1 : 0)) { errors.push(`${label}: pointer allowance ${f} must be a number >= ${f === 'maxTravelRatio' ? 1 : 0} (${source})`); continue; }
    out[f] = v;
    if (v > DEFAULTS[f]) loosened.push(f);
  }
  if (pointer.reason) out.reason = String(pointer.reason);
  if (loosened.length && !String(pointer.reason || '').trim()) errors.push(`${label}: pointer allowance loosens ${loosened.join(', ')} without a reason (${source})`);
  return out;
}

function judge(window, m, label) {
  const al = window.allowance;
  const f = [];
  const add = (check, measured, allowed, fail, message) => {
    f.push({ check, status: fail ? 'fail' : 'pass', measured, allowed, message: fail ? message : 'ok' });
    if (fail) errors.push(`${label}: ${message}`);
  };
  add('reversals', m.reversals, al.maxReversals, m.reversals > al.maxReversals,
    `pointer reverses direction ${m.reversals} time(s) (allowed ${al.maxReversals}): up-and-down, flicking or going back the way it came; lead the eye along one flow`);
  const over = m.travelRatio === null || m.travelRatio > al.maxTravelRatio + 1e-9;
  add('travel-ratio', m.travelRatio === null ? 'Infinity' : m.travelRatio, al.maxTravelRatio, over,
    m.travelRatio === null
      ? `pointer travels ${Math.round(m.travelPx)}px with nowhere named to go (no click, type or point to lead to)`
      : `pointer travels ${Math.round(m.travelPx)}px for a ${Math.round(m.directPx)}px direct path (ratio ${m.travelRatio.toFixed(2)}, allowed ${al.maxTravelRatio}): it wanders between the things the narration names`);
  add('scroll-reversals', m.scrollReversals, al.maxScrollReversals, m.scrollReversals > al.maxScrollReversals,
    `scroll changes direction ${m.scrollReversals} time(s) (allowed ${al.maxScrollReversals}): scrolling past and returning`);
  add('scroll-return', m.scrollReturns, al.maxScrollReversals, m.scrollReturns > al.maxScrollReversals,
    `scroll goes ${m.scrollPeakPx}px and returns to its start before the next named action (${m.scrollReturns} time(s), allowed ${al.maxScrollReversals}): scroll past and return`);
  add('unnamed-moves', m.unnamedMoves, al.maxUnnamedMoves, m.unnamedMoves > al.maxUnnamedMoves,
    `${m.unnamedMoves} pointer move(s) do not lead to a click, type or point (allowed ${al.maxUnnamedMoves}): nothing moves that the narration is not about`);
  return f;
}

// ---- windows
const windows = [];
const addWindow = (identity, events, approachOf, ids, label) => {
  const w = { ...identity, ...measure(events, approachOf) };
  w.allowance = allowanceFor(ids, label);
  w.findings = judge(w, w, label);
  windows.push(w);
};
const hasLog = (id, rec) => {
  if (Array.isArray(rec.actions) && rec.actions.length) return true;
  errors.push(`${id}: re-record: receipt has no action log, the pointer path cannot be judged`);
  return false;
};
const keptEdit = (g, rec) => ({ ...g.edit, srcSeconds: g.edit.srcSeconds ?? rec.clipSeconds ?? 1e6 });

if (mapped) {
  const beatsByClip = new Map();
  for (const b of sheet.beats) {
    const clipId = b.screen?.clip;
    if (!clipId || b.screen?.kind !== 'screen') continue;
    if (!beatsByClip.has(clipId)) beatsByClip.set(clipId, []);
    beatsByClip.get(clipId).push(b);
  }
  const perBeat = new Map();   // beat id -> { events, approachOf, clipId }
  for (const [clipId, beats] of beatsByClip) {
    // Piecewise cue clocks cannot use the legacy no-edit heuristic: it would
    // judge footage cut out of the rendered window and misassign beat ownership.
    // Until this gate supports verified piecewise event windows, refuse them.
    if ((sheet.edl || []).some((g) => g.clip === clipId && g.actualCaptureWindow?.piecewise_time_map) || beats.some((b) => b.picture_clock?.kind === 'receipt-to-piecewise-picture')) {
      errors.push(`${clipId}: piecewise picture clock is not supported by pointer-path validation; source events and beat windows cannot be judged safely`);
      continue;
    }
    const rec = clips[clipId];
    if (!rec) { if (receipt) warnings.push(`${clipId}: cue sheet shows this clip but the receipt has no entry for it; not judged`); continue; }
    if (!hasLog(clipId, rec)) continue;
    const clock = L.clipClock(rec);
    if (clock.offset === null) { errors.push(`${clipId}: ${clock.source}`); continue; }
    const approachOf = clipApproaches(rec.actions);
    const groups = (sheet.edl || []).filter((g) => g.clip === clipId && g.edit).map((g) => ({ startSeconds: Number(g.startSeconds), edit: keptEdit(g, rec) }));
    const ordered = beats.slice().sort((a, b) => a.slot_start - b.slot_start);
    const bucket = new Map(ordered.map((b) => [b.beat, []]));
    if (groups.length) {
      for (const e of rec.actions) {
        const clipTime = L.toClipTime(rec, e.tStart ?? e.t);
        if (clipTime === null) continue;
        let program = null;
        for (const g of groups) { const s = L.clipToSlot(g.edit, clipTime); if (s !== null) { program = g.startSeconds + s; break; } }
        if (program === null) continue;                       // dropped by the edit: not on screen
        let owner = ordered[0];
        for (const b of ordered) if (b.slot_start <= program + 1e-6) owner = b;
        bucket.get(owner.beat).push(e);
      }
    } else {
      // No usable edit for this clip: split at the first narrated action of each beat (its clip_time), earlier events go to the first beat.
      if (ordered.length > 1) warnings.push(`${clipId}: no edit in the cue sheet's edl; windows split at each beat's first action clip_time`);
      const starts = ordered.map((b) => { const ts = (b.actions || []).map((a) => a.clip_time).filter(Number.isFinite); return ts.length ? Math.min(...ts) : null; });
      for (const e of rec.actions) {
        const clipTime = L.toClipTime(rec, e.tStart ?? e.t);
        if (clipTime === null) continue;
        let k = 0;
        starts.forEach((s, i) => { if (s !== null && clipTime >= s - 1e-6) k = i; });
        bucket.get(ordered[k].beat).push(e);
      }
    }
    for (const b of ordered) perBeat.set(b.beat, { events: bucket.get(b.beat), approachOf, clipId, rec });
  }
  for (const b of sheet.beats) {
    const w = perBeat.get(b.beat);
    if (!w) continue;
    addWindow({ beat: b.beat, clip: w.clipId, segments: w.rec.segments || [w.clipId] }, w.events, w.approachOf, [b.beat, w.clipId, ...(w.rec.segments || [])], b.beat);
  }
  for (const id of Object.keys(clips)) if (receipt && !beatsByClip.has(id)) warnings.push(`${id}: in the receipt but no screen beat of the cue sheet shows it; not judged`);
} else {
  for (const [clipId, rec] of Object.entries(clips)) {
    if (!hasLog(clipId, rec)) continue;
    addWindow({ clip: clipId, segments: rec.segments || [clipId] }, rec.actions, clipApproaches(rec.actions), [clipId, ...(rec.segments || [])], clipId);
  }
}

const ok = errors.length === 0;
const report = {
  generator: 'media-studio/validate-pointer-path',
  schemaVersion: '1.0.0',
  ok,
  errors,
  warnings,
  inputs,
  thresholds: { ...DEFAULTS, turnCos: TURN_COS, minVectorPx: MIN_VECTOR_PX, scrollReturnPx: SCROLL_RETURN_PX, scrollReturnFraction: SCROLL_RETURN_FRACTION },
  mode: mapped ? 'mapped' : 'clip',
  windows,
};
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ok, out: relative(root, outPath).replace(/\\/g, '/'), mode: report.mode, windows: windows.length, errors, warnings }));
if (!ok) process.exit(1);
