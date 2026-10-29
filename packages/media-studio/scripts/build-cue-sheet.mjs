#!/usr/bin/env node
// Build plan/cue-sheet.json: one row per narration beat, joining the locked narration (word timestamps from local
// ASR), the capture receipt (timestamped pointer/click/type events from record-lib) and the compose edit decision
// list. It is the input to voice-first compose and to the sync gate (validate-sync.mjs). Directive: VIDEO-SYNC-DIRECTIVE §1-2.
//
// Usage: node build-cue-sheet.mjs <jobRoot> [--out plan/cue-sheet.json] [--compose-map output/<base>-compose-map.json]
//                                          [--lead 0.3] [--click-lead 0]
//
// Inputs (all under <jobRoot>; the product repository is never read):
//   story/narration-timeline.json  required  { durationSeconds, segments:[{ id, scene, text, startSeconds, durationSeconds }] }
//   voice/align/<segmentId>.json  picture clock. ai.ps1 align, method forced-alignment. Take-relative words, offset by startSeconds.
//                                  When job.json syncClock is forced-aligner, a missing align report is an error.
//                                  Whisper (voice/asr or narration-words) is a transcript check and cannot time that picture.
//   voice/asr/<segmentId>.json     legacy screencast word timestamps, seconds into that line's audio (offset by startSeconds).
//                                  Used only when no align report exists and the job has no forced-aligner clock.
//                                  Segment-level timing only -> precision "segment"; no timing at all -> authored text spread
//                                  across the segment, precision "estimate". Both are flagged and the sync gate refuses them.
//   capture/receipt.json           clips[id].actions (record-job.mjs): click / type / point events with tStart, label, x, y,
//                                  on the raw recording clock; clips[id].recastHeadTrimSeconds maps them onto the clip
//                                  (sync-lib clipClock). A Recast clip without it is refused: its events would be off by
//                                  the blank lead-in Recast trimmed (0.4-2.5 s measured on Revolva).
//   capture/manifest.json          clip -> segment mapping and trim/speed/skip hints (plan mode)
//   output/<base>-compose-map.json optional; when present the cue sheet is "mapped": action times are program times
//                                  through the real edit decision list. Run compose, then this script again.
//   story/cue-plan.json            optional authoring: { voiceFirst?, beats:{ S05:{ actions:[{ label, keywords?, narrated? }],
//                                  result:{ label, keywords? }, expectedState, camera, transition } } }
//   story/capture-plan.json, story/storyboard.json   expected UI state, camera and transition defaults
//
// Typical order:  ASR -> build-cue-sheet (plan) -> compose-screencast (voice-first alignment) -> build-cue-sheet (mapped) -> encode -> validate-sync
import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { asrAnchoredAllowed, clockAccepted, designedCuts, normalizeAlignWords, pictureScripts } from './picture-gates.mjs';
import { piecewiseCaptureClock } from './piecewise-capture-clock.mjs';
import { readPhysicalResultObservations, applyPhysicalResultObservations } from './physical-result-observations.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const libPath = [join(scriptDir, 'sync-lib.mjs'), join(scriptDir, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
if (!libPath) { console.error('sync-lib.mjs not found beside this script or in ../kit/screencast'); process.exit(2); }
const L = await import(pathToFileURL(libPath).href);

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
const jobRoot = pos[0];
if (!jobRoot) { console.error('Usage: node build-cue-sheet.mjs <jobRoot> [--out plan/cue-sheet.json] [--compose-map <file>] [--lead 0.3] [--click-lead 0]'); process.exit(1); }
const root = resolve(jobRoot);
const lead = Number(flag('--lead', L.SYNC_DEFAULTS.screenLeadSeconds));
const clickLead = Number(flag('--click-lead', L.SYNC_DEFAULTS.clickLeadSeconds));
const outPath = resolve(root, flag('--out', 'plan/cue-sheet.json'));
const readJson = (rel) => { const p = join(root, rel); return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, '')) : null; };
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const ref = (p) => (p && existsSync(p) ? { path: relative(root, p).replace(/\\/g, '/'), sha256: sha(p) } : null);
const warnings = [];
const errors = [];

const timelinePath = join(root, 'story', 'narration-timeline.json');
if (!existsSync(timelinePath)) { console.error('story/narration-timeline.json is required: lock and render the narration first (voice-first).'); process.exit(1); }
const timeline = readJson('story/narration-timeline.json');
const segs = timeline.segments || [];
if (!segs.length) { console.error('narration timeline has no segments'); process.exit(1); }
const plan = readJson('story/cue-plan.json') || {};
const capturePlan = readJson('story/capture-plan.json');
const storyboard = readJson('story/storyboard.json');
const manifest = readJson('capture/manifest.json') || {};
const receipt = readJson('capture/receipt.json');
const sbBeats = storyboard ? (storyboard.beats || storyboard.scenes || []) : [];
const cpScenes = capturePlan ? (capturePlan.scenes || []) : [];

// ---- compose map (edit decision list)
let composeMapPath = flag('--compose-map') ? resolve(root, flag('--compose-map')) : null;
if (!composeMapPath && existsSync(join(root, 'output'))) {
  const maps = readdirSync(join(root, 'output')).filter((f) => f.endsWith('-compose-map.json')).map((f) => join(root, 'output', f)).sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  composeMapPath = maps[0] || null;
}
const composeMap = composeMapPath && existsSync(composeMapPath) ? JSON.parse(readFileSync(composeMapPath, 'utf8')) : null;
const mapped = !!composeMap?.groups?.length;
if (composeMapPath && !composeMap) warnings.push(`compose map not found: ${composeMapPath}`);

// ---- narration words per segment. Aligner reports win. Whisper cannot time a forced-aligner picture.
const jobDoc = readJson('job.json') || {};
const forcedClock = jobDoc.syncClock === 'forced-aligner';
const absWords = readJson('story/narration-words.json');
const absParsed = absWords ? L.parseAsrWords(absWords) : null;
function wordsFromAlign(seg) {
  const alignPath = join(root, 'voice', 'align', `${seg.id}.json`);
  if (!existsSync(alignPath)) return null;
  const report = JSON.parse(readFileSync(alignPath, 'utf8').replace(/^\uFEFF/, ''));
  const clock = clockAccepted(report, { allowAsrAnchored: asrAnchoredAllowed(jobDoc) });
  if (!clock.ok) {
    errors.push(`${seg.id}: ${clock.reason}`);
    return { words: [], precision: 'refused', source: `voice/align/${seg.id}.json` };
  }
  const parsed = L.parseAsrWords(normalizeAlignWords(report), { offset: seg.startSeconds });
  if (parsed.words.length) return { ...parsed, source: `voice/align/${seg.id}.json` };
  errors.push(`${seg.id}: voice/align/${seg.id}.json has no usable timing`);
  return { words: [], precision: 'refused', source: `voice/align/${seg.id}.json` };
}
const beatsWords = segs.map((seg, i) => {
  const aligned = wordsFromAlign(seg);
  if (aligned) return aligned;
  if (forcedClock && String(seg.text || '').trim()) {
    // mvg local gates write their forced-aligner words here, marked clock: 'forced-aligner'. Unmarked Whisper output stays refused.
    const marked = join(root, 'voice', 'asr', `${seg.id}.json`);
    if (existsSync(marked)) {
      const payload = JSON.parse(readFileSync(marked, 'utf8').replace(/^\uFEFF/, ''));
      if (payload?.clock === 'forced-aligner') {
        const parsed = L.parseAsrWords(payload, { offset: seg.startSeconds });
        if (parsed.words.length) return { ...parsed, source: `voice/asr/${seg.id}.json` };
      }
    }
    errors.push(`${seg.id}: word times must come from ai.ps1 align (voice/align/${seg.id}.json, method forced-alignment). Whisper is a transcript check and cannot time the picture.`);
    return { words: [], precision: 'refused', source: 'missing aligner report' };
  }
  const next = segs[i + 1];
  const end = next ? next.startSeconds : Infinity;
  const perSeg = join(root, 'voice', 'asr', `${seg.id}.json`);
  if (existsSync(perSeg)) {
    const parsed = L.parseAsrWords(JSON.parse(readFileSync(perSeg, 'utf8').replace(/^\uFEFF/, '')), { offset: seg.startSeconds });
    if (parsed.words.length) return { ...parsed, source: `voice/asr/${seg.id}.json` };
    warnings.push(`${seg.id}: voice/asr/${seg.id}.json has no usable timing`);
  }
  if (absParsed?.words.length) {
    const words = absParsed.words.filter((w) => w.start >= seg.startSeconds - 0.05 && w.start < end);
    if (words.length) return { words, precision: absParsed.precision, source: 'story/narration-words.json' };
  }
  return { words: L.spreadWords(seg.text, seg.startSeconds, seg.startSeconds + seg.durationSeconds), precision: 'estimate', source: 'authored text spread across the segment (no ASR timing)' };
});

// ---- clips, groups, edit decisions
const rawClips = manifest.composeClips || manifest.clips || manifest.entries || manifest.captures || [];
const manifestClips = rawClips.map((c) => ({ ...c, id: c.id || c.scenario || c.storyboardSegmentId, segments: c.segments || [c.storyboardSegmentId].filter(Boolean) }));
const sceneOf = (seg) => seg.scene || String(seg.id).replace(/[a-z]$/, '');
const clipForSegment = (seg) => manifestClips.find((c) => c.segments.includes(seg.id)) || manifestClips.find((c) => c.segments.includes(sceneOf(seg)) || c.segments.includes(String(seg.id).replace(/[a-z]$/, ''))) || null;
// Plan mode has no compose map, so the clip length comes from the receipt (unknown = unbounded, never a silent null mapping).
const editOf = (src) => ({ trimStart: Number(src?.trimStart || 0), trimEnd: src?.trimEnd ? Number(src.trimEnd) : null, speed: Number(src?.speed || 1), skip: src?.skip || [], headHold: Number(src?.headHold || 0), srcSeconds: Number(src?.srcSeconds || receipt?.clips?.[src?.id]?.clipSeconds || 1e6) });
const piecewiseClocks = new Map();
const piecewiseSourceHashes = new Map();
for (const g of composeMap?.groups || []) {
  if (!g.actualCaptureWindow?.piecewise_time_map) continue;
  try {
    if (g.isImage || g.heldFromPrevious || g.extras || g.fit === 'fit') throw Error('unsupported transformed capture group');
    const file = resolve(root, g.file || '');
    if (!piecewiseSourceHashes.has(file)) piecewiseSourceHashes.set(file, sha(file));
    piecewiseClocks.set(g, piecewiseCaptureClock(g, { sourceSha256: piecewiseSourceHashes.get(file), receiptSha256: receipt?.clips?.[g.clipId]?.sha256 }));
  } catch (e) { errors.push(`${g.clipId}: ${e.message}`); }
}

function groupFor(seg) {
  if (mapped) {
    const g = composeMap.groups.find((x) => (x.segments || []).includes(seg.id));
    if (g) return { clipId: g.clipId, kind: g.isImage ? 'card' : g.heldFromPrevious ? 'hold' : 'screen', start: g.startSeconds, until: round(g.startSeconds + g.needSeconds), edit: g.edit || editOf({ ...g, srcSeconds: g.srcSeconds }), segments: g.segments, fit: g.fit, file: g.file, piecewise: piecewiseClocks.get(g), hasPiecewise: !!g.actualCaptureWindow?.piecewise_time_map, mappable: g.actualCaptureWindow?.piecewise_time_map ? piecewiseClocks.has(g) : !!(g.clipId && g.edit && !g.isImage && !g.heldFromPrevious && !g.extras && g.fit !== 'fit') };
    warnings.push(`${seg.id}: segment is not in the compose map`);
  }
  const c = clipForSegment(seg);
  const same = c ? segs.filter((s) => clipForSegment(s) === c) : [seg];
  const first = same[0];
  const last = same[same.length - 1];
  const isImage = c ? /\.(png|jpe?g|webp)$/i.test(c.file || '') : true;
  return { clipId: c ? c.id : null, kind: !c ? 'card' : isImage ? 'card' : 'screen', start: first.startSeconds, until: round(last.startSeconds + last.durationSeconds), edit: editOf(c), segments: same.map((s) => s.id), fit: c?.fit || 'cut', file: c?.file || null, mappable: !!c && !isImage && c.fit !== 'fit' && !c.extras };
}
function round(v) { return L.round(v); }

// ---- speech spans, slot starts
const speech = beatsWords.map((b) => ({ start: b.words[0]?.start ?? null, end: b.words.at(-1)?.end ?? null }));
const fcw = beatsWords.map((b) => L.firstContentWord(b.words));
const slots = segs.map((seg, i) => (i === 0 ? 0 : L.slotStartFor({ segmentStart: seg.startSeconds, firstWordStart: fcw[i]?.start, prevSpeechEnd: speech[i - 1].end, lead })));

// ---- beats
const beats = segs.map((seg, i) => {
  const bw = beatsWords[i];
  const g = groupFor(seg);
  const slotStart = mapped && g.segments[0] === seg.id ? g.start : mapped ? seg.startSeconds : slots[i];
  const nextSeg = segs[i + 1];
  const nextGroup = nextSeg ? groupFor(nextSeg) : null;
  const slotEnd = nextSeg ? (mapped && nextGroup.segments[0] === nextSeg.id ? nextGroup.start : mapped ? nextSeg.startSeconds : slots[i + 1]) : timeline.durationSeconds;
  const cp = plan.beats?.[seg.id] || plan.beats?.[sceneOf(seg)] || {};
  const sb = sbBeats.find((b) => b.id === seg.id || (b.segments || []).includes(seg.id)) || {};
  const cps = cpScenes.find((s) => s.sceneId === seg.id || s.sceneId === sceneOf(seg)) || {};
  const clipRec = g.clipId && receipt?.clips?.[g.clipId] ? receipt.clips[g.clipId] : null;
  if (g.kind === 'screen' && !clipRec) warnings.push(`${seg.id}: no capture receipt for clip ${g.clipId}; no actions can be timed`);
  // Receipt times are on the raw recording clock; the clip starts after Recast's blank lead-in trim.
  const clock = L.clipClock(clipRec);
  if (clipRec && clock.offset === null && ((clipRec.actions || []).length || (clipRec.expectations || []).length)) errors.push(`${seg.id}: clip ${g.clipId}: ${clock.source}`);
  const toProgram = (ts) => { if (!Number.isFinite(ts) || !g.mappable) return null; if (g.piecewise) { const t = g.piecewise.sourceToProgram(ts); return t === null ? null : round(t); } const t = L.clipToSlot(g.edit, ts); return t === null ? null : round(g.start + t); };
  const beatEnd = slotEnd;
  const beatStart = slotStart;
  const inBeat = (pt) => pt !== null && pt >= beatStart - 0.001 && pt < beatEnd - 0.001;

  // actions
  const events = (clipRec?.actions || []).filter((e) => {
    if (!['upload', 'fill'].includes(e.type)) return ['click', 'tap', 'type', 'point'].includes(e.type);
    const problems = e.type === 'upload' ? L.uploadEventProblems(e) : L.fillEventProblems(e);
    if (problems.length) errors.push(`${seg.id}: invalid ${e.type} receipt event: ${problems.join('; ')}`);
    return problems.length === 0;
  });
  const owned = events.map((e) => { const clipTime = L.toClipTime(clipRec, e.tStart ?? e.t); return { e, clipTime, program: toProgram(clipTime) }; }).filter((x) => x.clipTime !== null).filter((x) => g.segments.length === 1 || (x.program !== null ? inBeat(x.program) : g.segments[0] === seg.id));
  const planned = Array.isArray(cp.actions) ? cp.actions : null;
  const actions = [];
  const take = (x, spec) => {
    const label = spec?.label ?? x.e.label ?? null;
    const narrated = spec ? spec.narrated !== false : !!x.e.label;
    const keywords = narrated ? (spec?.keywords?.length ? spec.keywords : L.keywordsFromLabel(label || x.e.target)) : [];
    const keyword = narrated ? L.findKeywordWord(bw.words, keywords) : null;
    actions.push({
      kind: x.e.type, label, target: x.e.target || label || null, narrated, keywords,
      receipt_event_index: clipRec.actions.indexOf(x.e),
      ...(x.e.type === 'upload' ? { method: x.e.method, file: { ...x.e.file } } : {}),
      ...(x.e.type === 'fill' ? { method: x.e.method, inputType: x.e.inputType, value: x.e.value, targetBox: { ...x.e.targetBox } } : {}),
      clip_time: L.round(x.clipTime), cursor: Number.isFinite(x.e.x) ? { x: x.e.x, y: x.e.y } : null,
      action_time: mapped ? x.program : null,
      action_time_natural: g.mappable && !g.hasPiecewise ? round(g.start + (L.clipToSlot({ ...g.edit, headHold: 0 }, x.clipTime) ?? NaN)) : null,
      keyword: keyword ? { w: keyword.w, start: keyword.start, end: keyword.end, matched: keyword.keyword } : null,
    });
  };
  if (planned) {
    for (const spec of planned) {
      const x = owned.find((o) => String(o.e.label || '').toLowerCase() === String(spec.label || '').toLowerCase()) || owned.find((o) => String(o.e.target || '').toLowerCase().includes(String(spec.label || '').toLowerCase()));
      if (x) take(x, spec); else warnings.push(`${seg.id}: cue-plan action "${spec.label}" has no matching captured click/tap/type/point/upload/fill event`);
    }
  } else for (const x of owned) take(x, null);

  // result: the proof the product responded
  const expectations = (clipRec?.expectations || []).filter((x) => x.observed);
  let result = null;
  const resSpec = cp.result;
  const exp = resSpec ? expectations.find((x) => String(x.label).toLowerCase().includes(String(resSpec.label || '').toLowerCase())) : expectations.map((x) => ({ x, program: toProgram(L.toClipTime(clipRec, x.observedAt)) })).filter((y) => g.segments.length === 1 || inBeat(y.program)).map((y) => y.x).at(-1);
  if (exp || resSpec) {
    const label = resSpec?.label ?? exp?.label ?? null;
    const keywords = resSpec?.keywords?.length ? resSpec.keywords : L.keywordsFromLabel(label);
    const kw = L.findKeywordWord(bw.words, keywords, { last: true });
    const expClip = exp ? L.toClipTime(clipRec, exp.observedAt) : null;
    result = { label, receipt_expectation_index: exp ? clipRec.expectations.indexOf(exp) : null, clip_time: expClip, visible_at: expClip !== null && mapped ? toProgram(expClip) : null, keywords, keyword: kw ? { w: kw.w, start: kw.start, end: kw.end, matched: kw.keyword } : null };
  }
  const prevGroup = i > 0 ? groupFor(segs[i - 1]) : null;
  const cameraDefault = clipRec?.recast === 'full' ? 'Recast punch-in on clicks' : clipRec?.recast ? `Recast ${clipRec.recast}` : 'static';
  return {
    beat: seg.id,
    t_start: L.round(bw.words[0]?.start ?? seg.startSeconds),
    t_end: L.round(bw.words.at(-1)?.end ?? seg.startSeconds + seg.durationSeconds),
    slot_start: slotStart,
    slot_end: slotEnd,
    narration: { text: seg.text, words: bw.words, precision: bw.precision, source: bw.source, firstContentWord: fcw[i] },
    clip_clock: clipRec ? { offset_seconds: clock.offset, source: clock.source } : null,
    picture_clock: g.piecewise?.evidence || null,
    screen: { clip: g.clipId, kind: g.kind, file: g.file, visible_from: slotStart, visible_until: g.until, changes_from_previous: !prevGroup || prevGroup.clipId !== g.clipId || prevGroup.start !== g.start },
    actions,
    result,
    expected_ui_state: cp.expectedState ?? cps.resultState ?? cps.expectedResult ?? result?.label ?? null,
    camera: cp.camera ?? sb.camera ?? cameraDefault,
    transition: cp.transition ?? sb.transition ?? (!prevGroup ? 'fade-in' : prevGroup.clipId !== g.clipId ? 'cut' : 'continuous'),
  };
});

const flatScripts = pictureScripts(root).flat();
let designed = null;
if (flatScripts.length) {
  const timingById = {};
  segs.forEach((seg, i) => {
    const row = { s: seg.startSeconds, words: (beatsWords[i].words || []).map((word) => ({ w: word.w, s: word.start, start: word.start })) };
    if (!timingById[seg.id]) timingById[seg.id] = row;
    const dash = String(seg.id).lastIndexOf('-');
    const short = dash >= 0 ? String(seg.id).slice(dash + 1) : '';
    if (short && !timingById[short]) timingById[short] = row;
  });
  designed = designedCuts(flatScripts, timingById, 0);
  for (const miss of designed.misses) errors.push(miss);
}
const degraded = beats.filter((b) => b.narration.precision !== 'word').map((b) => ({ beat: b.beat, precision: b.narration.precision }));
if (degraded.length) warnings.push(`degraded timing precision on ${degraded.length} beat(s): ${degraded.map((d) => `${d.beat}=${d.precision}`).join(', ')}; the sync gate fails these. Run ai.ps1 align and write voice/align/<id>.json. Whisper cannot time the picture.`);
const composeEdl = mapped ? composeMap.groups.map((g) => ({ segments: g.segments, clip: g.clipId, startSeconds: g.startSeconds, needSeconds: g.needSeconds, fit: g.fit, edit: g.actualCaptureWindow?.piecewise_time_map ? null : g.edit || null, actualCaptureWindow: g.actualCaptureWindow || null })) : null;
let edl = composeEdl;
if (designed) {
  const existing = Array.isArray(composeEdl) ? [...composeEdl] : [];
  const seen = new Set(existing.map((row) => Number(row.startSeconds)));
  for (const start of designed.cuts) {
    if (seen.has(start)) continue;
    seen.add(start);
    existing.push({ startSeconds: start, kind: 'designed' });
  }
  existing.sort((a, b) => Number(a.startSeconds) - Number(b.startSeconds));
  edl = existing;
}
const sheet = {
  generator: 'media-studio/build-cue-sheet',
  schemaVersion: '1.0.0',
  voiceFirst: plan.voiceFirst !== false,
  mode: mapped ? 'mapped' : 'plan',
  durationSeconds: timeline.durationSeconds,
  parameters: { screenLeadSeconds: lead, clickLeadSeconds: clickLead },
  inputs: { timeline: ref(timelinePath), receipt: ref(join(root, 'capture', 'receipt.json')), manifest: ref(join(root, 'capture', 'manifest.json')), composeMap: mapped ? ref(composeMapPath) : null, cuePlan: ref(join(root, 'story', 'cue-plan.json')) },
  precision: { allWordLevel: degraded.length === 0, degradedBeats: degraded },
  edl,
  warnings,
  errors,
  beats,
};
const physicalPath = flag('--physical-results');
if (physicalPath) {
  try {
    if (!mapped) throw new Error('physical result observations require mapped compose');
    const proof = readPhysicalResultObservations({ root, path: resolve(root, physicalPath), inputs: sheet.inputs, beats });
    applyPhysicalResultObservations(beats, proof);
    sheet.inputs.physicalResults = proof.ref;
  } catch (e) { errors.push(e.message); }
}
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(sheet, null, 2));
const acts = beats.reduce((n, b) => n + b.actions.filter((a) => a.narrated).length, 0);
console.log(JSON.stringify({ ok: errors.length === 0, out: relative(root, outPath).replace(/\\/g, '/'), mode: sheet.mode, beats: beats.length, narratedActions: acts, allWordLevel: sheet.precision.allWordLevel, errors, warnings }, null, 2));
// Fail closed: an event time on an unknown clock would place every action off by the clip's head trim (up to 3 s).
if (errors.length) process.exit(1);
