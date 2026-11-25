// Render one screen-stage run: the plan (stage-plan.mjs) and the captured frames become a 60 fps silent H.264 picture through the
// kit's Remotion composition "ScreenStage". Renders belong on Daytona (render-lanes.md), never on the owner's PC.
// Usage: node render-stage.mjs --plan <plan.json> --public-dir <dir holding the frames> --out <file.mp4> [--frames-base <sub folder>]
//                              [--kit <kit dir>] [--concurrency 8]
// The plan's frame files are '<clipId>/frames/f000001.jpg', relative to <public-dir>/<frames-base>.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const flag = (name, d = null) => { const i = process.argv.indexOf(name); return i >= 0 ? process.argv[i + 1] : d; };
const here = path.dirname(fileURLToPath(import.meta.url));
const planPath = flag('--plan'), publicDir = flag('--public-dir'), out = flag('--out');
if (!planPath || !publicDir || !out) { console.error('usage: node render-stage.mjs --plan <plan.json> --public-dir <dir> --out <file.mp4> [--frames-base <sub>] [--kit <dir>] [--concurrency n]'); process.exit(2); }
const kit = path.resolve(flag('--kit', path.join(here, '..')));
const framesBase = (flag('--frames-base', '') || '').replace(/\\/g, '/').replace(/\/$/, '');
const plan = JSON.parse(readFileSync(planPath, 'utf8'));

// Every frame the plan can show must exist before a long render starts.
const missing = [];
for (const f of Object.values(plan.frames)) for (const file of f.files) if (!existsSync(path.join(publicDir, framesBase, file))) missing.push(file);
if (missing.length) { console.error(`[render-stage] ${missing.length} captured frame(s) are missing under ${path.join(publicDir, framesBase)}, first: ${missing[0]}`); process.exit(1); }

const cli = path.join(kit, 'node_modules', '@remotion', 'cli', 'remotion-cli.js');
if (!existsSync(cli)) { console.error(`[render-stage] Remotion CLI not found at ${cli}: run npm ci in the kit`); process.exit(1); }
const tmp = mkdtempSync(path.join(tmpdir(), 'screen-stage-'));
const propsPath = path.join(tmp, 'props.json');
writeFileSync(propsPath, JSON.stringify({ plan, framesBase }));
mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
const started = Date.now();
const args = [cli, 'render', 'src/index.ts', 'ScreenStage', path.resolve(out), `--props=${propsPath}`, `--public-dir=${path.resolve(publicDir)}`,
  '--image-format=png', '--codec=h264', '--crf=15', '--x264-preset=medium', '--pixel-format=yuv420p', '--color-space=bt709', '--muted', `--concurrency=${flag('--concurrency', '8')}`, `--gl=${process.env.STAGE_GL || (process.platform === 'linux' ? 'swangle' : 'angle')}`, '--overwrite', ...(process.env.STAGE_LOG ? [`--log=${process.env.STAGE_LOG}`] : [])];
// A render whose screenshot came from a canvas that had not been presented yet shows one earlier frame: a one-frame reversion (A, B, A).
// The film is checked after every render and a bad render is made again, never edited. Pixels are never touched.
const F = await import('./stage-film-checks.mjs');
const reversions = (file) => {
  const W = 480, H = 270;
  const raw = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', file, '-vf', `scale=${W}:${H}:flags=area,format=gray`, '-f', 'rawvideo', 'pipe:1'], { maxBuffer: 2 ** 31 - 1, windowsHide: true }).stdout;
  const n = Math.floor(raw.length / (W * H));
  return F.oneFrameReversions(Array.from({ length: n }, (_, i) => raw.subarray(i * W * H, (i + 1) * W * H)), { allowed: (plan.declaredAnimations || []).map((a) => ({ from: Math.floor(a.from * plan.frame.fps), to: Math.ceil(a.to * plan.frame.fps) })) });
};
let attempts = 0, r;
for (;;) {
  attempts++;
  r = spawnSync(process.execPath, args, { cwd: kit, stdio: 'inherit', windowsHide: true });
  if (r.status !== 0) { rmSync(tmp, { recursive: true, force: true }); process.exit(r.status || 1); }
  const bad = reversions(path.resolve(out));
  if (!bad.length) break;
  console.error(`[render-stage] attempt ${attempts}: ${bad.length} one-frame reversion(s) at film frame ${bad.map((b) => b.i).join(', ')}: the render showed an earlier picture for a frame`);
  if (attempts >= 3) { rmSync(tmp, { recursive: true, force: true }); console.error('[render-stage] the render still shows a one-frame reversion after 3 attempts'); process.exit(1); }
}
rmSync(tmp, { recursive: true, force: true });
const seconds = Number(((Date.now() - started) / 1000).toFixed(1));
console.log(JSON.stringify({ ok: true, out: path.resolve(out), bytes: statSync(out).size, renderSeconds: seconds, attempts, frames: Math.round(plan.runSeconds * plan.frame.fps) }));
