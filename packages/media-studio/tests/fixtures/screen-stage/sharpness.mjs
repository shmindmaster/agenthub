// Text-edge sharpness of a screen-stage film at rest, against the best the capture can give at the same geometry.
// For a hold time t (camera still), the reference is the captured frame cropped to what the camera shows and resampled to the film grid
// (area filter, one resample, no blur); the film frame is compared to it by high-pass energy (ratio) and by correlation of the high-pass.
// A second row does the same for the unzoomed opening, so the zoomed text is shown to hold its detail rather than being scaled up.
// Usage: node sharpness.mjs <film.mp4> <stage-plan.json> <frames-dir> <t1> [<t2> ...]
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import { pathToFileURL } from 'node:url';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const kit = join(here, '..', '..', '..', 'kit', 'screencast');
const M = await import(pathToFileURL(join(kit, 'stage-math.mjs')).href);
const F = await import(pathToFileURL(join(kit, 'stage-film-checks.mjs')).href);
const [film, planFile, framesDir, ...times] = process.argv.slice(2);
if (!film || !planFile || !framesDir || !times.length) { console.error('usage: node sharpness.mjs <film.mp4> <stage-plan.json> <frames-dir> <t> [<t> ...]'); process.exit(2); }
const plan = JSON.parse(readFileSync(planFile, 'utf8'));
const g = plan.geometry;
const W = g.W, H = g.H;
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', ...args], { maxBuffer: 2 ** 31 - 1 });
const gray = (buf, n) => Float32Array.from(buf.subarray(0, n));
const have = new Set(readdirSync(framesDir));

const rows = [];
for (const t of times.map(Number)) {
  const cam = M.cameraAt(plan.camera, t, g), st = M.stateAt(plan, t);
  const name = basename(st.frame);
  if (!have.has(name)) { rows.push({ t, error: `frame ${name} not in ${framesDir}` }); continue; }
  const src = join(framesDir, name);
  // the captured frame's pixel size
  const dims = execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', src]).toString().trim().split(',').map(Number);
  const k = dims[0] / W;                                     // capture px per stage px
  const cw = (W / cam.z) * k, ch = (H / cam.z) * k, x0 = (cam.cx - W / (2 * cam.z)) * k, y0 = (cam.cy - H / (2 * cam.z)) * k;
  const ref = gray(ff(['-i', src, '-vf', `crop=${cw.toFixed(3)}:${ch.toFixed(3)}:${x0.toFixed(3)}:${y0.toFixed(3)},scale=${W}:${H}:flags=area,format=gray`, '-frames:v', '1', '-f', 'rawvideo', 'pipe:1']), W * H);
  const fl = gray(ff(['-ss', t.toFixed(4), '-i', film, '-frames:v', '1', '-vf', `scale=${W}:${H}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1']), W * H);
  const win = F.busiestWindow(ref, W, H, 480, 270);
  const crop = (a) => { const o = new Float32Array(480 * 270); for (let j = 0; j < 270; j++) for (let i = 0; i < 480; i++) o[j * 480 + i] = a[(win.y0 + j) * W + win.x0 + i]; return o; };
  const a = F.highpass(crop(fl), 480, 270), b = F.highpass(crop(ref), 480, 270);
  let ea = 0, eb = 0, ab = 0;
  for (let i = 0; i < a.length; i++) { ea += a[i] * a[i]; eb += b[i] * b[i]; ab += a[i] * b[i]; }
  rows.push({ t, zoom: Number(cam.z.toFixed(3)), pxPerCssPx: Number((cam.z * (W / (g.viewport?.width || 1280))).toFixed(2)), window: { x0: win.x0, y0: win.y0 }, highpassRatio: Number((Math.sqrt(ea / eb)).toFixed(3)), highpassCorrelation: Number((ab / Math.sqrt(ea * eb)).toFixed(3)) });
}
console.log(JSON.stringify({ film, rows }, null, 1));
