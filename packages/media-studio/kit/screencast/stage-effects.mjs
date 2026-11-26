// Effects stem for a screen-stage film: one click or tap sound at each press the cursor draws, nothing else (typing is silent).
// Usage: node stage-effects.mjs <jobRoot> <base> [--under-speech]
// Writes output/<base>-effects.wav (16-bit, 48 kHz, mono) and output/<base>-effects.json (presses used, dropped, peak, sha256).
// Finish-Media.ps1 -Effects mixes the stem after loudness normalisation and never ducks it.
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SAMPLE_RATE, encodeWav16, seedFor, synthClick } from './click-sound.mjs';

export const ALONE_PEAK_DBFS = -20;
export const UNDER_SPEECH_PEAK_DBFS = -26;
export const MIN_GAP_MS = 60;
export const EFFECTS_SCHEMA = 'media-studio/effects-stem/1';
const r3 = (v) => Math.round(v * 1000) / 1000;
const dbfs = (lin) => (lin > 0 ? 20 * Math.log10(lin) : -Infinity);

/**
 * Place a synthesised click at each press, sample-accurate (round(t * sampleRate)), then scale the whole stem so it peaks at `peakDbfs`.
 * A press under 60 ms after the last kept one, or outside the film, is dropped and listed.
 * Returns { samples: Float32Array, sampleRate, kept, dropped, peakDbfs }.
 */
export function buildEffectsStem({ presses, durationSeconds, sampleRate = SAMPLE_RATE, peakDbfs = ALONE_PEAK_DBFS }) {
  if (sampleRate !== SAMPLE_RATE) throw new Error(`effects stem is ${SAMPLE_RATE} Hz, got ${sampleRate}`);
  const samples = new Float32Array(Math.round(durationSeconds * sampleRate));
  const kept = [], dropped = [];
  for (const p of [...presses].sort((a, b) => a.t - b.t)) {
    const press = { t: r3(p.t), kind: p.kind === 'tap' ? 'tap' : 'mouse', label: p.label ?? null };
    const start = Math.round(p.t * sampleRate);
    if (!(start >= 0 && start < samples.length)) { dropped.push({ ...press, reason: 'outside-film' }); continue; }
    const last = kept[kept.length - 1];
    if (last && Math.round((p.t - last.t) * 1000) < MIN_GAP_MS) { dropped.push({ ...press, reason: `within-${MIN_GAP_MS}ms-of-${last.t}` }); continue; }
    const click = synthClick({ kind: press.kind, seed: seedFor(p.t, press.label) });
    for (let i = 0; i < click.length && start + i < samples.length; i++) samples[start + i] += click[i];
    kept.push(press);
  }
  let peak = 0;
  for (const v of samples) peak = Math.max(peak, Math.abs(v));
  if (peak > 0) { const k = 10 ** (peakDbfs / 20) / peak; for (let i = 0; i < samples.length; i++) samples[i] *= k; }
  return { samples, sampleRate, kept, dropped, peakDbfs: peak > 0 ? peakDbfs : -Infinity };
}

export function loadComposeMap(jobRoot, base) {
  const dir = join(jobRoot, 'output');
  let file = base ? join(dir, `${base}-compose-map.json`) : null;
  if (!file) {
    const maps = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('-compose-map.json')).map((f) => join(dir, f)).sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs) : [];
    file = maps[0];
  }
  if (!file || !existsSync(file)) throw new Error(`no compose map in ${dir}${base ? ` for ${base}` : ''}`);
  return JSON.parse(readFileSync(file, 'utf8'));
}

/**
 * Absolute film time of every click and tap the cursor draws: stagePlans[n].startSeconds + plan.cursor.clicks[i].t.
 * `job.json` clickSound: 'off' gives an empty list. A touch run gives taps, a pointer run gives mouse clicks.
 */
export function pressesFromComposeMap(jobRoot, base) {
  const jobFile = join(jobRoot, 'job.json');
  const job = existsSync(jobFile) ? JSON.parse(readFileSync(jobFile, 'utf8').replace(/^﻿/, '')) : {};
  if (job.clickSound === 'off') return [];
  const map = loadComposeMap(jobRoot, base);
  const out = [];
  for (const sp of map.stagePlans || []) {
    const plan = JSON.parse(readFileSync(join(jobRoot, sp.file), 'utf8'));
    const start = Number(sp.startSeconds ?? plan.film?.startSeconds);
    if (!Number.isFinite(start)) throw new Error(`stage run ${sp.run}: no startSeconds in the compose map or the plan`);
    const kind = plan.cursor?.mode === 'touch' ? 'tap' : 'mouse';
    for (const c of plan.cursor?.clicks || []) if (Number.isFinite(c.t)) out.push({ t: r3(start + c.t), kind, label: c.label ?? null });
  }
  return out.sort((a, b) => a.t - b.t);
}

async function main(argv) {
  const pos = argv.filter((a) => !a.startsWith('--'));
  const [jobRootArg, base] = pos;
  if (!jobRootArg || !base) { console.error('Usage: node stage-effects.mjs <jobRoot> <base> [--under-speech]'); return 1; }
  const jobRoot = resolve(jobRootArg);
  const presses = pressesFromComposeMap(jobRoot, base);
  if (!presses.length) { console.log(JSON.stringify({ ok: true, skipped: 'no clicks to sound (clickSound off or no clicks in the plans)' })); return 0; }
  const map = loadComposeMap(jobRoot, base);
  const durationSeconds = Number(map.pictureSeconds ?? map.timelineSeconds);
  const target = argv.includes('--under-speech') ? UNDER_SPEECH_PEAK_DBFS : ALONE_PEAK_DBFS;
  const stem = buildEffectsStem({ presses, durationSeconds, peakDbfs: target });
  const wav = encodeWav16(stem.samples);
  let peak = 0;
  for (let i = 0; i < stem.samples.length; i++) peak = Math.max(peak, Math.abs(Math.round(stem.samples[i] * 32767)) / 32767);
  const out = join(jobRoot, 'output');
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, `${base}-effects.wav`), wav);
  const report = { schema: EFFECTS_SCHEMA, base, wav: `output/${base}-effects.wav`, sha256: createHash('sha256').update(wav).digest('hex'), sampleRate: SAMPLE_RATE, durationSeconds, mode: argv.includes('--under-speech') ? 'under-speech' : 'alone', targetPeakDbfs: target, peakDbfs: r3(dbfs(peak)), presses: stem.kept, dropped: stem.dropped };
  writeFileSync(join(out, `${base}-effects.json`), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: true, wav: report.wav, presses: stem.kept.length, dropped: stem.dropped.length, peakDbfs: report.peakDbfs }));
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) process.exit(await main(process.argv.slice(2)));
