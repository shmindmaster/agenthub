import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { frameFor } from '../kit/screencast/campaign-contract.mjs';
test('square profile declares exact delivery dimensions', () => {
  assert.deepEqual(frameFor({deliveryProfile:'square-1x1'}), {profile:'square-1x1',width:1080,height:1080,fps:30});
  assert.throws(() => frameFor({deliveryProfile:'unknown'}), /unknown/);
});
for (const missing of ['candidate', 'timeline']) test(`missing ${missing} writes a fail-closed report`, () => {
  const root = mkdtempSync(join(tmpdir(), 'encoded-input-'));
  try {
    const candidate = join(root, 'candidate.mp4');
    if (missing === 'timeline') writeFileSync(candidate, 'fixture without media decoding');
    const r = spawnSync(process.execPath, ['packages/media-studio/scripts/validate-encoded-picture.mjs',root,candidate], {encoding:'utf8',windowsHide:true});
    assert.equal(r.status, 1);
    assert.doesNotMatch(r.stderr, /ReferenceError/);
    const report = JSON.parse(readFileSync(join(root,'qa','encoded-picture.json'),'utf8'));
    assert.equal(report.ok,false);
    assert.ok(report.errors.some(e => e.includes(missing === 'candidate' ? 'candidate not found' : 'missing story/narration-timeline')));
  } finally { rmSync(root,{recursive:true,force:true}); }
});
