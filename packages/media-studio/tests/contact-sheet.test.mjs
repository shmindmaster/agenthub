// Contact-sheet builder against REAL synthetic media. Run: node --test tests/contact-sheet.test.mjs
// Requires ffmpeg/ffprobe on PATH; skipped otherwise.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(resolve(here, '..'), 'scripts', 'build-contact-sheet.mjs');
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { windowsHide: true, timeout: 120000, stdio: ['ignore', 'ignore', 'inherit'] });
const run = (args) => { const r = spawnSync(process.execPath, [script, ...args], { windowsHide: true, encoding: 'utf8' }); return { code: r.status, out: (r.stdout || '') + (r.stderr || '') }; };
function hasFfmpeg() {
  try { execFileSync('ffmpeg', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); return true; } catch { return false; }
}
const probeSize = (p) => {
  const [w, h] = execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0:s=x', p], { windowsHide: true }).toString().trim().split('x').map(Number);
  return { w, h };
};
const ok = hasFfmpeg();
const scratch = mkdtempSync(join(tmpdir(), 'ms-contact-'));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));

function movingClip(out, seconds) {
  ff(['-f', 'lavfi', '-i', `testsrc2=size=640x400:rate=25:duration=${seconds}`, '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', out]);
}
function beat(id, from, actionTimes, resultAt) {
  return {
    beat: id, t_start: from, t_end: from + 2.5, slot_start: from, slot_end: from + 3,
    screen: { clip: id, kind: 'screen', visible_from: from, visible_until: from + 3, changes_from_previous: true },
    actions: actionTimes.map((t, i) => ({ kind: 'click', label: `act ${id}${i}`, narrated: true, action_time: t })),
    result: resultAt === undefined ? null : { label: `res ${id}`, visible_at: resultAt },
  };
}

test('contact sheet: first + last + beat frames tiled into one PNG with an index', { skip: !ok }, () => {
  const root = join(scratch, 'job'); mkdirSync(join(root, 'plan'), { recursive: true }); mkdirSync(join(root, 'output'), { recursive: true });
  const cand = join(root, 'output', 'cand.mp4');
  movingClip(cand, 6);
  // two beats, three distinct times each: screen-on, action, result
  const sheet = { generator: 'media-studio/build-cue-sheet', mode: 'mapped', durationSeconds: 6, beats: [beat('B1', 0.5, [1.2], 1.9), beat('B2', 3.0, [3.8], 4.6)] };
  writeFileSync(join(root, 'plan', 'cue-sheet.json'), JSON.stringify(sheet));
  const r = run([root, cand, '--columns', '4', '--width', '200']);
  assert.equal(r.code, 0, r.out);
  const png = join(root, 'qa', 'contact-sheet.png');
  const idx = join(root, 'qa', 'contact-sheet.json');
  assert.ok(existsSync(png), 'png written');
  assert.ok(existsSync(idx), 'index written');
  const j = JSON.parse(readFileSync(idx, 'utf8'));
  assert.equal(j.generator, 'media-studio/build-contact-sheet');
  assert.equal(j.ok, true);
  assert.equal(j.frames.length, 8); // first + 6 + last
  assert.equal(j.frames[0].kind, 'first');
  assert.equal(j.frames[0].t, 0);
  assert.equal(j.frames.at(-1).kind, 'last');
  assert.ok(Math.abs(j.frames.at(-1).t - 5.9) < 0.05, `last frame at duration-0.1, got ${j.frames.at(-1).t}`);
  assert.deepEqual(j.frames.map((f) => f.kind).slice(1, 7), ['screen-on', 'action', 'result', 'screen-on', 'action', 'result']);
  assert.equal(j.frames[2].label, 'act B10');
  assert.equal(j.columns, 4);
  assert.equal(j.rows, 2);
  assert.equal(j.cell.w, 200);
  assert.match(j.candidate.sha256, /^[0-9a-f]{64}$/);
  assert.ok(j.candidate.bytes > 0);
  assert.ok(j.inputs.cueSheet.sha256);
  assert.ok(['burned', 'index-only'].includes(j.labels));
  const size = probeSize(png);
  assert.equal(size.w, 4 * j.cell.w);
  assert.equal(size.h, 2 * j.cell.h);
});

test('contact sheet: null times fall back to t_start; near-duplicate times dedupe within 0.1 s', { skip: !ok }, () => {
  const root = join(scratch, 'job-null'); mkdirSync(join(root, 'plan'), { recursive: true });
  const cand = join(root, 'cand.mp4');
  movingClip(cand, 4);
  const b = beat('B1', 1.0, [null], null);
  b.screen.visible_from = null; // -> t_start (1.0)
  b.actions[0].action_time = 1.05; // within 0.1 s of t_start -> deduped
  b.result = { label: 'x', visible_at: null }; // -> t_start, deduped as well
  b.t_start = 1.0;
  writeFileSync(join(root, 'plan', 'cue-sheet.json'), JSON.stringify({ mode: 'plan', durationSeconds: 4, beats: [b] }));
  const r = run([root, cand, '--width', '160']);
  assert.equal(r.code, 0, r.out);
  const j = JSON.parse(readFileSync(join(root, 'qa', 'contact-sheet.json'), 'utf8'));
  assert.equal(j.frames.length, 3, JSON.stringify(j.frames)); // first, one at 1.0, last
  assert.deepEqual(j.frames.map((f) => f.index), [0, 1, 2]);
});

test('contact sheet: missing cue sheet exits 1 and points at build-cue-sheet.mjs', { skip: !ok }, () => {
  const root = join(scratch, 'job-nocue'); mkdirSync(root, { recursive: true });
  const cand = join(root, 'cand.mp4');
  movingClip(cand, 2);
  const r = run([root, cand]);
  assert.equal(r.code, 1);
  assert.match(r.out, /build it with build-cue-sheet\.mjs/);
});

test('contact sheet: missing candidate exits 1', { skip: !ok }, () => {
  const root = join(scratch, 'job-nocand'); mkdirSync(join(root, 'plan'), { recursive: true });
  writeFileSync(join(root, 'plan', 'cue-sheet.json'), JSON.stringify({ mode: 'plan', durationSeconds: 4, beats: [] }));
  const r = run([root, join(root, 'nope.mp4')]);
  assert.equal(r.code, 1);
  assert.match(r.out, /candidate not found/);
});
