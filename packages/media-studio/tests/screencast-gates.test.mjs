// Product-picture gates against REAL encoded media, not hand-built JSON alone.
// Run: node --test packages/media-studio/tests/screencast-gates.test.mjs   (also discovered by tests/Run-AllTests.ps1)
// Requires ffmpeg/ffprobe on PATH (the same requirement the compositor has).
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, cpSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const pkg = resolve(here, '..');
const validator = join(pkg, 'scripts', 'validate-product-picture.mjs');
const encodedValidator = join(pkg, 'scripts', 'validate-encoded-picture.mjs');
const compose = join(pkg, 'kit', 'screencast', 'compose-screencast.mjs');
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args], { stdio: ['ignore', 'ignore', 'inherit'] });
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const run = (script, args, env = {}) => {
  const r = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', env: { ...process.env, AGENTHUB_ROOT: '', ...env } });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
};

function hasFfmpeg() {
  try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { stdio: 'ignore' }); return true; } catch { return false; }
}

/** A moving synthetic clip: testsrc2 (changes every frame) at the delivery frame. */
function movingClip(out, seconds) {
  ff(['-f', 'lavfi', '-i', `testsrc2=size=1600x1000:rate=30:duration=${seconds}`, '-c:v', 'libvpx', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '1M', '-pix_fmt', 'yuv420p', out]);
}
/** A still looped into a video container — what a screenshot posing as a screencast looks like on disk. */
function stillClip(out, seconds) {
  const png = out.replace(/\.webm$/, '.png');
  ff(['-f', 'lavfi', '-i', 'testsrc2=size=1600x1000:rate=1:duration=1', '-frames:v', '1', png]);
  ff(['-loop', '1', '-i', png, '-t', String(seconds), '-r', '30', '-c:v', 'libvpx', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '600k', '-pix_fmt', 'yuv420p', out]);
}

function writeJob(root, { screenSeconds = 16, cardSeconds = 6, clipFile = 'clips/S02.webm', extraClip = {}, beat = {}, receipt, intent = 'viewer-facing', plan = true, kind = 'product-screencast' } = {}) {
  mkdirSync(join(root, 'story'), { recursive: true });
  mkdirSync(join(root, 'capture', 'clips'), { recursive: true });
  mkdirSync(join(root, 'output'), { recursive: true });
  writeFileSync(join(root, 'job.json'), JSON.stringify({ kind, title: 't', workspace: root, repositoryWritePolicy: 'read-only', programForm: 'role-demo', intent }));
  writeFileSync(join(root, 'story', 'storyboard.json'), JSON.stringify({
    title: 't',
    beats: [
      { id: 'S01', order: 1, sceneRole: 'hook', narration: 'n', visualMode: 'slide', visualArchetype: 'kinetic-statement', durationSeconds: cardSeconds },
      { id: 'S02', order: 2, sceneRole: 'hero', narration: 'n', visualMode: 'screen', visualArchetype: 'screen-in-context', durationSeconds: screenSeconds, ...beat },
    ],
  }));
  writeFileSync(join(root, 'story', 'narration-timeline.json'), JSON.stringify({
    durationSeconds: cardSeconds + screenSeconds,
    segments: [
      { id: 'S01', scene: 'S01', text: 'hook', startSeconds: 0, durationSeconds: cardSeconds, endSeconds: cardSeconds },
      { id: 'S02', scene: 'S02', text: 'hero', startSeconds: cardSeconds, durationSeconds: screenSeconds, endSeconds: cardSeconds + screenSeconds },
    ],
  }));
  writeFileSync(join(root, 'capture', 'manifest.json'), JSON.stringify({ clips: [{ id: 'S02', file: clipFile, segments: ['S02'], ...extraClip }] }));
  if (plan) writeFileSync(join(root, 'story', 'capture-plan.json'), JSON.stringify({ scenes: [{ sceneId: 'S01', kind: 'card' }, { sceneId: 'S02', kind: 'interaction', action: 'click Submit', expectedResult: 'toast', startState: 'form ready', resultState: 'toast visible', provesClaim: 'submit sends the request', clip: clipFile }] }));
  if (receipt) writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(receipt));
}
const goodReceipt = (file, hash, over = {}) => ({
  schemaVersion: '1.0.0', generator: 'media-studio/record-job', clips: { S02: { file, sha256: hash, recast: 'full', valid: true, events: { pointerMoves: 24, clicks: 1, keystrokes: 0, scrolls: 0, expectations: 1, expectationsObserved: 1, expectationsFailed: [] }, ...over } },
});

const ffmpegAvailable = hasFfmpeg();
const scratch = mkdtempSync(join(tmpdir(), 'ms-gates-'));
test.after(() => rmSync(scratch, { recursive: true, force: true }));

test('plan gate: receipt-bound moving capture passes', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'ok');
  writeJob(root);
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 16);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  const r = run(validator, [root]);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /"ok":true/);
});

test('plan gate: a still looped into a .webm fails on the receipt (no live-session hash)', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'still');
  writeJob(root);
  stillClip(join(root, 'capture', 'clips', 'S02.webm'), 12);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', 'deadbeef')));
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /not in capture\/receipt\.json/);
});

test('plan gate: missing receipt fails even when the clip exists', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'noreceipt');
  writeJob(root);
  movingClip(join(root, 'capture', 'clips', 'S02.webm'), 12);
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /missing capture\/receipt\.json/);
});

test('plan gate: receipt without pointer motion or observed response fails an interaction beat', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'nopointer');
  writeJob(root);
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 12);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip), { events: { pointerMoves: 0, clicks: 0, keystrokes: 0, scrolls: 0, expectations: 1, expectationsObserved: 0, expectationsFailed: ['toast'] } })));
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /no pointer motion/);
  assert.match(r.out, /no click\/type\/scroll/);
});

test('plan gate: a 3s take frozen across 20s of narration fails (the 250-01 defect)', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'frozen');
  writeJob(root, { screenSeconds: 20 });
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 3);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /would be frozen/);
});

test('plan gate: fit retiming beyond ±20% fails', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'retime');
  writeJob(root, { screenSeconds: 20, extraClip: { fit: 'fit' } });
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 8);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /fit retimes/);
});

test('plan gate: intent=draft no longer skips the picture rules', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'draft');
  writeJob(root, { intent: 'draft' });
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0);
  assert.doesNotMatch(r.out, /skipped/);
});

test('plan gate: interaction missing provesClaim or identical start/result fails', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'nochain');
  writeJob(root);
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 12);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  writeFileSync(join(root, 'story', 'capture-plan.json'), JSON.stringify({
    scenes: [
      { sceneId: 'S01', kind: 'card' },
      { sceneId: 'S02', kind: 'interaction', action: 'click Submit', expectedResult: 'toast', startState: 'form ready', resultState: 'form ready', clip: 'clips/S02.webm' },
    ],
  }));
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0, r.out);
  assert.match(r.out, /missing provesClaim/);
  assert.match(r.out, /startState and resultState are identical/);
});

test('plan gate: Recast fallback fails unless the job allows it with a reason', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'recast');
  writeJob(root);
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 12);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip), { recast: 'fallback', recastNote: 'ffmpeg exit 1' })));
  const r = run(validator, [root]);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /Recast did not run/);
});

test('compose: refuses to run when the product-picture validator is not resolvable', { skip: !ffmpegAvailable }, () => {
  const kitCopy = join(scratch, 'kit-no-validator');
  mkdirSync(kitCopy, { recursive: true });
  cpSync(compose, join(kitCopy, 'compose-screencast.mjs'));
  const root = join(scratch, 'compose-nogate');
  writeJob(root);
  const r = spawnSync(process.execPath, [join(kitCopy, 'compose-screencast.mjs'), root, 'x'], { encoding: 'utf8', env: { ...process.env, AGENTHUB_ROOT: join(scratch, 'nowhere') } });
  const out = (r.stdout || '') + (r.stderr || '');
  // Either the hard-coded repo path resolves (dev machine) and the gate runs, or it must throw — never compose silently.
  assert.ok(r.status !== 0, out);
  assert.match(out, /validator not resolvable|product-picture/);
});

test('encoded gate: a master built from the capture passes; a master with a dead 16s screen fails', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'encoded');
  writeJob(root, { screenSeconds: 16, cardSeconds: 6 });
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 16);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  // Good master: 6s designed card (gray with text-free block) + the 12s capture.
  const card = join(root, 'capture', 'clips', 'S01-card.png');
  ff(['-f', 'lavfi', '-i', 'color=c=0x334455:size=1600x1000:rate=1:duration=1', '-frames:v', '1', card]);
  const good = join(root, 'output', 'good.mp4');
  ff(['-loop', '1', '-t', '6', '-i', card, '-i', clip, '-filter_complex', '[0:v]fps=30,format=yuv420p[a];[1:v]fps=30,format=yuv420p[b];[a][b]concat=n=2:v=1:a=0[v]', '-map', '[v]', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', good]);
  writeFileSync(join(root, 'output', 'good-compose-map.json'), JSON.stringify({ groups: [{ segments: ['S01'], clipId: 'S01-card', file: 'clips/S01-card.png', isImage: true }, { segments: ['S02'], clipId: 'S02', file: 'clips/S02.webm', fit: 'cut' }] }));
  const ok = run(encodedValidator, [root, good, '--out', 'qa/encoded-good.json']);
  assert.equal(ok.code, 0, ok.out);
  const rep = JSON.parse(readFileSync(join(root, 'qa', 'encoded-good.json'), 'utf8'));
  assert.equal(rep.ok, true);
  assert.equal(rep.segments.find((s) => s.id === 'S02').bound, true);

  // Bad master: same card, then a frozen frame of the capture for 12s (a screenshot substituted for the take).
  const frozen = join(root, 'capture', 'clips', 'frozen.png');
  ff(['-ss', '1', '-i', clip, '-frames:v', '1', frozen]);
  const bad = join(root, 'output', 'bad.mp4');
  ff(['-loop', '1', '-t', '6', '-i', card, '-loop', '1', '-t', '16', '-i', frozen, '-filter_complex', '[0:v]fps=30,format=yuv420p[a];[1:v]fps=30,format=yuv420p[b];[a][b]concat=n=2:v=1:a=0[v]', '-map', '[v]', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', bad]);
  writeFileSync(join(root, 'output', 'bad-compose-map.json'), JSON.stringify({ groups: [{ segments: ['S01'], clipId: 'S01-card', file: 'clips/S01-card.png', isImage: true }, { segments: ['S02'], clipId: 'S02', file: 'clips/S02.webm', fit: 'cut' }] }));
  const notOk = run(encodedValidator, [root, bad, '--out', 'qa/encoded-bad.json']);
  assert.notEqual(notOk.code, 0);
  assert.match(notOk.out, /dead screen/);
});

test('encoded gate: a card spliced where the capture belongs fails source binding', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'encoded-substitute');
  writeJob(root, { screenSeconds: 16, cardSeconds: 6 });
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 16);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  const fake = join(root, 'output', 'fake.mp4');
  // A moving but unrelated picture (a different generator) in the S02 slot.
  ff(['-f', 'lavfi', '-i', 'color=c=0x334455:size=1600x1000:rate=30:duration=6', '-f', 'lavfi', '-i', 'mandelbrot=size=1600x1000:rate=30', '-t', '22', '-filter_complex', '[0:v]format=yuv420p[a];[1:v]trim=duration=16,setpts=PTS-STARTPTS,format=yuv420p[b];[a][b]concat=n=2:v=1:a=0[v]', '-map', '[v]', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', fake]);
  writeFileSync(join(root, 'output', 'fake-compose-map.json'), JSON.stringify({ groups: [{ segments: ['S01'], clipId: 'S01-card', file: 'clips/S01-card.png', isImage: true }, { segments: ['S02'], clipId: 'S02', file: 'clips/S02.webm', fit: 'cut' }] }));
  const r = run(encodedValidator, [root, fake, '--out', 'qa/encoded-fake.json']);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /does not match any frame of the captured clip/);
});

test('compose: a pause between segments is picture time, so the picture runs the full timeline', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'compose-pause');
  writeJob(root, { screenSeconds: 16, cardSeconds: 6 });
  // Re-time the timeline with a 0.6 s pause before S02: S01 0-6, S02 6.6-22.6, total 22.6.
  writeFileSync(join(root, 'story', 'narration-timeline.json'), JSON.stringify({
    durationSeconds: 22.6,
    segments: [
      { id: 'S01', scene: 'S01', text: 'hook', startSeconds: 0, durationSeconds: 6, endSeconds: 6 },
      { id: 'S02', scene: 'S02', text: 'hero', startSeconds: 6.6, durationSeconds: 16, endSeconds: 22.6 },
    ],
  }));
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 17);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  const r = run(compose, [root, 'p']);
  assert.equal(r.code, 0, r.out);
  const map = JSON.parse(readFileSync(join(root, 'output', 'p-compose-map.json'), 'utf8'));
  const s01 = map.groups.find((g) => g.segments[0] === 'S01');
  assert.equal(s01.needSeconds, 6.6, 'the pause after S01 belongs to its picture');
  assert.ok(Math.abs(map.pictureSeconds - 22.6) < 0.35, `picture ${map.pictureSeconds}s should run the whole 22.6 s timeline`);
});

test('encoded gate: a static run straddling a pause is judged as the neighbouring beat, not as a card', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'encoded-pause');
  writeJob(root, { screenSeconds: 16, cardSeconds: 6 });
  writeFileSync(join(root, 'story', 'narration-timeline.json'), JSON.stringify({
    durationSeconds: 22.6,
    segments: [
      { id: 'S01', scene: 'S01', text: 'hook', startSeconds: 0, durationSeconds: 6, endSeconds: 6 },
      { id: 'S02', scene: 'S02', text: 'hero', startSeconds: 6.6, durationSeconds: 16, endSeconds: 22.6 },
    ],
  }));
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 16);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  const card = join(root, 'capture', 'clips', 'S01-card.png');
  ff(['-f', 'lavfi', '-i', 'color=c=0x334455:size=1600x1000:rate=1:duration=1', '-frames:v', '1', card]);
  // Card 0-6.6 (the pause is held on the card), then the moving capture 6.6-22.6.
  const good = join(root, 'output', 'good.mp4');
  ff(['-loop', '1', '-t', '6.6', '-i', card, '-i', clip, '-filter_complex', '[0:v]fps=30,format=yuv420p[a];[1:v]fps=30,format=yuv420p[b];[a][b]concat=n=2:v=1:a=0[v]', '-map', '[v]', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', good]);
  writeFileSync(join(root, 'output', 'good-compose-map.json'), JSON.stringify({ groups: [{ segments: ['S01'], clipId: 'S01-card', file: 'clips/S01-card.png', isImage: true }, { segments: ['S02'], clipId: 'S02', file: 'clips/S02.webm', fit: 'cut' }] }));
  const ok = run(encodedValidator, [root, good, '--out', 'qa/encoded-pause.json']);
  assert.equal(ok.code, 0, ok.out);
  const rep = JSON.parse(readFileSync(join(root, 'qa', 'encoded-pause.json'), 'utf8'));
  assert.ok(rep.staticRuns.every((r) => r.segment !== null), 'every static run is attributed to a segment');
  assert.ok(!ok.out.includes('card held'), 'no false card-held error from the pause');
});
