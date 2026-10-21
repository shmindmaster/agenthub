#!/usr/bin/env node
// Narration check: fail a script that spends the viewer's seconds on anything but information. It enforces the
// owner's standing rules: no fluff, the feed test (the hook wins in five seconds), nothing redundant, no talk of
// versions or how the film was made, and synthetic data disclosed on screen, never in narration.
//
// Usage: node validate-narration.mjs <jobRoot> [--before story/screenplay.draft.json] [--out qa/narration-check.json] [--wpm 150]
//
// Inputs (all under <jobRoot>):
//   story/screenplay.json           scenes[].id + narration; top-level hook, viewerPromise, syntheticDisclosure,
//                                   narrationAllowlist [{ phrase, reason }], wpm
//   story/narration-timeline.json   { durationSeconds, segments:[{ id, scene, text }] }. Runtime source when present;
//                                   the narration source when screenplay.json is absent (marketing cuts).
//   story/screenplay.draft.json     optional (or --before): the writer's draft, for the words-cut report
//   job.json                        optional: syntheticData, dataClass, syntheticDisclosure
//
// Lines are sentences. Each banned phrase is a hit (class, match, line, scene); each hit is an error. The report
// (qa/narration-check.json) is bound to the exact files it read by sha256, so write-story-review.py can tell when it is
// stale. Exit 1 on any error. Allowlisted phrases suppress only jargon, filler and version hits and need a reason.
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve, relative, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const libPath = [join(scriptDir, 'sync-lib.mjs'), join(scriptDir, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
if (!libPath) { console.error('sync-lib.mjs not found beside this script or in ../kit/screencast'); process.exit(2); }
const L = await import(pathToFileURL(libPath).href);

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
const jobRoot = pos[0];
if (!jobRoot) { console.error('Usage: node validate-narration.mjs <jobRoot> [--before story/screenplay.draft.json] [--out qa/narration-check.json] [--wpm 150]'); process.exit(1); }
const root = resolve(jobRoot);
const abs = (p) => (isAbsolute(p) ? p : join(root, p));
const outPath = abs(flag('--out', 'qa/narration-check.json'));
const rel = (p) => relative(root, p).replace(/\\/g, '/');
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, ''));
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const ref = (p) => ({ path: rel(p), sha256: sha(p) });
const round = (v, places = 2) => (Number.isFinite(v) ? Math.round(v * 10 ** places) / 10 ** places : v);

const errors = [];
const warnings = [];

// ---- the banned phrases: word-bounded, case-insensitive ------------------------------------------------------------
const rx = (source, flags = 'gi') => new RegExp(source, flags);
const BANNED = {
  greeting: [
    '\\bhello\\b', '\\b(?:hi there|hey everyone|hey there|hi|hey)\\b', '\\bwelcome(?: back)?\\b',
    '\\bthanks? (?:for|you for) (?:watching|joining|listening|tuning in)\\b', '\\bthank you for (?:watching|joining|listening)\\b',
    '\\bmy name is\\b',
  ].map((s) => rx(s)).concat(rx("\\bI['’]m [A-Z][a-z]+ and\\b", 'g')),
  meta: [
    '\\bin this (?:video|film|demo|clip)\\b', "\\btoday,? (?:we['’]ll|we will|i['’]ll|i will)\\b", "\\blet['’]?s take a look\\b",
    '\\blet me show you\\b', "\\blet['’]?s dive in\\b", '\\bas you can see\\b', '\\bhere you can see\\b',
    "\\b(?:now|next|first|finally),? (?:we|i)(?:['’]ll| will)?\\b", "\\bwhat we['’]ll cover\\b", '\\bwithout further ado\\b',
  ].map((s) => rx(s)),
  recap: [
    '\\bto recap\\b', '\\bin summary\\b', '\\bto sum up\\b', '\\bas we saw\\b', '\\bas mentioned\\b', '\\bas i said\\b',
    "\\bso that['’]s\\b", '\\bthat was\\b', "\\bwe['’]ve seen\\b",
  ].map((s) => rx(s)),
  process: [
    '\\bwe built this\\b', '\\bthis was (?:recorded|captured|rendered)\\b', '\\bthis (?:scene|take|shot|cut)\\b', '\\bthe narration\\b',
    '\\bvoice-?over\\b', '\\bfootage\\b', '\\bbehind the scenes\\b', '\\bthis film was made\\b',
  ].map((s) => rx(s)),
  version: [
    '\\bversions?\\b', '\\bv\\d+\\b', '\\brevisions?\\b', '\\brevised\\b', '\\bupdated since\\b', '\\bsince last time\\b',
    '\\bwhat changed\\b', "\\bwhat['’]s new\\b", '\\bpreviously\\b', '\\b(?:the )?(?:old|new) cut\\b', '\\bchangelog\\b',
    '\\brelease notes\\b', '\\biterations?\\b', '\\bbuild \\d+\\b', '\\blatest build\\b',
  ].map((s) => rx(s)),
  synthetic: [
    '\\bsynthetic\\b', '\\bdemo data\\b', '\\bsample data\\b', '\\btest data\\b', '\\bfake\\b', '\\bdummy\\b', '\\bplaceholder\\b',
    '\\bmade-?up\\b', '\\bfictional\\b', '\\bnot real\\b', '\\bfor demonstration purposes\\b',
  ].map((s) => rx(s)),
  jargon: [
    '\\bleverag(?:e|es|ed|ing)\\b', '\\bseamless(?:ly)?\\b', '\\brobust\\b', '\\bcutting[- ]edge\\b', '\\bstate[- ]of[- ]the[- ]art\\b',
    '\\bbest[- ]in[- ]class\\b', '\\bsynerg\\w*', '\\bparadigms?\\b', '\\bgame[- ]chang(?:er|ers|ing)\\b', '\\bnext[- ]generation\\b',
    '\\bholistic(?:ally)?\\b', '\\bstreamlin(?:e|es|ed|ing)\\b', '\\bempower(?:s|ed|ing)?\\b', '\\bunlock(?:s|ed|ing)?\\b',
    '\\brevolutioni\\w*', '\\bpowerful\\b', '\\bintuitive(?:ly)?\\b', '\\bworld[- ]class\\b', '\\bend[- ]to[- ]end\\b', '\\bturnkey\\b',
    '\\bfrictionless(?:ly)?\\b',
  ].map((s) => rx(s)),
  filler: [
    '\\bjust\\b', '\\breally\\b', '\\bvery\\b', '\\bactually\\b', '\\bbasically\\b', '\\bsimply\\b', '\\beasily\\b', '\\bkind of\\b',
    '\\bsort of\\b', '\\byou know\\b', '\\bgo ahead and\\b', '\\bobviously\\b', '\\bof course\\b', '\\bliterally\\b',
  ].map((s) => rx(s)),
};
// Only these classes may be allowlisted: a quoted product name can carry a jargon word, a greeting is never earned.
const ALLOWLISTABLE = new Set(['jargon', 'filler', 'version']);
const REDUNDANT_OVERLAP = 0.7;
const REDUNDANT_MIN_WORDS = 3;
const NO_NEW_INFO_MIN_WORDS = 4;
const HOOK_SECONDS = 5;

const flat = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();
const SENTENCE_BREAK = /(?<=[.!?]["'”’)\]]*)\s+/;
const sentences = (text) => flat(text).split(SENTENCE_BREAK).map((s) => s.trim()).filter((s) => L.textWords(s).length);
const contentWords = (text) => [...new Set(L.textWords(text).filter(L.isContentWord).map(L.norm))];
const overlap = (words, pool) => (words.length ? words.filter((w) => pool.some((p) => L.wordMatches(w, p))).length / words.length : 0);
const phraseKey = (s) => flat(s).toLowerCase().replace(/[’‘]/g, "'");

/** { sceneId, line } for every sentence of a screenplay or a narration timeline. */
function linesOf(doc) {
  const out = [];
  const add = (sceneId, text) => { for (const line of sentences(text)) out.push({ sceneId, line }); };
  if (Array.isArray(doc?.scenes)) for (const s of doc.scenes) add(s.id ?? s.slug ?? '?', s.narration);
  else if (Array.isArray(doc?.segments)) for (const s of doc.segments) add(s.scene ?? s.id ?? '?', s.text);
  return out;
}
const lineKey = (line) => { const c = contentWords(line); return (c.length ? c : L.textWords(line).map(L.norm)).join(' '); };

// ---- inputs --------------------------------------------------------------------------------------------------------
const screenplayPath = join(root, 'story', 'screenplay.json');
const timelinePath = join(root, 'story', 'narration-timeline.json');
const jobPath = join(root, 'job.json');
const beforeFlag = flag('--before');
const draftPath = beforeFlag ? abs(beforeFlag) : join(root, 'story', 'screenplay.draft.json');
const inputs = {};
const loadJson = (p, label) => { try { return readJson(p); } catch (e) { errors.push(`${label}: cannot parse ${rel(p)}: ${e.message}`); return null; } };

const screenplay = existsSync(screenplayPath) ? loadJson(screenplayPath, 'screenplay') : null;
const timeline = existsSync(timelinePath) ? loadJson(timelinePath, 'timeline') : null;
const job = existsSync(jobPath) ? loadJson(jobPath, 'job') : null;
let lines = [];
let source = null;
if (screenplay) { source = 'screenplay'; inputs.screenplay = ref(screenplayPath); lines = linesOf(screenplay); }
else if (timeline) { source = 'timeline'; lines = linesOf(timeline); }
if (timeline) inputs.timeline = ref(timelinePath);
if (job) inputs.job = ref(jobPath);
if (!source && !errors.length) errors.push('no narration to check: story/screenplay.json and story/narration-timeline.json are both absent');
if (source && !lines.length) errors.push(`${source === 'screenplay' ? 'story/screenplay.json' : 'story/narration-timeline.json'} has no narration lines`);
if (source === 'timeline') warnings.push('story/screenplay.json is absent: checked story/narration-timeline.json segments instead');

const wpmFlag = Number(flag('--wpm'));
const wpm = Number.isFinite(wpmFlag) && wpmFlag > 0 ? wpmFlag : (Number(screenplay?.wpm) >= 60 ? Number(screenplay.wpm) : 150);
const words = lines.reduce((n, l) => n + L.textWords(l.line).length, 0);
const timelineSeconds = Number(timeline?.durationSeconds);
const runtimeSeconds = Number.isFinite(timelineSeconds) && timelineSeconds > 0 ? timelineSeconds : round((words / wpm) * 60);
const runtimeSource = Number.isFinite(timelineSeconds) && timelineSeconds > 0 ? 'timeline.durationSeconds' : 'words/wpm';

// ---- allowlist -----------------------------------------------------------------------------------------------------
const allowEntries = [...(Array.isArray(screenplay?.narrationAllowlist) ? screenplay.narrationAllowlist : []),
  ...(Array.isArray(job?.narrationAllowlist) ? job.narrationAllowlist : [])];
const allow = new Map();
allowEntries.forEach((e, i) => {
  const phrase = phraseKey(e?.phrase);
  if (!phrase) { errors.push(`narrationAllowlist: entry ${i + 1} has no phrase`); return; }
  if (!flat(e?.reason)) { errors.push(`narrationAllowlist: "${e.phrase}" has no reason; an allowlisted phrase must say why it earns its seconds`); return; }
  allow.set(phrase, flat(e.reason));
});

// ---- fluff scan ----------------------------------------------------------------------------------------------------
const hits = [];
const allowlisted = [];
const seen = [];          // content-word lists of earlier lines; seen[i] belongs to lines[i]
const seenPool = [];      // every content word spoken so far
for (const { sceneId, line } of lines) {
  const text = line.replace(/[’‘]/g, "'");
  const lineHits = [];
  for (const [cls, list] of Object.entries(BANNED)) {
    for (const re of list) {
      re.lastIndex = 0;
      for (const m of text.matchAll(re)) lineHits.push({ index: m.index, sceneId, class: cls, match: m[0], line });
    }
  }
  // A phrase two patterns both catch (hi / hi there) is one hit: keep the longer match at the same spot.
  lineHits.sort((a, b) => a.index - b.index || b.match.length - a.match.length);
  let last = -1;
  for (const h of lineHits) {
    if (h.index < last) continue;
    last = h.index + h.match.length;
    const reason = ALLOWLISTABLE.has(h.class) ? allow.get(phraseKey(h.match)) : undefined;
    if (reason) allowlisted.push({ sceneId, class: h.class, match: h.match, line, reason });
    else hits.push({ sceneId, class: h.class, match: h.match, line });
  }
  const cw = contentWords(line);
  const redundantWith = cw.length >= REDUNDANT_MIN_WORDS ? seen.findIndex((prev) => overlap(cw, prev) >= REDUNDANT_OVERLAP) : -1;
  if (redundantWith >= 0) {
    hits.push({ sceneId, class: 'redundant', match: `${Math.round(overlap(cw, seen[redundantWith]) * 100)}% of its content words repeat ${lines[redundantWith].sceneId}`, line });
  } else if (cw.length >= NO_NEW_INFO_MIN_WORDS && cw.every((w) => seenPool.some((p) => L.wordMatches(w, p)))) {
    hits.push({ sceneId, class: 'no-new-information', match: 'every content word was already spoken', line });
  }
  seen.push(cw);
  cw.forEach((w) => seenPool.push(w));
}
for (const h of hits) errors.push(`${h.sceneId} ${h.class}: "${h.match}" in "${h.line}"`);

const hitLines = new Set(hits.map((h) => `${h.sceneId}\u0000${h.line}`));
const secondsSpent = round([...hitLines].reduce((n, k) => n + L.textWords(k.split('\u0000')[1]).length, 0) / wpm * 60);
const perMinute = runtimeSeconds > 0 ? round(hits.length / (runtimeSeconds / 60)) : 0;
const fluff = { perMinute, count: hits.length, secondsSpent, hits, allowlisted };

// ---- hook and promise: the first five seconds -----------------------------------------------------------------------
const hookMaxWords = Math.floor((HOOK_SECONDS * wpm) / 60); // 12 at 150 wpm (Math.round would give 13)
const firstSentence = lines[0]?.line ?? '';
const hookWords = L.textWords(firstSentence).length;
const hookSeconds = round((hookWords / wpm) * 60);
let hookOk = !!firstSentence && hookWords <= hookMaxWords;
if (firstSentence && !hookOk) {
  errors.push(`hook-5s: the first sentence is ${hookWords} words (${hookSeconds} s at ${wpm} wpm); the hook must fit ${HOOK_SECONDS} s, at most ${hookMaxWords} words: "${firstSentence}"`);
}
const promiseText = flat(screenplay?.viewerPromise) || flat(screenplay?.scenes?.[0]?.wiifm);
let promiseNamed = null;
if (!promiseText) {
  if (source) warnings.push('promise-5s skipped: no viewerPromise and no first-scene wiifm to check the opening against');
} else {
  const windowWords = L.textWords(lines.map((l) => l.line).join(' ')).slice(0, hookMaxWords);
  const promiseWords = contentWords(promiseText);
  promiseNamed = windowWords.some((w) => promiseWords.some((p) => L.wordMatches(w, p)));
  if (!promiseNamed) errors.push(`promise-5s: none of the promise's content words (${promiseWords.join(', ')}) is spoken in the first ${HOOK_SECONDS} seconds (${windowWords.length} words): "${windowWords.join(' ')}"`);
}
const hook = { firstSentence, words: hookWords, seconds: hookSeconds, ok: hookOk, promiseNamed };

// ---- synthetic data: a caption or an end card, never narration -------------------------------------------------------
const disclosure = screenplay?.syntheticDisclosure ?? job?.syntheticDisclosure ?? null;
const declaredSynthetic = job?.syntheticData === true || /synthetic/i.test(String(job?.dataClass ?? ''));
const disclosureRequired = declaredSynthetic || !!disclosure;
const mode = disclosure?.mode ?? null;
const disclosureText = flat(disclosure?.text);
const disclosureOk = !disclosureRequired || ((mode === 'caption' || mode === 'end-card') && !!disclosureText);
if (!disclosureOk) {
  const why = !disclosure ? 'no syntheticDisclosure is declared'
    : mode === 'none' ? 'syntheticDisclosure.mode is "none"'
    : (mode !== 'caption' && mode !== 'end-card') ? `syntheticDisclosure.mode "${mode}" is not caption or end-card` : 'syntheticDisclosure.text is empty';
  errors.push(`synthetic-disclosure: ${why}; truth needs a caption or end card, never narration`);
}
const syntheticDisclosure = { required: disclosureRequired, mode, text: disclosureText || null, ok: disclosureOk };

// ---- words cut ------------------------------------------------------------------------------------------------------
let wordsCut = { draft: null, note: 'no draft to compare' };
if (existsSync(draftPath)) {
  const draftDoc = loadJson(draftPath, 'draft');
  if (draftDoc) {
    inputs.draft = ref(draftPath);
    const before = linesOf(draftDoc);
    const after = lines;
    const afterKeys = new Set(after.map((l) => lineKey(l.line)));
    const beforeKeys = new Set(before.map((l) => lineKey(l.line)));
    const countWords = (ls) => ls.reduce((n, l) => n + L.textWords(l.line).length, 0);
    const wordsBefore = countWords(before);
    wordsCut = {
      draft: inputs.draft,
      wordsBefore,
      wordsAfter: words,
      runtimeBasis: 'words/wpm',
      runtimeBeforeSeconds: round((wordsBefore / wpm) * 60),
      runtimeAfterSeconds: round((words / wpm) * 60),
      linesRemoved: before.filter((l) => !afterKeys.has(lineKey(l.line))).map(({ sceneId, line }) => ({ sceneId, line })),
      linesAdded: after.filter((l) => !beforeKeys.has(lineKey(l.line))).map(({ sceneId, line }) => ({ sceneId, line })),
      linesKept: after.filter((l) => beforeKeys.has(lineKey(l.line))).length,
    };
  }
} else if (beforeFlag) {
  errors.push(`--before ${beforeFlag}: file not found`);
}

// ---- report ---------------------------------------------------------------------------------------------------------
const report = {
  generator: 'media-studio/validate-narration',
  schemaVersion: '1.0.0',
  ok: errors.length === 0,
  errors,
  warnings,
  inputs,
  thresholds: { wpm, hookSeconds: HOOK_SECONDS, hookMaxWords, redundantOverlap: REDUNDANT_OVERLAP, redundantMinContentWords: REDUNDANT_MIN_WORDS, noNewInformationMinContentWords: NO_NEW_INFO_MIN_WORDS },
  source,
  wpm,
  runtimeSeconds,
  runtimeSource,
  words,
  lines: lines.length,
  hook,
  fluff,
  syntheticDisclosure,
  wordsCut,
};
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(report, null, 2));

const cut = wordsCut.draft ? wordsCut : null;
console.log(JSON.stringify({
  ok: report.ok,
  out: rel(outPath),
  fluffPerMinute: perMinute,
  hits: hits.length,
  runtimeBeforeSeconds: cut ? cut.runtimeBeforeSeconds : null,
  runtimeAfterSeconds: cut ? cut.runtimeAfterSeconds : runtimeSeconds,
  linesRemoved: cut ? cut.linesRemoved.length : null,
  errors,
  warnings,
}, null, 2));
if (errors.length) process.exit(1);
