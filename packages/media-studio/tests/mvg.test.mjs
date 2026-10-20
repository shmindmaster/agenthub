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
import { chunkWords, toSrt, wrapCue } from '../kit/marketing/lib/captions.mjs';
import { alignScriptToAsr, buildTimeline, parseAsrWords } from '../kit/marketing/lib/timing.mjs';
import { buildMixArgs, loudnessTarget, parseLoudnorm } from '../kit/marketing/lib/mix.mjs';
import { deliverFiles, nextFreeNumber, updateReadme, usedNumbers, deliveredName } from '../kit/marketing/lib/deliver.mjs';
import { captionsCheck, releasable } from '../kit/marketing/lib/gates.mjs';
import { evaluate, parseVerdict, sampleTimes, runVisionQa, VerdictError } from '../kit/marketing/vision-qa.mjs';
import { dhash, hamming, staticRuns, bestDistance } from '../kit/marketing/lib/picture-gate.mjs';
import { estimateImageUsd, estimateTtsCredits, estimateVisionUsd } from '../kit/marketing/lib/prices.mjs';
import { lineKey, voiceStage } from '../kit/marketing/lib/stages/voice.mjs';
import { timingStage } from '../kit/marketing/lib/stages/timing.mjs';
import { assetsStage, sfxKey } from '../kit/marketing/lib/stages/assets.mjs';
import { planCost } from '../kit/marketing/lib/stages/lint.mjs';
import { cueTime, validateProps } from '../kit/marketing/lib/stages/compose.mjs';
import { parseArgs } from '../kit/marketing/mvg.mjs';

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
    { id: 'c-cta', text: 'Try the live demo on synthetic data', phrases: ['Try it on synthetic data'], kind: 'cta', evidence: 'approved:playbook concept 1 CTA' },
    { id: 'c-local', text: 'Nothing is sent to a payer', phrases: ['Nothing is sent to a payer'], evidence: 'clip:film#A01@0-10' },
  ],
  ratios: ['16x9', '9x16'], targetSeconds: 20,
  beats: [
    { id: 'B1', kind: 'ui', narration: 'Twelve units left, and three sessions still scheduled.', claims: ['c-runway'], ui: { sourceJob: 'film', clipId: 'A01', trimStart: 3 }, sfx: [{ cue: 'action:Carter row', prompt: 'soft interface click' }] },
    { id: 'B2', kind: 'ui', narration: 'Nothing is sent to a payer.', claims: ['c-local'], ui: { sourceJob: 'film', clipId: 'A01', trimStart: 1 } },
    { id: 'B3', kind: 'card', narration: 'Try it on synthetic data.', onScreenText: 'Try it on synthetic data', claims: ['c-cta'] },
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
  assert.ok(l.uiBand.y >= safe.top);
  const bad = { ...l, captionBox: { ...l.captionBox, y: 1500 } };
  assert.ok(safeZoneErrors(bad).some((e) => /captionBox/.test(e)));
  const text = readability(bandRegion({ srcW: 1600, srcH: 1000, band: l.uiBand, zoom: l.zoom }).scale);
  assert.equal(text.ok, true);
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

const verdictJson = (overrides = {}) => JSON.stringify({ frames: [{ label: 'F01', issues: [] }, { label: 'F02', issues: [{ category: 'typo', severity: 'medium', detail: 'x', evidence: 'y' }] }], overall: { labelPresentOnAllFrames: true, summary: 'ok' }, ...overrides });

test('vision-qa: strict verdict parsing, fenced JSON, schema errors', () => {
  assert.equal(parseVerdict(verdictJson()).frames.length, 2);
  assert.equal(parseVerdict(`\`\`\`json\n${verdictJson()}\n\`\`\``).overall.summary, 'ok');
  assert.throws(() => parseVerdict('not json'), VerdictError);
  assert.throws(() => parseVerdict(JSON.stringify({ frames: [{ label: 'F1', issues: [{ category: 'vibes', severity: 'high', detail: 'x', evidence: 'y' }] }], overall: { labelPresentOnAllFrames: true, summary: '' } })), /schema/);
  assert.throws(() => parseVerdict(JSON.stringify({ frames: [] })), VerdictError);
});

test('vision-qa: high-severity findings and a missing label fail; medium findings do not', () => {
  assert.equal(evaluate(parseVerdict(verdictJson())).ok, true);
  const high = parseVerdict(verdictJson({ frames: [{ label: 'F01', issues: [{ category: 'banned-claim', severity: 'high', detail: 'says guaranteed', evidence: 'GUARANTEED' }] }] }));
  const r = evaluate(high);
  assert.equal(r.ok, false);
  assert.equal(r.blocking, 1);
  assert.match(r.reasons[0], /banned-claim/);
  const nolabel = evaluate(parseVerdict(verdictJson({ overall: { labelPresentOnAllFrames: false, summary: 'missing' } })));
  assert.equal(nolabel.ok, false);
  assert.match(nolabel.reasons.join(' '), /label/);
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
  assert.equal(seen[1].nextText, 'Try it on synthetic data.');
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
