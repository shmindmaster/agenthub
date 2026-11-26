// Click and tap sounds for the screen stage, synthesised from a seed: filtered noise bursts plus a low thump. No sample files.
// Same input, same bytes. Each event varies by its seed within +-1 dB and +-2% pitch/filter, so repeats are not identical.
import { writeFileSync } from 'node:fs';

export const SAMPLE_RATE = 48000;
export const GAIN_VARIATION_DB = 1;
export const PITCH_VARIATION = 0.02;
export const RELEASE_DELAY_SECONDS = 0.07;
// Peak of each sound before the seed's gain. A tap is about 6 dB under a mouse press; a release is 6 dB under its press.
const PRESS_LEVEL = { mouse: 1, tap: 0.5 };
const RELEASE_LEVEL = 0.5;

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Seed from the press time (ms) and label: FNV-1a, so the same press always sounds the same. */
export function seedFor(t, label) {
  let h = 0x811c9dc5;
  for (const c of `${Math.round(t * 1000)}|${label ?? ''}`) { h ^= c.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
  return h;
}

/** RBJ band-pass (constant 0 dB peak) run over a buffer. */
export function bandpass(x, f0, q, sr) {
  const w = (2 * Math.PI * f0) / sr, alpha = Math.sin(w) / (2 * q), a0 = 1 + alpha;
  const b0 = alpha / a0, b2 = -alpha / a0, a1 = (-2 * Math.cos(w)) / a0, a2 = (1 - alpha) / a0;
  const y = new Float64Array(x.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < x.length; i++) {
    const v = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
  }
  return y;
}

/** One transient: band-passed noise (decay `tau`) plus a decaying sine thump, peak-normalised to 1, 0.3 ms attack and a short fade. */
function transient(rng, { f0, q, noiseMs, tauMs, thumpHz, thumpMs, thumpTauMs, thumpMix }, sr) {
  const n = Math.round((Math.max(noiseMs, thumpMs) / 1000) * sr);
  const noise = new Float64Array(n);
  for (let i = 0; i < n; i++) noise[i] = rng() * 2 - 1;
  const ring = bandpass(noise, f0, q, sr);
  const y = new Float64Array(n);
  const noiseN = Math.round((noiseMs / 1000) * sr), thumpN = Math.round((thumpMs / 1000) * sr);
  for (let i = 0; i < n; i++) {
    const t = i / sr;
    if (i < noiseN) y[i] += ring[i] * Math.exp(-t / (tauMs / 1000));
    if (i < thumpN) y[i] += thumpMix * Math.sin(2 * Math.PI * thumpHz * t) * Math.exp(-t / (thumpTauMs / 1000));
  }
  const attack = Math.round(0.0003 * sr), fade = Math.round(0.002 * sr);
  let peak = 0;
  for (let i = 0; i < n; i++) {
    if (i < attack) y[i] *= i / attack;
    if (i >= n - fade) y[i] *= 0.5 * (1 + Math.cos((Math.PI * (i - (n - fade))) / fade));
    peak = Math.max(peak, Math.abs(y[i]));
  }
  if (peak > 0) for (let i = 0; i < n; i++) y[i] /= peak;
  return y;
}

const PRESS = {
  mouse: { f0: 3200, q: 1.4, noiseMs: 14, tauMs: 2.2, thumpHz: 140, thumpMs: 24, thumpTauMs: 5, thumpMix: 0.5 },
  tap: { f0: 2800, q: 1.0, noiseMs: 9, tauMs: 1.6, thumpHz: 110, thumpMs: 16, thumpTauMs: 4, thumpMix: 0.7 },
};
const RELEASE = { f0: 3800, q: 1.4, noiseMs: 8, tauMs: 1.3, thumpHz: 180, thumpMs: 12, thumpTauMs: 3, thumpMix: 0.3 };
const scaled = (p, pitch) => ({ ...p, f0: p.f0 * pitch, thumpHz: p.thumpHz * pitch });

/** The seed's gain (+-1 dB) and pitch/filter factor (+-2%), drawn first from the event's generator. */
export function drawVariation(rng) {
  return { gainDb: (rng() * 2 - 1) * GAIN_VARIATION_DB, pitch: 1 + (rng() * 2 - 1) * PITCH_VARIATION };
}

/** One click: a mouse click is a press transient and, 70 ms later, a softer release; a tap is a single softer, shorter transient. */
export function synthClick({ kind = 'mouse', seed = 0 } = {}) {
  if (!PRESS[kind]) throw new Error(`click kind must be mouse or tap, got ${kind}`);
  const sr = SAMPLE_RATE, rng = mulberry32(seed);
  const { gainDb, pitch } = drawVariation(rng), gain = 10 ** (gainDb / 20);
  const press = transient(rng, scaled(PRESS[kind], pitch), sr);
  const release = kind === 'mouse' ? transient(rng, scaled(RELEASE, pitch), sr) : null;
  const releaseAt = Math.round(RELEASE_DELAY_SECONDS * sr);
  const out = new Float32Array(release ? releaseAt + release.length : press.length);
  for (let i = 0; i < press.length; i++) out[i] += gain * PRESS_LEVEL[kind] * press[i];
  if (release) for (let i = 0; i < release.length; i++) out[releaseAt + i] += gain * RELEASE_LEVEL * release[i];
  return out;
}

/** 16-bit mono PCM WAV bytes of float samples in [-1, 1]. */
export function encodeWav16(samples, sampleRate = SAMPLE_RATE) {
  const data = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) data.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(samples[i] * 32767))), i * 2);
  const head = Buffer.alloc(44);
  head.write('RIFF', 0); head.writeUInt32LE(36 + data.length, 4); head.write('WAVEfmt ', 8);
  head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22);
  head.writeUInt32LE(sampleRate, 24); head.writeUInt32LE(sampleRate * 2, 28); head.writeUInt16LE(2, 32); head.writeUInt16LE(16, 34);
  head.write('data', 36); head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
}

export function writeWav16(file, samples, sampleRate = SAMPLE_RATE) {
  const bytes = encodeWav16(samples, sampleRate);
  writeFileSync(file, bytes);
  return bytes;
}
