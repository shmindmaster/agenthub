// cloud-render planner tests: argument parsing, concat-list parsing and local->container path mapping. No Azure calls.
// Run: node --test tests/cloud-render.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { parseArgs, parseConcatList, mapArgs, jobResources } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-render.mjs')).href);

test('parseArgs splits options from the command after --', () => {
  const { sub, opts, rest } = parseArgs(['ffmpeg', '--name', 'drill', '--dry-run', '--out', 'a.mp4', '--', '-i', 'x.wav', 'out.mp4']);
  assert.equal(sub, 'ffmpeg');
  assert.equal(opts.name, 'drill');
  assert.equal(opts.dryRun, true);
  assert.deepEqual(opts.out, ['a.mp4']);
  assert.deepEqual(rest, ['-i', 'x.wav', 'out.mp4']);
});

test('parseArgs maps kebab options to camelCase', () => {
  const { opts } = parseArgs(['remotion', '--comp', 'Briefing', '--public-dir=pub', '--recast-opts', '{}']);
  assert.equal(opts.publicDir, 'pub');
  assert.equal(opts.recastOpts, '{}');
});

test('parseConcatList reads quoted, escaped and directive lines', () => {
  const parsed = parseConcatList("ffconcat version 1.0\nfile 'D:/cards/a.png'\nduration 2.5\nfile 'it'\\''s.png'\nfile plain\\ name.png\n");
  assert.deepEqual(parsed.filter((p) => p.file).map((p) => p.file), ['D:/cards/a.png', "it's.png", 'plain name.png']);
});

test('parseConcatList rejects ordinary text files', () => {
  assert.equal(parseConcatList('hello world\nfile is not a directive here\n'), null);
  assert.equal(parseConcatList('duration 2\n'), null);
});

test('mapArgs maps inputs, outputs, --flag=path and leaves filters alone', () => {
  const dir = mkdtempSync(join(tmpdir(), 'cr-test-'));
  writeFileSync(join(dir, 'voice.wav'), 'x');
  mkdirSync(join(dir, 'public'));
  const seen = { files: [], dirs: [] };
  const ctx = {
    cwd: dir,
    outputs: new Map([[join(dir, 'film.mp4'), '/job/out/film.mp4']]),
    addFile: (a) => (seen.files.push(a), `/job/in/f/${a.split(/[\\/]/).pop()}`),
    addDir: (a) => (seen.dirs.push(a), '/job/in/d0/public'),
    addConcat: () => null,
  };
  const out = mapArgs(['-i', 'voice.wav', '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '--public-dir=public', '-preset', 'veryfast', 'film.mp4'], ctx);
  assert.deepEqual(out, ['-i', '/job/in/f/voice.wav', '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '--public-dir=/job/in/d0/public', '-preset', 'veryfast', '/job/out/film.mp4']);
  assert.equal(seen.files.length, 1);
  assert.equal(seen.dirs.length, 1);
});

test('mapArgs leaves a missing path untouched', () => {
  const ctx = { cwd: tmpdir(), outputs: new Map(), addFile: () => assert.fail('no upload'), addDir: () => assert.fail('no upload'), addConcat: () => null };
  assert.deepEqual(mapArgs(['nope/missing.mp4'], ctx), ['nope/missing.mp4']);
});

test('jobResources gives --cpu its matching memory and refuses mismatched sizes', () => {
  assert.deepEqual(jobResources(undefined, undefined), { cpu: 4, memory: '8Gi' });
  assert.deepEqual(jobResources('8', undefined, { cpu: 8, memory: '16Gi' }), { cpu: 8, memory: '16Gi' });
  assert.deepEqual(jobResources(undefined, '16', { cpu: 8, memory: '16Gi' }), { cpu: 8, memory: '16Gi' });
  assert.deepEqual(jobResources('2', '4Gi'), { cpu: 2, memory: '4Gi' });
  assert.throws(() => jobResources('4', '16'), /memory = 2 x vCPU/);
});

test('jobResources refuses a request above the job definition maximum', () => {
  const base = { cpu: 4, memory: '8Gi' };
  assert.deepEqual(jobResources('4', undefined, base), { cpu: 4, memory: '8Gi' });
  assert.throws(() => jobResources('16', undefined, base), /exceeds the job definition's maximum of 4 vCPU/);
  assert.throws(() => jobResources('8', '16Gi', base), /exceeds the job definition's maximum/);
  assert.throws(() => jobResources(undefined, '16', base), /exceeds the job definition's maximum/);
});

test('waitForResult throws on deadline expiry', async () => {
  const { waitForResult } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-render.mjs')).href);
  const c = {
    storage: { getText: async () => null },
    arm: async () => ({}),
    jobUrl: 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.App/jobs/job',
  };
  await assert.rejects(waitForResult({}, c, 'job-1', 'exec-1', Date.now() - 1), /deadline exceeded/);
});

test('runChunked calls stop for sibling chunks when one fails', async () => {
  const { runChunked, stopExecution } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-render.mjs')).href);
  const stopped = [];
  const fakeStopExecution = (cfg, c, execName) => {
    stopped.push(execName);
    return Promise.resolve();
  };
  let execIndex = 0;
  const fakeClients = () => ({
    jobUrl: 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.App/jobs/job',
    storage: {
      exists: async () => false,
      putFile: async () => {},
      putText: async () => {},
      getText: async () => null,
      getFile: async () => {},
    },
    arm: async (method, url) => {
      if (method === 'GET' && url.includes('/jobs/job?')) {
        return {
          properties: {
            configuration: { replicaTimeout: 7200 },
            template: { containers: [{ resources: { cpu: 4, memory: '8Gi' }, env: [] }] },
          },
        };
      }
      if (method === 'POST' && url.includes('/start?')) return { name: `exec-${++execIndex}` };
      return {};
    },
  });
  const fakeWaitForResult = async (cfg, c, jobId, execName, deadlineMs) => {
    if (execName === 'exec-2') throw new Error('chunk 2 failed');
    await new Promise((r) => setTimeout(r, 50));
    return { result: { ok: true, outputs: [] }, exec: {} };
  };
  const opts = { chunks: 3, comp: 'Test', out: ['out.mp4'], cpu: 4, memory: '8Gi', name: 'test', kit: tmpdir() };
  await assert.rejects(runChunked(opts, [], {}, { clients: fakeClients, stopExecution: fakeStopExecution, waitForResult: fakeWaitForResult }), /chunk 2 failed/);
  assert.deepEqual(stopped.sort(), ['exec-1', 'exec-2', 'exec-3']);
});

test('runChunked stops sibling chunks when one reports ok: false', async () => {
  const { runChunked, stopExecution } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-render.mjs')).href);
  const stopped = [];
  const fakeStopExecution = (cfg, c, execName) => {
    stopped.push(execName);
    return Promise.resolve();
  };
  let execIndex = 0;
  const fakeClients = () => ({
    jobUrl: 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.App/jobs/job',
    storage: {
      exists: async () => false,
      putFile: async () => {},
      putText: async () => {},
      getText: async () => null,
      getFile: async () => {},
    },
    arm: async (method, url) => {
      if (method === 'GET' && url.includes('/jobs/job?')) {
        return {
          properties: {
            configuration: { replicaTimeout: 7200 },
            template: { containers: [{ resources: { cpu: 4, memory: '8Gi' }, env: [] }] },
          },
        };
      }
      if (method === 'POST' && url.includes('/start?')) return { name: `exec-${++execIndex}` };
      return {};
    },
  });
  const fakeWaitForResult = async (cfg, c, jobId, execName) => {
    if (execName === 'exec-2') return { result: { ok: false, error: 'render crashed' }, exec: {} };
    await new Promise((r) => setTimeout(r, 50));
    return { result: { ok: true, outputs: [] }, exec: {} };
  };
  const opts = { chunks: 3, comp: 'Test', out: ['out.mp4'], cpu: 4, memory: '8Gi', name: 'test', kit: tmpdir() };
  await assert.rejects(runChunked(opts, [], {}, { clients: fakeClients, stopExecution: fakeStopExecution, waitForResult: fakeWaitForResult }), /chunks failed: 2 .*render crashed/);
  assert.deepEqual(stopped.sort(), ['exec-1', 'exec-3']);
});
