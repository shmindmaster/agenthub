// Amp review follow-up: synthetic clocks and legacy evidence only, no provider or encode.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runPipeline } from '../kit/marketing/mvg.mjs';
import { verifiedCandidate } from '../kit/marketing/lib/candidate.mjs';
import { deliverStage } from '../kit/marketing/lib/stages/deliver.mjs';
import { fileSha } from '../kit/marketing/lib/util.mjs';
import { measureWordSync } from '../kit/screencast/sync-lib.mjs';

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
