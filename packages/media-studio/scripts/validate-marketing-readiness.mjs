#!/usr/bin/env node
// Marketing-readiness floor on the EXACT encoded candidate. A customer-facing cut competes in a feed against many other
// videos for attention; the bar is "wins the viewer against the references in the first five seconds", not "accurate and
// complete". The reviewer records the rubric verdicts with timestamped evidence in qa/marketing-readiness.json
// (skills/media-studio/references/marketing-readiness.md); this gate holds that file to the floor and measures what it
// can measure (hook inside two seconds, one promise, end card inside the last eight seconds, cuts on the beat grid from
// the real edit decision list, three cited references, the feed verdict). Below the floor the cut cannot release.
//
// Usage: node validate-marketing-readiness.mjs <jobRoot> <candidate.mp4> [--readiness qa/marketing-readiness.json]
//                                              [--cue-sheet plan/cue-sheet.json] [--compose-map <file>]
//                                              [--out qa/marketing-readiness-check.json] [--beat-tolerance-ms 80]
//                                              [--end-card-window 8] [--hook-max 2]
// Applies when job.json is a marketing cut: programForm campaign-flagship | campaign-comparison | campaign-short |
// campaign-outreach | marketing-cutdown | social-clip | hero, kind teaser, or marketing: true. Otherwise the report
// says applies: false and exits 0; explainers and technical stories keep the story rubric and inherit the no-fluff and
// cursor rules through validate-narration.mjs and validate-pointer-path.mjs.
import { existsSync, readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve, relative } from 'node:path';

const argv = process.argv.slice(2);
const VALUE_FLAGS = new Set(['--readiness', '--cue-sheet', '--compose-map', '--out', '--beat-tolerance-ms', '--end-card-window', '--hook-max']);
const pos = []; const opt = {};
for (let i = 0; i < argv.length; i++) { if (VALUE_FLAGS.has(argv[i])) opt[argv[i]] = argv[++i]; else if (argv[i].startsWith('--')) opt[argv[i]] = true; else pos.push(argv[i]); }
const [jobRoot, candidateArg] = pos;
if (!jobRoot || !candidateArg) { console.error('Usage: node validate-marketing-readiness.mjs <jobRoot> <candidate.mp4> [--readiness qa/marketing-readiness.json] [--out qa/marketing-readiness-check.json]'); process.exit(1); }
const root = resolve(jobRoot);
const candidate = resolve(candidateArg);
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, ''));
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const rel = (p) => relative(root, p).replace(/\\/g, '/');
const ref = (p) => (p && existsSync(p) ? { path: rel(p), sha256: sha(p) } : null);
const num = (n, d) => (opt[n] !== undefined ? Number(opt[n]) : d);
const T = { hookMaxSeconds: num('--hook-max', 2), endCardWindowSeconds: num('--end-card-window', 8), beatToleranceMs: num('--beat-tolerance-ms', 80), beatHitRatio: 0.9, referencesRequired: 3 };
const outPath = resolve(root, typeof opt['--out'] === 'string' ? opt['--out'] : 'qa/marketing-readiness-check.json');
const readinessPath = resolve(root, typeof opt['--readiness'] === 'string' ? opt['--readiness'] : 'qa/marketing-readiness.json');
const cuePath = resolve(root, typeof opt['--cue-sheet'] === 'string' ? opt['--cue-sheet'] : 'plan/cue-sheet.json');

export const MARKETING_FORMS = Object.freeze(['campaign-flagship', 'campaign-comparison', 'campaign-short', 'campaign-outreach', 'marketing-cutdown', 'social-clip', 'hero']);
export const isMarketingCut = (job) => job?.marketing === true || job?.kind === 'teaser' || MARKETING_FORMS.includes(job?.programForm);

const errors = []; const warnings = []; const checks = {};
const fail = (check, message) => { checks[check] = 'fail'; errors.push(`${check}: ${message}`); };
const pass = (check, note) => { checks[check] = 'pass'; if (note) checks[`${check}.note`] = note; };
const text = (v, min = 1) => typeof v === 'string' && v.trim().length >= min;

const job = existsSync(join(root, 'job.json')) ? readJson(join(root, 'job.json')) : {};
const applies = isMarketingCut(job);
let candidateRec = null; let duration = null; let readiness = null; let cueSheet = null; let beatMeasurement = null;

if (applies) {
  if (!existsSync(candidate)) fail('candidate', `candidate does not exist: ${candidate}`);
  else {
    candidateRec = { path: rel(candidate), sha256: sha(candidate), bytes: statSync(candidate).size };
    const pr = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', candidate], { encoding: 'utf8', windowsHide: true });
    duration = pr.status === 0 ? Number(String(pr.stdout).trim()) : NaN;
    if (!Number.isFinite(duration)) fail('candidate', 'ffprobe cannot read the candidate duration (ffprobe on PATH is required).');
  }
  if (!existsSync(readinessPath)) fail('readiness', `missing ${rel(readinessPath)}: the reviewer records the marketing rubric verdicts with timestamped evidence (marketing-readiness.md). Silence is not readiness.`);
  else { try { readiness = readJson(readinessPath); } catch (e) { fail('readiness', `cannot read ${rel(readinessPath)}: ${e.message}`); } }
  if (existsSync(cuePath)) { try { cueSheet = readJson(cuePath); } catch (e) { warnings.push(`cannot read cue sheet: ${e.message}`); } }
}

if (applies && readiness && candidateRec) {
  const R = readiness;
  if (R.schema !== 'media-studio/marketing-readiness/1') fail('readiness', `schema must be media-studio/marketing-readiness/1 (got ${R.schema ?? 'none'}).`);
  if (!text(R.reviewer)) fail('readiness', 'reviewer is required: a verdict nobody signed is not a review.');
  if (R.candidate?.sha256 !== candidateRec.sha256 || R.candidate?.bytes !== candidateRec.bytes) fail('candidate-binding', 'readiness review is not bound to this exact candidate SHA-256 and byte count; review the file a viewer will watch.');
  else pass('candidate-binding');

  // 1. Hook inside two seconds: the first thing on screen is the pain or the payoff, measured, not promised.
  const hookAt = Number(R.hook?.atSeconds);
  if (!Number.isFinite(hookAt) || hookAt < 0) fail('hook-2s', 'hook.atSeconds must be the measured time the hook lands on screen.');
  else if (hookAt > T.hookMaxSeconds) fail('hook-2s', `hook lands at ${hookAt}s; the floor is ${T.hookMaxSeconds}s. A feed viewer has left.`);
  else if (R.hook?.verdict !== 'pass' || !text(R.hook?.what, 10)) fail('hook-2s', 'hook needs verdict pass and a sentence saying what is on screen at that moment.');
  else pass('hook-2s', `${hookAt}s: ${R.hook.what}`);

  // 2. One promise.
  if (!text(R.promise?.text)) fail('one-promise', 'promise.text is required: the one thing the viewer can do or stop doing.');
  else if (R.promise?.count !== 1) fail('one-promise', `promise.count must be 1 (got ${R.promise?.count ?? 'none'}); a second promise splits the film.`);
  else if (R.promise?.verdict !== 'pass' || !text(R.promise?.evidence, 10)) fail('one-promise', 'promise needs verdict pass and scene-cited evidence that the film keeps it.');
  else pass('one-promise', R.promise.text);

  // 3. Designed motion and type.
  if (R.motion?.verdict !== 'pass' || !text(R.motion?.evidence, 20)) fail('designed-motion', 'motion needs verdict pass and timestamped evidence (type builds, moves, no static hold a feed would scroll past).');
  else pass('designed-motion');

  // 4. Music bed and sound design carrying the pace.
  if (R.sound?.bed !== true) fail('sound-design', 'sound.bed must be true: a marketing cut carries a music bed under the voice.');
  else if (!(Number(R.sound?.designCues) >= 1)) fail('sound-design', 'sound.designCues must count at least one designed cue (sting, riser, hit on a cut).');
  else if (R.sound?.verdict !== 'pass' || !text(R.sound?.evidence, 10)) fail('sound-design', 'sound needs verdict pass and evidence that the bed and cues carry the pace.');
  else pass('sound-design');

  // 5. Brand kit with end card and CTA, measured inside the last window of the file.
  const endAt = Number(R.brand?.endCardAtSeconds);
  if (!text(R.brand?.kit)) fail('brand-end-card', 'brand.kit must name the brand kit the end card uses.');
  else if (!text(R.brand?.cta, 3)) fail('brand-end-card', 'brand.cta is required: one next step on the end card.');
  else if (!Number.isFinite(endAt)) fail('brand-end-card', 'brand.endCardAtSeconds must be the measured time the end card appears.');
  else if (Number.isFinite(duration) && (endAt > duration || endAt < duration - T.endCardWindowSeconds)) fail('brand-end-card', `end card at ${endAt}s is not inside the last ${T.endCardWindowSeconds}s of a ${duration.toFixed(2)}s file.`);
  else if (R.brand?.verdict !== 'pass') fail('brand-end-card', 'brand needs verdict pass.');
  else pass('brand-end-card', `${R.brand.kit} end card at ${endAt}s: ${R.brand.cta}`);

  // 6. Cuts on the beat: measured from the real edit decision list against the declared grid.
  const bpm = Number(R.cutsOnBeat?.bpm); const offset = Number(R.cutsOnBeat?.offsetSeconds ?? 0);
  let cutTimes = null; let cutSource = null;
  if (cueSheet?.edl?.length) { cutTimes = cueSheet.edl.map((g) => Number(g.startSeconds)).filter((t) => Number.isFinite(t) && t > 0.05); cutSource = ref(cuePath); }
  else if (typeof opt['--compose-map'] === 'string' && existsSync(resolve(root, opt['--compose-map']))) { const cm = readJson(resolve(root, opt['--compose-map'])); cutTimes = (cm.groups || []).map((g) => Number(g.startSeconds)).filter((t) => Number.isFinite(t) && t > 0.05); cutSource = ref(resolve(root, opt['--compose-map'])); }
  let beatResult = null;
  if (!(bpm >= 40 && bpm <= 220)) fail('cuts-on-beat', 'cutsOnBeat.bpm must be the bed tempo between 40 and 220.');
  else if (!cutTimes) fail('cuts-on-beat', 'no edit decision list: build plan/cue-sheet.json in mapped mode (or pass --compose-map) so cut times are measured, not asserted.');
  else if (!cutTimes.length) fail('cuts-on-beat', 'the edit decision list has no cuts after the first frame; a single-shot marketing cut has no rhythm to judge.');
  else {
    const period = 60 / bpm;
    const deltas = cutTimes.map((t) => { const k = Math.round((t - offset) / period); return Math.abs(t - (offset + k * period)) * 1000; });
    const hits = deltas.filter((d) => d <= T.beatToleranceMs).length;
    beatResult = { bpm, offsetSeconds: offset, cuts: cutTimes.length, onBeat: hits, ratio: Number((hits / cutTimes.length).toFixed(3)), deltasMs: deltas.map((d) => Math.round(d)), source: cutSource };
    if (hits / cutTimes.length < T.beatHitRatio) fail('cuts-on-beat', `${hits}/${cutTimes.length} cuts land within ${T.beatToleranceMs} ms of the ${bpm} bpm grid; the floor is ${Math.round(T.beatHitRatio * 100)}%.`);
    else if (R.cutsOnBeat?.verdict !== 'pass') fail('cuts-on-beat', 'cutsOnBeat needs verdict pass once the measurement passes.');
    else pass('cuts-on-beat', `${hits}/${cutTimes.length} on the ${bpm} bpm grid`);
  }

  // 7. Three cited reference ads: what this cut is competing against, by name.
  const refs = Array.isArray(R.references) ? R.references : [];
  const badRef = refs.findIndex((r) => !text(r?.title) || !text(r?.source) || !text(r?.whyItWins, 10));
  if (refs.length !== T.referencesRequired) fail('references', `exactly ${T.referencesRequired} reference ads are required (got ${refs.length}); name what this cut competes against.`);
  else if (badRef >= 0) fail('references', `references[${badRef}] needs title, source and a sentence of whyItWins.`);
  else pass('references', refs.map((r) => r.title).join(' | '));

  // 8. The feed test: would this win the viewer in a feed next to those references?
  if (R.attentionCompetition?.winsAgainstReferences !== true) fail('feed-test', 'attentionCompetition.winsAgainstReferences is not true: the cut does not win the viewer in a feed next to the references. Recut; do not ship.');
  else if (!text(R.attentionCompetition?.evidence, 20)) fail('feed-test', 'attentionCompetition.evidence must say what wins the first five seconds against the references.');
  else pass('feed-test');

  // 9. No fluff is part of the floor: the narration check must have passed on this script.
  const nc = join(root, 'qa', 'narration-check.json');
  if (!existsSync(nc)) fail('no-fluff', 'missing qa/narration-check.json: run validate-narration.mjs; a marketing cut with unmeasured fluff is below the floor.');
  else { try { const n = readJson(nc); if (n.ok !== true) fail('no-fluff', `narration check failed (${(n.errors || []).length} error(s), ${n.fluff?.perMinute ?? '?'} fluff/min).`); else pass('no-fluff', `${n.fluff?.perMinute ?? 0} fluff/min`); } catch (e) { fail('no-fluff', `cannot read qa/narration-check.json: ${e.message}`); } }

  beatMeasurement = beatResult;
}

const report = {
  generator: 'media-studio/validate-marketing-readiness', schemaVersion: '1.0.0', ok: errors.length === 0, applies,
  errors, warnings, candidate: candidateRec, durationSeconds: duration,
  inputs: { job: ref(join(root, 'job.json')), readiness: ref(readinessPath), cueSheet: ref(cuePath) },
  thresholds: T, checks, cutsOnBeat: beatMeasurement,
  reason: applies ? (errors.length ? 'below the marketing floor' : 'at or above the marketing floor on this exact candidate') : `not a marketing cut (programForm ${job.programForm ?? 'none'}, kind ${job.kind ?? 'none'}); story rubric applies`,
};
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ok: report.ok, applies, out: rel(outPath), checks, errors, warnings }, null, 2));
process.exit(errors.length ? 1 : 0);
