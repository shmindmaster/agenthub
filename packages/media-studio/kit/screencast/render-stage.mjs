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
const r = spawnSync(process.execPath, args, { cwd: kit, stdio: 'inherit', windowsHide: true });
rmSync(tmp, { recursive: true, force: true });
if (r.status !== 0) process.exit(r.status || 1);
const seconds = Number(((Date.now() - started) / 1000).toFixed(1));
console.log(JSON.stringify({ ok: true, out: path.resolve(out), bytes: statSync(out).size, renderSeconds: seconds, frames: Math.round(plan.runSeconds * plan.frame.fps) }));
