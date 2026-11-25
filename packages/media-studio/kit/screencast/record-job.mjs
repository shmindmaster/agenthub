// Record the screen beats of one media-studio product-screencast job and finish each take with Recast.
// This is the only path that produces the picture of a `screen` beat (product-picture.md); PNG stills are
// diagnostic. Runs from the external job workspace; the product repository is read-only.
//
// Usage: node record-job.mjs <jobRoot> [S05 S06 ...] [--no-recast] [--recast-only] [--headed] [--fresh] [--skip-preflight] [--ratio <r>]
//   Exit 1 when any requested take failed or has no scene function; the receipt still records the failed take as invalid.
//   --recast-only opens no browser: it finishes takes recorded with --no-recast (on another machine) from their raw WebM and
//   trace, which must hash to the receipt, and reseals the receipt.
//   --ratio <r> records at options.viewports[r] = { width, height, deviceScaleFactor?, device?, isMobile?, hasTouch? } (a Playwright device name
//   such as 'iPhone 13' applies its emulation) instead of options.viewport; without it the options.viewport path is unchanged.
//   Every receipt clip records ratio, device, viewport and deviceScaleFactor, so a non-16:9 cut is captured at its own viewport.
//   Before the first take validate-capture-preflight.mjs checks scene ids, cue-plan keywords and typing budgets against the locked
//   narration (static, no browser); a failure stops the run. --skip-preflight bypasses it and records recordings.preflight = "skipped".
// Reads  <jobRoot>/capture/scenes.mjs:
//   export const order = ['S05', ...];                      // default recording order
//   export const options = { baseUrl, storageState?, carryState?, viewport?, deviceScaleFactor?, mobileLayout?: { cssWidth, scale }, pageZoom?: 1.5, recast?: { S05: { autoZoom: false } } };
//   export const scenes = { async S05(h, ctx) {...} };      // one function per screen beat; h = record-lib helpers
//   options.provenance = { sourceRevision }                   // the product source this job records (declared, not observed)
//   export const identity = async (page) => ({ persona, servedRevision });  // read off the live page after each take; it must not
//                                                             // act on it. Required for a viewer-facing job. A persona, scenario or
//                                                             // revision other than the scenario proof's makes the take invalid.
//   ctx = { page, beats, id, jobRoot, targetSeconds }       // targetSeconds = narration length of the beat, or null
// Writes <jobRoot>/capture/clips/<id>.webm                  (Recast: cursor approach, click ripple, punch-in zoom)
//        <jobRoot>/capture/beats/<id>.json                  (beat marks with elapsed seconds and bounding boxes)
//        <jobRoot>/capture/recordings.json                  (take length vs narration target, Recast status, errors)
//        <jobRoot>/capture/receipt.json                     (sealed, hash-bound capture receipt; receipt-lib.mjs; never edit it)
// One Recast render at a time (it writes .recast-tmp inside the clips dir). A Recast failure retries without
// autoZoom, then falls back to the raw WebM with recast: "fallback" recorded; the validator decides whether
// a fallback is acceptable (only when job.json says recastFallbackAllowed with a reason). Nothing is silent.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { startRecording, finishRecording, renderRecast } from './record-lib.mjs';
import { STAGE_CAPTURE } from './stage-math.mjs';
import { openReceipt, saveReceipt, isViewerFacing, proofProblems, provenanceProblems } from './receipt-lib.mjs';

const argv = process.argv.slice(2);
const flags = new Set(argv.filter((a) => a.startsWith('--')));
// --ratio takes a value (--ratio 9:16 or --ratio=9:16); the value is not a scene id.
const ratioAt = argv.indexOf('--ratio');
const ratioOpt = ratioAt >= 0 ? argv[ratioAt + 1] : (argv.find((a) => a.startsWith('--ratio=')) || '').slice(8) || null;
const [jobRootArg, ...only] = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--ratio'));
if (!jobRootArg) { console.error('usage: node record-job.mjs <jobRoot> [S05 ...] [--no-recast] [--headed]'); process.exit(2); }
const jobRoot = path.resolve(jobRootArg);
const job = JSON.parse(fs.readFileSync(path.join(jobRoot, 'job.json'), 'utf8').replace(/^﻿/, ''));
if (job.repositoryWritePolicy !== 'read-only') throw new Error('job.json must record repositoryWritePolicy: read-only before capture');
const cap = path.join(jobRoot, 'capture');
fs.mkdirSync(path.join(cap, 'clips'), { recursive: true });
fs.mkdirSync(path.join(cap, 'beats'), { recursive: true });
process.chdir(cap);

const mod = await import(pathToFileURL(path.join(cap, 'scenes.mjs')).href);
const scenes = mod.scenes || {};
const order = mod.order || Object.keys(scenes);
const options = mod.options || {};
// options/covers: one continuous take may carry several narration segments when the product keeps its state in
// memory between them (a live tally that a reload would reset). `export const covers = { S04: ['S04','S05','S06'] }`
// records one clip for S04 whose receipt and manifest entry span those segments; the scene paces each part with
// ctx.targets[segmentId].
const covers = mod.covers || {};
if (!options.baseUrl) throw new Error('capture/scenes.mjs must export options.baseUrl');
const storageState = options.storageState ? path.resolve(cap, options.storageState) : null;
if (storageState && !flags.has('--recast-only') && !fs.existsSync(storageState)) throw new Error('storageState not found: ' + storageState);
// options.carryState: each take saves its web storage (capture tallies, persona, drafts) and the next take starts
// from it, so a workflow split into beats still reads as one continuous session. The first take starts clean
// (or from options.storageState). `--fresh` discards a carried state left by an earlier run.
const carryPath = path.join(cap, '_carried-state.json');
if (flags.has('--fresh') && fs.existsSync(carryPath)) fs.unlinkSync(carryPath);
const carryState = options.carryState === true;

// Narration length per scene so a take can be paced to the words.
// Capture frame: options.viewport, or with --ratio the entry options.viewports[ratio]. Receipt records it either way.
let capture = { viewport: options.viewport, deviceScaleFactor: options.deviceScaleFactor, device: null, isMobile: undefined, hasTouch: undefined };
// The screen stage is the default finisher; Recast stays selectable (job.screenStage: false, or --recast) and keeps the old mobileLayout lane.
const stageLane = job.screenStage !== false && job.screenStage?.finisher !== 'recast' && !flags.has('--recast') && !options.mobileLayout && !flags.has('--recast-only');
if (stageLane) {
  const entry = ratioOpt ? (options.viewports || {})[ratioOpt] ?? STAGE_CAPTURE[ratioOpt] : (options.viewport ? { ...options.viewport, deviceScaleFactor: options.deviceScaleFactor ?? STAGE_CAPTURE['16:9'].deviceScaleFactor } : STAGE_CAPTURE['16:9']);
  if (!entry || !Number.isFinite(entry.width) || !Number.isFinite(entry.height)) throw new Error('--ratio ' + ratioOpt + ': no capture viewport for the screen stage (STAGE_CAPTURE has 16:9, 9:16, 4:5, 1:1)');
  capture = { viewport: { width: entry.width, height: entry.height }, deviceScaleFactor: entry.deviceScaleFactor ?? STAGE_CAPTURE['16:9'].deviceScaleFactor, device: entry.device || null, isMobile: entry.isMobile, hasTouch: entry.hasTouch };
}
if (ratioOpt && !stageLane) {
  const vp = (options.viewports || {})[ratioOpt];
  if (!vp || !Number.isFinite(vp.width) || !Number.isFinite(vp.height)) throw new Error('--ratio ' + ratioOpt + ': capture/scenes.mjs options.viewports["' + ratioOpt + '"] = { width, height, ... } is missing');
  capture = { viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: vp.deviceScaleFactor ?? options.deviceScaleFactor, device: vp.device || null, isMobile: vp.isMobile, hasTouch: vp.hasTouch };
  // A ratio entry is a CSS viewport (a phone is 390x844 at DSF 3), and Playwright records video at the size it is given,
  // not at device pixels. Record and Recast it at viewport x DSF so a 9:16 take is 1170x2532, not a 390x844 clip that
  // picture-integrity must reject as a 2.3x upscale into 1080x1920. mobileLayout already rasterises at native size.
  const dsf = Number(capture.deviceScaleFactor);
  if (!options.mobileLayout && Number.isFinite(dsf) && dsf > 1) capture.videoSize = { width: Math.round(vp.width * dsf), height: Math.round(vp.height * dsf) };
}
const gcd = (a, b) => (b ? gcd(b, a % b) : a);
const reducedRatio = (v) => { const g = gcd(v.width, v.height) || 1; return (v.width / g) + ':' + (v.height / g); };
const targets = {};
const tlPath = path.join(jobRoot, 'story', 'narration-timeline.json');
if (fs.existsSync(tlPath)) {
  const tl = JSON.parse(fs.readFileSync(tlPath, 'utf8').replace(/^﻿/, ''));
  for (const s of tl.segments || []) { const sc = s.scene || String(s.id).replace(/[a-z]$/, ''); targets[sc] = (targets[sc] || 0) + Number(s.durationSeconds || 0); }
}
const segmentTargets = { ...targets };
for (const [id, segs] of Object.entries(covers)) targets[id] = segs.reduce((n, s) => n + (segmentTargets[s] || 0), 0);

const sha256 = (f) => createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const probe = (f) => { try { return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString()); } catch { return 0; } };
const here = path.dirname(fileURLToPath(import.meta.url));
let recastVersion = null;
// Recast trims the blank lead-in off the head of every render (playwright-recast render/renderer.js detectBlankLeadIn,
// up to 3 s). Receipt events are logged on the raw recording clock, so the trim is measured with the same function on
// the same raw WebM and recorded per clip; sync-lib clipClock() subtracts it. Missing it, the sync tooling refuses the clip.
let detectBlankLeadIn = null;
for (const dir of [path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'node_modules'), path.join(path.dirname(fileURLToPath(import.meta.url)), 'node_modules')]) {
  const f = path.join(dir, 'playwright-recast', 'dist', 'render', 'renderer.js');
  if (!detectBlankLeadIn && fs.existsSync(f)) { try { ({ detectBlankLeadIn } = await import(pathToFileURL(f).href)); } catch { detectBlankLeadIn = null; } }
}
// The kit's node_modules sits one level above screencast/; playwright-recast does not export its package.json.
for (const dir of [path.join(here, '..', 'node_modules'), path.join(here, 'node_modules')]) { if (recastVersion) break; try { recastVersion = JSON.parse(fs.readFileSync(path.join(dir, 'playwright-recast', 'package.json'), 'utf8')).version; } catch { /* next */ } }
if (!recastVersion) { try { const p = fileURLToPath(await import.meta.resolve('playwright-recast/package.json')); recastVersion = JSON.parse(fs.readFileSync(p, 'utf8')).version; } catch { recastVersion = null; } }
let playwrightVersion = null;
try { playwrightVersion = JSON.parse(fs.readFileSync(fileURLToPath(await import.meta.resolve('playwright/package.json')), 'utf8')).version; } catch { playwrightVersion = null; }

const recPath = path.join(cap, 'recordings.json');
const recordings = fs.existsSync(recPath) ? JSON.parse(fs.readFileSync(recPath, 'utf8')) : { jobRoot: path.basename(jobRoot), takes: {} };
const receiptPath = path.join(cap, 'receipt.json');
const receipt = openReceipt(receiptPath, { generator: 'media-studio/record-job', clips: {} });
receipt.generator = 'media-studio/record-job';
receipt.playwrightVersion = playwrightVersion;
receipt.recastVersion = recastVersion;
receipt.baseUrl = options.baseUrl;
const save = () => { fs.writeFileSync(recPath, JSON.stringify(recordings, null, 2)); saveReceipt(receiptPath, receipt, { seal: true }); };

let kitVersion = null;
// kit/package.json beside the kit; plugin.json beside this file in _shared/tools
for (const f of [path.join(here, '..', 'package.json'), path.join(here, 'plugin.json')]) { try { kitVersion ||= JSON.parse(fs.readFileSync(f, 'utf8')).version; } catch { /* next */ } }
const viewerFacing = isViewerFacing(job);
const proofPath = path.join(jobRoot, 'evidence', 'demo-scenario-proof.json');
const proof = fs.existsSync(proofPath) ? JSON.parse(fs.readFileSync(proofPath, 'utf8').replace(/^\uFEFF/, '')) : null;
if (viewerFacing && !flags.has('--recast-only') && typeof mod.identity !== 'function') throw new Error('capture/scenes.mjs must export identity(page) => ({ persona, servedRevision }) for a viewer-facing job: the receipt records who and what was filmed');
const observeIdentity = async (page) => {
  const seen = typeof mod.identity === 'function' ? (await mod.identity(page)) || {} : {};
  return { persona: seen.persona ?? null, scenarioId: proof?.scenarioId ?? null, sourceRevision: options.provenance?.sourceRevision ?? null,
    servedRevision: seen.servedRevision ?? null, baseUrl: options.baseUrl, kitVersion };
};
const failed = [];

// Pre-flight (static, no browser): scene ids, cue-plan keywords and typing budgets are checked against the locked narration before
// the first take, so a mistake does not surface after a long recording. scripts/validate-capture-preflight.mjs sits beside this file
// in the deployed kit, in the package scripts/ folder, or in _shared/tools (the deploy list).
if (flags.has('--recast-only')) { /* the takes were recorded, and their pre-flight ran, on another machine */ }
else if (flags.has('--skip-preflight')) {
  console.log('WARNING: --skip-preflight: the capture pre-flight was bypassed; scene ids, cue-plan keywords and typing budgets are unchecked');
  recordings.preflight = 'skipped';
} else {
  const preflight = [path.join(here, 'validate-capture-preflight.mjs'), path.join(here, '..', '..', 'scripts', 'validate-capture-preflight.mjs'), path.join(here, '..', '..', '_shared', 'tools', 'validate-capture-preflight.mjs')].find((f) => fs.existsSync(f));
  if (!preflight) throw new Error('capture pre-flight script not found (deploy list)');
  try { execFileSync(process.execPath, [preflight, jobRoot], { windowsHide: true, stdio: 'inherit' }); }
  catch { throw new Error('capture pre-flight failed: fix scene ids, keywords or typing budgets before recording'); }
  recordings.preflight = { ok: true, report: 'qa/capture-preflight.json' };
}

/**
 * Stage lane: the screencast frames become clips/<id>.mp4, a constant-rate H.264 picture of the take (the sealed, probeable clip the
 * existing gates read). The stage renders from the original frames, not from this file, so nothing is resampled twice.
 */
function finishStageTake(id, fin, take) {
  const out = path.resolve('clips', id + '.mp4');
  for (const ext of ['webm', 'png', 'jpg']) { const p = path.resolve('clips', id + '.' + ext); if (fs.existsSync(p)) fs.unlinkSync(p); }
  const frames = fin.index.frames;
  const list = path.join(fin.rawDir, 'frames.ffconcat');
  const lines = [];
  frames.forEach((f, i) => {
    const next = i + 1 < frames.length ? frames[i + 1].t : fin.index.endSeconds;
    lines.push("file 'frames/" + f.file + "'", 'duration ' + Math.max(0.017, next - f.t).toFixed(4));
  });
  lines.push("file 'frames/" + frames[frames.length - 1].file + "'");
  fs.writeFileSync(list, lines.join('\n'));
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-vf', 'fps=30,format=yuv420p', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '14', '-an', '-movflags', '+faststart', out], { windowsHide: true });
  fs.rmSync(list, { force: true });
  take.finisher = 'stage';
  take.recast = null;
  take.clipSeconds = Number(probe(out).toFixed(1));
  take.headTrim = { seconds: 0, method: 'screen stage: clip clock starts at the first ready frame' };
  take.ratio = take.targetSeconds ? Number((take.clipSeconds / take.targetSeconds).toFixed(2)) : null;
  take.short = take.ratio !== null && take.ratio < 0.85;
  return out;
}

/** Recast (or copy) one raw take to clips/<id>.webm and measure the head trim. Sets take.recast, recastNote, clipSeconds, headTrim. */
async function finishTake(id, fin, take, resolution) {
  const out = path.resolve('clips', `${id}.webm`);
  // A native mobile layout gets no desktop cursor, ripple or punch-in zoom (picture integrity; the page shows touches).
  const opts = { ...(options.mobileLayout ? { cursor: false, autoZoom: false } : {}), ...((options.recast || {})[id] || {}) };
  if (flags.has('--no-recast')) { fs.copyFileSync(fin.webm, out); take.recast = 'skipped'; }
  else {
    // Relative paths: Recast writes its cursor clip into .recast-tmp beside the output and passes that path to ffmpeg's
    // movie filter with only backslashes escaped, so an absolute Windows path breaks on the drive colon. cwd is capture/.
    const rawRel = path.relative(process.cwd(), fin.rawDir);
    const outRel = path.join('clips', `${id}.webm`);
    try { await renderRecast(rawRel, outRel, { ...opts, resolution }); take.recast = opts.autoZoom === false ? 'noZoom' : 'full'; }
    catch (e) {
      console.log('  recast failed:', e.message.split('\n')[0]);
      fs.rmSync(path.resolve('clips', '.recast-tmp'), { recursive: true, force: true });
      try { await renderRecast(rawRel, outRel, { ...opts, autoZoom: false, resolution }); take.recast = 'noZoom'; take.recastNote = e.message.split('\n')[0]; }
      catch (e2) { fs.copyFileSync(fin.webm, out); take.recast = 'fallback'; take.recastNote = e2.message.split('\n')[0]; console.log('  raw webm copied (recast fallback)'); }
    }
  }
  for (const ext of ['png', 'jpg']) { const p = path.resolve('clips', `${id}.${ext}`); if (fs.existsSync(p)) fs.unlinkSync(p); }
  take.clipSeconds = Number(probe(out).toFixed(1));
  // Head trim: Recast's detector on the raw WebM; the raw-minus-clip length is the cross-check (Recast trims only the head).
  const lengthDelta = Number(Math.max(0, probe(fin.webm) - probe(out)).toFixed(3));
  if (take.recast === 'skipped' || take.recast === 'fallback') { take.headTrim = { seconds: 0, method: `raw copy (${take.recast})`, lengthDelta }; }
  else {
    let detected = null;
    if (detectBlankLeadIn) {
      const tmp = path.resolve('clips', `.trim-probe-${id}`);
      fs.mkdirSync(tmp, { recursive: true });
      try { detected = Number(detectBlankLeadIn(fin.webm, tmp).toFixed(3)); } catch { detected = null; } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
    }
    take.headTrim = detected !== null
      ? { seconds: detected, method: 'playwright-recast detectBlankLeadIn on the raw WebM', lengthDelta }
      : { seconds: lengthDelta, method: 'raw minus clip length (detector unavailable)', lengthDelta };
    if (Math.abs(take.headTrim.seconds - lengthDelta) > 0.15) console.log(`  head trim ${take.headTrim.seconds}s disagrees with raw-minus-clip ${lengthDelta}s; recorded both`);
  }
  take.ratio = take.targetSeconds ? Number((take.clipSeconds / take.targetSeconds).toFixed(2)) : null;
  take.short = take.ratio !== null && take.ratio < 0.85;
  return out;
}

if (flags.has('--recast-only')) {
  for (const id of only.length ? only : Object.keys(receipt.clips)) {
    const entry = receipt.clips[id];
    if (!entry) throw new Error(`--recast-only: ${id} is not in capture/receipt.json`);
    if (entry.recast !== 'skipped') { console.log(`=== ${id}: already finished (${entry.recast})`); continue; }
    if (!entry.valid) { console.log(`=== ${id}: invalid take, not finished`); failed.push(id); continue; }
    const rawDir = path.resolve('raw', id);
    const raws = fs.existsSync(rawDir) ? fs.readdirSync(rawDir).filter((f) => f.endsWith('.webm')).map((f) => path.join(rawDir, f)) : [];
    const webm = raws.find((f) => sha256(f) === entry.rawWebmSha256);
    if (!webm) throw new Error(`--recast-only: the raw take in capture/raw/${id} does not match the receipt`);
    const tracePath = path.join(rawDir, 'trace.zip');
    if (entry.traceSha256 && (!fs.existsSync(tracePath) || sha256(tracePath) !== entry.traceSha256)) throw new Error(`--recast-only: the trace in capture/raw/${id} does not match the receipt`);
    console.log('=== finishing', id);
    const take = recordings.takes[id] || { targetSeconds: targets[id] ? Number(targets[id].toFixed(1)) : null };
    const out = await finishTake(id, { webm, rawDir }, take, entry.videoSize || entry.viewport);
    recordings.takes[id] = take;
    Object.assign(entry, { sha256: sha256(out), bytes: fs.statSync(out).size, clipSeconds: take.clipSeconds, recast: take.recast, recastNote: take.recastNote || null, recastKitVersion: kitVersion,
      recastHeadTrimSeconds: take.headTrim.seconds, recastHeadTrimMethod: take.headTrim.method, rawMinusClipSeconds: take.headTrim.lengthDelta });
    save();
    console.log(`  clip ${take.clipSeconds}s recast=${take.recast}`);
  }
  if (failed.length) { console.log(`FAILED ${failed.join(' ')}`); process.exit(1); }
  console.log('done (recast only)');
  process.exit(0);
}

const ids = only.length ? only : order;
for (const id of ids) {
  if (!scenes[id]) { console.log('no scene function for', id); recordings.takes[id] = { error: 'no scene function' }; failed.push(id); save(); continue; }
  console.log('=== recording', id, targets[id] ? `(narration ${targets[id].toFixed(1)} s)` : '');
  fs.rmSync(path.resolve('clips', '.recast-tmp'), { recursive: true, force: true });
  const takeState = carryState && fs.existsSync(carryPath) ? carryPath : storageState;
  const rec = await startRecording(id, {
    storageState: takeState, baseUrl: options.baseUrl, viewport: capture.viewport, videoSize: capture.videoSize, deviceScaleFactor: capture.deviceScaleFactor, mobileLayout: options.mobileLayout, pageZoom: options.pageZoom,
    device: capture.device || undefined, isMobile: capture.isMobile, hasTouch: capture.hasTouch,
    headless: !flags.has('--headed'), colorScheme: options.colorScheme, timezoneId: options.timezoneId, extraHTTPHeaders: options.extraHTTPHeaders,
    stage: stageLane,
  });
  const t0 = Date.now();
  const take = { startedAt: new Date(t0).toISOString(), targetSeconds: targets[id] ? Number(targets[id].toFixed(1)) : null };
  try { await scenes[id](rec.h, { page: rec.page, beats: rec.beats, id, jobRoot, targetSeconds: targets[id] || null, targets: segmentTargets, covers: covers[id] || [id] }); }
  catch (e) { take.error = e.message.split('\n')[0]; console.log('  scene error:', take.error); await rec.page.screenshot({ path: path.join(rec.rawDir, 'error.png') }).catch(() => {}); }
  let provenance = null;
  if (!take.error) try {
    provenance = await observeIdentity(rec.page);
    const problems = viewerFacing ? provenanceProblems(id, provenance, proof) : [];
    if (problems.length) { take.error = problems.join('; '); console.log('  identity:', take.error); }
  } catch (e) { take.error = `identity() failed: ${e.message.split('\n')[0]}`; }
  const fin = await finishRecording(rec, carryState ? { saveStatePath: carryPath } : {});
  take.rawSeconds = Number(((Date.now() - t0) / 1000).toFixed(1));
  fs.writeFileSync(path.join(cap, 'beats', `${id}.json`), JSON.stringify({ id, marks: fin.beats, expectations: fin.expectations }, null, 2));
  const out = stageLane ? finishStageTake(id, fin, take) : await finishTake(id, fin, take, capture.videoSize || capture.viewport);
  take.events = fin.summary;
  const valid = !take.error && (fin.summary.pointerMoves > 0 || fin.summary.taps > 0) && fin.summary.expectationsFailed.length === 0;
  take.valid = valid;
  if (!valid) failed.push(id);
  recordings.takes[id] = take;
  receipt.clips[id] = {
    file: stageLane ? `clips/${id}.mp4` : `clips/${id}.webm`,
    segments: covers[id] || [id],
    sha256: sha256(out),
    bytes: fs.statSync(out).size,
    clipSeconds: take.clipSeconds,
    rawWebmSha256: fin.webm ? sha256(fin.webm) : null,
    traceSha256: fs.existsSync(fin.tracePath) ? sha256(fin.tracePath) : null,
    ...(stageLane ? { finisher: 'stage', stage: { framesIndex: 'raw/' + id + '/frames.json', framesIndexSha256: sha256(fin.indexPath), frames: fin.index.frames.length, width: fin.index.width, height: fin.index.height, deviceScaleFactor: fin.index.deviceScaleFactor, origin: fin.index.origin, endSeconds: fin.index.endSeconds }, hasTouch: !!capture.hasTouch } : { finisher: 'recast' }),
    recordedAt: take.startedAt,
    provenance,
    preflight: recordings.preflight === 'skipped' ? 'skipped' : 'ok',
    ...(capture.videoSize ? { videoSize: capture.videoSize } : {}),
    viewport: rec.viewport,
    deviceScaleFactor: options.mobileLayout ? options.mobileLayout.scale : capture.deviceScaleFactor || 2,
    ...(options.mobileLayout ? { mobileLayout: options.mobileLayout } : {}),
    ratio: ratioOpt || reducedRatio(rec.viewport),
    device: capture.device,
    ...(options.pageZoom ? { pageZoom: options.pageZoom } : {}),
    recast: take.recast,
    recastNote: take.recastNote || null,
    events: fin.summary,
    // Timestamped action log, in seconds into the raw WebM. Recast trims the blank lead-in off the head, so an event at
    // t plays at t - recastHeadTrimSeconds in clips/<id>.webm. build-cue-sheet.mjs applies that (sync-lib clipClock),
    // maps the result through the compose edit decision list, and the sync gate checks it against the spoken words.
    actionClock: stageLane ? 'clip' : 'recording-start',
    ...(stageLane ? {} : { recastHeadTrimSeconds: take.headTrim.seconds, recastHeadTrimMethod: take.headTrim.method, rawMinusClipSeconds: take.headTrim.lengthDelta }),
    actions: fin.events,
    expectations: fin.expectations,
    beats: fin.beats,
    error: take.error || null,
    valid,
  };
  save();
  console.log(`  clip ${take.clipSeconds}s${take.targetSeconds ? ` for ${take.targetSeconds}s of narration (${take.ratio}x)` : ''} recast=${take.recast} moves=${fin.summary.pointerMoves} clicks=${fin.summary.clicks} expectations=${fin.summary.expectationsObserved}/${fin.summary.expectations}${valid ? '' : '  INVALID: ' + (take.error || fin.summary.expectationsFailed.join(',') || 'no pointer motion')}${take.short ? '  SHORT: pace the take to the narration or split the beat' : ''}`);
}
if (failed.length) { console.log(`FAILED ${failed.join(' ')}: an invalid take is not footage; fix the scene and record it again`); process.exitCode = 1; }
else console.log('done', ids.join(' '));
