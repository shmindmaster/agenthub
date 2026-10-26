// cloud-render planner tests: argument parsing, concat-list parsing and local->container path mapping. No Azure calls.
// Run: node --test tests/cloud-render.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { parseArgs, parseConcatList, mapArgs } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-render.mjs')).href);

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
