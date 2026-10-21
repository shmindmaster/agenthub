// Frame-integrity gate against REAL synthetic media. Run: node --test tests/frame-integrity.test.mjs
// Requires ffmpeg/ffprobe on PATH; skipped otherwise.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(resolve(here, '..'), 'scripts', 'validate-frame-integrity.mjs');
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { windowsHide: true, timeout: 120000, stdio: ['ignore', 'ignore', 'inherit'] });
const run = (args) => { const r = spawnSync(process.execPath, [script, ...args], { windowsHide: true, encoding: 'utf8' }); return { code: r.status, out: (r.stdout || '') + (r.stderr || '') }; };
function hasFfmpeg() {
  try { execFileSync('ffmpeg', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); return true; } catch { return false; }
}
const ok = hasFfmpeg();
const scratch = mkdtempSync(join(tmpdir(), 'ms-integrity-'));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));
const enc = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];

function jobWith(name) { const root = join(scratch, name); mkdirSync(join(root, 'plan'), { recursive: true }); return root; }
const report = (root) => JSON.parse(readFileSync(join(root, 'qa', 'frame-integrity.json'), 'utf8'));

test('frame integrity: a plain testsrc2 clip passes', { skip: !ok }, () => {
  const root = jobWith('pass');
  const cand = join(root, 'ok.mp4');
  ff(['-f', 'lavfi', '-i', 'testsrc2=size=1280x800:rate=25:duration=4', ...enc, cand]);
  const r = run([root, cand]);
  assert.equal(r.code, 0, r.out);
  const j = report(root);
  assert.equal(j.ok, true);
  assert.equal(j.generator, 'media-studio/validate-frame-integrity');
  assert.deepEqual(j.tiled, []);
  assert.deepEqual(j.lumaJumps, []);
  assert.ok(j.sampled >= 7, `sampled ${j.sampled}`);
  assert.match(j.candidate.sha256, /^[0-9a-f]{64}$/);
  assert.ok(j.warnings.some((w) => /no cue sheet/i.test(w)), 'warns that nothing is exempt without a cue sheet');
});

test('frame integrity: a left half repeated on the right fails tiled-frame', { skip: !ok }, () => {
  const root = jobWith('tiled');
  const cand = join(root, 'tiled.mp4');
  ff(['-f', 'lavfi', '-i', 'testsrc2=size=1280x800:rate=25:duration=3', '-vf', 'crop=iw/2:ih:0:0,split[a][b];[a][b]hstack', ...enc, cand]);
  const r = run([root, cand]);
  assert.equal(r.code, 1, r.out);
  const j = report(root);
  assert.equal(j.ok, false);
  assert.ok(j.tiled.length >= 4);
  assert.equal(j.tiled[0].axis, 'horizontal');
  assert.ok(j.errors.some((e) => /^tiled-frame at t=[\d.]+s: left and right halves are near-identical \(PSNR [\d.]+ dB > 32 dB/.test(e)), j.errors[0]);
});

test('frame integrity: a top half repeated on the bottom fails tiled-frame (vertical)', { skip: !ok }, () => {
  const root = jobWith('tiled-v');
  const cand = join(root, 'tiled-v.mp4');
  ff(['-f', 'lavfi', '-i', 'testsrc2=size=1280x800:rate=25:duration=3', '-vf', 'crop=iw:ih/2:0:0,split[a][b];[a][b]vstack', ...enc, cand]);
  const r = run([root, cand]);
  assert.equal(r.code, 1, r.out);
  const j = report(root);
  assert.equal(j.tiled[0].axis, 'vertical');
  assert.ok(j.errors.some((e) => /top and bottom halves are near-identical/.test(e)));
});

function blackWhite(root) {
  const cand = join(root, 'bw.mp4');
  ff(['-f', 'lavfi', '-i', 'color=c=black:size=1280x800:rate=25:duration=2', '-f', 'lavfi', '-i', 'color=c=white:size=1280x800:rate=25:duration=2',
    '-filter_complex', '[0:v][1:v]concat=n=2:v=1:a=0', ...enc, cand]);
  return cand;
}

test('frame integrity: black then white fails luma-jump without a cue sheet', { skip: !ok }, () => {
  const root = jobWith('jump');
  const r = run([root, blackWhite(root)]);
  assert.equal(r.code, 1, r.out);
  const j = report(root);
  assert.equal(j.lumaJumps.length, 1);
  assert.ok(Math.abs(j.lumaJumps[0].t - 2) < 0.51, `jump at ${j.lumaJumps[0].t}`);
  assert.ok(j.lumaJumps[0].delta > 200);
  assert.ok(j.errors.some((e) => /^luma-jump at t=[\d.]+s: mean luma [\d.]+ -> [\d.]+ \(delta [\d.]+ > 40\) and no cut is declared there/.test(e)), j.errors.join('|'));
});

test('frame integrity: the same jump passes when the cue-sheet edl declares a cut at 2.0 s', { skip: !ok }, () => {
  const root = jobWith('jump-exempt');
  const cand = blackWhite(root);
  writeFileSync(join(root, 'plan', 'cue-sheet.json'), JSON.stringify({ mode: 'mapped', durationSeconds: 4, edl: [{ segments: ['A'], clip: 'A', startSeconds: 0, needSeconds: 2 }, { segments: ['B'], clip: 'B', startSeconds: 2.0, needSeconds: 2 }], beats: [] }));
  const r = run([root, cand]);
  assert.equal(r.code, 0, r.out);
  const j = report(root);
  assert.equal(j.ok, true);
  assert.deepEqual(j.lumaJumps, []);
  assert.ok(j.exemptCuts.length >= 1);
  assert.ok(j.inputs.cueSheet.sha256);
  assert.ok(!j.warnings.some((w) => /no cue sheet/i.test(w)));
});

test('frame integrity: an all-black clip is flat, never tiled', { skip: !ok }, () => {
  const root = jobWith('black');
  const cand = join(root, 'black.mp4');
  ff(['-f', 'lavfi', '-i', 'color=c=black:size=1280x800:rate=25:duration=3', ...enc, cand]);
  const r = run([root, cand]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(report(root).tiled, []);
});

test('frame integrity: missing candidate fails closed', { skip: !ok }, () => {
  const root = jobWith('nocand');
  const r = run([root, join(root, 'missing.mp4')]);
  assert.equal(r.code, 1);
  assert.match(r.out, /candidate not found/);
});
