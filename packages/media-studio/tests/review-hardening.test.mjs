// Synthetic review regressions. No model, provider, render, encode or delivery.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { candidatePaths } from '../kit/marketing/lib/candidate.mjs';
import { runSyncGates } from '../kit/marketing/lib/gate-runners.mjs';
import { qaStage } from '../kit/marketing/lib/stages/qa.mjs';
import { voiceStage } from '../kit/marketing/lib/stages/voice.mjs';
import { deliverStage } from '../kit/marketing/lib/stages/deliver.mjs';
import { requiredGates } from '../kit/marketing/lib/gates.mjs';
import { fileSha } from '../kit/marketing/lib/util.mjs';
import { runVisionQa } from '../kit/marketing/vision-qa.mjs';
import { runPipeline, selectedStages } from '../kit/marketing/mvg.mjs';

const root = mkdtempSync(join(tmpdir(), 'review-hardening-'));
test.after(() => rmSync(root, { recursive: true, force: true }));
const write = (path, value) => writeFileSync(path, JSON.stringify(value));
const moduleRoot = fileURLToPath(new URL('../kit/marketing', import.meta.url));

test('external QA rejects junction aliases into source evidence, including nonexistent trailing directories', () => {
  const job = join(root, 'junction-source'), alias = join(root, 'junction-alias');
  mkdirSync(job);
  symlinkSync(job, alias, process.platform === 'win32' ? 'junction' : 'dir');
  const flags = { candidateId: 'one', candidate: join(job, 'ad.mp4'), composeDir: job,
    qaDir: join(alias, 'not-created', 'qa') };
  assert.throws(() => candidatePaths({ jobDir: job, flags }, '9x16'), /outside/);
  flags.qaDir = join(job, 'not-created', 'qa');
  assert.throws(() => candidatePaths({ jobDir: alias, flags }, '9x16'), /outside/);
  flags.qaDir = join(root, 'safe-qa', 'new');
  assert.equal(candidatePaths({ jobDir: alias, flags }, '9x16').id, 'one');
  assert.equal(existsSync(join(job, 'not-created')), false);
});

test('transcript comparison fails closed before a cue-sheet early return', async () => {
  for (const kind of ['missing', 'malformed', 'different', 'matching', 'locked-unreadable']) {
    const ws = join(root, `transcript-${kind}`);
    mkdirSync(join(ws, 'qa'), { recursive: true });
    mkdirSync(join(ws, 'story'));
    const timeline = join(ws, 'story', 'narration-timeline.json');
    write(timeline, { segments: [{ text: 'Four trials.' }] });
    if (kind === 'locked-unreadable') writeFileSync(timeline, 'not-json');
    let calls = 0, transcripts = 0;
    const result = await runSyncGates({ ws, candidate: join(ws, 'fake.mp4'),
      moduleRoot, composeMapRel: 'unused', voiceLines: [],
      transcribe: async ({ jsonOut }) => {
        transcripts++;
        if (kind === 'malformed') writeFileSync(jsonOut, 'not-json');
        else if (kind !== 'missing') write(jsonOut, { text: kind === 'different' ? 'Five trials.' : '4 trials.' });
      },
      runCommand: async () => { calls++; return { code: 1, stderr: 'synthetic cue failure' }; },
    });
    assert.equal(transcripts, 1);
    assert.equal(calls, 1, 'only the cue sheet runs as a command; nothing shells out to a local runtime');
    assert.equal(result.sync.status, 'fail');
    assert.equal(result.transcript.status, kind === 'matching' ? 'pass' : 'fail');
    if (['missing', 'malformed', 'locked-unreadable'].includes(kind)) assert.match(result.transcript.detail, /unreadable/);
  }
});

test('Local AI is off: default aligner and transcript refuse with the hosted route, and a stale transcript never passes', async () => {
  const ws = join(root, 'local-ai-off');
  mkdirSync(join(ws, 'qa'), { recursive: true });
  mkdirSync(join(ws, 'story'));
  write(join(ws, 'story', 'narration-timeline.json'), { segments: [{ id: 'one', text: 'Four trials.', startSeconds: 0 }] });
  write(join(ws, 'job.json'), {});
  writeFileSync(join(ws, 'story', 'locked-script.txt'), 'Four trials.');
  const take = join(ws, 'take.wav');
  writeFileSync(take, 'synthetic take');
  // A transcript left by an earlier run must not be compared as if it belonged to this candidate.
  write(join(ws, 'qa', 'encoded-asr.json'), { text: '4 trials.' });
  const commands = [];
  const result = await runSyncGates({ ws, candidate: join(ws, 'fake.mp4'), moduleRoot, composeMapRel: 'unused',
    voiceLines: [{ file: take, startSec: 0 }],
    runCommand: async (exe, args) => { commands.push([exe, ...args].join(' ')); return { code: 1, stderr: 'synthetic cue failure' }; } });
  assert.equal(result.wordSync.status, 'fail');
  assert.match(result.wordSync.detail, /^forced alignment: local aligner: Local AI is off; use the hosted route \(kit\/cloud\/cloud-ai\.mjs align, Azure TTS\/STT\)/);
  assert.equal(result.transcript.status, 'fail');
  assert.match(result.transcript.detail, /encoded transcript: Local AI is off/);
  assert.equal(existsSync(join(ws, 'qa', 'encoded-asr.json')), false);
  assert.equal(result.listen, undefined, 'mvg has no listen runner');
  assert.ok(commands.every((c) => !/powershell|ai\.ps1/i.test(c)), commands.join('\n'));
  // transcribe: null skips the gate so the caller can report it pending.
  const skipped = await runSyncGates({ ws, candidate: join(ws, 'fake.mp4'), moduleRoot, composeMapRel: 'unused',
    voiceLines: [], transcribe: null, runCommand: async () => ({ code: 1, stderr: 'stop' }) });
  assert.equal(skipped.transcript, undefined);
});

test('Local AI is off: a local voice provider refuses before rendering instead of starting Qwen', async () => {
  const job = join(root, 'local-voice');
  const ctx = { jobDir: job, flags: {}, providers: {}, log() {},
    spec: { id: 'v', ratios: ['9x16'], beats: [{ id: 'b1', kind: 'card', narration: 'Open the queue.' }], voice: { provider: 'local', voiceId: 'role' } },
    ledger: { check() {}, charge() {}, summary: () => ({}) } };
  await assert.rejects(voiceStage(ctx), /local voice: Local AI is off; use the hosted route/);
  let rendered = 0;
  ctx.providers.localVoice = async ({ out }) => { rendered++; writeFileSync(out, 'synthetic wav'); };
  const result = await voiceStage(ctx);
  assert.equal(rendered, 1, 'the injected seam still works');
  assert.equal(result.main.lines.length, 1);
});

test('QA publishes pending gates for an unencoded prepared candidate without a hash receipt or compose metadata', async () => {
  const job = join(root, 'prepared');
  mkdirSync(join(job, 'timing', 'main'), { recursive: true });
  write(join(job, 'timing', 'main', 'timeline.json'), { durationSeconds: 1 });
  const ctx = { jobDir: job, spec: { ratios: ['9x16'], beats: [] },
    flags: { candidateId: 'one', qaDir: join(root, 'prepared-qa') } };
  const result = await qaStage(ctx);
  const gatePath = join(ctx.flags.qaDir, '9x16', 'gates.json');
  assert.equal(result['9x16'].ok, false);
  const receipt = JSON.parse(readFileSync(gatePath));
  assert.equal(receipt.candidate, null);
  assert.ok(Object.values(receipt.gates).every(gate => gate.status === 'pending'));
});

test('delivery dry inspection accepts reviewed sidecars and rejects missing or changed subtitle bindings', async () => {
  const job = join(root, 'sidecar');
  const ctx = { jobDir: job, flags: { candidateId: 'one', dryRun: true },
    spec: { ratios: ['9x16'], beats: [] }, specSha: 'a'.repeat(64), brandSha: 'b'.repeat(64),
    brand: { deliver: { dir: join(root, 'not-delivered') } }, log() {} };
  const paths = candidatePaths(ctx, '9x16');
  mkdirSync(paths.dir, { recursive: true }); mkdirSync(paths.qa, { recursive: true });
  mkdirSync(join(job, 'timing', 'main'), { recursive: true });
  write(join(job, 'timing', 'main', 'timeline.json'), { durationSeconds: 1 });
  writeFileSync(paths.ad, 'synthetic candidate');
  const srt = join(paths.dir, 'ad.srt');
  writeFileSync(srt, 'reviewed subtitle');
  const sha = fileSha(paths.ad);
  write(join(paths.dir, 'candidate.json'), { id: 'one', ratio: '9x16', sha256: sha,
    specSha256: ctx.specSha, brandSha256: ctx.brandSha });
  const verdict = { ok: true, gates: Object.fromEntries(requiredGates(ctx.spec).map(name =>
    [name, { status: 'pass', candidateSha256: sha }])), candidate: { id: 'one', sha256: sha },
    specSha256: ctx.specSha, brandSha256: ctx.brandSha, subtitles: { sha256: fileSha(srt) } };
  const gatePath = join(paths.qa, 'gates.json');
  write(gatePath, verdict);
  assert.equal((await deliverStage(ctx)).dryRun, true);
  writeFileSync(srt, 'changed subtitle');
  await assert.rejects(deliverStage(ctx), /subtitle SHA-256/);
  delete verdict.subtitles;
  write(gatePath, verdict);
  await assert.rejects(deliverStage(ctx), /subtitle SHA-256/);
  assert.equal(existsSync(ctx.brand.deliver.dir), false);
});

test('isolated encoded-stage dry runs are refused instead of reporting an empty success', async () => {
  for (const stage of ['compose', 'qa', 'deliver']) {
    for (const selector of ['stage', 'only']) {
      const ctx = { flags: { [selector]: stage, dryRun: true }, log() {} };
      await assert.rejects(runPipeline(ctx), /cannot use --dry-run/);
    }
  }
  assert.deepEqual(selectedStages({ stage: 'timing', dryRun: true }), ['lint', 'voice', 'timing']);
  assert.deepEqual(selectedStages({ stage: 'capture', dryRun: true }), ['lint', 'voice', 'timing', 'assets', 'capture']);
});

test('paid library and CLI vision refuse missing ledgers before decoding or contacting a provider', async () => {
  let calls = 0;
  await assert.rejects(runVisionQa({ provider: 'openai', frames() { calls++; }, vision() { calls++; } }), /cost ledger/);
  assert.equal(calls, 0);
  const folder = join(root, 'paid-cli'); mkdirSync(folder);
  const spec = join(folder, 'spec.json'), brand = join(folder, 'brand.json'), report = join(folder, 'report.json');
  write(spec, {}); write(brand, {});
  const cli = fileURLToPath(new URL('../kit/marketing/vision-qa.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [cli, join(folder, 'not-decoded.mp4'),
    '--spec', spec, '--brand', brand, '--ratio', '9x16', '--provider', 'openai', '--out', report],
  { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /cost ledger/);
  assert.equal(existsSync(report), false);
});

test('QA with --prepare-only publishes pending gates even for a verified encoded candidate', async () => {
  const job = join(root, 'prepare-only-verified');
  const ctx = { jobDir: job, spec: { id: 'spec-one', ratios: ['9x16'], beats: [] },
    specSha: 'a'.repeat(64), brandSha: 'b'.repeat(64),
    flags: { candidateId: 'one', prepareOnly: true, qaDir: join(root, 'prepare-only-qa') } };
  const paths = candidatePaths(ctx, '9x16');
  mkdirSync(paths.dir, { recursive: true });
  mkdirSync(join(job, 'timing', 'main'), { recursive: true });
  write(join(job, 'timing', 'main', 'timeline.json'), { durationSeconds: 1 });
  writeFileSync(paths.ad, 'synthetic encoded bytes');
  write(join(paths.dir, 'candidate.json'), { id: 'one', ratio: '9x16', sha256: fileSha(paths.ad),
    specSha256: ctx.specSha, brandSha256: ctx.brandSha });
  const result = await qaStage(ctx);
  assert.equal(result['9x16'].ok, false);
  const receipt = JSON.parse(readFileSync(join(ctx.flags.qaDir, '9x16', 'gates.json')));
  assert.equal(receipt.candidate, null);
  assert.ok(Object.values(receipt.gates).every(gate => gate.status === 'pending'));
});

test('QA records a pending-or-fail stage in the job manifest when no --qa-dir is given', async () => {
  const job = join(root, 'stage-record');
  mkdirSync(join(job, 'timing', 'main'), { recursive: true });
  write(join(job, 'timing', 'main', 'timeline.json'), { durationSeconds: 1 });
  const ctx = { jobDir: job, spec: { id: 'spec-two', ratios: ['9x16', '16x9'], beats: [] },
    specSha: 'a'.repeat(64), brandSha: 'b'.repeat(64), runId: 'run-1',
    ledger: { summary: () => ({ usd: 0 }) }, flags: { candidateId: 'one' } };
  const result = await qaStage(ctx);
  assert.deepEqual(Object.keys(result).sort(), ['16x9', '9x16']);
  const manifest = JSON.parse(readFileSync(join(job, 'manifest.json')));
  assert.equal(manifest.stages.qa.status, 'pending-or-fail');
  assert.equal(manifest.stages.qa.ratios['9x16'].ok, false);
  assert.ok(result['9x16'].failing.every(f => /pending/.test(f)));
});

test('a narrowed qa.required still publishes the film-chain and transcript pendings for an unencoded candidate', async () => {
  const job = join(root, 'narrowed');
  mkdirSync(join(job, 'timing', 'main'), { recursive: true });
  write(join(job, 'timing', 'main', 'timeline.json'), { durationSeconds: 1 });
  const ctx = { jobDir: job, spec: { ratios: ['9x16'], beats: [], qa: { required: ['picture', 'captions'] } },
    flags: { candidateId: 'one', qaDir: join(root, 'narrowed-qa') } };
  const result = await qaStage(ctx);
  assert.deepEqual(Object.keys(result['9x16'].gates).sort(),
    ['captions', 'frameIntegrity', 'integrity', 'marketing', 'picture', 'pointer', 'transcript', 'wordSync']);
  assert.equal(result['9x16'].failing.length, 8);
});
