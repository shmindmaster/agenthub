#!/usr/bin/env node
// cloud-render: upload -> render in Azure -> download. One shared path for every film session.
//
//   node cloud-render.mjs ffmpeg [opts] -- <ffmpeg args...>            last arg is the local output file
//   node cloud-render.mjs remotion [opts] --comp <id> --out <mp4> [--props <json>] [--public-dir <dir>] [--chunks N] [-- <remotion flags>]
//   node cloud-render.mjs recast [opts] --raw <rawDir> --out <file.webm> [--recast-opts <json>]
//   node cloud-render.mjs exec [opts] --out <file> [--out <file>...] -- <cmd> <args...>
//   node cloud-render.mjs bootstrap | doctor | status <jobId> | logs <jobId>
//
// opts: --name <label> --cpu <n> --memory <Gi> --kit <dir> --fonts <dir> --dry-run --config <file>
// Local files named in the arguments (and the files an ffmpeg concat list names) are uploaded content-addressed,
// so a card or WAV already in the cloud is not uploaded again. See README.md beside this file.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { blobClient, lockFingerprint, pool } from './blob.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG = path.join(process.env.LOCALAPPDATA || os.homedir(), 'AgentHub', 'media-studio', 'cloud-render.json');
const DEFAULT_KIT = path.resolve(HERE, '..');
const ARM = 'https://management.azure.com';
const ARM_API = '2024-03-01';
// Kit files overlaid on the runtime's kit for remotion/recast jobs (node_modules come from the runtime tarball).
const KIT_OVERLAY = ['src', 'screencast', 'cloud', 'remotion.config.ts', 'tsconfig.json', 'scene-archetypes.json', 'package.json'];

// ---------- argument parsing ----------
export function parseArgs(argv) {
  const sub = argv[0];
  const opts = { out: [] };
  const rest = [];
  let i = 1;
  for (; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--') {
      rest.push(...argv.slice(i + 1));
      break;
    }
    const m = a.match(/^--([\w-]+)(?:=(.*))?$/);
    if (!m) {
      rest.push(a);
      continue;
    }
    const key = m[1];
    const flag = ['dry-run', 'keep', 'json'].includes(key);
    const val = flag ? true : m[2] ?? argv[++i];
    if (key === 'out') opts.out.push(val);
    else opts[key.replace(/-(\w)/g, (_, c) => c.toUpperCase())] = val;
  }
  return { sub, opts, rest };
}

// ---------- path planning (pure; unit-tested) ----------
const looksLikePath = (v) => typeof v === 'string' && v.length > 0 && !v.startsWith('-') && (/[\\/]/.test(v) || /\.[A-Za-z0-9]{1,5}$/.test(v));

/** ffmpeg concat demuxer: parse `file '...'` lines. Returns null when the text is not a concat list. */
export function parseConcatList(text) {
  const lines = text.split(/\r?\n/);
  let files = 0;
  const parsed = lines.map((line) => {
    const m = line.match(/^(\s*file\s+)(.+?)\s*$/);
    if (!m) return { line };
    files++;
    let v = m[2];
    if (v.startsWith("'")) v = v.replace(/'\\''/g, '\u0000').replace(/^'|'$/g, '').replace(/\u0000/g, "'");
    else v = v.replace(/\\(.)/g, '$1');
    return { line, lead: m[1], file: v };
  });
  const directives = lines.every((l) => !l.trim() || /^\s*(ffconcat|file|duration|inpoint|outpoint|option|stream|exact_stream_id|file_packet_meta(data)?|#)/.test(l));
  return files > 0 && directives ? parsed : null;
}
const quoteConcat = (p) => `'${p.replace(/'/g, "'\\''")}'`;

/**
 * Map local paths in a command line onto container paths.
 * ctx: { cwd, outputs: Map<localAbs, containerPath>, addFile(localAbs) -> containerPath, addDir(localAbs) -> containerPath,
 *        addConcat(localAbs) -> containerPath }
 */
export function mapArgs(args, ctx) {
  // A bare word is mapped only when it looks like a path; a --flag=value names a path explicitly, so it maps whenever it exists.
  const mapValue = (v, explicit = false) => {
    if (!(explicit ? v && !v.startsWith('-') : looksLikePath(v))) return v;
    const abs = path.resolve(ctx.cwd, v);
    if (ctx.outputs.has(abs)) return ctx.outputs.get(abs);
    if (!fs.existsSync(abs)) return v;
    const st = fs.statSync(abs);
    if (st.isDirectory()) return ctx.addDir(abs);
    if (/\.(txt|ffconcat|list)$/i.test(abs) && st.size < 8 * 1024 * 1024) {
      const mapped = ctx.addConcat(abs);
      if (mapped) return mapped;
    }
    return ctx.addFile(abs);
  };
  return args.map((a) => {
    const kv = a.match(/^(--?[\w-]+=)(.+)$/);
    return kv ? kv[1] + mapValue(kv[2], true) : mapValue(a);
  });
}

// ---------- local helpers ----------
function azExe() {
  return process.platform === 'win32' ? 'az.cmd' : 'az';
}
function az(args) {
  const r = spawnSync(azExe(), args, { encoding: 'utf8', windowsHide: true, shell: process.platform === 'win32', maxBuffer: 16 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`az ${args.slice(0, 3).join(' ')} failed: ${(r.stderr || '').trim().split('\n').slice(-3).join(' | ')}`);
  return r.stdout;
}
const tokens = new Map();
function tokenFor(resource, sub) {
  return async () => {
    const t = tokens.get(resource);
    if (t && t.expires - 300 > Date.now() / 1000) return t.value;
    const j = JSON.parse(az(['account', 'get-access-token', '--resource', resource, '--subscription', sub, '--query', '{t:accessToken,e:expires_on}', '-o', 'json']));
    tokens.set(resource, { value: j.t, expires: Number(j.e) });
    return j.t;
  };
}
async function sha256File(file) {
  const h = createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) h.update(chunk);
  return h.digest('hex');
}
function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === 'node_modules' || e.name === '.git') continue;
      out.push(...walk(p));
    } else if (e.isFile()) out.push(p);
  }
  return out;
}
const fmtMB = (b) => `${(b / 1e6).toFixed(1)} MB`;
const slug = (s) => String(s || 'job').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'job';

function loadConfig(file) {
  if (!fs.existsSync(file)) throw new Error(`no config at ${file}: run Provision-CloudRender.ps1 first (see README.md)`);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

// ---------- job building ----------
class JobPlan {
  constructor(cwd) {
    this.cwd = cwd;
    this.outputs = new Map(); // localAbs -> container path
    this.files = new Map(); // localAbs -> container path
    this.generated = []; // { local temp file, container path }
    this.dirCount = 0;
    this.tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cloud-render-'));
  }
  addOutput(local) {
    const abs = path.resolve(this.cwd, local);
    const cpath = `/job/out/${path.basename(abs)}`;
    this.outputs.set(abs, cpath);
    return cpath;
  }
  addFile(abs, cpath) {
    if (!this.files.has(abs)) {
      const short = createHash('sha1').update(abs).digest('hex').slice(0, 12);
      this.files.set(abs, cpath || `/job/in/${short}/${path.basename(abs)}`);
    }
    return this.files.get(abs);
  }
  addDir(abs, cpath) {
    const root = cpath || `/job/in/d${this.dirCount++}/${path.basename(abs)}`;
    for (const f of walk(abs)) this.addFile(f, `${root}/${path.relative(abs, f).split(path.sep).join('/')}`);
    return root;
  }
  addConcat(abs) {
    const parsed = parseConcatList(fs.readFileSync(abs, 'utf8'));
    if (!parsed) return null;
    const base = path.dirname(abs);
    const text = parsed
      .map((p) => {
        if (!p.file) return p.line;
        const target = path.resolve(base, p.file);
        if (!fs.existsSync(target)) throw new Error(`concat list ${abs} names a missing file: ${p.file}`);
        return `${p.lead}${quoteConcat(this.addFile(target))}`;
      })
      .join('\n');
    const local = path.join(this.tmp, `concat-${this.generated.length}-${path.basename(abs)}`);
    fs.writeFileSync(local, text);
    const cpath = `/job/in/concat/${this.generated.length}-${path.basename(abs)}`;
    this.generated.push({ local, cpath });
    return cpath;
  }
  ctx() {
    return { cwd: this.cwd, outputs: this.outputs, addFile: (a) => this.addFile(a), addDir: (a) => this.addDir(a), addConcat: (a) => this.addConcat(a) };
  }
  addKitOverlay(kitDir) {
    for (const rel of KIT_OVERLAY) {
      const abs = path.join(kitDir, rel);
      if (!fs.existsSync(abs)) continue;
      if (fs.statSync(abs).isDirectory()) this.addDir(abs, `/opt/rt/kit/${rel}`);
      else this.addFile(abs, `/opt/rt/kit/${rel}`);
    }
  }
  allLocalFiles() {
    return [...[...this.files].map(([local, cpath]) => ({ local, cpath })), ...this.generated];
  }
}

function buildCommand(sub, opts, rest, plan) {
  const ctx = plan.ctx();
  if (sub === 'ffmpeg') {
    if (!rest.length) throw new Error('ffmpeg: pass ffmpeg arguments after --');
    const outLocal = rest[rest.length - 1];
    plan.addOutput(outLocal);
    for (const o of opts.out) plan.addOutput(o);
    const args = mapArgs(rest, ctx);
    if (!args.includes('-y')) args.unshift('-y');
    return { cmd: 'ffmpeg', args, cwd: '/job' };
  }
  if (sub === 'remotion') {
    if (!opts.comp || !opts.out.length) throw new Error('remotion: --comp and --out are required');
    plan.addKitOverlay(opts.kit || DEFAULT_KIT);
    const out = plan.addOutput(opts.out[0]);
    const extra = [];
    if (opts.props) extra.push(`--props=${mapArgs([opts.props], ctx)[0]}`);
    if (opts.publicDir) extra.push(`--public-dir=${mapArgs([path.resolve(opts.publicDir)], ctx)[0]}`);
    const user = mapArgs(rest, ctx);
    if (!user.some((a) => a.startsWith('--concurrency'))) extra.push(`--concurrency=${Math.max(1, Math.floor(Number(opts.cpu || 4)))}`);
    return { cmd: 'node', args: ['node_modules/@remotion/cli/remotion-cli.js', 'render', 'src/index.ts', opts.comp, out, ...extra, ...user], cwd: '/opt/rt/kit' };
  }
  if (sub === 'recast') {
    if (!opts.raw || !opts.out.length) throw new Error('recast: --raw and --out are required');
    plan.addKitOverlay(opts.kit || DEFAULT_KIT);
    const out = plan.addOutput(opts.out[0]);
    const raw = mapArgs([path.resolve(opts.raw)], ctx)[0];
    plan.addFile(path.join(HERE, 'recast-run.mjs'), '/opt/rt/kit/cloud/recast-run.mjs');
    return { cmd: 'node', args: ['cloud/recast-run.mjs', raw, out, ...(opts.recastOpts ? [opts.recastOpts] : [])], cwd: '/opt/rt/kit' };
  }
  if (sub === 'exec') {
    if (!rest.length || !opts.out.length) throw new Error('exec: --out <file> and a command after -- are required');
    for (const o of opts.out) plan.addOutput(o);
    if (opts.kit) plan.addKitOverlay(opts.kit);
    const [cmd, ...args] = rest;
    return { cmd, args: mapArgs(args, ctx), cwd: opts.kit ? '/opt/rt/kit' : '/job' };
  }
  throw new Error(`unknown subcommand: ${sub}`);
}

// ---------- cloud calls ----------
function clients(cfg) {
  const storage = blobClient(cfg.storageAccount, tokenFor('https://storage.azure.com/', cfg.subscriptionId));
  const armToken = tokenFor(`${ARM}/`, cfg.subscriptionId);
  const jobUrl = `${ARM}/subscriptions/${cfg.subscriptionId}/resourceGroups/${cfg.resourceGroup}/providers/Microsoft.App/jobs/${cfg.jobName}`;
  const arm = async (method, url, body) => {
    const res = await fetch(url, { method, headers: { Authorization: `Bearer ${await armToken()}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text();
    if (!res.ok) throw new Error(`ARM ${method} ${url.replace(ARM, '')}: HTTP ${res.status} ${text.slice(0, 400)}`);
    return text ? JSON.parse(text) : {};
  };
  return { storage, arm, jobUrl };
}

async function uploadAll(storage, files) {
  const hashed = await pool(files, 8, async (f) => ({ ...f, sha: await sha256File(f.local), size: fs.statSync(f.local).size }));
  const unique = [...new Map(hashed.map((h) => [h.sha, h])).values()];
  let uploaded = 0;
  let uploadedBytes = 0;
  let done = 0;
  await pool(unique, 16, async (h) => {
    const name = `cas/${h.sha}`;
    if (!(await storage.exists(name))) {
      await storage.putFile(name, h.local);
      uploaded++;
      uploadedBytes += h.size;
    }
    if (++done % 100 === 0) process.stderr.write(`  upload ${done}/${unique.length}\n`);
  });
  const totalBytes = unique.reduce((n, h) => n + h.size, 0);
  return { inputs: hashed.map((h) => ({ blob: `cas/${h.sha}`, path: h.cpath })), unique: unique.length, uploaded, uploadedBytes, totalBytes };
}

async function startExecution(cfg, c, jobId, { cpu, memory }) {
  const job = await c.arm('GET', `${c.jobUrl}?api-version=${ARM_API}`);
  const base = job.properties.template.containers[0];
  const env = (base.env || []).filter((e) => e.name !== 'JOB_ID').concat([{ name: 'JOB_ID', value: jobId }]);
  const container = { ...base, env, resources: { cpu: Number(cpu || base.resources.cpu), memory: memory ? `${memory}Gi`.replace(/GiGi$/, 'Gi') : base.resources.memory } };
  const res = await c.arm('POST', `${c.jobUrl}/start?api-version=${ARM_API}`, { containers: [container] });
  return { name: res.name || res.id?.split('/').pop(), resources: container.resources };
}

async function waitForResult(cfg, c, jobId, execName) {
  const t0 = Date.now();
  let lastStatus = '';
  let exec = null;
  for (;;) {
    const text = await c.storage.getText(`jobs/${jobId}/result.json`);
    if (text) {
      const result = JSON.parse(text);
      // Give ARM a moment to record the execution end time for the cost estimate.
      for (let i = 0; i < 6 && execName; i++) {
        exec = await c.arm('GET', `${c.jobUrl}/executions/${execName}?api-version=${ARM_API}`).catch(() => exec);
        if (exec?.properties?.endTime) break;
        await new Promise((r) => setTimeout(r, 5000));
      }
      return { result, exec };
    }
    if (execName && (Date.now() - t0 > 20000 || !lastStatus)) {
      exec = await c.arm('GET', `${c.jobUrl}/executions/${execName}?api-version=${ARM_API}`).catch(() => null);
      const status = exec?.properties?.status || '?';
      if (status !== lastStatus) {
        process.stderr.write(`  execution ${execName}: ${status} (${Math.round((Date.now() - t0) / 1000)}s)\n`);
        lastStatus = status;
      }
      if (status === 'Failed' || status === 'Stopped') {
        await new Promise((r) => setTimeout(r, 10000));
        const late = await c.storage.getText(`jobs/${jobId}/result.json`);
        if (late) return { result: JSON.parse(late), exec };
        return { result: { ok: false, error: `execution ${status} without a result (container failed to start or crashed); see logs` }, exec };
      }
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
}

function costOf(cfg, exec, resources) {
  const p = exec?.properties;
  if (!p?.startTime || !p?.endTime) return null;
  const seconds = (new Date(p.endTime) - new Date(p.startTime)) / 1000;
  const cpu = Number(resources.cpu);
  const mem = parseFloat(resources.memory);
  const rate = cfg.pricing || { vcpuSecond: 0.000024, gibSecond: 0.000003 };
  const usd = seconds * (cpu * rate.vcpuSecond + mem * rate.gibSecond);
  return { billedSeconds: seconds, usd, perMinute: 60 * (cpu * rate.vcpuSecond + mem * rate.gibSecond) };
}

/**
 * remotion --chunks N: one upload, N parallel executions each rendering a frame range (cloud/chunk-render.mjs reads the
 * length through the Remotion CLI), then a local stream-copy concat. Render picture muted and mux audio separately:
 * per-chunk AAC does not join gaplessly.
 */
async function runChunked(opts, rest, cfg) {
  const count = Math.floor(Number(opts.chunks));
  if (!(count >= 2 && count <= 16)) throw new Error('--chunks must be 2-16');
  const tStart = Date.now();
  const plan = new JobPlan(process.cwd());
  const command = buildCommand('remotion', opts, rest, plan);
  if (opts.fonts) plan.addDir(path.resolve(opts.fonts), '/job/fonts');
  if (!command.args.some((a) => a === '--muted')) process.stderr.write('  warning: chunked renders should be --muted; per-chunk audio does not join gaplessly\n');
  // The wrapper ships from beside this CLI: a custom --kit has no cloud/ folder of its own.
  plan.addFile(path.join(HERE, 'chunk-render.mjs'), '/opt/rt/kit/cloud/chunk-render.mjs');
  const outLocal = path.resolve(opts.out[0]);
  const [cli, , entry, comp, , ...flags] = command.args;
  const base = `${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)}-${slug(opts.name || 'remotion')}-${randomBytes(2).toString('hex')}`;
  const c = clients(cfg);
  const files = plan.allLocalFiles();
  process.stderr.write(`cloud-render ${base}: ${count} chunks, ${files.length} input files\n`);
  const up = await uploadAll(c.storage, files);
  const tUploaded = Date.now();
  process.stderr.write(`  uploaded ${up.uploaded}/${up.unique} new blobs (${fmtMB(up.uploadedBytes)}) in ${((tUploaded - tStart) / 1000).toFixed(1)}s\n`);
  if (cli !== 'node_modules/@remotion/cli/remotion-cli.js' || entry !== 'src/index.ts') throw new Error('unexpected remotion command shape');
  const chunks = await Promise.all(Array.from({ length: count }, async (_, k) => {
    const jobId = `${base}-c${String(k + 1).padStart(2, '0')}`;
    const file = `/job/out/chunk-${String(k).padStart(2, '0')}.mp4`;
    const outputs = [file, `${file}.range.json`].map((p) => ({ path: p, blob: `jobs/${jobId}/out/${path.basename(p)}` }));
    const manifest = { mode: 'render', jobId, cmd: 'node', args: ['cloud/chunk-render.mjs', String(k), String(count), comp, file, ...flags], cwd: '/opt/rt/kit', inputs: up.inputs, outputs, createdAt: new Date().toISOString(), host: os.hostname() };
    await c.storage.putText(`jobs/${jobId}/job.json`, JSON.stringify(manifest, null, 2));
    const exec = await startExecution(cfg, c, jobId, { cpu: opts.cpu, memory: opts.memory });
    process.stderr.write(`  chunk ${k + 1}/${count}: ${jobId} on ${exec.name}\n`);
    const { result, exec: execInfo } = await waitForResult(cfg, c, jobId, exec.name);
    return { k, jobId, outputs, result, cost: costOf(cfg, execInfo, exec.resources) };
  }));
  const tDone = Date.now();
  const failed = chunks.filter((ch) => !ch.result.ok);
  const tmp = fs.mkdtempSync(path.join(path.dirname(outLocal), '.cloud-render-chunks-'));
  for (const ch of chunks) {
    const log = await c.storage.getText(`jobs/${ch.jobId}/log.txt`);
    if (log) fs.writeFileSync(path.join(tmp, `chunk-${ch.k}.log`), log);
  }
  if (failed.length) throw new Error(`chunks failed: ${failed.map((ch) => `${ch.k + 1} (${ch.jobId}): ${String(ch.result.error).slice(-300)}`).join(' | ')}; logs in ${tmp}`);
  const ranges = [];
  for (const ch of chunks) {
    ch.local = path.join(tmp, path.basename(ch.outputs[0].path));
    await c.storage.getFile(ch.outputs[0].blob, ch.local);
    ranges.push(JSON.parse((await c.storage.getText(ch.outputs[1].blob)) || 'null'));
  }
  const expected = ranges.reduce((n, r) => n + (r.last - r.first + 1), 0);
  const list = path.join(tmp, 'concat.txt');
  fs.writeFileSync(list, chunks.map((ch) => `file '${ch.local.replace(/\\/g, '/').replace(/'/g, "'\\''")}'`).join('\n'));
  const ff = spawnSync('ffmpeg', ['-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', '-movflags', '+faststart', outLocal], { encoding: 'utf8', windowsHide: true });
  if (ff.status !== 0) throw new Error(`concat failed: ${ff.stderr || ff.error}`);
  const probe = spawnSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-count_packets', '-show_entries', 'stream=nb_read_packets', '-of', 'csv=p=0', outLocal], { encoding: 'utf8', windowsHide: true });
  const frames = parseInt(String(probe.stdout), 10); // csv output can carry a trailing comma
  const tJoined = Date.now();
  const usd = chunks.reduce((s, ch) => s + (ch.cost?.usd || 0), 0);
  const summary = {
    base, ok: frames === expected, error: frames === expected ? undefined : `joined ${frames} frames, expected ${expected}`,
    outputs: [outLocal], frames, expectedFrames: expected, total: ranges[0]?.total, chunks: chunks.map((ch, i) => ({ jobId: ch.jobId, range: ranges[i], runSeconds: ch.result.timings?.runSeconds, cost: ch.cost })),
    wallSeconds: { total: (tJoined - tStart) / 1000, upload: (tUploaded - tStart) / 1000, cloud: (tDone - tUploaded) / 1000, downloadAndJoin: (tJoined - tDone) / 1000 },
    cost: { usd: +usd.toFixed(4) }, logs: tmp,
  };
  fs.writeFileSync(`${outLocal}.cloud-render.json`, JSON.stringify(summary, null, 2));
  for (const ch of chunks) fs.rmSync(ch.local, { force: true });
  console.log(JSON.stringify(summary, null, 2));
  return summary.ok ? 0 : 1;
}

async function runJob(sub, opts, rest, cfg) {
  if (sub === 'remotion' && Number(opts.chunks) > 1 && !opts.dryRun) return runChunked(opts, rest, cfg);
  const tStart = Date.now();
  const plan = new JobPlan(process.cwd());
  const command = buildCommand(sub, opts, rest, plan);
  if (opts.fonts) plan.addDir(path.resolve(opts.fonts), '/job/fonts');
  const jobId = `${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)}-${slug(opts.name || sub)}-${randomBytes(2).toString('hex')}`;
  const files = plan.allLocalFiles();
  const outputs = [...plan.outputs].map(([local, cpath]) => ({ local, path: cpath, blob: `jobs/${jobId}/out/${path.basename(cpath)}` }));
  if (opts.dryRun) {
    console.log(JSON.stringify({ jobId, command, inputs: files.map((f) => ({ local: f.local, path: f.cpath })), outputs }, null, 2));
    return 0;
  }
  const c = clients(cfg);
  process.stderr.write(`cloud-render ${jobId}: ${files.length} input files\n`);
  const up = await uploadAll(c.storage, files);
  const tUploaded = Date.now();
  process.stderr.write(`  uploaded ${up.uploaded}/${up.unique} new blobs (${fmtMB(up.uploadedBytes)} of ${fmtMB(up.totalBytes)}) in ${((tUploaded - tStart) / 1000).toFixed(1)}s\n`);
  const manifest = { mode: 'render', jobId, ...command, inputs: up.inputs, outputs: outputs.map(({ path: p, blob }) => ({ path: p, blob })), createdAt: new Date().toISOString(), host: os.hostname() };
  await c.storage.putText(`jobs/${jobId}/job.json`, JSON.stringify(manifest, null, 2));
  const exec = await startExecution(cfg, c, jobId, { cpu: opts.cpu, memory: opts.memory });
  process.stderr.write(`  started ${exec.name} (${exec.resources.cpu} vCPU, ${exec.resources.memory})\n`);
  const { result, exec: execInfo } = await waitForResult(cfg, c, jobId, exec.name);
  const tDone = Date.now();
  for (const o of outputs) {
    const r = (result.outputs || []).find((x) => x.blob === o.blob);
    if (r && !r.missing) {
      fs.mkdirSync(path.dirname(o.local), { recursive: true });
      await c.storage.getFile(o.blob, o.local);
    }
  }
  const tDownloaded = Date.now();
  const logLocal = outputs.length ? `${outputs[0].local}.cloud-render.log` : path.join(plan.tmp, 'log.txt');
  const logText = await c.storage.getText(`jobs/${jobId}/log.txt`);
  if (logText) fs.writeFileSync(logLocal, logText);
  const cost = costOf(cfg, execInfo, exec.resources);
  const summary = {
    jobId,
    ok: result.ok,
    error: result.error,
    outputs: outputs.map((o) => o.local),
    log: logLocal,
    wallSeconds: { total: (tDownloaded - tStart) / 1000, upload: (tUploaded - tStart) / 1000, cloud: (tDone - tUploaded) / 1000, download: (tDownloaded - tDone) / 1000 },
    worker: result.timings,
    workerTotalSeconds: result.totalSeconds,
    upload: { files: files.length, uniqueBlobs: up.unique, newBlobs: up.uploaded, newBytes: up.uploadedBytes },
    cost,
  };
  fs.writeFileSync(path.join(plan.tmp, 'summary.json'), JSON.stringify(summary, null, 2));
  if (outputs.length) fs.writeFileSync(`${outputs[0].local}.cloud-render.json`, JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  if (!opts.keep) fs.rmSync(plan.tmp, { recursive: true, force: true });
  return result.ok ? 0 : 1;
}

async function bootstrap(opts, cfg) {
  const kit = opts.kit || DEFAULT_KIT;
  const c = clients(cfg);
  const jobId = `${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)}-bootstrap-${randomBytes(2).toString('hex')}`;
  // The loader fetches these two from runtime/ before anything else.
  await c.storage.putFile('runtime/worker.mjs', path.join(HERE, 'worker.mjs'));
  await c.storage.putFile('runtime/blob.mjs', path.join(HERE, 'blob.mjs'));
  const plan = new JobPlan(kit);
  for (const rel of [...KIT_OVERLAY, 'package-lock.json']) {
    const abs = path.join(kit, rel);
    if (!fs.existsSync(abs)) continue;
    if (fs.statSync(abs).isDirectory()) plan.addDir(abs, `/opt/rt/kit/${rel}`);
    else plan.addFile(abs, `/opt/rt/kit/${rel}`);
  }
  const up = await uploadAll(c.storage, plan.allLocalFiles());
  await c.storage.putText(`jobs/${jobId}/job.json`, JSON.stringify({ mode: 'bootstrap', jobId, inputs: up.inputs, createdAt: new Date().toISOString() }, null, 2));
  const exec = await startExecution(cfg, c, jobId, {});
  process.stderr.write(`bootstrap ${jobId}: started ${exec.name}\n`);
  const { result, exec: execInfo } = await waitForResult(cfg, c, jobId, exec.name);
  console.log(JSON.stringify({ jobId, ...result, cost: costOf(cfg, execInfo, exec.resources) }, null, 2));
  if (!result.ok) console.error((await c.storage.getText(`jobs/${jobId}/log.txt`))?.slice(-3000));
  return result.ok ? 0 : 1;
}

async function syncWorker(cfg) {
  // Worker code changes ship without a runtime rebuild.
  const c = clients(cfg);
  await c.storage.putFile('runtime/worker.mjs', path.join(HERE, 'worker.mjs'));
  await c.storage.putFile('runtime/blob.mjs', path.join(HERE, 'blob.mjs'));
  console.log('runtime/worker.mjs and runtime/blob.mjs updated');
  return 0;
}

async function doctor(cfg, opts) {
  const c = clients(cfg);
  const current = JSON.parse((await c.storage.getText('runtime/current.json')) || 'null');
  const job = await c.arm('GET', `${c.jobUrl}?api-version=${ARM_API}`);
  const kit = opts.kit || DEFAULT_KIT;
  const lock = path.join(kit, 'package-lock.json');
  const localLock = fs.existsSync(lock) ? lockFingerprint(fs.readFileSync(lock, 'utf8')) : null;
  console.log(JSON.stringify({
    config: { subscriptionId: cfg.subscriptionId, resourceGroup: cfg.resourceGroup, storageAccount: cfg.storageAccount, jobName: cfg.jobName, location: cfg.location },
    job: { provisioningState: job.properties.provisioningState, image: job.properties.template.containers[0].image, resources: job.properties.template.containers[0].resources, triggerType: job.properties.configuration.triggerType },
    runtime: current,
    kitLockMatchesRuntime: current && localLock ? current.kitLockSha === localLock : null,
    pricing: cfg.pricing,
  }, null, 2));
  return 0;
}

async function main() {
  const { sub, opts, rest } = parseArgs(process.argv.slice(2));
  if (!sub || sub === 'help' || sub === '--help') {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 12).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
    return 0;
  }
  const cfg = opts.dryRun ? {} : loadConfig(opts.config || DEFAULT_CONFIG);
  if (sub === 'bootstrap') return bootstrap(opts, cfg);
  if (sub === 'sync-worker') return syncWorker(cfg);
  if (sub === 'doctor') return doctor(cfg, opts);
  if (sub === 'fetch') {
    // Recover a finished job's output when the waiting CLI was interrupted (the cloud job keeps running).
    if (!rest[0] || !opts.out.length) throw new Error('fetch: cloud-render.mjs fetch <jobId> --out <local file> [--out ...]');
    const c = clients(cfg);
    const result = JSON.parse((await c.storage.getText(`jobs/${rest[0]}/result.json`)) || 'null');
    if (!result) throw new Error(`job ${rest[0]} has no result yet`);
    if (!result.ok) throw new Error(`job ${rest[0]} failed: ${String(result.error).slice(-400)}`);
    for (const local of opts.out) {
      const abs = path.resolve(local);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      await c.storage.getFile(`jobs/${rest[0]}/out/${path.basename(abs)}`, abs);
      console.log(`fetched ${abs}`);
    }
    return 0;
  }
  if (sub === 'logs' || sub === 'status') {
    const c = clients(cfg);
    const name = sub === 'logs' ? 'log.txt' : 'result.json';
    console.log((await c.storage.getText(`jobs/${rest[0]}/${name}`)) ?? `no ${name} yet for ${rest[0]}`);
    return 0;
  }
  return runJob(sub, opts, rest, cfg);
}

// realpath on both sides: the deployed briefing-kit is a junction, so argv[1] and import.meta.url can name different paths.
const realpath = (p) => {
  try {
    return fs.realpathSync.native(p).toLowerCase();
  } catch {
    return path.resolve(p).toLowerCase();
  }
};
if (process.argv[1] && realpath(process.argv[1]) === realpath(fileURLToPath(import.meta.url))) {
  main().then(
    (code) => process.exit(code),
    (err) => {
      console.error(`cloud-render: ${err.message}`);
      process.exit(1);
    },
  );
}
