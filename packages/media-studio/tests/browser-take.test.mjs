import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { logAction, receiptClip } from '../scripts/browser-take.mjs';
import { checkMediaSource } from '../scripts/build-picture.mjs';

const scripts = fileURLToPath(new URL('../scripts/', import.meta.url));

test('a logged take becomes a receipt the pointer-path gate can judge', () => {
  const take = { clipId: 'w01', video: 'capture/w01.webm', t0: 1_000_000, pointer: { x: 0, y: 0 }, actions: [] };
  for (const [i, f] of [1 / 3, 2 / 3, 1].entries()) logAction(take, { type: 'move', x: 600 * f, y: 300 * f }, 1_001_000 + i * 200);
  logAction(take, { type: 'click', x: 600, y: 300, label: 'Authorizations' }, 1_001_700);
  const clip = receiptClip(take, 1_004_000);
  assert.equal(clip.actionClock, 'clip');
  assert.equal(clip.clipSeconds, 4);
  assert.equal(clip.actions[3].tStart, 1.7);
  const job = mkdtempSync(join(tmpdir(), 'browser-take-'));
  mkdirSync(join(job, 'capture'), { recursive: true });
  writeFileSync(join(job, 'capture', 'receipt.json'), JSON.stringify({ clips: { w01: clip } }));
  const run = spawnSync(process.execPath, [join(scripts, 'validate-pointer-path.mjs'), job], { encoding: 'utf8' });
  const report = JSON.parse(readFileSync(join(job, 'qa', 'pointer-path.json'), 'utf8'));
  assert.equal(run.status, 0, run.stdout + run.stderr);
  assert.equal(report.ok, true);
});

test('build-picture rejects a source the composition cannot play', () => {
  assert.equal(checkMediaSource({ kind: 'screen-in-context', src: 'capture/w01.webm' }), null);
  assert.equal(checkMediaSource({ kind: 'broll', src: 'plates/a.png' }), null);
  assert.match(checkMediaSource({ kind: 'broll', src: 'notes.txt' }), /neither a still/);
  assert.match(checkMediaSource({ kind: 'screen-in-context' }), /no src/);
});
