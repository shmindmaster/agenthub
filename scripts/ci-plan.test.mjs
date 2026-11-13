import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classify, onlyDispatchHashChanged } from './ci-plan.mjs';

test('routes docs, doctor, dispatch and unknown changes conservatively', () => {
  assert.equal(classify(['docs/readme.md']), 'docs');
  assert.equal(classify(['global-agent-policy.md']), 'full');
  assert.equal(classify(['AGENTS.md']), 'full');
  assert.equal(classify(['src/doctor/main.js']), 'doctor');
  assert.equal(classify(['packages/coding-agent-dispatch/tests/a.test.mjs','registry/capabilities.json'], true), 'dispatch');
  assert.equal(classify(['packages/coding-agent-dispatch/a','registry/capabilities.json'], false), 'full');
  assert.equal(classify(['packages/media-studio/a']), 'full');
  assert.equal(classify(['packages/coding-agent-dispatch/a','scripts/sync.ps1']), 'full');
  assert.equal(classify([]), 'full');
});
test('only accepts hash changes for the dispatch package', () => {
  const a = { rows: [{hashBasis:'packages/coding-agent-dispatch',contentHash:'a', status:'active'}, {hashBasis:'packages/other',contentHash:'x'}] };
  const b = structuredClone(a); b.rows[0].contentHash = 'b';
  assert.equal(onlyDispatchHashChanged(a,b),true);
  b.rows[1].contentHash = 'y'; assert.equal(onlyDispatchHashChanged(a,b),false);
  b.rows[1].contentHash = 'x'; b.rows[0].status = 'inactive'; assert.equal(onlyDispatchHashChanged(a,b),false);
});
