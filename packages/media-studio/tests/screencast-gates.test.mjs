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
const releaseValidator = join(pkg, 'scripts', 'validate-viewer-release.mjs');
const compose = join(pkg, 'kit', 'screencast', 'compose-screencast.mjs');
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { windowsHide: true, timeout: 120000, stdio: ['ignore', 'ignore', 'inherit'] });
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const run = (script, args, env = {}) => {
  const r = spawnSync(process.execPath, [script, ...args], { windowsHide: true, encoding: 'utf8', env: { ...process.env, AGENTHUB_ROOT: '', ...env } });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
};

function hasFfmpeg() {
  try { execFileSync('ffmpeg', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); return true; } catch { return false; }
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
  cpSync(join(pkg, 'kit', 'screencast', 'campaign-contract.mjs'), join(kitCopy, 'campaign-contract.mjs'));
  const root = join(scratch, 'compose-nogate');
  writeJob(root);
  const r = spawnSync(process.execPath, [join(kitCopy, 'compose-screencast.mjs'), root, 'x'], { encoding: 'utf8', env: { ...process.env, AGENTHUB_ROOT: join(scratch, 'nowhere') } });
  const out = (r.stdout || '') + (r.stderr || '');
  // Either the hard-coded repo path resolves (dev machine) and the gate runs, or it must throw — never compose silently.
  assert.ok(r.status !== 0, out);
  assert.match(out, /validator not resolvable|product-picture/);
});

test('portrait campaign composes a bounded source reframe with timed graphic and binds the encoded source', { skip: !ffmpegAvailable, timeout: 180000 }, () => {
  const root = join(scratch, 'portrait-reframe');
  for (const dir of ['story', 'capture/clips', 'capture/graphics', 'evidence', 'output']) mkdirSync(join(root, dir), { recursive: true });
  const clip = join(root, 'capture', 'clips', 'S01.webm');
  ff(['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30:duration=10', '-c:v', 'libvpx', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '650k', '-pix_fmt', 'yuv420p', clip]);
  const label = join(root, 'capture', 'graphics', 'label.png');
  ff(['-f', 'lavfi', '-i', 'color=c=yellow@0.6:s=200x80:d=1,format=rgba', '-frames:v', '1', label]);
  const claim = join(root, 'evidence', 'claim.json'); writeFileSync(claim, '{"synthetic":true}');
  const region = { x: 0.275, y: 0, width: 0.45, height: 1 };
  const jobData = { kind: 'product-screencast', programForm: 'campaign-short', deliveryProfile: 'linkedin-4x5', intent: 'viewer-facing', campaign: {
    continuity: { mode: 'single-record', recordId: 'record-01', scenarioId: 'synthetic-01' },
    claims: [{ id: 'claim-01', text: 'An approval is visible.', asOf: '2026-09-22', segmentIds: ['S01'], evidence: { path: 'evidence/claim.json', sha256: sha(claim) } }],
    assets: [{ id: 'ui', path: 'capture/clips/S01.webm', sha256: sha(clip), origin: 'captured-ui', rights: 'synthetic capture' }, { id: 'label', path: 'capture/graphics/label.png', sha256: sha(label), origin: 'authored-graphic', rights: 'synthetic graphic' }],
    protectedRegions: [{ x: 550, y: 400, width: 350, height: 300 }], captionRegion: { x: 80, y: 930, width: 500, height: 100 },
  } };
  writeFileSync(join(root, 'job.json'), JSON.stringify(jobData));
  writeFileSync(join(root, 'story', 'narration-timeline.json'), JSON.stringify({ durationSeconds: 10, segments: [{ id: 'S01', scene: 'S01', text: 'Approve the plan.', startSeconds: 0, durationSeconds: 10 }] }));
  writeFileSync(join(root, 'story', 'storyboard.json'), JSON.stringify({ scenarioId: 'synthetic-01', beats: [{ id: 'S01', visualMode: 'screen', durationSeconds: 10 }] }));
  writeFileSync(join(root, 'story', 'capture-plan.json'), JSON.stringify({ scenes: [{ sceneId: 'S01', kind: 'interaction', action: 'click Approve', expectedResult: 'approved state', startState: 'pending', resultState: 'approved', provesClaim: 'approval visible', clip: 'clips/S01.webm' }] }));
  writeFileSync(join(root, 'story', 'timed-graphics.json'), JSON.stringify({ overlays: [{ assetId: 'label', x: 80, y: 180, width: 200, height: 80, startSeconds: 1, endSeconds: 3 }] }));
  writeFileSync(join(root, 'capture', 'manifest.json'), JSON.stringify({ clips: [{ id: 'S01', file: 'clips/S01.webm', segments: ['S01'], sourceRegion: region }] }));
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify({ schemaVersion: '1.0.0', generator: 'media-studio/record-job', clips: { S01: { file: 'clips/S01.webm', sha256: sha(clip), recast: 'full', valid: true, events: { pointerMoves: 10, clicks: 1, expectationsObserved: 1 } } } }));
  writeFileSync(join(root, 'evidence', 'demo-scenario-proof.json'), JSON.stringify({ scenarioId: 'synthetic-01', continuity: { entities: [{ type: 'client', id: 'record-01' }] } }));
  const composed = run(compose, [root, 'portrait']); assert.equal(composed.code, 0, composed.out);
  const mapPath = join(root, 'output', 'portrait-compose-map.json');
  assert.deepEqual(JSON.parse(readFileSync(mapPath, 'utf8')).groups[0].sourceRegion, region);
  const candidate = join(root, 'output', 'portrait-final.mp4'); cpSync(join(root, 'output', 'portrait-silent.mp4'), candidate);
  const encoded = run(encodedValidator, [root, candidate, '--out', 'qa/portrait-encoded.json']);
  assert.equal(encoded.code, 0, encoded.out);
  const report = JSON.parse(readFileSync(join(root, 'qa', 'portrait-encoded.json'), 'utf8'));
  assert.equal(report.segments[0].bound, true);
  cpSync(join(root, 'qa', 'portrait-encoded.json'), join(root, 'qa', 'encoded-picture.json'));
  const candidateSha = sha(candidate), scriptPath = join(root, 'story', 'screenplay.txt'), captionsPath = join(root, 'qa', 'captions.srt'), analyzerPath = join(root, 'qa', 'loudness.json');
  writeFileSync(scriptPath, 'Approve the plan after the result appears.');
  writeFileSync(captionsPath, '1\n00:00:00,000 --> 00:00:02,000\nApprove the plan.\n');
  writeFileSync(analyzerPath, JSON.stringify({ tool: 'ffmpeg-loudnorm', candidateSha256: candidateSha, integratedLufs: -16, truePeakDbtp: -1.5 }));
  const pass = { status: 'PASS', candidateSha256: candidateSha };
  writeFileSync(join(root, 'qa', 'viewer-release-evidence.json'), JSON.stringify({ candidate: { sha256: candidateSha }, captions: { ...pass, path: 'qa/captions.srt', sha256: sha(captionsPath), placementReviewed: true, region: jobData.campaign.captionRegion }, audio: { ...pass, integratedLufs: -16, truePeakDbtp: -1.5, analyzerReport: { path: 'qa/loudness.json', sha256: sha(analyzerPath) } }, pronunciation: { ...pass, reference: 'authored-script', scriptPath: 'story/screenplay.txt', scriptSha256: sha(scriptPath), releaseEligible: true }, encodedVisualReview: pass, titleReview: { ...pass, titleCount: 1 }, actionResultReview: { ...pass, events: [{ segmentId: 'S01', actionAtSeconds: 0, resultVisibleAtSeconds: 1, spokenResultAtSeconds: 1.5 }] }, storyReview: { ...pass, cta: 'Review the workflow' }, timedGraphicReview: { ...pass, controlsVisible: true, timingReviewed: true } }));
  const release = run(releaseValidator, [root, candidate]); assert.equal(release.code, 0, release.out);
  const map = JSON.parse(readFileSync(mapPath, 'utf8')); map.groups[0].sourceRegion.x = 0.1; writeFileSync(mapPath, JSON.stringify(map));
  const wrongRegion = run(encodedValidator, [root, candidate, '--out', 'qa/portrait-bad.json']);
  assert.notEqual(wrongRegion.code, 0); assert.match(wrongRegion.out, /differs from capture manifest/);
  const manifestPath = join(root, 'capture', 'manifest.json');
  writeFileSync(manifestPath, JSON.stringify({ clips: [{ id: 'S01', file: 'clips/S01.webm', segments: ['S01'] }] }));
  const missingRegion = run(compose, [root, 'portrait-missing']);
  assert.notEqual(missingRegion.code, 0); assert.match(missingRegion.out, /requires an explicit sourceRegion/);
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
  ff(['-f', 'lavfi', '-i', 'color=c=0x334455:size=1600x1000:rate=1:duration=1', '-frames:v', '1', join(root, 'capture', 'clips', 'S01-card.png')]);
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

test('encoded gate: a repeated source file binds by clip id, not by file order', { skip: !ffmpegAvailable }, () => {
  const root = join(scratch, 'encoded-samefile');
  writeJob(root, { screenSeconds: 16, cardSeconds: 6 });
  const clip = join(root, 'capture', 'clips', 'S02.webm');
  movingClip(clip, 16);
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify(goodReceipt('clips/S02.webm', sha(clip))));
  // Two distinct edits reuse one source video, each with its own clip id and crop. The wrong (first) clip shares
  // the file, so a file-first match binds S02 to the other clip's sourceRegion.
  const full = { x: 0, y: 0, width: 1, height: 1 };
  const leftHalf = { x: 0, y: 0, width: 0.5, height: 1 };
  writeFileSync(join(root, 'capture', 'manifest.json'), JSON.stringify({ clips: [
    { id: 'S02-b', file: 'clips/S02.webm', segments: ['S02-b'], sourceRegion: leftHalf },
    { id: 'S02', file: 'clips/S02.webm', segments: ['S02'], sourceRegion: full },
  ] }));
  const card = join(root, 'capture', 'clips', 'S01-card.png');
  ff(['-f', 'lavfi', '-i', 'color=c=0x334455:size=1600x1000:rate=1:duration=1', '-frames:v', '1', card]);
  const good = join(root, 'output', 'good.mp4');
  ff(['-loop', '1', '-t', '6', '-i', card, '-i', clip, '-filter_complex', '[0:v]fps=30,format=yuv420p[a];[1:v]fps=30,format=yuv420p[b];[a][b]concat=n=2:v=1:a=0[v]', '-map', '[v]', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', good]);
  const mapPath = join(root, 'output', 'good-compose-map.json');
  writeFileSync(mapPath, JSON.stringify({ groups: [{ segments: ['S01'], clipId: 'S01-card', file: 'clips/S01-card.png', isImage: true }, { segments: ['S02'], clipId: 'S02', file: 'clips/S02.webm', fit: 'cut', sourceRegion: full }] }));
  // The compose map agrees with the manifest clip that carries clip id S02: it must pass, not fail on the file twin.
  const ok = run(encodedValidator, [root, good, '--out', 'qa/encoded-samefile.json']);
  assert.equal(ok.code, 0, ok.out);
  assert.equal(JSON.parse(readFileSync(join(root, 'qa', 'encoded-samefile.json'), 'utf8')).ok, true);
  // A compose map whose crop matches the file twin (not clip id S02) contradicts the manifest: reject by identity.
  const map = JSON.parse(readFileSync(mapPath, 'utf8')); map.groups[1].sourceRegion = leftHalf; writeFileSync(mapPath, JSON.stringify(map));
  const mismatch = run(encodedValidator, [root, good, '--out', 'qa/encoded-samefile-b.json']);
  assert.notEqual(mismatch.code, 0);
  assert.match(mismatch.out, /differs from capture manifest/);
  map.groups[1].sourceRegion = full;
  map.groups[1].clipId = 'unknown';
  writeFileSync(mapPath, JSON.stringify(map));
  const ambiguous = run(encodedValidator, [root, good]);
  assert.notEqual(ambiguous.code, 0);
  assert.match(ambiguous.out, /does not resolve by clip id/);
  map.groups[1].clipId = 'S02';
  map.groups[1].file = 'clips/wrong.webm';
  writeFileSync(mapPath, JSON.stringify(map));
  const wrongFile = run(encodedValidator, [root, good]);
  assert.notEqual(wrongFile.code, 0);
  assert.match(wrongFile.out, /different source file/);
});
