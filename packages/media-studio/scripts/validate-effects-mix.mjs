#!/usr/bin/env node
// Gate: the click/tap stem must be audible over the music bed at every press.
// Usage: node validate-effects-mix.mjs <jobRoot> <effects.wav> <bed.wav> [--out qa/effects-mix.json]
// Reads press times from the effects.json beside effects.wav (output/<base>-effects.json). Checks:
//   1. the effects.json belongs to this wav (sha256)
//   2. no two presses within 60 ms
//   3. the stem peaks no higher than -20 dBFS (the alone level; under speech it is lower)
//   4. in the 30 ms from each press, in the 2-5 kHz band, the stem RMS is at least 6 dB above the bed RMS
// WAV parsing and filtering are built in; no ffmpeg. The report is bound to the sha256 of both wavs.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const LIMITS = Object.freeze({ bandHz: [2000, 5000], windowSeconds: 0.03, minMarginDb: 6, minGapMs: 60, maxPeakDbfs: -20 });
export const SCHEMA = 'media-studio/effects-mix/1';
const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');
const db = (lin) => (lin > 0 ? 20 * Math.log10(lin) : -Infinity);
const r2 = (v) => (Number.isFinite(v) ? Math.round(v * 100) / 100 : null);

/** Mono float samples from a PCM (16/24/32-bit) or float32 WAV; channels are averaged. */
export function readWav(buf) {
  if (buf.toString('latin1', 0, 4) !== 'RIFF' || buf.toString('latin1', 8, 12) !== 'WAVE') throw new Error('not a RIFF/WAVE file');
  let fmt = null, data = null;
  for (let p = 12; p + 8 <= buf.length;) {
    const id = buf.toString('latin1', p, p + 4), size = buf.readUInt32LE(p + 4), body = p + 8;
    if (id === 'fmt ') fmt = { tag: buf.readUInt16LE(body), channels: buf.readUInt16LE(body + 2), sampleRate: buf.readUInt32LE(body + 4), bits: buf.readUInt16LE(body + 14), sub: size >= 26 ? buf.readUInt16LE(body + 24) : null };
    if (id === 'data') { data = buf.subarray(body, Math.min(buf.length, body + size)); break; }
    p = body + size + (size & 1);
  }
  if (!fmt || !data) throw new Error('WAV has no fmt or data chunk');
  const tag = fmt.tag === 0xfffe ? fmt.sub : fmt.tag, bytes = fmt.bits / 8;
  const read = tag === 3 && fmt.bits === 32 ? (o) => data.readFloatLE(o)
    : tag === 1 && fmt.bits === 16 ? (o) => data.readInt16LE(o) / 32768
    : tag === 1 && fmt.bits === 24 ? (o) => data.readIntLE(o, 3) / 8388608
    : tag === 1 && fmt.bits === 32 ? (o) => data.readInt32LE(o) / 2147483648
    : null;
  if (!read) throw new Error(`unsupported WAV format tag ${tag} with ${fmt.bits} bits`);
  const frames = Math.floor(data.length / (bytes * fmt.channels)), x = new Float64Array(frames);
  for (let i = 0; i < frames; i++) { let s = 0; for (let c = 0; c < fmt.channels; c++) s += read((i * fmt.channels + c) * bytes); x[i] = s / fmt.channels; }
  return { samples: x, sampleRate: fmt.sampleRate };
}

function biquad(x, b, a) {
  const y = new Float64Array(x.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < x.length; i++) {
    const v = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2;
    x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
  }
  return y;
}
function rbj(type, f0, sr) {
  const w = (2 * Math.PI * f0) / sr, cs = Math.cos(w), alpha = Math.sin(w) / Math.SQRT2, a0 = 1 + alpha;
  const b = type === 'hp' ? [(1 + cs) / 2, -(1 + cs), (1 + cs) / 2] : [(1 - cs) / 2, 1 - cs, (1 - cs) / 2];
  return { b: b.map((v) => v / a0), a: [(-2 * cs) / a0, (1 - alpha) / a0] };
}
/** 2-5 kHz band-pass: two cascaded 2nd-order Butterworth high-pass and low-pass stages. */
export function bandPass({ samples, sampleRate }, [lo, hi] = LIMITS.bandHz) {
  let y = samples;
  for (const [type, f] of [['hp', lo], ['hp', lo], ['lp', hi], ['lp', hi]]) { const c = rbj(type, f, sampleRate); y = biquad(y, c.b, c.a); }
  return y;
}
export function windowRms(y, sampleRate, t, seconds = LIMITS.windowSeconds) {
  const a = Math.max(0, Math.round(t * sampleRate)), b = Math.min(y.length, Math.round((t + seconds) * sampleRate));
  let s = 0;
  for (let i = a; i < b; i++) s += y[i] * y[i];
  return b > a ? Math.sqrt(s / Math.round(seconds * sampleRate)) : 0; // samples past the end count as silence
}
const peakOf = (x) => { let p = 0; for (const v of x) p = Math.max(p, Math.abs(v)); return p; };

/** Measure every press. Returns { ok, peakDbfs, presses: [{ t, label, effectsDb, bedDb, marginDb, ok }], failures }. */
export function checkEffectsMix({ effects, bed, presses }) {
  const fx = bandPass(effects), bd = bandPass(bed), failures = [];
  const peakDbfs = db(peakOf(effects.samples));
  if (peakDbfs > LIMITS.maxPeakDbfs + 0.05) failures.push(`effects stem peaks at ${r2(peakDbfs)} dBFS, above ${LIMITS.maxPeakDbfs} dBFS (alone)`);
  const ts = presses.map((p) => p.t);
  for (let i = 1; i < ts.length; i++) if (Math.round((ts[i] - ts[i - 1]) * 1000) < LIMITS.minGapMs) failures.push(`presses at ${ts[i - 1]} s and ${ts[i]} s are under ${LIMITS.minGapMs} ms apart`);
  const rows = presses.map((p) => {
    const e = db(windowRms(fx, effects.sampleRate, p.t)), m = db(windowRms(bd, bed.sampleRate, p.t));
    const margin = e - m, ok = Number.isFinite(e) && (margin >= LIMITS.minMarginDb || m === -Infinity);
    if (!ok) failures.push(`press at ${p.t} s${p.label ? ` ("${p.label}")` : ''}: effects are ${r2(margin)} dB above the bed in 2-5 kHz, need ${LIMITS.minMarginDb}; lower or duck the bed, or drop the clicks`);
    return { t: p.t, label: p.label ?? null, effectsDb: r2(e), bedDb: r2(m), marginDb: r2(margin), ok };
  });
  return { ok: failures.length === 0, peakDbfs: r2(peakDbfs), presses: rows, failures };
}

function main(argv) {
  const flagAt = argv.indexOf('--out');
  const pos = argv.filter((a, i) => !a.startsWith('--') && (flagAt < 0 || i !== flagAt + 1));
  const [jobRoot, effectsArg, bedArg] = pos;
  if (!jobRoot || !effectsArg || !bedArg) { console.error('Usage: node validate-effects-mix.mjs <jobRoot> <effects.wav> <bed.wav> [--out qa/effects-mix.json]'); return 1; }
  const effectsPath = resolve(effectsArg), bedPath = resolve(bedArg), jsonPath = effectsPath.replace(/\.wav$/i, '.json');
  const outPath = resolve(jobRoot, flagAt >= 0 ? argv[flagAt + 1] : 'qa/effects-mix.json');
  if (!existsSync(jsonPath)) { console.error(`effects report not found beside the stem: ${jsonPath}`); return 2; }
  const effectsBuf = readFileSync(effectsPath), bedBuf = readFileSync(bedPath), jsonBuf = readFileSync(jsonPath);
  const meta = JSON.parse(jsonBuf.toString('utf8'));
  const result = checkEffectsMix({ effects: readWav(effectsBuf), bed: readWav(bedBuf), presses: meta.presses || [] });
  if (meta.sha256 !== sha256(effectsBuf)) { result.ok = false; result.failures.unshift('effects.json was written for a different stem (sha256 differs)'); }
  const report = { schema: SCHEMA, ok: result.ok, limits: LIMITS, effects: { file: effectsPath, sha256: sha256(effectsBuf) }, bed: { file: bedPath, sha256: sha256(bedBuf) }, effectsReport: { file: jsonPath, sha256: sha256(jsonBuf) }, ...result };
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: report.ok, presses: report.presses.length, peakDbfs: report.peakDbfs, failures: report.failures, out: outPath }));
  return report.ok ? 0 : 1;
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) process.exit(main(process.argv.slice(2)));
