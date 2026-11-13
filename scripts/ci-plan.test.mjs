import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classify, hashOnlyForPackages, packageMatrix } from './ci-plan.mjs';

test('routes changes and unions independent checks', () => {
  assert.deepEqual(classify(['docs/readme.md']), {core:false,doctor:false,docs:true,packages:[]});
  assert.deepEqual(classify(['global-agent-policy.md']), {core:true,doctor:true,docs:false,packages:[]});
  assert.deepEqual(classify(['src/doctor/a.js','packages/media-studio/a']), {core:false,doctor:true,docs:false,packages:['media-studio']});
  assert.deepEqual(classify(['packages/coding-agent-dispatch/a','registry/capabilities.json'], true), {core:false,doctor:false,docs:false,packages:['coding-agent-dispatch']});
  assert.equal(classify(['packages/coding-agent-dispatch/a','registry/capabilities.json'], false).core,true);
  assert.equal(classify(['scripts/sync.ps1']).core,true);
  assert.deepEqual(classify(['tests/Test-MediaStudioPython.ps1']).packages,['media-studio']);
  assert.equal(classify([]).core,true);
});
test('registry exception permits only changed packages hashes', () => {
  const a = {rows:[{hashBasis:'packages/a',contentHash:'a',status:'active'},{hashBasis:'packages/b',contentHash:'b'}]};
  const b = structuredClone(a); b.rows[0].contentHash='x';
  assert.equal(hashOnlyForPackages(a,b,['a']),true);
  assert.equal(hashOnlyForPackages(a,b,['b']),false);
  b.rows[0].status='disabled'; assert.equal(hashOnlyForPackages(a,b,['a']),false);
});

test('platform specific packages retain Windows checks', () => {
  for (const pkg of ['coding-agent-dispatch', 'repowise', 'mobile-development']) {
    assert.ok(packageMatrix([pkg]).some(row => row.os === 'windows-latest'));
  }
  assert.equal(packageMatrix(['media-studio']).length, 4);
});
