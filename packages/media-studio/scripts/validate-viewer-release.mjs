#!/usr/bin/env node
// Fail closed on evidence bound to the exact encoded product-demo candidate.
// Usage: node validate-viewer-release.mjs <jobRoot> <candidate.mp4>
import { existsSync, readFileSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { isAbsolute, join, relative, resolve } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { validateActionResultReview } from "./action-result-review.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const campaignHelper = existsSync(join(scriptDir, "campaign-contract.mjs"))
  ? join(scriptDir, "campaign-contract.mjs")
  : join(scriptDir, "..", "kit", "screencast", "campaign-contract.mjs");
const { CAMPAIGN_FORMS, frameFor, probeVideo, validateCampaign } = await import(pathToFileURL(campaignHelper).href);

const [jobRoot, candidateArg] = process.argv.slice(2);
if (!jobRoot || !candidateArg) { console.error("Usage: node validate-viewer-release.mjs <jobRoot> <candidate.mp4>"); process.exit(1); }
const root = resolve(jobRoot);
const candidate = resolve(candidateArg);
const json = (path) => JSON.parse(readFileSync(path, "utf8"));
const digest = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const withinRoot = (path) => {
  const rel = relative(root, path);
  return rel === "" || (!isAbsolute(rel) && rel !== ".." && !rel.startsWith("..\\") && !rel.startsWith("../"));
};
const errors = [];
if (!existsSync(candidate)) errors.push(`candidate does not exist: ${candidate}`);
const candidateSha = existsSync(candidate) ? digest(candidate) : null;
const jobPath = join(root, "job.json");
const job = existsSync(jobPath) ? json(jobPath) : {};
const timelinePath = join(root, "story", "narration-timeline.json");
const timeline = existsSync(timelinePath) ? json(timelinePath) : null;
const graphicsPath = join(root, "story", "timed-graphics.json");
const graphics = existsSync(graphicsPath) ? json(graphicsPath).overlays : [];
if (job.kind === 'product-screencast') {
  const picturePath = join(root, 'qa', 'encoded-picture.json');
  if (!existsSync(picturePath)) errors.push('missing qa/encoded-picture.json; encoded source and motion checks must pass on the exact candidate.');
  else {
    try {
      const picture = json(picturePath);
      if (!(picture.generator === 'media-studio/validate-encoded-picture' || (job.generator === 'media-studio/mvg' && picture.generator === 'media-studio/mvg-picture-gate')) || picture.ok !== true || !Array.isArray(picture.errors) || picture.errors.length) errors.push('encoded-picture report must be a PASS with no errors from validate-encoded-picture.');
      if (picture.candidate?.sha256 !== candidateSha || picture.candidate?.bytes !== (candidateSha ? statSync(candidate).size : null)) errors.push('encoded-picture report is not bound to the exact candidate SHA-256 and byte count.');
      if (picture.thresholds?.maxStaticSeconds !== 6 || picture.thresholds?.bindMaxHamming !== 12) errors.push('encoded-picture report must use canonical static and source-binding thresholds.');
      if (!Number.isFinite(picture.screenRatio) || picture.screenRatio < .7 || !Array.isArray(picture.segments) || !picture.segments.some((segment) => segment.bound === true) || picture.segments.some((segment) => segment.bound === false)) errors.push('encoded-picture report lacks passing screen coverage and source-bound segments.');
    } catch (error) { errors.push(`cannot read encoded-picture report: ${error.message}`); }
  }
}
if (job.kind === 'product-screencast') {
  // VIDEO-SYNC-DIRECTIVE §4: narration-to-visual sync is measured on the exact encoded file by validate-sync.mjs.
  const syncPath = join(root, 'qa', 'sync.json');
  if (!existsSync(syncPath)) errors.push('missing qa/sync.json; narration-to-visual sync must pass on the exact candidate (validate-sync.mjs).');
  else {
    try {
      const sync = json(syncPath);
      if (sync.generator !== 'media-studio/validate-sync' || sync.ok !== true || !Array.isArray(sync.errors) || sync.errors.length) errors.push('sync report must be a PASS with no errors from validate-sync.');
      if (sync.degraded === true || sync.precision?.allWordLevel !== true) errors.push('sync report was produced with degraded (non word-level) narration timing; run word-level ASR per line and rebuild the cue sheet.');
      if (sync.candidate?.sha256 !== candidateSha || sync.candidate?.bytes !== (candidateSha ? statSync(candidate).size : null)) errors.push('sync report is not bound to the exact candidate SHA-256 and byte count.');
      const th = sync.thresholds || {};
      if (!(th.actionToleranceMs <= 300) || !(th.screenToleranceMs <= 40) || !(th.resultHoldMinSeconds >= 1.5) || !(th.driftMaxMs <= 40) || !(th.maxFreezeSeconds <= 6) || !(th.maxHoldSeconds <= 6.5) || !(th.maxDroppedFrames <= 3)) errors.push('sync report must use the canonical thresholds (action +-300 ms, screen-on 40 ms, result hold 1.5 s, A/V drift 40 ms, freeze 6 s, declared hold 6.5 s, dropped frames 3).');
      const performedChecks = new Set(sync.checks?.performed || []);
      const missingChecks = ['screen-on', 'action-timing', 'result-hold', 'narration-order', 'av-sync', 'frozen-frames', 'dropped-frames'].filter((check) => !performedChecks.has(check));
      if (missingChecks.length) errors.push(`sync report did not perform: ${missingChecks.join(', ')}.`);
      if (!Array.isArray(sync.checks?.notPerformed) || !Array.isArray(sync.beats) || !sync.beats.some((beat) => (beat.findings || []).some((finding) => finding.check === 'action-timing' && finding.status === 'pass'))) errors.push('sync report must list checks not performed and show at least one passed action-timing finding.');
    } catch (error) { errors.push(`cannot read sync report: ${error.message}`); }
  }
}
// Video standard (owner direction 2026-10-20): no fluff, the feed test, nothing redundant, a purposeful cursor. Each rule
// has its own measuring gate; this gate only refuses a release that lacks a PASS bound to the exact inputs it measured.
const boundReport = (relPath, generator, label) => {
  const path = join(root, relPath);
  if (!existsSync(path)) { errors.push(`missing ${relPath}; ${label}.`); return null; }
  try {
    const report = json(path);
    if (report.generator !== generator || report.ok !== true || !Array.isArray(report.errors) || report.errors.length) { errors.push(`${relPath} must be a PASS with no errors from ${generator.replace('media-studio/', '')}.`); return null; }
    return report;
  } catch (error) { errors.push(`cannot read ${relPath}: ${error.message}`); return null; }
};
const boundToCandidate = (report, relPath) => { if (report && (report.candidate?.sha256 !== candidateSha || report.candidate?.bytes !== (candidateSha ? statSync(candidate).size : null))) errors.push(`${relPath} is not bound to the exact candidate SHA-256 and byte count.`); };
const boundToInput = (report, relPath, inputKeys, label) => {
  if (!report) return;
  const key = inputKeys.find((k) => report.inputs?.[k]?.path);
  const input = key ? report.inputs[key] : null;
  if (!input) { errors.push(`${relPath} does not record the ${label} it read.`); return; }
  const source = resolve(root, input.path);
  if (!withinRoot(source) || !existsSync(source)) { errors.push(`${relPath} names a ${label} that is not in the job workspace: ${input.path}.`); return; }
  if (digest(source) !== input.sha256) errors.push(`${relPath} is stale: ${input.path} changed since it was checked; rerun the gate.`);
};
// A PASS counts only at the canonical floor: each gate takes its thresholds as flags, so a report run with a loosened
// threshold (--tile-psnr 100, --max-travel-ratio 9, --hook-max 30) would otherwise pass here with the floor disabled.
// Each rule is [threshold, 'max' | 'min', canonical]: 'max' means the recorded value may be at most the canonical one.
const canonical = (report, relPath, rules) => {
  if (!report) return report;
  const th = report.thresholds || {};
  const off = rules.filter(([key, dir, value]) => !Number.isFinite(th[key]) || (dir === 'max' ? th[key] > value : th[key] < value));
  if (off.length) errors.push(`${relPath} was not run at the canonical thresholds: ${off.map(([key, dir, value]) => `${key} ${th[key] ?? 'missing'} (${dir === 'max' ? 'at most' : 'at least'} ${value})`).join(', ')}.`);
  return report;
};
// The selector requires verification; the report records the actual timing method.
// ASR opt-in must never silently skip the same candidate/input provenance checks.
const supportedWordClocks = ['forced-aligner', 'asr-anchored'];
if (job.syncClock != null && !supportedWordClocks.includes(job.syncClock)) errors.push('unsupported syncClock; use forced-aligner or explicitly opted-in asr-anchored.');
if (job.syncClock === 'asr-anchored' && job.clockPolicy?.allowAsrAnchored !== true) errors.push('asr-anchored syncClock requires clockPolicy.allowAsrAnchored: true.');
if (supportedWordClocks.includes(job.syncClock) || job.clockPolicy?.allowAsrAnchored === true) {
  const word = canonical(boundReport('qa/word-sync.json', 'media-studio/validate-word-sync', 'word onsets require verified encoded word-clock evidence on the exact candidate'), 'qa/word-sync.json', [['driftMaxMs', 'max', 40]]);
  boundToCandidate(word, 'qa/word-sync.json');
  boundToInput(word, 'qa/word-sync.json', ['alignment'], 'alignment evidence');
  boundToInput(word, 'qa/word-sync.json', ['cueSheet'], 'cue sheet');
  boundToInput(word, 'qa/word-sync.json', ['script'], 'locked alignment script');
  if (word?.method === 'verified-preserved-pcm-edit-map') {
    boundToInput(word, 'qa/word-sync.json', ['editMap'], 'complete immutable edit map');
    try {
      const { readVerifiedMap, measureMappedClock } = await import('./edit-map-clock.mjs');
      const proof = json(resolve(root, word.inputs.alignment.path));
      const mapped = readVerifiedMap(root, proof, {takeSha256:candidateSha,scriptSha256:digest(join(root,'story','locked-script.txt')),editMapSha256:word.inputs.editMap.sha256});
      const measured = measureMappedClock(mapped, json(resolve(root,word.inputs.cueSheet.path)).beats.flatMap(b=>b.narration?.words||[]));
      for (const key of ['ok','count','offsetMs','driftMs','p95AbsMs','words','changedWords']) if(JSON.stringify(measured[key])!==JSON.stringify(word[key]))throw Error(`mapped clock ${key} differs from current inputs`);
      if(word.gridMs!==null||word.sourceGridMs!==80||word.sourceUncertaintyMs!==80||!Number.isFinite(word.offsetMs)||!Number.isFinite(word.driftMs)||Math.abs(word.offsetMs)>40||Math.abs(word.driftMs)>40)throw Error('mapped clock must retain80ms uncertainty and canonical40ms drift/offset limits');
    } catch(e) { errors.push(`invalid verified edit-map provenance: ${e.message}`); }
  } else if(word?.method==='queue-qwen-forced-alignment-identity-pcm-on-encoded'){
    try{
      const {readQueueQwenClock,measureQueueQwenClock}=await import('./queue-qwen-alignment-clock.mjs');
      const clock=readQueueQwenClock(root,json(resolve(root,word.inputs.alignment.path)),{takeSha256:candidateSha,scriptSha256:digest(join(root,'story','locked-script.txt'))});
      const measured=measureQueueQwenClock(clock,json(resolve(root,word.inputs.cueSheet.path)).beats.flatMap(b=>b.narration?.words||[]));
    for(const key of ['ok','count','offsetMs','driftMs','p95AbsMs','words','pcmSha256','pcmSamples','requestId','sessionId','engineName','executionPrecision','terminalEndpointToleranceMs','terminalEndpointOvershootMs','gridMs','uncertaintyMs','modelRevision','rawTimestampMilliseconds'])if(JSON.stringify(measured[key])!==JSON.stringify(word[key]))throw Error(`queue Qwen clock ${key} differs from current inputs`);
      if(measured.ok!==true)throw Error('queue Qwen clock exceeds canonical40ms limits');
    }catch(e){errors.push(`invalid queue Qwen provenance: ${e.message}`);}
  } else if(word?.method==='hosted-forced-alignment-on-encoded'){
    try{
      const {readHostedClock,measureHostedClock}=await import('./hosted-alignment-clock.mjs');
      const clock=readHostedClock(root,json(resolve(root,word.inputs.alignment.path)),{takeSha256:candidateSha,scriptSha256:digest(join(root,'story','locked-script.txt'))});
      const measured=measureHostedClock(clock,json(resolve(root,word.inputs.cueSheet.path)).beats.flatMap(b=>b.narration?.words||[]));
      for(const key of ['ok','count','offsetMs','driftMs','p95AbsMs','words','pcmSha256','pcmSamples','providerLoss'])if(JSON.stringify(measured[key])!==JSON.stringify(word[key]))throw Error(`hosted clock ${key} differs from current inputs`);
      if(word.gridMs!==null||word.uncertaintyMs!==null||word.provider!=='elevenlabs'||measured.ok!==true)throw Error('hosted clock must preserve unknown uncertainty and canonical40ms offset/drift limits');
    }catch(e){errors.push(`invalid hosted alignment provenance: ${e.message}`);}
  } else if(word?.method==='asr-anchored-identity-pcm-on-encoded'){
    try{
      const {readDerivedAudioClock,measureDerivedAudioClock}=await import('./derived-audio-clock.mjs');
      const job=json(join(root,'job.json'));
      const clock=readDerivedAudioClock(root,json(resolve(root,word.inputs.alignment.path)),{takeSha256:candidateSha,scriptSha256:digest(join(root,'story','locked-script.txt')),allowAsrAnchored:job?.clockPolicy?.allowAsrAnchored===true});
      const measured=measureDerivedAudioClock(clock,json(resolve(root,word.inputs.cueSheet.path)).beats.flatMap(b=>b.narration?.words||[]));
      for(const key of ['ok','count','offsetMs','driftMs','p95AbsMs','words','pcmSha256','pcmSamples','pcmSampleRate','sourceAudioSha256'])if(JSON.stringify(measured[key])!==JSON.stringify(word[key]))throw Error(`derived ASR clock ${key} differs from current inputs`);
      if(word.gridMs!==80||measured.ok!==true)throw Error('derived ASR clock must retain80ms grid and40ms offset/drift limits');
    }catch(e){errors.push(`invalid derived ASR provenance: ${e.message}`);}
  } else if (word?.method === 'asr-anchored-alignment-on-encoded') {
    // Cloud ASR-anchored clock: release-eligible only where the job opted in (job.json clockPolicy.allowAsrAnchored).
    let job = null;
    try { job = json(join(root, 'job.json')); } catch { job = null; }
    if (job?.clockPolicy?.allowAsrAnchored !== true || word.gridMs !== 80) errors.push('word-sync report uses the cloud asr-anchored clock, which this job has not opted in to (job.json clockPolicy.allowAsrAnchored)');
  } else if (word && (word.method !== 'forced-alignment-on-encoded' || word.gridMs !== 80)) errors.push('word-sync report must name its native forced clock, verified preserved-PCM edit map, or verified hosted encoded alignment');
}
// No fluff: the narration check on the locked script, bound to the script it read (the timeline when there is one).
const narration = canonical(boundReport('qa/narration-check.json', 'media-studio/validate-narration', 'the locked script must pass the no-fluff check (validate-narration.mjs) before release'), 'qa/narration-check.json',
  [['hookSeconds', 'max', 5], ['redundantOverlap', 'max', 0.7], ['redundantMinContentWords', 'max', 3], ['noNewInformationMinContentWords', 'max', 4]]);
boundToInput(narration, 'qa/narration-check.json', ['timeline', 'screenplay'], 'locked script');
for (const adjudication of narration?.fluff?.scopeAdjudications ?? []) {
  boundToInput(narration, 'qa/narration-check.json', ['job'], 'scope qualification declaration');
  const key = Object.keys(narration.inputs ?? {}).find((k) => k.startsWith('scopeQualification')
    && narration.inputs[k]?.path === adjudication.evidence?.path && narration.inputs[k]?.sha256 === adjudication.evidence?.sha256);
  boundToInput(narration, 'qa/narration-check.json', key ? [key] : [], 'scope qualification evidence');
}
// Frame integrity on the exact encoded picture.
boundToCandidate(canonical(boundReport('qa/frame-integrity.json', 'media-studio/validate-frame-integrity', 'tiled frames and off-cut luma jumps must be checked on the exact candidate (validate-frame-integrity.mjs)'), 'qa/frame-integrity.json',
  [['tilePsnr', 'max', 32], ['lumaJump', 'max', 40], ['contrastFloor', 'max', 12], ['cutWindow', 'max', 0.25], ['sampleFps', 'min', 2]]), 'qa/frame-integrity.json');
if (job.kind === 'product-screencast') {
  // The cursor moved with purpose: the pointer-path gate on the capture receipt the picture came from. A beat's own
  // reasoned allowance lives in the cue plan or storyboard; the run-wide defaults stay at the floor.
  boundToInput(canonical(boundReport('qa/pointer-path.json', 'media-studio/validate-pointer-path', 'every take must pass the pointer-path gate (validate-pointer-path.mjs): one direction per beat, no wandering, no scroll return'), 'qa/pointer-path.json',
    [['maxReversals', 'max', 0], ['maxTravelRatio', 'max', 1.35], ['maxScrollReversals', 'max', 0], ['maxUnnamedMoves', 'max', 0], ['turnCos', 'min', -0.5]]), 'qa/pointer-path.json', ['receipt'], 'capture receipt');
  // Nothing morphed or cropped: every product clip at native scale, uncropped, unbarred, each ratio from its own viewport.
  boundToCandidate(canonical(boundReport('qa/picture-integrity.json', 'media-studio/validate-picture-integrity', 'product footage must pass the picture-integrity gate (validate-picture-integrity.mjs): no stretch, upscale, crop, bars or undeclared zoom, each ratio captured at its own viewport'), 'qa/picture-integrity.json',
    [['scaleTolerance', 'max', 0.005], ['barVariance', 'min', 4], ['barMinPx', 'max', 6], ['ratioTolerance', 'max', 0.02]]), 'qa/picture-integrity.json');
}
// The feed test: marketing cuts fail closed below the marketing floor (validate-marketing-readiness.mjs owns the list).
const MARKETING_FORMS = ['campaign-flagship', 'campaign-comparison', 'campaign-short', 'campaign-outreach', 'marketing-cutdown', 'social-clip', 'hero'];
if (job.marketing === true || job.kind === 'teaser' || MARKETING_FORMS.includes(job.programForm)) {
  const mk = canonical(boundReport('qa/marketing-readiness-check.json', 'media-studio/validate-marketing-readiness', 'a marketing cut releases only at or above the marketing floor (validate-marketing-readiness.mjs)'), 'qa/marketing-readiness-check.json',
    [['hookMaxSeconds', 'max', 2], ['endCardWindowSeconds', 'max', 8], ['beatToleranceMs', 'max', 80], ['beatHitRatio', 'min', 0.9], ['referencesRequired', 'min', 3]]);
  if (mk && mk.applies !== true) errors.push('qa/marketing-readiness-check.json did not apply the marketing floor to this job; rerun it with the job.json that declares the marketing cut.');
  boundToCandidate(mk, 'qa/marketing-readiness-check.json');
}
if (Object.hasOwn(CAMPAIGN_FORMS, job.programForm)) errors.push(...validateCampaign(root, job, timeline, graphics));
if (job.deliveryProfile || Object.hasOwn(CAMPAIGN_FORMS, job.programForm)) {
  try {
    const expected = frameFor(job);
    const actual = probeVideo(candidate);
    if (actual.width !== expected.width || actual.height !== expected.height) errors.push(`encoded frame ${actual.width}x${actual.height} does not match ${expected.profile} ${expected.width}x${expected.height}.`);
    const range = CAMPAIGN_FORMS[job.programForm];
    if (range && (!Number.isFinite(actual.duration) || actual.duration < range[0] || actual.duration > range[1] + 0.5)) errors.push(`${job.programForm} encoded duration must be ${range[0]}–${range[1]} seconds (0.5s encode tolerance).`);
    if (timeline && Math.abs(actual.duration - timeline.durationSeconds) > 1) errors.push('encoded duration differs from the narration timeline by more than one second.');
    if (Number.isFinite(job.durationSeconds) && Math.abs(actual.duration - job.durationSeconds) > 1) errors.push('encoded duration differs from job.durationSeconds by more than one second.');
  } catch (error) { errors.push(`cannot verify encoded frame and duration: ${error.message}`); }
}
const releasePath = join(root, "qa", "viewer-release-evidence.json");
if (!existsSync(releasePath)) errors.push("missing qa/viewer-release-evidence.json; skipped or quiet QA is not a release pass.");
let evidence;
if (!errors.length) evidence = json(releasePath);
const requireBoundPass = (name) => {
  const check = evidence?.[name];
  if (!check || check.status !== "PASS") errors.push(`${name} must be a PASS review.`);
  else if (check.candidateSha256 !== candidateSha) errors.push(`${name} is not bound to this encoded candidate.`);
  return check;
};
const workspaceFile = (path, label) => {
  if (!path || typeof path !== "string") { errors.push(`${label} path is required.`); return null; }
  const resolved = resolve(root, path);
  if (!withinRoot(resolved)) { errors.push(`${label} path escapes the job workspace.`); return null; }
  if (!existsSync(resolved)) { errors.push(`${label} file is missing: ${path}.`); return null; }
  return resolved;
};
const seconds = (value) => {
  const match = /^(\d{2}):(\d{2}):(\d{2})[,.](\d{3})$/.exec(value.trim());
  if (!match) return NaN;
  const [, h, m, s, ms] = match.map(Number);
  return m >= 60 || s >= 60 ? NaN : h * 3600 + m * 60 + s + ms / 1000;
};
const parseSrt = (text) => text.trim() ? text.trim().split(/\r?\n\s*\r?\n/).map((block) => {
  const lines = block.split(/\r?\n/).filter(Boolean);
  const timeIndex = lines.findIndex((line) => line.includes("-->"));
  const [startText, endText] = (lines[timeIndex] ?? "").split("-->");
  const captionLines = timeIndex < 0 ? [] : lines.slice(timeIndex + 1);
  const start = seconds(startText ?? ""); const end = seconds(endText ?? "");
  return { lines: captionLines, words: captionLines.join(" ").trim(), start, end, duration: end - start };
}) : [];
if (evidence) {
  if (evidence.candidate?.sha256 !== candidateSha) errors.push("release evidence is not bound to this encoded candidate.");
  const captions = requireBoundPass("captions");
  if (captions) {
    if (Object.hasOwn(CAMPAIGN_FORMS, job.programForm) && frameFor(job).height > frameFor(job).width && (captions.placementReviewed !== true || JSON.stringify(captions.region || null) !== JSON.stringify(job.campaign?.captionRegion || null))) errors.push('portrait campaign captions need a candidate-bound placement review matching captionRegion.');
    const captionPath = workspaceFile(captions.path, "captions");
    if (captionPath && digest(captionPath) !== captions.sha256) errors.push("captions hash does not match release evidence.");
    if (captionPath) {
      const cues = parseSrt(readFileSync(captionPath, "utf8"));
      if (!cues.length) errors.push("captions contain no readable cues.");
      let rateBound = null;
      const bound = captions.rateBoundReport;
      if (bound?.path) {
        const reportPath = workspaceFile(bound.path, "caption rate-bound report");
        if (reportPath && digest(reportPath) !== bound.sha256) errors.push("caption rate-bound report hash does not match release evidence.");
        else if (reportPath) rateBound = json(reportPath);
      }
      let previousEnd = -1;
      for (const [index, cue] of cues.entries()) {
        if (!cue.words || !Number.isFinite(cue.start) || !Number.isFinite(cue.end) || cue.start < 0 || cue.end <= cue.start) errors.push(`caption cue ${index + 1} has invalid or nonpositive timing.`);
        if (cue.start < previousEnd) errors.push(`caption cue ${index + 1} overlaps or is out of order.`);
        previousEnd = Math.max(previousEnd, cue.end);
        if (cue.lines.length > 2 || cue.lines.some((line) => line.length > 42) || cue.words.length > 84) errors.push(`caption cue ${index + 1} is a paragraph or exceeds readable line limits.`);
        if (Number.isFinite(cue.duration) && cue.duration > 0 && cue.words.length / cue.duration > 20) {
          const key = String(index + 1);
          const listed = Array.isArray(rateBound?.cues) && rateBound.cues.includes(index + 1);
          const intact = listed && rateBound?.texts?.[key] === cue.words;
          if (!intact) errors.push(`caption cue ${index + 1} exceeds 20 characters per second.`);
        }
      }
    }
  }
  const audio = requireBoundPass("audio");
  if (audio) {
    const reportPath = workspaceFile(audio.analyzerReport?.path, "audio analyzer report");
    if (reportPath && digest(reportPath) !== audio.analyzerReport?.sha256) errors.push("audio analyzer report hash does not match release evidence.");
    if (reportPath) {
      const measured = json(reportPath);
      if (measured.tool !== "ffmpeg-loudnorm" || measured.candidateSha256 !== candidateSha || measured.integratedLufs !== audio.integratedLufs || measured.truePeakDbtp !== audio.truePeakDbtp) errors.push("audio values must come from a candidate-bound ffmpeg-loudnorm analyzer report.");
    }
    const loudnessTarget = Number.isFinite(job.loudnessTargetLufs) ? job.loudnessTargetLufs : -16;
    if (!Number.isFinite(audio.integratedLufs) || audio.integratedLufs < loudnessTarget - 1.5 || audio.integratedLufs > loudnessTarget + 1.5 || !Number.isFinite(audio.truePeakDbtp) || audio.truePeakDbtp > -1) errors.push(`audio must measure ${loudnessTarget} LUFS ±1.5 and at or below -1 dBTP.`);
  }
  const pronunciation = requireBoundPass("pronunciation");
  if (pronunciation) {
    if (pronunciation.reference !== "authored-script") errors.push("pronunciation review must be grounded in the authored script, never an ASR transcript.");
    const scriptPath = workspaceFile(pronunciation.scriptPath, "authored script");
    if (scriptPath && digest(scriptPath) !== pronunciation.scriptSha256) errors.push("authored script hash does not match pronunciation review.");
    if (pronunciation.releaseEligible !== true) errors.push("pronunciation review is not release eligible.");
  }
  requireBoundPass("encodedVisualReview");
  const titles = requireBoundPass("titleReview");
  if (titles && (!Number.isInteger(titles.titleCount) || titles.titleCount < 0 || titles.titleCount > 1)) errors.push("exact encoded title review must confirm no more than one opening title treatment.");
  const actions = requireBoundPass("actionResultReview");
  if (actions) {
    const storyboardPath = join(root, 'story', 'storyboard.json');
    const stateReview = ['settled-state', 'conceptual-animation'].includes(actions.mode);
    const storyboard = stateReview && existsSync(storyboardPath) ? json(storyboardPath) : null;
    let candidateDurationSeconds;
    if (stateReview) {
      try { candidateDurationSeconds = probeVideo(candidate).duration; }
      catch { errors.push('cannot measure the encoded program duration for state/concept review.'); }
    }
    errors.push(...validateActionResultReview({job, storyboard, timeline, review: actions, candidateSha256: candidateSha, candidateDurationSeconds}));
  }
  const story = requireBoundPass("storyReview");
  if (story && !story.cta) errors.push("story review must confirm a concrete CTA.");
  if (story?.sequence && (!story.sequence.seriesId || !Number.isInteger(story.sequence.chapter))) errors.push("when a series sequence is declared, story review must provide seriesId and integer chapter.");
  if (graphics?.length) {
    const review = requireBoundPass('timedGraphicReview');
    if (review && (review.controlsVisible !== true || review.timingReviewed !== true)) errors.push('timed graphic review must confirm product controls remain visible and overlay timing was reviewed on the encoded candidate.');
    if (job.campaign?.continuity?.mode === 'labeled-vignettes' && review?.vignetteLabelsVisible !== true) errors.push('encoded review must confirm each vignette label is visible.');
  }
}
console.log(JSON.stringify({ ok: errors.length === 0, candidateSha256: candidateSha, errors }, null, 2));
process.exit(errors.length ? 1 : 0);
