// Optional independent encoded-frame observations. Poll receipts remain immutable.
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative, isAbsolute, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';

const hash = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const text = (v) => typeof v === 'string' && v.trim().length > 0;
const die = (m) => { throw new Error(`physical result observations: ${m}`); };
function file(root, ref) {
  if (!ref || !text(ref.path) || !/^[a-f0-9]{64}$/.test(ref.sha256 || '')) die('invalid artifact reference');
  const p = resolve(root, ref.path); const rel = relative(root, p);
  if (isAbsolute(ref.path) || rel === '..' || rel.startsWith('../') || rel.startsWith('..\\')) die('artifact must be job-relative');
  if (!existsSync(p) || hash(p) !== ref.sha256) die(`missing or changed artifact ${ref.path}`);
  return p;
}
const fraction = (v) => { const [n, d] = String(v).split('/').map(Number); return Number.isFinite(n) && Number.isFinite(d) && d > 0 ? n / d : NaN; };

export function readPhysicalResultObservations({ root, path, candidatePath = null, inputs, beats, probe = null, decode = decodeFrame }) {
  const sidecarRelative = relative(root, path);
  if (sidecarRelative === '..' || sidecarRelative.startsWith('../') || sidecarRelative.startsWith('..\\') || isAbsolute(sidecarRelative)) die('sidecar must be job-relative');
  const doc = JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
  if (doc.schema !== 'media-studio/physical-result-observations/1') die('unsupported schema');
  if (!text(doc.reviewer?.identity) || !text(doc.producer) || doc.reviewer.identity.trim() === doc.producer.trim() || doc.reviewer.independent !== true || !text(doc.reviewer.method)) die('independent identified reviewer and method required');
  const candidate = file(root, doc.candidate);
  if (candidatePath && resolve(candidatePath) !== candidate) die('candidate path differs');
  for (const key of ['receipt', 'composeMap', 'cuePlan']) {
    file(root, doc.inputs?.[key]);
    if (!inputs?.[key] || doc.inputs[key].sha256 !== inputs[key].sha256 || doc.inputs[key].path !== inputs[key].path) die(`${key} binding differs`);
  }
  const receipt = JSON.parse(readFileSync(file(root, doc.inputs.receipt), 'utf8').replace(/^\uFEFF/, ''));
  if (!probe) {
    const p = spawnSync('ffprobe', ['-v', 'error', '-show_streams', '-of', 'json', candidate], { encoding: 'utf8', windowsHide: true });
    if (p.status !== 0) die('cannot probe candidate');
    probe = JSON.parse(p.stdout);
  }
  const video = probe.streams?.find((s) => s.codec_type === 'video');
  if (![video?.width, video?.height].every((v) => Number.isInteger(v) && v > 0)) die('invalid encoded viewport');
  const { numerator: n, denominator: d } = doc.frameRate || {};
  const fps = n / d; const frames = Number(video?.nb_frames);
  const avg = fraction(video?.avg_frame_rate); const nominal = fraction(video?.r_frame_rate);
  if (!Number.isInteger(n) || n <= 0 || !Number.isInteger(d) || d <= 0 || !Number.isInteger(frames) || frames <= 0 || !Number.isFinite(avg) || !Number.isFinite(nominal) || Math.abs(avg - fps) > 1e-8 || Math.abs(nominal - fps) > 1e-8) die('frame rate/count is not exact constant-rate candidate clock');
  if (!Array.isArray(doc.observations) || !doc.observations.length) die('nonempty observations required');
  const seen = new Set(); const observations = new Map();
  for (const o of doc.observations) {
    if (!text(o.beat) || seen.has(o.beat)) die('duplicate or missing beat'); seen.add(o.beat);
    const b = beats.find((b) => b.beat === o.beat);
    if (!b?.result || o.clip !== b.screen?.clip || !Number.isInteger(o.receiptExpectationIndex) || o.receiptExpectationIndex !== b.result.receipt_expectation_index || o.label !== b.result.label) die('unknown or mismatched receipt event identity');
    const clip = receipt.clips?.[o.clip]; const event = clip?.expectations?.[o.receiptExpectationIndex];
    if (event?.observed !== true || !Number.isFinite(event.observedAt) || !text(event.label) || !event.label.toLowerCase().includes(o.label.toLowerCase())) die('receipt does not establish named observed result');
    if (!text(clip.file)) die('receipt source clip missing');
    file(root, { path: relative(root, resolve(dirname(resolve(root, doc.inputs.receipt.path)), clip.file)), sha256: clip.sha256 });
    if (!Number.isInteger(o.firstVisibleFrame) || o.firstVisibleFrame <= 0 || o.firstVisibleFrame >= frames || o.previousFrame !== o.firstVisibleFrame - 1) die('missing adjacent previous frame or out-of-range frame');
    const seconds = o.firstVisibleFrame / fps;
    if (![b.slot_start, b.slot_end, b.screen?.visible_from, b.screen?.visible_until].every(Number.isFinite) || seconds < b.slot_start || seconds >= b.slot_end || seconds < b.screen.visible_from || seconds >= b.screen.visible_until) die('result frame outside beat/retained screen');
    const r = o.region;
    if (!r || ![r.x, r.y, r.w, r.h].every(Number.isInteger) || r.x < 0 || r.y < 0 || r.w <= 0 || r.h <= 0 || r.x + r.w > video.width || r.y + r.h > video.height) die('result region outside encoded viewport');
    if (!text(o.previousState) || !text(o.visibleState) || o.previousState.trim() === o.visibleState.trim()) die('distinct prior/result state descriptions required');
    const pixels = [];
    for (const [key, frame] of [['previousEvidence', o.previousFrame], ['visibleEvidence', o.firstVisibleFrame]]) {
      if (o[key]?.frame !== frame) die('evidence frame identity differs');
      const evidence = file(root, o[key]);
      const actual = decode(candidate, frame, r); const saved = decode(evidence, 0, null);
      if (actual.length !== r.w * r.h * 4 || !actual.equals(saved)) die('evidence pixels differ from candidate frame/region');
      pixels.push(actual);
    }
    if (pixels[0].equals(pixels[1])) die('adjacent result region has no pixel transition');
    observations.set(o.beat, { seconds, observation: o, pollObservedAt: event.observedAt });
  }
  return { ref: { path: relative(root, path).replace(/\\/g, '/'), sha256: hash(path) }, observations };
}

function decodeFrame(path, frame, region) {
  const filters = [`select=eq(n\\,${frame})`, ...(region ? [`crop=${region.w}:${region.h}:${region.x}:${region.y}:exact=1`] : []), 'format=rgba'];
  const r = spawnSync('ffmpeg', ['-v', 'error', '-threads', '2', '-filter_threads', '1', '-i', path, '-vf', filters.join(','), '-frames:v', '1', '-f', 'rawvideo', 'pipe:1'], { windowsHide: true, maxBuffer: 1 << 27, timeout: 120000 });
  if (r.status !== 0 || !r.stdout?.length) die('cannot decode candidate/evidence frame');
  return r.stdout;
}

export function applyPhysicalResultObservations(beats, proof, { verify = false } = {}) {
  for (const b of beats) {
    const found = proof?.observations.get(b.beat);
    if (!found) { if (b.result?.physical_observation) die('cue declares unbound physical observation'); continue; }
    const identity = { sidecar: proof.ref, first_visible_frame: found.observation.firstVisibleFrame, receipt_observed_at: found.pollObservedAt };
    if (verify) {
      if (b.result.visible_at !== found.seconds || JSON.stringify(b.result.physical_observation) !== JSON.stringify(identity) || !Number.isFinite(b.result.poll_visible_at)) die('cue observation time/provenance differs');
    } else {
      if (!Number.isFinite(b.result.visible_at)) die('missing original mapped polling time');
      b.result.poll_visible_at = b.result.visible_at;
      b.result.visible_at = found.seconds;
      b.result.physical_observation = identity;
    }
  }
}
