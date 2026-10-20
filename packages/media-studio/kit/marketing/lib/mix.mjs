// Audio mix and final encode (FFmpeg): voice lines placed on the voice-first timeline, sound effects on their cues,
// a music bed at -24 dB ducked under the voice, then two-pass loudness normalization (-14 LUFS social, -16 web)
// and the mux with the silent Remotion picture. Pure argument builders here; mvg stages run them windowless.
import { spawn } from 'node:child_process';
import { round } from './util.mjs';

export const LOUDNESS = { social: -14, web: -16 };
export const TRUE_PEAK = -1.5;

export function loudnessTarget(ratio, spec, brand) {
  const kind = spec?.qa?.loudness || (ratio === '16x9' ? 'web' : 'social');
  return { kind, lufs: brand?.loudness?.[kind] ?? LOUDNESS[kind], truePeak: brand?.loudness?.truePeak ?? TRUE_PEAK };
}

const ms = (s) => Math.max(0, Math.round(s * 1000));

/** ffmpeg arguments that render the pre-loudness mix wav. `lines`/`sfx` carry absolute file paths and program seconds. */
export function buildMixArgs({ lines, sfx = [], music = null, durationSec, out, bedDb = -24 }) {
  const args = ['-hide_banner', '-loglevel', 'error', '-y'];
  const chains = [];
  const voiceLabels = [];
  let index = 0;
  for (const l of lines) {
    args.push('-i', l.file);
    chains.push(`[${index}:a]aresample=48000,aformat=channel_layouts=stereo,adelay=${ms(l.startSec)}|${ms(l.startSec)}[v${index}]`);
    voiceLabels.push(`[v${index}]`);
    index++;
  }
  const sfxLabels = [];
  for (const s of sfx) {
    args.push('-i', s.file);
    chains.push(`[${index}:a]aresample=48000,aformat=channel_layouts=stereo,volume=${s.gainDb ?? -12}dB,adelay=${ms(s.startSec)}|${ms(s.startSec)}[s${index}]`);
    sfxLabels.push(`[s${index}]`);
    index++;
  }
  if (!voiceLabels.length) throw new Error('mix needs at least one narration line');
  chains.push(`${voiceLabels.join('')}amix=inputs=${voiceLabels.length}:normalize=0:duration=longest,asplit=2[voice][voicesc]`);
  const mixIns = ['[voice]'];
  if (sfxLabels.length) {
    chains.push(`${sfxLabels.join('')}amix=inputs=${sfxLabels.length}:normalize=0:duration=longest[sfxbus]`);
    mixIns.push('[sfxbus]');
  }
  if (music) {
    args.push('-i', music.file);
    chains.push(`[${index}:a]aresample=48000,aformat=channel_layouts=stereo,volume=${music.bedDb ?? bedDb}dB,atrim=duration=${round(durationSec, 3)},afade=t=in:d=0.6,afade=t=out:st=${round(Math.max(0, durationSec - 1.4), 3)}:d=1.4[bed0]`);
    chains.push('[bed0][voicesc]sidechaincompress=threshold=0.02:ratio=8:attack=30:release=500[bed]');
    mixIns.push('[bed]');
  } else chains.push('[voicesc]anullsink');
  chains.push(`${mixIns.join('')}amix=inputs=${mixIns.length}:normalize=0:duration=longest,apad,atrim=duration=${round(durationSec, 3)}[mix]`);
  args.push('-filter_complex', chains.join(';'), '-map', '[mix]', '-ar', '48000', '-ac', '2', '-c:a', 'pcm_s16le', out);
  return args;
}

export function loudnormMeasureArgs(wav, { lufs, truePeak }) {
  return ['-hide_banner', '-nostats', '-i', wav, '-af', `loudnorm=I=${lufs}:TP=${truePeak}:LRA=11:print_format=json`, '-f', 'null', '-'];
}

export function parseLoudnorm(stderr) {
  const open = stderr.lastIndexOf('{');
  const close = stderr.lastIndexOf('}');
  if (open < 0 || close < open) throw new Error('loudnorm printed no measurement');
  const m = JSON.parse(stderr.slice(open, close + 1));
  return { integrated: Number(m.input_i), truePeak: Number(m.input_tp), lra: Number(m.input_lra), thresh: Number(m.input_thresh), offset: Number(m.target_offset) };
}

/** Second-pass loudnorm + mux of the silent picture with the mix. H.264 yuv420p 30 fps + AAC 48 kHz, faststart. */
export function encodeArgs({ silent, mixWav, out, measured, target }) {
  const ln = `loudnorm=I=${target.lufs}:TP=${target.truePeak}:LRA=11:measured_I=${measured.integrated}:measured_TP=${measured.truePeak}:measured_LRA=${measured.lra}:measured_thresh=${measured.thresh}:offset=${measured.offset}:linear=true:print_format=json`;
  return ['-hide_banner', '-loglevel', 'error', '-y', '-i', silent, '-i', mixWav, '-map', '0:v:0', '-map', '1:a:0', '-af', `${ln},aresample=48000`,
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-r', '30', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-movflags', '+faststart', '-shortest', out];
}

/** Run ffmpeg/ffprobe without a window. Resolves { code, stdout, stderr }. */
export function run(cmd, args, { timeoutMs = 900000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error(`${cmd} timed out`)); }, timeoutMs);
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', (e) => { clearTimeout(timer); reject(e); });
    child.on('close', (code) => { clearTimeout(timer); resolve({ code, stdout, stderr }); });
  });
}
