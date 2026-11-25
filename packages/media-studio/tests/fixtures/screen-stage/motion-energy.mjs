// Per-0.1 s motion energy of a film, for the numeric comparison with the owner's reference. Style reference only: nothing is written
// from the reference but these numbers. Usage: node motion-energy.mjs <film.mp4> [--out energy.json]
// Energy = mean absolute difference of consecutive frames (gray, 480x270). A move is a run of 0.1 s bins above 3x the still floor.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const file = process.argv[2];
const outAt = process.argv.indexOf('--out');
if (!file) { console.error('usage: node motion-energy.mjs <film.mp4> [--out energy.json]'); process.exit(2); }
const probe = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height,avg_frame_rate,nb_frames,duration', '-of', 'json', file]).toString()).streams[0];
const [n, d] = probe.avg_frame_rate.split('/').map(Number);
const fps = n / d;
const W = 480, H = 270;
const raw = execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', file, '-vf', `scale=${W}:${H}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1'], { maxBuffer: 2 ** 31 - 1 });
const frames = Math.floor(raw.length / (W * H));
const diffs = [0];
for (let i = 1; i < frames; i++) {
  let s = 0;
  const a = (i - 1) * W * H, b = i * W * H;
  for (let k = 0; k < W * H; k++) s += Math.abs(raw[a + k] - raw[b + k]);
  diffs.push(s / (W * H));
}
const per = Math.max(1, Math.round(fps / 10));
const bins = [];
for (let i = 0; i < diffs.length; i += per) { const sl = diffs.slice(i, i + per); bins.push(Number((sl.reduce((x, y) => x + y, 0) / sl.length).toFixed(3))); }
const sorted = [...bins].sort((x, y) => x - y);
const floor = sorted[Math.floor(sorted.length * 0.3)] || 0.01;
const thr = Math.max(0.15, floor * 3);
const moves = [];
let cur = null;
bins.forEach((e, i) => {
  if (e > thr) { if (!cur) cur = { startSeconds: i / 10, peak: 0, peakAt: 0 }; if (e > cur.peak) { cur.peak = e; cur.peakAt = i / 10; } cur.endSeconds = (i + 1) / 10; }
  else if (cur) { moves.push(cur); cur = null; }
});
if (cur) moves.push(cur);
const summary = { file, width: probe.width, height: probe.height, fps: Number(fps.toFixed(3)), seconds: Number(probe.duration), frames, thresholdEnergy: Number(thr.toFixed(3)), moves: moves.map((m) => ({ ...m, durationSeconds: Number((m.endSeconds - m.startSeconds).toFixed(2)), timeToPeakSeconds: Number((m.peakAt - m.startSeconds).toFixed(2)), peak: Number(m.peak.toFixed(2)) })) };
const full = { ...summary, bins };
if (outAt >= 0) writeFileSync(process.argv[outAt + 1], JSON.stringify(full));
console.log(JSON.stringify(summary));
