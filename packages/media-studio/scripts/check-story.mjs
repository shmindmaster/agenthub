#!/usr/bin/env node
// Pre-capture story gate for any product and any film type.
//
// Reads a brief (a full ad spec, or the smaller shape below) and says whether
// the film has the parts its own form needs, before anything is captured,
// generated or paid for. It contacts no provider and writes nothing unless
// --out is given.
//
//   node check-story.mjs <brief.json> [--brand <brand.json>] [--json] [--out <report.json>]
//   node check-story.mjs --types [--json]
//
// Smallest brief:
//   { "product": "Rexa", "filmType": "tutorial", "targetSeconds": 90,
//     "narrative": { "goal": "..." },
//     "beats": [ { "role": "goal", "line": "..." }, { "role": "step", "line": "..." }, { "role": "payoff", "line": "..." } ] }
//
// A planning document's spine is accepted as written: each beat may use
// role/storyRole, line/narration, onScreen/onScreenText, and start/end seconds.
// Exit code 0 when the story passes, 1 when a rule fails, 2 on bad input.
import { existsSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
// The kit sits beside this script in the package, and elsewhere once deployed (briefing-kit\screencast, _shared\tools).
const libRoot = [['..', 'kit', 'marketing', 'lib'], ['..', 'marketing', 'lib'], ['..', '..', 'briefing-kit', 'marketing', 'lib']]
  .map((parts) => resolve(here, ...parts)).find((dir) => existsSync(resolve(dir, 'narrative.mjs')));
if (!libRoot) { console.error('check-story: the marketing kit library was not found beside this script; run Sync-MediaStudioKit.ps1.'); process.exit(2); }
const lib = (name) => pathToFileURL(resolve(libRoot, name)).href;
const { inspectNarrativeArc, describeFilmType } = await import(lib('narrative.mjs'));
const { FILM_TYPES, resolveFilmType } = await import(lib('story-profiles.mjs'));
const { creativeMode } = await import(lib('creative-modes.mjs'));
const { withProductProfile, productProfile } = await import(lib('product-profile.mjs'));
const { estimateBeatSeconds } = await import(lib('lint.mjs'));

const SHOWS_PRODUCT = new Set(['demonstration', 'demo', 'proof', 'step', 'steps', 'mechanism', 'walkthrough']);

/** One beat in the kit's shape, from whatever a planner wrote. */
export function normalizeBeat(raw, index) {
  const storyRole = raw.storyRole ?? raw.role;
  const narration = raw.narration ?? raw.line ?? raw.spoken ?? '';
  const onScreenText = raw.onScreenText ?? raw.onScreen ?? raw.text;
  const role = String(storyRole || '').trim().toLowerCase();
  const start = Number(raw.start ?? raw.startSeconds);
  const end = Number(raw.end ?? raw.endSeconds);
  const beat = {
    id: raw.id || `B${index + 1}`,
    storyRole,
    narration,
    // A plan has no capture yet, so kind is the declared intent: the product is shown where the role shows it.
    // A shot classified as proposed, fictional or illustrative is a generated shot, never a capture.
    kind: raw.kind || (SHOWS_PRODUCT.has(role) && !['proposed', 'fictional', 'illustrative'].includes(raw.truthStatus) ? 'ui' : 'card'),
  };
  if (onScreenText) beat.onScreenText = onScreenText;
  if (raw.truthStatus) beat.truthStatus = raw.truthStatus;
  if (raw.broll) beat.broll = raw.broll;
  if (Number.isFinite(start) && Number.isFinite(end) && end > start) beat.minSeconds = end - start;
  else if (Number.isFinite(Number(raw.seconds))) beat.minSeconds = Number(raw.seconds);
  return beat;
}

/** Cuts in the kit's shape: the brief's cuts, or one cut from its top-level beats or spine. */
export function normalizeCuts(brief) {
  const cuts = Array.isArray(brief.cuts) && brief.cuts.length
    ? brief.cuts
    : [{ id: 'main', targetSeconds: brief.targetSeconds, beats: brief.beats || brief.spine || [], filmType: undefined }];
  return cuts.map((cut, i) => ({
    ...cut,
    id: cut.id || `cut-${i + 1}`,
    targetSeconds: Number(cut.targetSeconds ?? brief.targetSeconds) || 0,
    beats: (cut.beats || cut.spine || []).map(normalizeBeat),
  }));
}

const seconds = (beat) => (Number.isFinite(beat.minSeconds) ? Math.max(beat.minSeconds, 0) : estimateBeatSeconds(beat));

/** Run the gate. Pure: returns the report. */
export function checkStory(brief, brand = {}) {
  if (!brief || typeof brief !== 'object' || Array.isArray(brief)) throw new TypeError('the brief must be a JSON object');
  for (const key of ['beats', 'spine', 'cuts']) if (brief[key] !== undefined && !Array.isArray(brief[key])) throw new TypeError(`${key} must be an array`);
  for (const cut of brief.cuts || []) for (const key of ['beats', 'spine']) if (cut && cut[key] !== undefined && !Array.isArray(cut[key])) throw new TypeError(`cuts[].${key} must be an array`);
  const spec = { ...brief };
  const merged = withProductProfile(brand, spec);
  const mode = creativeMode(spec);
  const cuts = normalizeCuts(spec);
  const report = { product: spec.product || merged?.product || null, creativeMode: mode, productProfile: productProfile(spec.product || merged?.product, merged?.id)?.id || null, cuts: [], ok: true };
  for (const cut of cuts) {
    const estimated = cut.beats.reduce((sum, b) => sum + seconds(b), 0);
    const type = resolveFilmType(spec, { ...cut, targetSeconds: Math.max(cut.targetSeconds, estimated) || cut.targetSeconds }, mode);
    const findings = inspectNarrativeArc(spec, cut, seconds, { brand: merged });
    const failures = findings.filter((f) => !f.waived).map(({ rule, message, where }) => ({ rule, message, where }));
    const waived = findings.filter((f) => f.waived).map(({ rule, message, where, waived: reason }) => ({ rule, reason, message, where }));
    if (failures.length) report.ok = false;
    report.cuts.push({
      id: cut.id, filmType: type.id, compact: Boolean(type.compact), seconds: Math.round(Math.max(cut.targetSeconds, estimated)),
      requires: type.unknown ? null : describeFilmType(type.id),
      failures, waived,
    });
  }
  return report;
}

function print(report) {
  for (const cut of report.cuts) {
    const head = `${report.product || 'film'} / ${cut.id}: ${cut.filmType}${cut.compact ? ' (short cut)' : ''}, about ${cut.seconds}s`;
    console.log(`${cut.failures.length ? 'FAIL' : 'PASS'}  ${head}`);
    for (const f of cut.failures) console.log(`  - [${f.rule}] ${f.message}${f.where && f.where !== cut.id ? `  (${f.where})` : ''}`);
    for (const w of cut.waived) console.log(`  ~ [${w.rule}] waived: ${w.reason}`);
    if (cut.failures.length && cut.requires) console.log(`  A ${cut.filmType} film: ${cut.requires.summary}`);
  }
  if (!report.ok) console.log('To waive a story rule for a reason, add { "rule": "<rule id>", "reason": "<who decided and why>" } to storyOverrides. Truth and evidence rules cannot be waived.');
}

// Compared by real path: through a junction or a symlink the two spellings differ, and the gate must still run.
const invoked = (() => { try { return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } })();
if (invoked) {
  const args = process.argv.slice(2);
  const flag = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
  const json = args.includes('--json');
  if (args.includes('--types')) {
    const types = Object.keys(FILM_TYPES).map(describeFilmType);
    if (json) console.log(JSON.stringify(types, null, 2));
    else for (const t of types) console.log(`${t.id}\n  ${t.summary}\n  beats, in order: ${t.slots.join(' > ') || '(free order)'}\n  brief: ${t.briefFields.join(', ') || '(none)'}${t.id === 'non-narrative' ? '\n  needs organizingPrinciple' : ''}\n`);
    process.exit(0);
  }
  const briefPath = args.find((a) => !a.startsWith('--') && a !== flag('--brand') && a !== flag('--out'));
  if (!briefPath || !existsSync(briefPath)) { console.error('usage: node check-story.mjs <brief.json> [--brand <brand.json>] [--json] [--out <report.json>] | --types'); process.exit(2); }
  let brief; let brand = {};
  try {
    brief = JSON.parse(readFileSync(briefPath, 'utf8'));
    const brandPath = flag('--brand');
    if (brandPath) brand = JSON.parse(readFileSync(brandPath, 'utf8'));
  } catch (error) { console.error(`check-story: ${error.message}`); process.exit(2); }
  let report;
  try { report = checkStory(brief, brand); } catch (error) { console.error(`check-story: ${error.message}`); process.exit(2); }
  if (flag('--out')) writeFileSync(flag('--out'), `${JSON.stringify(report, null, 2)}\n`);
  if (json) console.log(JSON.stringify(report, null, 2)); else print(report);
  process.exit(report.ok ? 0 : 1);
}
