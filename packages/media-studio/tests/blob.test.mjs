// blob client: every request carries an abort timeout. No network (global fetch is stubbed).
// Run: node --test tests/blob.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { blobClient } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'blob.mjs')).href);

test('blob requests carry an AbortSignal so a stalled socket cannot hang a render', async () => {
  const originalFetch = global.fetch;
  const signals = [];
  global.fetch = async (url, init) => {
    signals.push(init.signal);
    return { status: 200, ok: true, text: async () => 'hi', arrayBuffer: async () => new ArrayBuffer(0) };
  };
  try {
    const client = blobClient('acct', async () => 'token');
    assert.equal(await client.getText('jobs/x/result.json'), 'hi');
    await client.putText('jobs/x/job.json', '{}');
    assert.equal(signals.length, 2);
    for (const s of signals) assert.ok(s instanceof AbortSignal, 'fetch must receive an AbortSignal');
  } finally {
    global.fetch = originalFetch;
  }
});
