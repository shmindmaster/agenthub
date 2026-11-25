#!/usr/bin/env node
// Fail-closed gate on the ENCODED film of a screen-stage job, measured against the stage plan that produced it.
// Usage: node validate-screen-stage.mjs <jobRoot> <candidate.mp4> [--out qa/screen-stage.json]
// Contract: skills/studio/references/screen-stage.md. For every stage run in output/<base>-compose-map.json it proves, on decoded
// frames and not on the plan alone:
//   1. the plan on disk is the plan its inputs give (receipt events + compose edit list), so a hand-edited plan cannot pass
//   2. 60 fps: the stream rate, a regular timestamp grid and the frame count
//   3. the film opens and closes on the full page, and the last wide framing equals the first
//   4. at every planned press the target is inside the measured view and the camera has zoomed to it
//   5. each camera move converges on the planned spring curve and is settled in time; nothing drifts during a hold
//   6. no duplicated or frozen frame inside a camera or cursor move
//   7. the cursor is drawn on the recorded click point at the click time
//   8. every sampled frame is the receipt-bound capture: the source frame, warped by the measured camera, matches the film frame
//   9. core-v2 motion rules (each fails the core-v1 picture): plan rules (1.5x default zoom, camera leads the pointer, a clean
//      opening hold, a result elsewhere reached within 0.25 s); a flat patch keeps its colour within 2/255 during a move; no
//      repeated copies along the motion (autocorrelation against an ideal blur); no fade in; the result of a press is in the
//      measured view; no unchanged view held over 1.0 s; the cursor presses to about 0.9 and back; the capture delivered
//      50+ unique frames a second while the page animated (30 fps floor)
// Camera estimation registers the film frame against the source frame (normalised cross-correlation, pattern search from the plan).
import { existsSync, mkdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const argv = process.argv.slice(2);
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--out'));
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const [jobRoot, candidateArg] = pos;
if (!jobRoot || !candidateArg) { console.error('Usage: node validate-screen-stage.mjs <jobRoot> <candidate.mp4> [--out qa/screen-stage.json]'); process.exit(1); }
const candidate = resolve(candidateArg);
const outPath = resolve(jobRoot, flag('--out', 'qa/screen-stage.json'));
const scriptDir = dirname(fileURLToPath(import.meta.url));
const kitDir = [join(scriptDir, '..', 'kit', 'screencast'), scriptDir].find((d) => existsSync(join(d, 'stage-math.mjs')));
if (!kitDir) { console.error('stage-math.mjs not found beside this script or in ../kit/screencast'); process.exit(2); }
const M = await import(pathToFileURL(join(kitDir, 'stage-math.mjs')).href);
const P = await import(pathToFileURL(join(kitDir, 'stage-plan.mjs')).href);
const C = await import(pathToFileURL(join(kitDir, 'stage-checks.mjs')).href);
const F = await import(pathToFileURL(join(kitDir, 'stage-film-checks.mjs')).href);
const CH = await import(pathToFileURL(join(kitDir, 'stage-changes.mjs')).href);
const RAMPS = await import(pathToFileURL(join(kitDir, 'stage-ramps.mjs')).href);

export const LIMITS = Object.freeze({
  fpsTolerance: 0.01, ptsJitterMs: 1.0, frameCountSlack: 2,
  wideZoomTolerance: 0.03, wideCenterPx: 8, sameFramingPx: 6,
  zoomTolerance: 0.06, centerPx: 28, settleProgressTolerance: 0.14, holdDriftPx: 5, holdDriftZoom: 0.02,
  duplicateDiff: 0.02, minMovingPxPerFrame: 1.5,
  cursorPx: 8, cursorNcc: 0.45, bindingNcc: 0.8,
  colourShift: 2.0,            // 0-255: a flat patch during a move vs the same patch on the hold
  ghostExcess: 0.15,           // autocorrelation excess along the motion over an ideal blur
  openingLumaStep: 1.0,        // the opening hold's mean luma may not change more than this (no fade in)
  stillSeconds: 1.0, stillEndSeconds: 1.5, stillStartSeconds: 0.7, // unchanged-view holds
  pressScale: [0.86, 0.94],    // measured cursor scale at the dip of a press
  uniqueFps: 50, floorFps: 30, // capture delivery while the page animates
  resultSeenSeconds: [0.3, 1.0],
});

const readJson = (rel) => { const p = join(jobRoot, rel); return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, '')) : null; };
const sha256 = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const errors = [];
const fail = (m) => { console.error(`[screen-stage] ${m}`); errors.push(m); };
const ff = (args, opts = {}) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', ...args], { maxBuffer: 1 << 30, ...opts });
const r2 = (v) => Math.round(v * 100) / 100;

// ---------------------------------------------------------------------------------------------------- decoding
function grayAt(file, t, w, h) {
  const buf = ff(['-ss', Math.max(0, t).toFixed(4), '-i', file, '-frames:v', '1', '-vf', `scale=${w}:${h}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']);
  return buf.length >= w * h ? new Uint8Array(buf.buffer, buf.byteOffset, w * h) : null;
}
function grayImage(file, w, h) {
  const buf = ff(['-i', file, '-frames:v', '1', '-vf', `scale=${w}:${h}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']);
  return buf.length >= w * h ? new Uint8Array(buf.buffer, buf.byteOffset, w * h) : null;
}
function grayRun(file, t0, t1, w, h, fps) {
  const buf = ff(['-ss', t0.toFixed(4), '-t', (t1 - t0).toFixed(4), '-i', file, '-vf', `fps=${fps},scale=${w}:${h}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']);
  const n = Math.floor(buf.length / (w * h));
  return Array.from({ length: n }, (_, i) => new Uint8Array(buf.buffer, buf.byteOffset + i * w * h, w * h));
}
function rgbAt(file, t, w, h) {
  const buf = ff(['-ss', Math.max(0, t).toFixed(4), '-i', file, '-frames:v', '1', '-vf', `scale=${w}:${h}:flags=area,format=rgb24`, '-f', 'rawvideo', 'pipe:1']);
  return buf.length >= w * h * 3 ? new Uint8Array(buf.buffer, buf.byteOffset, w * h * 3) : null;
}
const meanAbsDiff = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length; };

// ---------------------------------------------------------------------------------------------------- camera registration
const EW = 960, EH = 540; // estimation resolution: half the 1920x1080 stage

/** Mean-removed correlation of the film frame with the source frame warped by camera c = { cx, cy, z } (stage px). */
function warpNcc(film, src, c, W, H) {
  const sc = EW / W; // stage px -> estimation px
  let n = 0, sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
  for (let v = 0; v < EH; v += 2) {
    const y = ((v / sc - H / 2) / c.z + c.cy) * sc;
    if (y < 0 || y >= EH - 1) continue;
    const y0 = Math.floor(y), fy = y - y0;
    for (let u = 0; u < EW; u += 2) {
      const x = ((u / sc - W / 2) / c.z + c.cx) * sc;
      if (x < 0 || x >= EW - 1) continue;
      const x0 = Math.floor(x), fx = x - x0, i = y0 * EW + x0;
      const b = (src[i] * (1 - fx) + src[i + 1] * fx) * (1 - fy) + (src[i + EW] * (1 - fx) + src[i + EW + 1] * fx) * fy;
      const a = film[v * EW + u];
      n++; sa += a; sb += b; saa += a * a; sbb += b * b; sab += a * b;
    }
  }
  if (n < 2000) return -1;
  const cov = sab - (sa * sb) / n, va = saa - (sa * sa) / n, vb = sbb - (sb * sb) / n;
  return va > 1 && vb > 1 ? cov / Math.sqrt(va * vb) : 0;
}

/** Pattern search for the camera that best explains the film frame, starting from the plan's camera. */
function registerCamera(film, src, start, g) {
  let best = { ...start }, score = warpNcc(film, src, best, g.W, g.H);
  for (const [dp, dz] of [[8, 0.03], [4, 0.015], [2, 0.008], [1, 0.004], [0.5, 0.002]]) {
    for (let round = 0; round < 3; round++) {
      let moved = false;
      for (const cand of [{ cx: dp }, { cx: -dp }, { cy: dp }, { cy: -dp }, { z: dz }, { z: -dz }]) {
        const c = { cx: best.cx + (cand.cx || 0), cy: best.cy + (cand.cy || 0), z: Math.max(0.9, best.z + (cand.z || 0)) };
        const s = warpNcc(film, src, c, g.W, g.H);
        if (s > score + 1e-5) { best = c; score = s; moved = true; }
      }
      if (!moved) break;
    }
  }
  return { ...best, ncc: score };
}

// ---------------------------------------------------------------------------------------------------- cursor template
/** Rasterise a cursor polygon (black fill, white outline) the way the stage draws it; returns { w, h, hx, hy, px } with px in 0..255 luma and -1 outside. */
function cursorTemplate(kind, height) {
  const shape = M.CURSOR_SHAPES[kind] || M.CURSOR_SHAPES.arrow;
  const sc = height / shape.height, pad = Math.ceil(2 * sc) + 2;
  const maxX = Math.max(...shape.points.map((p) => p[0])), maxY = Math.max(...shape.points.map((p) => p[1]));
  const w = Math.ceil(maxX * sc) + 2 * pad, h = Math.ceil(maxY * sc) + 2 * pad;
  const hx = pad + shape.hot[0] * sc, hy = pad + shape.hot[1] * sc;
  const inside = (x, y) => { let c = false; const pts = shape.points; for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) { const [xi, yi] = pts[i], [xj, yj] = pts[j]; if (((yi > y) !== (yj > y)) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c; } return c; };
  const dist = (x, y) => { let d = Infinity; const pts = shape.points; for (let i = 0; i < pts.length; i++) { const [ax, ay] = pts[i], [bx, by] = pts[(i + 1) % pts.length]; const t = Math.max(0, Math.min(1, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2 || 1))); d = Math.min(d, Math.hypot(x - (ax + t * (bx - ax)), y - (ay + t * (by - ay)))); } return d; };
  const px = new Float32Array(w * h).fill(-1);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const ux = (x - pad) / sc, uy = (y - pad) / sc;
    if (inside(ux, uy)) px[y * w + x] = 0; else if (dist(ux, uy) <= 0.85) px[y * w + x] = 255;
  }
  return { w, h, hx, hy, px };
}

/** Best template position in a full-resolution frame near (x, y): returns { x, y, ncc } of the hotspot. */
function findCursor(frame, W, H, tpl, x, y, radius) {
  let best = { ncc: -1, x: NaN, y: NaN };
  for (let oy = -radius; oy <= radius; oy += 1) for (let ox = -radius; ox <= radius; ox += 1) {
    const tx = Math.round(x + ox - tpl.hx), ty = Math.round(y + oy - tpl.hy);
    if (tx < 0 || ty < 0 || tx + tpl.w > W || ty + tpl.h > H) continue;
    let n = 0, sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
    for (let j = 0; j < tpl.h; j += 1) for (let i = 0; i < tpl.w; i += 1) {
      const b = tpl.px[j * tpl.w + i];
      if (b < 0) continue;
      const a = frame[(ty + j) * W + tx + i];
      n++; sa += a; sb += b; saa += a * a; sbb += b * b; sab += a * b;
    }
    if (n < 30) continue;
    const va = saa - (sa * sa) / n, vb = sbb - (sb * sb) / n;
    const ncc = va > 1 && vb > 1 ? (sab - (sa * sb) / n) / Math.sqrt(va * vb) : 0;
    if (ncc > best.ncc) best = { ncc, x: tx + tpl.hx, y: ty + tpl.hy };
  }
  return best;
}

// ---------------------------------------------------------------------------------------------------- run
const report = { schemaVersion: '1.0.0', generator: 'media-studio/validate-screen-stage', candidate: { path: candidate, sha256: null, bytes: null }, limits: LIMITS, runs: [], errors };
function finish() {
  report.ok = errors.length === 0;
  report.generatedAt = new Date().toISOString();
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  if (errors.length) { console.error(`[screen-stage] ${errors.length} error(s); report ${outPath}`); process.exit(1); }
  console.log(JSON.stringify({ ok: true, report: outPath, runs: report.runs.length, sha256: report.candidate.sha256 }));
  process.exit(0);
}

if (!existsSync(candidate)) { fail(`candidate not found: ${candidate}`); finish(); }
report.candidate = { path: candidate, sha256: sha256(candidate), bytes: statSync(candidate).size };
const base = basename(candidate, extname(candidate));
const composeMap = readJson(`output/${base}-compose-map.json`) || readJson(`output/${base.replace(/-final$|-master$|-silent$/, '')}-compose-map.json`);
if (!composeMap) { fail('no compose map beside the candidate: this gate measures the film against the plans listed in it'); finish(); }
const receipt = readJson('capture/receipt.json');
const plansListed = composeMap.stagePlans || [];
if (!plansListed.length) { fail('the compose map lists no screen-stage run: this film is not a screen-stage film'); finish(); }

// 2. frame rate (whole film)
{
  const probe = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-count_frames', '-show_entries', 'stream=avg_frame_rate,r_frame_rate,nb_read_frames,width,height', '-show_entries', 'frame=pts_time', '-of', 'json', candidate], { maxBuffer: 1 << 28 }).toString());
  const s = probe.streams[0];
  const [n, d] = String(s.avg_frame_rate).split('/').map(Number);
  const fps = d ? n / d : NaN;
  const pts = (probe.frames || []).map((f) => Number(f.pts_time)).filter(Number.isFinite);
  let worst = 0;
  for (let i = 1; i < pts.length; i++) worst = Math.max(worst, Math.abs(pts[i] - pts[i - 1] - 1 / M.STAGE.fps) * 1000);
  report.frameRate = { fps: r2(fps), frames: Number(s.nb_read_frames), width: s.width, height: s.height, worstPtsJitterMs: r2(worst) };
  if (!(Math.abs(fps - M.STAGE.fps) <= LIMITS.fpsTolerance * M.STAGE.fps)) fail(`the film runs at ${r2(fps)} fps, not ${M.STAGE.fps}: a screen-stage film is 60 fps`);
  if (worst > LIMITS.ptsJitterMs) fail(`timestamps are not on a regular 60 fps grid (worst step error ${r2(worst)} ms)`);
  if (composeMap.width !== s.width || composeMap.height !== s.height) fail(`the film is ${s.width}x${s.height} but the compose map says ${composeMap.width}x${composeMap.height}`);
}

for (const listed of plansListed) {
  const planPath = join(jobRoot, listed.file);
  const row = { run: listed.run, plan: listed.file, startSeconds: listed.startSeconds, durationSeconds: listed.durationSeconds, checks: {}, samples: [], moves: [], presses: [], motionEnergy: [] };
  report.runs.push(row);
  if (!existsSync(planPath)) { fail(`run ${listed.run}: plan ${listed.file} is missing`); continue; }
  if (sha256(planPath) !== listed.sha256) { fail(`run ${listed.run}: plan ${listed.file} was changed after the film was composed`); continue; }
  const plan = JSON.parse(readFileSync(planPath, 'utf8'));
  const g = plan.geometry;
  const T0 = listed.startSeconds;

  // 1. the plan is the pure function of its inputs
  let rebuilt = null;
  const captureRows = [];
  const CH_RATE = F.captureRate;
  if (receipt) {
    try {
      const clipsIn = {};
      for (const id of new Set(plan.slots.map((s) => s.clipId))) {
        const e = receipt.clips[id];
        const index = JSON.parse(readFileSync(join(jobRoot, 'capture', e.stage.framesIndex), 'utf8'));
        const frames = { times: index.frames.map((f) => f.t), files: index.frames.map((f) => `${id}/frames/${f.file}`) };
        // what changed after each press is measured again here from the captured frames: a plan that ignored it cannot match
        const pressTimes = (e.actions || []).filter((a) => P.PRESS.has(a.type)).map((a) => a.tStart ?? a.t);
        const changes = CH.measureChanges({ presses: pressTimes, frames: { times: frames.times, files: frames.files.map((f) => join(jobRoot, 'capture', 'raw', f)) }, viewport: e.viewport });
        clipsIn[id] = { actions: e.actions || [], expectations: e.expectations || [], frames, touch: !!e.hasTouch, changes };
        captureRows.push({ clip: id, deviceScaleFactor: e.deviceScaleFactor, ...CH_RATE(frames.times) });
      }
      const again = P.buildStagePlan({ frame: plan.frame, viewport: plan.viewport, dsf: plan.deviceScaleFactor, slots: plan.slots, clips: clipsIn, options: { hideCursor: plan.cursor.hiddenDeclared || [], idleHide: plan.cursor.idleHide } });
      rebuilt = again;
      const same = JSON.stringify(again.camera) === JSON.stringify(plan.camera) && JSON.stringify(again.cursor.samples) === JSON.stringify(plan.cursor.samples) && JSON.stringify(again.planned) === JSON.stringify(plan.planned);
      row.checks.planFromReceipt = same;
      if (!same) fail(`run ${listed.run}: the plan's camera, cursor or targets are not what the receipt events and edit list give`);
    } catch (e) { fail(`run ${listed.run}: cannot rebuild the plan from the receipt (${e.message.split('\n')[0]})`); }
    // speed ramps (typing at 2x) are exactly the ones the captured frames and the job's declarations give, each with a reason, none over 3x
    try {
      const cfg = (readJson('job.json') || {}).screenStage;
      const manifest = readJson('capture/manifest.json') || {};
      for (const slot of plan.slots) {
        if (slot.hold) continue;
        const e = receipt.clips[slot.clipId];
        const index = JSON.parse(readFileSync(join(jobRoot, 'capture', e.stage.framesIndex), 'utf8'));
        const clip = (manifest.clips || []).find((c) => c.id === slot.clipId) || {};
        const want = RAMPS.stageRamps({ jobRoot, entry: e, index, id: slot.clipId, cfg: cfg && typeof cfg === 'object' ? cfg : {}, manual: clip.speedSpans || [] });
        const got = slot.edit.ramps || [];
        const norm = (l) => JSON.stringify(l.map((r) => [r.from, r.to, r.speed, r.reason]));
        row.checks.ramps = { clip: slot.clipId, spans: got.length };
        if (norm(want) !== norm(got)) fail(`run ${listed.run}: the speed ramps of ${slot.clipId} are not the typing and declared spans the capture gives`);
        for (const r of got) if (!(r.speed > 1 && r.speed <= 3) || !r.reason) fail(`run ${listed.run}: a speed ramp [${r.from}, ${r.to}] of ${slot.clipId} is over 3x or has no reason`);
      }
    } catch (e) { fail(`run ${listed.run}: cannot verify the speed ramps (${e.message.split(String.fromCharCode(10))[0]})`); }
    // the edit list in the plan is the compose map's
    for (const slot of plan.slots) {
      const group = composeMap.groups.find((gr) => gr.stage?.run === listed.run && gr.clipId === slot.clipId && !gr.heldFromPrevious && gr.edit);
      if (group && !slot.hold) {
        const e = group.edit;
        const ok = ['trimStart', 'speed'].every((k) => Number(e[k]) === Number(slot.edit[k])) && JSON.stringify(e.skip || []) === JSON.stringify(slot.edit.skip || []);
        if (!ok) fail(`run ${listed.run}: the plan's edit list for ${slot.clipId} differs from the compose map`);
      }
    }
  }

  const fps = plan.frame.fps;
  const filmEnd = T0 + listed.durationSeconds;
  // 6. duplicated or frozen frames inside moves, and the motion energy curve (per 0.1 s)
  const run = grayRun(candidate, T0, filmEnd, 480, 270, fps);
  const diffs = run.map((f, i) => (i ? meanAbsDiff(run[i - 1], f) : null));
  const bins = new Map();
  diffs.forEach((d, i) => { if (d !== null) { const b = Math.floor(i / fps * 10) / 10; bins.set(b, [...(bins.get(b) || []), d]); } });
  row.motionEnergy = [...bins].map(([t, v]) => [r2(t), r2(v.reduce((a, b) => a + b, 0) / v.length)]);
  let dup = 0, moving = 0;
  for (let i = 1; i < run.length; i++) {
    const t = i / fps;
    const a = M.stateAt(plan, t - T0 + T0 === t ? t : t), b = M.stateAt(plan, Math.max(0, t - 1 / fps));
    const camPx = Math.hypot((a.camera.cx - b.camera.cx) * a.camera.z, (a.camera.cy - b.camera.cy) * a.camera.z, (a.camera.z - b.camera.z) * 400);
    const curPx = a.cursor && b.cursor && a.cursor.visible > 0.99 && !a.cursor.hidden ? Math.hypot(a.cursor.x - b.cursor.x, a.cursor.y - b.cursor.y) * a.camera.z : 0;
    const srcSame = a.frame === b.frame;
    if ((camPx >= LIMITS.minMovingPxPerFrame) || (curPx >= LIMITS.minMovingPxPerFrame * 2 && srcSame)) { moving++; if (diffs[i] < LIMITS.duplicateDiff) dup++; }
  }
  row.checks.movingFrames = moving; row.checks.duplicatedInMoves = dup;
  if (dup > 0) fail(`run ${listed.run}: ${dup} duplicated or frozen frame(s) inside a camera or cursor move (of ${moving} moving frames)`);

  // 3-5, 8. camera measurements at chosen times
  const measure = (t) => {
    const st = M.stateAt(plan, t - T0);
    const film = grayAt(candidate, t, EW, EH);
    const srcFile = join(jobRoot, 'capture', 'raw', st.frame);
    if (!film || !existsSync(srcFile)) return null;
    const src = grayImage(srcFile, EW, EH);
    if (!src) return null;
    const planned = { cx: st.camera.cx, cy: st.camera.cy, z: st.camera.z };
    const got = registerCamera(film, src, planned, g);
    return { t: r2(t - T0), planned: { cx: r2(planned.cx), cy: r2(planned.cy), z: r2(planned.z) }, measured: { cx: r2(got.cx), cy: r2(got.cy), z: r2(got.z) }, ncc: r2(got.ncc), dz: r2(got.z - planned.z), dxy: r2(Math.hypot(got.cx - planned.cx, got.cy - planned.cy)), st };
  };
  const keep = (m, kind) => { if (m) row.samples.push({ kind, ...m, st: undefined }); return m; };

  const first = keep(measure(T0 + 0.05), 'open'), last = keep(measure(filmEnd - 0.05), 'close');
  if (first && last) {
    for (const [label, m] of [['opens', first], ['closes', last]]) {
      if (Math.abs(m.measured.z - 1) > LIMITS.wideZoomTolerance || Math.hypot(m.measured.cx - g.W / 2, m.measured.cy - g.H / 2) > LIMITS.wideCenterPx) fail(`run ${listed.run}: the film ${label} on a framed view (zoom ${m.measured.z}, centre ${m.measured.cx},${m.measured.cy}), not the full page`);
    }
    const dFraming = Math.hypot(last.measured.cx - first.measured.cx, last.measured.cy - first.measured.cy);
    row.checks.lastWideEqualsFirst = { offsetPx: r2(dFraming), zoomDiff: r2(Math.abs(last.measured.z - first.measured.z)) };
    if (dFraming > LIMITS.sameFramingPx || Math.abs(last.measured.z - first.measured.z) > LIMITS.wideZoomTolerance) fail(`run ${listed.run}: the last wide frame's framing differs from the first (${r2(dFraming)} px)`);
  }

  for (const p of plan.planned) {
    const tp = T0 + p.t;
    const m = measure(Math.min(tp, filmEnd - 0.05));
    if (!m) { fail(`run ${listed.run}: cannot decode the film or the source at press "${p.label || p.type}" (${p.t}s)`); continue; }
    const cam = { cx: m.measured.cx, cy: m.measured.cy, z: m.measured.z };
    const inView = M.boxInView(cam, g, p.boxStage);
    const zoomedOk = !p.zoomed || m.measured.z >= m.planned.z - LIMITS.zoomTolerance;
    row.presses.push({ label: p.label, t: p.t, measuredZoom: m.measured.z, plannedZoom: m.planned.z, targetInMeasuredView: inView, ncc: m.ncc });
    if (!inView) fail(`run ${listed.run}: at "${p.label || p.type}" (${p.t}s) the target is not inside the measured view`);
    if (!zoomedOk) fail(`run ${listed.run}: at "${p.label || p.type}" (${p.t}s) the camera measured ${m.measured.z}x, not the planned ${m.planned.z}x`);
    if (m.ncc < LIMITS.bindingNcc) fail(`run ${listed.run}: the film frame at ${p.t}s does not match the receipt-bound capture (correlation ${m.ncc} < ${LIMITS.bindingNcc}); the encoded picture is not the capture`);
    if (Math.hypot(m.measured.cx - m.planned.cx, m.measured.cy - m.planned.cy) > LIMITS.centerPx) fail(`run ${listed.run}: at ${p.t}s the camera centre is ${m.dxy} px from the plan`);
  }

  // moves: converge on the spring curve, settled by settleSeconds, then still until the next move
  const segs = plan.camera.segments;
  segs.forEach((seg, i) => {
    const next = segs[i + 1]?.t0 ?? Infinity;
    const probes = [0.15, 0.25, 0.4, 0.55, 0.7].filter((d) => seg.t0 + d < Math.min(next, listed.durationSeconds - 0.03));
    const before = M.cameraAt(plan.camera, seg.t0 - 1e-6, g);
    const rec = { t0: seg.t0, reason: seg.reason, progress: [] };
    for (const d of probes) {
      const m = measure(T0 + seg.t0 + d);
      if (!m) continue;
      const span = Math.hypot(seg.to.cx - before.cx, seg.to.cy - before.cy, (seg.to.z - before.z) * 400);
      if (span < 20) continue;
      const got = Math.hypot(m.measured.cx - before.cx, m.measured.cy - before.cy, (m.measured.z - before.z) * 400) / span;
      const want = M.springAxis(0, 0, 1, d).x;
      rec.progress.push({ after: d, measured: r2(got), expected: r2(want) });
      if (d >= M.STAGE.settleSeconds - 1e-6 && Math.abs(got - 1) > LIMITS.settleProgressTolerance) fail(`run ${listed.run}: the ${seg.reason} move at ${seg.t0}s is not settled ${d}s after it starts (${r2(got * 100)}% of the way)`);
      if (m.ncc < LIMITS.bindingNcc - 0.2) continue;
      if (d <= 0.4 && Math.abs(got - want) > LIMITS.settleProgressTolerance + 0.12 && !(next < seg.t0 + d)) fail(`run ${listed.run}: the ${seg.reason} move at ${seg.t0}s is ${r2(got * 100)}% done ${d}s in; the planned spring is at ${r2(want * 100)}%`);
    }
    row.moves.push(rec);
    // hold: between this move's settle and the next move's start the view must not drift
    const holdFrom = seg.t0 + M.STAGE.settleSeconds + 0.05, holdTo = Math.min(next, listed.durationSeconds) - 0.1;
    if (holdTo - holdFrom > 0.3) {
      const a = measure(T0 + holdFrom), b = measure(T0 + holdTo);
      if (a && b) {
        const drift = Math.hypot(b.measured.cx - a.measured.cx, b.measured.cy - a.measured.cy), dz = Math.abs(b.measured.z - a.measured.z);
        rec.hold = { fromSeconds: r2(holdFrom), toSeconds: r2(holdTo), driftPx: r2(drift), zoomDrift: r2(dz) };
        if (drift > LIMITS.holdDriftPx || dz > LIMITS.holdDriftZoom) fail(`run ${listed.run}: the view drifts during the hold ${r2(holdFrom)}-${r2(holdTo)}s (${r2(drift)} px, ${r2(dz)} zoom)`);
      }
    }
  });

  // 9a. plan rules
  const rules = C.planProblems(plan);
  row.checks.planRules = rules.length === 0;
  for (const p of rules) fail(`run ${listed.run}: ${p}`);

  // 9b. the opening is a clean full-brightness page held still: no fade in
  {
    const hold0 = Math.min(0.35, (plan.camera.segments[0]?.t0 ?? 0.35) - 0.03);
    const n = Math.max(2, Math.round(hold0 * fps));
    const luma = run.slice(0, n).map(F.meanLuma);
    const step = Math.max(...luma) - Math.min(...luma);
    const still = F.stillRuns(run.slice(0, n));
    row.checks.opening = { seconds: r2(hold0), lumaStep: r2(step), still: still.length === 1 && still[0].from === 0 && still[0].to === n - 1 };
    if (step > LIMITS.openingLumaStep) fail(`run ${listed.run}: the opening is not at full brightness from the first frame (luma changes by ${r2(step)} over the first ${r2(hold0)} s): no fade in`);
    if (!row.checks.opening.still) fail(`run ${listed.run}: the picture is not held still for the first ${r2(hold0)} s`);
  }

  // 9c. no unchanged view held for over 1.0 s
  {
    const longRuns = [];
    for (const r of F.stillRuns(run)) {
      const dur = (r.to - r.from + 1) / fps;
      const atStart = r.from === 0, atEnd = r.to >= run.length - 2;
      const allowed = atStart ? LIMITS.stillStartSeconds : atEnd ? LIMITS.stillEndSeconds : LIMITS.stillSeconds;
      if (dur > allowed) longRuns.push({ fromSeconds: r2(r.from / fps), seconds: r2(dur) });
    }
    row.checks.longStillRuns = longRuns;
    for (const l of longRuns) fail(`run ${listed.run}: the view is held unchanged for ${l.seconds} s from ${l.fromSeconds}s (limit ${LIMITS.stillSeconds} s without narration)`);
  }

  // 9d. a result that appears elsewhere is in the measured view
  row.results = [];
  for (const res of (rebuilt || plan).results || []) {
    let seen = null;
    for (const d of [0.3, 0.55, 0.8, 1.0]) {
      const t = res.t + d; if (t > listed.durationSeconds - 0.05) break;
      const m = measure(T0 + t);
      if (m && m.ncc >= LIMITS.bindingNcc - 0.2 && M.boxInView({ cx: m.measured.cx, cy: m.measured.cy, z: m.measured.z }, g, { x: res.boxStage.x + 3, y: res.boxStage.y + 3, w: res.boxStage.w - 6, h: res.boxStage.h - 6 })) { seen = r2(d); break; }
    }
    row.results.push({ label: res.label, t: res.t, seenAfterSeconds: seen });
    if (seen === null) fail(`run ${listed.run}: the result of "${res.label || 'press'}" (${res.t}s) is not inside the measured view within ${LIMITS.resultSeenSeconds[1]} s`);
  }

  // 9e. colour and ghosting during moves: the fastest frames of each camera move
  {
    const tShutter = (M.STAGE.blur.shutterAngle / 360) / fps;
    const sc = EW / g.W;
    const speedAt = (t) => { const a = M.cameraAt(plan.camera, t - 0.5 / fps, g), b = M.cameraAt(plan.camera, t + 0.5 / fps, g); return Math.hypot((a.cx - b.cx) * a.z, (a.cy - b.cy) * a.z, (a.z - b.z) * g.W / 2); };
    const project = (cam, bx, by) => ({ x: ((bx / sc - cam.cx) * cam.z + g.W / 2) * sc, y: ((by / sc - cam.cy) * cam.z + g.H / 2) * sc });
    const colourRows = [], ghostRows = [];
    let measuredFast = 0;
    plan.camera.segments.forEach((seg, i) => {
      const next = plan.camera.segments[i + 1]?.t0 ?? Infinity;
      const frames = [];
      for (let k = 1; k <= Math.round(0.55 * fps); k++) { const t = seg.t0 + k / fps; if (t >= next - 0.02 || t > listed.durationSeconds - 0.05) break; frames.push({ t, v: speedAt(t) }); }
      const fast = frames.filter((f) => f.v >= 6).sort((a, b) => b.v - a.v).slice(0, 3);
      if (!fast.length) return;
      measuredFast += fast.length;
      const tHold = Math.max(0.02, seg.t0 - 0.06), camHold = M.cameraAt(plan.camera, tHold, g);
      const holdFrame = M.stateAt(plan, tHold).frame;
      const srcGray = grayImage(join(jobRoot, 'capture', 'raw', holdFrame), EW, EH);
      if (!srcGray) return;
      const filmHold = rgbAt(candidate, T0 + tHold, EW, EH);
      const blocks = F.spread(F.flatBlocks(srcGray, EW, EH, 28, 1.5, 6), 24, 50);
      // blocks that stay inside the picture at the hold and at every measured frame
      const cams = fast.map((f) => M.cameraAt(plan.camera, f.t, g));
      const usable = blocks.filter((b) => [camHold, ...cams].every((c) => { const p = project(c, b.cx, b.cy); return p.x > 40 && p.x < EW - 40 && p.y > 40 && p.y < EH - 40 && c.z * 24 * 0.5 < 60; }));
      const chosen = F.spread(usable, 3, 50);
      if (chosen.length < 3) fail(`run ${listed.run}: no three flat regions of the page stay in view through the move at ${seg.t0}s: the colour during motion cannot be checked`);
      const holdPatches = chosen.length < 3 ? [] : chosen.map((b) => { const p = project(camHold, b.cx, b.cy); return filmHold ? F.patchMean(filmHold, EW, EH, p.x, p.y, 3) : null; });
      for (const f of chosen.length < 3 ? [] : fast) {
        const cam = M.cameraAt(plan.camera, f.t, g);
        const film = rgbAt(candidate, T0 + f.t, EW, EH);
        if (!film) continue;
        const patches = chosen.map((b) => { const p = project(cam, b.cx, b.cy); return F.patchMean(film, EW, EH, p.x, p.y, 3); });
        const shift = F.colourShift(patches, holdPatches);
        colourRows.push({ move: seg.t0, t: r2(f.t), speedPxPerFrame: r2(f.v), shift: shift === null ? null : r2(shift) });
        if (shift !== null && shift > LIMITS.colourShift) fail(`run ${listed.run}: a flat part of the page changes colour by ${r2(shift)}/255 during the ${seg.reason} move at ${seg.t0}s (frame ${r2(f.t)}s, limit ${LIMITS.colourShift}): colour cast in motion`);
      }
      // ghosting on the single fastest frame
      const top = fast[0];
      const camTop = M.cameraAt(plan.camera, top.t, g);
      const stTop = M.stateAt(plan, top.t);
      const src = grayImage(join(jobRoot, 'capture', 'raw', stTop.frame), EW, EH);
      const film480 = grayAt(candidate, T0 + top.t, 480, 270);
      if (!src || !film480) return;
      const cs = []; for (let k = 0; k < 96; k++) cs.push(M.cameraAt(plan.camera, Math.max(0, top.t + ((k + 0.5) / 96 - 0.5) * tShutter), g));
      const ideal = F.idealBlur(src, EW, EH, g.W, g.H, cs, 480, 270);
      const a = cs[0], b = cs[cs.length - 1];
      let dir = { x: 0, y: 0 };
      for (const [fx, fy] of [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]) { const pa = project(a, EW * fx, EH * fy), pb = project(b, EW * fx, EH * fy); if (Math.hypot(pb.x - pa.x, pb.y - pa.y) > Math.hypot(dir.x, dir.y)) dir = { x: pb.x - pa.x, y: pb.y - pa.y }; }
      const lenEst = Math.hypot(dir.x, dir.y) / 2; // px at 480 wide
      const maxLag = Math.max(6, Math.min(60, Math.ceil(lenEst * 3)));
      const filmF = Float32Array.from(film480);
      const ge = F.ghostExcess(filmF, ideal, 480, 270, dir, maxLag);
      ghostRows.push({ move: seg.t0, t: r2(top.t), blurPx480: r2(lenEst), excess: r2(ge.excess), lag: ge.lag });
      if (ge.excess > LIMITS.ghostExcess) fail(`run ${listed.run}: repeated copies along the motion in the ${seg.reason} move at ${seg.t0}s (frame ${r2(top.t)}s: autocorrelation ${r2(ge.excess)} above an ideal blur at lag ${ge.lag}, limit ${LIMITS.ghostExcess})`);
    });
    row.checks.colourInMotion = colourRows; row.checks.ghosting = ghostRows;
    if (plan.camera.segments.length && !measuredFast) fail(`run ${listed.run}: no camera move is fast enough to measure motion blur on`);
  }

  // 9f. the cursor presses: about 0.9 of its size at the dip, back to 1.0 after
  if (plan.cursor.mode !== 'touch') {
    const rows = [];
    for (const c of plan.cursor.clicks.slice(0, 4)) {
      const st0 = M.stateAt(plan, c.t);
      if (!st0.cursor || st0.cursor.visible < 0.99 || st0.cursor.hidden > 0) continue;
      const screenAt = (t) => { const s = M.stateAt(plan, t); return { s, p: M.projectPoint(s.camera, g, { x: c.x, y: c.y }) }; };
      const best = (t) => {
        const { s, p } = screenAt(t);
        const frameFull = grayAt(candidate, T0 + t, g.W, g.H);
        if (!frameFull) return null;
        let top = { scale: NaN, ncc: -1 };
        for (let sc2 = 0.76; sc2 <= 1.081; sc2 += 0.02) {
          const tpl = cursorTemplate(s.cursor.kind, M.cursorHeightFor(s.camera.z, g) * sc2);
          const f = findCursor(frameFull, g.W, g.H, tpl, p.x, p.y, 3);
          if (f.ncc > top.ncc) top = { scale: sc2, ncc: f.ncc };
        }
        return top;
      };
      const quiet = (() => { for (let d = 0.3; d <= 1.3; d += 0.05) { const a = M.cameraAt(plan.camera, c.t + d - 0.5 / fps, g), b = M.cameraAt(plan.camera, c.t + d + 0.5 / fps, g); if (Math.hypot((a.cx - b.cx) * a.z, (a.cy - b.cy) * a.z, (a.z - b.z) * g.W / 2) < 1.5) return c.t + d; } return c.t + 0.4; })();
      const dip = best(Math.round((c.t + 0.15 * 0.35) * fps) / fps), rest = best(quiet);
      rows.push({ label: c.label, t: c.t, dipScale: dip && r2(dip.scale), restScale: rest && r2(rest.scale) });
      if (dip && !(dip.scale >= LIMITS.pressScale[0] && dip.scale <= LIMITS.pressScale[1])) fail(`run ${listed.run}: the cursor at the press of "${c.label}" (${c.t}s) measures ${r2(dip.scale)} of its size, not about 0.9: no press response`);
      if (rest && !(rest.scale >= 0.96 && rest.scale <= 1.06)) fail(`run ${listed.run}: the cursor does not return to full size after the press of "${c.label}" (${r2(rest.scale)})`);
    }
    row.checks.pressResponse = rows;
  }

  // 9g. the capture delivered a unique frame every 20 ms or better while the page animated
  for (const cr of captureRows) {
    row.checks.capture = captureRows;
    if (cr.burstGaps >= 12) {
      if (cr.uniqueFps < LIMITS.uniqueFps) fail(`run ${listed.run}: clip ${cr.clip} delivered ${r2(cr.uniqueFps)} unique frames a second while the page animated (median gap ${r2(cr.medianGapMs)} ms), under ${LIMITS.uniqueFps}`);
      if (cr.floorFps < LIMITS.floorFps) fail(`run ${listed.run}: clip ${cr.clip} dropped to ${r2(cr.floorFps)} fps (95th percentile gap ${r2(cr.p95GapMs)} ms), under the ${LIMITS.floorFps} fps floor`);
    }
  }

  // 7. the cursor is on the click point at the click time
  const cursorRows = [];
  for (const c of plan.cursor.clicks) {
    if (plan.cursor.mode === 'touch') continue;
    const t = T0 + c.t;
    const st = M.stateAt(plan, c.t);
    if (!st.cursor || st.cursor.visible < 0.99 || st.cursor.hidden > 0) continue;
    const screen = M.projectPoint(st.camera, g, { x: c.x, y: c.y });
    const frameFull = grayAt(candidate, Math.min(t, filmEnd - 0.03), g.W, g.H);
    if (!frameFull) continue;
    const tpl = cursorTemplate(st.cursor.kind, M.cursorHeightFor(st.camera.z, g) * st.press);
    const found = findCursor(frameFull, g.W, g.H, tpl, screen.x, screen.y, 14);
    const err = Math.hypot(found.x - screen.x, found.y - screen.y);
    cursorRows.push({ label: c.label, t: c.t, expected: { x: r2(screen.x), y: r2(screen.y) }, found: { x: r2(found.x), y: r2(found.y) }, errorPx: r2(err), ncc: r2(found.ncc) });
    if (!(found.ncc >= LIMITS.cursorNcc) || err > LIMITS.cursorPx) fail(`run ${listed.run}: the cursor is not drawn on the click point of "${c.label}" at ${c.t}s (found ${r2(err)} px away, correlation ${r2(found.ncc)})`);
  }
  row.cursorAtClicks = cursorRows;
}

finish();
