// Cloud render worker: runs inside the Azure Container Apps job (mcr.microsoft.com/playwright image, root).
// The job's loader fetches this file and blob.mjs from the `runtime` container and imports it.
// Input: env JOB_ID, STORAGE_ACCOUNT; manifest at jobs/<JOB_ID>/job.json written by cloud-render.mjs.
// Output: outputs, log.txt and result.json under jobs/<JOB_ID>/. Auth: the job's system-assigned managed identity.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { blobClient, lockFingerprint, pool } from './blob.mjs';

const { JOB_ID, STORAGE_ACCOUNT, IDENTITY_ENDPOINT, IDENTITY_HEADER } = process.env;
const RT = '/opt/rt';
const JOB = '/job';
// Static GPL FFmpeg (libx264, loudnorm) from the BtbN builds ffmpeg.org links to. Asset names move with each FFmpeg
// release, so the newest numbered release is resolved from the `latest` tag; the master build is the fallback.
const FFMPEG_RELEASE = 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/tags/latest';
const FFMPEG_FALLBACK = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz';

async function ffmpegUrl() {
  try {
    const rel = await (await fetch(FFMPEG_RELEASE, { headers: { 'User-Agent': 'media-studio-cloud-render' } })).json();
    const ver = (n) => n.match(/-n(\d+)\.(\d+)-latest-linux64-gpl-/).slice(1).map(Number);
    const best = rel.assets.filter((a) => /^ffmpeg-n\d+\.\d+-latest-linux64-gpl-[\d.]+\.tar\.xz$/.test(a.name)).sort((a, b) => {
      const [x, y] = [ver(a.name), ver(b.name)];
      return y[0] - x[0] || y[1] - x[1];
    })[0];
    if (best) return best.browser_download_url;
  } catch (err) {
    log(`ffmpeg release lookup failed (${err.message}); using master build`);
  }
  return FFMPEG_FALLBACK;
}

let token = null;
async function getToken() {
  if (token && token.expires - 300 > Date.now() / 1000) return token.value;
  const res = await fetch(`${IDENTITY_ENDPOINT}?resource=https://storage.azure.com/&api-version=2019-08-01`, { headers: { 'X-IDENTITY-HEADER': IDENTITY_HEADER } });
  if (!res.ok) throw new Error(`managed identity token: HTTP ${res.status}`);
  const j = await res.json();
  token = { value: j.access_token, expires: Number(j.expires_on) };
  return token.value;
}
const blob = blobClient(STORAGE_ACCOUNT, getToken);
const prefix = `jobs/${JOB_ID}`;

fs.mkdirSync(JOB, { recursive: true });
const logFile = path.join(JOB, 'log.txt');
const logStream = fs.createWriteStream(logFile, { flags: 'a' });
const log = (msg) => {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stdout.write(line);
  logStream.write(line);
};
const flushLog = async () => {
  await new Promise((r) => logStream.write('', r));
  await blob.putFile(`${prefix}/log.txt`, logFile).catch(() => {});
};

function sh(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    log(`$ ${cmd} ${args.map((a) => (/\s/.test(a) ? JSON.stringify(a) : a)).join(' ')}`);
    const p = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], ...opts });
    const tail = [];
    const onData = (d) => {
      logStream.write(d);
      const s = d.toString();
      tail.push(s);
      if (tail.length > 200) tail.shift();
    };
    p.stdout.on('data', onData);
    p.stderr.on('data', onData);
    p.on('error', (err) => resolve({ code: -1, tail: String(err) }));
    p.on('close', (code) => resolve({ code, tail: tail.join('').slice(-4000) }));
  });
}
async function must(cmd, args, opts) {
  const r = await sh(cmd, args, opts);
  if (r.code !== 0) throw new Error(`${cmd} exited ${r.code}: ${r.tail.slice(-800)}`);
  return r;
}

// Open fonts the kits' font stacks name after their Windows-only first choices (Segoe UI -> Inter,
// Consolas/Cascadia -> Cascadia Code, Segoe UI Emoji -> Noto Color Emoji). Proprietary Windows fonts are never shipped.
const GF = 'https://raw.githubusercontent.com/google/fonts/main/ofl';
const FONTS = {
  'Inter[opsz,wght].ttf': `${GF}/inter/Inter%5Bopsz,wght%5D.ttf`,
  'Inter-Italic[opsz,wght].ttf': `${GF}/inter/Inter-Italic%5Bopsz,wght%5D.ttf`,
  'CascadiaCode[wght].ttf': `${GF}/cascadiacode/CascadiaCode%5Bwght%5D.ttf`,
  'NotoColorEmoji-Regular.ttf': `${GF}/notocoloremoji/NotoColorEmoji-Regular.ttf`,
};

/** Install runtime fonts and any job fonts (--fonts) into fontconfig before the command runs. */
async function installFonts() {
  const dest = '/usr/local/share/fonts/cloud-render';
  let n = 0;
  for (const dir of [path.join(RT, 'fonts'), path.join(JOB, 'fonts')]) {
    if (!fs.existsSync(dir)) continue;
    fs.mkdirSync(dest, { recursive: true });
    for (const f of fs.readdirSync(dir, { recursive: true })) {
      if (!/\.(ttf|otf|ttc|woff2?)$/i.test(f)) continue;
      fs.copyFileSync(path.join(dir, f), path.join(dest, path.basename(f)));
      n++;
    }
  }
  if (n) await sh('fc-cache', ['-f', dest]);
  log(`fonts installed: ${n}`);
}

async function placeInputs(inputs) {
  // Each unique blob downloads once; every container path that needs it gets a hard link (or a copy across devices).
  const unique = [...new Set(inputs.map((i) => i.blob))];
  const cacheDir = path.join(JOB, '.cas');
  fs.mkdirSync(cacheDir, { recursive: true });
  let bytes = 0;
  await pool(unique, 16, async (name) => {
    bytes += await blob.getFile(name, path.join(cacheDir, name.replace(/[^\w.-]/g, '_')));
  });
  for (const { blob: name, path: dest } of inputs) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const src = path.join(cacheDir, name.replace(/[^\w.-]/g, '_'));
    fs.rmSync(dest, { force: true });
    try {
      fs.linkSync(src, dest);
    } catch {
      fs.copyFileSync(src, dest);
    }
  }
  return { files: inputs.length, unique: unique.length, bytes };
}

async function installRuntime() {
  const current = JSON.parse((await blob.getText('runtime/current.json')) || 'null');
  if (!current) throw new Error('no runtime/current.json: run `cloud-render.mjs bootstrap` first');
  const tgz = '/tmp/runtime.tgz';
  await blob.getFile(current.blob, tgz);
  fs.mkdirSync(RT, { recursive: true });
  await must('tar', ['-xzf', tgz, '-C', RT]);
  fs.rmSync(tgz, { force: true });
  return current;
}

async function bootstrap(manifest) {
  // Build the runtime tarball: kit node_modules (Linux binaries) + Remotion's headless Chrome + static FFmpeg.
  const kit = path.join(RT, 'kit');
  const env = { ...process.env, PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: '1', npm_config_cache: '/tmp/npm-cache', CI: '1' };
  await must('npm', ['ci', '--omit=dev', '--no-audit', '--no-fund', '--loglevel=error'], { cwd: kit, env });
  await must('node', ['node_modules/@remotion/cli/remotion-cli.js', 'browser', 'ensure'], { cwd: kit, env });
  const ffDir = path.join(RT, 'ffmpeg');
  fs.mkdirSync(ffDir, { recursive: true });
  const url = manifest.ffmpegUrl || (await ffmpegUrl());
  log(`ffmpeg: ${url}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`ffmpeg download: HTTP ${res.status}`);
  fs.writeFileSync('/tmp/ffmpeg.tar.xz', Buffer.from(await res.arrayBuffer()));
  if ((await sh('sh', ['-c', 'command -v xz'])).code !== 0) {
    await must('sh', ['-c', 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xz-utils']);
  }
  await must('tar', ['-xJf', '/tmp/ffmpeg.tar.xz', '-C', ffDir, '--strip-components=1']);
  fs.rmSync('/tmp/ffmpeg.tar.xz', { force: true });
  const ver = await must(path.join(ffDir, 'bin', 'ffmpeg'), ['-hide_banner', '-version']);
  await must('sh', ['-c', `${ffDir}/bin/ffmpeg -hide_banner -filters | grep -q loudnorm && ${ffDir}/bin/ffmpeg -hide_banner -encoders | grep -q libx264`]);
  const fontDir = path.join(RT, 'fonts');
  fs.mkdirSync(fontDir, { recursive: true });
  for (const [file, url] of Object.entries(FONTS)) {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`font ${file}: HTTP ${r.status}`);
    fs.writeFileSync(path.join(fontDir, file), Buffer.from(await r.arrayBuffer()));
  }
  log(`fonts: ${Object.keys(FONTS).join(', ')}`);
  const tgz = '/tmp/runtime.tgz';
  await must('tar', ['-czf', tgz, '-C', RT, '.']);
  const kitLockSha = lockFingerprint(fs.readFileSync(path.join(kit, 'package-lock.json'), 'utf8'));
  const name = `runtime/runtime-${kitLockSha.slice(0, 16)}-${Date.now()}.tgz`;
  const size = await blob.putFile(name, tgz);
  const current = { blob: name, bytes: size, kitLockSha, node: process.version, ffmpeg: ver.tail.split('\n')[0], builtAt: new Date().toISOString(), job: JOB_ID };
  await blob.putText('runtime/current.json', JSON.stringify(current, null, 2));
  log(`runtime published: ${name} (${(size / 1e6).toFixed(0)} MB)`);
  return { runtime: current };
}

async function render(manifest) {
  const t = {};
  let s = Date.now();
  const runtime = await installRuntime();
  t.runtimeSeconds = (Date.now() - s) / 1000;
  s = Date.now();
  const placed = await placeInputs(manifest.inputs);
  t.inputSeconds = (Date.now() - s) / 1000;
  log(`inputs: ${placed.files} paths, ${placed.unique} blobs, ${(placed.bytes / 1e6).toFixed(1)} MB in ${t.inputSeconds}s`);
  for (const o of manifest.outputs) fs.mkdirSync(path.dirname(o.path), { recursive: true });
  await installFonts();
  const env ={ ...process.env, PATH: `${RT}/ffmpeg/bin:${RT}/kit/node_modules/.bin:${process.env.PATH}`, ...(manifest.env || {}) };
  s = Date.now();
  const r = await sh(manifest.cmd, manifest.args, { cwd: manifest.cwd || JOB, env });
  t.runSeconds = (Date.now() - s) / 1000;
  log(`command exited ${r.code} after ${t.runSeconds}s`);
  s = Date.now();
  const outputs = [];
  for (const o of manifest.outputs) {
    if (!fs.existsSync(o.path)) {
      outputs.push({ ...o, missing: true });
      continue;
    }
    outputs.push({ ...o, bytes: await blob.putFile(o.blob, o.path) });
  }
  t.outputSeconds = (Date.now() - s) / 1000;
  const ok = r.code === 0 && outputs.every((o) => !o.missing);
  return { ok, exitCode: r.code, error: ok ? undefined : r.tail.slice(-1500) || 'output missing', outputs, timings: t, runtime: runtime.blob };
}

const started = Date.now();
let result;
const ticker = setInterval(() => flushLog(), 20000);
try {
  if (!JOB_ID || !STORAGE_ACCOUNT) throw new Error('JOB_ID and STORAGE_ACCOUNT must be set');
  const manifest = JSON.parse((await blob.getText(`${prefix}/job.json`)) || 'null');
  if (!manifest) throw new Error(`missing ${prefix}/job.json`);
  log(`job ${JOB_ID} mode=${manifest.mode} cpus=${os.cpus().length} mem=${(os.totalmem() / 2 ** 30).toFixed(1)}GiB node=${process.version}`);
  if (manifest.mode === 'bootstrap') {
    const placed = await placeInputs(manifest.inputs);
    log(`kit files placed: ${placed.files}`);
    result = { ok: true, ...(await bootstrap(manifest)) };
  } else {
    result = await render(manifest);
  }
} catch (err) {
  log(`ERROR ${err.stack || err}`);
  result = { ok: false, error: String(err.message || err) };
}
clearInterval(ticker);
result.totalSeconds = (Date.now() - started) / 1000;
result.finishedAt = new Date().toISOString();
log(`done ok=${result.ok} total=${result.totalSeconds}s`);
await flushLog();
await blob.putText(`${prefix}/result.json`, JSON.stringify(result, null, 2)).catch((e) => console.error('result upload failed', e));
process.exit(result.ok ? 0 : 1);
