// Picture-integrity gate against REAL encoded media: stretch, upscale, crop, bars, zoom and capture-ratio.
// Run: node --test tests/picture-integrity.test.mjs   (from the package root; needs ffmpeg/ffprobe on PATH)
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const pkg = resolve(here, '..');
const script = join(pkg, 'scripts', 'validate-picture-integrity.mjs');
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { windowsHide: true, timeout: 120000, stdio: ['ignore', 'ignore', 'inherit'] });
const hasFfmpeg = (() => {
  try { execFileSync('ffmpeg', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); return true; } catch { return false; }
})();
const opts = { skip: !hasFfmpeg && 'ffmpeg/ffprobe not on PATH' };

test('external caption canvas binds master and validates actual product rectangle', opts, () => {
  let source;
  const { root, cand } = buildJob({ clip: [1600, 1000], frame: [1600, 1000], candidate: (r, c, out) => {
    source = c;
    ff(['-i', c, '-vf', 'scale=1280:800:flags=lanczos,pad=1600:1000:160:0:color=0x101524', '-c:v', 'libx264', '-preset', 'ultrafast', out]);
  }});
  const sha = p => createHash('sha256').update(readFileSync(p)).digest('hex');
  const mapFile = join(root, 'output', 'film-compose-map.json');
  const map = JSON.parse(readFileSync(mapFile));
  map.finalEncoderTransform = { candidateSha256: sha(cand), sourceFile: 'capture/clips/W01.mp4', sourceSha256: sha(source), sourceWidth: 1600, sourceHeight: 1000, outputWidth: 1600, outputHeight: 1000, scaleWidth: 1280, scaleHeight: 800, padX: 160, padY: 0, crop: false, purpose: 'external-caption-band' };
  writeFileSync(mapFile, JSON.stringify(map));
  assert.equal(runGate(root, cand).report.ok, true);
  writeFileSync(join(root, 'story', 'narration-timeline.json'), JSON.stringify({ durationSeconds: 2, segments: [{ id: 'W01', startSeconds: 0, durationSeconds: 2 }] }));
  writeFileSync(join(root, 'capture', 'manifest.json'), JSON.stringify({ clips: [{ id: 'W01', file: 'clips/W01.mp4', segments: ['W01'] }] }));
  const encoded = () => {
    const r = spawnSync(process.execPath, [join(pkg, 'scripts', 'validate-encoded-picture.mjs'), root, cand], { windowsHide: true, encoding: 'utf8' });
    return { code: r.status, output: r.stdout + r.stderr };
  };
  assert.equal(encoded().code, 0, encoded().output);
  map.finalEncoderTransform.padY = 100;
  writeFileSync(mapFile, JSON.stringify(map));
  assert.equal(runGate(root, cand).report.ok, false, 'incorrect rectangle must fail against encoded master pixels');
  assert.notEqual(encoded().code, 0, 'encoded binding rejects incorrect product rectangle');
  map.finalEncoderTransform.padY = 0;
  map.finalEncoderTransform.sourceSha256 = '0'.repeat(64);
  writeFileSync(mapFile, JSON.stringify(map));
  assert.equal(runGate(root, cand).report.ok, false, 'stale master must fail');
  assert.notEqual(encoded().code, 0, 'encoded binding rejects stale master');
});

const roots = [];
test.after(() => { for (const r of roots) rmSync(r, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); });
const tempRoot = () => { const r = mkdtempSync(join(tmpdir(), 'picint-')); roots.push(r); return r; };

/** A busy synthetic clip: testsrc2 changes everywhere, so it has no flat border strip. */
const movingClip = (out, w, h, seconds = 2) => ff(['-f', 'lavfi', '-i', `testsrc2=size=${w}x${h}:rate=10:duration=${seconds}`, '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', out]);
/** The compositor's filter, applied for real, so the candidate has the bars the compose map predicts. */
const composeLike = (src, out, W, H, region) => {
  const crop = region ? `crop=iw*${region.width}:ih*${region.height}:iw*${region.x}:ih*${region.y},` : '';
  ff(['-i', src, '-vf', `${crop}scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2,format=yuv420p`, '-c:v', 'libx264', '-preset', 'ultrafast', out]);
};

/**
 * Build a job workspace: clip, receipt, compose map, job.json and (optionally) cue plan / cue sheet.
 * `candidate` is a function (jobRoot, clipPath) that writes output/<base>.mp4.
 */
function buildJob({ profile = 'briefing-board', clip = [1600, 1000], frame = [1600, 1000], region = null, recast = 'noZoom', dsf = 1, viewport, job = {}, cuePlan, cueSheet, candidate, extraReceipt = {}, receiptMissingClip = false } = {}) {
  const root = tempRoot();
  for (const d of ['capture/clips', 'output', 'qa', 'plan', 'story']) mkdirSync(join(root, d), { recursive: true });
  const clipPath = join(root, 'capture', 'clips', 'W01.mp4');
  movingClip(clipPath, clip[0], clip[1]);
  writeFileSync(join(root, 'job.json'), JSON.stringify({ kind: 'product-screencast', title: 't', deliveryProfile: profile, ...job }));
  const vp = viewport || { width: clip[0], height: clip[1] };
  writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify({
    schemaVersion: '1.0.0', generator: 'media-studio/record-job',
    clips: receiptMissingClip ? {} : { W01: { file: 'clips/W01.mp4', segments: ['W01'], viewport: vp, deviceScaleFactor: dsf, recast, ...extraReceipt } },
  }));
  writeFileSync(join(root, 'output', 'film-compose-map.json'), JSON.stringify({
    generator: 'media-studio/compose-screencast', base: 'film', deliveryProfile: profile, width: frame[0], height: frame[1], timelineSeconds: 2, groups: [
      { segments: ['W01'], startSeconds: 0, needSeconds: 2, clipId: 'W01', file: 'clips/W01.mp4', heldFromPrevious: false, sourceRegion: region, fit: 'hold', isImage: false },
    ],
  }));
  if (cuePlan) writeFileSync(join(root, 'story', 'cue-plan.json'), JSON.stringify(cuePlan));
  if (cueSheet) writeFileSync(join(root, 'plan', 'cue-sheet.json'), JSON.stringify(cueSheet));
  const cand = join(root, 'output', 'film.mp4');
  (candidate || ((r, c) => composeLike(c, cand, frame[0], frame[1], region)))(root, clipPath, cand);
  return { root, cand };
}
function runGate(root, cand, extra = []) {
  const r = spawnSync(process.execPath, [script, root, cand, ...extra], { windowsHide: true, encoding: 'utf8' });
  const reportPath = join(root, 'qa', 'picture-integrity.json');
  return { code: r.status, out: (r.stdout || '') + (r.stderr || ''), report: existsSync(reportPath) ? JSON.parse(readFileSync(reportPath, 'utf8')) : null };
}
const has = (res, re) => res.report.errors.some((e) => re.test(e));

test('clean: native-size full-region footage in a matching frame passes', opts, () => {
  const { root, cand } = buildJob({});
  const r = runGate(root, cand);
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.ok, true);
  assert.equal(r.report.generator, 'media-studio/validate-picture-integrity');
  assert.equal(r.report.frame.W, 1600);
  assert.equal(r.report.clips[0].verdict, 'pass');
  assert.equal(r.report.clips[0].native.w, 1600);
  assert.equal(r.report.clips[0].scaleX, 1);
  assert.deepEqual(r.report.clips[0].bars, { left: 0, right: 0, top: 0, bottom: 0 });
  assert.ok(r.report.checks.performed.includes('upscale'));
  assert.ok(r.report.checks.notPerformed.some((n) => /named UI/i.test(n.check + n.reason)), 'the unattestable check is listed');
  assert.match(r.report.candidate.sha256, /^[0-9a-f]{64}$/);
  for (const k of ['job', 'composeMap', 'receipt']) assert.match(r.report.inputs[k].sha256, /^[0-9a-f]{64}$/, k);
});

test('upscale: a 1600x1000 recording in a 1920x1080 frame fails upscale and bars (96 px pillar), confirmed on pixels', opts, () => {
  const { root, cand } = buildJob({ profile: 'youtube-16x9', frame: [1920, 1080] });
  const r = runGate(root, cand);
  assert.equal(r.code, 1);
  assert.ok(has(r, /\[upscale\].*upscales beyond the capture's native 1600x1000.*capture at the delivery frame or larger/), r.report.errors.join('\n'));
  assert.ok(has(r, /\[bars\].*pillarbox\/letterbox inside the product frame.*96 px/), r.report.errors.join('\n'));
  assert.ok(has(r, /\[bars\].*confirmed on the encoded frame/), 'bars are confirmed on the middle frame pixels');
  const c = r.report.clips[0];
  assert.equal(c.verdict, 'fail');
  assert.equal(c.bars.left, 96);
  assert.equal(c.bars.right, 96);
  assert.ok(c.scaleX > 1.07 && c.scaleX < 1.09, `scaleX ${c.scaleX}`);
  assert.ok(c.barsMeasured.left >= 90 && c.barsMeasured.right >= 90, JSON.stringify(c.barsMeasured));
});

test('stretch: a candidate scaled to fill a different aspect fails stretch on the measured content', opts, () => {
  const { root, cand } = buildJob({
    profile: 'briefing-board', frame: [1920, 1000],
    candidate: (r, clip, out) => ff(['-i', clip, '-vf', 'scale=1920:1000,format=yuv420p', '-c:v', 'libx264', '-preset', 'ultrafast', out]),
  });
  const r = runGate(root, cand);
  assert.equal(r.code, 1);
  assert.ok(has(r, /\[stretch\]/), r.report.errors.join('\n'));
  assert.ok(r.report.clips[0].measured.scaleX > r.report.clips[0].measured.scaleY * 1.1);
});

test('crop: a sourceRegion below 1 fails crop; a cue-plan crop reason turns it into a warning', opts, () => {
  const region = { x: 0.1, y: 0.1, width: 0.625, height: 0.625 };
  const failing = buildJob({ clip: [2560, 1600], region });
  const r1 = runGate(failing.root, failing.cand);
  assert.equal(r1.code, 1);
  assert.ok(has(r1, /\[crop\].*crop removes UI edges/), r1.report.errors.join('\n'));
  assert.equal(r1.report.clips[0].cropBox.w, 1600);
  assert.equal(r1.report.clips[0].cropBox.x, 256);
  assert.equal(r1.report.errors.length, 1, 'only the crop fails: no upscale, no bars');

  const declared = buildJob({ clip: [2560, 1600], region, cuePlan: { beats: { W01: { crop: { reason: 'the table is the only thing the line names' } } } } });
  const r2 = runGate(declared.root, declared.cand);
  assert.equal(r2.code, 0, r2.out);
  assert.ok(r2.report.warnings.some((w) => /\[crop\].*the table is the only thing/.test(w)));
  assert.equal(r2.report.inputs.cuePlan.path, 'story/cue-plan.json');

  const noReason = buildJob({ clip: [2560, 1600], region, cuePlan: { beats: { W01: { crop: {} } } } });
  assert.equal(runGate(noReason.root, noReason.cand).code, 1, 'a crop declaration without a reason does not count');
});

test('bars on pixels: bars in the file that the compose map does not predict fail', opts, () => {
  const { root, cand } = buildJob({
    candidate: (r, clip, out) => ff(['-i', clip, '-vf', 'scale=1440:1000,pad=1600:1000:(ow-iw)/2:(oh-ih)/2,format=yuv420p', '-c:v', 'libx264', '-preset', 'ultrafast', out]),
  });
  const r = runGate(root, cand);
  assert.equal(r.code, 1);
  assert.ok(has(r, /\[bars\].*not in the compose map/), r.report.errors.join('\n'));
});

test('bars predicted by the compose map but absent from the file are a disagreement, still a failure', opts, () => {
  const { root, cand } = buildJob({
    profile: 'youtube-16x9', frame: [1920, 1080],
    candidate: (r, clip, out) => ff(['-i', clip, '-vf', 'scale=1920:1080,format=yuv420p', '-c:v', 'libx264', '-preset', 'ultrafast', out]),
  });
  const r = runGate(root, cand);
  assert.equal(r.code, 1);
  assert.ok(has(r, /\[bars\].*not visible in the encoded frame/), r.report.errors.join('\n'));
});

test('zoom: recast full needs a declared beat and a 2x capture', opts, () => {
  const declared = { beats: { W01: { zoom: true } } };
  const undeclared = buildJob({ recast: 'full', dsf: 2 });
  const r1 = runGate(undeclared.root, undeclared.cand);
  assert.equal(r1.code, 1);
  assert.ok(has(r1, /\[zoom\].*zoom on product footage is off by default: declare the beat and capture at 2x or higher/), r1.report.errors.join('\n'));
  assert.equal(r1.report.clips[0].recast, 'full');
  assert.equal(r1.report.clips[0].zoomDeclared, false);

  const lowDsf = buildJob({ recast: 'full', dsf: 1, cuePlan: declared });
  const r2 = runGate(lowDsf.root, lowDsf.cand);
  assert.equal(r2.code, 1);
  assert.ok(has(r2, /\[zoom\].*device scale factor 1/), r2.report.errors.join('\n'));

  const ok = buildJob({ recast: 'full', dsf: 2, cuePlan: declared });
  const r3 = runGate(ok.root, ok.cand);
  assert.equal(r3.code, 0, r3.out);
  assert.equal(r3.report.clips[0].zoomDeclared, true);

  const bySheet = buildJob({ recast: 'full', dsf: 2, cueSheet: { beats: [{ beat: 'W01', camera: 'punch-in on the Import button' }] } });
  const r4 = runGate(bySheet.root, bySheet.cand);
  assert.equal(r4.code, 0, r4.out);
  assert.equal(r4.report.inputs.cueSheet.path, 'plan/cue-sheet.json');

  const dflt = buildJob({ recast: 'full', dsf: 2, cueSheet: { beats: [{ beat: 'W01', camera: 'Recast punch-in on clicks' }] } });
  const r5 = runGate(dflt.root, dflt.cand);
  assert.equal(r5.code, 1, 'the generated default camera text is not a declaration');
  assert.ok(r5.report.errors.some((e) => /is not a decision/.test(e)), r5.out);
});

test('ratio: a desktop recording cannot back a 9:16 cut; a matching phone capture can', opts, () => {
  const desktop = buildJob({ profile: 'vertical-9x16', frame: [1080, 1920], clip: [1600, 1000] });
  const r1 = runGate(desktop.root, desktop.cand);
  assert.equal(r1.code, 1);
  assert.ok(has(r1, /\[ratio\].*never derived from a desktop capture/), r1.report.errors.join('\n'));
  assert.equal(r1.report.ratio.deliverable, '9:16');
  assert.equal(r1.report.ratio.ok, false);

  const table = { '9:16': { width: 360, height: 640, deviceScaleFactor: 3, device: 'Pixel 7' } };
  const phone = buildJob({ profile: 'vertical-9x16', frame: [1080, 1920], clip: [1080, 1920], viewport: { width: 360, height: 640 }, dsf: 3, job: { captureViewports: table }, extraReceipt: { device: 'Pixel 7' } });
  const r2 = runGate(phone.root, phone.cand);
  assert.equal(r2.code, 0, r2.out);
  assert.equal(r2.report.ratio.ok, true);
  assert.deepEqual(r2.report.ratio.required, table['9:16']);

  // The table entry governs: a 390x844 phone matching its declared entry passes the ratio check (bars are judged separately).
  const iphone = buildJob({ profile: 'vertical-9x16', frame: [1080, 1920], clip: [1170, 2532], viewport: { width: 390, height: 844 }, dsf: 3, job: { captureViewports: { '9:16': { width: 390, height: 844, deviceScaleFactor: 3 } } } });
  const r3 = runGate(iphone.root, iphone.cand);
  assert.ok(!has(r3, /\[ratio\]/), r3.report.errors.join('\n'));

  // A viewport that disagrees with the table fails even when its ratio is fine.
  const wrong = buildJob({ profile: 'vertical-9x16', frame: [1080, 1920], clip: [1080, 1920], viewport: { width: 360, height: 640 }, dsf: 3, job: { captureViewports: { '9:16': { width: 412, height: 732, deviceScaleFactor: 3 } } } });
  assert.ok(has(runGate(wrong.root, wrong.cand), /\[ratio\].*412x732/));
});

test('ratio exception: responsive:false needs reason and declaredBy, and is recorded', opts, () => {
  const exception = { reason: 'the product is desktop-only', declaredBy: 'owner 2026-10-20' };
  const withEx = buildJob({ profile: 'vertical-9x16', frame: [1080, 1920], clip: [1600, 1000], job: { responsive: false, responsiveException: exception } });
  const r1 = runGate(withEx.root, withEx.cand);
  assert.ok(!has(r1, /\[ratio\]/), r1.report.errors.join('\n'));
  assert.deepEqual(r1.report.ratio.exception, exception);
  assert.ok(r1.report.checks.performed.includes('ratio') || r1.report.ratio.skipped, 'recorded');
  assert.ok(has(r1, /\[bars\]|\[upscale\]|\[crop\]/), 'stretch/upscale/crop/bars still apply');

  const missing = buildJob({ profile: 'vertical-9x16', frame: [1080, 1920], clip: [1600, 1000], job: { responsive: false } });
  assert.ok(has(runGate(missing.root, missing.cand), /\[ratio\].*responsiveException/));

  const partial = buildJob({ profile: 'vertical-9x16', frame: [1080, 1920], clip: [1600, 1000], job: { responsive: false, responsiveException: { reason: 'x' } } });
  assert.ok(has(runGate(partial.root, partial.cand), /\[ratio\].*declaredBy/));
});

test('fail closed: clip absent from the receipt, frame disagreement, wrong candidate size, no compose map', opts, () => {
  const absent = buildJob({ receiptMissingClip: true });
  assert.ok(has(runGate(absent.root, absent.cand), /\[receipt\].*W01/));

  const mismatch = buildJob({ profile: 'youtube-16x9', frame: [1600, 1000], candidate: (r, clip, out) => composeLike(clip, out, 1600, 1000) });
  assert.ok(has(runGate(mismatch.root, mismatch.cand), /\[frame\].*1600x1000.*1920x1080/));

  const small = buildJob({ candidate: (r, clip, out) => composeLike(clip, out, 800, 500) });
  assert.ok(has(runGate(small.root, small.cand), /\[frame\].*candidate is 800x500/));

  const none = buildJob({});
  rmSync(join(none.root, 'output', 'film-compose-map.json'));
  const r = runGate(none.root, none.cand);
  assert.equal(r.code, 1);
  assert.match(r.out, /compose map/i);
});

test('compose map: --compose-map selects an explicit map and the newest default is used otherwise', opts, () => {
  const { root, cand } = buildJob({});
  const alt = JSON.parse(readFileSync(join(root, 'output', 'film-compose-map.json'), 'utf8'));
  alt.width = 1920; alt.height = 1080;
  writeFileSync(join(root, 'output', 'alt-compose-map.json'), JSON.stringify(alt));
  const r = runGate(root, cand, ['--compose-map', 'output/alt-compose-map.json']);
  assert.equal(r.report.inputs.composeMap.path, 'output/alt-compose-map.json');
  assert.equal(r.report.frame.W, 1920);
});
