// Synthetic regression tests. No provider, GPU, encode or library delivery.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runPipeline, selectedStages, parseArgs } from '../kit/marketing/mvg.mjs';
import { reserveCandidate, candidatePaths, verifiedCandidate, selectedCuts } from '../kit/marketing/lib/candidate.mjs';
import { renderCaptions } from '../kit/marketing/lib/stages/compose.mjs';
import { deliverStage } from '../kit/marketing/lib/stages/deliver.mjs';
import { fileSha } from '../kit/marketing/lib/util.mjs';
import { forcedWordOnsets, measureWordSync } from '../kit/screencast/sync-lib.mjs';
import { runVisionQa } from '../kit/marketing/vision-qa.mjs';
import { localVisionJson, visionEndpoint } from '../kit/marketing/lib/providers/local.mjs';

const root = mkdtempSync(join(tmpdir(), 'candidate-qa-'));
test.after(() => rmSync(root, { recursive: true, force: true }));
const write = (p, value) => writeFileSync(p, JSON.stringify(value));

test('QA and deliver stage selection cannot re-enter compose, even with force or stale upstream inputs', async () => {
  for (const name of ['qa', 'deliver']) {
    const calls = [];
    const stages = ['lint', 'voice', 'timing', 'assets', 'capture', 'compose', 'qa', 'deliver'].map((n) => [n, () => { calls.push(n); if (n !== name) throw new Error('upstream must not run'); }]);
    await runPipeline({ flags: { stage: name, force: true }, log() {} }, stages);
    assert.deepEqual(calls, [name]);
  }
  assert.deepEqual(selectedStages({ stage: 'compose' }), ['compose']);
  assert.throws(() => selectedStages({}), /explicit/);
  assert.throws(() => selectedStages({ stage: 'all' }), /explicit/);
});

test('compose candidate identity is mandatory and exclusive; force cannot replace reviewed bytes', () => {
  const ctx = { jobDir: join(root, 'exclusive'), flags: {} };
  assert.throws(() => reserveCandidate(ctx), /candidate-id/);
  ctx.flags = { candidateId: '../escape' };
  assert.throws(() => reserveCandidate(ctx), /candidate-id/);
  ctx.flags = { candidateId: 'cut-a' };
  const dir = reserveCandidate(ctx);
  writeFileSync(join(dir, 'reviewed.mp4'), 'reviewed');
  ctx.flags.force = true;
  assert.throws(() => reserveCandidate(ctx), /EEXIST/);
  assert.equal(readFileSync(join(dir, 'reviewed.mp4'), 'utf8'), 'reviewed');
  assert.throws(() => candidatePaths(ctx, '../../escape'), /ratio/);
});

test('named candidates reject missing, swapped, or changed hashes and wrong receipt ids', () => {
  const ctx = { jobDir: join(root, 'binding'), flags: { candidateId: 'one' } };
  reserveCandidate(ctx);
  const paths = candidatePaths(ctx, '9x16');
  mkdirSync(paths.dir);
  writeFileSync(paths.ad, 'accepted');
  assert.throws(() => verifiedCandidate(ctx, '9x16'), /receipt/);
  const sha256 = fileSha(paths.ad);
  write(join(paths.dir, 'candidate.json'), { id: 'other', sha256 });
  assert.throws(() => verifiedCandidate(ctx, '9x16'), /id/);
  write(join(paths.dir, 'candidate.json'), { id: 'one', sha256 });
  assert.equal(verifiedCandidate(ctx, '9x16').sha256, sha256);
  writeFileSync(paths.ad, 'changed');
  assert.throws(() => verifiedCandidate(ctx, '9x16'), /SHA-256/);
  ctx.flags = { candidateId: 'import', candidate: paths.ad };
  assert.throws(() => verifiedCandidate(ctx, '9x16'), /candidate-sha256/);
  assert.throws(() => selectedCuts(ctx, [{ ratios: ['9x16'] }]), /--ratio/);
  ctx.flags.candidateSha256 = fileSha(paths.ad);
  assert.throws(() => verifiedCandidate(ctx, '9x16'), /--qa-dir/);
  ctx.flags.composeDir = paths.dir; ctx.flags.qaDir = join(ctx.jobDir, 'qa');
  assert.throws(() => verifiedCandidate(ctx, '9x16'), /outside/);
  ctx.flags.qaDir = `${ctx.jobDir}-qa`;
  assert.equal(verifiedCandidate(ctx, '9x16').sha256, ctx.flags.candidateSha256);
});

test('delivery refuses a forged top-level pass without per-gate bindings', async () => {
  const ctx = { jobDir: join(root, 'delivery'), flags: { candidateId: 'one' }, spec: { ratios: ['9x16'], beats: [] } };
  reserveCandidate(ctx);
  const p = candidatePaths(ctx, '9x16');
  mkdirSync(p.dir); mkdirSync(p.qa, { recursive: true });
  writeFileSync(p.ad, 'accepted');
  write(join(p.dir, 'candidate.json'), { id: 'one', sha256: fileSha(p.ad) });
  write(join(p.qa, 'gates.json'), { ok: true, gates: {} });
  await assert.rejects(deliverStage(ctx), /per-gate candidate binding/);
});

test('line chips and burned captions can be turned off without altering input chunks', () => {
  const chunks = [{ words: ['a'] }];
  const ctx = { flags: {}, spec: {} };
  assert.equal(renderCaptions(ctx, chunks), chunks);
  for (const flags of [{ noLineChips: true }, { noCaptions: true }]) assert.deepEqual(renderCaptions({ ...ctx, flags }, chunks), []);
  for (const render of [{ lineChips: false }, { captions: false }]) assert.deepEqual(renderCaptions({ ...ctx, spec: { render } }, chunks), []);
  assert.equal(chunks.length, 1);
  const args = parseArgs(['spec.json', '--stage', 'qa', '--candidate-id', 'one', '--candidate', 'x.mp4', '--candidate-sha256', 'a'.repeat(64), '--vision-provider', 'local']);
  assert.equal(args.flags.candidateId, 'one');
  assert.equal(args.flags.visionProvider, 'local');
  assert.throws(() => parseArgs(['spec.json', '--candidate-id']), /needs a value/);
});

const cue = [{ w: 'Open', start: 0.08 }, { w: 'seventy-five.', start: 0.32 }];
const bindings = { takeSha256: 'a'.repeat(64), scriptSha256: 'b'.repeat(64) };
const alignment = () => ({
  schema: 'local-ai/forced-alignment/1', units: 'seconds', gridSeconds: 0.08, durationSeconds: 1,
  take: { sha256: bindings.takeSha256 }, script: { sha256: bindings.scriptSha256 },
  words: [{ text: 'Open', start: 0.08, end: 0.24 }, { text: 'seventy', start: 0.32, end: 0.56 }, { text: 'five', start: 0.56, end: 0.8 }],
});
test('forced clock preserves 80 ms provenance, split words and the canonical 40 ms gate', () => {
  const raw = alignment();
  const result = measureWordSync(raw, cue, bindings);
  assert.equal(result.ok, true);
  assert.equal(result.offsetMs, 0);
  assert.equal(result.gridMs, 80);
  assert.equal(result.method, 'forced-alignment-on-encoded');
  assert.equal(result.words[1].end, 0.8);
  for (const w of raw.words) { w.start += 0.08; w.end += 0.08; }
  const late = measureWordSync(raw, cue, bindings);
  assert.equal(late.ok, false);
  assert.match(late.errors.join(' '), /80 ms off/);
});
test('forced clock fails wrong candidate/script, nonfinite, malformed, missing and off-grid words', () => {
  for (const change of [
    (r) => { r.take.sha256 = 'c'.repeat(64); },
    (r) => { r.script.sha256 = 'c'.repeat(64); },
    (r) => { r.units = 'milliseconds'; },
    (r) => { r.words[0].start = NaN; },
    (r) => { r.words[0].start = 0.09; },
    (r) => { r.words[1].start = 0.08; },
    (r) => { r.words.pop(); },
    (r) => { r.words[0].text = 'Close'; },
  ]) {
    const raw = alignment(); change(raw);
    assert.throws(() => forcedWordOnsets(raw, cue, bindings));
  }
});

const spec = { product: 'Synthetic Fixture', labels: 'SYNTHETIC DEMO · NO PHI', beats: [], cta: {} };
const frames = (c, times) => times.map((t, i) => ({ label: `F${i}`, t, dataUrl: 'data:image/jpeg;base64,AAAA' }));
const verdict = (fs) => JSON.stringify({ frames: fs.map((f) => ({ label: f.label, issues: [] })), overall: { labelPresentWhereRequired: true, summary: 'reviewed' } });
test('local vision is the default, costs zero and never silently falls back to paid', async () => {
  let paid = 0;
  const ledger = { check() { throw new Error('local must not charge'); }, charge() { throw new Error('local must not charge'); } };
  const options = { candidate: join(root, 'not-a-real-video'), spec, ratio: '9x16', duration: 2, frames, ledger, vision() { paid++; throw new Error('paid'); } };
  const r = await runVisionQa({ ...options, localVision: async ({ frames: fs }) => ({ text: verdict(fs), model: 'existing-local' }) });
  assert.equal(r.provider, 'local'); assert.equal(r.costUsd, 0); assert.equal(r.ok, true);
  await assert.rejects(runVisionQa({ ...options, localVision: async () => { throw new Error('retired'); } }), /retired/);
  assert.equal(paid, 0);
  await assert.rejects(runVisionQa({ ...options, localVision: async () => ({ text: verdict([]) }) }), /every sampled frame/);
});
test('local vision refuses retired providers or remote endpoints before any network call', async () => {
  let requests = 0;
  await assert.rejects(localVisionJson({ frames: [] }, { discover: async () => ({ id: 'provider.local', status: 'retired' }), fetchImpl: async () => { requests++; } }), /retired/);
  assert.equal(requests, 0);
  for (const serves of ['https://example.com/v1', 'http://example.com/v1', 'http://user:pass@127.0.0.1/v1']) assert.throws(() => visionEndpoint({ id: 'provider.local', status: 'enabled', required_files: ['mmproj.gguf'], serves }), /loopback/);
});
test('local vision uses the registered model and one image per serial request', async () => {
  const calls = [];
  const result = await localVisionJson({ frames: [{ label: 'F1', t: 1, dataUrl: 'data:image/jpeg;base64,AAAA' }], system: 'QA', instructions: 'Review', schema: {}, schemaName: 'qa' }, {
    discover: async () => ({ id: 'provider.local', status: 'enabled', required_files: ['mmproj.gguf'], serves: 'http://127.0.0.1:10000/v1' }),
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return { ok: true, json: async () => url.endsWith('/models') ? { data: [{ id: 'registered-vision' }] } : { choices: [{ message: { content: verdict([{ label: 'F1' }]) } }] } };
    },
  });
  assert.equal(result.model, 'registered-vision');
  assert.equal(calls.length, 2);
  assert.equal(JSON.parse(calls[1].options.body).model, 'registered-vision');
  assert.equal(calls[1].options.redirect, 'error');
});
