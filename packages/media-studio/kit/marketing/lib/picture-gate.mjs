// Encoded-picture gate for mvg ads. validate-encoded-picture.mjs compares whole frames, which cannot hold for an ad
// that composites the UI into a band beside captions, so this gate applies the same three tests to the UI band:
//   1. source binding: at each UI segment's midpoint the band decoded from the candidate perceptually matches
//      (dHash, Hamming <= 12) a frame of the receipt-bound source clip under that segment's sourceRegion;
//   2. no dead screen: inside UI segments no stretch of near-identical band frames longer than 6 s;
//   3. designed first/last frames (not black) and a UI-seconds ratio >= 0.7.
// The pure helpers are exported for tests; `runPictureGate` drives ffmpeg windowlessly.
import { execFileSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import { fileSha, round } from './util.mjs';

export const THRESHOLDS = { bindMaxHamming: 12, maxStaticSeconds: 6, screenRatioMin: 0.7, staticChangedFraction: 0.003, changedPixelDelta: 16 };

export function dhash(gray9x8) {
  let bits = 0n;
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { bits <<= 1n; if (gray9x8[y * 9 + x] > gray9x8[y * 9 + x + 1]) bits |= 1n; }
  return bits;
}
export function hamming(a, b) { let x = a ^ b; let n = 0; while (x) { n += Number(x & 1n); x >>= 1n; } return n; }
export const changedFraction = (a, b, delta = THRESHOLDS.changedPixelDelta) => { let n = 0; for (let i = 0; i < a.length; i++) if (Math.abs(a[i] - b[i]) > delta) n++; return n / a.length; };
export const meanLuma = (a) => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i]; return s / a.length; };

/** Runs of near-identical consecutive frames: [{startSeconds,endSeconds,seconds}] for frames sampled at `fps`. */
export function staticRuns(frames, fps) {
  const flags = frames.map((f, i) => (i === 0 ? false : changedFraction(frames[i - 1], f) < THRESHOLDS.staticChangedFraction));
  const runs = [];
  let start = null;
  for (let i = 0; i < flags.length; i++) {
    if (flags[i] && start === null) start = i - 1;
    if ((!flags[i] || i === flags.length - 1) && start !== null) {
      const end = flags[i] ? i : i - 1;
      runs.push({ startSeconds: start / fps, endSeconds: (end + 1) / fps, seconds: (end + 1 - start) / fps });
      start = null;
    }
  }
  return runs;
}

/** Best (lowest) Hamming distance between `h` and any of `hashes`. */
export function bestDistance(h, hashes) {
  let best = 64;
  for (const c of hashes) { const d = hamming(h, c); if (d < best) best = d; if (best === 0) break; }
  return best;
}

const ffmpeg = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-hwaccel', 'none', ...args], { maxBuffer: 1 << 30, windowsHide: true });
const cropExpr = (band) => `crop=${band.w}:${band.h}:${band.x}:${band.y}`;

function grayFrames(file, vf, w, h, fps) {
  const buf = ffmpeg(['-i', file, '-vf', `${vf},fps=${fps},scale=${w}:${h}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']);
  const n = Math.floor(buf.length / (w * h));
  return Array.from({ length: n }, (_, i) => buf.subarray(i * w * h, (i + 1) * w * h));
}
function grayAt(file, t, vf, w, h) {
  const buf = ffmpeg(['-ss', t.toFixed(3), '-i', file, '-frames:v', '1', '-vf', `${vf},scale=${w}:${h}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']);
  return buf.length >= w * h ? buf.subarray(0, w * h) : null;
}

/**
 * @param {object} o { candidate, band:{x,y,w,h}, segments:[{id,kind,startSeconds,durationSeconds,clipFile,sourceRegion,clipStart}], durationSeconds }
 */
export function runPictureGate(o) {
  const errors = [];
  const fail = (m) => errors.push(m);
  const report = { generator: 'media-studio/mvg-picture-gate', thresholds: THRESHOLDS, band: o.band, segments: [], staticRuns: [] };
  if (!existsSync(o.candidate)) return { ...report, ok: false, errors: [`candidate not found: ${o.candidate}`] };
  report.candidate = { path: o.candidate, sha256: fileSha(o.candidate), bytes: statSync(o.candidate).size };
  const bandVf = cropExpr(o.band);
  // dead-screen scan on the band
  const frames = grayFrames(o.candidate, bandVf, 160, 100, 2);
  for (const r of staticRuns(frames, 2)) {
    const seg = o.segments.find((s) => r.startSeconds + r.seconds / 2 >= s.startSeconds && r.startSeconds + r.seconds / 2 < s.startSeconds + s.durationSeconds);
    const row = { ...r, segment: seg?.id || null, ui: seg?.kind === 'ui' };
    report.staticRuns.push(row);
    if (seg?.kind === 'ui' && r.seconds > THRESHOLDS.maxStaticSeconds) fail(`dead screen: ${r.seconds.toFixed(1)}s of near-identical UI frames at ${r.startSeconds.toFixed(1)}s (segment ${seg.id})`);
  }
  let ui = 0;
  let total = 0;
  for (const seg of o.segments) {
    total += seg.durationSeconds;
    const row = { id: seg.id, kind: seg.kind, hamming: null, bound: null };
    report.segments.push(row);
    if (seg.kind !== 'ui') continue;
    ui += seg.durationSeconds;
    if (!existsSync(seg.clipFile)) { fail(`segment ${seg.id}: source clip missing ${seg.clipFile}`); continue; }
    const r = seg.sourceRegion;
    const crop = `crop=iw*${r.width}:ih*${r.height}:iw*${r.x}:ih*${r.y},scale=${o.band.w}:${o.band.h}`;
    const hashes = grayFrames(seg.clipFile, crop, 9, 8, 30).map(dhash);
    const mid = seg.startSeconds + seg.durationSeconds / 2;
    const got = grayAt(o.candidate, Math.min(mid, o.durationSeconds - 0.2), bandVf, 9, 8);
    if (!got || !hashes.length) { fail(`segment ${seg.id}: cannot decode candidate or source frames`); continue; }
    row.hamming = bestDistance(dhash(got), hashes);
    row.bound = row.hamming <= THRESHOLDS.bindMaxHamming;
    if (!row.bound) fail(`segment ${seg.id}: UI band at ${mid.toFixed(1)}s does not match the receipt-bound capture (dHash ${row.hamming} > ${THRESHOLDS.bindMaxHamming})`);
  }
  report.screenRatio = total ? round(ui / total, 3) : null;
  if (total && ui / total < THRESHOLDS.screenRatioMin) fail(`UI ratio ${report.screenRatio} < ${THRESHOLDS.screenRatioMin}`);
  const f0 = grayAt(o.candidate, Math.min(0.7, o.durationSeconds / 2), 'null', 32, 20);
  const f1 = grayAt(o.candidate, Math.max(0, o.durationSeconds - 1), 'null', 32, 20);
  report.firstFrameLuma = f0 ? round(meanLuma(f0), 1) : null;
  report.lastFrameLuma = f1 ? round(meanLuma(f1), 1) : null;
  if (f0 && meanLuma(f0) < 10) fail('first frame is black');
  if (f1 && meanLuma(f1) < 10) fail('last frame is black');
  return { ...report, ok: errors.length === 0, errors };
}
