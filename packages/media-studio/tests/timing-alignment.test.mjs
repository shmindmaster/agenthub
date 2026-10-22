import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { timingStage, timingWordSource } from '../kit/marketing/lib/stages/timing.mjs';
import { requireTimingClock, timingReceiptFor } from '../kit/marketing/lib/stages/compose.mjs';
import { fileSha, readJson, writeJson } from '../kit/marketing/lib/util.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const fixture = readJson(join(here, 'fixtures', 'timing', 'split-word-alignment.json'));

test('timing source defaults to the aligner and requires an explicit Whisper fallback', () => {
  assert.deepEqual(timingWordSource({}, { timing: { provider: 'openai-whisper' } }), {
    clock: 'forced-aligner',
    provider: 'local-aligner',
  });
  assert.deepEqual(timingWordSource({ whisperTiming: true }, { timing: { provider: 'local-whisper' } }), {
    clock: 'whisper',
    provider: 'local-whisper',
  });
  assert.deepEqual(timingWordSource({ whisperTiming: true, hostedOnly: true }, { timing: { provider: 'local-whisper' } }), {
    clock: 'whisper',
    provider: 'openai-whisper',
  });
  requireTimingClock({ wordClock: 'forced-aligner' });
  assert.throws(() => requireTimingClock({ wordClock: 'whisper' }), /requires forced-aligner timing/);
  assert.doesNotThrow(() => requireTimingClock({}, { whisperTiming: true }), 'legacy 2.0.4/2.0.5 timeline');
  assert.equal(timingReceiptFor({ jobDir: 'unused' }, {
    wordClock: 'forced-aligner',
    segments: [{ id: 'silent-ui', text: '' }],
    lines: [{ beatId: 'silent-ui', asr: null, alignment: null }],
  }, 'silent-ui'), null, 'silent UI beats need no narration alignment receipt');
});

test('timing stage uses fixture forced-alignment onsets for the timeline and captions', async () => {
  const root = mkdtempSync(join(tmpdir(), 'mvg-aligner-timing-'));
  try {
    const jobDir = join(root, 'jobs', 'fixture');
    const audioRel = 'voice/lines/accepted.wav';
    const audio = join(jobDir, audioRel);
    mkdirSync(dirname(audio), { recursive: true });
    writeFileSync(audio, 'accepted narration take');
    writeJson(join(jobDir, 'voice', 'main.lines.json'), {
      cut: 'main',
      lines: [{ beatId: 'B1', text: fixture.script, file: audioRel, key: 'a'.repeat(64), sha256: fileSha(audio) }],
    });

    let alignCalls = 0;
    const ctx = {
      spec: {
        id: 'fixture',
        title: 'Fixture',
        targetSeconds: 5,
        ratios: ['16x9'],
        beats: [{ id: 'B1', kind: 'card', narration: fixture.script, onScreenText: 'Fixture' }],
      },
      brand: { captionStyle: {} },
      jobDir,
      flags: { quiet: true },
      providers: {
        probeDuration: async () => fixture.durationSeconds,
        transcribeWords: async () => { throw new Error('Whisper must not set default timing'); },
        alignWords: async ({ file, script, output }) => {
          alignCalls++;
          assert.equal(file, audio);
          assert.equal(readFileSync(script, 'utf8'), fixture.script);
          writeJson(output, {
            schema: 'local-ai/forced-alignment/1',
            units: 'seconds',
            gridSeconds: 0.08,
            durationSeconds: fixture.durationSeconds,
            take: { sha256: fileSha(file) },
            script: { sha256: fileSha(script) },
            words: fixture.words,
          });
        },
      },
      ledger: { check() {}, charge() {}, summary: () => ({ elevenlabsCredits: 0, openaiUsd: 0 }) },
      runId: 'fixture',
      specSha: 'spec',
      brandSha: 'brand',
      log() {},
    };

    const result = await timingStage(ctx);
    const timeline = readJson(join(jobDir, 'timing', 'main', 'timeline.json'));
    const segment = timeline.segments[0];
    assert.equal(result.main.wordClock, 'forced-aligner');
    assert.equal(timeline.wordClock, 'forced-aligner');
    assert.equal(alignCalls, 1);
    assert.deepEqual(segment.words.map((word) => Number((word.start - segment.lineStartSeconds).toFixed(2))), fixture.expectedOnsets);
    assert.equal(segment.words[1].word, 'seventy-five');
    assert.equal(Number((segment.words[1].end - segment.lineStartSeconds).toFixed(2)), 0.8, 'split aligner tokens cover one authored word');

    const captions = readJson(join(jobDir, 'timing', 'main', 'captions.json')).chunks;
    assert.equal(captions[0].words[0].start, segment.words[0].start);
    const alignment = readJson(join(jobDir, timeline.lines[0].asr));
    assert.equal(alignment.schema, 'local-ai/forced-alignment/1');
    const receipt = timingReceiptFor(ctx, timeline, 'B1');
    assert.deepEqual(receipt, { ...timeline.lines[0].alignment, bound: true });

    await timingStage(ctx);
    assert.equal(alignCalls, 1, 'unchanged timing reuses the bound alignment receipt');
    writeFileSync(join(jobDir, receipt.path), '{}');
    assert.throws(() => timingReceiptFor(ctx, timeline, 'B1'), /timing receipt changed/);
    rmSync(join(jobDir, receipt.path));
    assert.throws(() => timingReceiptFor(ctx, timeline, 'B1'), /timing receipt is missing/);
    writeFileSync(audio, 'mutated after acceptance');
    await assert.rejects(() => timingStage(ctx), /accepted narration take changed before timing/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
