#!/usr/bin/env node
// Fail-closed picture-integrity gate on the ENCODED candidate: the picture a viewer sees must not be morphed,
// enlarged, cropped, barred or zoomed away from what was captured, and a non-16:9 cut must be captured at its own ratio.
// Usage: node validate-picture-integrity.mjs <jobRoot> <candidate.mp4> [--compose-map output/<base>-compose-map.json]
//        [--out qa/picture-integrity.json] [--scale-tolerance 0.005] [--bar-variance 4] [--bar-min-px 6]
//
// Reads job.json (deliveryProfile, captureViewports, responsive, responsiveException), the compose map written by
// kit/screencast/compose-screencast.mjs (default: newest output/*-compose-map.json), capture/receipt.json, and when present
// plan/cue-sheet.json (beat camera) and story/cue-plan.json (beats[id].zoom, beats[id].crop). The frame is the compose map's
// width x height, cross-checked against frameFor(job) and the candidate's ffprobe size.
//
// Per product-clip group (not isImage, not heldFromPrevious), using the exact filter compose applies (sourcePictureFilter):
//   [upscale]  fitted scale > 1 + tolerance: the capture is enlarged beyond its native size (soft text).
//   [stretch]  on the encoded middle frame, the non-bar content is scaled differently on x and y than the captured crop.
//   [crop]     sourceRegion w < 1 or h < 1 removes UI edges, unless story/cue-plan.json declares beats[id].crop.reason for
//              every segment of the group (then a warning).
//   [bars]     fitted frame leaves more than --bar-min-px of pillar/letter bars; confirmed on the pixels of the middle frame
//              (a border strip with variance below --bar-variance). Flat bars the compose map did not predict also fail.
//   [zoom]     receipt recast 'full' is a punch-in: allowed only when deviceScaleFactor >= 2 AND every segment is declared by
//              the cue sheet beat camera (punch-in / zoom) or story/cue-plan.json beats[id].zoom === true.
//   [ratio]    a portrait or square deliverable needs a capture viewport at its own ratio (job.captureViewports table entry
//              when present, else within 2 %), never a desktop viewport; job.responsive === false needs a full
//              responsiveException { reason, declaredBy }.
// Writes qa/picture-integrity.json bound to the candidate's sha256. Exit 1 on any error.
import { existsSync, readFileSync, mkdirSync, writeFileSync, statSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { basename, dirname, extname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { validateFinalEncoderTransform, cropGray, meanAbsoluteDifference } from './final-encoder-transform.mjs';
import { productPanelGeometry, panelSourceSample, cropPanelGray, panelReferenceFilter } from './product-panel-geometry.mjs';

const USAGE = 'Usage: node validate-picture-integrity.mjs <jobRoot> <candidate.mp4> [--compose-map output/<base>-compose-map.json] [--out qa/picture-integrity.json] [--scale-tolerance 0.005] [--bar-variance 4] [--bar-min-px 6]';
const VALUE_FLAGS = new Set(['--compose-map', '--out', '--scale-tolerance', '--bar-variance', '--bar-min-px']);
const pos = [];
const flags = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (VALUE_FLAGS.has(a)) flags[a] = process.argv[++i];
  else if (a.startsWith('--')) { console.error(`unknown flag ${a}\n${USAGE}`); process.exit(1); }
  else pos.push(a);
}
const [jobRootArg, candidateArg] = pos;
if (!jobRootArg || !candidateArg) { console.error(USAGE); process.exit(1); }

const jobRoot = resolve(jobRootArg);
const candidate = resolve(candidateArg);
const outPath = resolve(jobRoot, flags['--out'] || 'qa/picture-integrity.json');
const SCALE_TOLERANCE = Number(flags['--scale-tolerance'] ?? 0.005);
const BAR_VARIANCE = Number(flags['--bar-variance'] ?? 4);
const BAR_MIN_PX = Number(flags['--bar-min-px'] ?? 6);
const RATIO_TOLERANCE = 0.02;
const PAD_LUMA_MAX = 20; // compose pads with black; a flat strip brighter than this is page background, not a bar
const ZOOM_RE = /punch[- ]?in|zoom/i;
const DEFAULT_CAMERA = 'Recast punch-in on clicks'; // build-cue-sheet.mjs writes this when nobody declared a camera

const errors = [];
const warnings = [];
const inputs = {};
const performed = [];
const notPerformed = [];
const addError = (tag, label, message) => { const m = `[${tag}] ${label}: ${message}`; if (!errors.includes(m)) errors.push(m); };
const addWarning = (tag, label, message) => { const m = `[${tag}] ${label}: ${message}`; if (!warnings.includes(m)) warnings.push(m); };
const sha256 = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const relPath = (p) => relative(jobRoot, p).replace(/\\/g, '/');
const bind = (name, p) => { inputs[name] = { path: relPath(p), sha256: sha256(p) }; };
const readJsonFile = (p) => JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, ''));
const gcd = (a, b) => (b ? gcd(b, a % b) : a);
const round = (n, d = 3) => Number(Number(n).toFixed(d));

const scriptDir = dirname(fileURLToPath(import.meta.url));
const helper = existsSync(join(scriptDir, 'campaign-contract.mjs')) ? join(scriptDir, 'campaign-contract.mjs') : join(scriptDir, '..', 'kit', 'screencast', 'campaign-contract.mjs');
const { frameFor, probeVideo } = await import(pathToFileURL(helper).href);

const report = {
  generator: 'media-studio/validate-picture-integrity',
  schemaVersion: '1.0.0',
  ok: false,
  errors,
  warnings,
  candidate: null,
  inputs,
  thresholds: { scaleTolerance: SCALE_TOLERANCE, barVariance: BAR_VARIANCE, barMinPx: BAR_MIN_PX, ratioTolerance: RATIO_TOLERANCE, padLumaMax: PAD_LUMA_MAX },
  frame: null,
  ratio: null,
  clips: [],
  skippedGroups: [],
  checks: { performed, notPerformed },
};
const finish = () => {
  report.ok = errors.length === 0;
  report.generatedAt = new Date().toISOString();
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  const out = relPath(outPath);
  if (errors.length) {
    for (const e of errors) console.error(`[picture-integrity] ${e}`);
    console.log(JSON.stringify({ ok: false, out, errors, warnings }));
    process.exit(1);
  }
  console.log(JSON.stringify({ ok: true, out, clips: report.clips.length, warnings }));
  process.exit(0);
};
const stop = (message) => { errors.push(message); finish(); };

// ---- inputs ----
if (!existsSync(candidate)) stop(`[input] candidate not found: ${candidate}`);
report.candidate = { path: relPath(candidate), sha256: sha256(candidate), bytes: statSync(candidate).size };
const jobFile = join(jobRoot, 'job.json');
if (!existsSync(jobFile)) stop('[input] job.json is missing');
bind('job', jobFile);
const job = readJsonFile(jobFile);

let composeMapFile;
if (flags['--compose-map']) composeMapFile = resolve(jobRoot, flags['--compose-map']);
else {
  const dir = join(jobRoot, 'output');
  const maps = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('-compose-map.json')).map((f) => ({ f: join(dir, f), m: statSync(join(dir, f)).mtimeMs })).sort((a, b) => b.m - a.m) : [];
  composeMapFile = maps[0]?.f;
}
if (!composeMapFile || !existsSync(composeMapFile)) stop('[input] no compose map: pass --compose-map or run compose-screencast.mjs (output/<base>-compose-map.json)');
bind('composeMap', composeMapFile);
const composeMap = readJsonFile(composeMapFile);
if (!Array.isArray(composeMap.groups)) stop('[input] compose map has no groups[]');

const receiptFile = join(jobRoot, 'capture', 'receipt.json');
if (!existsSync(receiptFile)) stop('[input] capture/receipt.json is missing');
bind('receipt', receiptFile);
const receipt = readJsonFile(receiptFile);
const cueSheetFile = join(jobRoot, 'plan', 'cue-sheet.json');
const cuePlanFile = join(jobRoot, 'story', 'cue-plan.json');
const cueSheet = existsSync(cueSheetFile) ? (bind('cueSheet', cueSheetFile), readJsonFile(cueSheetFile)) : null;
const cuePlan = existsSync(cuePlanFile) ? (bind('cuePlan', cuePlanFile), readJsonFile(cuePlanFile)) : null;

// ---- frame: compose map, cross-checked against the delivery profile and the candidate ----
const W = Number(composeMap.width), H = Number(composeMap.height);
let profileFrame = null;
try { profileFrame = frameFor(job); } catch (e) { addError('frame', 'job.json', e.message); }
const candidateSize = (() => { try { return probeVideo(candidate); } catch { return null; } })();
if (!(W > 0 && H > 0)) stop('[frame] compose map has no width/height');
report.frame = { W, H, profile: profileFrame?.profile || composeMap.deliveryProfile || null };
if (profileFrame && (profileFrame.width !== W || profileFrame.height !== H)) addError('frame', 'compose map', `compose map frame is ${W}x${H} but deliveryProfile ${profileFrame.profile} is ${profileFrame.width}x${profileFrame.height}`);
if (!candidateSize || !(candidateSize.width > 0)) addError('frame', 'candidate', 'candidate cannot be probed with ffprobe');
else if (candidateSize.width !== W || candidateSize.height !== H) addError('frame', 'candidate', `candidate is ${candidateSize.width}x${candidateSize.height} but the compose map frame is ${W}x${H}`);
performed.push('frame');

// ---- ratio section (deliverable-level) ----
const ratioKey = (w, h) => { const g = gcd(w, h); return `${w / g}:${h / g}`; };
const deliverableKey = ratioKey(W, H);
const portraitOrSquare = H >= W;
const table = job.captureViewports && typeof job.captureViewports === 'object' ? job.captureViewports : {};
const required = portraitOrSquare ? (table[deliverableKey] || { aspect: round(W / H, 4), tolerance: RATIO_TOLERANCE }) : null;
const ratio = { deliverable: deliverableKey, aspect: round(W / H, 4), portraitOrSquare, required, exception: null, skipped: false, ok: true };
report.ratio = ratio;
const filled = (v) => typeof v === 'string' && v.trim().length > 0;
if (job.responsive === false) {
  const ex = job.responsiveException;
  if (ex && filled(ex.reason) && filled(ex.declaredBy)) { ratio.exception = { reason: ex.reason, declaredBy: ex.declaredBy }; ratio.skipped = true; }
  else { ratio.ok = false; addError('ratio', 'job.json', `responsive:false needs responsiveException { reason, declaredBy } with both filled${ex ? ` (missing ${['reason', 'declaredBy'].filter((k) => !filled(ex[k])).join(' and ')})` : ' (none declared)'}; the ratio check fails closed`); }
}
if (!portraitOrSquare) ratio.skipped = true;
if (ratio.skipped) { if (!ratio.exception && !portraitOrSquare) ratio.note = 'landscape deliverable: capture ratio is not constrained'; }
else performed.push('ratio');

// ---- decoding helpers ----
function grayFrameAt(file, t, w, h, scale = false) {
  try {
    const filter = typeof scale === 'string' ? scale : (scale ? `scale=${w}:${h}:flags=lanczos,` : '') + 'format=gray';
    const buf = execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-threads', '2', '-filter_threads', '1', '-ss', Math.max(0, t).toFixed(6), '-i', file, '-frames:v', '1', '-vf', filter, '-f', 'rawvideo', 'pipe:1'], { windowsHide: true, maxBuffer: 1 << 28 });
    return buf.length >= w * h ? buf.subarray(0, w * h) : null;
  } catch { return null; }
}
/** Flat border strips: the widest run from each edge whose pixel variance stays below `varMax`. */
function flatBars(buf, w, h, varMax) {
  const run = (count, lineLen, at) => { // accumulate lines from one edge inward
    let s = 0, ss = 0, n = 0, k = 0;
    for (let i = 0; i < Math.floor(count / 2); i++) {
      let ls = 0, lss = 0;
      for (let j = 0; j < lineLen; j++) { const v = at(i, j); ls += v; lss += v * v; }
      const ns = s + ls, nss = ss + lss, nn = n + lineLen;
      const variance = nss / nn - (ns / nn) ** 2;
      if (variance >= varMax) break;
      s = ns; ss = nss; n = nn; k = i + 1;
    }
    return { px: k, mean: n ? s / n : null };
  };
  const left = run(w, h, (i, j) => buf[j * w + i]);
  const right = run(w, h, (i, j) => buf[j * w + (w - 1 - i)]);
  const top = run(h, w, (i, j) => buf[i * w + j]);
  const bottom = run(h, w, (i, j) => buf[(h - 1 - i) * w + j]);
  return { left, right, top, bottom };
}

// ---- cue declarations ----
const sheetBeat = (id) => (cueSheet?.beats || []).find((b) => b.beat === id || b.id === id) || null;
const zoomDeclaration = (id) => {
  if (cuePlan?.beats?.[id]?.zoom === true) return { declared: true, viaDefaultOnly: false };
  const camera = sheetBeat(id)?.camera;
  // build-cue-sheet.mjs writes the default camera text for every Recast 'full' clip whether or not anyone decided on a
  // punch-in, so that text is not a declaration: only an authored camera line or cue-plan zoom: true counts.
  if (typeof camera === 'string' && camera.trim() === DEFAULT_CAMERA) return { declared: false, viaDefaultOnly: true };
  if (typeof camera === 'string' && ZOOM_RE.test(camera)) return { declared: true, viaDefaultOnly: false };
  return { declared: false, viaDefaultOnly: false };
};
const cropReason = (id) => {
  const c = cuePlan?.beats?.[id]?.crop;
  return c && filled(c.reason) ? c.reason : null;
};

// ---- per-group judgement ----
let encoderTransform = null;
if (composeMap.finalEncoderTransform) {
  try {
    encoderTransform = validateFinalEncoderTransform(composeMap.finalEncoderTransform, report.candidate.sha256, W, H);
    const source = resolve(jobRoot, encoderTransform.sourceFile);
    if (!existsSync(source) || sha256(source) !== encoderTransform.sourceSha256) throw new Error('pre-caption master source hash mismatch');
    const size = probeVideo(source);
    if (size.width !== W || size.height !== H || Math.abs(size.duration - candidateSize.duration) > 0.05) throw new Error('pre-caption source dimensions or duration mismatch');
    bind('finalEncoderMaster', source);
    report.finalEncoderTransform = encoderTransform;
  } catch (e) { stop(`[final-encoder-transform] ${e.message}`); }
}
const receiptClips = receipt.clips || {};
const receiptFor = (group) => (group.clipId && receiptClips[group.clipId]) || Object.values(receiptClips).find((e) => e.file === group.file) || null;
let zoomGroups = 0, decodedFrames = 0;
for (const group of composeMap.groups) {
  const segs = group.segments || [];
  const label = segs.join('+') || group.clipId || '(group)';
  if (group.isImage) { report.skippedGroups.push({ segments: segs, reason: 'isImage: cards and stills are judged by validate-encoded-picture' }); continue; }
  if (group.heldFromPrevious || !group.clipId) { report.skippedGroups.push({ segments: segs, reason: 'heldFromPrevious: repeats the previous clip' }); continue; }
  const entry = receiptFor(group);
  if (!entry) { addError('receipt', label, `clip ${group.clipId} (${group.file}) is not in capture/receipt.json; its picture cannot be judged`); continue; }
  const file = resolve(jobRoot, 'capture', group.file);
  if (!existsSync(file)) { addError('receipt', label, `source clip capture/${group.file} is missing`); continue; }
  let native;
  try { native = probeVideo(file); } catch { native = null; }
  if (!native || !(native.width > 0)) { addError('receipt', label, `source clip capture/${group.file} cannot be probed`); continue; }
  const region = group.sourceRegion || null;
  const rx = region?.x ?? 0, ry = region?.y ?? 0, rw = region?.width ?? 1, rh = region?.height ?? 1;
  const cropBox = { x: round(native.width * rx, 2), y: round(native.height * ry, 2), w: round(native.width * rw, 2), h: round(native.height * rh, 2) };
  let panel = null;
  if (group.destinationRect != null) {
    try {
      if (![rx, ry, rw, rh].every(Number.isFinite) || rx < 0 || ry < 0 || rw <= 0 || rh <= 0 || rx + rw > 1 || ry + rh > 1) throw new Error('sourceRegion must remain inside the native capture');
      panel = productPanelGeometry(group.destinationRect, W, H, cropBox.w, cropBox.h, encoderTransform);
      if (!Number.isFinite(group.startSeconds) || group.startSeconds < 0 || !Number.isFinite(group.needSeconds) || group.needSeconds <= 0 || group.startSeconds + group.needSeconds > candidateSize.duration + 0.05) throw new Error('panel group must declare a positive interval inside the candidate');
    } catch (e) { addError('destination-rect', label, e.message); continue; }
  }
  const pictureW = panel?.encoded.width || encoderTransform?.scaleWidth || W, pictureH = panel?.encoded.height || encoderTransform?.scaleHeight || H;
  const s = Math.min(pictureW / cropBox.w, pictureH / cropBox.h);
  const fitted = { w: cropBox.w * s, h: cropBox.h * s };
  const bars = { left: Math.round((pictureW - fitted.w) / 2), right: Math.round((pictureW - fitted.w) / 2), top: Math.round((pictureH - fitted.h) / 2), bottom: Math.round((pictureH - fitted.h) / 2) };
  for (const k of Object.keys(bars)) if (bars[k] < 0) bars[k] = 0;
  const viewport = entry.viewport || null;
  const dsf = Number(entry.deviceScaleFactor) || 1;
  const row = {
    segments: segs, clip: group.clipId, file: group.file,
    native: { w: native.width, h: native.height }, viewport, deviceScaleFactor: dsf,
    region, scaleX: round(panel ? panel.scale : fitted.w / cropBox.w, 4), scaleY: round(panel ? panel.scale : fitted.h / cropBox.h, 4), cropBox, bars,
    barsMeasured: null, measured: null, recast: entry.recast ?? null, zoomDeclared: null, verdict: 'pass', findings: [],
  };
  const finding = (check, status, message, extra = {}) => { row.findings.push({ check, status, message, ...extra }); };
  const fail = (check, message, extra) => { addError(check, `${label} (${group.file})`, message); finding(check, 'fail', message, extra); };
  const warn = (check, message, extra) => { addWarning(check, `${label} (${group.file})`, message); finding(check, 'warn', message, extra); };
  const pass = (check, message, extra) => finding(check, 'pass', message, extra);
  if (panel) row.destinationRect = panel;

  // upscale: planned scale of the capture into the frame
  if (row.scaleX > 1 + SCALE_TOLERANCE) fail('upscale', `upscales beyond the capture's native ${native.width}x${native.height} by ${row.scaleX.toFixed(3)}x (${cropBox.w}x${cropBox.h} drawn at ${Math.round(fitted.w)}x${Math.round(fitted.h)}); capture at the delivery frame or larger`, { measured: row.scaleX, allowed: 1 + SCALE_TOLERANCE });
  else pass('upscale', `scale ${row.scaleX.toFixed(3)}x`, { measured: row.scaleX, allowed: 1 + SCALE_TOLERANCE });

  // crop
  if (rw < 1 || rh < 1) {
    const reasons = segs.map(cropReason);
    if (segs.length && reasons.every(Boolean)) warn('crop', `sourceRegion ${rw}x${rh} crops product footage; declared in the cue plan: ${[...new Set(reasons)].join('; ')}`);
    else fail('crop', `crop removes UI edges: sourceRegion ${rw}x${rh} keeps ${cropBox.w}x${cropBox.h} of the ${native.width}x${native.height} capture; declare story/cue-plan.json beats[id].crop { reason } for every segment, or capture the framing you want`);
  } else pass('crop', 'full region');

  // encoded middle frame: bars and stretch
  const mid = Number(group.startSeconds || 0) + Number(group.needSeconds || 0) / 2;
  let cw = candidateSize?.width, ch = candidateSize?.height;
  const sampleAt = Math.min(mid, Math.max(0, (candidateSize.duration || mid) - 0.1));
  let frameBuf = cw > 0 ? grayFrameAt(candidate, sampleAt, cw, ch) : null;
  const candidateFrame = frameBuf;
  if (encoderTransform && frameBuf) {
    const t = encoderTransform;
    frameBuf = cropGray(frameBuf, cw, t.padX, t.padY, t.scaleWidth, t.scaleHeight);
    cw = t.scaleWidth; ch = t.scaleHeight;
    const reference = grayFrameAt(resolve(jobRoot, t.sourceFile), sampleAt, cw, ch, true);
    const difference = meanAbsoluteDifference(frameBuf, reference);
    row.finalEncoderMasterDifference = difference;
    // Compression is tolerated, while an incorrect rectangle, replaced UI or internal captions fail.
    if (difference > 4) fail('final-encoder-transform', `encoded product rectangle differs from full-master source: mean luma error ${difference.toFixed(3)} exceeds 4`);
    else pass('final-encoder-transform', 'exact source master matches encoded product rectangle', { measured: difference, allowed: 4 });
  }
  if (panel) {
    try {
      const sourceHash = sha256(file);
      const sourceSeconds = panelSourceSample(group.sourceBinding, { candidateSha256: report.candidate.sha256, sourceSha256: sourceHash, groupStartSeconds: group.startSeconds, sampleSeconds: sampleAt, sourceDuration: native.duration });
      // Validate the entire declared interval, not merely one convenient sample.
      panelSourceSample(group.sourceBinding, { candidateSha256: report.candidate.sha256, sourceSha256: sourceHash, groupStartSeconds: group.startSeconds, sampleSeconds: group.startSeconds + group.needSeconds - Math.min(0.001, group.needSeconds / 2), sourceDuration: native.duration });
      bind(`panelSource:${group.clipId}`, file);
      frameBuf = cropPanelGray(candidateFrame, candidateSize.width, candidateSize.height, panel);
      cw = panel.raster.width; ch = panel.raster.height;
      const reference = grayFrameAt(file, sourceSeconds, cw, ch, panelReferenceFilter(cropBox, panel));
      const difference = meanAbsoluteDifference(frameBuf, reference);
      row.panelSource = { sha256: sourceHash, sourceSeconds, candidateSeconds: sampleAt, difference, binding: group.sourceBinding };
      if (difference > 4) fail('panel-source', `encoded panel differs from its exact capture/time/fit: mean luma error ${difference.toFixed(3)} exceeds 4`, { measured: difference, allowed: 4 });
      else pass('panel-source', 'encoded panel matches hash-bound capture at the declared source time', { measured: difference, allowed: 4 });
    } catch (e) { fail('panel-source', e.message); frameBuf = null; }
  }
  let content = null;
  if (frameBuf) {
    decodedFrames++;
    const fb = flatBars(frameBuf, cw, ch, BAR_VARIANCE);
    const symX = Math.abs(fb.left.px - fb.right.px) <= 2, symY = Math.abs(fb.top.px - fb.bottom.px) <= 2;
    const padX = symX && fb.left.px > 0 && fb.left.mean <= PAD_LUMA_MAX && fb.right.mean <= PAD_LUMA_MAX;
    const padY = symY && fb.top.px > 0 && fb.top.mean <= PAD_LUMA_MAX && fb.bottom.mean <= PAD_LUMA_MAX;
    const m = { left: padX ? fb.left.px : 0, right: padX ? fb.right.px : 0, top: padY ? fb.top.px : 0, bottom: padY ? fb.bottom.px : 0 };
    row.barsMeasured = m;
    content = { w: cw - m.left - m.right, h: ch - m.top - m.bottom };
    row.measured = { content, scaleX: round(content.w / cropBox.w, 4), scaleY: round(content.h / cropBox.h, 4), atSeconds: round(mid, 2) };
  } else {
    notPerformed.push({ check: `stretch+bars-on-pixels:${label}`, reason: 'the candidate middle frame could not be decoded' });
  }

  // stretch
  if (content) {
    const { scaleX, scaleY } = row.measured;
    const rel = Math.abs(scaleX - scaleY) / scaleX;
    if (rel > SCALE_TOLERANCE) fail('stretch', `the encoded content is ${content.w}x${content.h} for a ${cropBox.w}x${cropBox.h} capture (x ${scaleX.toFixed(3)}, y ${scaleY.toFixed(3)}); the picture is stretched by ${(rel * 100).toFixed(1)} %, aspect not preserved`, { measured: rel, allowed: SCALE_TOLERANCE });
    else pass('stretch', `x ${scaleX.toFixed(3)} y ${scaleY.toFixed(3)}`, { measured: rel, allowed: SCALE_TOLERANCE });
  }

  // bars
  const predictedX = Math.max(bars.left, bars.right), predictedY = Math.max(bars.top, bars.bottom);
  const predicted = Math.max(predictedX, predictedY) > BAR_MIN_PX;
  const mb = row.barsMeasured;
  const measuredPx = mb ? Math.max(mb.left, mb.right, mb.top, mb.bottom) : 0;
  if (predicted) {
    const kind = predictedX >= predictedY ? `pillarbox ${predictedX} px per side (left/right)` : `letterbox ${predictedY} px per side (top/bottom)`;
    const confirmed = mb ? (predictedX >= predictedY ? Math.min(mb.left, mb.right) : Math.min(mb.top, mb.bottom)) > BAR_MIN_PX : null;
    const note = confirmed === null ? 'not checked on pixels' : confirmed ? `confirmed on the encoded frame (measured ${mb.left}/${mb.right}/${mb.top}/${mb.bottom} px l/r/t/b)` : 'not visible in the encoded frame: the compose map and the file disagree';
    fail('bars', `pillarbox/letterbox inside the product frame: ${kind}; ${cropBox.w}x${cropBox.h} is fitted to ${Math.round(fitted.w)}x${Math.round(fitted.h)} in ${W}x${H}. ${note}. Capture at the delivery aspect.`, { measured: Math.max(predictedX, predictedY), allowed: BAR_MIN_PX, confirmed });
  } else if (measuredPx > BAR_MIN_PX) {
    fail('bars', `pillarbox/letterbox inside the product frame: the encoded frame carries flat bars (${mb.left}/${mb.right}/${mb.top}/${mb.bottom} px l/r/t/b) that are not in the compose map (predicted ${predictedX}/${predictedY} px)`, { measured: measuredPx, allowed: BAR_MIN_PX });
  } else pass('bars', 'no bars', { measured: Math.max(predictedX, predictedY), allowed: BAR_MIN_PX });

  // zoom (Recast punch-in)
  if (entry.recast === 'full') {
    zoomGroups++;
    const decl = segs.map(zoomDeclaration);
    const declared = segs.length > 0 && decl.every((d) => d.declared);
    row.zoomDeclared = declared;
    const problems = [];
    if (dsf < 2) problems.push(`captured at device scale factor ${dsf}`);
    if (!declared) problems.push(`beat ${segs.filter((_, i) => !decl[i].declared).join(', ') || label} is not declared (an authored cue sheet camera line must say punch-in or zoom, or story/cue-plan.json beats[id].zoom must be true${decl.some((d) => d.viaDefaultOnly) ? '; the generated default camera text "Recast punch-in on clicks" is not a decision' : ''})`);
    if (problems.length) fail('zoom', `zoom on product footage is off by default: declare the beat and capture at 2x or higher. ${problems.join('; ')}`, { measured: dsf, allowed: 2 });
    else pass('zoom', `declared punch-in at device scale factor ${dsf}`, { measured: dsf, allowed: 2 });
  } else row.zoomDeclared = null;

  // ratio (per clip)
  if (!ratio.skipped && portraitOrSquare) {
    if (!viewport || !(viewport.width > 0)) { ratio.ok = false; fail('ratio', 'the receipt has no capture viewport, so the capture ratio cannot be judged; re-record'); }
    else {
      const desktop = viewport.width >= 1024 && viewport.width > viewport.height;
      const entryReq = table[deliverableKey];
      let reason = null;
      if (entryReq) {
        const mismatches = [];
        if (viewport.width !== entryReq.width || viewport.height !== entryReq.height) mismatches.push(`viewport ${viewport.width}x${viewport.height} is not the declared ${entryReq.width}x${entryReq.height}`);
        if (entryReq.deviceScaleFactor != null && dsf !== Number(entryReq.deviceScaleFactor)) mismatches.push(`device scale factor ${dsf} is not the declared ${entryReq.deviceScaleFactor}`);
        if (entryReq.device && entry.device && entry.device !== entryReq.device) mismatches.push(`device ${entry.device} is not the declared ${entryReq.device}`);
        if (mismatches.length) reason = `captureViewports['${deliverableKey}'] declares ${entryReq.width}x${entryReq.height}: ${mismatches.join('; ')}`;
      } else {
        const rel = Math.abs(viewport.width / viewport.height - W / H) / (W / H);
        if (rel > RATIO_TOLERANCE) reason = `capture viewport ${viewport.width}x${viewport.height} (${round(viewport.width / viewport.height, 3)}) is ${(rel * 100).toFixed(1)} % off the ${deliverableKey} deliverable (${round(W / H, 3)}), allowed ${RATIO_TOLERANCE * 100} %`;
      }
      if (reason) {
        ratio.ok = false;
        fail('ratio', `${reason}${desktop ? '; this is a desktop viewport' : ''}. A non-16:9 cut is captured at its own viewport with device emulation; never derived from a desktop capture.`, { measured: `${viewport.width}x${viewport.height}`, allowed: entryReq ? `${entryReq.width}x${entryReq.height}` : `${deliverableKey} ±2%` });
      } else pass('ratio', `${viewport.width}x${viewport.height} @${dsf}x for ${deliverableKey}`);
    }
  }

  row.verdict = row.findings.some((f) => f.status === 'fail') ? 'fail' : 'pass';
  report.clips.push(row);
}

performed.push('upscale', 'crop', 'bars', 'stretch');
if (zoomGroups) performed.push('zoom');
else notPerformed.push({ check: 'zoom', reason: 'no product clip in the compose map has receipt recast "full", so no punch-in exists to judge' });
if (!decodedFrames && report.clips.length) notPerformed.push({ check: 'bars-on-pixels', reason: 'no candidate frame could be decoded' });
if (!report.clips.length && !errors.length) errors.push('[input] the compose map has no product clip group to judge');
notPerformed.push({ check: 'named UI never leaves the frame', reason: 'which UI the narration names is not machine-checkable from pixels; the reviewer attests it from the contact sheet' });
if (zoomGroups && !cueSheet && !cuePlan) notPerformed.push({ check: 'zoom declaration source', reason: 'neither plan/cue-sheet.json nor story/cue-plan.json exists, so no beat can declare a punch-in' });

finish();
