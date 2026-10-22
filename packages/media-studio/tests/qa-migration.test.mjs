// Amp review follow-up: synthetic clocks and legacy evidence only, no provider or encode.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runPipeline } from '../kit/marketing/mvg.mjs';
import { candidatePaths, verifiedCandidate } from '../kit/marketing/lib/candidate.mjs';
import { runSyncGates } from '../kit/marketing/lib/local-gates.mjs';
import { deliverStage } from '../kit/marketing/lib/stages/deliver.mjs';
import { fileSha } from '../kit/marketing/lib/util.mjs';
import { measureWordSync } from '../kit/screencast/sync-lib.mjs';

test('external QA refuses ratio and nested-workspace junctions before writing source evidence', () => {
  const root = mkdtempSync(join(tmpdir(), 'qa-descendant-link-'));
  try {
    const job = join(root, 'source'), qaDir = join(root, 'external-qa');
    mkdirSync(job); mkdirSync(qaDir);
    const ctx = { jobDir: job, flags: { candidateId: 'one', candidate: join(job, 'ad.mp4'),
      composeDir: job, qaDir } };
    const ratioDir = join(qaDir, '9x16');
    symlinkSync(job, ratioDir, process.platform === 'win32' ? 'junction' : 'dir');
    assert.throws(() => candidatePaths(ctx, '9x16'), /reparse|outside/);
    rmSync(ratioDir);
    mkdirSync(ratioDir);
    const nested = join(ratioDir, 'ws', 'qa');
    mkdirSync(join(ratioDir, 'ws'));
    symlinkSync(job, nested, process.platform === 'win32' ? 'junction' : 'dir');
    assert.throws(() => candidatePaths(ctx, '9x16'), /reparse|outside/);
    rmSync(nested);
    assert.equal(candidatePaths(ctx, '9x16').qa, ratioDir);
    assert.equal(existsSync(join(job, 'gates.json')), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('punctuation-only narration tokens do not invalidate successful take alignment', async () => {
  const root = mkdtempSync(join(tmpdir(), 'qa-punctuation-'));
  try {
    for (const dir of ['story', 'qa', 'voice/asr']) mkdirSync(join(root, dir), { recursive: true });
    const text = 'Check the queue — then approve.';
    const json = (path, value) => writeFileSync(path, JSON.stringify(value));
    json(join(root, 'story', 'narration-timeline.json'), { segments: [{ id: 'one', text, startSeconds: 0 }] });
    json(join(root, 'job.json'), {});
    writeFileSync(join(root, 'story', 'locked-script.txt'), text);
    const candidate = join(root, 'candidate.mp4'), take = join(root, 'accepted.wav');
    writeFileSync(candidate, 'synthetic encoded bytes'); writeFileSync(take, 'synthetic take bytes');
    let alignCalls = 0;
    const result = await runSyncGates({ ws: root, candidate, composeMapRel: 'unused',
      moduleRoot: fileURLToPath(new URL('../kit/marketing', import.meta.url)),
      voiceLines: [{ file: take, startSec: .35 }],
      align: async ({ file, script, output }) => {
        alignCalls++;
        json(output, { schema: 'local-ai/forced-alignment/1', units: 'seconds', gridSeconds: .08,
          durationSeconds: 2, take: { sha256: fileSha(file) }, script: { sha256: fileSha(script) },
          words: ['Check', 'the', 'queue', 'then', 'approve.'].map((text, i) =>
            ({ text, start: i * .24, end: i * .24 + .16 })) });
      },
      runCommand: async () => ({ code: 1, stderr: 'synthetic stop after alignment' }),
    });
    assert.equal(alignCalls, 2);
    assert.equal(result.wordSync, undefined, 'no failed alignment gate before the deliberate cue stop');
    const words = JSON.parse(readFileSync(join(root, 'voice', 'asr', 'one.json'), 'utf8')).words;
    assert.deepEqual(words.map(word => word.w), ['Check', 'the', 'queue', 'then', 'approve.']);
    assert.equal(words[0].start, .35);
    assert.equal(existsSync(join(root, 'qa', 'encoded-alignment.json')), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('multi-beat non-grid placement preserves raw 80 ms phases and the 40 ms drift gate', () => {
  const bindings = { takeSha256: 'a'.repeat(64), scriptSha256: 'b'.repeat(64) };
  const labels = ['First', 'check', 'Second', 'check', 'Third', 'check'];
  // Three accepted takes have onsets .08/.32. Their program placements are
  // deliberately not multiples of .08; the full-program aligner stays on its own grid.
  const cue = [.35, 1.97, 3.61].flatMap(lead => [.08, .32].map(start => ({ start: lead + start })))
    .map((word, i) => ({ ...word, w: labels[i] }));
  const report = {
    schema: 'local-ai/forced-alignment/1', units: 'seconds', gridSeconds: .08, durationSeconds: 5,
    take: { sha256: bindings.takeSha256 }, script: { sha256: bindings.scriptSha256 },
    words: [.4, .64, 2.08, 2.32, 3.68, 3.92].map((start, i) => ({ text: labels[i], start, end: start + .16 })),
  };
  const unchanged = structuredClone(report);
  const measured = measureWordSync(report, cue, bindings);
  assert.equal(measured.ok, true);
  assert.equal(measured.gridMs, 80);
  assert.equal(measured.offsetMs, -10);
  assert.equal(measured.driftMs, 20);
  assert.deepEqual(report, unchanged, 'measurement must not snap or retime raw alignment');
  const late = structuredClone(report);
  for (const word of late.words.slice(-2)) { word.start += .08; word.end += .08; }
  const failed = measureWordSync(late, cue, bindings);
  assert.equal(failed.ok, false);
  assert.equal(failed.driftMs, 100);
  assert.match(failed.errors.join(' '), /A\/V drift/);
});

test('2.0.4 runners stop before stages, while retained encodes migrate by explicit hash without rewriting evidence', async () => {
  const root = mkdtempSync(join(tmpdir(), 'qa-204-migration-'));
  try {
    const jobDir = join(root, 'legacy-job'), composeDir = join(jobDir, 'compose', '9x16');
    mkdirSync(composeDir, { recursive: true });
    const ad = join(composeDir, 'ad.mp4'), srt = join(composeDir, 'ad.srt');
    const gatePath = join(jobDir, 'qa', '9x16', 'gates.json');
    mkdirSync(join(jobDir, 'qa', '9x16'), { recursive: true });
    writeFileSync(ad, 'synthetic retained 2.0.4 encode');
    writeFileSync(srt, 'synthetic retained subtitles');
    writeFileSync(gatePath, JSON.stringify({ ok: true, gates: { picture: { status: 'pass' } } }));
    const originals = [ad, srt, gatePath].map(fileSha);
    const calls = [];
    const stages = ['compose', 'qa', 'deliver'].map(name => [name, () => calls.push(name)]);
    for (const flags of [{}, { stage: 'all' }]) {
      await assert.rejects(runPipeline({ flags, log() {} }, stages), /explicit --stage/);
    }
    assert.deepEqual(calls, []);
    const ctx = { jobDir, log() {}, spec: { ratios: ['9x16'], beats: [] },
      flags: { stage: 'qa', candidateId: 'retained-204', candidate: ad, composeDir,
        candidateSha256: originals[0], ratio: '9x16', qaDir: join(root, 'external-qa') } };
    assert.equal(existsSync(join(composeDir, 'candidate.json')), false);
    assert.equal(verifiedCandidate(ctx, '9x16').sha256, originals[0]);
    await runPipeline(ctx, stages);
    assert.deepEqual(calls, ['qa']);
    // Even a legacy PASS copied into the new QA directory cannot authorize delivery.
    const newQa = join(ctx.flags.qaDir, '9x16');
    mkdirSync(newQa, { recursive: true });
    writeFileSync(join(newQa, 'gates.json'), readFileSync(gatePath));
    await assert.rejects(deliverStage(ctx), /per-gate candidate binding/);
    assert.deepEqual([ad, srt, gatePath].map(fileSha), originals);
    assert.equal(existsSync(join(composeDir, 'candidate.json')), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
