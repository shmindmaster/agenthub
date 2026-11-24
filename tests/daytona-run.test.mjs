// Offline: argument rules and image naming of scripts/daytona-run.mjs. No provider is called.
import test from 'node:test';
import assert from 'node:assert/strict';
import { imageName, parseArgs, retry } from '../scripts/daytona-run.mjs';

test('a run names its owner and exactly one command', () => {
  assert.throws(() => parseArgs(['--', 'ls']), /--owner/);
  assert.throws(() => parseArgs(['--owner', 'x']), /no command/);
  assert.throws(() => parseArgs(['--owner', 'x', '--script', 'a.sh', '--', 'ls']), /not both/);
  const o = parseArgs(['--owner', 'x', '--cpu', '4', '--get', '/work/a=b/a', '--', 'npm', 'test']);
  assert.deepEqual([o.owner, o.cpu, o.get, o.command], ['x', 4, [['/work/a', 'b/a']], 'npm test']);
});

test('size and lifetime are bounded, and an unknown option refuses', () => {
  assert.throws(() => parseArgs(['--owner', 'x', '--minutes', '0', '--', 'ls']), /--minutes/);
  assert.throws(() => parseArgs(['--owner', 'x', '--cpu', '33', '--', 'ls']), /--cpu/);
  assert.throws(() => parseArgs(['--owner', 'x', '--macos', 'yes', '--', 'ls']), /unknown option/);
});

test('an edited Dockerfile gets a new image name; line endings do not change it', () => {
  assert.equal(imageName('FROM a\n'), imageName('FROM a\r\n'));
  assert.notEqual(imageName('FROM a\n'), imageName('FROM b\n'));
});

test('a dropped connection is retried a bounded number of times; any other error is not', async () => {
  let calls = 0;
  const drop = (until) => async () => { if (++calls < until) throw new TypeError('fetch failed'); return 'ok'; };
  assert.equal(await retry(drop(3), { pause: 0 }), 'ok');
  assert.equal(calls, 3);
  calls = 0;
  await assert.rejects(retry(drop(99), { tries: 4, pause: 0 }), /fetch failed/);
  assert.equal(calls, 4);
  calls = 0;
  await assert.rejects(retry(async () => { calls++; throw new Error('quota exceeded'); }, { pause: 0 }), /quota/);
  assert.equal(calls, 1);
});
