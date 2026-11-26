// Frame audit of a captured take: is the list of captured frames itself in order and free of one-frame reversions?
// Usage: node frame-audit.mjs <jobRoot> [clipId=S01]
// 1. timestamps (frames.json) strictly increase in arrival order; 2. no captured frame differs from both neighbours while the
// neighbours are alike (A, B, A) -- if it does, the product painted it or the browser delivered it, and the evidence is printed.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const [jobRoot, clip = 'S01'] = process.argv.slice(2);
const dir = join(jobRoot, 'capture', 'raw', clip);
const idx = JSON.parse(readFileSync(join(dir, 'frames.json'), 'utf8'));
const frames = idx.frames;
const W = 240, H = 135;
const gray = (f) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', join(dir, 'frames', f), '-vf', `scale=${W}:${H}:flags=area,format=gray`, '-frames:v', '1', '-f', 'rawvideo', 'pipe:1'], { maxBuffer: 1 << 26 });
const g = frames.map((f) => gray(f.file));
const d = (a, b) => { let s = 0; for (let k = 0; k < a.length; k++) s += Math.abs(a[k] - b[k]); return s / a.length; };
const order = [];
for (let i = 1; i < frames.length; i++) if (!(frames[i].t > frames[i - 1].t)) order.push({ i, file: frames[i].file, t: frames[i].t, prevT: frames[i - 1].t });
const aba = [];
for (let i = 1; i < frames.length - 1; i++) {
  const a = d(g[i - 1], g[i]), b = d(g[i], g[i + 1]);
  if (a > 0.15 && b > 0.15) { const c = d(g[i - 1], g[i + 1]); if (c < 0.35 * Math.min(a, b)) aba.push({ i, file: frames[i].file, t: Number(frames[i].t.toFixed(4)), toPrev: Number(a.toFixed(2)), toNext: Number(b.toFixed(2)), prevToNext: Number(c.toFixed(2)) }); }
}
const gaps = frames.slice(1).map((f, i) => Number(((f.t - frames[i].t) * 1000).toFixed(1)));
console.log(JSON.stringify({ clip, frames: frames.length, timestampsOutOfOrder: order, oneFrameReversions: aba, firstGapsMs: gaps.slice(0, 12) }, null, 1));
