#!/usr/bin/env node
// Fail-closed product-picture gate (plan + clips). Contract: skills/media-studio/references/product-picture.md
// Usage: node validate-product-picture.mjs <jobRoot> [--json]
//
// What it proves before compose is allowed to run:
//   1. Every `screen` beat maps to a real video clip on disk (ffprobe: video stream, duration), never a still.
//   2. Every screen clip is bound by capture/receipt.json (record-job.mjs) — sha256 of the file on disk matches a
//      receipt entry recorded from a live Playwright session with pointer motion. Stills animations, looped PNGs,
//      re-encoded plates, or a hand-typed manifest cannot produce that receipt.
//   3. Interaction beats (capture-plan kind=interaction) have at least one real action and an observed expectation.
//   4. Recast finishing ran (full or noZoom). A raw fallback needs job.recastFallbackAllowed; skipped needs intent=draft.
//   5. No hidden freeze: a clip shorter than its narration by more than HOLD_PAD_MAX seconds fails unless the
//      storyboard beat declares resultHoldSeconds covering the gap (≤ RESULT_HOLD_MAX). `fit` retiming beyond ±20%
//      fails (it misrepresents product speed). `speed` > 1 needs speedReason.
//   6. ≥70% of the timeline is screen; cards ≤ 8 s each.
// The encoded master is checked separately by validate-encoded-picture.mjs (QA). intent=draft never skips this gate.
import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { extname, join, resolve } from 'node:path';

export const SCREEN_DURATION_MIN = 0.7;
export const CARD_MAX_SECONDS = 8;
export const HOLD_PAD_MAX = 2.0;
export const RESULT_HOLD_MAX = 6.0;
export const FIT_RATIO_MIN = 0.8;
export const FIT_RATIO_MAX = 1.25;
const VIDEO_EXT = new Set(['.webm', '.mp4', '.mov']);
const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.webp']);
const PRODUCT_FORMS = new Set([
  'product-overview', 'outcome-workflow', 'role-demo', 'feature-tutorial', 'ai-in-action', 'integration-demo',
  'competitive-demo', 'technical-story', 'onboarding', 'help-center', 'before-after', 'release',
]);
const CARD_MODES = new Set(['slide', 'diagram', 'talking-head', 'motif', 'animation', 'narration-only', 'broll']);

const args = process.argv.slice(2);
const jobRoot = args.find((a) => !a.startsWith('--'));
if (!jobRoot) { console.error('Usage: node validate-product-picture.mjs <jobRoot>'); process.exit(1); }

function readJson(rel) {
  const p = join(jobRoot, rel);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, ''));
}
let errorCount = 0;
const warnings = [];
function fail(message) { console.error(`[product-picture] ${message}`); errorCount += 1; }
function warn(message) { console.error(`[product-picture] warning: ${message}`); warnings.push(message); }
const isVideoName = (f) => typeof f === 'string' && VIDEO_EXT.has(extname(f).toLowerCase());
const isImageName = (f) => typeof f === 'string' && IMAGE_EXT.has(extname(f).toLowerCase());
const sha256 = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
function probe(p) {
  try {
    const out = execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_type,width,height,nb_frames:format=duration', '-of', 'json', p], { encoding: 'utf8' });
    const j = JSON.parse(out);
    const v = (j.streams || []).find((s) => s.codec_type === 'video');
    return { duration: Number(j.format?.duration) || 0, video: !!v, width: v?.width || 0, height: v?.height || 0 };
  } catch { return null; }
}

const job = readJson('job.json');
if (!job) { fail('missing job.json'); process.exit(1); }
const draft = job.intent === 'draft';
const kind = job.kind;
const form = job.programForm;
if (PRODUCT_FORMS.has(form) && kind !== 'product-screencast') {
  fail(`programForm ${form} requires kind product-screencast (got ${kind || 'missing'}). A running product is not a briefing.`);
}
const applies = kind === 'product-screencast' || PRODUCT_FORMS.has(form);
if (!applies) { console.log(JSON.stringify({ ok: true, skipped: `kind=${kind}` })); process.exit(0); }
if (kind !== 'product-screencast') fail('product-picture applies but kind is not product-screencast');

const board = readJson('story/storyboard.json') || readJson('storyboard.json');
const timeline = readJson('story/narration-timeline.json');
const manifest = readJson('capture/manifest.json');
const plan = readJson('story/capture-plan.json');
const receipt = readJson('capture/receipt.json');
if (!board) fail('missing story/storyboard.json');
if (!manifest) fail('missing capture/manifest.json');

const beats = board ? (board.beats || board.scenes || []) : [];
const beatById = new Map();
for (const b of beats) { if (b.id) beatById.set(b.id, b); for (const sid of b.segments || []) beatById.set(sid, b); }
const beatFor = (id) => beatById.get(id) || beatById.get(String(id).replace(/[a-z]$/, '')) || null;
const beatMode = (id) => beatFor(id)?.visualMode || 'screen';
const isScreenMode = (mode) => mode === 'screen' || !CARD_MODES.has(mode);

const rawClips = manifest ? (manifest.composeClips || manifest.clips || manifest.entries || manifest.captures || []) : [];
const clips = rawClips.map((c) => ({
  ...c,
  id: c.id || c.scenario || c.storyboardSegmentId,
  file: c.file || c.clip || c.video || c.output,
  segments: c.segments || (c.storyboardSegmentId ? [c.storyboardSegmentId] : []),
  autoCard: c.autoCard === true,
}));
const segments = timeline?.segments?.length
  ? timeline.segments
  : beats.map((b, i) => ({ id: b.id, scene: b.id, durationSeconds: Number(b.durationSeconds) || 0, order: i }));
if (!segments.length) fail('no storyboard beats or narration-timeline segments to measure');

// Deal clips to segments the same way compose-screencast.mjs does (segment id, or scene id spanning segments).
const segsByScene = new Map();
for (const s of segments) { const sc = s.scene || String(s.id).replace(/[a-z]$/, ''); if (!segsByScene.has(sc)) segsByScene.set(sc, []); segsByScene.get(sc).push(s.id); }
const clipBySeg = new Map();
const sceneQueue = new Map();
for (const c of clips) {
  for (const key of c.segments || []) {
    if (segments.some((s) => s.id === key)) { clipBySeg.set(key, c); continue; }
    const scene = String(key).replace(/[a-z]$/, '');
    const targets = segsByScene.get(scene) || segsByScene.get(key) || [];
    if (!targets.length) continue;
    const q = sceneQueue.get(scene) || 0; sceneQueue.set(scene, q + 1);
    const target = targets[Math.min(q, targets.length - 1)];
    if (!clipBySeg.has(target)) clipBySeg.set(target, c);
  }
}

// Interaction beats per capture plan
const interactionScenes = new Set();
for (const s of plan?.scenes || []) if (s.kind === 'interaction') interactionScenes.add(s.sceneId);

let screenSeconds = 0;
let totalSeconds = 0;
const needByClip = new Map(); // clip -> { need, segments[] }
for (const seg of segments) {
  const dur = Number(seg.durationSeconds) || 0;
  totalSeconds += dur;
  const mode = beatMode(seg.id);
  if (!isScreenMode(mode)) {
    if (dur > CARD_MAX_SECONDS) fail(`segment ${seg.id} visualMode=${mode} is ${dur}s; card/slide/diagram cutaways on a product-screencast are ≤${CARD_MAX_SECONDS}s`);
    continue;
  }
  screenSeconds += dur;
  const clip = clipBySeg.get(seg.id);
  if (!clip) { fail(`segment ${seg.id} is visualMode=screen with no captured clip; auto-card is forbidden`); continue; }
  if (clip.autoCard) fail(`segment ${seg.id} screen beat used an auto-card`);
  if (isImageName(clip.file)) fail(`segment ${seg.id} screen beat is a still (${clip.file}); product screens require WebM/MP4 + Recast`);
  else if (clip.file && !isVideoName(clip.file)) fail(`segment ${seg.id} screen clip ${clip.file} is not a video file`);
  const rec = needByClip.get(clip) || { need: 0, segments: [] };
  rec.need += dur; rec.segments.push(seg.id);
  needByClip.set(clip, rec);
}

if (totalSeconds > 0) {
  const ratio = screenSeconds / totalSeconds;
  if (ratio < SCREEN_DURATION_MIN) fail(`screen duration ratio ${ratio.toFixed(3)} < ${SCREEN_DURATION_MIN} (${screenSeconds.toFixed(1)}s of ${totalSeconds.toFixed(1)}s)`);
}

// Clip-level evidence: file on disk, real video, receipt-bound, pointer motion, Recast, no hidden freeze.
const receiptBySha = new Map();
for (const [id, entry] of Object.entries(receipt?.clips || {})) if (entry?.sha256) receiptBySha.set(entry.sha256, { id, ...entry });
if (needByClip.size && !receipt) fail('missing capture/receipt.json; screen clips must come from kit/screencast/record-job.mjs (live Playwright session, hash-bound receipt)');
const clipReport = [];
for (const [clip, { need, segments: segIds }] of needByClip) {
  if (!isVideoName(clip.file)) continue;
  const abs = resolve(jobRoot, 'capture', clip.file);
  const label = `${clip.id} (${segIds.join('+')})`;
  if (!existsSync(abs)) { fail(`clip ${label}: file not found: ${clip.file}`); continue; }
  const info = probe(abs);
  if (!info || !info.video) { fail(`clip ${label}: ffprobe found no video stream in ${clip.file}`); continue; }
  if (info.duration < 0.5) fail(`clip ${label}: video is ${info.duration.toFixed(2)}s; not a capture`);
  const hash = sha256(abs);
  const entry = receipt ? receiptBySha.get(hash) : null;
  const row = { clip: clip.id, file: clip.file, segments: segIds, needSeconds: Number(need.toFixed(2)), clipSeconds: Number(info.duration.toFixed(2)), receipt: !!entry, recast: entry?.recast || null, events: entry?.events || null };
  clipReport.push(row);
  if (receipt && !entry) {
    fail(`clip ${label}: sha256 ${hash.slice(0, 12)} is not in capture/receipt.json; the encoded picture must be the receipt-bound clip from record-job.mjs (no re-encode, no substitution)`);
  } else if (entry) {
    if (entry.valid === false) fail(`clip ${label}: receipt marks the take invalid (${entry.error || (entry.events?.expectationsFailed || []).join(',') || 'no pointer motion'})`);
    const ev = entry.events || {};
    if (!(ev.pointerMoves > 0)) fail(`clip ${label}: receipt records no pointer motion; a screen beat needs a visible pointer lead`);
    const interactive = segIds.some((s) => interactionScenes.has(s) || interactionScenes.has(String(s).replace(/[a-z]$/, '')));
    if (interactive) {
      if (!((ev.clicks || 0) + (ev.keystrokes || 0) + (ev.scrolls || 0) > 0)) fail(`clip ${label}: interaction beat with no click/type/scroll in the receipt`);
      if (!(ev.expectationsObserved > 0)) {
        // A trace-backfilled receipt (backfill-capture-receipt.mjs) proves a live session and real clicks from the
        // Playwright trace but cannot prove the scene waited for the product's response. Accept it only when the
        // recorder marked beats, and say so; the kit recorder's h.expect() is the real proof.
        if (entry.source === 'trace-backfill' && (entry.beats || []).length > 0) warn(`clip ${label}: trace-backfilled receipt has no observed expectation; accepted on beat marks (${entry.beats.length}). Re-record with kit/screencast/record-job.mjs for a live receipt.`);
        else fail(`clip ${label}: interaction beat with no observed product response (h.expect) in the receipt`);
      }
    }
    const rc = entry.recast;
    if (rc === 'full' || rc === 'noZoom') { /* ok */ }
    else if (rc === 'fallback') {
      if (job.recastFallbackAllowed === true) warn(`clip ${label}: Recast fallback accepted (job.recastFallbackAllowed): ${entry.recastNote || 'no note'}`);
      else fail(`clip ${label}: Recast did not run (fallback: ${entry.recastNote || 'no note'}); pointer finishing is required. Split the take, render without autoZoom, or set job.recastFallbackAllowed with a reason.`);
    } else if (rc === 'skipped') {
      if (draft) warn(`clip ${label}: Recast skipped on a draft`);
      else fail(`clip ${label}: Recast skipped (--no-recast) on a viewer-facing job`);
    } else if (rc === 'unknown' && entry.source === 'trace-backfill') warn(`clip ${label}: Recast status unknown on a trace-backfilled receipt`);
    else fail(`clip ${label}: receipt has no Recast status`);
  }
  // Hidden-freeze / retime rules
  const trimStart = Number(clip.trimStart || 0);
  const trimEnd = clip.trimEnd ? Number(clip.trimEnd) : info.duration;
  const skipped = (clip.skip || []).reduce((n, [a, b]) => n + Math.max(0, Number(b) - Number(a)), 0);
  const speed = Number(clip.speed || 1);
  if (speed > 1 && !clip.speedReason) fail(`clip ${label}: speed ${speed}x needs speedReason (only real wait time may be compressed)`);
  const effective = Math.max(0, (trimEnd - trimStart - skipped)) / (speed > 0 ? speed : 1);
  row.effectiveSeconds = Number(effective.toFixed(2));
  const fit = clip.fit || (effective > need ? 'cut' : 'hold');
  row.fit = fit;
  if (fit === 'fit') {
    const r = need / (effective || 1);
    if (r < FIT_RATIO_MIN || r > FIT_RATIO_MAX) fail(`clip ${label}: fit retimes ${effective.toFixed(1)}s of product footage to ${need.toFixed(1)}s (${r.toFixed(2)}x); allowed ${FIT_RATIO_MIN}–${FIT_RATIO_MAX}x. Re-pace the take or split the beat.`);
  } else if (fit === 'hold' || fit === 'fitpad') {
    const pad = need - effective;
    if (pad > HOLD_PAD_MAX) {
      const declared = Math.max(0, ...segIds.map((s) => Number(beatFor(s)?.resultHoldSeconds || 0)));
      if (!(declared >= pad && declared <= RESULT_HOLD_MAX)) {
        fail(`clip ${label}: ${effective.toFixed(1)}s of footage would be frozen for ${pad.toFixed(1)}s to cover ${need.toFixed(1)}s of narration (max ${HOLD_PAD_MAX}s, or a storyboard resultHoldSeconds ≤ ${RESULT_HOLD_MAX}s). That is a screenshot posing as a screencast — re-pace the take, cut the narration, or split the beat.`);
      }
    }
  }
}

if (plan?.scenes) {
  for (const scene of plan.scenes) {
    if (scene.kind === 'hold' && isImageName(scene.clip || scene.plateName)) fail(`capture-plan ${scene.sceneId} hold is a still; hold is the last frame of the preceding WebM`);
    if (scene.kind !== 'interaction') continue;
    if (!scene.action) fail(`capture-plan ${scene.sceneId} interaction missing action`);
    if (!scene.expectedResult) fail(`capture-plan ${scene.sceneId} interaction missing expectedResult`);
    if (!scene.clip) fail(`capture-plan ${scene.sceneId} interaction missing video clip`);
    if (scene.clip && isImageName(scene.clip)) fail(`capture-plan ${scene.sceneId} interaction clip is a still (${scene.clip})`);
    if (scene.plateName && /\.(png|jpg|jpeg|webp)$/i.test(scene.plateName) && !scene.clip) fail(`capture-plan ${scene.sceneId} names a PNG plate with no video clip; plates are diagnostic only`);
  }
}

if (errorCount > 0) { console.error(`[product-picture] ${errorCount} error(s)`); process.exit(1); }
console.log(JSON.stringify({
  ok: true,
  kind,
  programForm: form || null,
  intent: job.intent || null,
  screenSeconds: Number(screenSeconds.toFixed(2)),
  totalSeconds: Number(totalSeconds.toFixed(2)),
  screenRatio: totalSeconds > 0 ? Number((screenSeconds / totalSeconds).toFixed(3)) : null,
  clips: clipReport,
  warnings,
}));
