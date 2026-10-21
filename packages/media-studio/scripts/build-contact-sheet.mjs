#!/usr/bin/env node
// Contact sheet for the reviewer: one PNG, one still per moment that matters, in cue-sheet order, so a person can see
// the whole film's story at a glance and jump to the frame a finding names.
// Usage: node build-contact-sheet.mjs <jobRoot> <candidate.mp4> [--cue-sheet plan/cue-sheet.json] [--out qa/contact-sheet.png]
//                                      [--columns 4] [--width 320]
//
// Frames: the first frame (0.0); for each cue-sheet beat the moment its screen is on (screen.visible_from), each action
// (actions[].action_time) and its result (result.visible_at), each falling back to the beat's t_start when null; the
// last frame (duration - 0.1). Times within 0.1 s of a kept frame are dropped. Stills are tiled left to right, top to
// bottom. When ffmpeg has a working drawtext each still carries "beat kind t" top-left; otherwise the sheet is
// index-only (tile order = frames[].index in the report).
// Writes <out>.json beside the PNG: { generator, ok, errors, candidate:{path,sha256,bytes}, inputs:{cueSheet}, out,
// columns, rows, cell:{w,h}, labels:'burned'|'index-only', frames:[{index,beat,kind,t,label}] }.
import { existsSync, readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, relative, isAbsolute, extname } from 'node:path';

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
const [jobRoot, candidateArg] = pos;
if (!jobRoot || !candidateArg) { console.error('Usage: node build-contact-sheet.mjs <jobRoot> <candidate.mp4> [--cue-sheet plan/cue-sheet.json] [--out qa/contact-sheet.png] [--columns 4] [--width 320]'); process.exit(1); }

const root = resolve(jobRoot);
const candidate = resolve(candidateArg);
const cueSheetPath = resolve(root, flag('--cue-sheet', 'plan/cue-sheet.json'));
const pngPath = resolve(root, flag('--out', 'qa/contact-sheet.png'));
const indexPath = pngPath.replace(new RegExp(`${extname(pngPath).replace('.', '\\.')}$`), '') + '.json';
const COLUMNS = Math.max(1, Math.floor(Number(flag('--columns', 4))) || 4);
const WIDTH = Math.max(32, Math.floor(Number(flag('--width', 320))) || 320);
const DEDUPE = 0.1;
const KIND_RANK = { first: 0, 'screen-on': 1, action: 2, result: 3, last: 4 };

const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const rel = (p) => { const r = relative(root, p); return (r && !r.startsWith('..') && !isAbsolute(r) ? r : p).replace(/\\/g, '/'); };
const errors = [];
const warnings = [];
const fail = (m) => { console.error(`[contact-sheet] ${m}`); errors.push(m); };
const ffmpeg = (args) => spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { windowsHide: true, encoding: 'utf8', timeout: 180000, maxBuffer: 1 << 24 });

const report = { generator: 'media-studio/build-contact-sheet', schemaVersion: '1.0.0', ok: false, errors, warnings, candidate: null, inputs: {}, out: rel(pngPath), columns: 0, rows: 0, cell: { w: 0, h: 0 }, labels: 'index-only', frames: [] };
function finish() {
  report.ok = errors.length === 0;
  mkdirSync(dirname(indexPath), { recursive: true });
  writeFileSync(indexPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: report.ok, out: rel(pngPath), index: rel(indexPath), frames: report.frames.length, labels: report.labels, errors, warnings }));
  process.exit(report.ok ? 0 : 1);
}

if (!existsSync(candidate)) { fail(`candidate not found: ${candidate}`); finish(); }
report.candidate = { path: rel(candidate), sha256: sha(candidate), bytes: statSync(candidate).size };
if (!existsSync(cueSheetPath)) { fail(`cue sheet not found: ${rel(cueSheetPath)}; build it with build-cue-sheet.mjs, then run this again`); finish(); }
let sheet;
try { sheet = JSON.parse(readFileSync(cueSheetPath, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { fail(`cue sheet is not valid JSON: ${rel(cueSheetPath)} (${e.message})`); finish(); }
report.inputs.cueSheet = { path: rel(cueSheetPath), sha256: sha(cueSheetPath) };

const pr = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', candidate], { windowsHide: true, encoding: 'utf8', timeout: 60000 });
const duration = parseFloat(String(pr.stdout || '').trim());
if (!(duration > 0)) { fail('ffprobe cannot read the candidate duration'); finish(); }
const lastT = Math.max(0, Math.round((duration - 0.1) * 1000) / 1000);

// ---- the moments
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const raw = [{ t: 0, kind: 'first', beat: null, label: null }];
for (const b of sheet.beats || []) {
  const fb = num(b.t_start);
  const add = (t, kind, label) => {
    const v = num(t) ?? fb;
    if (v === null) { warnings.push(`beat ${b.beat}: no time for ${kind}${label ? ` "${label}"` : ''} and no t_start; skipped`); return; }
    raw.push({ t: v, kind, beat: b.beat ?? null, label: label ?? null });
  };
  add(b.screen?.visible_from, 'screen-on', b.screen?.clip ?? null);
  for (const a of b.actions || []) add(a.action_time, 'action', a.label ?? a.target ?? null);
  if (b.result) add(b.result.visible_at, 'result', b.result.label ?? null);
}
raw.push({ t: lastT, kind: 'last', beat: null, label: null });
let beyond = 0;
for (const m of raw) if (m.t > lastT) { m.t = lastT; beyond++; } else if (m.t < 0) m.t = 0;
if (beyond) warnings.push(`${beyond} moment(s) lie past the end of the candidate and were clamped to the last frame`);
raw.sort((a, b) => a.t - b.t || KIND_RANK[a.kind] - KIND_RANK[b.kind]);
// first and last always survive; anything within 0.1 s of a kept frame is dropped
const kept = [];
for (const m of raw) {
  const near = kept.find((k) => Math.abs(k.t - m.t) < DEDUPE);
  if (!near) { kept.push(m); continue; }
  if (m.kind === 'last' && near.kind !== 'first') { kept[kept.indexOf(near)] = m; } // the last frame outranks a neighbour
}
kept.sort((a, b) => a.t - b.t || KIND_RANK[a.kind] - KIND_RANK[b.kind]);
kept.forEach((m, index) => { m.index = index; m.t = Math.round(m.t * 1000) / 1000; });
report.frames = kept.map((m) => ({ index: m.index, beat: m.beat, kind: m.kind, t: m.t, label: m.label }));

// ---- stills
const work = mkdtempSync(join(tmpdir(), 'ms-contact-'));
build: try {
  const hasDrawtext = /drawtext/.test(spawnSync('ffmpeg', ['-hide_banner', '-filters'], { windowsHide: true, encoding: 'utf8', timeout: 30000 }).stdout || '');
  const fontCandidates = ['C:/Windows/Fonts/arial.ttf', 'C:/Windows/Fonts/segoeui.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/System/Library/Fonts/Supplemental/Arial.ttf'];
  const font = fontCandidates.find(existsSync);
  const clean = (s) => String(s ?? '').replace(/[^A-Za-z0-9._ -]/g, '').slice(0, 24);
  const drawtext = (m) => {
    const text = `${m.index} ${clean(m.beat)} ${m.kind} ${m.t.toFixed(2)}s`.replace(/\s+/g, ' ');
    const fontPart = font ? `fontfile='${font.replace(/^([A-Za-z]):/, '$1\\:')}':` : '';
    return `drawtext=${fontPart}text='${text}':x=4:y=4:fontsize=${Math.max(10, Math.round(WIDTH / 22))}:fontcolor=white:box=1:boxcolor=black@0.65:boxborderw=3`;
  };
  const extract = (labelled) => {
    for (const m of kept) {
      const vf = `scale=${WIDTH}:-2${labelled ? ',' + drawtext(m) : ''}`;
      const r = ffmpeg(['-ss', String(m.t), '-i', candidate, '-frames:v', '1', '-an', '-vf', vf, join(work, `s${String(m.index).padStart(4, '0')}.png`)]);
      if (r.status !== 0 || !existsSync(join(work, `s${String(m.index).padStart(4, '0')}.png`))) return String(r.stderr || r.error || 'ffmpeg failed').trim().slice(0, 300);
    }
    return null;
  };
  let labels = 'index-only';
  let problem = null;
  if (hasDrawtext) {
    problem = extract(true);
    if (problem) warnings.push(`drawtext failed (${problem.split('\n')[0]}); labels are index-only`);
    else labels = 'burned';
  } else warnings.push('ffmpeg has no drawtext filter; labels are index-only (tile order = frames[].index)');
  if (labels === 'index-only') { problem = extract(false); if (problem) { fail(`could not extract stills: ${problem}`); break build; } }
  report.labels = labels;

  // ---- tile
  const cols = Math.min(COLUMNS, kept.length);
  const rows = Math.ceil(kept.length / cols);
  const probe = spawnSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0:s=x', join(work, 's0000.png')], { windowsHide: true, encoding: 'utf8', timeout: 30000 });
  const [cw, ch] = String(probe.stdout || '').trim().split('x').map(Number);
  if (!(cw > 0 && ch > 0)) { fail('cannot read the still size'); break build; }
  mkdirSync(dirname(pngPath), { recursive: true });
  const t = ffmpeg(['-framerate', '1', '-i', join(work, 's%04d.png'), '-vf', `tile=${cols}x${rows}:padding=0:margin=0`, '-frames:v', '1', pngPath]);
  if (t.status !== 0 || !existsSync(pngPath)) { fail(`tile failed: ${String(t.stderr || t.error || '').trim().slice(0, 300)}`); break build; }
  Object.assign(report, { columns: cols, rows, cell: { w: cw, h: ch } });
} finally {
  rmSync(work, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
}
finish();
