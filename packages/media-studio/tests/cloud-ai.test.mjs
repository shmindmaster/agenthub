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

test('providerOrder: Anthropic first with spillover; --client refuses Anthropic', () => {
  assert.deepEqual(providerOrder({}), ['anthropic', 'openai', 'gemini']);
  assert.deepEqual(providerOrder({ provider: 'gemini' }), ['gemini']);
  assert.throws(() => providerOrder({ client: true }), /may not go to Anthropic/);
  assert.throws(() => providerOrder({ client: true, provider: 'anthropic' }), /may not go to Anthropic/);
  assert.deepEqual(providerOrder({ client: true, provider: 'openai' }), ['openai']);
});
