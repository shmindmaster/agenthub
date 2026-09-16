#!/usr/bin/env node
// Fail-closed product-picture gate on the ENCODED candidate. Contract: skills/media-studio/references/product-picture.md
// Usage: node validate-encoded-picture.mjs <jobRoot> <candidate.mp4> [--max-static 6] [--out qa/encoded-picture.json]
//
// The plan validator proves the clips are real captures. This one proves the file a viewer will watch is made of
// them and does not sit still:
//   1. Duration of the candidate matches story/narration-timeline.json (±1.0 s).
//   2. Source binding: for every screen segment, a frame decoded from the candidate at the segment's midpoint
//      perceptually matches (dHash, Hamming ≤ threshold) a frame of the receipt-bound source clip. A card, a
//      screenshot substitute, or a stills animation spliced in place of the capture fails here.
//   3. No dead screen: inside screen segments, no stretch of near-identical frames longer than max-static seconds
//      (default 6; a beat may declare resultHoldSeconds up to 8). Measured on decoded frames, 2 fps, 32×20 gray.
//   4. Cards ≤ 8 s; screen ratio ≥ 70% of the encoded timeline; designed first/last frames (not black).
// Writes qa/encoded-picture.json bound to the candidate's sha256 and byte count. QA and the release ledger cite it.
import { existsSync, readFileSync, mkdirSync, writeFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { extname, join, resolve, dirname } from 'node:path';

const argv = process.argv.slice(2);
const pos = argv.filter((a) => !a.startsWith('--'));
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const [jobRoot, candidateArg] = pos;
if (!jobRoot || !candidateArg) { console.error('Usage: node validate-encoded-picture.mjs <jobRoot> <candidate.mp4> [--max-static 6] [--out qa/encoded-picture.json]'); process.exit(1); }
const MAX_STATIC = Number(flag('--max-static', 6));
const RESULT_HOLD_MAX = 8;
const CARD_MAX_SECONDS = 8;
const SCREEN_DURATION_MIN = 0.7;
const BIND_MAX_HAMMING = Number(flag('--bind-hamming', 12));
const BIND_MAX_HAMMING_OVERLAY = BIND_MAX_HAMMING + 6;
const STATIC_DIFF = 0.6; // mean abs gray diff (0–255) below which two consecutive 2 fps frames count as identical
const FPS = 2;
const SMALL_W = 32, SMALL_H = 20;
const CARD_MODES = new Set(['card', 'slide', 'diagram', 'talking-head', 'motif', 'animation', 'narration-only', 'broll']);
const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.webp']);

const candidate = resolve(candidateArg);
const outPath = resolve(jobRoot, flag('--out', 'qa/encoded-picture.json'));
function readJson(rel) { const p = join(jobRoot, rel); if (!existsSync(p)) return null; return JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, '')); }
const errors = [];
const fail = (m) => { console.error(`[encoded-picture] ${m}`); errors.push(m); };
const run = (args, opts = {}) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', ...args], { maxBuffer: 1 << 30, ...opts });
function probeDuration(p) {
  try { return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', p]).toString()) || 0; } catch { return 0; }
}
const SCALE_PAD = 'scale=1600:1000:force_original_aspect_ratio=decrease,pad=1600:1000:(ow-iw)/2:(oh-ih)/2';
function grayFrames(file, w, h, fps, extra = []) {
  const buf = run(['-i', file, '-vf', `${extra.length ? extra.join(',') + ',' : ''}fps=${fps},scale=${w}:${h}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']);
  const n = Math.floor(buf.length / (w * h));
  const frames = [];
  for (let i = 0; i < n; i++) frames.push(buf.subarray(i * w * h, (i + 1) * w * h));
  return frames;
}
function grayFrameAt(file, t, w, h) {
  const buf = run(['-ss', t.toFixed(3), '-i', file, '-frames:v', '1', '-vf', `scale=${w}:${h}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']);
  return buf.length >= w * h ? buf.subarray(0, w * h) : null;
}
function dhash(gray9x8) { // 9x8 gray -> 64-bit as BigInt
  let bits = 0n;
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { bits <<= 1n; if (gray9x8[y * 9 + x] > gray9x8[y * 9 + x + 1]) bits |= 1n; }
  return bits;
}
function hamming(a, b) { let x = a ^ b, n = 0; while (x) { n += Number(x & 1n); x >>= 1n; } return n; }
const meanDiff = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length; };
const meanLuma = (a) => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i]; return s / a.length; };

if (!existsSync(candidate)) { fail(`candidate not found: ${candidate}`); finish(); }
const job = readJson('job.json') || {};
const tl = readJson('story/narration-timeline.json');
const board = readJson('story/storyboard.json') || readJson('storyboard.json');
const manifest = readJson('capture/manifest.json');
const receipt = readJson('capture/receipt.json');
const base = extname(candidate) ? candidate.slice(candidate.lastIndexOf(/[\\/]/.test(candidate) ? Math.max(candidate.lastIndexOf('\\'), candidate.lastIndexOf('/')) : 0) + 1).replace(/\.[^.]+$/, '') : '';
const composeMap = readJson(`output/${base}-compose-map.json`) || readJson(`output/${base.replace(/-final$|-master$/, '')}-compose-map.json`);
if (!tl) { fail('missing story/narration-timeline.json'); finish(); }
if (!manifest) { fail('missing capture/manifest.json'); finish(); }

const beats = board ? (board.beats || board.scenes || []) : [];
const beatById = new Map();
for (const b of beats) { if (b.id) beatById.set(b.id, b); for (const sid of b.segments || []) beatById.set(sid, b); }
const beatFor = (id) => beatById.get(id) || beatById.get(String(id).replace(/[a-z]$/, '')) || null;
// visualMode: storyboard beat first, then the screenplay scene (exact id, then the id with the beat suffix stripped).
// The storyboards this kit writes carry no visualMode, so without the screenplay every card and code reveal read as a
// screen beat without a clip (Duckie job 13, 2026-09-15). Unknown stays the kind's default so the gate still fails closed.
const screenplayModes = new Map(((readJson('story/screenplay.json') || {}).scenes || []).map((s) => [s.id, s.visualMode]));
const beatMode = (id) => beatFor(id)?.visualMode || screenplayModes.get(id) || screenplayModes.get(String(id).replace(/[a-z]+$/, '')) || (job.kind === 'product-screencast' ? 'screen' : 'slide');
const isScreen = (id) => !CARD_MODES.has(beatMode(id));

// Segment -> source clip mapping: prefer the compose map written by compose-screencast.mjs, else deal like compose.
const segSource = new Map();
if (composeMap?.groups) {
  for (const g of composeMap.groups) for (const sid of g.segments) segSource.set(sid, g);
} else {
  const rawClips = manifest.composeClips || manifest.clips || manifest.entries || manifest.captures || [];
  const clips = rawClips.map((c) => ({ ...c, id: c.id || c.scenario || c.storyboardSegmentId, file: c.file || c.clip || c.video || c.output, segments: c.segments || [c.storyboardSegmentId] }));
  const segsByScene = new Map();
  for (const s of tl.segments) { const sc = s.scene || String(s.id).replace(/[a-z]$/, ''); if (!segsByScene.has(sc)) segsByScene.set(sc, []); segsByScene.get(sc).push(s.id); }
  const q = new Map();
  for (const c of clips) for (const key of c.segments || []) {
    if (tl.segments.some((s) => s.id === key)) { segSource.set(key, { clipId: c.id, file: c.file, overlay: c.overlay || null }); continue; }
    const scene = String(key).replace(/[a-z]$/, '');
    const targets = segsByScene.get(scene) || segsByScene.get(key) || [];
    if (!targets.length) continue;
    const n = q.get(scene) || 0; q.set(scene, n + 1);
    const t = targets[Math.min(n, targets.length - 1)];
    if (!segSource.has(t)) segSource.set(t, { clipId: c.id, file: c.file, overlay: c.overlay || null });
  }
  // a segment with no clip holds the previous clip
  let prev = null;
  for (const s of tl.segments) { if (segSource.has(s.id)) prev = segSource.get(s.id); else if (prev) segSource.set(s.id, { ...prev, heldFromPrevious: true }); }
}

const duration = probeDuration(candidate);
const report = {
  schemaVersion: '1.0.0',
  generator: 'media-studio/validate-encoded-picture',
  candidate: { path: candidate, sha256: createHash('sha256').update(readFileSync(candidate)).digest('hex'), bytes: statSync(candidate).size, durationSeconds: Number(duration.toFixed(3)) },
  timelineSeconds: Number(tl.durationSeconds || 0),
  thresholds: { maxStaticSeconds: MAX_STATIC, resultHoldMax: RESULT_HOLD_MAX, bindMaxHamming: BIND_MAX_HAMMING, staticDiff: STATIC_DIFF, fps: FPS },
  segments: [],
  staticRuns: [],
  screenRatio: null,
  firstFrameLuma: null,
  lastFrameLuma: null,
};
if (Math.abs(duration - Number(tl.durationSeconds || 0)) > 1.0) fail(`candidate is ${duration.toFixed(2)}s but the narration timeline is ${Number(tl.durationSeconds).toFixed(2)}s`);

// 3. dead-screen scan on the decoded candidate
const frames = grayFrames(candidate, SMALL_W, SMALL_H, FPS);
const staticFlags = frames.map((f, i) => (i === 0 ? false : meanDiff(frames[i - 1], f) < STATIC_DIFF));
const runs = [];
let runStart = null;
for (let i = 0; i < staticFlags.length; i++) {
  if (staticFlags[i] && runStart === null) runStart = i - 1;
  if ((!staticFlags[i] || i === staticFlags.length - 1) && runStart !== null) {
    const end = staticFlags[i] ? i : i - 1;
    runs.push({ startSeconds: runStart / FPS, endSeconds: (end + 1) / FPS, seconds: (end + 1 - runStart) / FPS });
    runStart = null;
  }
}
// A time inside a pause between two segments belongs to the nearest segment: the pause is the preceding beat's picture,
// not a card, so a static run that straddles a pause is judged by that beat's rules.
const segAt = (t) => tl.segments.find((s) => t >= s.startSeconds && t < s.startSeconds + s.durationSeconds)
  || tl.segments.reduce((best, s) => { const d = t < s.startSeconds ? s.startSeconds - t : t - (s.startSeconds + s.durationSeconds); return !best || d < best.d ? { s, d } : best; }, null)?.s || null;
for (const r of runs) {
  const mid = (r.startSeconds + r.endSeconds) / 2;
  const seg = segAt(mid);
  const tailAllowance = duration - 1.5; // final designed hold / fade
  const inScreen = seg ? isScreen(seg.id) : false;
  const declared = seg ? Math.min(RESULT_HOLD_MAX, Number(beatFor(seg.id)?.resultHoldSeconds || 0)) : 0;
  const allowed = Math.max(MAX_STATIC, declared);
  const row = { ...r, seconds: Number(r.seconds.toFixed(1)), segment: seg?.id || null, screen: inScreen, allowedSeconds: allowed };
  report.staticRuns.push(row);
  if (r.startSeconds >= tailAllowance || r.endSeconds <= 0.7) continue;
  if (inScreen && r.seconds > allowed) fail(`dead screen: ${r.seconds.toFixed(1)}s of near-identical frames at ${r.startSeconds.toFixed(1)}–${r.endSeconds.toFixed(1)}s (segment ${seg.id}); max ${allowed}s. Redesign the beat: the product must be doing something while the voice talks.`);
  if (!inScreen && r.seconds > CARD_MAX_SECONDS) fail(`card held ${r.seconds.toFixed(1)}s at ${r.startSeconds.toFixed(1)}s (segment ${seg?.id}); cards on a screencast are ≤${CARD_MAX_SECONDS}s`);
}

// 2. source binding per screen segment + card/ratio accounting
let screenSeconds = 0, totalSeconds = 0;
const clipHashCache = new Map();
function clipHashes(file) {
  if (clipHashCache.has(file)) return clipHashCache.get(file);
  const abs = resolve(jobRoot, 'capture', file);
  if (!existsSync(abs)) { clipHashCache.set(file, null); return null; }
  const fr = grayFrames(abs, 9, 8, FPS, [SCALE_PAD]);
  const hs = fr.map(dhash);
  clipHashCache.set(file, hs);
  return hs;
}
for (const seg of tl.segments) {
  const dur = Number(seg.durationSeconds) || 0;
  totalSeconds += dur;
  const src = segSource.get(seg.id) || null;
  const row = { id: seg.id, startSeconds: seg.startSeconds, durationSeconds: dur, mode: beatMode(seg.id), source: src?.clipId || src?.file || null, bound: null, hamming: null };
  report.segments.push(row);
  if (!isScreen(seg.id)) { if (dur > CARD_MAX_SECONDS) fail(`segment ${seg.id} (${row.mode}) is ${dur}s; cards are ≤${CARD_MAX_SECONDS}s`); continue; }
  screenSeconds += dur;
  if (!src || !src.file) { fail(`segment ${seg.id} is a screen beat with no source clip in the compose map / manifest`); continue; }
  if (IMAGE_EXT.has(extname(src.file).toLowerCase())) { fail(`segment ${seg.id} screen beat is composed from a still (${src.file})`); continue; }
  if (receipt && !Object.values(receipt.clips || {}).some((e) => e.file === src.file || src.file.endsWith(e.file))) fail(`segment ${seg.id}: source ${src.file} is not a receipt-bound capture`);
  const hs = clipHashes(src.file);
  if (!hs || !hs.length) { fail(`segment ${seg.id}: cannot decode source clip ${src.file}`); continue; }
  const mid = seg.startSeconds + Math.min(dur / 2, Math.max(0.5, dur / 2));
  const fr = grayFrameAt(candidate, Math.min(mid, duration - 0.2), 9, 8);
  if (!fr) { fail(`segment ${seg.id}: cannot decode candidate frame at ${mid.toFixed(2)}s`); continue; }
  const h = dhash(fr);
  let best = 64;
  for (const c of hs) { const d = hamming(h, c); if (d < best) best = d; if (best === 0) break; }
  row.hamming = best;
  const limit = src.overlay ? BIND_MAX_HAMMING_OVERLAY : BIND_MAX_HAMMING;
  row.bound = best <= limit;
  if (!row.bound) fail(`segment ${seg.id}: candidate frame at ${mid.toFixed(1)}s does not match any frame of the captured clip ${src.file} (dHash distance ${best} > ${limit}); the encoded picture is not the receipt-bound capture`);
}
report.screenRatio = totalSeconds ? Number((screenSeconds / totalSeconds).toFixed(3)) : null;
if (totalSeconds && screenSeconds / totalSeconds < SCREEN_DURATION_MIN) fail(`screen ratio ${(screenSeconds / totalSeconds).toFixed(3)} < ${SCREEN_DURATION_MIN}`);

// 4. designed first / last frames
const f0 = grayFrameAt(candidate, Math.min(0.7, duration / 2), SMALL_W, SMALL_H);
const f1 = grayFrameAt(candidate, Math.max(0, duration - 1.0), SMALL_W, SMALL_H);
report.firstFrameLuma = f0 ? Number(meanLuma(f0).toFixed(1)) : null;
report.lastFrameLuma = f1 ? Number(meanLuma(f1).toFixed(1)) : null;
if (f0 && meanLuma(f0) < 10) fail(`first frame (0.7s) is black (luma ${meanLuma(f0).toFixed(1)}); design the opening frame`);
if (f1 && meanLuma(f1) < 10) fail(`last frame (−1.0s) is black (luma ${meanLuma(f1).toFixed(1)}); design the closing frame`);

finish();

function finish() {
  report.ok = errors.length === 0;
  report.errors = errors;
  report.generatedAt = new Date().toISOString();
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  if (errors.length) { console.error(`[encoded-picture] ${errors.length} error(s); report ${outPath}`); process.exit(1); }
  console.log(JSON.stringify({ ok: true, report: outPath, sha256: report.candidate.sha256, screenRatio: report.screenRatio, staticRuns: report.staticRuns.length, segments: report.segments.length }));
  process.exit(0);
}
