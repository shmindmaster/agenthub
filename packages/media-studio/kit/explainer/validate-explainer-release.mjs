#!/usr/bin/env node
// The explainer release gate: refuse a film whose shot grammar, clock or
// measured picture does not hold up.
//
//   node validate-explainer-release.mjs <jobRoot> [--props picture/explainer-props.json]
//        [--metrics qa/explainer-frame-metrics.json] [--encoded output/film.mp4]
//        [--require-metrics] [--strict]
//
// Why this exists: the package's own evidence says the existing gates cannot
// tell a good picture from a clean one ("variety, not quality"; relevance
// "does not judge design"). This gate judges the three things that separated
// the reference's weak film from its strong one: frame composition (hero size,
// emptiness, debris), sustained motion with a landing hold, and a shot grammar
// that actually varies the composition. It writes qa/explainer-release.json.
//
// No network, no spend.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { familyOf, FAMILIES, RULES, validateShot } from './grammar.mjs';
import { isWide } from './layout.mjs';

const flag = (argv, name, fallback = null) => {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : fallback;
};
const has = (argv, name) => argv.includes(name);
const readJson = (path) => JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
const sha256 = (buffer) => createHash('sha256').update(buffer).digest('hex').toUpperCase();

/** Tolerant reader for the metrics receipt: fields may be film-level or derived. */
export const metricsFacts = (report) => {
  const film = report.film ?? {};
  const runs = report.staticRuns ?? film.staticRuns ?? [];
  const longest = Number(
    film.longestStaticSeconds ?? (runs.length ? Math.max(...runs.map((run) => Number(run.seconds ?? 0))) : 0),
  );
  const emptyRun = Number(film.longestEmptyRunFrames ?? film.emptyRunMaxFrames ?? 0);
  const emptySeconds = Number(film.longestEmptyRunSeconds ?? emptyRun / (Number(report.fps) || 30));
  const heroMedian = Number(film.heroMedianPx ?? film.heroMedianHeight ?? 0);
  const debris = Number(film.debrisMax ?? film.debrisMedian ?? 0);
  const cuts = Number(film.cuts ?? (Array.isArray(report.cuts) ? report.cuts.length : 0));
  return { longestStaticSeconds: longest, emptySeconds, heroMedianPx: heroMedian, debris, cuts };
};

/**
 * The whole judgement as a pure function so tests can drive it without a job.
 * `metrics` and `encoded` are optional; `requireMetrics` turns their absence
 * into a failure instead of a warning.
 */
export const judge = ({ props, propsSha256, cueSheet, metrics, encoded, requireMetrics = false, strict = false }) => {
  const failed = [];
  const warnings = [];
  const fail = (rule, message, shotId) => failed.push({ rule, message, ...(shotId ? { shotId } : {}) });
  const warn = (rule, message, shotId) => warnings.push({ rule, message, ...(shotId ? { shotId } : {}) });

  if (!props || typeof props !== 'object') {
    fail('props-shape', 'the props are not an object');
    return { ok: false, failed, warnings };
  }
  const film = props.film ?? {};
  const shots = Array.isArray(props.shots) ? props.shots : [];
  if (!film.title) fail('film-title', 'film.title is missing');
  if (!Array.isArray(film.chapters) || !film.chapters.length) fail('chapters-empty', 'film.chapters is empty');
  if (!shots.length) fail('shots-empty', 'shots[] is empty');
  if (!isWide({ width: film.width ?? 0, height: film.height ?? 0 })) {
    fail('aspect', `explainer renders landscape only; ${film.width}x${film.height} is not wide`);
  }
  if (!Number.isFinite(props.totalSeconds) || props.totalSeconds <= 0) fail('duration', 'totalSeconds is not positive');

  const fps = Number(film.fps ?? 30);
  const sumFrames = shots.reduce((sum, shot) => sum + Number(shot.durationFrames ?? 0), 0);
  const expectedFrames = Math.round(Number(props.totalSeconds ?? 0) * fps);
  if (Math.abs(sumFrames - expectedFrames) > 1) {
    fail('duration-exact', `shot frames sum to ${sumFrames}; totalSeconds is ${expectedFrames} frames`);
  }
  for (let index = 0; index < shots.length; index += 1) {
    const shot = shots[index];
    const expectedStart = index === 0 ? 0 : shots[index - 1].startFrame + shots[index - 1].durationFrames;
    if (shot.startFrame !== expectedStart) {
      fail('shot-contiguous', `${shot.id} starts at frame ${shot.startFrame}; the previous shot ends at ${expectedStart}`, shot.id);
    }
    if (familyOf(shot.archetype, shot.visual?.kind) !== shot.family) {
      fail('family-consistent', `${shot.id} declares family ${shot.family} but ${shot.archetype} renders as ${familyOf(shot.archetype, shot.visual?.kind)}`, shot.id);
    }
    const durationSeconds = Number(shot.durationSeconds ?? shot.durationFrames / fps);
    for (const problem of validateShot({ ...shot, durationSeconds }, { previousFamily: familyOf(shots[index - 1]?.archetype, shots[index - 1]?.visual?.kind) })) {
      fail(problem.rule, problem.message, shot.id);
    }
    const lastBeat = Math.max(0, ...(shot.beats ?? []).map((beat) => Number(beat.atSeconds ?? 0)));
    const hold = Number(shot.holdSeconds ?? durationSeconds - lastBeat);
    if (hold < RULES.minHoldSeconds) {
      fail('hold', `${shot.id} lands and cuts: ${hold.toFixed(2)}s after the last beat, floor ${RULES.minHoldSeconds}s`, shot.id);
    }
    const firstBeat = Math.min(
      ...(shot.beats?.length ? shot.beats.map((beat) => Number(beat.atSeconds ?? Infinity)) : [0.15]),
    );
    const firstMotion = shot.title || shot.kicker || shot.sub ? 0.15 : firstBeat;
    if (firstMotion > RULES.firstBeatMaxSeconds) {
      fail('first-beat', `${shot.id} does not move until ${firstMotion.toFixed(2)}s, later than ${RULES.firstBeatMaxSeconds}s`, shot.id);
    }
    if (firstBeat > RULES.heroMaxSeconds) {
      fail('hero-late', `${shot.id} brings its hero at ${firstBeat.toFixed(2)}s, later than ${RULES.heroMaxSeconds}s`, shot.id);
    }
    if ((shot.beats ?? []).some((beat) => Number(beat.atSeconds) > durationSeconds - 0.2)) {
      fail('beat-after-end', `${shot.id} has a beat at or after its end`, shot.id);
    }
  }

  const typeOnly = shots.filter((shot) => ['statement', 'quote', 'number'].includes(shot.family)).length;
  if (typeOnly / Math.max(1, shots.length) > RULES.maxStatementShare) {
    fail('type-only-cap', `${typeOnly}/${shots.length} shots are type-only; cap ${Math.round(RULES.maxStatementShare * 100)}%`);
  }

  const chapters = film.chapters ?? [];
  chapters.forEach((chapter, index) => {
    const expectedStart = index === 0 ? 0 : chapters[index - 1].endFrame;
    if (chapter.startFrame !== expectedStart) {
      fail('chapter-contiguous', `chapter ${chapter.id} starts at ${chapter.startFrame}; expected ${expectedStart}`);
    }
    const seconds = (chapter.endFrame - chapter.startFrame) / fps;
    if (seconds <= 0) fail('chapter-empty', `chapter ${chapter.id} has no frames`);
    if (props.totalSeconds >= 180 && seconds < RULES.minChapterSeconds) {
      fail('chapter-min', `chapter ${chapter.id} runs ${seconds.toFixed(1)}s; a film over three minutes needs ${RULES.minChapterSeconds}s`);
    }
    const members = shots.filter((shot) => shot.chapterId === chapter.id);
    if (!members.length) fail('chapter-members', `chapter ${chapter.id} has no shots`);
    const hasBig = members.some((shot) => ['l', 'xl'].includes(FAMILIES[shot.family]?.tier));
    if (!hasBig) fail('chapter-hero', `chapter ${chapter.id} has no large or full-frame shot`);
  });
  if (chapters.length > RULES.maxChapters) fail('chapter-count', `${chapters.length} chapters; ceiling ${RULES.maxChapters}`);
  if (chapters.length) {
    const last = chapters[chapters.length - 1];
    if (Math.abs(last.endFrame - sumFrames) > 1) {
      fail('chapter-cover', `the last chapter ends at ${last.endFrame}; the shots end at ${sumFrames}`);
    }
  }

  if (cueSheet) {
    const cueIds = (cueSheet.cues ?? []).map((cue) => cue.id);
    const shotIds = shots.map((shot) => shot.id);
    if (cueIds.length !== shotIds.length || cueIds.some((id, index) => id !== shotIds[index])) {
      const first = cueIds.findIndex((id, index) => id !== shotIds[index]);
      fail('cue-coverage', `shots and cues differ at position ${first + 1}: cue ${cueIds[first] ?? 'none'}, shot ${shotIds[first] ?? 'none'}`);
    }
  }

  if (metrics) {
    if (propsSha256 && metrics.propsSha256 && String(metrics.propsSha256).toUpperCase() !== String(propsSha256).toUpperCase()) {
      fail('metrics-binding', 'the metrics receipt was measured against different props');
    }
    const facts = metricsFacts(metrics);
    if (facts.longestStaticSeconds > RULES.maxStaticRunSeconds) {
      fail(
        'static-run',
        `the picture holds still for ${facts.longestStaticSeconds.toFixed(2)}s; the ceiling is ${RULES.maxStaticRunSeconds}s — give the verb its action, do not add drifting`,
      );
    }
    if (facts.emptySeconds > 1.5) {
      fail(
        'empty-frame',
        `an empty stretch runs ${facts.emptySeconds.toFixed(2)}s: the hero falls under 15% of frame height, so the frame has no subject`,
      );
    }
    const smallHero = 0.1528 * Number(film.height ?? 1000);
    if (facts.heroMedianPx && facts.heroMedianPx < smallHero) {
      warn('hero-small', `the median hero is ${facts.heroMedianPx.toFixed(0)}px; ${smallHero.toFixed(0)}px is the floor at this height`);
    }
    if (facts.debris > 10) warn('debris', `${facts.debris} small components compete with the hero`);
  } else if (requireMetrics) {
    fail('metrics-missing', 'no frame-metrics receipt was supplied');
  } else {
    warn('metrics-missing', 'no measured frames: composition, static runs and hold are unverified');
  }

  if (encoded) {
    if (!encoded.probed) {
      warn('encoded-unprobed', 'ffprobe is unavailable, so the encoded duration was not checked');
    } else if (Math.abs(encoded.seconds - Number(props.totalSeconds ?? 0)) > 0.25) {
      fail('encoded-duration', `the encoded film is ${encoded.seconds.toFixed(2)}s; the props are ${Number(props.totalSeconds).toFixed(2)}s`);
    }
    if (encoded.sha256 && encoded.sha256 === propsSha256) {
      fail('encoded-binding', 'the encoded file hash equals the props hash; the receipt is bound to the wrong file');
    }
  }

  if (strict && warnings.length) {
    for (const warning of warnings) failed.push({ ...warning, rule: `${warning.rule}-strict` });
  }
  return { ok: failed.length === 0, failed, warnings };
};

const probeDuration = (file) => {
  const probe = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'json', file], {
    windowsHide: true,
    encoding: 'utf8',
  });
  if (probe.status !== 0) return null;
  try {
    return Number(JSON.parse(probe.stdout).format.duration);
  } catch {
    return null;
  }
};

const isMain = Boolean(process.argv[1]) && resolve(process.argv[1]).replace(/\\/g, '/').endsWith('validate-explainer-release.mjs');
if (isMain) {
  const argv = process.argv.slice(2);
  const jobRoot = argv.find((arg) => !arg.startsWith('--'));
  if (!jobRoot) {
    console.error('Usage: node validate-explainer-release.mjs <jobRoot> [--props P] [--metrics P] [--encoded P] [--require-metrics] [--strict]');
    process.exit(1);
  }
  const root = resolve(jobRoot);
  const propsPath = resolve(root, flag(argv, '--props', 'picture/explainer-props.json'));
  const metricsFlag = flag(argv, '--metrics', null);
  const metricsPath = metricsFlag ? resolve(root, metricsFlag) : resolve(root, 'qa/explainer-frame-metrics.json');
  const encodedPath = flag(argv, '--encoded', null);
  const errors = [];
  let props = null;
  let propsSha256 = null;
  if (!existsSync(propsPath)) {
    errors.push(`props file is missing: ${propsPath}`);
  } else {
    const bytes = readFileSync(propsPath);
    propsSha256 = sha256(bytes);
    try {
      props = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
    } catch (error) {
      errors.push(`props file is not JSON: ${error.message}`);
    }
  }
  const cuePath = join(root, 'story/cue-sheet.json');
  const cueSheet = existsSync(cuePath) ? readJson(cuePath) : null;
  const metrics = existsSync(metricsPath) ? readJson(metricsPath) : null;
  let encoded = null;
  if (encodedPath) {
    const file = resolve(root, encodedPath);
    if (!existsSync(file)) errors.push(`encoded file is missing: ${file}`);
    else {
      const bytes = readFileSync(file);
      const seconds = probeDuration(file);
      encoded = { sha256: sha256(bytes), bytes: bytes.length, seconds: seconds ?? 0, probed: seconds !== null };
    }
  }
  const verdict = props
    ? judge({
        props,
        propsSha256,
        cueSheet,
        metrics,
        encoded,
        requireMetrics: has(argv, '--require-metrics'),
        strict: has(argv, '--strict'),
      })
    : { ok: false, failed: [], warnings: [] };
  const report = {
    schema: 'media-studio/explainer-release/1',
    generator: 'media-studio/validate-explainer-release',
    ok: errors.length === 0 && verdict.ok,
    props: propsPath.slice(root.length + 1).replace(/\\/g, '/'),
    propsSha256,
    filmId: props?.film?.id ?? null,
    shots: props?.shots?.length ?? 0,
    chapters: props?.film?.chapters?.length ?? 0,
    totalSeconds: props?.totalSeconds ?? null,
    metricsMeasured: Boolean(metrics),
    metricsSha256: metrics ? sha256(readFileSync(metricsPath)) : null,
    encoded,
    failed: [...errors.map((message) => ({ rule: 'input', message })), ...verdict.failed],
    warnings: verdict.warnings,
  };
  const outPath = resolve(root, 'qa/explainer-release.json');
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ ok: report.ok, failed: report.failed.length, warnings: report.warnings.length, report: outPath }));
  for (const entry of report.failed) console.error(`[explainer-release] ${entry.rule}${entry.shotId ? ` ${entry.shotId}` : ''}: ${entry.message}`);
  process.exit(report.ok ? 0 : 1);
}
