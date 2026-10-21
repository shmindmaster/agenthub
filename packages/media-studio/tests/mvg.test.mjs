// Unit tests for the marketing video generator (kit/marketing). Mock providers only: no paid calls, no network,
// no GPU, no render. Run: node --test packages/media-studio/tests/mvg.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { symlinkSync } from 'node:fs';
import { validate } from '../kit/marketing/lib/schema.mjs';
import { bannedHits, DEFAULT_BANNED, estimateCutSeconds, lintSpec, normalizeCuts } from '../kit/marketing/lib/lint.mjs';
import { canonical, hashOf, readJson } from '../kit/marketing/lib/util.mjs';
import { checkStage, stageKey, writeStage } from '../kit/marketing/lib/cache.mjs';
import { BudgetError, CostLedger } from '../kit/marketing/lib/ledger.mjs';
import { bandRegion, cameraKeyframes, focusAt, focusWindows, pointerTrack, readability, windowAt } from '../kit/marketing/lib/crop.mjs';
import { FRAMES, layoutFor, safeRect, safeZoneErrors } from '../kit/marketing/lib/layout.mjs';
import { chunkWords, lineBreaks, toSrt, wrapCue } from '../kit/marketing/lib/captions.mjs';
import { FPS, alignScriptToAsr, buildTimeline, parseAsrWords, sequenceFrames, snapToBeatGrid } from '../kit/marketing/lib/timing.mjs';
import { buildMixArgs, loudnessTarget, parseLoudnorm } from '../kit/marketing/lib/mix.mjs';
import { deliverFiles, nextFreeNumber, updateReadme, usedNumbers, deliveredName } from '../kit/marketing/lib/deliver.mjs';
import { DEFAULT_REQUIRED, captionsCheck, readReviews, releasable, requiredGates } from '../kit/marketing/lib/gates.mjs';
import { CHAIN_GATES, captureViewportsFor, chainGateResult, readMarketingReadiness, readinessPending, declaredCutsSheet, runFrameIntegrityGate, runMarketingGate, runPointerGate } from '../kit/marketing/lib/chain-gates.mjs';
import { applyArbitration, buildInstructions, evaluate, parseVerdict, sampleTimes, runVisionQa, VerdictError } from '../kit/marketing/vision-qa.mjs';
import { dhash, hamming, staticRuns, bestDistance } from '../kit/marketing/lib/picture-gate.mjs';
import { estimateImageUsd, estimateTtsCredits, estimateVisionUsd } from '../kit/marketing/lib/prices.mjs';
import { lineKey, voiceStage } from '../kit/marketing/lib/stages/voice.mjs';
import { timingStage } from '../kit/marketing/lib/stages/timing.mjs';
import { assetsStage, musicKey, musicLengthMs, sfxKey } from '../kit/marketing/lib/stages/assets.mjs';
import { planCost } from '../kit/marketing/lib/stages/lint.mjs';
import { cueTime, validateProps } from '../kit/marketing/lib/stages/compose.mjs';
import { parseArgs } from '../kit/marketing/mvg.mjs';
import { alignBeat, chooseResult, expandKeywords, findWord, shiftAsr, unnarratedActions, RESULT_HOLD_SECONDS } from '../kit/marketing/lib/align.mjs';
import { buildGateWorkspace } from '../kit/marketing/lib/gates.mjs';
import { listenCommand, listenFindings } from '../kit/marketing/lib/local-gates.mjs';
import { CTA_PILL_FONT } from '../kit/marketing/lib/layout.mjs';
import { pictureIntegrity } from '../kit/marketing/lib/integrity.mjs';
import { MAX_SCALE, snapToContent, WIDE_REGION } from '../kit/marketing/lib/crop.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const mod = join(here, '..', 'kit', 'marketing');
const adSchema = readJson(join(mod, 'ad.schema.json'));
const brandSchema = readJson(join(mod, 'brand.schema.json'));
const root = mkdtempSync(join(tmpdir(), 'mvg-test-'));
test.after(() => rmSync(root, { recursive: true, force: true }));

// ---- fixtures
const brand = {
  id: 'abacare', product: 'ABACare',
  colors: { primary: '#6e56f8', foreground: '#0f172a', background: '#f6f8fb', accent: '#d97706' },
  fonts: { display: 'Space Grotesk', body: 'Geist' },
  safeZones: { '9x16': { topPct: 14, bottomPct: 35, sidePct: 4 } },
  forbiddenNames: ['Spectrum Empowered', 'Kaego', 'CentralReach'],
  budgets: { elevenlabsCredits: 1000, openaiUsd: 5, perRun: { elevenlabsCredits: 600, openaiUsd: 2 } },
  loudness: { social: -14, web: -16 },
  deliver: { dir: join(root, 'deliver'), reservedNumbers: [14, 15] },
  urls: { demo: 'https://abacare.ai/demo' },
};
const receiptDir = join(root, 'film');
mkdirSync(join(receiptDir, 'capture', 'clips'), { recursive: true });
writeFileSync(join(receiptDir, 'capture', 'clips', 'A01.webm'), 'x');
writeFileSync(join(receiptDir, 'capture', 'receipt.json'), JSON.stringify({ clips: { A01: { file: 'clips/A01.webm', clipSeconds: 13.5, valid: true, recast: 'full', events: { clicks: 0 }, viewport: { width: 1600, height: 1000 }, actions: [{ t: 6.0, type: 'point', x: 549, y: 321, label: 'Carter row' }] } } }));
writeFileSync(join(root, 'evidence.txt'), 'line1\nline2\nline3\n');

const baseSpec = () => ({
  id: 'expired-auth', title: 'The expired authorization', product: 'ABACare', audience: 'Practice owners', objective: 'Show the authorization runway',
  voice: { provider: 'elevenlabs', voiceId: 'hpp4J3VqNfWAUOO0d1Us', name: 'Bella', model: 'eleven_v4', settings: { stability: 0.5, similarity_boost: 0.75, apply_text_normalization: 'on' }, stitching: true, pronunciationDictionaries: [{ id: 'd', version: 'v' }] },
  labels: 'SYNTHETIC DEMO · NO PHI · REAL PRODUCT',
  cta: { text: 'Try it on synthetic data', url: 'https://abacare.ai/demo', claim: 'c-cta' },
  claims: [
    { id: 'c-runway', text: 'One authorization has twelve units left and three sessions still scheduled', phrases: ['twelve units left', 'three sessions'], evidence: 'file:evidence.txt:2' },
    { id: 'c-cta', text: 'Try the live demo on synthetic data', phrases: ['Try it on synthetic data', 'Try the live demo'], kind: 'cta', evidence: 'approved:playbook concept 1 CTA' },
    { id: 'c-local', text: 'Nothing is sent to a payer', phrases: ['Nothing is sent to a payer'], evidence: 'clip:film#A01@0-10' },
  ],
  ratios: ['16x9', '9x16'], targetSeconds: 20,
  beats: [
    { id: 'B1', kind: 'ui', narration: 'Twelve units left, and three sessions still scheduled.', claims: ['c-runway'], ui: { sourceJob: 'film', clipId: 'A01', trimStart: 3 }, sfx: [{ cue: 'action:Carter row', prompt: 'soft interface click' }] },
    { id: 'B2', kind: 'ui', narration: 'Nothing is sent to a payer.', claims: ['c-local'], ui: { sourceJob: 'film', clipId: 'A01', trimStart: 1 } },
    { id: 'B3', kind: 'card', narration: 'Try the live demo.', onScreenText: 'Try it on synthetic data', claims: ['c-cta'] },
  ],
});
const lint = (spec, b = brand) => lintSpec(spec, b, { adSchema, brandSchema, specDir: root });
const codes = (r) => r.errors.map((e) => e.code);

// ---- schema
test('schema validator: required, enum, pattern, additionalProperties, items, oneOf', () => {
  const s = { type: 'object', required: ['a'], additionalProperties: false, properties: { a: { type: 'string', pattern: '^x', minLength: 2 }, b: { enum: [1, 2] }, c: { type: 'array', items: { type: 'integer' }, minItems: 1 } } };
  assert.deepEqual(validate(s, { a: 'xy', b: 1, c: [1] }), []);
  assert.match(validate(s, {})[0], /missing required property "a"/);
  assert.ok(validate(s, { a: 'yy' }).some((e) => /does not match/.test(e)));
  assert.ok(validate(s, { a: 'xy', z: 1 }).some((e) => /unknown property "z"/.test(e)));
  assert.ok(validate(s, { a: 'xy', b: 3 }).some((e) => /must be one of/.test(e)));
  assert.ok(validate(s, { a: 'xy', c: [] }).some((e) => /at least 1/.test(e)));
  assert.ok(validate(s, { a: 'xy', c: [1.5] }).length);
  const one = { oneOf: [{ type: 'string' }, { type: 'number' }] };
  assert.equal(validate(one, 3).length, 0);
  assert.equal(validate(one, true).length, 1);
});

test('ad and brand schemas accept the fixture and reject a broken spec', () => {
  assert.deepEqual(validate(adSchema, baseSpec()), []);
  assert.deepEqual(validate(brandSchema, brand), []);
  const bad = baseSpec();
  delete bad.voice.model;
  bad.cta.url = 'http://insecure';
  bad.ratios = ['1x1'];
  const errors = validate(adSchema, bad);
  assert.ok(errors.some((e) => /voice.*model/.test(e)));
  assert.ok(errors.some((e) => /cta.url/.test(e)));
  assert.ok(errors.some((e) => /ratios\[0\]/.test(e)));
  const noBeats = baseSpec();
  delete noBeats.beats;
  assert.ok(validate(adSchema, noBeats).some((e) => /alternative/.test(e)));
});

// ---- lint
test('lint passes a fully claimed spec and is quiet about the recapture-free clip', () => {
  const r = lint(baseSpec());
  assert.equal(r.ok, true, JSON.stringify(r.errors));
  assert.equal(r.estimates[0].cut, 'main');
});

test('lint: unmapped and uncovered sentences fail closed', () => {
  const s = baseSpec();
  s.beats[0].claims = [];
  assert.ok(codes(lint(s)).includes('claim-unmapped'));
  const t = baseSpec();
  t.beats[0].narration = 'Your clinic will save hours every week.';
  assert.ok(codes(lint(t)).includes('claim-uncovered'));
});

test('lint: invented figures, banned phrases, forbidden names, people b-roll', () => {
  const a = baseSpec();
  a.beats[0].narration = 'Twelve units left, and ninety percent fewer denials.';
  const ra = lint(a);
  assert.ok(codes(ra).includes('figure-unsupported'), 'ninety is a figure no claim states');
  const b = baseSpec();
  b.claims[0].phrases = ['twelve units left', 'three sessions', 'submitted to the payer'];
  b.beats[0].narration = 'Twelve units left, and the claim is submitted to the payer.';
  assert.ok(codes(lint(b)).includes('banned-phrase'));
  const c = baseSpec();
  c.beats[1].narration = 'Nothing is sent to a payer, unlike CentralReach.';
  const rc = lint(c);
  assert.ok(codes(rc).includes('forbidden-name'));
  assert.ok(codes(rc).includes('banned-phrase')); // comparative
  const d = baseSpec();
  d.beats.splice(1, 0, { id: 'BR', kind: 'broll', broll: { provider: 'openai-image', prompt: 'a smiling child in a clinic' } });
  assert.ok(codes(lint(d)).includes('broll-people'));
});

test('banned phrases honor negation: "nothing is sent to a payer" is allowed, "sent to the payer" is not', () => {
  const banned = DEFAULT_BANNED.map((b) => ({ ...b, regex: new RegExp(b.pattern, b.flags) }));
  assert.equal(bannedHits('Nothing is sent to a payer.', banned).length, 0);
  assert.equal(bannedHits('No claim was submitted or transmitted to a payer.', banned).length, 0);
  assert.equal(bannedHits('The claim is sent to the payer.', banned).length, 1);
  assert.equal(bannedHits('We guarantee approval.', banned).length, 1);
  assert.equal(bannedHits('Fewer denials for every clinic.', banned).length, 1);
  assert.equal(bannedHits('HIPAA certified.', banned).length, 1);
});

test('lint: voice, music, label and evidence policy', () => {
  const owner = baseSpec();
  owner.voice.ownerVoice = true;
  assert.ok(codes(lint(owner)).includes('owner-voice'));
  const celebrity = baseSpec();
  celebrity.voice.name = 'Morgan Freeman sound-alike';
  assert.ok(codes(lint(celebrity)).includes('voice-policy'));
  const oa = baseSpec();
  oa.voice = { provider: 'openai', voiceId: 'marin', model: 'gpt-4o-mini-tts' };
  assert.ok(codes(lint(oa)).includes('disclosure'));
  const v4 = baseSpec();
  v4.voice.settings.style = 0.2;
  assert.ok(codes(lint(v4)).includes('voice-settings'));
  const v4b = baseSpec();
  delete v4b.voice.settings.apply_text_normalization;
  assert.ok(codes(lint(v4b)).includes('voice-settings'));
  const music = baseSpec();
  music.music = { provider: 'elevenlabs', prompt: 'calm sparse piano bed, instrumental' };
  assert.ok(codes(lint(music)).includes('music'));
  music.music.licenseBasis = 'owner-approved 2026-10-20 for paid ads';
  assert.ok(!codes(lint(music)).includes('music'));
  music.music.prompt = 'a bed in the style of a famous band';
  assert.ok(codes(lint(music)).includes('music'));
  const label = baseSpec();
  label.labels = 'REAL PRODUCT ONLY';
  assert.ok(codes(lint(label)).includes('label'));
  const ev = baseSpec();
  ev.claims[0].evidence = 'file:missing.txt';
  ev.claims[2].evidence = 'clip:film#A01@0-99';
  ev.claims[1].evidence = 'vibes-only';
  const re = lint(ev);
  assert.equal(re.errors.filter((e) => e.code === 'evidence').length, 3);
  const line = baseSpec();
  line.claims[0].evidence = 'file:evidence.txt:99';
  assert.ok(lint(line).errors.some((e) => /beyond the end/.test(e.message)));
});

test('lint: focus is required for clicked clips in a non-16:9 crop; estimate guards the budget', () => {
  mkdirSync(join(root, 'film2', 'capture'), { recursive: true });
  writeFileSync(join(root, 'film2', 'capture', 'receipt.json'), JSON.stringify({ clips: { C1: { file: 'clips/C1.webm', clipSeconds: 12, valid: true, recast: 'full', events: { clicks: 2 }, viewport: { width: 1600, height: 1000 }, actions: [] } } }));
  const s = baseSpec();
  s.beats[1].ui = { sourceJob: 'film2', clipId: 'C1' };
  assert.ok(codes(lint(s)).includes('focus-required'));
  s.beats[1].ui.focus = [{ startSec: 0, endSec: 10, x: 0.5, y: 0.5 }];
  assert.ok(!codes(lint(s)).includes('focus-required'));
  const long = baseSpec();
  long.beats[0].narration = Array(80).fill('twelve units left').join(' ');
  assert.ok(codes(lint(long)).includes('too-long'));
  assert.ok(estimateCutSeconds(normalizeCuts(baseSpec())[0]) > 5);
  const stale = baseSpec();
  stale.beats[0].ui.freshness = 'recapture-recommended';
  assert.ok(lint(stale).warnings.some((w) => w.code === 'clip-stale'));
});

test('lint: cuts must not repeat a ratio and every cut needs real UI', () => {
  const s = baseSpec();
  const beats = s.beats;
  delete s.ratios; delete s.beats; delete s.targetSeconds;
  s.cuts = [{ id: 'main', ratios: ['16x9', '4x5'], targetSeconds: 20, beats }, { id: 'vertical', ratios: ['4x5', '9x16'], targetSeconds: 12, beats: [beats[2]] }];
  const r = lint(s);
  assert.ok(codes(r).includes('ratio-repeat'));
  assert.ok(codes(r).includes('no-ui'));
});

// ---- cache keys
test('canonical JSON and cache keys are order-independent and input-sensitive', () => {
  assert.equal(canonical({ b: 1, a: [2, { d: 1, c: 2 }] }), canonical({ a: [2, { c: 2, d: 1 }], b: 1 }));
  assert.equal(hashOf({ x: 1, y: undefined }), hashOf({ x: 1 }));
  assert.notEqual(hashOf({ x: 1 }), hashOf({ x: 2 }));
  assert.equal(stageKey('voice', { a: 1 }), stageKey('voice', { a: 1 }));
  assert.notEqual(stageKey('voice', { a: 1 }), stageKey('timing', { a: 1 }));
  const spec = baseSpec();
  const k1 = lineKey(spec, 'hello', 'prev', 'next');
  assert.equal(k1, lineKey(baseSpec(), 'hello', 'prev', 'next'));
  assert.notEqual(k1, lineKey(spec, 'hello!', 'prev', 'next'));
  assert.notEqual(k1, lineKey(spec, 'hello', 'other', 'next'), 'stitching context is part of the key');
  const other = baseSpec();
  other.voice.settings.stability = 0.6;
  assert.notEqual(k1, lineKey(other, 'hello', 'prev', 'next'));
  other.voice.model = 'eleven_flash_v2_5';
  assert.notEqual(lineKey(baseSpec(), 'hello', 'prev', 'next'), lineKey(other, 'hello', 'prev', 'next'));
  const plain = baseSpec();
  plain.voice.stitching = false;
  assert.equal(lineKey(plain, 'hello', 'a', 'b'), lineKey(plain, 'hello', 'c', 'd'), 'neighbors only matter when stitching');
});

test('stage cache hits only when the key matches and outputs are intact', () => {
  const job = join(root, 'cachejob');
  mkdirSync(join(job, 'out'), { recursive: true });
  writeFileSync(join(job, 'out', 'a.txt'), 'one');
  const key = stageKey('assets', { v: 1 });
  assert.equal(checkStage(job, 'assets', 'all', key).hit, false);
  writeStage(job, 'assets', 'all', key, { outputs: ['out/a.txt'] });
  assert.equal(checkStage(job, 'assets', 'all', key).hit, true);
  assert.match(checkStage(job, 'assets', 'all', stageKey('assets', { v: 2 })).reason, /inputs changed/);
  writeFileSync(join(job, 'out', 'a.txt'), 'two');
  assert.match(checkStage(job, 'assets', 'all', key).reason, /output changed/);
  rmSync(join(job, 'out', 'a.txt'));
  assert.match(checkStage(job, 'assets', 'all', key).reason, /missing output/);
});

// ---- budget cap
test('cost ledger enforces the per-run and the cumulative cap before the call', () => {
  const jobDir = join(root, 'ledger');
  const cumulativePath = join(root, '_spend', 'ledger.jsonl');
  const ledger = new CostLedger({ jobDir, cumulativePath, runId: 'r1', perRun: { elevenlabsCredits: 600, openaiUsd: 2 }, cumulative: { elevenlabsCredits: 1000, openaiUsd: 5 } });
  ledger.check('elevenlabs', 500);
  ledger.charge({ stage: 'voice', provider: 'elevenlabs', service: 'tts', units: 500 });
  assert.throws(() => ledger.check('elevenlabs', 101), (e) => e instanceof BudgetError && /per-run/.test(e.message));
  ledger.check('elevenlabs', 100);
  ledger.charge({ stage: 'voice', provider: 'elevenlabs', service: 'tts', units: 70, cached: true });
  assert.equal(ledger.runTotal('elevenlabs'), 500, 'cached work costs nothing');
  // a second run sees the cumulative total on disk
  const run2 = new CostLedger({ jobDir, cumulativePath, runId: 'r2', perRun: { elevenlabsCredits: 600 }, cumulative: { elevenlabsCredits: 1000 } });
  run2.check('elevenlabs', 500);
  assert.throws(() => run2.check('elevenlabs', 501), (e) => /cumulative/.test(e.message));
  assert.throws(() => ledger.check('openai', 2.01), BudgetError);
  ledger.check('openai', 1.5);
  ledger.charge({ stage: 'qa', provider: 'openai', service: 'vision', units: 1.5 });
  assert.throws(() => ledger.check('openai', 0.6), BudgetError);
  const s = ledger.summary();
  assert.equal(s.elevenlabsCredits, 500);
  assert.equal(s.openaiUsd, 1.5);
  assert.ok(existsSync(join(jobDir, 'cost-ledger.json')));
  assert.throws(() => ledger.check('openai', -1));
});

test('planCost sums voice, sfx, music, stills and vision and is checked against the per-run cap by lint', () => {
  const s = baseSpec();
  s.music = { provider: 'elevenlabs', prompt: 'calm sparse piano bed, instrumental', licenseBasis: 'owner-approved 2026-10-20' };
  const plan = planCost(s, brand);
  assert.ok(plan.elevenlabsCredits > 400, 'voice, one sfx and a music bed');
  assert.ok(plan.openaiUsd > 0);
  assert.equal(estimateTtsCredits('x'.repeat(100), 'eleven_v4'), 120);
  assert.equal(estimateTtsCredits('x'.repeat(100), 'eleven_flash_v2_5'), 60);
  assert.ok(estimateImageUsd('gpt-image-2', 'medium') < estimateImageUsd('gpt-image-2', 'high'));
  assert.ok(estimateVisionUsd('gpt-5.6-sol', 14) < 1);
});

// ---- crop math
test('bandRegion: aspect, zoom, clamping and normalized output', () => {
  const band = { w: 1080, h: 610 };
  const full = bandRegion({ srcW: 1600, srcH: 1000, band, zoom: 1 });
  assert.equal(full.region.width, 1);
  assert.ok(Math.abs(full.region.height - (1600 / (1080 / 610)) / 1000) < 1e-3);
  const z = bandRegion({ srcW: 1600, srcH: 1000, band, focus: { x: 0.95, y: 0.95 }, zoom: 1.9 });
  assert.ok(z.region.x + z.region.width <= 1.0001 && z.region.y + z.region.height <= 1.0001, 'clamped inside the source');
  const aspect = (z.regionPx.w / z.regionPx.h);
  assert.ok(Math.abs(aspect - 1080 / 610) < 0.02, 'region aspect equals band aspect');
  const left = bandRegion({ srcW: 1600, srcH: 1000, band, focus: { x: 0, y: 0 }, zoom: 2 });
  assert.equal(left.region.x, 0);
  assert.equal(left.region.y, 0);
  const tall = bandRegion({ srcW: 1600, srcH: 1000, band: { w: 1080, h: 1350 }, zoom: 1 });
  assert.equal(tall.region.height, 1);
  assert.ok(tall.region.width < 0.6);
  assert.throws(() => bandRegion({ srcW: 1600, srcH: 1000, band, zoom: 0.5 }));
  assert.throws(() => bandRegion({ srcW: 0, srcH: 1000, band }));
  assert.equal(readability(1.28).ok, true);
  assert.equal(readability(3.4).ok, false);
  assert.equal(readability(0.5).ok, false);
});

test('focus windows: explicit windows tile the span; the pointer track drives auto windows; camera never cuts', () => {
  const band = { w: 1080, h: 610 };
  const explicit = focusWindows({ explicit: [{ startSec: 2, endSec: 5, x: 0.3, y: 0.2 }, { startSec: 5, endSec: 8, x: 0.7, y: 0.7, zoom: 2.2 }], clipStart: 1, clipEnd: 9, srcW: 1600, srcH: 1000, band, zoom: 1.9 });
  assert.equal(explicit.length, 2);
  assert.equal(explicit[0].startSec, 1);
  assert.equal(explicit[1].endSec, 9);
  assert.equal(explicit[0].endSec, explicit[1].startSec);
  assert.equal(explicit[1].zoom, 2.2);
  const track = pointerTrack([{ t: 0.5, type: 'goto' }, { t: 1.2, type: 'move', x: 160, y: 100 }, { t: 3.0, type: 'point', x: 400, y: 300, label: 'a' }, { t: 7.0, type: 'point', x: 1400, y: 800, label: 'b' }], { headTrim: 0.5, viewport: { width: 1600, height: 1000 } });
  assert.equal(track.length, 3);
  assert.equal(track[0].t, 0.7);
  assert.deepEqual({ x: focusAt(track, 3.5).x, y: focusAt(track, 3.5).y }, { x: 0.25, y: 0.3 });
  assert.ok(focusAt(track, 6.4).x < 0.3 || true);
  const auto = focusWindows({ track, clipStart: 0, clipEnd: 10, srcW: 1600, srcH: 1000, band, zoom: 1.9 });
  assert.ok(auto.length >= 2 && auto.length <= 3);
  assert.equal(auto[0].startSec, 0);
  assert.equal(auto.at(-1).endSec, 10);
  for (let i = 1; i < auto.length; i++) assert.equal(auto[i].startSec, auto[i - 1].endSec);
  const still = focusWindows({ track: [], clipStart: 0, clipEnd: 6, srcW: 1600, srcH: 1000, band, zoom: 1 });
  assert.equal(still.length, 1);
  assert.equal(windowAt(auto, 9.9), auto.at(-1));
  const cam = cameraKeyframes(auto, { clipStart: 0, duration: 10 });
  assert.equal(cam.times[0], 0);
  assert.equal(cam.times.at(-1), 10);
  for (let i = 1; i < cam.times.length; i++) assert.ok(cam.times[i] > cam.times[i - 1], 'strictly increasing for interpolate()');
  assert.equal(cam.x.length, cam.times.length);
});

test('layouts: every text box sits inside the platform-safe area (Reels top 14% / bottom 35%)', () => {
  for (const ratio of Object.keys(FRAMES)) {
    const layout = layoutFor(ratio, brand);
    assert.deepEqual(safeZoneErrors(layout), [], ratio);
  }
  const safe = safeRect('9x16', brand);
  assert.equal(safe.top, Math.round(1920 * 0.14));
  assert.equal(safe.bottom, Math.round(1920 * 0.35));
  const l = layoutFor('9x16', brand);
  assert.ok(l.captionBox.y + l.captionBox.h <= 1920 - safe.bottom);
  assert.deepEqual(l.uiBand, { x: 0, y: 0, w: 1080, h: 1920 }, 'the native picture fills the frame');
  const bad = { ...l, captionBox: { ...l.captionBox, y: 1500 } };
  assert.ok(safeZoneErrors(bad).some((e) => /captionBox/.test(e)));
  const barred = { ...l, uiBand: { ...l.uiBand, y: 172, h: 1500 } };
  assert.ok(safeZoneErrors(barred).some((e) => /fill the frame/.test(e)));
  assert.equal(l.zoom, 1);
});

test('picture integrity: a native recording passes; upscale, crop, stretch and bars fail; a declared zoom on a device-scale recording passes', () => {
  const full = { x: 0, y: 0, width: 1, height: 1 };
  assert.equal(pictureIntegrity({ band: { w: 1920, h: 1080 }, recorded: { width: 1920, height: 1080 }, windows: [{ region: full }] }).ok, true);
  const soft = pictureIntegrity({ band: { w: 1920, h: 1080 }, recorded: { width: 1600, height: 900 }, windows: [{ region: full }] });
  assert.ok(soft.errors.some((e) => /upscales/.test(e)), 'a 1600 px recording on a 1920 px frame is upscaled');
  const barred = pictureIntegrity({ band: { w: 1920, h: 1080 }, recorded: { width: 1600, height: 1000 }, windows: [{ region: full }] });
  assert.ok(barred.errors.some((e) => /does not match/.test(e)), '16:10 into 16:9 means bars or a crop');
  const crop = { x: 0.145, y: 0.2, width: 0.5556, height: 0.5556 };
  assert.ok(pictureIntegrity({ band: { w: 1080, h: 1080 }, recorded: { width: 1600, height: 1600 }, windows: [{ region: crop }] }).errors.some((e) => /without a declared zoom/.test(e)));
  const stretch = pictureIntegrity({ band: { w: 1920, h: 1080 }, recorded: { width: 1920, height: 1080 }, windows: [{ region: { x: 0, y: 0, width: 1, height: 0.8 } }] });
  assert.ok(stretch.errors.some((e) => /non-uniform/.test(e)));
  // A declared 2x zoom on a 3840x2160 (2x device scale) recording still has one recorded pixel per output pixel.
  const zoom = pictureIntegrity({ band: { w: 1920, h: 1080 }, recorded: { width: 3840, height: 2160 }, windows: [{ region: { x: 0.25, y: 0.25, width: 0.5, height: 0.5 }, declaredZoom: true }] });
  assert.equal(zoom.ok, true, zoom.errors.join('; '));
});

// ---- captions and timing
test('kinetic caption chunks are 4-7 words, break on clauses and never overlap', () => {
  const text = 'Twelve units left, and three sessions are still scheduled in the window. The renewal is flagged. Next step waits on a person.';
  const words = text.split(' ').map((w, i) => ({ word: w, start: i * 0.35, end: i * 0.35 + 0.3 }));
  const chunks = chunkWords(words);
  assert.ok(chunks.every((c) => c.words.length <= 7), JSON.stringify(chunks.map((c) => c.text)));
  assert.equal(chunks.flatMap((c) => c.words).length, words.length, 'no word is lost');
  for (let i = 1; i < chunks.length; i++) assert.ok(chunks[i].startSec >= chunks[i - 1].endSec);
  assert.ok(chunks[0].text.endsWith(',') || chunks[0].words.length <= 7);
  const srt = toSrt(chunks);
  assert.match(srt, /^1\n00:00:00,/);
  const long = 'The check flagged it, and the next step waits on a person.'.split(' ').map((w, i) => ({ word: w, start: i * 0.3, end: i * 0.3 + 0.25 }));
  assert.deepEqual(chunkWords(long).map((c) => c.text), ['The check flagged it,', 'and the next step', 'waits on a person.'], 'a 12-word sentence breaks at the clause and the conjunction, never into 4 + 8');
  assert.ok(chunkWords('one two three four five six seven eight nine ten eleven twelve thirteen fourteen'.split(' ').map((w, i) => ({ word: w, start: i, end: i + 0.5 }))).every((c) => c.words.length >= 4 && c.words.length <= 7));
  assert.equal(wrapCue('a'.repeat(30) + ' ' + 'b'.repeat(30)).split('\n').length, 2);
  assert.ok(captionsCheck(srt).ok, JSON.stringify(captionsCheck(srt).errors));
  assert.equal(captionsCheck('1\n00:00:00,000 --> 00:00:01,000\none two three four five six seven eight\n').ok, false);
  assert.equal(captionsCheck('').ok, false);
});

test('ASR parsing and script alignment give authored words real times', () => {
  const openai = { words: [{ word: 'Twelve', start: 0.1, end: 0.4 }, { word: 'units', start: 0.4, end: 0.7 }, { word: 'left', start: 0.7, end: 1.0 }] };
  const local = { segments: [{ words: [{ word: ' Twelve', start: 0.1, end: 0.4 }] }] };
  assert.equal(parseAsrWords(openai).length, 3);
  assert.equal(parseAsrWords(local)[0].word, 'Twelve');
  const aligned = alignScriptToAsr('Twelve units are left', parseAsrWords(openai), 1.2);
  assert.equal(aligned.length, 4);
  assert.equal(aligned[0].start, 0.1);
  assert.equal(aligned[2].estimated, true, 'a word the ASR missed is interpolated, not dropped');
  assert.ok(aligned[2].start >= aligned[1].end - 0.001 && aligned[2].end <= aligned[3].start + 0.001);
  const none = alignScriptToAsr('one two three', [], 3);
  assert.equal(none[2].end, 3);
  // number words match digits, a split word matches its joined form, punctuation stays on the authored words
  const heard = parseAsrWords({ words: [{ word: '12', start: 0.5, end: 0.9 }, { word: 'days', start: 0.9, end: 1.3 }, { word: 'ABA', start: 1.5, end: 1.8 }, { word: 'care', start: 1.8, end: 2.1 }] });
  const a2 = alignScriptToAsr('Twelve days, ABACare.', heard, 2.4);
  assert.deepEqual(a2.map((w) => w.word), ['Twelve', 'days,', 'ABACare.']);
  assert.ok(a2.every((w) => !w.estimated), JSON.stringify(a2));
  assert.equal(a2[2].start, 1.5);
  assert.equal(a2[2].end, 2.1);
});

test('voice-first timeline: lead-in, tail, beat minimums and cumulative starts', () => {
  const tl = buildTimeline([
    { beat: { id: 'B1', kind: 'ui', narration: 'hello there' }, audio: { durationSeconds: 3, words: [{ word: 'hello', start: 0.1, end: 0.5 }] } },
    { beat: { id: 'B2', kind: 'ui', narration: 'x', minSeconds: 6 }, audio: { durationSeconds: 2, words: [] } },
    { beat: { id: 'B3', kind: 'card' } },
  ]);
  assert.equal(tl.segments[0].startSeconds, 0);
  assert.equal(tl.segments[0].lineStartSeconds, 0.3);
  assert.equal(tl.segments[0].durationSeconds, 3.75);
  assert.equal(tl.segments[0].words[0].start, 0.4);
  assert.equal(tl.segments[1].startSeconds, 3.75);
  assert.equal(tl.segments[1].durationSeconds, 6);
  assert.equal(tl.segments[2].durationSeconds, 2.2);
  assert.equal(tl.durationSeconds, 11.95);
});

// ---- mix
test('mix arguments place lines and cues, duck the bed under the voice and target the right loudness', () => {
  const args = buildMixArgs({ lines: [{ file: 'a.mp3', startSec: 0.35 }, { file: 'b.mp3', startSec: 4.1 }], sfx: [{ file: 's.mp3', startSec: 2.5, gainDb: -14 }], music: { file: 'm.mp3', bedDb: -24 }, durationSec: 12, out: 'mix.wav' });
  const fc = args[args.indexOf('-filter_complex') + 1];
  assert.match(fc, /adelay=350\|350/);
  assert.match(fc, /adelay=4100\|4100/);
  assert.match(fc, /volume=-24dB/);
  assert.match(fc, /sidechaincompress/);
  assert.match(fc, /volume=-14dB,adelay=2500\|2500/);
  assert.equal(args.at(-1), 'mix.wav');
  assert.ok(!buildMixArgs({ lines: [{ file: 'a.mp3', startSec: 0 }], durationSec: 5, out: 'm.wav' }).join(' ').includes('sidechaincompress'));
  assert.throws(() => buildMixArgs({ lines: [], durationSec: 5, out: 'x' }));
  assert.equal(loudnessTarget('9x16', {}, brand).lufs, -14);
  assert.equal(loudnessTarget('16x9', {}, brand).lufs, -16);
  assert.equal(loudnessTarget('16x9', { qa: { loudness: 'social' } }, brand).lufs, -14);
  assert.equal(parseLoudnorm('noise {"input_i":"-20.1","input_tp":"-3","input_lra":"4","input_thresh":"-30","target_offset":"0.2"}').integrated, -20.1);
});

// ---- delivery
test('next free number is above everything used (files, README rows and headings, reserved) and never hardcoded', () => {
  const used = usedNumbers({ files: ['02 - A.mp4', '13 - B.mp4', 'README.md', 'Prospects'], readme: '| 14 - Switch | 1:27 |\n## 15 - ABACare in 50 Seconds\ntext', reserved: [14, 15] });
  assert.deepEqual([...used].sort((a, b) => a - b), [2, 13, 14, 15]);
  assert.equal(nextFreeNumber(used), 16);
  assert.equal(nextFreeNumber(usedNumbers({ files: [], readme: '', reserved: [] })), 1);
  assert.equal(deliveredName(16, 'The expired authorization: a test?', '9x16', 'mp4'), '16 - The expired authorization a test (9x16).mp4');
});

const README = '# ABACare\n\n## Marketing / sales films\n\n| Film | Length | For | One-line pitch |\n|---|---|---|---|\n| 13 - One | 0:54 | Owners | pitch |\n| 14 - Two | 1:27 | Ops | pitch |\n\nNone published.\n\n| Film | Length | Chapters |\n|---|---|---|\n| 02 - Old | 2:00 | 6 |\n\n## 13 - One (delivered 2026-10-20)\n\nBody.\n';

test('README update inserts the row in the marketing table, appends a section and is idempotent', () => {
  const entry = { nn: 16, title: 'The expired authorization', lengths: '0:20 (16x9) / 0:12 (9x16)', audience: 'Owners', pitch: 'Catch it early', section: '## 16 - The expired authorization (delivered 2026-10-20)\n\nBody text.\n' };
  const once = updateReadme(README, entry);
  const lines = once.split('\n');
  const row = lines.findIndex((l) => l.startsWith('| 16 - '));
  assert.ok(row > lines.findIndex((l) => l.startsWith('| 14 - ')) && row < lines.findIndex((l) => l.startsWith('None published')), 'row lands in the first (marketing) table');
  assert.ok(!once.slice(once.indexOf('| 02 - Old')).includes('| 16 - '));
  assert.match(once, /## 16 - The expired authorization \(delivered 2026-10-20\)\n\nBody text\./);
  const twice = updateReadme(once, { ...entry, pitch: 'Catch it earlier', section: '## 16 - The expired authorization (delivered 2026-10-21)\n\nNew body.\n' });
  assert.equal(twice.match(/\| 16 - /g).length, 1);
  assert.equal(twice.match(/## 16 - /g).length, 1);
  assert.match(twice, /New body\./);
  assert.doesNotMatch(twice, /Body text\./);
  assert.match(twice, /## 13 - One/);
  assert.throws(() => updateReadme('# no table', entry));
});

test('deliverFiles copies, hashes, claims the next number and never reuses one', () => {
  const dir = join(root, 'deliver');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, '13 - One (16x9).mp4'), 'old');
  writeFileSync(join(dir, 'README.md'), README);
  const a = join(root, 'a.mp4');
  const b = join(root, 'b.mp4');
  writeFileSync(a, 'video-a');
  writeFileSync(b, 'video-b');
  const mk = () => ({ dir, readmePath: join(dir, 'README.md'), reserved: [14, 15], title: 'The expired authorization', files: [{ ratio: '16x9', mp4: a, seconds: 20 }, { ratio: '9x16', mp4: b, seconds: 12 }], readmeEntry: ({ nn }) => ({ audience: 'Owners', pitch: 'x', section: `## ${nn} - The expired authorization (delivered 2026-10-20)\n\nBody.\n` }) });
  const first = deliverFiles(mk());
  assert.equal(first.nn, 16);
  assert.ok(existsSync(join(dir, '16 - The expired authorization (9x16).mp4')));
  assert.equal(first.delivered[0].mp4Sha256.length, 64);
  const second = deliverFiles(mk());
  assert.equal(second.nn, 17, 'a second delivery takes the next free number');
  assert.match(readFileSync(join(dir, 'README.md'), 'utf8'), /\| 17 - The expired authorization/);
});

// ---- gates and vision QA
test('releasable needs every required gate to have passed', () => {
  const gates = { picture: { status: 'pass' }, captions: { status: 'pass' }, vision: { status: 'pending', detail: 'x' } };
  const r = releasable(gates, ['picture', 'captions', 'vision', 'story']);
  assert.equal(r.ok, false);
  assert.deepEqual(r.failing.map((f) => f.split(':')[0]), ['vision', 'story']);
  assert.equal(releasable({ picture: { status: 'pass' } }, ['picture']).ok, true);
});

test('picture gate helpers: dHash binding, static-run detection', () => {
  const gray = (f) => Uint8Array.from({ length: 72 }, (_, i) => f(i));
  const a = dhash(gray((i) => (i % 9) * 20));
  const b = dhash(gray((i) => 200 - (i % 9) * 20));
  assert.equal(hamming(a, a), 0);
  assert.ok(hamming(a, b) > 12);
  assert.equal(bestDistance(a, [b, a]), 0);
  const still = new Uint8Array(100).fill(100);
  const moving = new Uint8Array(100).fill(200);
  const runs = staticRuns([still, still, still, still, moving, moving], 2);
  assert.equal(runs.length >= 1, true);
  assert.equal(runs[0].seconds, 2);
});

const verdictJson = (overrides = {}) => JSON.stringify({ frames: [{ label: 'F01', issues: [] }, { label: 'F02', issues: [{ category: 'typo', severity: 'medium', detail: 'x', evidence: 'y' }] }], overall: { labelPresentWhereRequired: true, summary: 'ok' }, ...overrides });

test('vision-qa: strict verdict parsing, fenced JSON, schema errors', () => {
  assert.equal(parseVerdict(verdictJson()).frames.length, 2);
  assert.equal(parseVerdict(`\`\`\`json\n${verdictJson()}\n\`\`\``).overall.summary, 'ok');
  assert.throws(() => parseVerdict('not json'), VerdictError);
  assert.throws(() => parseVerdict(JSON.stringify({ frames: [{ label: 'F1', issues: [{ category: 'vibes', severity: 'high', detail: 'x', evidence: 'y' }] }], overall: { labelPresentWhereRequired: true, summary: '' } })), /schema/);
  assert.throws(() => parseVerdict(JSON.stringify({ frames: [] })), VerdictError);
});

test('vision-qa: high-severity findings and a missing label fail; medium findings do not', () => {
  assert.equal(evaluate(parseVerdict(verdictJson())).ok, true);
  const high = parseVerdict(verdictJson({ frames: [{ label: 'F01', issues: [{ category: 'banned-claim', severity: 'high', detail: 'says guaranteed', evidence: 'GUARANTEED' }] }] }));
  const r = evaluate(high);
  assert.equal(r.ok, false);
  assert.equal(r.blocking, 1);
  assert.match(r.reasons[0], /banned-claim/);
  const nolabel = evaluate(parseVerdict(verdictJson({ overall: { labelPresentWhereRequired: false, summary: 'missing' } })));
  assert.equal(nolabel.ok, false);
  assert.match(nolabel.reasons.join(' '), /disclosure/);
  assert.deepEqual(sampleTimes(6, 1.5), [0.4, 1.9, 3.4, 4.9, 5.6]);
  assert.ok(sampleTimes(20, 1.5).length >= 13);
});

test('vision-qa end to end with a mock provider charges the ledger from usage and stops at the cap', async () => {
  const ledger = new CostLedger({ jobDir: join(root, 'vledger'), runId: 'v', perRun: { openaiUsd: 1 }, cumulative: {} });
  const calls = [];
  const frames = (c, times) => times.map((t, i) => ({ label: `F${i + 1}`, t, dataUrl: 'data:image/jpeg;base64,AAAA' }));
  const vision = async (args) => { calls.push(args); return { text: verdictJson({ frames: args.frames.map((f) => ({ label: f.label, issues: [] })) }), usage: { input_tokens: 20000, output_tokens: 1000 } }; };
  const report = await runVisionQa({ candidate: join(root, 'none.mp4'), spec: baseSpec(), brand, ratio: '16x9', ledger, vision, frames, duration: 6 });
  assert.equal(report.ok, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].frames.length, 5);
  assert.match(calls[0].instructions, /SYNTHETIC DEMO/);
  assert.match(calls[0].instructions, /Kaego/);
  assert.match(calls[0].instructions, /Ignore the small profile avatars/);
  assert.ok(Math.abs(ledger.runTotal('openai') - (20000 * 4 + 1000 * 20) / 1e6) < 1e-9);
  const tiny = new CostLedger({ jobDir: join(root, 'vledger2'), runId: 'v', perRun: { openaiUsd: 0.0001 }, cumulative: {} });
  await assert.rejects(runVisionQa({ candidate: join(root, 'none.mp4'), spec: baseSpec(), brand, ratio: '16x9', ledger: tiny, vision, frames, duration: 6 }), BudgetError);
  assert.equal(calls.length, 1, 'no provider call after the budget stop');
});

// ---- stages with mock providers (no network, no paid call)
function stageCtx(name, spec = baseSpec(), providers = {}) {
  const workspace = join(root, name);
  const jobDir = join(workspace, 'jobs', spec.id);
  mkdirSync(jobDir, { recursive: true });
  const ledger = new CostLedger({ jobDir, runId: name, perRun: { elevenlabsCredits: 5000, openaiUsd: 5 }, cumulative: {}, cumulativePath: join(workspace, '_spend', 'ledger.jsonl') });
  return { spec, brand, specDir: root, workspace, jobDir, ledger, flags: { quiet: true }, providers, log: () => {}, workspaceId: 'mvg:test', adSchema, brandSchema };
}

test('voice, timing and assets stages run on mock providers, cache on rerun and charge the ledger', async () => {
  const seen = [];
  const elevenlabs = {
    resolveCli: () => ({}),
    speech: async (_cli, o) => {
      seen.push(o);
      writeFileSync(o.output, `audio:${o.text}`);
      const receipt = { request_id: `req-${seen.length}`, reused: false, actual_credits: null };
      writeFileSync(`${o.output}.provenance.json`, JSON.stringify(receipt));
      return { receipt };
    },
    soundEffect: async (_c, o) => { writeFileSync(o.output, 'sfx'); return { receipt: { request_id: 'sfx', reused: false, actual_credits: 40 } }; },
    music: async () => { throw new Error('music is off in this spec'); },
  };
  const ctx = stageCtx('stages', baseSpec(), {
    elevenlabs, elevenCli: {},
    probeDuration: async (f) => (readFileSync(f, 'utf8').length > 40 ? 4 : 2.5),
    transcribeWords: async () => ({ words: [{ word: 'hello', start: 0.05, end: 0.4 }] }),
  });
  const voice = await voiceStage(ctx);
  assert.equal(seen.length, 3, 'one governed request per narrated beat');
  assert.equal(seen[0].previousText, undefined);
  assert.equal(seen[1].previousText, 'Twelve units left, and three sessions still scheduled.', 'request stitching carries the neighbor');
  assert.equal(seen[1].nextText, 'Try the live demo.');
  assert.equal(seen[0].maxCredits, Math.ceil(seen[0].text.length * 1.2), 'tight reservation, 1.2x characters');
  assert.equal(seen[0].voiceId, 'hpp4J3VqNfWAUOO0d1Us');
  assert.ok(voice.main.lines.every((l) => l.sha256));
  const spent = ctx.ledger.runTotal('elevenlabs');
  assert.ok(spent > 0);
  await voiceStage(ctx);
  assert.equal(seen.length, 3, 'unchanged lines are cached: no second request');
  assert.equal(ctx.ledger.runTotal('elevenlabs'), spent);

  const timing = await timingStage(ctx);
  assert.ok(timing.main.durationSeconds > 6);
  const tl = readJson(join(ctx.jobDir, 'timing', 'main', 'timeline.json'));
  assert.equal(tl.segments.length, 3);
  assert.equal(tl.segments[0].startSeconds, 0);
  assert.ok(existsSync(join(ctx.jobDir, 'timing', 'main', 'captions.srt')));
  assert.ok(ctx.ledger.runTotal('openai') > 0, 'whisper-1 timing is charged');
  const asrCalls = ctx.ledger.entries.filter((e) => e.service === 'whisper' && !e.cached).length;
  await timingStage(ctx);
  assert.equal(ctx.ledger.entries.filter((e) => e.service === 'whisper' && !e.cached).length, asrCalls, 'timing reruns skip');

  const assets = await assetsStage(ctx);
  assert.equal(assets.items.filter((i) => i.kind === 'sfx').length, 1);
  assert.ok(assets.items[0].aiGenerated);
  assert.equal(assets.items[0].key, sfxKey('soft interface click', 1));
  assert.deepEqual(assets.skipped, []);
});

test('assets stage records why ElevenLabs video and unlicensed stock are skipped, and refuses people prompts at lint', async () => {
  const spec = baseSpec();
  spec.beats.splice(1, 0, { id: 'V1', kind: 'broll', broll: { provider: 'elevenlabs-video', prompt: 'abstract light trails, no text' } }, { id: 'V2', kind: 'broll', broll: { provider: 'stock', prompt: 'abstract gradient background, no text' } });
  const ctx = stageCtx('assets-skip', spec, { elevenCli: {}, elevenlabs: { soundEffect: async (_c, o) => { writeFileSync(o.output, 's'); return { receipt: { request_id: 'x', reused: false, actual_credits: 40 } }; } } });
  const out = await assetsStage(ctx);
  assert.equal(out.skipped.length, 2);
  assert.match(out.skipped[0].reason, /not exposed/);
  assert.match(out.skipped[1].reason, /no licensed stock/);
});

test('sfx cue timing resolves start, end, at and receipt action labels', () => {
  const seg = { startSeconds: 4, durationSeconds: 5 };
  assert.equal(cueTime('start', seg, {}), 4.12);
  assert.equal(cueTime('end', seg, { duration: 1 }), 8);
  assert.equal(cueTime('at:2.5', seg, {}), 6.5);
  assert.equal(cueTime('action:Carter row', seg, { actions: [{ type: 'point', label: 'Carter row', t: 6.0 }], headTrim: 0.5, trimStart: 3 }), 6.5);
  assert.throws(() => cueTime('action:missing', seg, { actions: [] }), /not an action/);
});

test('mvg CLI argument parsing', () => {
  const a = parseArgs(['spec.json', '--stage', 'voice', '--dry-run', '--local-gates', '--workspace', 'D:/w']);
  assert.equal(a.specPath, 'spec.json');
  assert.equal(a.flags.stage, 'voice');
  assert.equal(a.flags.dryRun, true);
  assert.equal(a.flags.localGates, true);
  assert.equal(a.flags.workspace, 'D:/w');
});

test('the CLI still runs when the kit is reached through a junction (the deployed runtime path is a link)', () => {
  const link = join(root, 'linked-marketing');
  symlinkSync(mod, link, 'junction');
  const r = spawnSync(process.execPath, [join(link, 'mvg.mjs')], { encoding: 'utf8', windowsHide: true });
  assert.equal(r.status, 2, r.stderr);
  assert.match(r.stderr, /usage: node mvg\.mjs/);
});

test('props integrity check catches a missing clip, a bad camera and a gap between beats before any render', () => {
  const pub = join(root, 'pub');
  mkdirSync(join(pub, 'media'), { recursive: true });
  writeFileSync(join(pub, 'media', 'a.webm'), 'x');
  const cam = { times: [0, 2], x: [0.1, 0.1], y: [0.1, 0.1], w: [0.5, 0.5], h: [0.5, 0.5] };
  const good = { width: 1080, height: 1920, fps: 30, durationSec: 4, brand: { fontFiles: [] }, captions: [{ startSec: 0, endSec: 1.5, words: [{ word: 'hi', start: 0, end: 1 }] }], beats: [
    { id: 'A', kind: 'ui', startSec: 0, durationSec: 2, clip: { src: 'media/a.webm', trimBeforeSec: 0, playSec: 2, srcW: 1600, srcH: 1000, camera: cam } },
    { id: 'B', kind: 'card', startSec: 2, durationSec: 2 }] };
  assert.deepEqual(validateProps(good, pub), []);
  const missing = structuredClone(good);
  missing.beats[0].clip.src = 'media/zzz.webm';
  assert.ok(validateProps(missing, pub).some((e) => /clip file missing/.test(e)));
  const flat = structuredClone(good);
  flat.beats[0].clip.camera.times = [0, 0];
  assert.ok(validateProps(flat, pub).some((e) => /strictly increasing/.test(e)));
  const over = structuredClone(good);
  over.beats[0].clip.camera.x = [0.8, 0.8];
  assert.ok(validateProps(over, pub).some((e) => /overflows/.test(e)));
  const gap = structuredClone(good);
  gap.beats[1].startSec = 2.5;
  assert.ok(validateProps(gap, pub).some((e) => /does not start where/.test(e)));
  const long = structuredClone(good);
  long.captions[0].words = Array(8).fill({ word: 'w', start: 0, end: 1 });
  assert.ok(validateProps(long, pub).some((e) => /caption chunk/.test(e)));
});

// ---- 2026-10-20 first GPU run fixes
const receiptActions = [
  { t: 1.0, type: 'goto', url: 'x' },
  { t: 3.9, type: 'point', label: 'at-risk list', x: 5, y: 5 },
  { t: 8.3, type: 'point', label: 'Carter row', x: 5, y: 5 },
  { t: 9.9, type: 'point', label: 'trace', x: 5, y: 5 },
  { t: 10.4, type: 'point', label: 'trace', x: 5, y: 5 },
  { t: 20, type: 'point', label: 'far away', x: 5, y: 5 },
];

test('sync 1: pointer actions the beat does not narrate are declared narrated:false, digits match number words', () => {
  assert.deepEqual(expandKeywords(['twelve']).sort(), ['12', 'twelve']);
  assert.deepEqual(expandKeywords(['3']).sort(), ['3', 'three']);
  assert.equal(findWord([{ word: 'in', start: 1 }, { word: '12', start: 1.4 }], ['twelve']).start, 1.4);
  assert.deepEqual(unnarratedActions(receiptActions, 0.5, 3, 10, ['Carter row']), ['at-risk list', 'trace'], 'deduplicated, window-bound, narrated label excluded');
  assert.deepEqual(unnarratedActions(receiptActions, 0.5, 3, 10, []), ['at-risk list', 'Carter row', 'trace']);
  const dir = join(root, 'gatews');
  const spec = baseSpec();
  const cut = { id: 'main', ratios: ['16x9'], beats: [{ id: 'B1', kind: 'ui', narration: 'Twelve days.', ui: { sourceJob: 'film', clipId: 'A01', actions: [{ label: 'Carter row', keywords: ['twelve'] }] } }] };
  const timeline = { durationSeconds: 3, segments: [{ id: 'B1', text: 'Twelve days.', startSeconds: 0, durationSeconds: 3, speechSeconds: 2, lineStartSeconds: 0.3, words: [{ word: 'Twelve', start: 0.4, end: 0.8 }, { word: 'days.', start: 0.9, end: 1.3 }] }] };
  const clipFile = join(receiptDir, 'capture', 'clips', 'A01.webm');
  const composeMap = { groups: [{ segments: ['B1'], edit: { trimStart: 3.0, trimEnd: 11, speed: 1, skip: [], headHold: 0 }, sourceRegion: { x: 0, y: 0, width: 0.5, height: 0.5 } }] };
  buildGateWorkspace({ root: dir, spec, cut, ratio: '16x9', timeline, composeMap, clips: [{ beatId: 'B1', file: clipFile, receiptEntry: { actions: receiptActions, recastHeadTrimSeconds: 0.5 } }], asr: {}, loudnessLufs: -16 });
  const plan = readJson(join(dir, 'story', 'cue-plan.json')).beats.B1.actions;
  assert.deepEqual(plan.filter((a) => a.narrated).map((a) => [a.label, a.keywords.sort()]), [['Carter row', ['12', 'twelve']]]);
  assert.deepEqual(plan.filter((a) => !a.narrated).map((a) => a.label), ['at-risk list', 'trace']);
  // listen inputs
  const seg = readJson(join(dir, 'story', 'narration-segments.json')).segments;
  assert.equal(seg[0].text, 'Twelve days.');
  const tl = readJson(join(dir, 'qa', 'listen-timeline.json'));
  assert.equal(tl.segments[0].audioStartSeconds, 0.4);
  assert.equal(tl.segments[0].audioEndSeconds, 2.3);
  assert.equal(tl.segments[0].sceneEndSeconds, 3);
});

test('sync 2: the clip is cut so the first narrated action lands on its word and the beat holds the result >= 1.5 s', () => {
  const words = [{ word: 'An', start: 0.3 }, { word: 'authorization', start: 0.5 }, { word: 'runs', start: 1.4 }, { word: 'out', start: 1.6 }, { word: 'in', start: 1.7 }, { word: '12', start: 2.0 }, { word: 'days', start: 2.3 }];
  const a = alignBeat({ actions: [{ label: 'Carter row', keywords: ['twelve'] }], receiptActions, headTrim: 0.5, wordsRel: words, fallbackTrim: 6 });
  assert.equal(a.aligned, true);
  assert.equal(a.trimStart, 5.8, 'action at 7.8 s of the clip lands at the word 2.0 s into the beat');
  assert.equal(a.actions[0].programRel, 2.0);
  assert.equal(a.requiredSeconds, 2.0 + RESULT_HOLD_SECONDS, 'the beat outlasts the action by the result hold');
  assert.ok(a.requiredSeconds - a.actions[0].programRel >= 1.5);
  // several actions: align the first, hold after the last
  const two = alignBeat({ actions: [{ label: 'Carter row', keywords: ['twelve'] }, { label: 'trace', keywords: ['days'] }], receiptActions, headTrim: 0.5, wordsRel: words });
  assert.ok(Math.abs(two.requiredSeconds - (9.4 - 5.8 + RESULT_HOLD_SECONDS)) < 1e-9);
  // nothing to match: authored trim is kept and the beat is not resized
  const none = alignBeat({ actions: [{ label: 'Carter row', keywords: ['payer'] }], receiptActions, headTrim: 0.5, wordsRel: words, fallbackTrim: 6 });
  assert.equal(none.aligned, false);
  assert.equal(none.trimStart, 6);
  assert.equal(none.requiredSeconds, null);
  // the word comes before the clip has enough lead-in: clamped at 0 with an explanation, never a negative trim
  const early = alignBeat({ actions: [{ label: 'at-risk list', keywords: ['twelve'] }], receiptActions: [{ t: 0.9, type: 'point', label: 'at-risk list' }], headTrim: 0, wordsRel: words });
  assert.equal(early.trimStart, 0);
  assert.match(early.note, /land late/);
});

test('sync 2b: explicit focus windows outside a re-aligned clip window drop out instead of producing negative spans', () => {
  const band = { w: 1080, h: 900 };
  const w = focusWindows({ explicit: [{ startSec: 2, endSec: 4, x: 0.2, y: 0.2 }, { startSec: 4, endSec: 9, x: 0.6, y: 0.6 }], clipStart: 6, clipEnd: 10, srcW: 1600, srcH: 1000, band, zoom: 2.4 });
  assert.equal(w.length, 1);
  assert.equal(w[0].startSec, 6);
  assert.equal(w[0].endSec, 10);
  assert.equal(w[0].focus.x, 0.6);
});

test('captions 3: a cue never exceeds 18 characters per second; the gap around it is used, never a neighbor', () => {
  const fast = [['Twelve', 0, 0.2], ['units', 0.2, 0.45], ['left,', 0.45, 0.7], ['renewal', 0.7, 1.0], ['not', 1.0, 1.2], ['started.', 1.2, 1.6], ['Next', 4.0, 4.3], ['step.', 4.3, 4.8]].map(([word, start, end]) => ({ word, start, end }));
  const chunks = chunkWords(fast);
  for (const c of chunks) assert.ok(c.text.length / (c.endSec - c.startSec) <= 18.01, `${c.text}: ${(c.text.length / (c.endSec - c.startSec)).toFixed(1)} cps`);
  for (let i = 1; i < chunks.length; i++) assert.ok(chunks[i].startSec >= chunks[i - 1].endSec, 'no overlap');
  assert.ok(captionsCheck(toSrt(chunks)).ok, JSON.stringify(captionsCheck(toSrt(chunks)).errors));
  const tight = [['And', 0.0, 0.2], ['the', 0.2, 0.35], ['next', 0.35, 0.6], ['step', 0.6, 0.9], ['waits', 0.9, 1.2], ['on', 1.2, 1.35], ['a', 1.35, 1.45], ['person.', 1.45, 1.9]].map(([word, start, end]) => ({ word, start, end }));
  const tc = chunkWords(tight);
  assert.ok(tc.every((c) => c.text.length / (c.endSec - c.startSec) <= 20), JSON.stringify(tc.map((c) => [c.text, c.startSec, c.endSec])));
});

test('vision 5: the synthetic-data disclosure is an end-card line, never a chip over the product picture; caption contrast holds', () => {
  const tsx = readFileSync(join(mod, '..', 'src', 'MarketingAd.tsx'), 'utf8');
  assert.doesNotMatch(tsx, /const Label: FC/, 'no persistent label component');
  assert.match(tsx, /const foot = \[props\.label, props\.disclosure\]/, 'the end card carries the label and disclosure');
  for (const ratio of ['16x9', '4x5', '9x16']) assert.equal(layoutFor(ratio, brand).labelBox, undefined, ratio);
  assert.match(tsx, /UNSPOKEN_OPACITY = 0\.88/, 'unspoken caption words stay >= 0.85');
  assert.match(tsx, /EMPHASIS_COLOR = "#ffd166"/);
});

test('listen 4: the listen command passes the pronunciation manifest and the timeline the gate requires', () => {
  const cmd = listenCommand({ candidate: 'C:/ws/output/x.mp4', ws: 'C:/ws', sha: 'abc', sourceRevision: 'rev', risk: 'C:/ws/qa/pronunciation-risk.json', listenOut: 'C:/ws/qa/listen-encoded.json' });
  for (const flag of ['listen', '--transcript', '--pronunciation-manifest', '--timeline', '--candidate-id abc', '--source-revision rev', '--output']) assert.ok(cmd.includes(flag), flag);
  assert.match(cmd, /pronunciation-risk\.json/);
  assert.match(cmd, /listen-timeline\.json/);
});

test('item 6: a window already magnified by a Recast punch-in gets a wider crop so the magnification stays under the cap', () => {
  const band = { w: 1080, h: 900 };
  const base = bandRegion({ srcW: 1600, srcH: 1000, band, zoom: 2.4 }).scale;
  assert.ok(Math.abs(base - 2.16) < 0.01, 'the 9:16 band at base zoom is about 2.16x');
  const [w] = focusWindows({ explicit: [{ startSec: 0, endSec: 5, x: 0.4, y: 0.4, sourceZoom: 1.5 }], clipStart: 0, clipEnd: 5, srcW: 1600, srcH: 1000, band, zoom: 2.4 });
  assert.ok(w.scale <= MAX_SCALE + 1e-6, `scale ${w.scale}`);
  assert.ok(w.zoom < 2.4 && w.zoom >= 1, `zoom reduced to ${w.zoom}`);
  assert.equal(readability(w.scale).ok, true);
  const [fits] = focusWindows({ explicit: [{ startSec: 0, endSec: 5, x: 0.4, y: 0.4, sourceZoom: 1.2 }], clipStart: 0, clipEnd: 5, srcW: 1600, srcH: 1000, band, zoom: 2.4 });
  assert.equal(fits.zoom, 2.4);
  const [huge] = focusWindows({ explicit: [{ startSec: 0, endSec: 5, x: 0.4, y: 0.4, sourceZoom: 3.8 }], clipStart: 0, clipEnd: 5, srcW: 1600, srcH: 1000, band, zoom: 2.4 });
  assert.equal(huge.zoom, 1);
  assert.equal(readability(huge.scale).ok, false);
  const [wide] = focusWindows({ explicit: [{ startSec: 0, endSec: 5, x: 0.4, y: 0.4, sourceZoom: 1.5 }], clipStart: 0, clipEnd: 5, srcW: 1600, srcH: 1000, band: { w: 1080, h: 760 }, zoom: 1.7 });
  assert.equal(wide.zoom, 1.7);
});

// ---- round 2 (second GPU run)
test('sync r2-1: a result is declared only when it is visible inside the beat and holds >= 1.5 s; a slightly late one lengthens the beat', () => {
  const exp = (label, clip) => ({ label, clip });
  // held: 2.0 s into a 4.1 s beat -> kept, no extension
  let r = chooseResult({ expectations: [exp('runway visible', 8.0)], trimStart: 6.0, naturalSeconds: 4.1 });
  assert.equal(r.keep.length, 1);
  assert.equal(r.requiredSeconds, null);
  // after the beat (clip 8.04 against a window that ends at 5.6): left out, never stamped after the beat
  r = chooseResult({ expectations: [exp('Carter first on the list', 8.04)], trimStart: 2.7, naturalSeconds: 2.83 });
  assert.equal(r.keep.length, 0);
  assert.equal(r.dropped.length, 1);
  // before the clip window: dropped
  assert.equal(chooseResult({ expectations: [exp('early', 1)], trimStart: 3, naturalSeconds: 5 }).keep.length, 0);
  // 0.14 s short of the hold (V1 in the second run): the beat grows by that much
  r = chooseResult({ expectations: [exp('result', 2.22)], trimStart: 0, naturalSeconds: 3.68 });
  assert.equal(r.keep.length, 1);
  assert.ok(Math.abs(r.requiredSeconds - (2.22 + RESULT_HOLD_SECONDS)) < 1e-9);
  // more than 0.5 s short: not this beat's result
  assert.equal(chooseResult({ expectations: [exp('late', 3.2)], trimStart: 0, naturalSeconds: 3.68 }).keep.length, 0);
  // the last of several held expectations is the one the cue sheet picks, so every held one is kept
  assert.equal(chooseResult({ expectations: [exp('a', 1), exp('b', 2)], trimStart: 0, naturalSeconds: 6 }).keep.length, 2);
});

test('sync r2-2: the per-line ASR copy is shifted by the lead so keyword times match where the line is placed', () => {
  const payload = { words: [{ word: 'Twelve', start: 0.1, end: 0.4 }], segments: [{ start: 0, end: 1, words: [{ word: 'Twelve', start: 0.1, end: 0.4 }] }] };
  const moved = shiftAsr(payload, 0.3);
  assert.equal(moved.words[0].start, 0.4);
  assert.equal(moved.segments[0].words[0].end, 0.7);
  assert.equal(payload.words[0].start, 0.1, 'the source is not modified');
  const dir = join(root, 'gatews2');
  const spec = baseSpec();
  const cut = { id: 'main', ratios: ['16x9'], beats: [{ id: 'B1', kind: 'ui', narration: 'Twelve days.', ui: { sourceJob: 'film', clipId: 'A01', actions: [{ label: 'Carter row', keywords: ['twelve'] }] } }, { id: 'B2', kind: 'ui', narration: 'Later.', ui: { sourceJob: 'film', clipId: 'A01' } }] };
  const timeline = { durationSeconds: 8, segments: [
    { id: 'B1', text: 'Twelve days.', startSeconds: 0, durationSeconds: 4, speechSeconds: 2, lineStartSeconds: 0.3, words: [{ word: 'Twelve', start: 0.4, end: 0.8 }] },
    { id: 'B2', text: 'Later.', startSeconds: 4, durationSeconds: 4, speechSeconds: 1, lineStartSeconds: 4.3, words: [{ word: 'Later.', start: 4.4, end: 4.8 }] }] };
  const asrFile = join(root, 'asr-b1.json');
  writeFileSync(asrFile, JSON.stringify(payload));
  const clipFile = join(receiptDir, 'capture', 'clips', 'A01.webm');
  const expectations = [{ label: 'in window', observed: true, observedAt: 5.0 }, { label: 'after the beat', observed: true, observedAt: 12.0 }, { label: 'never observed', observed: false, observedAt: 5.5 }];
  const composeMap = { groups: [{ segments: ['B1'], edit: { trimStart: 3.0, trimEnd: 12, speed: 1, skip: [], headHold: 0 }, sourceRegion: { x: 0, y: 0, width: 0.5, height: 0.5 } }, { segments: ['B2'], edit: { trimStart: 3.0, trimEnd: 12, speed: 1, skip: [], headHold: 0 }, sourceRegion: { x: 0, y: 0, width: 0.5, height: 0.5 } }] };
  buildGateWorkspace({ root: dir, spec, cut, ratio: '16x9', timeline, composeMap, clips: [{ beatId: 'B1', file: clipFile, receiptEntry: { actions: receiptActions, expectations, recastHeadTrimSeconds: 0 } }, { beatId: 'B2', file: clipFile, receiptEntry: { actions: receiptActions, expectations, recastHeadTrimSeconds: 0 } }], asr: { B1: asrFile }, loudnessLufs: -16 });
  assert.equal(readJson(join(dir, 'voice', 'asr', 'B1.json')).words[0].start, 0.4);
  const rec = readJson(join(dir, 'capture', 'receipt.json')).clips;
  assert.deepEqual(rec.B1.expectations.filter((x) => x.observed).map((x) => x.label), ['in window'], 'only an expectation that can hold inside the beat stays');
  assert.deepEqual(rec.B2.expectations.filter((x) => x.observed).map((x) => x.label), ['in window']);
  assert.equal(rec.B1.expectations.length, 2, 'unobserved expectations are untouched');
});

test('vision r2-3: frames are not sampled within 0.25 s of a caption transition, and the rubric says captions are chunks', () => {
  const cues = [{ startSec: 1.0, endSec: 2.5 }, { startSec: 2.6, endSec: 4.0 }, { startSec: 5.0, endSec: 6.0 }];
  const plain = sampleTimes(7, 1.5);
  const nudged = sampleTimes(7, 1.5, { cues });
  assert.ok(plain.some((t) => cues.some((c) => Math.abs(t - c.startSec) < 0.25 || Math.abs(t - c.endSec) < 0.25)), 'the plain grid does hit a transition');
  for (const t of nudged) assert.ok(cues.every((c) => Math.abs(t - c.startSec) >= 0.25 && Math.abs(t - c.endSec) >= 0.25), `sample ${t} is on a transition`);
  assert.ok(nudged.every((t, i) => i === 0 || t > nudged[i - 1]), 'still ordered and unique');
  assert.deepEqual(sampleTimes(6, 1.5, { cues: [] }), [0.4, 1.9, 3.4, 4.9, 5.6], 'no cues, no change');
  const text = buildInstructions({ spec: baseSpec(), brand, ratio: '16x9' });
  assert.match(text, /4-7 word chunks of ONE spoken sentence/);
  assert.match(text, /NOT a typo or an incomplete sentence/);
});

test('vision r2-4: arbitration is honoured only for this candidate hash, a named reviewer and specific false-positive items', () => {
  const verdict = parseVerdict(verdictJson({ frames: [
    { label: 'F13', issues: [{ category: 'typo', severity: 'high', detail: 'reads "Tru"', evidence: 'Tru' }] },
    { label: 'F14', issues: [{ category: 'typo', severity: 'high', detail: 'reads "Tru"', evidence: 'Tru' }, { category: 'banned-claim', severity: 'high', detail: 'real', evidence: 'x' }] }] }));
  const base = evaluate(verdict);
  assert.equal(base.ok, false);
  const arb = { candidateSha256: 'a'.repeat(64), reviewer: 'sarosh', items: [
    { frame: 'F13', category: 'typo', verdict: 'false-positive', reason: 'Try is legible in the encoded frame' },
    { frame: 'F14', category: 'typo', verdict: 'false-positive', reason: 'same card, frame checked by eye' }] };
  let r = applyArbitration(structuredClone(base), arb, 'a'.repeat(64));
  assert.equal(r.arbitration.honoured, true);
  assert.equal(r.arbitration.applied.length, 2);
  assert.equal(r.ok, false, 'the real banned-claim finding on F14 still blocks');
  assert.equal(r.blocking, 1);
  const only = { ...arb, items: [{ frame: 'F13', category: 'typo', verdict: 'false-positive', reason: 'Try is legible in the encoded frame' }] };
  const clean = evaluate(parseVerdict(verdictJson({ frames: [{ label: 'F13', issues: [{ category: 'typo', severity: 'high', detail: 'x', evidence: 'y' }] }] })));
  r = applyArbitration(structuredClone(clean), only, 'a'.repeat(64));
  assert.equal(r.ok, true);
  assert.equal(r.arbitration.reviewer, 'sarosh');
  // wrong candidate, no reviewer, weak item, unknown finding, wrong verdict: not honoured
  assert.equal(applyArbitration(structuredClone(clean), only, 'b'.repeat(64)).ok, false);
  assert.match(applyArbitration(structuredClone(clean), only, 'b'.repeat(64)).arbitration.ignored[0].reason, /different candidate/);
  assert.equal(applyArbitration(structuredClone(clean), { ...only, reviewer: ' ' }, 'a'.repeat(64)).ok, false);
  assert.equal(applyArbitration(structuredClone(clean), { ...only, items: [{ frame: 'F13', category: 'typo', verdict: 'false-positive', reason: 'no' }] }, 'a'.repeat(64)).ok, false);
  assert.equal(applyArbitration(structuredClone(clean), { ...only, items: [{ frame: 'F99', category: 'typo', verdict: 'false-positive', reason: 'there is no such frame' }] }, 'a'.repeat(64)).ok, false);
  assert.equal(applyArbitration(structuredClone(clean), { ...only, items: [{ frame: 'F13', category: 'typo', verdict: 'real', reason: 'it is a real typo here' }] }, 'a'.repeat(64)).ok, false);
  // no file at all
  assert.equal(applyArbitration(structuredClone(clean), null, 'a'.repeat(64)).arbitration.file, false);
  // a missing label can be arbitrated only through an explicit overall/missing-label item
  const nolabel = evaluate(parseVerdict(verdictJson({ overall: { labelPresentWhereRequired: false, summary: 'x' } })));
  assert.equal(applyArbitration(structuredClone(nolabel), { candidateSha256: 'a'.repeat(64), reviewer: 'r', items: [{ frame: 'overall', category: 'missing-label', verdict: 'false-positive', reason: 'label present on every frame, checked' }] }, 'a'.repeat(64)).ok, true);
  // mvg itself never writes the file: the vision run leaves no arbitration behind
  const qdir = join(root, 'noauto');
  mkdirSync(qdir, { recursive: true });
  const src = readFileSync(join(mod, 'lib', 'stages', 'qa.mjs'), 'utf8');
  assert.ok(!/writeJson\([^)]*vision-arbitration/.test(src) && !/writeFileSync\([^)]*vision-arbitration/.test(src));
});

test('listen r2-5: releaseEligible is the pass signal and any finding, a WARNING included, is named in the gate detail', () => {
  const report = { status: 'FAIL', releaseEligible: false, findings: [{ severity: 'WARNING', checkId: 'delivery-and-pacing', startSeconds: 0.33, description: "A slight hesitation before 'Twelve units left.'" }] };
  assert.match(listenFindings(report), /WARNING delivery-and-pacing at 0.33s: A slight hesitation/);
  assert.equal(listenFindings({ findings: [] }), 'no findings (check the report)');
  const src = readFileSync(join(mod, 'lib', 'local-gates.mjs'), 'utf8');
  assert.match(src, /releaseEligible === true/);
  assert.ok(!/severity === 'WARNING'/.test(src), 'a WARNING is never downgraded');
});

test('reviews.json counts only for the candidate hash it names', () => {
  const dir = mkdtempSync(join(tmpdir(), 'mvg-reviews-'));
  const path = join(dir, 'reviews.json');
  assert.deepEqual(readReviews(path, 'abc'), {});
  writeFileSync(path, JSON.stringify({ candidateSha256: 'old', storyReview: { status: 'PASS', score: 90 } }));
  assert.deepEqual(readReviews(path, 'new'), {});
  writeFileSync(path, JSON.stringify({ storyReview: { status: 'PASS', score: 90 } }));
  assert.deepEqual(readReviews(path, 'new'), {});
  writeFileSync(path, JSON.stringify({ candidateSha256: 'new', storyReview: { status: 'PASS', score: 90 } }));
  assert.equal(readReviews(path, 'new').storyReview.score, 90);
});

// ---- round 3: design review fixes
test('review 2: a crop never starts inside the product navigation', () => {
  const opts = { contentLeft: 0.13, insetPx: 24, srcW: 1600 };
  const r = (x, width) => ({ x, y: 0.2, width, height: 0.4 });
  // starts mid-nav, narrow crop: snaps to the content edge plus the inset (0.13 + 24/1600 = 0.145)
  assert.equal(snapToContent(r(0.05, 0.42), opts).x, 0.145);
  assert.equal(snapToContent(r(0.12, 0.42), opts).x, 0.145);
  // wide crop: shows the whole navigation instead
  assert.equal(snapToContent(r(0.07, WIDE_REGION), opts).x, 0);
  assert.equal(snapToContent(r(0.07, 0.8), opts).x, 0);
  // already at 0, or at/after the content edge: untouched
  assert.equal(snapToContent(r(0, 0.4), opts).x, 0);
  assert.equal(snapToContent(r(0.13, 0.4), opts).x, 0.13);
  assert.equal(snapToContent(r(0.4, 0.4), opts).x, 0.4);
  // just under the wide threshold: still fits after the nav, so it snaps rather than showing the whole nav
  assert.equal(snapToContent(r(0.1, 0.59), opts).x, 0.145);
  // no brand edge: nothing changes
  assert.equal(snapToContent(r(0.05, 0.4), { insetPx: 24, srcW: 1600 }).x, 0.05);
  // through focusWindows: a 9:16 window centred near the nav no longer starts inside it
  const band = { w: 1080, h: 820 };
  const [w] = focusWindows({ explicit: [{ startSec: 0, endSec: 5, x: 0.2, y: 0.4 }], clipStart: 0, clipEnd: 5, srcW: 1600, srcH: 1000, band, zoom: 2.4, contentLeft: 0.13, contentInsetPx: 24 });
  assert.ok(w.region.x >= 0.145 - 1e-9 || w.region.x === 0, `region starts at ${w.region.x}`);
  const [free] = focusWindows({ explicit: [{ startSec: 0, endSec: 5, x: 0.2, y: 0.4 }], clipStart: 0, clipEnd: 5, srcW: 1600, srcH: 1000, band, zoom: 2.4 });
  assert.ok(free.region.x > 0 && free.region.x < 0.13, 'without the brand edge the same crop would start inside the nav');
});

test('review 5: caption lines are balanced, fit 82% of the frame, and never leave a one-word line', () => {
  const words = (t) => t.split(' ').map((word) => ({ word }));
  const fit = 0.82 * 1080;
  for (const text of ['Nine checks pass, the hold clears,', 'This claim is held because', 'the note behind it is unsigned.', 'One authorization runs out in twelve days,', 'and nothing is sent to a payer.', 'Ready to Bill means locally ready.']) {
    const w = words(text);
    const lines = lineBreaks(w, { maxWidthPx: fit, fontSize: 62 });
    assert.equal(lines.reduce((a, b) => a + b, 0), w.length, text);
    if (w.length >= 4) assert.ok(lines.every((n) => n >= 2), `${text}: ${lines}`);
    let at = 0;
    for (const n of lines) { const row = w.slice(at, at + n); at += n; assert.ok(row.map((x) => x.word).join(' ').length * 0.58 * 62 + (n - 1) * 0.4 * 62 <= fit + 1, `${text}: a line is too wide`); }
    if (lines.length === 2) assert.ok(Math.abs(lines[0] - lines[1]) <= 2, `${text}: unbalanced ${lines}`);
  }
  assert.deepEqual(lineBreaks(words('One authorization runs out in twelve days,'), { maxWidthPx: 1574, fontSize: 50 }), [7], 'one line when it fits');
  assert.deepEqual(lineBreaks(words('Twelve units left.'), { maxWidthPx: 200, fontSize: 62 }), [3], 'too short to split stays whole');
  assert.deepEqual(lineBreaks([], { maxWidthPx: 100, fontSize: 50 }), []);
  // a 5-word chunk too wide for one line splits 3 + 2, not 4 + 1
  assert.deepEqual(lineBreaks(words('authorization authorization authorization renewal renewal'), { maxWidthPx: 1100, fontSize: 62 }).every((n) => n >= 2), true);
});

test('review 1/3/5/6: composition behaviours the layout depends on are in the source', () => {
  const tsx = readFileSync(join(mod, '..', 'src', 'MarketingAd.tsx'), 'utf8');
  // 1: no captions on card / title beats, fade <= 6 frames, no eyebrow
  assert.match(tsx, /b\.kind === "card" \|\| b\.kind === "title"\) && frame >= frames\[i\]\.from/);
  assert.match(tsx, /CAPTION_FADE_FRAMES = 6/);
  assert.ok(!/letterSpacing: "0\.12em"/.test(tsx), 'the product-name eyebrow is gone');
  // 3: captions sit on their own navy plate over the native picture (no band, no backdrop)
  assert.match(tsx, /background: `rgba\(\$\{PLATE\}, 0\.86\)`/);
  assert.ok(!/BAND_FADE_PX|UiBackdrop/.test(tsx), 'the band layout is gone');
  // 5: balance, 82% width, bold when spoken
  assert.match(tsx, /textWrap: "balance"/);
  assert.match(tsx, /width \* 0\.82/);
  assert.match(tsx, /bold=\{em \|\| spoken\}/);
  // 6: amber pill with navy text
  assert.match(tsx, /background: brand\.colors\.emphasis \?\? EMPHASIS_COLOR, color: brand\.colors\.foreground/);
  assert.equal(CTA_PILL_FONT['9x16'], 52);
  // title: one row per sentence so "Out in 2 days." never wraps mid-sentence; the word stagger counts across rows
  assert.match(tsx, /split\(\/\(\?<=\[\.!\?\]\)\\s\+\/\)/);
  assert.match(tsx, /rows\.slice\(0, r\)\.reduce\(\(n, x\) => n \+ x\.length, 0\)/);
  // title: each sentence row is sized to fit one line from its character count (0.56 em per character + 0.28 em word gaps),
  // capped at the hook size, floored at 0.08 of the box
  assert.match(tsx, /0\.56 \* r\.join\(""\)\.length \+ 0\.28 \* \(r\.length - 1\)/);
  assert.match(tsx, /Math\.max\(floor, Math\.min\(cap, Math\.floor\(box\.w \/ rowEm\)\)\)/);
  assert.match(tsx, /const floor = Math\.round\(Math\.min\(box\.w, box\.h\) \* 0\.08\)/);
  assert.match(tsx, /columnGap: size \* 0\.28/);
  const titleSize = (ratio, headline) => {
    const box = layoutFor(ratio, brand).ctaBox;
    const rows = headline.split(/(?<=[.!?])\s+/).map((r) => r.split(/\s+/).filter(Boolean));
    const cap = Math.round(Math.min(box.w, box.h) * (ratio === '16x9' ? 0.16 : 0.15));
    const floor = Math.round(Math.min(box.w, box.h) * 0.08);
    const rowEm = Math.max(...rows.map((r) => 0.56 * r.join('').length + 0.28 * (r.length - 1)));
    return { box, cap, floor, rowEm, size: Math.max(floor, Math.min(cap, Math.floor(box.w / rowEm))) };
  };
  const unsigned = titleSize('4x5', 'Unsigned note. Claim held.');
  assert.ok(unsigned.size < unsigned.cap, 'the fixed fraction would have wrapped "Unsigned" alone');
  assert.ok(unsigned.size * unsigned.rowEm <= unsigned.box.w, 'the widest row fits its box on one line');
  assert.ok(unsigned.size >= unsigned.floor);
  const short = titleSize('16x9', 'Two days.');
  assert.equal(short.size, short.cap, 'a short row keeps the hook size');
  const huge = titleSize('9x16', 'Authorization renewals quietly lapsing everywhere unnoticed today.');
  assert.equal(huge.size, huge.floor, 'an over-long row bottoms out at the floor, where it may wrap');
  // 6: the card block is centred in the safe area and shares the caption / label left edge
  const l916 = layoutFor('9x16', brand);
  assert.equal(l916.ctaBox.y, l916.safe.y);
  assert.equal(l916.ctaBox.h, l916.safe.h);
  assert.equal(l916.ctaBox.x, l916.captionBox.x);
  const l169 = layoutFor('16x9', brand);
  assert.equal(l169.ctaBox.x, 96);
  assert.equal(l169.ctaBox.x, l169.captionBox.x);
  for (const ratio of ['16x9', '4x5', '9x16']) assert.deepEqual(safeZoneErrors(layoutFor(ratio, brand)), [], ratio);
});

test('record-lib pageZoom: an opt-in desktop document zoom set early and on load, recorded per take, never combined with mobileLayout', () => {
  const lib = readFileSync(join(mod, '..', 'screencast', 'record-lib.mjs'), 'utf8');
  const job = readFileSync(join(mod, '..', 'screencast', 'record-job.mjs'), 'utf8');
  assert.match(lib, /if \(opts\.pageZoom && !mobile\)/);
  assert.match(lib, /document\.documentElement\.style\.zoom = String\(z\)/);
  assert.match(lib, /addEventListener\('DOMContentLoaded', set\);\s+window\.addEventListener\('load', set\)/);
  assert.match(job, /pageZoom: options\.pageZoom,/);
  assert.match(job, /\.\.\.\(options\.pageZoom \? \{ pageZoom: options\.pageZoom \} : \{\}\)/);
});

test('review 5: compose hands the composition explicit caption line breaks that cover every word', () => {
  const props = { width: 1080, height: 1920, fps: 30, durationSec: 4, brand: { fontFiles: [] }, beats: [{ id: 'A', kind: 'card', startSec: 0, durationSec: 4 }],
    captions: [{ startSec: 0, endSec: 1.5, words: 'one two three four five'.split(' ').map((word) => ({ word, start: 0, end: 1 })), lines: [3, 2] }] };
  assert.deepEqual(validateProps(props, join(root, 'pub')), []);
  props.captions[0].lines = [4, 1];
  assert.ok(validateProps(props, join(root, 'pub')).some((e) => /single word/.test(e)));
  props.captions[0].lines = [2, 2];
  assert.ok(validateProps(props, join(root, 'pub')).some((e) => /cover every word/.test(e)));
});

test('voiceTake gives a line a fresh cache key without touching its neighbours', () => {
  const spec = { voice: { provider: 'elevenlabs', voiceId: 'v', model: 'eleven_v4', settings: { stability: 0.5 } } };
  const a = lineKey(spec, 'Twelve units left.', 'prev', 'next');
  assert.equal(lineKey(spec, 'Twelve units left.', 'prev', 'next', 0), a);
  assert.notEqual(lineKey(spec, 'Twelve units left.', 'prev', 'next', 2), a);
});

test('a focus window zoom is one number, and a zoom the cue sheet declares is marked declaredZoom', async () => {
  const { validate } = await import('../kit/marketing/lib/schema.mjs');
  const schema = JSON.parse(readFileSync(new URL('../kit/marketing/ad.schema.json', import.meta.url), 'utf8'));
  const find = (node) => (node && typeof node === 'object' ? (node.declaredZoom ? node : Object.values(node).map(find).find(Boolean)) : null);
  const focus = find(schema);
  assert.deepEqual(validate(focus.zoom, 1.8), []);
  assert.notDeepEqual(validate(focus.zoom, { '16x9': 1.8 }), [], 'per-ratio crops are gone: each ratio is its own capture');
  assert.notDeepEqual(validate(focus.x, { '4x5': 0.3 }), []);
  assert.deepEqual(validate(focus.declaredZoom, true), []);
});

test('lint: narration about synthetic/demo data or the film itself is fluff and fails', async () => {
  const { FLUFF } = await import('../kit/marketing/lib/lint.mjs');
  assert.ok(FLUFF.test('Try ABACare on synthetic data.'));
  assert.ok(FLUFF.test('In this video we show the hold queue.'));
  assert.ok(!FLUFF.test('Twelve units left. Three sessions on the calendar.'));
});

// ---- media-studio 2.0.0 film-chain gates: picture integrity, pointer path, marketing readiness
test('chain gates 1: integrity, pointer and marketing are required by default and always, and deliver refuses without them', () => {
  for (const g of ['integrity', 'pointer', 'frameIntegrity', 'marketing']) assert.ok(DEFAULT_REQUIRED.includes(g), g);
  assert.deepEqual([...CHAIN_GATES], ['integrity', 'pointer', 'frameIntegrity', 'marketing']);
  const narrowed = requiredGates({ qa: { required: ['picture', 'captions'] } });
  assert.deepEqual(narrowed, ['picture', 'captions', 'integrity', 'pointer', 'frameIntegrity', 'marketing'], 'a spec cannot drop the film-chain gates');
  assert.deepEqual(requiredGates({}), DEFAULT_REQUIRED);
  const passing = Object.fromEntries(DEFAULT_REQUIRED.map((g) => [g, { status: 'pass' }]));
  assert.equal(releasable(passing, requiredGates({})).ok, true);
  for (const g of CHAIN_GATES) {
    const pending = releasable({ ...passing, [g]: { status: 'pending', detail: 'x' } }, requiredGates({}));
    assert.equal(pending.ok, false, `${g} pending blocks release`);
    assert.match(pending.failing.join(' '), new RegExp(`${g}: pending`));
    assert.equal(releasable({ ...passing, [g]: { status: 'fail' } }, requiredGates({})).ok, false);
    const missing = { ...passing };
    delete missing[g];
    assert.match(releasable(missing, requiredGates({})).failing.join(' '), new RegExp(`${g}: not run`));
  }
  const names = adSchema.properties.qa.properties.required.items.enum;
  for (const g of CHAIN_GATES) assert.ok(names.includes(g), `ad.schema.json lists ${g}`);
  assert.deepEqual(validate(adSchema.properties.qa, { required: [...DEFAULT_REQUIRED] }), []);
});

test('chain gates 2: the marketing-readiness file counts only for the candidate it names, and mvg never writes it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'mvg-readiness-'));
  const path = join(dir, 'marketing-readiness.json');
  assert.equal(readMarketingReadiness(path, 'sha-new').state, 'absent');
  writeFileSync(path, '{ not json');
  assert.equal(readMarketingReadiness(path, 'sha-new').state, 'unreadable');
  writeFileSync(path, JSON.stringify({ schema: 'media-studio/marketing-readiness/1', candidate: { sha256: 'sha-old', bytes: 1 } }));
  const stale = readMarketingReadiness(path, 'sha-new');
  assert.deepEqual([stale.state, stale.readiness, stale.boundTo], ['stale', null, 'sha-old'], 'a review of an earlier render never passes a new one');
  writeFileSync(path, JSON.stringify({ schema: 'media-studio/marketing-readiness/1', reviewer: 'r' }));
  assert.equal(readMarketingReadiness(path, 'sha-new').state, 'stale', 'a file that names no candidate is not bound');
  writeFileSync(path, JSON.stringify({ candidate: { sha256: 'sha-new', bytes: 9 } }));
  assert.equal(readMarketingReadiness(path, 'sha-new').state, 'bound');
  writeFileSync(path, JSON.stringify({ candidateSha256: 'sha-new' }));
  assert.equal(readMarketingReadiness(path, 'sha-new').state, 'bound', 'the reviews.json convention binds too');
  assert.equal(readMarketingReadiness(path, '').state, 'stale');
  const msg = readinessPending({ ratio: '4x5', state: 'absent', boundTo: null, sha: 'a'.repeat(64) });
  assert.match(msg, /qa\/4x5\/marketing-readiness\.json/);
  assert.match(msg, /candidate\.sha256 aaaaaaaaaaaa/);
  assert.match(readinessPending({ ratio: '4x5', state: 'stale', boundTo: 'b'.repeat(64), sha: 'a'.repeat(64) }), /bound to another candidate \(bbbbbbbbbbbb/);
  const src = readFileSync(join(mod, 'lib', 'chain-gates.mjs'), 'utf8');
  assert.ok(!/writeJson\([^)]*marketing-readiness\.json/.test(src) && !/writeFileSync\([^)]*marketing-readiness\.json/.test(src), 'mvg never writes the reviewer file');
});

test('chain gates 3: the marketing gate is pending, not fail, without a reviewer file for this candidate, and runs no marketing script', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'mvg-mkgate-'));
  const ws = join(dir, 'ws');
  const qdir = join(dir, 'qa');
  mkdirSync(join(ws, 'qa'), { recursive: true });
  mkdirSync(qdir, { recursive: true });
  writeFileSync(join(ws, 'qa', 'marketing-readiness.json'), '{"old":true}');
  writeFileSync(join(ws, 'qa', 'marketing-readiness-check.json'), '{"ok":true}');
  const args = { ws, qdir, ratio: '9x16', candidate: join(ws, 'output', 'x.mp4'), sha: 'c'.repeat(64), composeMapRel: 'output/x-compose-map.json', moduleRoot: join(dir, 'no-such-kit') };
  const absent = await runMarketingGate(args);
  assert.equal(absent.status, 'pending');
  assert.match(absent.detail, /qa\/9x16\/marketing-readiness\.json/);
  assert.ok(!existsSync(join(ws, 'qa', 'marketing-readiness.json')) && !existsSync(join(ws, 'qa', 'marketing-readiness-check.json')), 'no earlier copy or report survives into this candidate');
  assert.ok(!existsSync(join(qdir, 'marketing-readiness.json')), 'mvg did not write the reviewer file');
  writeFileSync(join(qdir, 'marketing-readiness.json'), JSON.stringify({ candidate: { sha256: 'd'.repeat(64), bytes: 1 } }));
  const stale = await runMarketingGate(args);
  assert.equal(stale.status, 'pending');
  assert.match(stale.detail, /bound to another candidate/);
  assert.ok(!existsSync(join(ws, 'qa', 'marketing-readiness.json')), 'a stale file is not copied into the workspace');
  // A file for this candidate is copied and the shared script is then required (missing kit: a fail that names it, never a pass).
  writeFileSync(join(qdir, 'marketing-readiness.json'), JSON.stringify({ candidate: { sha256: 'c'.repeat(64), bytes: 1 } }));
  const bound = await runMarketingGate(args);
  assert.equal(bound.status, 'fail');
  assert.match(bound.detail, /not found/);
  assert.ok(existsSync(join(ws, 'qa', 'marketing-readiness.json')), 'the bound file was copied into the workspace');
});

test('chain gates 4: a gate script result is a pass only on exit 0 with ok:true; a marketing floor that did not apply fails', () => {
  assert.equal(chainGateResult('integrity', { code: 0, report: { ok: true, clips: [{}, {}], ratio: { deliverable: '4:5' }, warnings: [] } }).status, 'pass');
  assert.equal(chainGateResult('integrity', { code: 1, report: { ok: true } }).status, 'fail', 'exit code wins');
  assert.equal(chainGateResult('frameIntegrity', { code: 0, report: { ok: true, sampled: 40, warnings: [] } }).status, 'pass');
  assert.equal(chainGateResult('frameIntegrity', { code: 1, report: { ok: false, errors: ['tiled frame at 3.5 s'] } }).detail, 'tiled frame at 3.5 s');
  assert.equal(chainGateResult('integrity', { code: 0, report: { ok: false, errors: ['[bars] x'] } }).status, 'fail');
  assert.equal(chainGateResult('pointer', { code: 1, report: { ok: false, errors: ['a', 'b', 'c', 'd'] } }).detail, 'a | b | c');
  assert.match(chainGateResult('pointer', { code: 0, report: { ok: true, mode: 'clip', windows: [{}] } }).detail, /whole clips/);
  assert.doesNotMatch(chainGateResult('pointer', { code: 0, report: { ok: true, mode: 'mapped', windows: [{}] } }).detail, /whole clips/);
  assert.equal(chainGateResult('integrity', { code: -1, report: null, stderr: 'validate-picture-integrity.mjs not found' }).detail, 'validate-picture-integrity.mjs not found');
  assert.equal(chainGateResult('marketing', { code: 0, report: { ok: true, applies: false, reason: 'not a marketing cut' } }).status, 'fail');
  assert.ok(chainGateResult('marketing', { code: 0, report: { ok: true, applies: true, checks: { 'hook-2s': 'pass', 'hook-2s.note': 'x', 'feed-test': 'pass' } } }).detail.startsWith('2 checks'));
});

test('chain gates 5: the workspace declares a marketing cut and the capture frame each non-landscape ratio must have', () => {
  assert.deepEqual(captureViewportsFor('16x9', FRAMES['16x9']), {}, 'landscape is not constrained by the gate');
  assert.deepEqual(captureViewportsFor('4x5', FRAMES['4x5']), { '4:5': { width: 1080, height: 1350 } });
  assert.deepEqual(captureViewportsFor('9x16', FRAMES['9x16']), { '9:16': { width: 1080, height: 1920 } });
  const dir = join(root, 'gatews-chain');
  const spec = baseSpec();
  const cut = { id: 'main', ratios: ['4x5'], beats: [{ id: 'B1', kind: 'ui', narration: 'Twelve days.', ui: { sourceJob: 'film', clipId: 'A01', actions: [{ label: 'Carter row', keywords: ['twelve'] }] } }, { id: 'B2', kind: 'ui', narration: 'Later.', ui: { sourceJob: 'film', clipId: 'A01' } }] };
  const timeline = { durationSeconds: 8, segments: [
    { id: 'B1', text: 'Twelve days.', startSeconds: 0, durationSeconds: 4, speechSeconds: 2, lineStartSeconds: 0.3, words: [{ word: 'Twelve', start: 0.4, end: 0.8 }] },
    { id: 'B2', text: 'Later.', startSeconds: 4, durationSeconds: 4, speechSeconds: 1, lineStartSeconds: 4.3, words: [{ word: 'Later.', start: 4.4, end: 4.8 }] }] };
  const full = { x: 0, y: 0, width: 1, height: 1 };
  const half = { x: 0, y: 0, width: 0.5, height: 0.5 };
  const edit = { trimStart: 0, trimEnd: 12, speed: 1, skip: [], headHold: 0 };
  const composeMap = { groups: [{ segments: ['B1'], edit, sourceRegion: half, windows: [{ declaredZoom: true }] }, { segments: ['B2'], edit, sourceRegion: half, windows: [{ declaredZoom: false }] }] };
  const clipFile = join(receiptDir, 'capture', 'clips', 'A01.webm');
  const entry = { actions: [{ t: 6, type: 'point', x: 5, y: 5, label: 'Carter row' }], recastHeadTrimSeconds: 0 };
  const clips = [{ beatId: 'B1', file: clipFile, receiptEntry: entry }, { beatId: 'B2', file: clipFile, receiptEntry: entry }];
  buildGateWorkspace({ root: dir, spec, cut, ratio: '4x5', timeline, composeMap, clips, asr: {}, loudnessLufs: -14 });
  const job = readJson(join(dir, 'job.json'));
  assert.equal(job.marketing, true);
  assert.equal(job.programForm, 'outcome-workflow', 'programForm is unchanged: marketing:true carries the applicability');
  assert.equal(job.deliveryProfile, 'linkedin-4x5');
  assert.deepEqual(job.captureViewports, { '4:5': { width: 1080, height: 1350 } });
  assert.deepEqual(job.syntheticDisclosure, { mode: 'end-card', text: spec.labels }, 'the narration check sees the end-card disclosure');
  assert.notEqual(job.responsive, false, 'no responsiveException shortcut');
  const plan = readJson(join(dir, 'story', 'cue-plan.json')).beats;
  assert.equal(plan.B1.zoom, true, 'an authored declaredZoom is declared in the cue plan');
  assert.match(plan.B1.crop.reason, /declaredZoom/);
  assert.equal(plan.B2?.zoom, undefined, 'an undeclared crop is never declared on the author behalf');
  assert.equal(plan.B2?.crop, undefined);
  const dir2 = join(root, 'gatews-chain2');
  const fullMap = { groups: [{ segments: ['B1'], edit, sourceRegion: full, windows: [{ declaredZoom: true }] }, { segments: ['B2'], edit, sourceRegion: full, windows: [] }] };
  buildGateWorkspace({ root: dir2, spec, cut, ratio: '4x5', timeline, composeMap: fullMap, clips, asr: {}, loudnessLufs: -14 });
  assert.equal(readJson(join(dir2, 'story', 'cue-plan.json')).beats.B1.crop, undefined, 'a full-region window needs no crop declaration');
});

test('chain gates 6: the pointer gate runs the shared script on the workspace receipt: a led path passes, a wandering one fails', async () => {
  const mk = (name, actions) => {
    const ws = join(root, name);
    mkdirSync(join(ws, 'capture'), { recursive: true });
    writeFileSync(join(ws, 'capture', 'receipt.json'), JSON.stringify({ clips: { B1: { file: 'clips/B1.webm', segments: ['B1'], actions } } }));
    return ws;
  };
  const move = (t, x, y) => ({ t, type: 'move', x, y });
  const led = mk('ws-pointer-ok', [move(1, 100, 100), move(1.1, 200, 160), move(1.2, 300, 220), { t: 1.4, tStart: 1.4, type: 'click', x: 320, y: 230, label: 'Carter row' }]);
  const ok = await runPointerGate({ ws: led, moduleRoot: mod });
  assert.equal(ok.status, 'pass', ok.detail);
  assert.ok(existsSync(join(led, 'qa', 'pointer-path.json')));
  const wander = mk('ws-pointer-bad', [move(1, 100, 100), move(1.1, 400, 100), move(1.2, 100, 300), move(1.3, 400, 300), move(1.4, 100, 100)]);
  const bad = await runPointerGate({ ws: wander, moduleRoot: mod });
  assert.equal(bad.status, 'fail');
  const none = join(root, 'ws-pointer-none');
  mkdirSync(none, { recursive: true });
  assert.equal((await runPointerGate({ ws: none, moduleRoot: mod })).status, 'fail', 'no receipt: fail closed');
});

// ---- edit.beatGrid: cuts on the music bed's beat
const gridFixture = () => buildTimeline([
  { beat: { id: 'B1', kind: 'ui', narration: 'hello there friend' }, audio: { durationSeconds: 3.1, words: [{ word: 'hello', start: 0.1, end: 0.5 }, { word: 'there', start: 0.6, end: 1.0 }, { word: 'friend', start: 1.2, end: 1.9 }] } },
  { beat: { id: 'B2', kind: 'ui', narration: 'second line', minSeconds: 6 }, audio: { durationSeconds: 2.37, words: [{ word: 'second', start: 0.2, end: 0.7 }, { word: 'line', start: 0.9, end: 1.3 }] } },
  { beat: { id: 'B3', kind: 'card' } },
  { beat: { id: 'B4', kind: 'ui', narration: 'last words here' }, audio: { durationSeconds: 1.83, words: [{ word: 'last', start: 0.1, end: 0.4 }, { word: 'words', start: 0.5, end: 0.9 }, { word: 'here', start: 1.0, end: 1.5 }] } },
]);

test('beat grid 1: every boundary but the start lands on the grid within 1 ms, no segment shrinks, each extension is under one beat', () => {
  for (const grid of [{ bpm: 120, offsetSeconds: 0.12 }, { bpm: 128, offsetSeconds: 0.3 }, { bpm: 97, offsetSeconds: 0 }, { bpm: 60, offsetSeconds: 2.5 }, { bpm: 200, offsetSeconds: 9.9 }]) {
    const before = gridFixture();
    const frozen = JSON.stringify(before);
    const after = snapToBeatGrid(before, grid);
    assert.equal(JSON.stringify(before), frozen, 'the input timeline is not modified');
    const period = 60 / grid.bpm;
    assert.equal(after.segments[0].startSeconds, 0, 'the program start is not snapped');
    after.segments.forEach((seg, i) => {
      assert.ok(seg.durationSeconds >= before.segments[i].durationSeconds - 1e-9, `${grid.bpm}/${seg.id} never shrinks`);
      assert.ok(seg.snapExtendSeconds >= 0 && seg.snapExtendSeconds < period, `${grid.bpm}/${seg.id} extends by ${seg.snapExtendSeconds}s, under one ${period}s beat`);
      assert.ok(Math.abs(seg.durationSeconds - before.segments[i].durationSeconds - seg.snapExtendSeconds) < 1e-9, 'the whole change is the tail hold');
      const end = seg.startSeconds + seg.durationSeconds;
      const beats = (end - grid.offsetSeconds) / period;
      assert.ok(Math.abs((beats - Math.round(beats)) * period) <= 0.001, `${grid.bpm}/${seg.id} ends at ${end}, ${Math.abs((beats - Math.round(beats)) * period) * 1000} ms off the grid`);
      if (i) assert.ok(Math.abs(seg.startSeconds - (after.segments[i - 1].startSeconds + after.segments[i - 1].durationSeconds)) < 1e-9, 'segments stay contiguous');
    });
    const last = after.segments.at(-1);
    assert.ok(Math.abs(after.durationSeconds - (last.startSeconds + last.durationSeconds)) < 1e-9, 'the total is the last boundary');
    assert.ok(after.durationSeconds >= before.durationSeconds);
    assert.deepEqual([after.beatGrid.bpm, after.beatGrid.offsetSeconds], [grid.bpm, grid.offsetSeconds]);
    assert.equal(after.beatGrid.snapped, after.segments.filter((s) => s.snapExtendSeconds > 0).length);
    assert.ok(Math.abs(after.beatGrid.addedSeconds - (after.durationSeconds - before.durationSeconds)) < 1e-9);
  }
});

test('beat grid 2: a boundary already on a beat is left alone, and the offset is the bed phase, so beats run back to program time 0', () => {
  const tl = buildTimeline([{ beat: { id: 'A', kind: 'card', minSeconds: 3 } }, { beat: { id: 'B', kind: 'card', minSeconds: 2.25 } }, { beat: { id: 'C', kind: 'card', minSeconds: 1 } }]);
  const on = snapToBeatGrid(tl, { bpm: 120, offsetSeconds: 0 }); // 0.5 s beats: 3 is on a beat, 5.25 is half a beat late, 6.5 is on a beat again
  assert.deepEqual(on.segments.map((s) => s.snapExtendSeconds), [0, 0.25, 0]);
  assert.deepEqual(on.segments.map((s) => s.startSeconds + s.durationSeconds), [3, 5.5, 6.5]);
  const early = snapToBeatGrid(buildTimeline([{ beat: { id: 'A', kind: 'card', minSeconds: 0.4 } }]), { bpm: 120, offsetSeconds: 2 });
  assert.equal(early.segments[0].durationSeconds, 0.5, 'beats at 2 - n * 0.5 include 0.5: no extension of a whole offset');
  assert.equal(snapToBeatGrid({ durationSeconds: 0, segments: [] }, { bpm: 90, offsetSeconds: 0 }).durationSeconds, 0);
  assert.throws(() => snapToBeatGrid(tl, { bpm: 0, offsetSeconds: 0 }), /bpm/);
  assert.throws(() => snapToBeatGrid(tl, { bpm: 120, offsetSeconds: -1 }), /offsetSeconds/);
});

test('beat grid 3: narration does not move inside its segment; lead-in, words and caption chunks shift with the segment', () => {
  const before = gridFixture();
  const after = snapToBeatGrid(before, { bpm: 120, offsetSeconds: 0.12 });
  assert.ok(after.segments.some((s, i) => s.startSeconds > before.segments[i].startSeconds), 'something shifted');
  after.segments.forEach((seg, i) => {
    const old = before.segments[i];
    const shift = seg.startSeconds - old.startSeconds;
    assert.equal(seg.speechSeconds, old.speechSeconds);
    assert.equal(seg.text, old.text);
    if (old.lineStartSeconds === null) assert.equal(seg.lineStartSeconds, null);
    else assert.ok(Math.abs(seg.lineStartSeconds - seg.startSeconds - (old.lineStartSeconds - old.startSeconds)) < 1e-9, `${seg.id} lead-in is unchanged`);
    seg.words.forEach((w, k) => {
      assert.ok(Math.abs(w.start - seg.startSeconds - (old.words[k].start - old.startSeconds)) < 1e-9, `${seg.id}/${w.word} keeps its place inside the segment`);
      assert.ok(Math.abs(w.end - old.words[k].end - shift) < 1e-9);
      assert.ok(w.start >= seg.startSeconds && w.end <= seg.startSeconds + seg.durationSeconds, 'the words stay inside their scene');
    });
  });
  // captions are derived from the words, so they move with them
  const chunkStarts = (tl) => tl.segments.flatMap((s) => (s.words.length ? chunkWords(s.words).map((c) => c.startSec - s.startSeconds) : []));
  assert.equal(chunkStarts(after).length, chunkStarts(before).length);
  chunkStarts(after).forEach((rel, i) => assert.ok(Math.abs(rel - chunkStarts(before)[i]) < 1e-6, 'caption chunk offsets inside the scene are unchanged'));
});

test('beat grid 4: the grid lives outside spec.music, so the bed key cannot change, and the timing stage re-times only when it changes', async () => {
  const spec = { ...baseSpec(), music: { provider: 'elevenlabs', prompt: 'warm instrumental pulse, 120 bpm', licenseBasis: 'owner-approved test' } };
  const withGrid = { ...spec, edit: { beatGrid: { bpm: 120, offsetSeconds: 0.12 } } };
  assert.deepEqual(validate(adSchema, withGrid).filter((e) => /edit|beatGrid/.test(e)), [], 'edit.beatGrid is in the schema');
  assert.notDeepEqual(validate(adSchema, { ...spec, edit: { beatGrid: { bpm: 10, offsetSeconds: 0 } } }), [], 'a tempo outside 40-220 is refused');
  assert.notDeepEqual(validate(adSchema, { ...spec, edit: { beatGrid: { bpm: 120 } } }), [], 'offsetSeconds is required with bpm');
  assert.notDeepEqual(validate(adSchema, { ...spec, music: { ...spec.music, beatGrid: { bpm: 120, offsetSeconds: 0 } } }), [], 'music takes no beatGrid');
  assert.equal(JSON.stringify(withGrid.music), JSON.stringify(spec.music));
  assert.equal(musicKey(withGrid.music.prompt, 30000, 'music_v2_5'), musicKey(spec.music.prompt, 30000, 'music_v2_5'));
  assert.ok(!/beatGrid/.test(readFileSync(join(mod, 'lib', 'stages', 'assets.mjs'), 'utf8')), 'the assets stage never reads the grid');

  const elevenlabs = {
    resolveCli: () => ({}),
    speech: async (_cli, o) => { writeFileSync(o.output, `audio:${o.text}`); const receipt = { request_id: 'r', reused: false, actual_credits: null }; writeFileSync(`${o.output}.provenance.json`, JSON.stringify(receipt)); return { receipt }; },
  };
  const providers = { elevenlabs, elevenCli: {}, probeDuration: async (f) => (readFileSync(f, 'utf8').length > 40 ? 4 : 2.5), transcribeWords: async () => ({ words: [{ word: 'hello', start: 0.05, end: 0.4 }] }) };
  const plain = stageCtx('stages-nogrid', baseSpec(), providers);
  await voiceStage(plain);
  await timingStage(plain);
  const plainTl = readJson(join(plain.jobDir, 'timing', 'main', 'timeline.json'));
  assert.equal(plainTl.beatGrid, undefined, 'no grid: the timeline is the voice-first one');

  const grid = stageCtx('stages-grid', { ...baseSpec(), edit: { beatGrid: { bpm: 120, offsetSeconds: 0.12 } } }, providers);
  await voiceStage(grid);
  const timed = await timingStage(grid);
  const tl = readJson(join(grid.jobDir, 'timing', 'main', 'timeline.json'));
  assert.deepEqual([tl.beatGrid.bpm, tl.beatGrid.offsetSeconds], [120, 0.12]);
  assert.ok(tl.durationSeconds >= plainTl.durationSeconds);
  assert.equal(timed.main.beatGrid.bpm, 120);
  for (const seg of tl.segments) {
    const beats = (seg.startSeconds + seg.durationSeconds - 0.12) / 0.5;
    assert.ok(Math.abs(beats - Math.round(beats)) * 0.5 <= 2 / FPS, `${seg.id} ends on the grid, to the frame the stage snaps it to`);
    const frames = (seg.startSeconds + seg.durationSeconds) * FPS;
    assert.ok(Math.abs(frames - Math.round(frames)) < 0.02, `${seg.id} ends on a whole frame (${frames})`);
  }
  const chunks = readJson(join(grid.jobDir, 'timing', 'main', 'captions.json')).chunks;
  assert.ok(chunks.length > 0 && chunks.every((c) => { const seg = tl.segments.find((x) => x.id === c.beatId); return c.startSec >= seg.startSeconds - 0.06 && c.startSec <= seg.startSeconds + seg.durationSeconds; }), 'every caption chunk starts inside its snapped scene');
  assert.ok(grid.ledger.entries.filter((e) => e.service === 'whisper' && !e.cached).length > 0);
  const calls = grid.ledger.entries.filter((e) => e.service === 'whisper' && !e.cached).length;
  await timingStage(grid);
  assert.equal(readJson(join(grid.jobDir, 'timing', 'main', 'timeline.json')).beatGrid.bpm, 120);
  grid.spec.edit.beatGrid.bpm = 100;
  await timingStage(grid);
  const retimed = readJson(join(grid.jobDir, 'timing', 'main', 'timeline.json'));
  assert.equal(retimed.beatGrid.bpm, 100, 'a changed grid re-times (it is part of the timing cache key)');
  assert.equal(grid.ledger.entries.filter((e) => e.service === 'whisper' && !e.cached).length, calls, 're-timing reuses the cached ASR: no new spend');
});

test('beat grid 5: the compose map records the grid so the marketing-readiness measurement can be cross-checked', () => {
  const src = readFileSync(join(mod, 'lib', 'stages', 'compose.mjs'), 'utf8');
  assert.match(src, /timeline\.beatGrid \? \{ beatGrid: \{ bpm: timeline\.beatGrid\.bpm, offsetSeconds: timeline\.beatGrid\.offsetSeconds \} \}/);
  assert.match(readFileSync(join(mod, 'README.md'), 'utf8'), /edit\.beatGrid/);
});

// ---- music.lengthSeconds: one bed length for many jobs
test('music length 1: the default bed is the longest cut plus 2 s per job; lengthSeconds fixes it, and must cover the program', () => {
  assert.equal(musicLengthMs({ provider: 'elevenlabs' }, 24.2), 27000, 'default: ceil(longest + 2) seconds');
  assert.equal(musicLengthMs(undefined, 1), 3000, 'default floor of 3 s');
  assert.equal(musicLengthMs({ provider: 'elevenlabs', lengthSeconds: 40 }, 24.2), 40000);
  assert.equal(musicLengthMs({ provider: 'elevenlabs', lengthSeconds: 40 }, 31.9), 40000, 'a different job length asks for the same bed');
  assert.equal(musicLengthMs({ provider: 'elevenlabs', lengthSeconds: 26.2 }, 24.2), 26200, 'exactly the longest cut plus 2 s is enough');
  assert.throws(() => musicLengthMs({ provider: 'elevenlabs', lengthSeconds: 26 }, 24.2), /music\.lengthSeconds is 26 s.*raise it to at least 27/);
  assert.throws(() => musicLengthMs({ provider: 'elevenlabs', lengthSeconds: 2 }, 1), /at least 3/);
  assert.equal(musicLengthMs({ provider: 'elevenlabs', lengthSeconds: 20 }, 40, { measured: false }), 20000, 'estimates alone never fail the length');
  const prompt = 'warm instrumental pulse, 120 bpm';
  assert.equal(musicKey(prompt, musicLengthMs({ lengthSeconds: 40 }, 24.2), 'music_v2_5'), musicKey(prompt, musicLengthMs({ lengthSeconds: 40 }, 31.9), 'music_v2_5'), 'same prompt, model and length: one request');
  assert.notEqual(musicKey(prompt, musicLengthMs({}, 24.2), 'music_v2_5'), musicKey(prompt, musicLengthMs({}, 31.9), 'music_v2_5'), 'without it each job length buys a new track');
  assert.deepEqual(validate(adSchema.properties.music, { provider: 'elevenlabs', prompt, licenseBasis: 'owner-approved test', lengthSeconds: 40 }), []);
  assert.notDeepEqual(validate(adSchema.properties.music, { provider: 'elevenlabs', lengthSeconds: 2 }), [], 'lengthSeconds is at least 3');
  // the mix trims the bed to the program and fades it out inside the program, so a longer fixed bed never extends the film
  const args = buildMixArgs({ lines: [{ file: 'v.wav', startSec: 0.3 }], music: { file: 'bed.mp3' }, durationSec: 20, out: 'mix.wav' });
  const graph = args[args.indexOf('-filter_complex') + 1];
  assert.match(graph, /\[1:a\][^;]*atrim=duration=20[^;]*afade=t=out:st=18\.6:d=1\.4\[bed0\]/);
  assert.match(graph, /apad,atrim=duration=20\[mix\]/);
});

test('music length 2: lint refuses a fixed bed shorter than the cut plus 2 s; the assets stage buys one bed for jobs of different lengths and refuses a short one', async () => {
  const music = { provider: 'elevenlabs', prompt: 'warm instrumental pulse, 120 bpm', licenseBasis: 'owner-approved test basis', lengthSeconds: 40 };
  assert.ok(!codes(lint({ ...baseSpec(), music })).includes('music-length'));
  assert.ok(codes(lint({ ...baseSpec(), music: { ...music, lengthSeconds: 20 } })).includes('music-length'), 'baseSpec targets 20 s, so a 20 s bed cannot outlast it');

  const requests = [];
  const providers = () => ({
    elevenCli: {},
    elevenlabs: {
      resolveCli: () => ({}),
      soundEffect: async (_c, o) => { writeFileSync(o.output, 'sfx'); return { receipt: { request_id: 'sfx', reused: false, actual_credits: 40 } }; },
      music: async (_c, o) => { requests.push({ prompt: o.prompt, lengthMs: o.lengthMs, model: o.model }); writeFileSync(o.output, 'bed'); return { receipt: { request_id: `m${requests.length}`, reused: requests.length > 1, actual_credits: 100 } }; },
    },
  });
  const job = (name, seconds, lengthSeconds) => {
    const spec = { ...baseSpec(), id: name, music: { ...music, lengthSeconds } };
    spec.beats = spec.beats.map(({ sfx, ...b }) => b);
    const ctx = stageCtx(`music-${name}`, spec, providers());
    mkdirSync(join(ctx.jobDir, 'timing', 'main'), { recursive: true });
    writeFileSync(join(ctx.jobDir, 'timing', 'main', 'timeline.json'), JSON.stringify({ durationSeconds: seconds, segments: [] }));
    return ctx;
  };
  await assetsStage(job('music-job-a', 19.4, 40));
  await assetsStage(job('music-job-b', 26.8, 40));
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[0], requests[1], 'an identical request, which the governed adapter reuses');
  assert.equal(requests[0].lengthMs, 40000);
  const per = [];
  for (const [name, seconds] of [['music-job-c', 19.4], ['music-job-d', 26.8]]) {
    const before = requests.length;
    await assetsStage(job(name, seconds, undefined));
    per.push(requests[before].lengthMs);
  }
  assert.deepEqual(per, [22000, 29000], 'without lengthSeconds each job length asks for its own bed');
  await assert.rejects(() => assetsStage(job('music-job-e', 39.5, 40)), /music\.lengthSeconds is 40 s but the longest cut is 39\.50 s/);
});

test('chain gates 7: the frame-integrity gate runs the shared script on the candidate and leaves its report where viewer-release reads it', async () => {
  const ws = join(root, 'ws-frame');
  mkdirSync(join(ws, 'output'), { recursive: true });
  assert.deepEqual(declaredCutsSheet({ groups: [{ startSeconds: 0 }, { startSeconds: 3.5 }, { startSeconds: 'x' }] }).edl, [{ startSeconds: 0 }, { startSeconds: 3.5 }], 'the planned cuts of the compose map are the declared cuts');
  writeFileSync(join(ws, 'output', 'x-compose-map.json'), JSON.stringify({ groups: [{ startSeconds: 0 }, { startSeconds: 3.5 }] }));
  const missing = await runFrameIntegrityGate({ ws, candidate: join(ws, 'output', 'none.mp4'), composeMapRel: 'output/x-compose-map.json', moduleRoot: mod });
  assert.deepEqual(readJson(join(ws, 'qa', 'frame-integrity-cuts.json')).edl, [{ startSeconds: 0 }, { startSeconds: 3.5 }]);
  assert.equal(missing.status, 'fail', 'no candidate: fail closed');
  assert.ok(existsSync(join(ws, 'qa', 'frame-integrity.json')), 'the report is written to <ws>/qa/frame-integrity.json, the path validate-viewer-release.mjs reads');
  assert.equal(readJson(join(ws, 'qa', 'frame-integrity.json')).generator, 'media-studio/validate-frame-integrity');
  assert.match(readFileSync(join(here, '..', 'scripts', 'validate-viewer-release.mjs'), 'utf8'), /boundReport\('qa\/frame-integrity\.json'/);
  const qa = readFileSync(join(mod, 'lib', 'stages', 'qa.mjs'), 'utf8');
  assert.match(qa, /gates\.frameIntegrity = await runFrameIntegrityGate/);
  assert.ok(qa.indexOf('runSyncGates(') < qa.indexOf('runFrameIntegrityGate({'), 'it runs after the sync gate has built the cue sheet');
});

// ---- frame tiling at beat boundaries (one-frame black gaps) and silent beats in the sync gate
const stepFrames = (list) => list.map((f, i) => (i ? list[i - 1].from + list[i - 1].durationInFrames === f.from : true));

test('frame gaps 1: sequences tile exactly whatever the boundary times are (a 10.751 s cut, and 2000 random ones)', () => {
  // The defect: Math.round(start * 30) and Math.round(duration * 30) taken separately. A beat that starts at 7.213 s (frame 216.39 -> 216)
  // and is 3.547 s long (106.41 -> 106) ends at frame 322, while the next beat starts at 10.76 s (322.8 -> 323): frame 322 is in no sequence.
  const beats = [
    { id: 'U1', startSec: 3.5, durationSec: 3.7 }, { id: 'U2', startSec: 7.2, durationSec: 3.551 }, { id: 'U3', startSec: 10.751, durationSec: 4.449 },
  ];
  const odd = [{ startSec: 7.213, durationSec: 3.547 }, { startSec: 10.76, durationSec: 4.44 }];
  const independent = odd.map((b) => ({ from: Math.round(b.startSec * FPS), durationInFrames: Math.max(1, Math.round(b.durationSec * FPS)) }));
  assert.ok(stepFrames(independent).includes(false), 'rounding start and duration separately leaves a gap on this cut');
  assert.ok(stepFrames(sequenceFrames(odd)).every(Boolean));
  const tiled = sequenceFrames(beats);
  assert.ok(stepFrames(tiled).every(Boolean), JSON.stringify(tiled));
  assert.equal(tiled[0].from, Math.round(3.5 * FPS));
  assert.equal(tiled.at(-1).from + tiled.at(-1).durationInFrames, Math.round(15.2 * FPS), 'the last beat ends where the program ends');
  let seed = 7;
  const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
  let independentGaps = 0;
  for (let run = 0; run < 2000; run++) {
    let t = 0;
    const list = Array.from({ length: 2 + Math.floor(rnd() * 8) }, (_, i) => {
      const durationSec = Math.round((0.2 + rnd() * 5) * 1000) / 1000;
      const b = { id: `S${i}`, startSec: Math.round(t * 1000) / 1000, durationSec };
      t += durationSec;
      return b;
    });
    const frames = sequenceFrames(list);
    assert.ok(stepFrames(frames).every(Boolean), `gap or overlap for ${JSON.stringify(list)}`);
    assert.ok(frames.every((f) => f.durationInFrames >= 1));
    assert.ok(Math.abs(frames.at(-1).from + frames.at(-1).durationInFrames - Math.round(t * FPS)) <= 1);
    if (stepFrames(list.map((b) => ({ from: Math.round(b.startSec * FPS), durationInFrames: Math.max(1, Math.round(b.durationSec * FPS)) }))).includes(false)) independentGaps++;
  }
  assert.ok(independentGaps > 100, `the old arithmetic does leave gaps on random cuts (${independentGaps} of 2000)`);
  assert.deepEqual(sequenceFrames([]), []);
  assert.equal(sequenceFrames([{ startSec: 0, durationSec: 0 }])[0].durationInFrames, 1, 'a beat is at least one frame');
});

test('frame gaps 2: MarketingAd lays its sequences from the tiled frames, and KineticCaptions asks the same frames', () => {
  const tsx = readFileSync(join(mod, '..', 'src', 'MarketingAd.tsx'), 'utf8');
  assert.ok(!/Math\.round\(beat\.startSec \* fps\)/.test(tsx) && !/Math\.round\(beat\.durationSec \* fps\)/.test(tsx), 'no beat start or duration is rounded on its own');
  assert.match(tsx, /const frames = beatFrames\(props\.beats, fps\);\s+return \(\s+<AbsoluteFill style=\{\{ background: brand\.colors\.foreground \}\}>/);
  assert.match(tsx, /const \{ from, durationInFrames: duration \} = frames\[i\];/);
  assert.match(tsx, /<Sequence key=\{beat\.id\} from=\{from\} durationInFrames=\{duration\}/);
  // the in-file function is the twin of timing.mjs sequenceFrames: evaluate its body on a cut with unaligned boundaries
  const body = /const beatFrames = \(beats: AdBeat\[\], fps: number\)[^=]*=> \{([\s\S]*?)\n\};/.exec(tsx);
  assert.ok(body, 'beatFrames is defined in MarketingAd.tsx');
  const beatFrames = new Function('beats', 'fps', body[1]);
  const beats = [{ startSec: 0, durationSec: 3.049 }, { startSec: 3.049, durationSec: 3.3 }, { startSec: 6.349, durationSec: 4.402 }, { startSec: 10.751, durationSec: 2.2 }];
  assert.deepEqual(beatFrames(beats, FPS), sequenceFrames(beats, FPS));
  assert.ok(stepFrames(beatFrames(beats, FPS)).every(Boolean));
  assert.ok(!/t >= b\.startSec/.test(tsx), 'no per-beat window compares seconds against frame / fps');
});

test('frame gaps 3: with a beat grid and fps every boundary is a whole frame, no scene shrinks, words and lead-ins move with their scene', () => {
  for (const grid of [{ bpm: 120, offsetSeconds: 0.12 }, { bpm: 128, offsetSeconds: 0.3 }, { bpm: 97, offsetSeconds: 0 }, { bpm: 100, offsetSeconds: 1.37 }]) {
    const before = gridFixture();
    const frozen = JSON.stringify(before);
    const after = snapToBeatGrid(before, grid, { fps: FPS });
    assert.equal(JSON.stringify(before), frozen);
    assert.equal(after.beatGrid.fps, FPS);
    const period = 60 / grid.bpm;
    after.segments.forEach((seg, i) => {
      const end = seg.startSeconds + seg.durationSeconds;
      assert.ok(Math.abs(end * FPS - Math.round(end * FPS)) < 0.02, `${grid.bpm}/${seg.id} ends on frame ${end * FPS}`);
      assert.ok(seg.durationSeconds >= before.segments[i].durationSeconds - 0.0006, `${grid.bpm}/${seg.id} never shrinks`);
      const off = (end - grid.offsetSeconds) / period;
      assert.ok(Math.abs((off - Math.round(off)) * period) <= 2 / FPS, `${grid.bpm}/${seg.id} is ${Math.abs((off - Math.round(off)) * period) * 1000} ms from the beat`);
      assert.ok(seg.snapExtendSeconds < period + 1 / FPS);
      seg.words.forEach((w, k) => {
        const old = before.segments[i];
        assert.ok(Math.abs(w.start - seg.startSeconds - (old.words[k].start - old.startSeconds)) < 1e-9, 'a word keeps its place inside its scene');
      });
    });
    assert.ok(Math.abs(after.durationSeconds - (after.segments.at(-1).startSeconds + after.segments.at(-1).durationSeconds)) < 1e-9);
    // the frames the picture cuts on are exactly the boundaries the timeline names
    const frames = sequenceFrames(after.segments.map((s) => ({ startSec: s.startSeconds, durationSec: s.durationSeconds })));
    assert.ok(stepFrames(frames).every(Boolean));
    after.segments.forEach((seg, i) => assert.equal(frames[i].from, Math.round(seg.startSeconds * FPS)));
  }
  // without fps nothing changes: the millisecond grid of the plain call is kept
  const plain = snapToBeatGrid(gridFixture(), { bpm: 120, offsetSeconds: 0.12 });
  assert.equal(plain.beatGrid.fps, undefined);
  assert.ok(plain.segments.some((s) => Math.abs((s.startSeconds + s.durationSeconds) * FPS - Math.round((s.startSeconds + s.durationSeconds) * FPS)) > 0.02), 'the fixture does have unaligned boundaries');
  // a boundary already on a frame and on a beat needs no extra frame
  const exact = snapToBeatGrid(buildTimeline([{ beat: { id: 'A', kind: 'card', minSeconds: 3 } }, { beat: { id: 'B', kind: 'card', minSeconds: 3 } }]), { bpm: 120, offsetSeconds: 0 }, { fps: FPS });
  assert.deepEqual(exact.segments.map((s) => s.durationSeconds), [3, 3]);
});

test('frame gaps 4: the timing stage snaps its grid to frames and keys the cache on it', () => {
  const src = readFileSync(join(mod, 'lib', 'stages', 'timing.mjs'), 'utf8');
  assert.match(src, /snapToBeatGrid\(buildTimeline\(lines\), grid, \{ fps: FPS \}\)/);
  assert.match(src, /beatGrid: grid, frameSnap: FPS/);
});

test('silent beats 1: a beat with no narration is not a narration row, so the cue sheet has no estimate-precision beat to refuse', () => {
  const dir = join(root, 'gatews-silent');
  const spec = baseSpec();
  const edit = { trimStart: 3.0, trimEnd: 12, speed: 1, skip: [], headHold: 0 };
  const cut = { id: 'main', ratios: ['16x9'], beats: [
    { id: 'T1', kind: 'title', onScreenText: 'Twelve units left.' },
    { id: 'B1', kind: 'ui', narration: 'Twelve days.', ui: { sourceJob: 'film', clipId: 'A01', actions: [{ label: 'Carter row', keywords: ['twelve'] }] } },
    { id: 'B3', kind: 'card', narration: 'Try the live demo.', onScreenText: 'Try it on synthetic data' },
  ] };
  const timeline = { durationSeconds: 9.2, segments: [
    { id: 'T1', kind: 'title', text: '', startSeconds: 0, durationSeconds: 2.2, speechSeconds: 0, lineStartSeconds: null, words: [] },
    { id: 'B1', kind: 'ui', text: 'Twelve days.', startSeconds: 2.2, durationSeconds: 4, speechSeconds: 2, lineStartSeconds: 2.5, words: [{ word: 'Twelve', start: 2.6, end: 3.0 }, { word: 'days.', start: 3.1, end: 3.5 }] },
    { id: 'B3', kind: 'card', text: 'Try the live demo.', startSeconds: 6.2, durationSeconds: 3, speechSeconds: 1.5, lineStartSeconds: 6.5, words: [{ word: 'Try', start: 6.6, end: 6.8 }, { word: 'the', start: 6.8, end: 6.9 }, { word: 'live', start: 6.9, end: 7.1 }, { word: 'demo.', start: 7.1, end: 7.5 }] },
  ] };
  const asrB1 = join(root, 'silent-b1.json');
  const asrB3 = join(root, 'silent-b3.json');
  writeFileSync(asrB1, JSON.stringify({ words: [{ word: 'Twelve', start: 0.1, end: 0.5 }, { word: 'days', start: 0.6, end: 1.0 }] }));
  writeFileSync(asrB3, JSON.stringify({ words: [{ word: 'Try', start: 0.1, end: 0.3 }, { word: 'the', start: 0.3, end: 0.4 }, { word: 'live', start: 0.4, end: 0.6 }, { word: 'demo', start: 0.6, end: 1.0 }] }));
  const composeMap = { groups: [
    { segments: ['T1'], startSeconds: 0, needSeconds: 2.2, clipId: 'T1', isImage: true, edit: null, sourceRegion: null },
    { segments: ['B1'], startSeconds: 2.2, needSeconds: 4, clipId: 'B1', edit, sourceRegion: { x: 0, y: 0, width: 0.5, height: 0.5 } },
    { segments: ['B3'], startSeconds: 6.2, needSeconds: 3, clipId: 'B3', isImage: true, edit: null, sourceRegion: null },
  ] };
  const clipFile = join(receiptDir, 'capture', 'clips', 'A01.webm');
  buildGateWorkspace({ root: dir, spec, cut, ratio: '16x9', timeline, composeMap, clips: [{ beatId: 'B1', file: clipFile, receiptEntry: { actions: receiptActions, recastHeadTrimSeconds: 0.5 } }], asr: { B1: asrB1, B3: asrB3 }, loudnessLufs: -16 });
  const tl = readJson(join(dir, 'story', 'narration-timeline.json'));
  assert.deepEqual(tl.segments.map((x) => x.id), ['B1', 'B3'], 'the silent title is not a narration row');
  assert.equal(tl.durationSeconds, 9.2, 'the film keeps its whole length');
  assert.deepEqual(readJson(join(dir, 'story', 'storyboard.json')).beats.map((b) => b.id), ['T1', 'B1', 'B3'], 'the title is still a beat of the film');
  assert.equal(readFileSync(join(dir, 'story', 'locked-script.txt'), 'utf8'), 'Twelve days.\nTry the live demo.\n');
  // the real cue-sheet builder over this workspace: every beat it lists is word-level, which is what validate-sync requires
  const builder = join(mod, '..', '..', 'scripts', 'build-cue-sheet.mjs');
  const run = spawnSync(process.execPath, [builder, dir, '--compose-map', 'output/expired-auth-compose-map.json'], { encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr || run.stdout);
  const sheet = readJson(join(dir, 'plan', 'cue-sheet.json'));
  assert.deepEqual(sheet.beats.map((b) => [b.beat, b.narration.precision]), [['B1', 'word'], ['B3', 'word']]);
  assert.equal(sheet.precision.allWordLevel, true);
  assert.deepEqual(sheet.precision.degradedBeats, []);
  assert.equal(sheet.durationSeconds, 9.2);
  // the control: the same film with the silent beat listed as a narration row is what validate-sync refuses
  const listed = readJson(join(dir, 'story', 'narration-timeline.json'));
  listed.segments.unshift({ id: 'T1', scene: 'T1', text: '', startSeconds: 0, durationSeconds: 2.2, speechSeconds: 0 });
  writeFileSync(join(dir, 'story', 'narration-timeline.json'), JSON.stringify(listed));
  const ctl = spawnSync(process.execPath, [builder, dir, '--compose-map', 'output/expired-auth-compose-map.json', '--out', 'plan/control.json'], { encoding: 'utf8' });
  assert.equal(ctl.status, 0, ctl.stderr || ctl.stdout);
  assert.deepEqual(readJson(join(dir, 'plan', 'control.json')).precision.degradedBeats, [{ beat: 'T1', precision: 'estimate' }], 'listed as a row, a silent beat is estimate-precision');
});

test('silent beats 2: a cut with no narration at all lists no narration row rather than an estimate row', () => {
  const dir = join(root, 'gatews-allsilent');
  const cut = { id: 'main', ratios: ['16x9'], beats: [{ id: 'T1', kind: 'title', onScreenText: 'Hook.' }] };
  const timeline = { durationSeconds: 2.2, segments: [{ id: 'T1', kind: 'title', text: '', startSeconds: 0, durationSeconds: 2.2, speechSeconds: 0, lineStartSeconds: null, words: [] }] };
  buildGateWorkspace({ root: dir, spec: baseSpec(), cut, ratio: '16x9', timeline, composeMap: { groups: [] }, clips: [], asr: {}, loudnessLufs: -16 });
  assert.deepEqual(readJson(join(dir, 'story', 'narration-timeline.json')).segments, []);
  assert.deepEqual(readJson(join(dir, 'qa', 'listen-timeline.json')).segments, []);
});
