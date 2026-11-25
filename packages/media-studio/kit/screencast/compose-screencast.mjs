// Assemble the silent picture for a screencast-led video from captured clips, aligned to the locked narration timeline.
// Usage: node compose-screencast.mjs <jobRoot> <base>
// Inputs (all under <jobRoot>, the external job workspace — never a product repo):
//   story/narration-timeline.json  { durationSeconds, segments: [{ id, scene, text, startSeconds, durationSeconds }] }
//   capture/manifest.json          { clips: [{ id, file: "clips/x.webm|mp4|png", segments: ["S03","S04"], ...hints }] }
//   story/storyboard.json          optional; beats supply kicker/title/subtitle/footer for auto cards
//   job.json                       optional; `title` and `cardFooter` feed auto cards; `endFadeSeconds` fades the end to black (default none)
// Per-clip hints (see README.md): trimStart, trimEnd, speed, skip, fit: cut|hold|fit|fitpad, overlay.
// A segment with no clip holds the previous clip's last frame. A png is a card, looped.
// Output: output/<base>-silent.mp4 at the job delivery profile, 30 fps, yuv420p.
// Voice-first: when plan/cue-sheet.json exists (build-cue-sheet.mjs; disable with --no-voice-first) the picture is built to the
// locked narration. A new screen comes up `screenLeadSeconds` before the first content word, and each clip's first narrated
// action is aligned to its spoken word by freezing the clip's first frame (headHold, at most 1.5 s) or trimming its head.
// A clip that cannot cover its narration span after alignment stops the compose with a recapture message; the voice is never squeezed.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { CAMPAIGN_FORMS, frameFor, sourcePictureFilter, sourceRegionError, validateCampaign } from './campaign-contract.mjs';
import { SYNC_DEFAULTS, planAlignment, keptRanges, editSlotSeconds } from './sync-lib.mjs';
import { stageRamps } from './stage-ramps.mjs';
import { STAGE, gradientFromColour } from './stage-math.mjs';
import { buildStagePlan, PRESS } from './stage-plan.mjs';
import { measureChanges } from './stage-changes.mjs';

const [jobRoot, base] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
if (!jobRoot || !base) { console.error('usage: node compose-screencast.mjs <jobRoot> <base> [--no-voice-first]'); process.exit(2); }
const here = path.dirname(fileURLToPath(import.meta.url));
function findProductPictureValidator() {
  const candidates = [
    path.join(here, 'validate-product-picture.mjs'),
    path.join(here, '..', '..', 'scripts', 'validate-product-picture.mjs'),
    process.env.AGENTHUB_ROOT ? path.join(process.env.AGENTHUB_ROOT, 'packages', 'media-studio', 'scripts', 'validate-product-picture.mjs') : null,
    path.join('C:', 'Repos', 'shmindmaster', 'agenthub', 'packages', 'media-studio', 'scripts', 'validate-product-picture.mjs'),
  ].filter(Boolean);
  return candidates.find((p) => fs.existsSync(p)) || null;
}
// product-picture.md: the gate is not optional. A compositor that cannot find its validator must stop,
// not compose unchecked (that silent skip is how stills-and-slides cuts shipped before 2026-09-15).
const productPictureValidator = findProductPictureValidator();
if (!productPictureValidator) {
  throw new Error('product-picture validator not resolvable (looked beside this script, in ../../scripts, and under AGENTHUB_ROOT). Run Sync-MediaStudioKit.ps1 or set AGENTHUB_ROOT; do not compose without the gate.');
}
try {
  execFileSync(process.execPath, [productPictureValidator, jobRoot], { stdio: 'inherit' });
} catch {
  process.exit(1);
}
const HOLD_PAD_MAX = 2.0;     // seconds a screen clip may be frozen to reach the narration length
const RESULT_HOLD_MAX = 6.0;  // unless the storyboard beat declares resultHoldSeconds up to this
const tl = JSON.parse(fs.readFileSync(path.join(jobRoot, 'story', 'narration-timeline.json'), 'utf8'));
const man = JSON.parse(fs.readFileSync(path.join(jobRoot, 'capture', 'manifest.json'), 'utf8'));
const job = (() => { try { return JSON.parse(fs.readFileSync(path.join(jobRoot, 'job.json'), 'utf8')); } catch { return {}; } })();
const { width: W, height: H, fps: PROFILE_FPS, profile } = frameFor(job);
let FPS = PROFILE_FPS;
const graphicsPath = path.join(jobRoot, 'story', 'timed-graphics.json');
const graphics = fs.existsSync(graphicsPath) ? JSON.parse(fs.readFileSync(graphicsPath, 'utf8')).overlays : [];
const contractErrors = validateCampaign(jobRoot, job, tl, graphics);
if (contractErrors.length) throw new Error(`campaign contract: ${contractErrors.join(' ')}`);
const cuePath = path.join(jobRoot, 'plan', 'cue-sheet.json');
const cue = !process.argv.includes('--no-voice-first') && fs.existsSync(cuePath) ? JSON.parse(fs.readFileSync(cuePath, 'utf8')) : null;
const voiceFirst = !!cue && cue.voiceFirst !== false;
if (voiceFirst) {
  const tlSha = createHash('sha256').update(fs.readFileSync(path.join(jobRoot, 'story', 'narration-timeline.json'))).digest('hex');
  if (cue.inputs?.timeline?.sha256 !== tlSha) throw new Error('voice-first: plan/cue-sheet.json was built from a different narration timeline. Re-lock the narration, then rerun build-cue-sheet.mjs; do not compose against a stale cue sheet.');
}
const cueBeat = (id) => (voiceFirst ? cue.beats.find((b) => b.beat === id) : null);
const clickLead = Number(cue?.parameters?.clickLeadSeconds ?? SYNC_DEFAULTS.clickLeadSeconds);
const recaptureNote = voiceFirst ? ' Voice-first: the narration is locked, so recapture this beat longer (hold on the result, slower pointer approach, or a pause before the action) instead of squeezing the voice.' : '';
// Accept both shapes: { clips:[{id,file,segments}] } and the validator-shaped { captures:[{storyboardSegmentId, segments, clip?}] }.
// A job may pre-assemble one exact-length plate per scene (manifest.composeClips); it wins over the raw capture record.
const rawClips = man.composeClips || man.clips || man.entries || man.captures || [];
const clips = rawClips.map((c) => {
  const id = c.id || c.scenario || c.storyboardSegmentId;
  let file = c.file || c.clip || c.video || c.output;
  if (!file) for (const ext of ['webm', 'mp4', 'png']) { if (fs.existsSync(path.join(jobRoot, 'capture', 'clips', `${id}.${ext}`))) { file = `clips/${id}.${ext}`; break; } }
  return { ...c, id, file, segments: c.segments || [c.storyboardSegmentId] };
}).filter((c) => c.file);
for (const clip of clips) {
  const regionError = sourceRegionError(clip.sourceRegion);
  if (regionError) throw new Error(`clip ${clip.id}: ${regionError}`);
  if (Object.hasOwn(CAMPAIGN_FORMS, job.programForm) && H > W && !/\.(png|jpe?g|webp)$/i.test(clip.file) && !clip.sourceRegion) throw new Error(`clip ${clip.id}: portrait campaign requires an explicit sourceRegion for intentional framing.`);
}
// Screen stage (stage-plan.mjs, ScreenStage.tsx): clips whose receipt says finisher "stage" are not scaled and padded here. Contiguous
// screen groups become one stage run with one continuous camera; the film then runs at the stage frame rate in every part.
const receiptFile = path.join(jobRoot, 'capture', 'receipt.json');
const receipt = fs.existsSync(receiptFile) ? JSON.parse(fs.readFileSync(receiptFile, 'utf8').replace(/^\uFEFF/, '')) : null;
const stageClip = (c) => !!c && receipt?.clips?.[c.id]?.finisher === 'stage';
const stageFilm = clips.some(stageClip);
if (stageFilm) FPS = STAGE.fps;
const stageRuns = [];
const stageCfg = job.screenStage && typeof job.screenStage === 'object' ? job.screenStage : {};
// Speed ramps of a stage clip (typing at 2x and declared spans): part of the edit, so every time below sees the same map.
function rampsFor(clip) {
  const entry = receipt.clips[clip.id];
  const index = JSON.parse(fs.readFileSync(path.join(jobRoot, 'capture', entry.stage.framesIndex), 'utf8'));
  return stageRamps({ jobRoot, entry, index, id: clip.id, cfg: stageCfg, manual: clip.speedSpans || [] });
}
function stageFrames(clipId) {
  const entry = receipt.clips[clipId];
  const indexPath = path.join(jobRoot, 'capture', entry.stage.framesIndex);
  if (!fs.existsSync(indexPath) || createHash('sha256').update(fs.readFileSync(indexPath)).digest('hex') !== entry.stage.framesIndexSha256) throw new Error(`screen stage: the frames of clip ${clipId} do not match capture/receipt.json (${entry.stage.framesIndex}); re-record the take`);
  const index = JSON.parse(fs.readFileSync(indexPath, 'utf8'));
  return { times: index.frames.map((f) => f.t), files: index.frames.map((f) => `${clipId}/frames/${f.file}`) };
}

// Map clips to timeline segments. A clip may name a segment id (S06a / S12), a scene id (S06) that
// spans several paragraph segments, or several of either. When several clips name one scene they
// are dealt to that scene's segments in order; leftovers attach to the last segment as extra sources.
const bySeg = new Map();
const segsByScene = new Map();
for (const seg of tl.segments) { if (!segsByScene.has(seg.scene)) segsByScene.set(seg.scene, []); segsByScene.get(seg.scene).push(seg.id); }
const sceneQueue = new Map();
for (const c of clips) {
  for (const key of c.segments || []) {
    if (!key) continue;
    if (tl.segments.some((s) => s.id === key)) { bySeg.set(key, c); continue; }
    const scene = key.replace(/[a-z]$/, '');
    const targets = segsByScene.get(scene) || segsByScene.get(key) || [];
    if (!targets.length) { console.error('clip', c.id, 'names unknown segment/scene', key); continue; }
    const q = sceneQueue.get(scene) || 0; sceneQueue.set(scene, q + 1);
    const target = targets[Math.min(q, targets.length - 1)];
    if (bySeg.has(target) && bySeg.get(target) !== c) { const prev = bySeg.get(target); prev.extras = [...(prev.extras || []), c]; }
    else bySeg.set(target, c);
  }
}
// Card-only segments: render a typeset card from the storyboard beat when no clip exists.
// product-picture.md: auto-card is forbidden on visualMode=screen (default on product-screencast).
const CARD_MODES = new Set(['card', 'slide', 'diagram', 'talking-head', 'motif', 'animation', 'narration-only', 'broll']);
const sbPath = path.join(jobRoot, 'story', 'storyboard.json');
const sb = fs.existsSync(sbPath) ? JSON.parse(fs.readFileSync(sbPath, 'utf8')) : null;
const beats = sb ? (sb.beats || sb.scenes || []) : [];
const jobTitle = job.title || '';
const beatFor = (segId) => beats.find((x) => x.id === segId || (x.segments || []).includes(segId)) || {};
// visualMode: storyboard beat first, then the screenplay scene (exact id, then the id with the beat suffix stripped).
// The storyboards this kit writes carry no visualMode, so without the screenplay every card and code reveal read as a
// screen beat without a clip (job 13, 2026-09-15). Unknown stays the kind's default so the gate still fails closed.
const screenplayModes = (() => { try { return new Map((JSON.parse(fs.readFileSync(path.join(jobRoot, 'story', 'screenplay.json'), 'utf8')).scenes || []).map((s) => [s.id, s.visualMode])); } catch { return new Map(); } })();
const beatMode = (segId) => {
  const mode = beatFor(segId).visualMode || screenplayModes.get(segId) || screenplayModes.get(String(segId).replace(/[a-z]+$/, ''));
  if (mode) return mode;
  return job.kind === 'product-screencast' ? 'screen' : 'slide';
};
const isScreenBeat = (segId) => !CARD_MODES.has(beatMode(segId));
for (const seg of tl.segments) {
  if (bySeg.has(seg.id)) continue;
  if (isScreenBeat(seg.id)) {
    throw new Error(`product-picture: segment ${seg.id} is visualMode=${beatMode(seg.id)} with no captured clip. Capture WebM (Playwright + Recast). Auto-card is forbidden on screen beats.`);
  }
  const png = path.join(jobRoot, 'capture', 'clips', `${seg.id}-card.png`);
  if (!fs.existsSync(png)) {
    const b = beatFor(seg.id);
    const spec = { kicker: b.kicker || jobTitle, title: b.title || (seg.text.split(/[.!?]/)[0] || '').slice(0, 90), subtitle: b.subtitle || '', footer: b.footer || job.cardFooter || '' };
    execFileSync('node', [path.join(here, 'render-card.mjs'), png, JSON.stringify({ ...spec, width: W, height: H })], { stdio: 'ignore' });
  }
  const card = { id: `${seg.id}-card`, file: `clips/${seg.id}-card.png`, segments: [seg.id], autoCard: true };
  clips.push(card); bySeg.set(seg.id, card);
}

const probe = (f) => { try { return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString()); } catch { return 0; } };
const tmp = path.join(jobRoot, 'output', '_parts'); fs.mkdirSync(tmp, { recursive: true });

// Group consecutive segments that share a clip so a long clip plays continuously across them.
const groups = [];
for (const seg of tl.segments) {
  const clip = bySeg.get(seg.id) || null;
  const last = groups[groups.length - 1];
  if (last && last.clip === clip && clip) { last.segments.push(seg); last.duration += seg.durationSeconds; }
  else groups.push({ clip, segments: [seg], duration: seg.durationSeconds, start: seg.startSeconds });
}
// Voice-first: a new screen is up before the first content word of its line, never before the previous line has finished.
if (voiceFirst) {
  groups.forEach((g, i) => {
    if (i === 0) return;
    const b = cueBeat(g.segments[0].id);
    if (b && Number.isFinite(b.slot_start) && b.slot_start <= g.start + 1e-6 && b.slot_start >= groups[i - 1].start + 0.5) g.start = b.slot_start;
  });
}
// A pause between segments (pauseBeforeSeconds in the timeline) is picture time too: the product stays on screen while
// the voice breathes. Each group therefore runs until the next group starts (the last one to the end of the timeline),
// otherwise the picture finishes ahead of the narration by the sum of the pauses and drifts out of sync on the way.
groups.forEach((g, i) => { const next = groups[i + 1]; g.duration = Number(((next ? next.start : tl.durationSeconds) - g.start).toFixed(3)); });
// Picture time is timeline time: the first part also carries [0, groups[0].start) as a clone of its first frame.
const leadIn = groups.length ? Math.max(0, Number(Number(groups[0].start || 0).toFixed(3))) : 0;

const parts = [];
const rows = [];
const mapGroups = [];
let prevFile = null;
let prevClipFile = null;
let openRun = null; // the stage run the previous group belongs to, while groups stay contiguous
groups.forEach((g, i) => {
  const out = path.join(tmp, `part-${String(i).padStart(3, '0')}.mp4`);
  const dur = g.duration.toFixed(3);
  let src = g.clip ? path.join(jobRoot, 'capture', g.clip.file) : prevFile;
  if (!src) throw new Error(`segment ${g.segments[0].id} has no clip and nothing precedes it`);
  if (g.clip && g.clip.extras && g.clip.extras.length) {
    if (g.clip.sourceRegion || g.clip.extras.some((extra) => extra.sourceRegion)) throw new Error(`clip ${g.clip.id}: sourceRegion with extra clips is unsupported; split the segments into separate manifest clips.`);
    // pre-concatenate the clip and its extras into one source so the slot plays them in order
    const srcs = [g.clip, ...g.clip.extras].map((c) => path.join(jobRoot, 'capture', c.file));
    const listP = path.join(tmp, `extras-${i}.txt`);
    const normed = srcs.map((f, k) => { const o = path.join(tmp, `extras-${i}-${k}.mp4`); execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', f, '-vf', `scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2,fps=${FPS},format=yuv420p`, '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', o]); return o; });
    fs.writeFileSync(listP, normed.map((p) => `file '${p.replace(/\\/g, '/')}'`).join('\n'));
    src = path.join(tmp, `extras-${i}.mp4`);
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', listP, '-c', 'copy', src]);
  }
  const isImage = /\.(png|jpe?g|webp)$/i.test(src);
  const stageGroup = !isImage && !!g.clip && stageClip(g.clip) && g.segments.some((s) => isScreenBeat(s.id));
  const stageHold = !g.clip && !!openRun;
  const stageSlot = stageGroup || stageHold;
  if (!stageSlot) openRun = null;
  if (isImage && g.segments.some((s) => isScreenBeat(s.id))) {
    throw new Error(`product-picture: segment ${g.segments.map((s) => s.id).join('+')} is a screen beat with a still (${src}). Product screens require WebM/MP4 + Recast.`);
  }
  // Per-clip edit hints from the manifest: trimStart (s), trimEnd (s), speed (>1 = faster, applied to the
  // whole clip; use for real wait time such as a production query), skip: [[a,b],...] (seconds to drop).
  const hints = g.clip || {};
  let align = null;
  if (voiceFirst && g.clip && !isImage && hints.fit !== 'fit') {
    for (const s of g.segments) {
      const a = cueBeat(s.id)?.actions?.find((x) => x.narrated && x.keyword && Number.isFinite(x.clip_time));
      if (a) { align = { clipTime: a.clip_time, keywordStart: a.keyword.start, label: `${s.id} action "${a.label || a.target}"` }; break; }
    }
  }
  const ramps = stageGroup ? rampsFor(g.clip) : [];
  const effEdit = { trimStart: Number(hints.trimStart || 0), trimEnd: hints.trimEnd ? Number(hints.trimEnd) : null, speed: Number(hints.speed || 1), skip: hints.skip || [], ramps, headHold: 0, srcSeconds: 0 };
  if (!isImage && ((hints.skip && hints.skip.length) || hints.trimStart || hints.trimEnd || hints.speed || align || ramps.length)) {
    // The manifest's trimStart was chosen against the narration alone; the slot also carries the pause after the beat.
    // Never trim away footage the slot needs: shrink the head trim first, so the take's own tail is used before any hold.
    const fullSrc = probe(src);
    let trimStart = Number(hints.trimStart || 0);
    const t1 = hints.trimEnd ? Number(hints.trimEnd) : fullSrc;
    if (!hints.speed && !(hints.skip && hints.skip.length) && !ramps.length && t1 - trimStart < g.duration) trimStart = Math.max(0, Number((t1 - g.duration).toFixed(3)));
    const sp = Number(hints.speed || 1);
    let headHold = 0;
    if (align) {
      const planned = planAlignment({ edit: { trimStart, trimEnd: t1, speed: sp, skip: hints.skip || [], ramps, headHold: 0, srcSeconds: fullSrc }, actionClipTime: align.clipTime, targetSlotSeconds: align.keywordStart + clickLead - g.start, label: align.label });
      if (planned.error) throw new Error(`segment ${g.segments.map((s) => s.id).join('+')}: ${planned.error}`);
      trimStart = planned.edit.trimStart; headHold = planned.edit.headHold;
    }
    Object.assign(effEdit, { trimStart, trimEnd: t1, speed: sp, headHold, srcSeconds: fullSrc, ramps });
    if (!stageGroup) {
    const t0 = trimStart;
    const keep = [];
    let cur = t0;
    for (const [a, b] of (hints.skip || []).slice().sort((x, y) => x[0] - y[0])) { if (a > cur) keep.push([cur, Math.min(a, t1)]); cur = Math.max(cur, b); }
    if (cur < t1) keep.push([cur, t1]);
    let fc = keep.map(([a, b], k) => `[0:v]trim=start=${a}:end=${b},setpts=(PTS-STARTPTS)/${sp}[k${k}]`).join(';') + ';' + keep.map((_, k) => `[k${k}]`).join('') + `concat=n=${keep.length}:v=1:a=0[ed]`;
    // headHold: freeze the first frame so an action that would land before its spoken word lands on it.
    if (headHold > 0) fc += `;[ed]tpad=start_mode=clone:start_duration=${headHold.toFixed(3)}[edh]`;
    const edited = path.join(tmp, `edited-${i}.mp4`);
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', src, '-filter_complex', fc, '-map', headHold > 0 ? '[edh]' : '[ed]', '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-r', String(FPS), edited]);
    src = edited;
    }
  }
  let srcDur = isImage ? 0 : probe(src);
  if (!effEdit.srcSeconds) effEdit.srcSeconds = srcDur;
  if (stageGroup) {
    // The stage plays the original frames through this edit; the length the edit yields is what the slot checks below measure.
    effEdit.trimEnd = effEdit.trimEnd || effEdit.srcSeconds;
    srcDur = editSlotSeconds(effEdit);
  }
  const fit = g.clip?.fit || (srcDur > g.duration ? 'cut' : 'hold');
  // A 'cut' whose footage still ends before the slot does (a take paced to the words, then the pause after them) may hold
  // its last frame for at most HOLD_PAD_MAX; anything longer is the frozen-footage defect and fails like a hold would.
  const cutShortfall = !isImage && g.clip && fit === 'cut' && srcDur < g.duration ? Number((g.duration - srcDur).toFixed(3)) : 0;
  if (cutShortfall > HOLD_PAD_MAX && g.segments.some((s) => isScreenBeat(s.id))) {
    throw new Error(`product-picture: segment ${g.segments.map((s) => s.id).join('+')} has ${srcDur.toFixed(1)}s of footage for a ${g.duration.toFixed(1)}s slot; the last frame would freeze for ${cutShortfall.toFixed(1)}s (max ${HOLD_PAD_MAX}s). Re-pace the take or trim the words.${recaptureNote}`);
  }
  if (!isImage && g.clip && (fit === 'hold' || fit === 'fitpad') && g.segments.some((s) => isScreenBeat(s.id))) {
    const pad = g.duration - srcDur;
    const declared = Math.max(0, ...g.segments.map((s) => Number(beatFor(s.id).resultHoldSeconds || 0)));
    if (pad > HOLD_PAD_MAX && !(declared >= pad && declared <= RESULT_HOLD_MAX)) {
      throw new Error(`product-picture: segment ${g.segments.map((s) => s.id).join('+')} would freeze ${srcDur.toFixed(1)}s of footage for ${pad.toFixed(1)}s to cover ${g.duration.toFixed(1)}s of narration (max ${HOLD_PAD_MAX}s or a declared resultHoldSeconds ≤ ${RESULT_HOLD_MAX}s). Re-pace the take, cut the words, or split the beat.${recaptureNote}`);
    }
  }
  if (!isImage && g.clip && fit === 'fit' && srcDur > 0 && g.segments.some((s) => isScreenBeat(s.id))) {
    const r = g.duration / srcDur;
    if (r < 0.8 || r > 1.25) throw new Error(`product-picture: segment ${g.segments.map((s) => s.id).join('+')} fit would retime product footage ${r.toFixed(2)}x (allowed 0.8–1.25x); that misrepresents the product's speed.`);
  }
  const sourceRegion = g.clip?.sourceRegion || (!g.clip ? (mapGroups.at(-1)?.sourceRegion || null) : null);
  if (sourceRegion && g.clip?.overlay) throw new Error(`clip ${g.clip.id}: sourceRegion cannot be combined with a legacy full-frame annotation overlay; use a timed campaign graphic.`);
  if (stageSlot) {
    if (!openRun) { openRun = { slots: [], startSeconds: i === 0 ? 0 : g.start, partIndex: parts.length, out, groupIndexes: [] }; stageRuns.push(openRun); parts.push(out); }
    const lead = i === 0 ? leadIn : 0;
    const last = openRun.slots[openRun.slots.length - 1];
    const edit = stageHold
      ? { trimStart: last.edit.trimEnd, trimEnd: last.edit.trimEnd, speed: 1, skip: [], headHold: 0, srcSeconds: last.edit.srcSeconds }
      : { ...effEdit, headHold: Number((effEdit.headHold + lead).toFixed(3)) };
    openRun.slots.push({ clipId: stageHold ? last.clipId : g.clip.id, startSeconds: i === 0 ? 0 : Number((g.start - openRun.startSeconds).toFixed(3)), durationSeconds: Number((g.duration + lead).toFixed(3)), edit, hold: stageHold, segments: g.segments.map((s) => s.id) });
    openRun.groupIndexes.push(mapGroups.length);
    mapGroups.push({ segments: g.segments.map((s) => s.id), startSeconds: g.start, needSeconds: Number(g.duration.toFixed(3)), clipId: stageHold ? last.clipId : g.clip.id, file: stageHold ? prevClipFile : g.clip.file, heldFromPrevious: stageHold, sourceRegion: null, srcSeconds: Number(srcDur.toFixed(3)), fit: g.clip ? fit : 'hold-prev', trimStart: Number(hints.trimStart || 0), speed: Number(hints.speed || 1), edit: stageHold ? null : effEdit, extras: false, overlay: null, isImage: false, stage: { run: stageRuns.indexOf(openRun) } });
    rows.push(`${g.segments.map((s) => s.id).join('+').padEnd(16)} ${(g.clip ? g.clip.id : '(hold prev)').padEnd(28)} need=${g.duration.toFixed(1).padStart(6)}s clip=${srcDur.toFixed(1).padStart(6)}s ${fit} stage run ${stageRuns.indexOf(openRun)}`);
    if (g.clip) { prevClipFile = g.clip.file; prevFile = src; }
    return;
  }
  let vf = `${sourcePictureFilter(sourceRegion, { width: W, height: H })},fps=${FPS},format=yuv420p`;
  let args;
  if (isImage) args = ['-loop', '1', '-t', dur, '-i', src, '-vf', vf];
  else if (!g.clip) args = ['-sseof', '-0.1', '-i', src, '-vf', `${vf},tpad=stop_mode=clone:stop_duration=${dur}`, '-t', dur]; // hold previous last frame
  else if ((fit === 'fitpad' || fit === 'hold') && srcDur < g.duration) args = ['-i', src, '-vf', `${vf},tpad=stop_mode=clone:stop_duration=${(g.duration - srcDur + 0.5).toFixed(3)}`, '-t', dur];
  else if (fit === 'fit' && srcDur > 0) args = ['-i', src, '-vf', `setpts=PTS*${(g.duration / srcDur).toFixed(4)},${vf}`, '-t', dur]; // fit: retime the clip to the narration
  else args = ['-i', src, '-vf', `${vf},tpad=stop_mode=clone:stop_duration=${(cutShortfall + 0.5).toFixed(3)}`, '-t', dur]; // cut: play from the start, stop at the slot end; the clone only fills a sub-2 s tail so every part is exactly its slot
  if (g.clip && g.clip.overlay) {
    // annotation overlay (transparent PNG, 1600x1000, from render-overlay.mjs): apply after scaling so the boxes align with the frame
    const ov = path.join(jobRoot, 'capture', g.clip.overlay);
    if (!fs.existsSync(ov)) throw new Error(`clip ${g.clip.id} names overlay ${g.clip.overlay} which does not exist`);
    const vfIdx = args.indexOf('-vf'); const baseVf = args[vfIdx + 1]; args.splice(vfIdx, 2);
    const inIdx = args.indexOf('-i'); args.splice(inIdx + 2, 0, '-i', ov);
    args.push('-filter_complex', `[0:v]${baseVf}[b];[b][1:v]overlay=0:0:format=auto,format=yuv420p[v]`, '-map', '[v]');
  }
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args, '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-r', String(FPS), out]);
  if (i === 0 && leadIn > 0) {
    // The narration timeline starts its first line at groups[0].start (the voice's lead-in silence), and the speech stem keeps
    // that silence. Every later slot is placed on the timeline, so the picture must cover [0, start) too: hold the first frame
    // for the lead-in, otherwise the whole picture plays early by the lead-in and every action leads its spoken word.
    const led = path.join(tmp, 'part-000-lead.mp4');
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', out, '-vf', `tpad=start_mode=clone:start_duration=${leadIn.toFixed(3)},format=yuv420p`, '-t', (leadIn + g.duration).toFixed(3), '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-r', String(FPS), led]);
    fs.renameSync(led, out);
  }
  parts.push(out); prevFile = src;
  mapGroups.push({ segments: g.segments.map((s) => s.id), startSeconds: g.start, needSeconds: Number(g.duration.toFixed(3)), clipId: g.clip ? g.clip.id : null, file: g.clip ? g.clip.file : (prevClipFile || null), heldFromPrevious: !g.clip, sourceRegion, srcSeconds: Number(srcDur.toFixed(3)), fit: g.clip ? fit : 'hold-prev', trimStart: Number(hints.trimStart || 0), speed: Number(hints.speed || 1), edit: isImage || !g.clip ? null : effEdit, extras: !!(g.clip && g.clip.extras && g.clip.extras.length), overlay: g.clip?.overlay || null, isImage });
  if (g.clip) prevClipFile = g.clip.file;
  rows.push(`${g.segments.map((s) => s.id).join('+').padEnd(16)} ${(g.clip ? g.clip.id : '(hold prev)').padEnd(28)} need=${g.duration.toFixed(1).padStart(6)}s clip=${srcDur.toFixed(1).padStart(6)}s ${fit}${g.clip && g.clip.overlay ? ' +overlay' : ''}`);
});
// Render each stage run: one plan, one continuous camera, one Remotion render into the part file its first group would have used.
const stagePlans = [];
stageRuns.forEach((run, n) => {
  const durationSeconds = Number(run.slots.reduce((m, s) => Math.max(m, s.startSeconds + s.durationSeconds), 0).toFixed(3));
  const clipIds = [...new Set(run.slots.map((s) => s.clipId))];
  const clipsIn = {};
  for (const id of clipIds) {
    const e = receipt.clips[id], frames = stageFrames(id);
    // What changed on the page after each press, from the captured frames: the plan frames the result as well as the target.
    const pressTimes = (e.actions || []).filter((a) => PRESS.has(a.type)).map((a) => a.tStart ?? a.t);
    const changes = measureChanges({ presses: pressTimes, frames: { times: frames.times, files: frames.files.map((f) => path.join(jobRoot, 'capture', 'raw', f)) }, viewport: e.viewport });
    clipsIn[id] = { actions: e.actions || [], expectations: e.expectations || [], frames, touch: !!e.hasTouch, changes };
  }
  const viewport = receipt.clips[clipIds[0]].viewport;
  const hideCursor = (stageCfg.hideCursor || []).map((h) => {
    if (h.beat) { const gi = groups.find((x) => x.segments.some((s) => s.id === h.beat)); if (!gi) throw new Error(`screenStage.hideCursor names unknown beat ${h.beat}`); return [gi.start - run.startSeconds, gi.start + gi.duration - run.startSeconds]; }
    return [h.from - run.startSeconds, h.to - run.startSeconds];
  }).filter(([a, b]) => b > 0 && a < durationSeconds);
  const layout = stageCfg.background ? 'phone' : null;
  let background = null;
  if (layout) {
    // The gradient behind a phone screen is generated from the page's own colour: a dark and a lighter tone of its mean colour.
    const first = clipsIn[clipIds[0]].frames.files[0];
    const mean = execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', path.join(jobRoot, 'capture', 'raw', first), '-vf', 'scale=1:1:flags=area,format=rgb24', '-f', 'rawvideo', 'pipe:1']);
    background = { colors: gradientFromColour([mean[0], mean[1], mean[2]]), angle: STAGE.background.angle, ...(Array.isArray(stageCfg.background.colors) ? { colors: stageCfg.background.colors } : {}) };
  }
  const plan = buildStagePlan({ frame: { width: W, height: H, fps: FPS }, viewport, dsf: receipt.clips[clipIds[0]].deviceScaleFactor, slots: run.slots.map(({ segments, ...s }) => s), clips: clipsIn, options: { hideCursor, idleHide: stageCfg.idleHide, zoom: stageCfg.zoom, highlights: stageCfg.highlights, layout, background } });
  plan.film = { startSeconds: run.startSeconds, segments: run.slots.map((s) => s.segments) };
  for (const w of plan.warnings) console.log(`  screen stage run ${n}: ${w}`);
  const planFile = path.join(jobRoot, 'output', `${base}-stage-plan-${n}.json`);
  fs.writeFileSync(planFile, JSON.stringify(plan));
  const t0 = Date.now();
  execFileSync(process.execPath, [path.join(here, 'render-stage.mjs'), '--plan', planFile, '--public-dir', path.join(jobRoot, 'capture', 'raw'), '--out', run.out, '--concurrency', process.env.STAGE_CONCURRENCY || '8'], { stdio: 'inherit' });
  stagePlans.push({ run: n, file: path.relative(jobRoot, planFile).replace(/\\/g, '/'), sha256: createHash('sha256').update(fs.readFileSync(planFile)).digest('hex'), startSeconds: run.startSeconds, durationSeconds, renderSeconds: Number(((Date.now() - t0) / 1000).toFixed(1)), warnings: plan.warnings });
  for (const gi of run.groupIndexes) mapGroups[gi].stage.plan = stagePlans[n].file;
});
const list = path.join(tmp, 'concat.txt');
fs.writeFileSync(list, parts.map((p) => `file '${p.replace(/\\/g, '/')}'`).join('\n'));
const outFile = path.join(jobRoot, 'output', `${base}-silent.mp4`);
const baseFile = graphics?.length ? path.join(tmp, 'picture-before-graphics.mp4') : outFile;
// The last picture holds (treatments.md). A fade to black is opt-in: it fails a declared final hold and a light last frame.
const endFade = Number(job.endFadeSeconds) || 0;
execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-vf', `${stageFilm ? '' : 'fade=t=in:st=0:d=0.5,'}${endFade > 0 ? `fade=t=out:st=${(tl.durationSeconds - endFade).toFixed(2)}:d=${endFade},` : ''}format=yuv420p`, '-c:v', 'libx264', '-preset', 'medium', '-crf', '17', '-r', String(FPS), '-movflags', '+faststart', baseFile]);
if (graphics.length) {
  const assets = new Map(job.campaign.assets.map((asset) => [asset.id, asset]));
  const inputs = graphics.flatMap((graphic) => ['-loop', '1', '-i', path.resolve(jobRoot, assets.get(graphic.assetId).path)]);
  const filters = [];
  let source = '[0:v]';
  graphics.forEach((graphic, index) => {
    const overlay = `[g${index}]`, next = `[v${index}]`;
    filters.push(`[${index + 1}:v]scale=${graphic.width}:${graphic.height},format=rgba${overlay}`);
    filters.push(`${source}${overlay}overlay=${graphic.x}:${graphic.y}:enable='between(t,${graphic.startSeconds},${graphic.endSeconds})':eof_action=pass${next}`);
    source = next;
  });
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', baseFile, ...inputs, '-filter_complex', filters.join(';'), '-map', source, '-t', String(tl.durationSeconds), '-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '17', '-r', String(FPS), '-pix_fmt', 'yuv420p', '-movflags', '+faststart', outFile]);
}
const finalDur = probe(outFile);
// Compose map: validate-encoded-picture.mjs uses it to bind every encoded segment back to its receipt-bound clip.
fs.writeFileSync(path.join(jobRoot, 'output', `${base}-compose-map.json`), JSON.stringify({ generator: 'media-studio/compose-screencast', base, voiceFirst, cueSheetSha256: voiceFirst ? createHash('sha256').update(fs.readFileSync(cuePath)).digest('hex') : null, silent: outFile, deliveryProfile: profile, width: W, height: H, fps: FPS, stagePlans, timelineSeconds: tl.durationSeconds, pictureSeconds: finalDur, leadInSeconds: leadIn, timedGraphics: graphics, groups: mapGroups }, null, 2));
console.log(rows.join('\n'));
console.log(JSON.stringify({ ok: true, out: outFile, pictureSeconds: finalDur, timelineSeconds: tl.durationSeconds, delta: +(finalDur - tl.durationSeconds).toFixed(2) }));
