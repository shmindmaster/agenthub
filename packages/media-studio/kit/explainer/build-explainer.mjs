#!/usr/bin/env node
// Build the Explainer composition props from the cue sheet, the accepted takes
// and the explainer plan, with every beat pinned to a spoken word.
//
//   node build-explainer.mjs <jobRoot> [--plan story/explainer-plan.json]
//                            [--out picture/explainer-props.json] [--fps 30]
//
// Inputs (all under the job root):
//   story/cue-sheet.json        cues[{id,start,end,gapAfter,text}], totalSeconds
//   takes/<cueId>.receipt.json  word_boundaries[{text,start_seconds,boundary_type}]
//   story/explainer-plan.json   { film, chapters, shots }  (see the schema)
//
// The plan chooses the archetype per cue and carries the visual payload. This
// script owns the clock: it resolves "@word" anchors, assigns chapters, derives
// each shot's beats and landing hold, and refuses a film that cannot be cut to
// the voice. It writes no props when anything fails.
//
// No network, no spend.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { anchorSeconds, resolveAnchors, sceneEdges, timeKeyAt, wordsOf } from './anchor.mjs';
import { checkShotLayout } from './fit.mjs';
import { familyOf, FAMILIES, RULES, validateShot, beatFitsShot } from './grammar.mjs';
import { theme } from './theme.mjs';

export const PLAN_SCHEMA = 'media-studio/explainer-plan/1';
export const PROPS_SCHEMA = 'media-studio/explainer-film/1';

const flag = (argv, name, fallback = null) => {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : fallback;
};

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));

/** Every beat inside the resolved visual, with the path that carries it. */
export const collectBeats = (node, path = 'visual', out = []) => {
  if (Array.isArray(node)) {
    node.forEach((item, index) => collectBeats(item, `${path}[${index}]`, out));
  } else if (node && typeof node === 'object') {
    for (const [key, value] of Object.entries(node)) {
      if (key === timeKeyAt(path) && typeof value === 'number') out.push({ target: path, atSeconds: value });
      else collectBeats(value, `${path}.${key}`, out);
    }
  }
  return out;
};

/**
 * Structural checks that need the cue sheet: one shot per cue, chapters in cue
 * order, no orphans. Timing is checked per shot later, once the clock is known.
 */
export const validatePlan = (plan, cueSheet) => {
  const errors = [];
  const fail = (code, message) => errors.push({ code, message });
  if (!plan || typeof plan !== 'object') {
    fail('plan-shape', 'the plan is not an object');
    return errors;
  }
  if (!plan.film || !plan.film.title) fail('film-title', 'film.title is required');
  if (!Array.isArray(plan.shots) || !plan.shots.length) fail('shots-empty', 'shots[] is empty');
  if (!Array.isArray(plan.chapters) || !plan.chapters.length) fail('chapters-empty', 'chapters[] is empty');
  const cues = cueSheet?.cues ?? [];
  if (!cues.length) fail('cues-empty', 'story/cue-sheet.json has no cues');
  const shotIds = new Set();
  for (const shot of plan.shots ?? []) {
    if (!shot.id) fail('shot-id', 'a shot has no id');
    else if (shotIds.has(shot.id)) fail('shot-duplicate', `shot ${shot.id} appears twice`);
    else shotIds.add(shot.id);
    if (!familyOf(shot.archetype, shot.visual?.kind)) fail('archetype-known', `${shot.id}: unknown archetype "${shot.archetype}"`);
  }
  const cueIds = new Set(cues.map((cue) => cue.id));
  for (const cue of cues) if (!shotIds.has(cue.id)) fail('shot-missing', `cue ${cue.id} has no shot`);
  for (const shot of plan.shots ?? []) if (!cueIds.has(shot.id)) fail('cue-missing', `shot ${shot.id} has no cue`);

  const chapterShotOrder = [];
  for (const chapter of plan.chapters ?? []) {
    if (!chapter.id || !chapter.label) fail('chapter-shape', 'every chapter needs an id and a label');
    if (!Array.isArray(chapter.shots) || !chapter.shots.length) fail('chapter-shots', `chapter ${chapter.id} has no shots`);
    for (const id of chapter.shots ?? []) chapterShotOrder.push(id);
  }
  const counted = new Set();
  for (const id of chapterShotOrder) {
    if (counted.has(id)) fail('chapter-duplicate', `shot ${id} is in more than one chapter`);
    counted.add(id);
    if (!shotIds.has(id)) fail('chapter-unknown', `chapter names unknown shot ${id}`);
  }
  for (const shot of plan.shots ?? []) if (!counted.has(shot.id)) fail('chapter-missing', `shot ${shot.id} is in no chapter`);
  const cueOrder = cues.map((cue) => cue.id);
  if (chapterShotOrder.length === cueOrder.length) {
    const firstMismatch = cueOrder.findIndex((id, index) => chapterShotOrder[index] !== id);
    if (firstMismatch >= 0) {
      fail(
        'chapter-order',
        `chapters must partition the film in cue order: expected ${cueOrder[firstMismatch]} at position ${firstMismatch + 1}, found ${chapterShotOrder[firstMismatch]}`,
      );
    }
  }
  return errors;
};

/**
 * The whole build as a pure function: no disk, no clock, no randomness.
 * Returns the props the Explainer composition renders and a receipt report.
 */
export const buildExplainer = ({ cueSheet, receipts, plan, fps = 30, width = theme.canvas.width, height = theme.canvas.height, voiceoverFile }) => {
  const errors = validatePlan(plan, cueSheet).map((entry) => `${entry.code}: ${entry.message}`);
  const warnings = [];
  if (errors.length) return { ok: false, props: null, report: { ok: false, errors, warnings }, errors };

  const cues = cueSheet.cues;
  const edges = sceneEdges(cueSheet);
  const totalFrames = Math.round(edges[edges.length - 1] * fps);
  const byId = Object.fromEntries(plan.shots.map((shot) => [shot.id, shot]));
  const chapterOf = {};
  for (const chapter of plan.chapters) for (const id of chapter.shots) chapterOf[id] = chapter;

  const shots = cues.map((cue, index) => {
    const planShot = byId[cue.id];
    const family = familyOf(planShot.archetype, planShot.visual?.kind);
    const startFrame = Math.round(edges[index] * fps);
    const endFrame = Math.round(edges[index + 1] * fps);
    const durationFrames = Math.max(1, endFrame - startFrame);
    const durationSeconds = durationFrames / fps;
    const sceneStart = startFrame / fps;
    const words = wordsOf(receipts[cue.id]);
    const cueStart = cue.start ?? 0;
    const anchorErrors = [];
    const resolved = planShot.visual
      ? resolveAnchors(
          planShot.visual,
          (spec) => anchorSeconds({ spec, cueStart, words, sceneStart, fps, snap: true }),
          anchorErrors,
          `shot ${cue.id} visual`,
        )
      : undefined;
    for (const message of anchorErrors) errors.push(`${cue.id}: ${message}`);

    const beats = collectBeats(resolved);
    const titleAt = 0.15;
    const heroAtSeconds = beats.length ? Math.min(...beats.map((beat) => beat.atSeconds)) : titleAt;
    const lastBeat = beats.length ? Math.max(...beats.map((beat) => beat.atSeconds)) : titleAt;
    const holdSeconds = Math.max(0, +(durationSeconds - lastBeat).toFixed(3));

    if (beats.some((beat) => !beatFitsShot(beat.atSeconds, fps, durationFrames))) {
      errors.push(`${cue.id}: a beat lands at or after the end of a ${durationSeconds.toFixed(2)}s shot`);
    }
    const firstMotion = planShot.title || planShot.kicker || planShot.sub ? titleAt : heroAtSeconds;
    if (firstMotion > RULES.firstBeatMaxSeconds) {
      warnings.push(`${cue.id}: nothing moves until ${firstMotion.toFixed(2)}s; the first entrance must land by ${RULES.firstBeatMaxSeconds}s`);
    }
    if (heroAtSeconds > RULES.heroMaxSeconds) {
      warnings.push(`${cue.id}: the hero does not appear until ${heroAtSeconds.toFixed(2)}s; the ceiling is ${RULES.heroMaxSeconds}s`);
    }
    if (holdSeconds < RULES.minHoldSeconds) {
      warnings.push(
        `${cue.id}: lands and cuts — ${holdSeconds.toFixed(2)}s hold after the last beat, the floor is ${RULES.minHoldSeconds}s`,
      );
    }
    const needsTitle = ['statement', 'number', 'contrast', 'mechanism', 'layers', 'timeline', 'evidence', 'checklist'].includes(family);
    if (needsTitle && !planShot.title) errors.push(`${cue.id}: ${planShot.archetype} needs a title (the line the shot is about)`);

    const structural = validateShot({ ...planShot, visual: resolved, durationSeconds, beats }, {
      advisory: (rule, message) => warnings.push([cue.id, rule, message].join(': ')),
    });
    for (const problem of structural) errors.push(`${cue.id}: ${problem.rule}: ${problem.message}`);

    // Only a shot the grammar accepts has a composition to measure.
    if (!structural.length) {
      try {
        const layout = checkShotLayout({ ...planShot, family, visual: resolved }, { width, height });
        for (const message of layout.errors) errors.push(`${cue.id}: ${message}`);
        for (const message of layout.warnings) warnings.push(`${cue.id}: ${message}`);
      } catch (error) {
        errors.push(`${cue.id}: layout: the ${resolved?.kind ?? family} cannot be laid out: ${error.message}`);
      }
    }

    return {
      id: cue.id,
      archetype: planShot.archetype,
      family,
      chapterId: chapterOf[cue.id]?.id ?? '',
      startSeconds: +(startFrame / fps).toFixed(6),
      durationSeconds: +durationSeconds.toFixed(6),
      startFrame,
      durationFrames,
      ...(planShot.kicker ? { kicker: planShot.kicker } : {}),
      ...(planShot.title ? { title: planShot.title } : {}),
      ...(planShot.sub ? { sub: planShot.sub } : {}),
      ...(planShot.accent ? { accent: planShot.accent } : {}),
      chrome: planShot.chrome ?? FAMILIES[family].chrome,
      ...(resolved ? { visual: resolved } : {}),
      ...(planShot.visualScale ? { visualScale: planShot.visualScale } : {}),
      ...(planShot.repeatIsPoint ? { repeatIsPoint: true } : {}),
      ...(planShot.longShotReason ? { longShotReason: planShot.longShotReason } : {}),
      heroAtSeconds: +heroAtSeconds.toFixed(3),
      holdSeconds,
      beats: beats
        .sort((a, b) => a.atSeconds - b.atSeconds)
        .map((beat) => ({ target: beat.target, atSeconds: beat.atSeconds, frame: Math.round(beat.atSeconds * fps) })),
    };
  });

  const chapters = plan.chapters.map((chapter) => {
    const members = shots.filter((shot) => shot.chapterId === chapter.id);
    const startFrame = members[0]?.startFrame ?? 0;
    const last = members[members.length - 1];
    const endFrame = last ? last.startFrame + last.durationFrames : startFrame;
    return {
      id: chapter.id,
      label: chapter.label,
      startSeconds: +(startFrame / fps).toFixed(6),
      endSeconds: +(endFrame / fps).toFixed(6),
      startFrame,
      endFrame,
    };
  });

  const sumFrames = shots.reduce((sum, shot) => sum + shot.durationFrames, 0);
  if (Math.abs(sumFrames - totalFrames) > 1) {
    errors.push(`shot frames sum to ${sumFrames}; the cue sheet is ${totalFrames}`);
  }
  for (const chapter of chapters) {
    if (chapter.endFrame <= chapter.startFrame) errors.push(`chapter ${chapter.id} is empty`);
  }
  const longEnoughForChapters = totalFrames / fps >= 180;
  for (const chapter of chapters) {
    const seconds = (chapter.endFrame - chapter.startFrame) / fps;
    if (longEnoughForChapters && seconds < RULES.minChapterSeconds) {
      warnings.push(`chapter ${chapter.id} runs ${seconds.toFixed(1)}s; a film over three minutes needs chapters of ${RULES.minChapterSeconds}s or more`);
    }
  }
  if (chapters.length > RULES.maxChapters) {
    warnings.push(`${chapters.length} chapters; the ceiling is ${RULES.maxChapters}`);
  }
  for (const chapter of chapters) {
    const members = shots.filter((shot) => shot.chapterId === chapter.id);
    const hasBig = members.some((shot) => ['l', 'xl'].includes(FAMILIES[shot.family].tier));
    if (!hasBig) warnings.push(`chapter ${chapter.id} has no large or full-frame shot; every chapter needs one`);
  }
  for (let index = 1; index < shots.length; index += 1) {
    if (shots[index].family === shots[index - 1].family && !shots[index].repeatIsPoint) {
      warnings.push(`${shots[index].id}: ${shots[index].family} repeats the previous shot with no repeatIsPoint`);
    }
  }
  const typeOnly = shots.filter((shot) => ['statement', 'quote', 'number'].includes(shot.family)).length;
  if (typeOnly / shots.length > RULES.maxStatementShare) {
    warnings.push(`${typeOnly}/${shots.length} shots are type-only; keep at or under ${Math.round(RULES.maxStatementShare * 100)}%`);
  }

  const film = {
    id: plan.film.id ?? 'film',
    title: plan.film.title,
    ...(plan.film.subtitle ? { subtitle: plan.film.subtitle } : {}),
    backdrop: plan.film.backdrop ?? 'dots',
    width,
    height,
    fps,
    ...(plan.film.accent ? { accent: plan.film.accent } : {}),
    ...(plan.film.chrome ? { chrome: plan.film.chrome } : {}),
    chapters,
  };
  const props = {
    film,
    shots,
    totalSeconds: +(totalFrames / fps).toFixed(6),
    ...(voiceoverFile ?? plan.film.voiceoverFile ? { voiceoverFile: voiceoverFile ?? plan.film.voiceoverFile } : {}),
  };
  const report = {
    schema: 'media-studio/explainer-build/1',
    ok: errors.length === 0,
    filmId: film.id,
    shots: shots.length,
    chapters: chapters.length,
    totalFrames,
    seconds: props.totalSeconds,
    beats: shots.reduce((sum, shot) => sum + shot.beats.length, 0),
    beatsWithoutWordAnchor: shots.filter((shot) => shot.beats.length === 0).length,
    errors,
    warnings,
  };
  return { ok: errors.length === 0, props: errors.length ? null : props, report, errors };
};

/** Disk wrapper: reads the job, writes props and the report, never a partial film. */
export const buildFromJob = (jobRoot, options = {}) => {
  const fps = Number(options.fps ?? 30);
  const planPath = resolve(jobRoot, options.plan ?? 'story/explainer-plan.json');
  const outPath = resolve(jobRoot, options.out ?? 'picture/explainer-props.json');
  const cueSheetPath = resolve(jobRoot, options.cueSheet ?? 'story/cue-sheet.json');
  const cueSheet = readJson(cueSheetPath);
  if (!Array.isArray(cueSheet.cues) || !Number.isFinite(cueSheet.totalSeconds)) {
    throw new Error(`Expected a narration cue sheet with cues[] and totalSeconds at ${cueSheetPath}; the product action EDL is a different clock`);
  }
  const plan = readJson(planPath);
  const receipts = {};
  for (const cue of cueSheet.cues) {
    const receiptPath = join(jobRoot, 'takes', `${cue.id}.receipt.json`);
    receipts[cue.id] = existsSync(receiptPath) ? readJson(receiptPath).word_boundaries ?? [] : [];
  }
  const result = buildExplainer({
    cueSheet,
    receipts,
    plan,
    fps,
    width: Number(options.width ?? theme.canvas.width),
    height: Number(options.height ?? theme.canvas.height),
    voiceoverFile: options.voiceoverFile,
  });
  mkdirSync(dirname(outPath), { recursive: true });
  const reportPath = outPath.replace(/\.json$/, '') + '.report.json';
  writeFileSync(reportPath, JSON.stringify(result.report, null, 2) + '\n');
  if (result.ok) writeFileSync(outPath, JSON.stringify(result.props, null, 2) + '\n');
  return { ...result, outPath, reportPath };
};

const isMain = Boolean(process.argv[1]) && resolve(process.argv[1]).replace(/\\/g, '/').endsWith('build-explainer.mjs');
if (isMain) {
  const argv = process.argv.slice(2);
  const jobRoot = argv.find((arg) => !arg.startsWith('--'));
  if (!jobRoot) {
    console.error('Usage: node build-explainer.mjs <jobRoot> [--plan P] [--cue-sheet P] [--out P] [--fps N] [--width N] [--height N] [--voice P]');
    process.exit(1);
  }
  const result = buildFromJob(resolve(jobRoot), {
    cueSheet: flag(argv, '--cue-sheet', 'story/cue-sheet.json'),
    plan: flag(argv, '--plan', 'story/explainer-plan.json'),
    out: flag(argv, '--out', 'picture/explainer-props.json'),
    fps: flag(argv, '--fps', 30),
    width: flag(argv, '--width', theme.canvas.width),
    height: flag(argv, '--height', theme.canvas.height),
    voiceoverFile: flag(argv, '--voice', undefined),
  });
  console.log(JSON.stringify(result.report));
  if (!result.ok) for (const message of result.errors) console.error(`[explainer] ${message}`);
  process.exit(result.ok ? 0 : 1);
}
