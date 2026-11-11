import test from 'node:test';
import assert from 'node:assert/strict';
import { requiredGates, DEFAULT_REQUIRED, releasable } from '../kit/marketing/lib/gates.mjs';
import { creativeMode } from '../kit/marketing/lib/creative-modes.mjs';

test('old default verified-demo retains complete UI evidence and pointer QA', () => {
  assert.equal(creativeMode({}), 'verified-demo');
  assert.deepEqual(requiredGates({}), DEFAULT_REQUIRED);
  for (const key of ['picture', 'integrity', 'pointer', 'sync', 'frameIntegrity', 'story', 'viewerRelease']) {
    assert.ok(requiredGates({}).includes(key));
  }
});
test('a fictional, future-vision or documentary marketing cut requires film QA but not product UI QA', () => {
  for (const creativeMode of ['future-vision', 'concept-film', 'fictional-story', 'hybrid', 'documentary', 'educational', 'abstract', 'explainer']) {
    const gates = requiredGates({ creativeMode });
    for (const key of ['picture', 'integrity', 'pointer', 'sync']) assert.ok(!gates.includes(key), creativeMode + '/' + key);
    for (const key of ['frameIntegrity', 'marketing', 'story', 'vision', 'viewerRelease', 'wordSync', 'transcript']) assert.ok(gates.includes(key), creativeMode + '/' + key);
    const skipped = Object.fromEntries(gates.map(k => [k, { status: 'pass' }]));
    skipped.picture = { status: 'n/a' };
    skipped.pointer = { status: 'n/a' };
    assert.equal(releasable(skipped, gates).ok, true, creativeMode);
  }
});
test('a mode-specific requested QA list cannot silently reenable UI-only gates', () => {
  const gates = requiredGates({ creativeMode: 'future-vision',
    qa: { required: ['pointer', 'picture', 'sync', 'story', 'vision', 'captions'] } });
  assert.ok(!gates.includes('pointer'));
  assert.ok(!gates.includes('picture'));
  assert.ok(!gates.includes('sync'));
  for (const k of ['story', 'vision', 'captions', 'frameIntegrity', 'marketing', 'wordSync', 'transcript']) assert.ok(gates.includes(k), k);
});
test('a nonverified cut cannot claim a successful release with missing story or vision review', () => {
  const gates = requiredGates({ creativeMode: 'future-vision' });
  const missing = Object.fromEntries(gates.map(k => [k, { status: 'pass' }]));
  missing.story = { status: 'pending' };
  assert.equal(releasable(missing, gates).ok, false);
  assert.match(releasable(missing, gates).failing.join(' '), /story: pending/);
});
