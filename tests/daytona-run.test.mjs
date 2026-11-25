// Offline: argument rules and image naming of scripts/daytona-run.mjs. No provider is called.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fetchVerified, follow, imageName, parseArgs, retry } from '../scripts/daytona-run.mjs';

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

test('one argument is shell text; several keep their boundaries', () => {
  const command = (...words) => parseArgs(['--owner', 'x', '--', ...words]).command;
  assert.equal(command('npm ci && npm test'), 'npm ci && npm test');
  assert.equal(command('bash', '-c', "echo 'a b'"), `bash -c 'echo '"'"'a b'"'"''`);
  assert.equal(command('npm', 'run', 'test:unit'), 'npm run test:unit');
});

test('a cut log stream resumes after the last event, prints nothing twice and keeps the exit code', async () => {
  const seen = [];
  const log = (cursor, data) => ({ type: 'log', cursor, frame: { channel: 'stdout', data } });
  const handle = { calls: [], async *streamLogs(o) {
    handle.calls.push(o.cursor);
    if (handle.calls.length === 1) { yield log('1', 'a'); yield log('2', 'b'); throw Object.assign(new Error('cut'), { name: 'ConnectionError' }); }
    yield log('3', 'c'); yield { type: 'state', cursor: '4', result: { exitCode: 7 } }; yield { type: 'eof' };
  } };
  const out = { write: (d) => seen.push(d) };
  assert.equal(await follow(handle, { again: (s) => retry(s, { pause: 0 }), out, err: out }), 7);
  assert.deepEqual([seen.join(''), handle.calls], ['abc', [undefined, '2']]);
  const silent = { async *streamLogs() { yield { type: 'eof' }; } };
  assert.equal(await follow(silent, { out, err: out }), 1);
});

test('a download reaches its destination only when hash and size match', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'daytona-run-test-'));
  try {
    const local = join(dir, 'out', 'a.bin');
    const good = createHash('sha256').update('good').digest('hex');
    const box = (body, record) => ({ process: { run: async () => record }, fs: { downloadFile: async (_, to) => writeFileSync(to, body) } });
    const ok = { exitCode: 0, stdout: `${good}  /work/a.bin\n4\n` };
    await assert.rejects(fetchVerified(box('evil', ok), '/work/a.bin', local), /does not match/);
    await assert.rejects(fetchVerified(box('good', { exitCode: 0, stdout: `${good}  /work/a.bin\n5\n` }), '/work/a.bin', local), /does not match/);
    await assert.rejects(fetchVerified(box('', { exitCode: 1, stdout: '' }), '/work/a.bin', local), /not found/);
    assert.deepEqual([existsSync(local), existsSync(`${local}.part`)], [false, false]);
    assert.equal((await fetchVerified(box('good', ok), '/work/a.bin', local)).size, 4);
    assert.equal(readFileSync(local, 'utf8'), 'good');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

// daytona-run.mjs builds this path in pieces, so no search for the path finds its reader.
test('the default image has its Dockerfile', () => {
  const dockerfile = join(import.meta.dirname, '..', 'ci', 'daytona', 'Dockerfile');
  assert.match(readFileSync(dockerfile, 'utf8'), /^FROM /m);
});
