#!/usr/bin/env node
// Fail-closed frame-integrity gate on the ENCODED candidate: catches the two defects a viewer sees at once and
// a sync or dead-screen gate does not: a tiled frame (the picture repeated in two halves, a broken scale/crop/stack
// chain) and an undeclared luma jump (a flash to black or white that is not a planned cut).
// Usage: node validate-frame-integrity.mjs <jobRoot> <candidate.mp4> [--out qa/frame-integrity.json] [--sample-fps 2]
//        [--tile-psnr 32] [--luma-jump 40] [--contrast-floor 12] [--cut-window 0.25] [--cue-sheet plan/cue-sheet.json]
//
// One ffmpeg pass decodes the candidate to 256x160 gray rawvideo at --sample-fps. Per frame:
//   tiled-frame  PSNR(left half, right half) or PSNR(top half, bottom half) above --tile-psnr dB, while the frame's
//                pixel standard deviation is above --contrast-floor (a flat frame is never "tiled").
//   luma-jump    |mean luma(i) - mean luma(i-1)| above --luma-jump levels (0-255), unless a declared cut lies within
//                --cut-window seconds of the sampled interval. Declared cuts come from the cue sheet: edl[].startSeconds,
//                beats[].slot_start and 0. Without a cue sheet nothing is exempt.
// Writes qa/frame-integrity.json bound to the candidate's sha256 and byte count (and the cue sheet's, when read).
import { existsSync, readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve, relative, isAbsolute } from 'node:path';

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
const [jobRoot, candidateArg] = pos;
const USAGE = 'Usage: node validate-frame-integrity.mjs <jobRoot> <candidate.mp4> [--out qa/frame-integrity.json] [--sample-fps 2] [--tile-psnr 32] [--luma-jump 40] [--contrast-floor 12] [--cut-window 0.25]';
if (!jobRoot || !candidateArg) { console.error(USAGE); process.exit(1); }

const root = resolve(jobRoot);
const candidate = resolve(candidateArg);
const SAMPLE_FPS = Number(flag('--sample-fps', 2));
const TILE_PSNR = Number(flag('--tile-psnr', 32));
const LUMA_JUMP = Number(flag('--luma-jump', 40));
const CONTRAST_FLOOR = Number(flag('--contrast-floor', 12));
const CUT_WINDOW = Number(flag('--cut-window', 0.25));
const W = 256, H = 160;
const outPath = resolve(root, flag('--out', 'qa/frame-integrity.json'));
const cueSheetPath = resolve(root, flag('--cue-sheet', 'plan/cue-sheet.json'));

const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const rel = (p) => { const r = relative(root, p); return (r && !r.startsWith('..') && !isAbsolute(r) ? r : p).replace(/\\/g, '/'); };
const errors = [];
const warnings = [];
const fail = (m) => { console.error(`[frame-integrity] ${m}`); errors.push(m); };

const thresholds = { tilePsnr: TILE_PSNR, lumaJump: LUMA_JUMP, contrastFloor: CONTRAST_FLOOR, cutWindow: CUT_WINDOW, decode: `${W}x${H} gray`, sampleFps: SAMPLE_FPS };
const report = {
  generator: 'media-studio/validate-frame-integrity', schemaVersion: '1.0.0', ok: false, errors, warnings,
  candidate: null, inputs: {}, thresholds, sampled: 0, sampleFps: SAMPLE_FPS,
  tiled: [], lumaJumps: [], exemptCuts: [],
  checks: { performed: [], notPerformed: [{ check: 'flash-between-samples', reason: `a single-frame flash shorter than ${(1 / SAMPLE_FPS).toFixed(2)} s can fall between samples; raise --sample-fps to look for one` }] },
};

function finish() {
  report.ok = errors.length === 0 && !!report.candidate;
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: report.ok, out: rel(outPath), sampled: report.sampled, tiled: report.tiled.length, lumaJumps: report.lumaJumps.length, errors, warnings }));
  process.exit(report.ok ? 0 : 1);
}

if (!Number.isFinite(SAMPLE_FPS) || SAMPLE_FPS <= 0) { fail(`--sample-fps must be a positive number, got ${flag('--sample-fps')}`); finish(); }
if (!existsSync(candidate)) { fail(`candidate not found: ${candidate}`); finish(); }
report.candidate = { path: rel(candidate), sha256: sha(candidate), bytes: statSync(candidate).size };

// ---- declared cuts
const cuts = new Set([0]);
if (existsSync(cueSheetPath)) {
  let sheet = null;
  try { sheet = JSON.parse(readFileSync(cueSheetPath, 'utf8').replace(/^﻿/, '')); } catch (e) { fail(`cue sheet is not valid JSON: ${rel(cueSheetPath)} (${e.message})`); }
  report.inputs.cueSheet = { path: rel(cueSheetPath), sha256: sha(cueSheetPath) };
  for (const g of sheet?.edl || []) if (Number.isFinite(g.startSeconds)) cuts.add(g.startSeconds);
  for (const b of sheet?.beats || []) if (Number.isFinite(b.slot_start)) cuts.add(b.slot_start);
  if (sheet && cuts.size === 1) warnings.push('cue sheet declares no cuts (no edl and no beat slot_start); every luma jump counts');
} else {
  warnings.push(`no cue sheet at ${rel(cueSheetPath)}: nothing is exempt, so a planned hard cut that jumps luma reads as a failure`);
}
const declared = [...cuts].sort((a, b) => a - b);

// ---- one decode pass
const dec = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-threads', '2', '-i', candidate, '-an', '-vf', `fps=${SAMPLE_FPS},scale=${W}:${H}:flags=area`, '-pix_fmt', 'gray', '-f', 'rawvideo', '-'], { windowsHide: true, maxBuffer: 1 << 28, timeout: 600000 });
if (dec.error || dec.status !== 0) { fail(`ffmpeg could not decode the candidate: ${dec.error ? dec.error.message : String(dec.stderr || '').trim().slice(0, 300)}`); finish(); }
const buf = dec.stdout;
const FRAME = W * H;
const n = Math.floor(buf.length / FRAME);
if (!n) { fail('candidate decoded to zero video frames'); finish(); }
report.sampled = n;

// ---- measures (all on the 256x160 gray bytes)
function stats(f) {
  let s = 0, s2 = 0;
  for (let i = 0; i < FRAME; i++) { const v = f[i]; s += v; s2 += v * v; }
  const mean = s / FRAME;
  return { mean, std: Math.sqrt(Math.max(0, s2 / FRAME - mean * mean)) };
}
function psnr(mse) { return mse <= 0 ? 99 : Math.min(99, 10 * Math.log10(255 * 255 / mse)); }
function halvesPsnr(f) {
  const hw = W / 2, hh = H / 2;
  let lr = 0, tb = 0;
  for (let y = 0; y < H; y++) for (let x = 0; x < hw; x++) { const d = f[y * W + x] - f[y * W + x + hw]; lr += d * d; }
  for (let y = 0; y < hh; y++) for (let x = 0; x < W; x++) { const d = f[y * W + x] - f[(y + hh) * W + x]; tb += d * d; }
  return { lr: psnr(lr / (hw * H)), tb: psnr(tb / (W * hh)) };
}
const r2 = (v) => Math.round(v * 100) / 100;

let prev = null;
for (let i = 0; i < n; i++) {
  const f = buf.subarray(i * FRAME, (i + 1) * FRAME);
  const t = r2(i / SAMPLE_FPS);
  const { mean, std } = stats(f);
  if (std > CONTRAST_FLOOR) {
    const p = halvesPsnr(f);
    if (p.lr > TILE_PSNR) {
      report.tiled.push({ t, axis: 'horizontal', psnr: r2(p.lr) });
      fail(`tiled-frame at t=${t}s: left and right halves are near-identical (PSNR ${r2(p.lr)} dB > ${TILE_PSNR} dB, contrast ${r2(std)}); the picture is repeated across the frame`);
    } else if (p.tb > TILE_PSNR) {
      report.tiled.push({ t, axis: 'vertical', psnr: r2(p.tb) });
      fail(`tiled-frame at t=${t}s: top and bottom halves are near-identical (PSNR ${r2(p.tb)} dB > ${TILE_PSNR} dB, contrast ${r2(std)}); the picture is repeated down the frame`);
    }
  }
  if (prev) {
    const delta = Math.abs(mean - prev.mean);
    if (delta > LUMA_JUMP) {
      // the jump happened somewhere between the previous sample and this one
      const lo = (i - 1) / SAMPLE_FPS - CUT_WINDOW, hi = t + CUT_WINDOW;
      const cut = declared.find((c) => c >= lo && c <= hi);
      const rec = { t, from: r2(prev.mean), to: r2(mean), delta: r2(delta) };
      if (cut !== undefined) report.exemptCuts.push({ ...rec, cut });
      else {
        report.lumaJumps.push(rec);
        fail(`luma-jump at t=${t}s: mean luma ${rec.from} -> ${rec.to} (delta ${rec.delta} > ${LUMA_JUMP}) and no cut is declared there; a flash to black or white that the edit list does not plan`);
      }
    }
  }
  prev = { mean };
}
report.checks.performed = ['tiled-frame', 'luma-jump'];
finish();
