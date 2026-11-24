#!/usr/bin/env node
// Measures the picture an edit list cannot describe: hero size, a lit hero,
// empty stretches, background debris and the landing hold. These are review
// diagnostics. The receipt identifies the exact props and candidate measured.
//
// Usage: node scripts/measure-explainer-frames.mjs --props <explainer-props.json> --frames <dir>
//          [--encoded <candidate.mp4>] [--out <report.json>] [--step 4] [--fps 30] [--strict]
//
// Frames are read natively: PNG through kit/explainer/png.mjs and binary PPM
// (P6) here. Nothing shells out to ffmpeg, nothing spends, nothing fetches.
//
// Exit codes: 2 when the inputs cannot be measured (no frames, unreadable
// props, an undecodable frame) — a silent empty report is the failure mode
// this script exists to prevent; 1 under --strict for incomplete frame
// coverage; 0 otherwise. Composition flags remain in the report.
import { createHash } from 'node:crypto';
import { createReadStream, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { PngError, decodePng } from './png.mjs';
import {
  RULES,
  analyzeSequence,
  contentProfile,
  frameMetrics,
  landingHold,
  scoreFilm,
  scoreFrame,
} from './frame-metrics.mjs';

const USAGE =
  'Usage: node measure-explainer-frames.mjs --props <explainer-props.json> --frames <dir> [--encoded <candidate.mp4>] [--out <report.json>] [--step 4] [--fps 30] [--strict]';

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const at = argv.indexOf(name);
  if (at < 0) return fallback;
  const value = argv[at + 1];
  if (value === undefined || value.startsWith('--')) {
    console.error(`[measure-explainer-frames] ${name} needs a value\n${USAGE}`);
    process.exit(2);
  }
  return value;
};
const strict = argv.includes('--strict');

const propsPath = flag('--props');
const framesDir = flag('--frames');
if (!propsPath || !framesDir) {
  console.error(`[measure-explainer-frames] --props and --frames are required\n${USAGE}`);
  process.exit(2);
}

const propsFile = resolve(propsPath);
const framesRoot = resolve(framesDir);

const die = (message) => {
  console.error(`[measure-explainer-frames] ${message}`);
  process.exit(2);
};

const number = (value, name, { min = 0, integer = false } = {}) => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || (integer && !Number.isInteger(value))) {
    die(`${name} must be ${integer ? 'an integer' : 'a number'} >= ${min}, got ${value}`);
  }
  return value;
};

const r1 = (v) => Math.round(v * 10) / 10;
const r3 = (v) => Math.round(v * 1000) / 1000;

/* ------------------------------------------------------------------ props -- */

if (!existsSync(propsFile)) die(`props not found: ${propsFile}`);
const propsBytes = readFileSync(propsFile);
const propsSha256 = createHash('sha256').update(propsBytes).digest('hex');
let props;
try {
  props = JSON.parse(propsBytes.toString('utf8').replace(/^\uFEFF/, ''));
} catch (error) {
  die(`props is not valid JSON: ${error.message}`);
}
if (!props || typeof props !== 'object') die('props must be a JSON object');
const film = props.film;
if (!film || typeof film !== 'object') die('props.film is required; it carries the canvas the frames were rendered at');
const canvas = {
  width: number(film.width, 'props.film.width', { min: 1, integer: true }),
  height: number(film.height, 'props.film.height', { min: 1, integer: true }),
};
const fps = number(Number(flag('--fps', film.fps ?? 30)), '--fps', { min: 1 });
const step = number(Number(flag('--step', 4)), '--step', { min: 1, integer: true });
if (!Array.isArray(props.shots) || props.shots.length === 0) {
  die('props.shots is required; without shot boundaries the measurements cannot be bound to a shot');
}

// The props may sit in a job's story/ or plan/ folder; the report belongs at
// the job root's qa/, where every other gate looks for its evidence.
const JOB_SUBDIRS = new Set(['story', 'plan', 'props', 'films', 'kit', 'picture']);
const jobRootFor = (file) => {
  const dir = dirname(file);
  return JOB_SUBDIRS.has(basename(dir).toLowerCase()) ? dirname(dir) : dir;
};
const jobRoot = jobRootFor(propsFile);
const outFile = resolve(jobRoot, flag('--out', join('qa', 'explainer-frame-metrics.json')));
const rel = (p) => {
  const r = relative(jobRoot, p);
  return (r && !r.startsWith('..') && !isAbsolute(r) ? r : p).replace(/\\/g, '/');
};

/* ----------------------------------------------------------------- frames -- */

if (!existsSync(framesRoot) || !statSync(framesRoot).isDirectory()) {
  die(`frames directory not found: ${framesRoot}`);
}
const FRAME_NAME = /^(?:frame|f)[-_]?(\d+)\.(png|ppm)$/i;
const found = new Map();
for (const name of readdirSync(framesRoot)) {
  const match = FRAME_NAME.exec(name);
  if (!match) continue;
  const index = Number(match[1]);
  if (!Number.isInteger(index) || index < 1) die(`frame file ${name} has no usable 1-based index`);
  if (found.has(index)) die(`two frame files claim frame ${index}: ${found.get(index).name} and ${name}`);
  found.set(index, { index, name, ext: match[2].toLowerCase() });
}
if (found.size === 0) {
  die(
    `no frame files in ${framesRoot}; expected frame-000001.png, f_0001.png or frame_000001.ppm (the index in the name is 1-based)`,
  );
}
const frameFiles = [...found.values()].sort((a, b) => a.index - b.index);
const expectedFrames = Math.round(props.totalSeconds * fps);
const complete = frameFiles.length === expectedFrames && frameFiles.every((frame, i) => frame.index === i + 1);
const encodedArg = flag('--encoded');
let encoded = null;
if (encodedArg) {
  if (!complete) die('an encoded release measurement requires the complete 1-based frame export');
  const candidate = resolve(encodedArg);
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(candidate)) hash.update(chunk);
  encoded = { sha256: hash.digest('hex').toUpperCase(), bytes: statSync(candidate).size };
}
const sampled = frameFiles.filter((frame) => (frame.index - 1) % step === 0);

/* PPM (P6) is read here rather than in the pure module because it is frame
 * I/O; the pure module must stay free of fs. */
const WHITESPACE = new Set([32, 9, 10, 13, 11, 12]);
const readPpm = (buffer, name) => {
  if (buffer.length < 2 || buffer[0] !== 0x50 || buffer[1] !== 0x36) {
    throw new Error(`${name} is not a binary PPM (P6)`);
  }
  let i = 2;
  const tokens = [];
  while (tokens.length < 3) {
    while (i < buffer.length && WHITESPACE.has(buffer[i])) i += 1;
    if (i < buffer.length && buffer[i] === 0x23) {
      while (i < buffer.length && buffer[i] !== 0x0a) i += 1;
      continue;
    }
    const start = i;
    while (i < buffer.length && !WHITESPACE.has(buffer[i])) i += 1;
    if (start === i) throw new Error(`${name} has a truncated PPM header`);
    tokens.push(Number(buffer.toString('latin1', start, i)));
  }
  const [width, height, maxval] = tokens;
  if (!Number.isInteger(width) || width < 1 || !Number.isInteger(height) || height < 1) {
    throw new Error(`${name} declares ${width}x${height}`);
  }
  if (maxval !== 255) throw new Error(`${name} has maxval ${maxval}; only 8-bit PPM is read`);
  if (i < buffer.length && WHITESPACE.has(buffer[i])) i += buffer[i] === 13 && buffer[i + 1] === 10 ? 2 : 1;
  const needed = width * height * 3;
  if (buffer.length - i < needed) throw new Error(`${name} declares ${width}x${height} but carries ${buffer.length - i} bytes`);
  const rgba = new Uint8Array(width * height * 4);
  for (let p = 0, q = i; p < rgba.length; p += 4, q += 3) {
    rgba[p] = buffer[q];
    rgba[p + 1] = buffer[q + 1];
    rgba[p + 2] = buffer[q + 2];
    rgba[p + 3] = 0xff;
  }
  return { width, height, rgba };
};

const readFrame = (file) => {
  const path = join(framesRoot, file.name);
  const bytes = readFileSync(path);
  if (file.ext === 'ppm') return readPpm(bytes, file.name);
  return decodePng(bytes);
};

/* ------------------------------------------------------------------ sweep -- */

const metricsOptions = { step };
const entries = [];
for (const file of sampled) {
  let frame;
  try {
    frame = readFrame(file);
  } catch (error) {
    if (error instanceof PngError) die(`${file.name}: ${error.message} (${error.code})`);
    die(`${file.name}: ${error.message}`);
  }
  if (frame.width !== canvas.width || frame.height !== canvas.height) {
    die(
      `frame ${file.name} is ${frame.width}x${frame.height} but props.film is ${canvas.width}x${canvas.height}; measure a render of these props, not a resized preview`,
    );
  }
  entries.push({
    index: file.index,
    width: frame.width,
    height: frame.height,
    metrics: frameMetrics(frame.rgba, frame.width, frame.height, metricsOptions),
    // Keep the 320x180 profile instead of the RGBA buffer: a full film of
    // 1600x1000 frames would be gigabytes of pixels held for a diff.
    profile: contentProfile(frame.rgba, frame.width, frame.height),
  });
}

// Families whose first second is the build itself: a diagram landing is not an
// empty frame, and the reference exempted a set-piece's opening 40 frames.
const SET_PIECE_FAMILIES = new Set(['mechanism', 'layers', 'timeline', 'contrast', 'checklist']);
const shots = props.shots.map((shot) => ({
  id: shot.id,
  family: shot.family ?? null,
  startFrame: shot.startFrame,
  durationFrames: shot.durationFrames,
}));
const setPieceShots = shots.filter((shot) => SET_PIECE_FAMILIES.has(shot.family)).map((shot) => shot.id);

const sequence = analyzeSequence(entries, canvas, {
  fps,
  step,
  shots,
  setPieceShots,
  metrics: metricsOptions,
});
const hold = landingHold(entries, { fps, step });

const filmRules = { ...RULES };
const scored = sequence.perFrame.map((frame) => {
  const verdict = scoreFrame(
    frame,
    { width: frame.width, height: frame.height },
    { ...filmRules, family: frame.family },
  );
  return { index: frame.index, level: verdict.level, flags: verdict.flags };
});
const verdict = scoreFilm(
  { perFrame: scored, staticRuns: sequence.staticRuns, emptyRuns: sequence.emptyRuns, landingHold: hold },
  filmRules,
);

/* ------------------------------------------------------------- per shot -- */

const median = (values) => {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

const worst = (levels) => {
  const rank = { ok: 0, low: 1, medium: 2, high: 3 };
  return levels.reduce((a, b) => (rank[b] > rank[a] ? b : a), 'ok');
};

const levelOf = new Map(scored.map((entry) => [entry.index, entry.level]));
const perShot = shots.map((shot) => {
  const frames = sequence.perFrame.filter((frame) => frame.shotId === shot.id);
  const levels = frames.map((frame) => levelOf.get(frame.index)).filter(Boolean);
  const heroes = frames.map((frame) => (frame.hero ? frame.hero.height : 0));

  let longestEmpty = 0;
  let runStart = null;
  for (let i = 0; i < frames.length; i += 1) {
    if (frames[i].empty) {
      if (runStart === null) runStart = frames[i].index;
    } else if (runStart !== null) {
      longestEmpty = Math.max(longestEmpty, frames[i - 1].index - runStart + step);
      runStart = null;
    }
  }
  if (runStart !== null) longestEmpty = Math.max(longestEmpty, frames[frames.length - 1].index - runStart + step);

  let longestStatic = 0;
  let stillStart = null;
  frames.forEach((frame) => {
    if (frame.static) {
      if (stillStart === null) stillStart = frame.index;
      longestStatic = Math.max(longestStatic, (frame.index - stillStart) / fps);
    } else stillStart = null;
  });

  return {
    id: shot.id,
    family: shot.family,
    startFrame: shot.startFrame,
    durationFrames: shot.durationFrames,
    sampled: frames.length,
    heroMedianPx: Math.round(median(heroes)),
    heroMinPx: Math.round(heroes.length ? Math.min(...heroes) : 0),
    longestEmptyRunFrames: longestEmpty,
    longestEmptyRunSeconds: r1(longestEmpty / fps),
    debrisMax: frames.reduce((max, frame) => Math.max(max, frame.debris), 0),
    longestStaticRunSeconds: r1(longestStatic),
    level: worst(levels),
    high: levels.filter((level) => level === 'high').length,
    medium: levels.filter((level) => level === 'medium').length,
  };
});

/* ---------------------------------------------------------------- report -- */

const flagCounts = {};
for (const entry of verdict.flags) flagCounts[entry.rule] = (flagCounts[entry.rule] ?? 0) + 1;

// validate-explainer-release reads these two rather than the run list, so a
// measured empty stretch has to arrive as a film-level number or the receipt
// binds to a gate that can never see it.
const longestEmptyRun = sequence.emptyRuns.reduce(
  (max, run) => (run.frames > max.frames ? run : max),
  { frames: 0, seconds: 0 },
);

const report = {
  generator: 'media-studio/measure-explainer-frames',
  schemaVersion: '1.0.0',
  props: rel(propsFile),
  propsSha256,
  encoded,
  complete,
  framesDir: rel(framesRoot),
  frames: frameFiles.length,
  sampled: entries.length,
  step,
  fps,
  canvas,
  frameIndexBase: 'frame file N is film frame N-1; shots[].startFrame is 0-based',
  thresholds: {
    ...filmRules,
    heroStrongPx: Math.round(filmRules.heroStrong * canvas.height),
    heroSmallPx: Math.round(filmRules.heroSmall * canvas.height),
    heroEmptyPx: Math.round(filmRules.heroEmpty * canvas.height),
    setPieceShots,
  },
  perShot,
  film: {
    ok: verdict.ok,
    level: verdict.high ? 'high' : verdict.medium ? 'medium' : 'ok',
    high: verdict.high,
    medium: verdict.medium,
    low: verdict.low,
    flagCounts,
    flags: verdict.flags,
    longestStaticSeconds: r3(sequence.longestStaticSeconds),
    longestEmptyRunFrames: longestEmptyRun.frames,
    longestEmptyRunSeconds: r1(longestEmptyRun.seconds),
    staticRuns: sequence.staticRuns.map((run) => ({
      startFrame: run.startFrame,
      endFrame: run.endFrame,
      frames: run.frames,
      seconds: r3(run.seconds),
    })),
    cuts: sequence.cuts.length,
    emptyRuns: sequence.emptyRuns.map((run) => ({
      startFrame: run.startFrame,
      endFrame: run.endFrame,
      frames: run.frames,
      seconds: r1(run.seconds),
    })),
    landingHold: { frames: hold.frames, seconds: r3(hold.seconds), heldFrames: hold.heldFrames },
    heroMedianPx: Math.round(sequence.medianHero),
    inkCoverageMedian: r3(median(sequence.perFrame.map((frame) => frame.inkCoverage))),
    lumaStdMedian: r1(median(sequence.perFrame.map((frame) => frame.lumaStd))),
    debrisMedian: median(sequence.perFrame.map((frame) => frame.debris)),
  },
};

report.ok = verdict.ok;
mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, `${JSON.stringify(report, null, 2)}\n`);

console.log(
  JSON.stringify({
    ok: verdict.ok,
    out: rel(outFile),
    frames: report.frames,
    sampled: report.sampled,
    step,
    fps,
    high: verdict.high,
    medium: verdict.medium,
    longestStaticSeconds: report.film.longestStaticSeconds,
    landingHoldFrames: hold.frames,
    emptyRuns: report.film.emptyRuns.length,
    shots: perShot.length,
    propsSha256,
  }),
);

if (strict && !complete) process.exit(1);
