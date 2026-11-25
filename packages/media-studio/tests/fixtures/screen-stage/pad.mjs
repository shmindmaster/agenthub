// Deterministic synthesised instrumental pad: the stand-in "licensed bed" for the effects-mix gate test.
// Usage: node pad.mjs <out.wav> [seconds=20] [--bright]
// Slow sine chords with a soft attack and almost no energy in 2-5 kHz. --bright adds steady noisy 3 kHz content: a bad bed that must fail the gate.
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { bandpass, mulberry32, SAMPLE_RATE, writeWav16 } from '../../../kit/screencast/click-sound.mjs';

export const PAD_PEAK = 0.2; // about -14 dBFS
export const BRIGHT_NOISE = 0.3; // in-band noise gain before the final scale

export function buildPad({ seconds = 20, bright = false } = {}) {
  const sr = SAMPLE_RATE, n = Math.round(seconds * sr);
  const chords = [[110, 164.81, 220, 277.18], [87.31, 130.81, 174.61, 220], [98, 146.83, 196, 246.94], [110, 164.81, 220, 277.18]];
  const each = 5; // seconds per chord; each fades in over 2 s and out over 2 s, so neighbours overlap
  const y = new Float64Array(n);
  for (let c = 0; c * each < seconds + 2; c++) {
    const t0 = c * each - 1, notes = chords[c % chords.length];
    for (let i = Math.max(0, Math.round(t0 * sr)); i < Math.min(n, Math.round((t0 + each + 2) * sr)); i++) {
      const t = i / sr - t0, env = Math.min(1, t / 2, (each + 2 - t) / 2);
      let v = 0;
      for (const f of notes) v += Math.sin(2 * Math.PI * f * t) + 0.25 * Math.sin(4 * Math.PI * f * t) + 0.08 * Math.sin(6 * Math.PI * f * t);
      y[i] += Math.max(0, env) * v * 0.25;
    }
  }
  if (bright) {
    const rng = mulberry32(7), noise = new Float64Array(n);
    for (let i = 0; i < n; i++) noise[i] = rng() * 2 - 1;
    const band = bandpass(noise, 3000, 2, sr);
    for (let i = 0; i < n; i++) y[i] += BRIGHT_NOISE * band[i];
  }
  let peak = 0;
  for (const v of y) peak = Math.max(peak, Math.abs(v));
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = (y[i] / peak) * PAD_PEAK;
  return out;
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  if (!args[0]) { console.error('Usage: node pad.mjs <out.wav> [seconds] [--bright]'); process.exit(1); }
  writeWav16(args[0], buildPad({ seconds: Number(args[1]) || 20, bright: process.argv.includes('--bright') }));
}
