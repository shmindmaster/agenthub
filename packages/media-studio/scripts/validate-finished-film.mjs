#!/usr/bin/env node
// Finished-film gate on the ENCODED candidate: the defects a viewer meets in the first and last seconds and in the
// gaps, which no sync, integrity or dead-screen gate measures. ffmpeg/ffprobe only; no OCR, no ML.
// Usage: node validate-finished-film.mjs <candidate> [--out qa/finished-film.json] [--requirements story/requirements.json]
//        [--deliverable narrated-video|silent-video|audio] [--reviewed-silence 12.5-20[:reason]]...
//
// Hard errors (objective): opening-blank (black or single-colour first frame >= 0.2 s), blank-span (near-uniform span
// > 0.5 s anywhere except a fade at the very end <= 1 s), silence (mid-film audio silence >= 5 s, unless reviewed),
// trailing-silence (> 6 s, or > finalHoldSeconds + 3 s when declared), final-hold-unmet / final-hold-blank / final-hold-fading (the
// declared final hold is not a stable, visible picture), no-audio, no-video, aspect-mismatch, duration-mismatch, deliverable-mismatch.
// Advisories (a human looks; never block): opening-static, ending-unsettled, silence-review (3-5 s), low-detail
// (possible loading or empty page), blurred-fill (vertical cut made from a 16:9 master).
// Edge clipping, UI text size, spinners and language are not measured here: see skills/finish/references/gates.md.
//
// Cost: one reduced-scale decode of the film at SAMPLE_FPS, one audio pass, and two short freezedetect windows (the
// first 3 s and the last seconds). requirements.json is read for finalHoldSeconds, aspect ("16x9"; "16:9" is tolerated),
// durationSeconds and reviewedSilences [{start,end,reason}] (reason required), at its top level or one object down. The
// deliverable comes from --deliverable, else job.json (deliverable, or kind audio-only), else narrated-video; stills and
// storyboard are not applicable (ok:true, notApplicable:true, nothing measured).
import { existsSync, readFileSync, writeFileSync, mkdirSync, statSync, openSync, readSync, closeSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const libPath = [join(scriptDir, 'sync-lib.mjs'), join(scriptDir, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
if (!libPath) { console.error('sync-lib.mjs not found beside this script or in ../kit/screencast'); process.exit(2); }
const { parseFreezes } = await import(pathToFileURL(libPath).href);

const USAGE = 'Usage: node validate-finished-film.mjs <candidate> [--out qa/finished-film.json] [--requirements story/requirements.json] [--deliverable narrated-video|silent-video|audio] [--reviewed-silence a-b[:reason]]...';
const argv = process.argv.slice(2);
const opt = {}; const pos = []; const reviewedArgs = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--reviewed-silence') { if (i + 1 >= argv.length) { console.error(`--reviewed-silence needs one a-b range\n${USAGE}`); process.exit(2); } reviewedArgs.push(argv[++i]); }
  else if (['--out', '--requirements', '--deliverable'].includes(a)) opt[a] = argv[++i];
  else if (a.startsWith('--')) { console.error(`unknown option ${a}\n${USAGE}`); process.exit(2); }
  else pos.push(a);
}
if (pos.length !== 1) { console.error(USAGE); process.exit(2); }
const candidate = resolve(pos[0]);
const outPath = resolve(opt['--out'] || 'qa/finished-film.json');

// thresholds
const T = {
  sampleFps: 8, openingFps: 25, openingWindowSeconds: 3,
  blankStd: 2.0,              // gray std below this is a near-uniform frame (black, white or any single colour)
  blackLuma: 16,
  openingBlankSeconds: 0.2, blankSpanSeconds: 0.5, endFadeSeconds: 1,
  silenceNoiseDb: -40, silenceErrorSeconds: 5, silenceAdvisorySeconds: 3, trailingSilenceSlackSeconds: 3, trailingSilenceUndeclaredSeconds: 6,
  edgeLevel: 16,              // |dx|+|dy| above this counts as an edge pixel at 320x180
  lowDetailEdgeFrac: 0.05, busyEdgeFrac: 0.08, lowDetailSeconds: 0.3,
  freezeNoise: 0.002, freezeMinSeconds: 0.5, stableEndSeconds: 2, openingStaticSeconds: 2.8,
  blurredBandEdgeRatio: 0.4, blurredBandStd: 5, blurredShare: 0.4,
  aspectTolerance: 0.02,
};
const AW = 320, AH = 180;

const errors = []; const advisories = [];
const err = (code, at, message) => errors.push({ code, at: at === null ? null : round(at), message });
const adv = (code, at, message) => advisories.push({ code, at: at === null ? null : round(at), message });
const round = (v, p = 2) => (Number.isFinite(v) ? Math.round(v * 10 ** p) / 10 ** p : v);
const tc = (s) => `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, '0')}`;

const report = {
  schema: 'media-studio/finished-film/1', ok: false, candidate, sha256: null, durationSeconds: null, deliverable: null,
  requirements: null, thresholds: T, errors, advisories,
  opening: null, ending: { stillSeconds: null, trailingSilenceSeconds: null }, silences: [], blankSpans: [],
};
function finish() {
  report.ok = errors.length === 0;
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: report.ok, out: outPath, errors: errors.map((e) => `${e.code}@${e.at}`), advisories: advisories.map((a) => `${a.code}@${a.at}`) }));
  for (const e of errors) console.error(`[finished-film] ERROR ${e.code} at ${e.at ?? '-'}: ${e.message}`);
  for (const a of advisories) console.error(`[finished-film] advisory ${a.code} at ${a.at ?? '-'}: ${a.message}`);
  process.exit(report.ok ? 0 : 1);
}

// ---------------------------------------------------------------- helpers
function sha256File(p) {
  const h = createHash('sha256'); const fd = openSync(p, 'r'); const buf = Buffer.allocUnsafe(1 << 22);
  try { for (let n; (n = readSync(fd, buf, 0, buf.length, null)) > 0;) h.update(buf.subarray(0, n)); } finally { closeSync(fd); }
  return h.digest('hex');
}
let timeoutMs = Number(process.env.FINISHED_FILM_TIMEOUT_MS) || 120000; // widened after the probe: generous, scales with duration
const killAfter = (p, flag) => setTimeout(() => { flag.timedOut = true; p.kill('SIGKILL'); }, timeoutMs);
function exec(cmd, args) {
  return new Promise((res) => {
    const p = spawn(cmd, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    const flag = { timedOut: false }; const timer = killAfter(p, flag);
    let out = '', errText = '';
    p.stdout.on('data', (c) => { out += c; }); p.stderr.on('data', (c) => { errText += c; });
    p.on('error', (e) => { clearTimeout(timer); res({ code: -1, out, err: e.message }); });
    p.on('close', (code) => { clearTimeout(timer); res({ code, out, err: errText, timedOut: flag.timedOut }); });
  });
}
const ffmpegText = (args) => exec('ffmpeg', ['-hide_banner', '-nostdin', '-nostats', ...args]);

/** Decode `inputArgs` to gray rawvideo w x h and call onFrame(frame, index) synchronously (the buffer is reused). */
function decodeGray(inputArgs, vf, w, h, onFrame) {
  return new Promise((res) => {
    const FR = w * h; const frame = Buffer.allocUnsafe(FR); let off = 0, idx = 0;
    const p = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-nostdin', ...inputArgs, '-an', '-vf', `${vf},scale=${w}:${h}:flags=area`, '-pix_fmt', 'gray', '-f', 'rawvideo', '-'], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    const flag = { timedOut: false }; const timer = killAfter(p, flag);
    let errText = '';
    p.stderr.on('data', (c) => { errText += c; });
    p.stdout.on('data', (c) => {
      for (let i = 0; i < c.length;) {
        const n = Math.min(FR - off, c.length - i); c.copy(frame, off, i, i + n); off += n; i += n;
        if (off === FR) { onFrame(frame, idx++); off = 0; }
      }
    });
    p.on('error', (e) => { clearTimeout(timer); res({ frames: idx, error: e.message }); });
    p.on('close', (code) => { clearTimeout(timer); res({ frames: idx, timedOut: flag.timedOut, error: flag.timedOut ? 'timed out' : code === 0 ? null : errText.trim().slice(0, 300) }); });
  });
}
function frameStats(f, w, h) {
  const N = w * h; let s = 0, s2 = 0;
  for (let i = 0; i < N; i++) { const v = f[i]; s += v; s2 += v * v; }
  const mean = s / N, std = Math.sqrt(Math.max(0, s2 / N - mean * mean));
  let edges = 0;
  for (let y = 0; y < h - 1; y++) for (let x = 0, r = y * w; x < w - 1; x++) {
    const v = f[r + x];
    if (Math.abs(v - f[r + x + 1]) + Math.abs(v - f[r + x + w]) > T.edgeLevel) edges++;
  }
  return { mean, std, edgeFrac: edges / N };
}
const isBlank = (s) => s.std < T.blankStd;
function pick(obj, keys) {
  if (!obj || typeof obj !== 'object') return undefined;
  for (const k of keys) if (obj[k] !== undefined) return obj[k];
  for (const v of Object.values(obj)) if (v && typeof v === 'object' && !Array.isArray(v)) for (const k of keys) if (v[k] !== undefined) return v[k];
  return undefined;
}
function parseAspect(v) {
  const m = /^\s*(\d+(?:\.\d+)?)\s*[:x/]\s*(\d+(?:\.\d+)?)\s*$/.exec(String(v ?? ''));
  return m ? Number(m[1]) / Number(m[2]) : null;
}
function parseRanges(list) {
  const out = [];
  for (const s of list) {
    const m = /^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)(?::(.*))?$/.exec(String(s).trim());
    if (!m || Number(m[2]) < Number(m[1])) { console.error(`bad --reviewed-silence range "${s}" (expected a-b or a-b:reason, seconds)`); process.exit(2); }
    out.push([Number(m[1]), Number(m[2])]);
  }
  return out;
}

// ---------------------------------------------------------------- inputs
let requirements = null;
const reqPath = opt['--requirements'] ? resolve(opt['--requirements']) : (existsSync(resolve('story/requirements.json')) ? resolve('story/requirements.json') : null);
report.requirementsSha256 = null;
if (reqPath) {
  if (!existsSync(reqPath)) { err('requirements-unreadable', null, `requirements file not found: ${reqPath}`); finish(); }
  try { requirements = JSON.parse(readFileSync(reqPath, 'utf8').replace(/^\uFEFF/, '')); report.requirements = reqPath; report.requirementsSha256 = sha256File(reqPath); }
  catch (e) { err('requirements-unreadable', null, `requirements are not valid JSON: ${e.message}`); finish(); }
}
// job.json: <root>/out/x.mp4 -> <root>/job.json; the requirements file sits at <root>/story/requirements.json
function findJob() {
  const starts = [dirname(candidate), ...(reqPath ? [dirname(reqPath)] : [])];
  for (const d of starts) for (const dir of [d, dirname(d)]) {
    const j = join(dir, 'job.json');
    if (existsSync(j)) { try { return JSON.parse(readFileSync(j, 'utf8').replace(/^\uFEFF/, '')); } catch { /* an unreadable job.json declares nothing */ } }
  }
  return null;
}
const job = findJob();
const jobDeliverable = job?.deliverable ? String(job.deliverable) : job?.kind === 'audio-only' ? 'audio' : null;
const DELIVERABLES = ['narrated-video', 'silent-video', 'audio', 'stills', 'storyboard'];
if (opt['--deliverable'] && !DELIVERABLES.includes(opt['--deliverable'])) { console.error(`unknown deliverable "${opt['--deliverable']}"\n${USAGE}`); process.exit(2); }
const deliverable = opt['--deliverable'] || jobDeliverable || 'narrated-video';
report.deliverable = deliverable;
if (opt['--deliverable'] && jobDeliverable && opt['--deliverable'] !== jobDeliverable) err('deliverable-mismatch', null, `--deliverable ${opt['--deliverable']} contradicts the job's declared deliverable ${jobDeliverable}`);
if (deliverable === 'stills' || deliverable === 'storyboard') { report.notApplicable = true; finish(); }
if (!existsSync(candidate)) { err('candidate-missing', null, `candidate not found: ${candidate}`); finish(); }
const holdRaw = pick(requirements, ['finalHoldSeconds']);
const hold = Number.isFinite(Number(holdRaw)) && Number(holdRaw) > 0 ? Number(holdRaw) : 0;
const reviewedList = Array.isArray(pick(requirements, ['reviewedSilences'])) ? pick(requirements, ['reviewedSilences']) : [];
const reviewedReq = [];
for (const r of reviewedList) {
  if (!r || !Number.isFinite(Number(r.start)) || !Number.isFinite(Number(r.end)) || !String(r.reason ?? '').trim()) err('reviewed-silence-invalid', Number.isFinite(Number(r?.start)) ? Number(r.start) : null, 'a reviewed silence needs start, end and a reason saying why the pause is deliberate; it is not counted as reviewed');
  else reviewedReq.push([Number(r.start), Number(r.end)]);
}
const reviewed = [...parseRanges(reviewedArgs), ...reviewedReq];
const wantAspect = parseAspect(pick(requirements, ['aspect']));
const wantDuration = Number(pick(requirements, ['durationSeconds'])) || null;
const hasVideoDeliverable = deliverable !== 'audio';

const probe = await exec('ffprobe', ['-v', 'error', '-show_entries', 'format=duration:stream=index,codec_type,width,height,duration', '-of', 'json', candidate]);
let info = null;
try { info = JSON.parse(probe.out); } catch { /* handled below */ }
if (probe.timedOut) { err('timeout', null, `ffprobe did not finish within ${Math.round(timeoutMs / 1000)} s`); finish(); }
if (probe.code !== 0 || !info?.streams?.length) { err('unreadable', null, `ffprobe could not read the candidate: ${(probe.err || 'no streams').trim().slice(0, 200)}`); finish(); }
report.sha256 = sha256File(candidate);
const vStream = info.streams.find((s) => s.codec_type === 'video' && s.width);
const aStream = info.streams.find((s) => s.codec_type === 'audio');
const duration = Number(info.format?.duration) || Number(vStream?.duration) || Number(aStream?.duration) || 0;
report.durationSeconds = round(duration, 3);
if (!(duration > 0)) { err('unreadable', null, 'candidate has no measurable duration'); finish(); }
if (!process.env.FINISHED_FILM_TIMEOUT_MS) timeoutMs = 120000 + Math.ceil(duration * 1500);
if (wantDuration && Math.abs(duration - wantDuration) > Math.max(2, wantDuration * 0.03)) err('duration-mismatch', null, `the film runs ${round(duration)} s but requirements declare durationSeconds ${wantDuration}`);

if (hasVideoDeliverable && !vStream) err('no-video', null, `${deliverable} has no video stream`);
if (deliverable !== 'silent-video' && !aStream) err('no-audio', null, `${deliverable} has no audio stream; a narrated film must carry its narration`);
if (vStream && hasVideoDeliverable) {
  const w = Number(vStream.width), h = Number(vStream.height);
  report.size = { width: w, height: h };
  if (wantAspect && Math.abs(w / h / wantAspect - 1) > T.aspectTolerance) err('aspect-mismatch', null, `frame is ${w}x${h} (${round(w / h)}) but requirements declare aspect ${pick(requirements, ['aspect'])}`);
}

// ---------------------------------------------------------------- video: one reduced-scale pass + two freeze windows
const portrait = vStream && Number(vStream.height) > Number(vStream.width);
const [FW, FH] = portrait ? [AH, AW] : [AW, AH];
let frames = [];       // { mean, std, edgeFrac } per sample
const bandFlags = [];  // portrait only: { t, flagged } per sampled second
let openingStill = 0, endStill = 0, endWindow = 0;
async function videoPasses() {
  const wait = [];
  wait.push(decodeGray(['-i', candidate], `fps=${T.sampleFps}`, FW, FH, (f, i) => {
    const st = frameStats(f, FW, FH); frames.push(st);
    if (portrait && i % T.sampleFps === 0 && !isBlank(st)) {
      const rowEdge = (y0, y1) => { let s = 0, c = 0; for (let y = Math.floor(y0 * FH); y < Math.floor(y1 * FH); y++) for (let x = 0; x < FW - 1; x++) { s += Math.abs(f[y * FW + x] - f[y * FW + x + 1]); c++; } return s / c; };
      const bandStd = (y0, y1) => { let s = 0, s2 = 0, c = 0; for (let y = Math.floor(y0 * FH); y < Math.floor(y1 * FH); y++) for (let x = 0; x < FW; x++) { const v = f[y * FW + x]; s += v; s2 += v * v; c++; } const m = s / c; return Math.sqrt(Math.max(0, s2 / c - m * m)); };
      const centre = rowEdge(0.4, 0.6), top = rowEdge(0.02, 0.22), bottom = rowEdge(0.78, 0.98);
      const flagged = centre > 3 && top < centre * T.blurredBandEdgeRatio && bottom < centre * T.blurredBandEdgeRatio && bandStd(0.02, 0.22) > T.blurredBandStd && bandStd(0.78, 0.98) > T.blurredBandStd;
      bandFlags.push({ t: i / T.sampleFps, flagged });
    }
  }));
  const openArgs = ['-i', candidate, '-t', String(T.openingWindowSeconds)];
  const opening = [];
  wait.push(decodeGray(openArgs, `fps=${T.openingFps}`, FW, FH, (f) => {
    let s = 0, s2 = 0; for (let i = 0; i < f.length; i++) { s += f[i]; s2 += f[i] * f[i]; }
    const mean = s / f.length; opening.push({ mean, std: Math.sqrt(Math.max(0, s2 / f.length - mean * mean)) });
  }).then(() => opening));
  wait.push(ffmpegText(['-t', String(T.openingWindowSeconds), '-i', candidate, '-an', '-vf', `scale=320:-2,freezedetect=n=${T.freezeNoise}:d=${T.freezeMinSeconds}`, '-f', 'null', '-']));
  endWindow = Math.min(duration, Math.max(15, hold + 6));
  wait.push(ffmpegText(['-sseof', String(-endWindow), '-i', candidate, '-an', '-vf', `scale=320:-2,freezedetect=n=${T.freezeNoise}:d=${T.freezeMinSeconds}`, '-f', 'null', '-']));
  const [main, openFrames, openFreeze, endFreeze] = await Promise.all(wait);
  if (main.timedOut || openFreeze.timedOut || endFreeze.timedOut) { err('timeout', null, `ffmpeg did not finish decoding the picture within ${Math.round(timeoutMs / 1000)} s`); return null; }
  if (main.error) { err('decode-failed', null, `ffmpeg could not decode the picture: ${main.error}`); return null; }
  const of = parseFreezes(openFreeze.err, T.openingWindowSeconds).find((f) => f.start <= 0.3);
  openingStill = of ? of.duration : 0;
  const ef = parseFreezes(endFreeze.err, endWindow).filter((f) => f.end >= endWindow - 0.5).pop();
  endStill = ef ? Math.min(ef.duration, endWindow) : 0;
  return openFrames;
}

function analysePicture(openFrames) {
  const n = frames.length;
  if (!n) { err('decode-failed', null, 'candidate decoded to zero video frames'); return; }
  const dt = 1 / T.sampleFps;

  // opening: leading near-uniform frames at 25 fps
  let lead = 0; while (lead < openFrames.length && isBlank(openFrames[lead])) lead++;
  const blankSeconds = round(lead / T.openingFps);
  const first = openFrames[0] || frames[0];
  const staticOpening = !lead && openingStill >= T.openingStaticSeconds && duration > T.openingWindowSeconds;
  report.opening = { firstFrame: { meanLuma: round(first.mean, 1), std: round(first.std, 1), blank: lead > 0, black: lead > 0 && first.mean < T.blackLuma }, blankSeconds, stillSeconds: round(openingStill), changeWithin3s: !staticOpening };
  if (blankSeconds >= T.openingBlankSeconds) {
    err('opening-blank', 0, `the film opens on a ${first.mean < T.blackLuma ? 'black' : 'single-colour'} frame for ${blankSeconds} s (limit ${T.openingBlankSeconds} s); open on a designed first frame`);
  } else if (staticOpening) {
    adv('opening-static', 0, `no picture change in the first 3 s (still for ${round(openingStill)} s); look at 0:00-0:03 and confirm the opening is a designed frame, not a held loading or title-less screen`);
  }

  // blank spans
  let i = 0;
  while (i < n) {
    if (!isBlank(frames[i])) { i++; continue; }
    let j = i; while (j + 1 < n && isBlank(frames[j + 1])) j++;
    const start = i * dt, end = (j + 1) * dt, len = end - start;
    const kind = frames[i].mean < T.blackLuma ? 'black' : 'single-colour';
    const atEnd = end >= duration - 2 * dt;
    let exempt = null;
    if (i === 0) exempt = 'opening';
    else if (atEnd && len <= T.endFadeSeconds) exempt = 'end-fade';
    if (len > dt * 1.5 || !exempt) report.blankSpans.push({ start: round(start), end: round(Math.min(end, duration)), seconds: round(len), kind, exempt });
    if (!exempt && len > T.blankSpanSeconds) err('blank-span', start, `${kind} frame from ${tc(start)} to ${tc(Math.min(end, duration))} (${round(len)} s, limit ${T.blankSpanSeconds} s${atEnd ? '; a closing fade may last at most 1 s' : ''}); a gap, an unrendered scene or a dropped clip`);
    i = j + 1;
  }

  // low-detail spans between busier frames
  const low = (s) => !isBlank(s) && s.edgeFrac < T.lowDetailEdgeFrac;
  i = 1;
  while (i < n - 1) {
    if (!low(frames[i])) { i++; continue; }
    let j = i; while (j + 1 < n && low(frames[j + 1])) j++;
    const before = frames[i - 1], after = frames[j + 1];
    const len = (j - i + 1) * dt;
    if (after && before.edgeFrac > T.busyEdgeFrac && after.edgeFrac > T.busyEdgeFrac && len >= T.lowDetailSeconds) {
      adv('low-detail', i * dt, `a near-empty frame (little detail, not black) from ${tc(i * dt)} to ${tc((j + 1) * dt)} between busier pictures; look at those ${round(len)} s for a loading page, spinner or empty state left in the cut`);
    }
    i = j + 1;
  }

  // ending: last picture
  const last = frames[n - 1];
  const stillSeconds = round(endStill, 1);
  report.ending.stillSeconds = stillSeconds;
  if (hold > 0) {
    if (isBlank(last)) err('final-hold-blank', duration - 0.1, `the film ends on a ${last.mean < T.blackLuma ? 'black' : 'blank'} frame, but a ${hold} s final hold of the outcome picture is declared`);
    else if (stillSeconds < hold - 0.25) {
      const back = frames[Math.max(0, n - 1 - Math.round(2 * T.sampleFps))];
      const fading = back && last.mean < back.mean * 0.6 && last.mean < 60;
      err(fading ? 'final-hold-fading' : 'final-hold-unmet', Math.max(0, duration - hold), `a ${hold} s stable final picture is declared but the picture is still for ${stillSeconds} s${fading ? ' and is fading out' : ''}; hold the outcome state for the declared time`);
    }
  } else if (stillSeconds < T.stableEndSeconds && !isBlank(last)) {
    adv('ending-unsettled', Math.max(0, duration - 5), `the final picture is still for only ${stillSeconds} s; look at the last 5 s (${tc(Math.max(0, duration - 5))}-${tc(duration)}) and confirm it is a designed outcome state, not a cropped page or a cut mid-action`);
  }

  // blurred-fill vertical
  if (portrait && bandFlags.length) {
    const flagged = bandFlags.filter((b) => b.flagged);
    if (flagged.length / bandFlags.length >= T.blurredShare) {
      adv('blurred-fill', flagged[0].t, `${flagged.length} of ${bandFlags.length} sampled seconds of this vertical film show a sharp centre band with soft blurred bands above and below; look at ${tc(flagged[0].t)} and confirm it is recomposed from native captures, not a 16:9 master on a blurred fill`);
    }
  }
}

// ---------------------------------------------------------------- audio
async function audioPass() {
  if (deliverable === 'silent-video' || !aStream) return;
  const r = await ffmpegText(['-i', candidate, '-vn', '-af', `silencedetect=noise=${T.silenceNoiseDb}dB:d=0.5`, '-f', 'null', '-']);
  if (r.timedOut) { err('timeout', null, `ffmpeg did not finish the audio pass within ${Math.round(timeoutMs / 1000)} s`); return; }
  if (r.code !== 0) { err('decode-failed', null, `ffmpeg could not decode the audio: ${r.err.trim().slice(-200)}`); return; }
  const audioDur = Number(aStream.duration) || duration;
  const found = [];
  let open = null;
  for (const line of r.err.split(/\r?\n/)) {
    const s = /silence_start:\s*(-?[\d.]+)/.exec(line), e = /silence_end:\s*(-?[\d.]+)/.exec(line);
    if (s) open = Math.max(0, Number(s[1]));
    if (e && open !== null) { found.push({ start: open, end: Number(e[1]) }); open = null; }
  }
  if (open !== null) found.push({ start: open, end: audioDur });
  let trailing = 0;
  for (const s of found) {
    const dur = s.end - s.start;
    const isTrailing = s.end >= audioDur - 0.15;
    if (isTrailing) { trailing = Math.max(trailing, s.end - s.start); continue; }
    if (dur < 2) continue;
    const ok = reviewed.some(([a, b]) => s.start >= a - 1 && s.end <= b + 1);
    report.silences.push({ start: round(s.start), end: round(s.end), seconds: round(dur), kind: 'mid', reviewed: ok });
    if (dur >= T.silenceErrorSeconds && !ok) err('silence', s.start, `${round(dur)} s of silence from ${tc(s.start)} to ${tc(s.end)} (limit ${T.silenceErrorSeconds} s); fill the gap, cut it, or list it as reviewed with --reviewed-silence`);
    else if (dur >= T.silenceAdvisorySeconds && dur < T.silenceErrorSeconds) adv('silence-review', s.start, `${round(dur)} s of silence from ${tc(s.start)} to ${tc(s.end)}; listen to it and confirm the pause is deliberate (a result being read, a transition) and not dead air`);
  }
  if (vStream && hasVideoDeliverable && duration - audioDur > 0.05) trailing += duration - audioDur;
  if (trailing > 0) report.silences.push({ start: round(duration - trailing), end: round(duration), seconds: round(trailing), kind: 'trailing', reviewed: false });
  report.ending.trailingSilenceSeconds = round(trailing, 1);
  const limit = hold > 0 ? hold + T.trailingSilenceSlackSeconds : T.trailingSilenceUndeclaredSeconds;
  if (trailing > limit + 0.1) {
    err('trailing-silence', duration - trailing, `${round(trailing)} s of silence at the end (allowed: ${hold > 0 ? `the ${hold} s declared final hold plus 3 s` : '6 s when no final hold is declared'}); end the film when the last line ends or declare the hold`);
  } else if (hold === 0 && trailing > T.trailingSilenceSlackSeconds) {
    pendingTrailingReview = trailing; // worded after the picture pass, which knows whether the final picture was stable
  }
}
let pendingTrailingReview = null;

if (hasVideoDeliverable && vStream) {
  const [openFrames] = await Promise.all([videoPasses(), audioPass()]);
  if (openFrames) analysePicture(openFrames);
} else {
  await audioPass();
}
if (pendingTrailingReview !== null) {
  const at = duration - pendingTrailingReview;
  const pic = !(hasVideoDeliverable && vStream) ? '' : endStill >= pendingTrailingReview - 0.5 ? ` The final picture was stable for ${round(endStill, 1)} s, so this reads as a held outcome card;` : ` The final picture was still for only ${round(endStill, 1)} s, so it may be moving or fading through the silence;`;
  adv('trailing-silence-review', at, `${round(pendingTrailingReview)} s of silence at the end (${tc(at)}-${tc(duration)}).${pic} look at the last seconds and confirm the held picture is a designed outcome state.`);
}
finish();
