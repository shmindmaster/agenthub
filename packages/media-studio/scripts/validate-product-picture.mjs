#!/usr/bin/env node
// Fail-closed product-picture gate. Contract: skills/media-studio/references/product-picture.md
// Usage: node validate-product-picture.mjs <jobRoot>
import { existsSync, readFileSync } from 'node:fs';
import { extname, join } from 'node:path';

const SCREEN_DURATION_MIN = 0.7;
const CARD_MAX_SECONDS = 8;
const VIDEO_EXT = new Set(['.webm', '.mp4', '.mov']);
const PRODUCT_FORMS = new Set([
  'product-overview',
  'outcome-workflow',
  'role-demo',
  'feature-tutorial',
  'ai-in-action',
  'integration-demo',
  'competitive-demo',
  'technical-story',
  'onboarding',
  'help-center',
  'before-after',
  'release',
]);
const CARD_MODES = new Set(['slide', 'diagram', 'talking-head', 'motif', 'animation', 'narration-only', 'broll']);

const jobRoot = process.argv[2];
if (!jobRoot) {
  console.error('Usage: node validate-product-picture.mjs <jobRoot>');
  process.exit(1);
}

function readJson(rel) {
  const p = join(jobRoot, rel);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
}

function fail(message) {
  console.error(`[product-picture] ${message}`);
  errorCount += 1;
}

function clipLooksVideo(file) {
  if (!file || typeof file !== 'string') return false;
  return VIDEO_EXT.has(extname(file).toLowerCase());
}

function clipLooksImage(file) {
  if (!file || typeof file !== 'string') return false;
  return ['.png', '.jpg', '.jpeg', '.webp'].includes(extname(file).toLowerCase());
}

let errorCount = 0;
const job = readJson('job.json');
if (!job) {
  fail('missing job.json');
  process.exit(1);
}

if (job.intent === 'draft') {
  console.log(JSON.stringify({ ok: true, skipped: 'intent:draft' }));
  process.exit(0);
}

const kind = job.kind;
const form = job.programForm;
if (PRODUCT_FORMS.has(form) && kind !== 'product-screencast') {
  fail(`programForm ${form} requires kind product-screencast (got ${kind || 'missing'}). A running product is not a briefing.`);
}

const applies = kind === 'product-screencast' || PRODUCT_FORMS.has(form);
if (!applies) {
  console.log(JSON.stringify({ ok: true, skipped: `kind=${kind}` }));
  process.exit(0);
}

if (kind !== 'product-screencast') {
  fail('product-picture applies but kind is not product-screencast');
}

const board = readJson('story/storyboard.json') || readJson('storyboard.json');
const timeline = readJson('story/narration-timeline.json');
const manifest = readJson('capture/manifest.json');
const plan = readJson('story/capture-plan.json');

if (!board) fail('missing story/storyboard.json');
if (!manifest) fail('missing capture/manifest.json');

const beats = board ? (board.beats || board.scenes || []) : [];
const beatById = new Map();
for (const b of beats) {
  if (b.id) beatById.set(b.id, b);
  for (const sid of b.segments || []) beatById.set(sid, b);
}

function beatMode(id) {
  const b = beatById.get(id);
  if (b?.visualMode) return b.visualMode;
  return 'screen';
}

const rawClips = manifest ? (manifest.composeClips || manifest.clips || manifest.entries || manifest.captures || []) : [];
const clips = rawClips.map((c) => ({
  ...c,
  id: c.id || c.scenario || c.storyboardSegmentId,
  file: c.file || c.clip || c.video || c.output,
  segments: c.segments || (c.storyboardSegmentId ? [c.storyboardSegmentId] : []),
  autoCard: c.autoCard === true,
}));

const clipBySeg = new Map();
for (const c of clips) {
  for (const key of c.segments || []) clipBySeg.set(key, c);
}

const segments = timeline?.segments?.length
  ? timeline.segments
  : beats.map((b, i) => ({
      id: b.id,
      durationSeconds: Number(b.durationSeconds) || 0,
      order: i,
    }));

if (!segments.length) fail('no storyboard beats or narration-timeline segments to measure');

let screenSeconds = 0;
let totalSeconds = 0;
for (const seg of segments) {
  const dur = Number(seg.durationSeconds) || 0;
  totalSeconds += dur;
  const mode = beatMode(seg.id);
  const isScreen = mode === 'screen' || !CARD_MODES.has(mode);
  if (!isScreen) {
    if (dur > CARD_MAX_SECONDS) {
      fail(`segment ${seg.id} visualMode=${mode} is ${dur}s; card/slide/diagram cutaways on a product-screencast are ≤${CARD_MAX_SECONDS}s`);
    }
    continue;
  }
  screenSeconds += dur;
  const clip = clipBySeg.get(seg.id);
  if (!clip) {
    fail(`segment ${seg.id} is visualMode=screen with no captured clip; auto-card is forbidden`);
    continue;
  }
  if (clip.autoCard) fail(`segment ${seg.id} screen beat used an auto-card`);
  if (clipLooksImage(clip.file)) {
    fail(`segment ${seg.id} screen beat is a still (${clip.file}); product screens require WebM/MP4 + Recast`);
  }
  if (clip.file && !clipLooksVideo(clip.file) && !clipLooksImage(clip.file)) {
    fail(`segment ${seg.id} screen clip ${clip.file} is not a video file`);
  }
}

if (totalSeconds > 0) {
  const ratio = screenSeconds / totalSeconds;
  if (ratio < SCREEN_DURATION_MIN) {
    fail(`screen duration ratio ${ratio.toFixed(3)} < ${SCREEN_DURATION_MIN} (${screenSeconds.toFixed(1)}s of ${totalSeconds.toFixed(1)}s)`);
  }
}

if (plan?.scenes) {
  for (const scene of plan.scenes) {
    if (scene.kind === 'hold' && clipLooksImage(scene.clip || scene.plateName)) {
      fail(`capture-plan ${scene.sceneId} hold is a still; hold is the last frame of the preceding WebM`);
    }
    if (scene.kind !== 'interaction') continue;
    if (!scene.action) fail(`capture-plan ${scene.sceneId} interaction missing action`);
    if (!scene.expectedResult) fail(`capture-plan ${scene.sceneId} interaction missing expectedResult`);
    if (!scene.clip) fail(`capture-plan ${scene.sceneId} interaction missing video clip`);
    if (scene.clip && clipLooksImage(scene.clip)) {
      fail(`capture-plan ${scene.sceneId} interaction clip is a still (${scene.clip})`);
    }
    if (scene.plateName && /\.(png|jpg|jpeg|webp)$/i.test(scene.plateName) && !scene.clip) {
      fail(`capture-plan ${scene.sceneId} names a PNG plate with no video clip; plates are diagnostic only`);
    }
  }
}

if (errorCount > 0) {
  console.error(`[product-picture] ${errorCount} error(s)`);
  process.exit(1);
}
console.log(JSON.stringify({
  ok: true,
  kind,
  programForm: form || null,
  screenSeconds,
  totalSeconds,
  screenRatio: totalSeconds > 0 ? Number((screenSeconds / totalSeconds).toFixed(3)) : null,
}));
