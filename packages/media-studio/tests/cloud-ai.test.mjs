// cloud-ai pure helpers: argument parsing, JSON extraction from model replies, provider order and the client guard.
// Run: node --test tests/cloud-ai.test.mjs (no provider calls)
import test from 'node:test';
import assert from 'node:assert/strict';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { parseArgs, extractJson, providerOrder } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-ai.mjs')).href);

test('parseArgs collects list options until the next flag', () => {
  const { sub, opts } = parseArgs(['qa', '--images', 'a.jpg', 'b.png', '--prompt', 'look', '--out', 'r.json', '--client']);
  assert.equal(sub, 'qa');
  assert.deepEqual(opts.images, ['a.jpg', 'b.png']);
  assert.equal(opts.prompt, 'look');
  assert.equal(opts.out, 'r.json');
  assert.equal(opts.client, true);
});

test('extractJson reads fenced and prose-wrapped replies', () => {
  assert.deepEqual(extractJson('Here:\n```json\n{"score": 90, "pass": true}\n```'), { score: 90, pass: true });
  assert.deepEqual(extractJson('Verdict {"score": 40, "findings": []} done'), { score: 40, findings: [] });
  assert.throws(() => extractJson('no json here'), /no JSON/);
});

test('providerOrder: Anthropic first with spillover; --client stays in the owner tenant', () => {
  assert.deepEqual(providerOrder({}), ['anthropic', 'azure-openai', 'gemini']);
  assert.deepEqual(providerOrder({ provider: 'gemini' }), ['gemini']);
  assert.deepEqual(providerOrder({ client: true }), ['azure-openai']);
  assert.throws(() => providerOrder({ client: true, provider: 'anthropic' }), /may not go to Anthropic/);
  assert.deepEqual(providerOrder({ client: true, provider: 'openai' }), ['openai']);
});

const { canonKey, heardKeys, scriptTokens, alignScript } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-ai.mjs')).href);
const { forcedWordOnsets, cloudAlignCoverage } = await import(pathToFileURL(join(pkg, 'kit', 'screencast', 'sync-lib.mjs')).href);

test('canonKey speaks numbers and expands apostrophe contractions', () => {
  assert.equal(canonKey('30'), 'thirty');
  assert.equal(canonKey('$1.71'), 'onepointsevenonedollars');
  assert.equal(canonKey('10%'), 'tenpercent');
  assert.equal(canonKey('twenty-four'), canonKey('24'));
  assert.equal(canonKey('20-person'), 'twentyperson');
  assert.equal(canonKey('I’m'), 'iam');
  assert.equal(canonKey('ill'), 'ill');
});

test('heardKeys moves a currency word after its scale word', () => {
  assert.deepEqual(heardKeys([{ text: '$800', start: 0, end: 1 }, { text: 'million', start: 1, end: 2 }]).map((w) => w.key), ['eighthundred', 'milliondollars']);
});

const heard = (pairs) => pairs.map(([text, start, end]) => ({ key: canonKey(text), start, end }));

test('alignScript keeps exact ASR onsets, merges compounds and snaps to the 80 ms grid', () => {
  const script = scriptTokens("Hi, I'm a language-model builder.");
  const { words, coverage } = alignScript(script, heard([['hi', 0.1, 0.3], ['i', 0.41, 0.5], ['am', 0.5, 0.62], ['a', 0.7, 0.75], ['language', 0.8, 1.2], ['model', 1.2, 1.5], ['builder', 1.6, 2.0]]), 2.5);
  assert.deepEqual(words.map((w) => w.text), ['Hi,', "I'm", 'a', 'language-model', 'builder.']);
  assert.ok(words.every((w) => !w.precisionLimited));
  assert.ok(words.every((w) => Math.abs(w.start / 0.08 - Math.round(w.start / 0.08)) < 1e-6));
  assert.equal(words[1].start, 0.4);
  assert.equal(coverage.exact, 5);
});

test('alignScript bounds a misheard word by its neighbours and flags it', () => {
  const { words, coverage } = alignScript(scriptTokens('at Pendoah where'), heard([['at', 0, 0.2], ['pandoa', 0.25, 0.8], ['where', 0.9, 1.1]]), 1.5);
  assert.equal(words[1].precisionLimited, true);
  assert.ok(words[1].start >= words[0].end && words[1].end <= words[2].start);
  assert.equal(coverage.longestUnmatchedRun, 1);
});

const cloudReport = (words) => ({ schema: 'cloud-speech/script-alignment/1', units: 'seconds', gridSeconds: 0.08, durationSeconds: 10, take: { sha256: 't' }, script: { sha256: 's' }, words });

test('sync gate accepts a tight cloud alignment and refuses a loose one', () => {
  const tight = Array.from({ length: 10 }, (_, i) => ({ text: `w${i}`, start: +(i * 0.16).toFixed(2), end: +(i * 0.16 + 0.08).toFixed(2), precisionLimited: i === 4 }));
  const cue = tight.map((w) => ({ w: w.text, start: w.start }));
  assert.equal(forcedWordOnsets(cloudReport(tight), cue, { takeSha256: 't', scriptSha256: 's' }).length, 10);
  const loose = tight.map((w, i) => ({ ...w, precisionLimited: i < 3 }));
  assert.equal(cloudAlignCoverage(loose).exactRatio, 0.7);
  assert.throws(() => forcedWordOnsets(cloudReport(loose), cue, { takeSha256: 't', scriptSha256: 's' }), /too loose/);
  assert.throws(() => forcedWordOnsets({ ...cloudReport(tight), schema: 'whisper/1' }, cue, { takeSha256: 't', scriptSha256: 's' }), /80 ms grid/);
  assert.throws(() => forcedWordOnsets(cloudReport(tight), cue, { takeSha256: 'other', scriptSha256: 's' }), /SHA-256 mismatch/);
});
