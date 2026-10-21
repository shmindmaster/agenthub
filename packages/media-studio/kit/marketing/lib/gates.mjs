// QA gate plumbing: the per-ratio gate workspace that lets the existing release gates (validate-sync,
// validate-viewer-release, build-cue-sheet) read an mvg ad, the caption check, the evidence assembly and the
// releasable decision. Nothing here is a pass unless a gate actually ran on the exact candidate.
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { chooseResult, expectationClipTimes, expandKeywords, shiftAsr, unnarratedActions } from './align.mjs';
import { CHAIN_GATES, captureViewportsFor } from './chain-gates.mjs';
import { FRAMES } from './layout.mjs';
import { fileSha, readJson, round, writeJson } from './util.mjs';

// integrity, pointer, frameIntegrity and marketing are the media-studio 2.0.0 film-chain gates (picture integrity, pointer path,
// tiled-frame / luma-jump check, marketing floor).
export const DEFAULT_REQUIRED = ['picture', 'integrity', 'pointer', 'frameIntegrity', 'captions', 'loudness', 'sync', 'listen', 'vision', 'marketing', 'story', 'viewerRelease'];

/** The gates deliver requires: the spec's list (or the default), always including the film-chain gates. */
export const requiredGates = (spec) => [...new Set([...(spec?.qa?.required || DEFAULT_REQUIRED), ...CHAIN_GATES])];

const seconds = (value) => {
  const m = /^(\d{2}):(\d{2}):(\d{2})[,.](\d{3})$/.exec(value.trim());
  return m ? Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(m[4]) / 1000 : NaN;
};
export function parseSrt(text) {
  return text.trim() ? text.trim().split(/\r?\n\s*\r?\n/).map((block) => {
    const lines = block.split(/\r?\n/).filter(Boolean);
    const ti = lines.findIndex((l) => l.includes('-->'));
    const [a, b] = (lines[ti] || '').split('-->');
    const captionLines = ti < 0 ? [] : lines.slice(ti + 1);
    const start = seconds(a || '');
    const end = seconds(b || '');
    return { lines: captionLines, words: captionLines.join(' ').trim(), start, end, duration: end - start };
  }) : [];
}

/** Caption rules: 3-7 words per cue (5-7 target), <=2 lines of <=42 chars, <=20 chars/s, ordered, no overlap. */
export function captionsCheck(srtText, { maxWords = 7, minWords = 2 } = {}) {
  const errors = [];
  const cues = parseSrt(srtText);
  if (!cues.length) errors.push('captions contain no cues');
  let prev = -1;
  cues.forEach((c, i) => {
    const n = c.words.split(/\s+/).filter(Boolean).length;
    if (!Number.isFinite(c.start) || !Number.isFinite(c.end) || c.end <= c.start) errors.push(`cue ${i + 1} has invalid timing`);
    if (c.start < prev) errors.push(`cue ${i + 1} overlaps the previous cue`);
    prev = Math.max(prev, c.end);
    if (n > maxWords) errors.push(`cue ${i + 1} has ${n} words (max ${maxWords})`);
    if (n < minWords && i !== cues.length - 1) errors.push(`cue ${i + 1} has only ${n} word`);
    if (c.lines.length > 2 || c.lines.some((l) => l.length > 42)) errors.push(`cue ${i + 1} exceeds 2 lines of 42 characters`);
    if (c.duration > 0 && c.words.length / c.duration > 20) errors.push(`cue ${i + 1} exceeds 20 characters per second`);
  });
  return { ok: errors.length === 0, cues: cues.length, errors };
}

/**
 * Gate workspace for one ratio: just the files validate-sync / validate-viewer-release / build-cue-sheet read.
 * Clip ids are remapped to the beat ids so clips from different film workspaces never collide.
 */
export function buildGateWorkspace({ root, spec, cut, ratio, timeline, composeMap, clips, asr, loudnessLufs }) {
  const frame = FRAMES[ratio];
  mkdirSync(join(root, 'story'), { recursive: true });
  mkdirSync(join(root, 'capture', 'clips'), { recursive: true });
  mkdirSync(join(root, 'voice', 'asr'), { recursive: true });
  mkdirSync(join(root, 'qa'), { recursive: true });
  mkdirSync(join(root, 'output'), { recursive: true });
  writeJson(join(root, 'job.json'), {
    jobId: `mvg-${spec.id}-${ratio}`, product: spec.product, title: spec.title, kind: 'product-screencast', programForm: 'outcome-workflow', intent: 'viewer-facing',
    craftScoreMin: spec.qa?.storyMin ?? 85, deliveryProfile: frame.profile, repositoryWritePolicy: 'read-only', workspace: root,
    // A paid ad competes in a feed: validate-marketing-readiness and viewer-release apply the marketing floor to marketing: true
    // (programForm stays outcome-workflow, see README deviation 8). Each portrait or square ratio is captured at its own frame.
    marketing: true, captureViewports: captureViewportsFor(ratio, frame),
    dataClass: 'synthetic only', label: spec.labels, syntheticDisclosure: { mode: 'end-card', text: spec.labels }, loudnessTargetLufs: loudnessLufs, recastFallbackAllowed: false, generator: 'media-studio/mvg',
  });
  // A beat with no narration (the opening title card, an end card with only on-screen text) is a silent beat: it has no words and
  // no timing precision to ask for. The cue sheet (build-cue-sheet.mjs) makes one row per segment of this file and, with no ASR
  // to read for a segment, spreads its (empty) text and marks the row precision "estimate", which validate-sync refuses as
  // "narration timing is estimate (not word-level)". So the narration timeline lists the narrated beats only; the film's total
  // length stays, and the silent beat's picture is still in the compose map and the storyboard below.
  writeJson(join(root, 'story', 'narration-timeline.json'), {
    durationSeconds: timeline.durationSeconds,
    segments: timeline.segments.filter((s) => s.text).map((s) => ({ id: s.id, scene: s.id, text: s.text, startSeconds: s.startSeconds, durationSeconds: s.durationSeconds, speechSeconds: s.speechSeconds })),
  });
  writeJson(join(root, 'story', 'storyboard.json'), {
    title: `${spec.title} - storyboard`, kind: 'product-screencast', deliveryProfile: frame.profile, scenarioId: spec.id,
    beats: cut.beats.map((b, i) => ({ id: b.id, order: i + 1, narration: b.narration || '', visualMode: b.kind === 'ui' ? 'screen' : b.kind === 'broll' ? 'broll' : 'card', resultHoldSeconds: 1.6 })),
  });
  // Inputs the Local-AI listen gate requires for a speech review: the segments for the pronunciation-risk manifest, the
  // reading overrides, and a timeline whose audioStart/audioEnd bound the spoken words inside each scene.
  const narratedSegs = timeline.segments.filter((s) => s.text);
  writeJson(join(root, 'story', 'narration-segments.json'), { segments: narratedSegs.map((s) => ({ id: s.id, scene: s.id, text: s.text, wavSeconds: s.speechSeconds })) });
  writeJson(join(root, 'story', 'reading-overrides.json'), {});
  writeJson(join(root, 'qa', 'listen-timeline.json'), {
    durationSeconds: timeline.durationSeconds, leadInSeconds: 0, tailSeconds: 0,
    segments: narratedSegs.map((s) => ({
      id: s.id, scene: s.id, text: s.text, startSeconds: s.startSeconds, durationSeconds: s.durationSeconds, speechSeconds: s.speechSeconds,
      audioStartSeconds: s.words.length ? s.words[0].start : s.lineStartSeconds, audioEndSeconds: round(s.lineStartSeconds + s.speechSeconds, 3), sceneEndSeconds: round(s.startSeconds + s.durationSeconds, 3),
    })),
  });
  writeFileSync(join(root, 'story', 'locked-script.txt'), `${timeline.segments.map((s) => s.text).filter(Boolean).join('\n')}\n`, 'utf8');
  const cuePlan = { voiceFirst: true, beats: {} };
  const manifestClips = [];
  const receipt = { schemaVersion: '1.0.0', generator: 'media-studio/record-job', clips: {} };
  for (const beat of cut.beats.filter((b) => b.kind === 'ui')) {
    const c = clips.find((x) => x.beatId === beat.id);
    const dest = join('clips', `${beat.id}.webm`);
    if (!existsSync(join(root, 'capture', dest))) copyFileSync(c.file, join(root, 'capture', dest));
    const g = composeMap.groups.find((x) => x.segments.includes(beat.id));
    manifestClips.push({ id: beat.id, file: dest.replace(/\\/g, '/'), segments: [beat.id], fit: 'hold', trimStart: g.edit.trimStart, trimEnd: g.edit.trimEnd, sourceRegion: g.sourceRegion });
    // Only expectations that can serve as this beat's result stay in the receipt copy: visible inside the beat and held
    // >= 1.5 s (see align.chooseResult). Others belong to a later part of the clip and would be stamped after the beat.
    const segDur = timeline.segments.find((x) => x.id === beat.id).durationSeconds;
    const keep = new Set(chooseResult({ expectations: expectationClipTimes(c.receiptEntry), trimStart: g.edit.trimStart, naturalSeconds: segDur }).keep.map((e) => e.raw));
    const expectations = (c.receiptEntry.expectations || []).filter((x) => !x.observed || keep.has(x));
    receipt.clips[beat.id] = { ...c.receiptEntry, expectations, file: dest.replace(/\\/g, '/'), segments: [beat.id], sha256: fileSha(join(root, 'capture', dest)) };
    // Every receipt action inside the beat's window is declared: the narrated ones with their spoken keywords (digits and
    // number words both), all others narrated:false so the sync gate does not ask for a spoken word for a pointer trace.
    const narrated = (beat.ui.actions || []).map((a) => ({ label: a.label, narrated: true, keywords: expandKeywords(a.keywords) }));
    const quiet = unnarratedActions(c.receiptEntry.actions, c.receiptEntry.recastHeadTrimSeconds ?? 0, g.edit.trimStart, g.edit.trimEnd, narrated.map((a) => a.label)).map((label) => ({ label, narrated: false }));
    // What the spec author declared, for validate-picture-integrity: a focus window with `declaredZoom` is an authored punch-in
    // (and, below full region, an authored crop). Nothing undeclared is written here, so any other crop or zoom still fails.
    const declared = (g.windows || []).some((w) => w.declaredZoom);
    const cropped = g.sourceRegion && (g.sourceRegion.width < 1 || g.sourceRegion.height < 1);
    const beatPlan = { ...(narrated.length || quiet.length ? { actions: [...narrated, ...quiet] } : {}), ...(declared ? { zoom: true } : {}), ...(declared && cropped ? { crop: { reason: 'ui.focus declaredZoom: an authored focus window on a device-scale recording' } } : {}) };
    if (Object.keys(beatPlan).length) cuePlan.beats[beat.id] = beatPlan;
  }
  writeJson(join(root, 'capture', 'manifest.json'), { clips: manifestClips });
  writeJson(join(root, 'capture', 'receipt.json'), receipt);
  writeJson(join(root, 'story', 'cue-plan.json'), cuePlan);
  // The cue sheet reads a line's word times as seconds from the START OF ITS SCENE, but mvg places each line after a lead-in
  // pause, so the per-line ASR is shifted by that lead; otherwise every keyword lands one lead early (a constant 300 ms miss).
  for (const [beatId, file] of Object.entries(asr || {})) {
    const seg = timeline.segments.find((x) => x.id === beatId);
    const lead = seg && seg.lineStartSeconds !== null ? seg.lineStartSeconds - seg.startSeconds : 0;
    writeJson(join(root, 'voice', 'asr', `${beatId}.json`), shiftAsr(readJson(file), round(lead, 3)));
  }
  writeJson(join(root, 'output', `${spec.id}-compose-map.json`), composeMap);
  return root;
}

/** Evidence file validate-viewer-release.mjs reads, assembled from measured reports and the reviewer's file. */
export function assembleEvidence({ root, candidate, candidateSha, srtPath, loudnessReportPath, loudness, reviews, scriptPath }) {
  const bound = (r) => (r ? { ...r, candidateSha256: candidateSha } : undefined);
  const evidence = {
    candidate: { path: relative(root, candidate).replace(/\\/g, '/'), sha256: candidateSha },
    captions: { status: 'PASS', candidateSha256: candidateSha, path: relative(root, srtPath).replace(/\\/g, '/'), sha256: fileSha(srtPath) },
    audio: { status: 'PASS', candidateSha256: candidateSha, integratedLufs: loudness.integratedLufs, truePeakDbtp: loudness.truePeakDbtp, analyzerReport: { path: relative(root, loudnessReportPath).replace(/\\/g, '/'), sha256: fileSha(loudnessReportPath) } },
    pronunciation: bound(reviews.pronunciation ? { ...reviews.pronunciation, reference: 'authored-script', scriptPath: relative(root, scriptPath).replace(/\\/g, '/'), scriptSha256: fileSha(scriptPath) } : null),
    encodedVisualReview: bound(reviews.encodedVisualReview),
    titleReview: bound(reviews.titleReview),
    actionResultReview: bound(reviews.actionResultReview),
    storyReview: bound(reviews.storyReview),
  };
  return evidence;
}

/** A ratio is releasable only when every required gate passed on the exact candidate. */
export function releasable(gates, required = DEFAULT_REQUIRED) {
  const failing = [];
  for (const name of required) {
    const g = gates[name];
    if (!g || g.status !== 'pass') failing.push(`${name}: ${g ? g.status : 'not run'}${g?.detail ? ` (${g.detail})` : ''}`);
  }
  return { ok: failing.length === 0, failing };
}

/** The reviewer's file counts only for the candidate it names: a review of an earlier render must never pass a new one. */
export function readReviews(path, candidateSha) {
  if (!existsSync(path)) return {};
  const reviews = readJson(path);
  return reviews.candidateSha256 && reviews.candidateSha256 === candidateSha ? reviews : {};
}
export { round };
