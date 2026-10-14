#!/usr/bin/env node
// Fail closed on evidence bound to the exact encoded product-demo candidate.
// Usage: node validate-viewer-release.mjs <jobRoot> <candidate.mp4>
import { existsSync, readFileSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { isAbsolute, join, relative, resolve } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

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
      if (picture.generator !== 'media-studio/validate-encoded-picture' || picture.ok !== true || !Array.isArray(picture.errors) || picture.errors.length) errors.push('encoded-picture report must be a PASS with no errors from validate-encoded-picture.');
      if (picture.candidate?.sha256 !== candidateSha || picture.candidate?.bytes !== (candidateSha ? statSync(candidate).size : null)) errors.push('encoded-picture report is not bound to the exact candidate SHA-256 and byte count.');
      if (picture.thresholds?.maxStaticSeconds !== 6 || picture.thresholds?.bindMaxHamming !== 12) errors.push('encoded-picture report must use canonical static and source-binding thresholds.');
      if (!Number.isFinite(picture.screenRatio) || picture.screenRatio < .7 || !Array.isArray(picture.segments) || !picture.segments.some((segment) => segment.bound === true) || picture.segments.some((segment) => segment.bound === false)) errors.push('encoded-picture report lacks passing screen coverage and source-bound segments.');
    } catch (error) { errors.push(`cannot read encoded-picture report: ${error.message}`); }
  }
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
      let previousEnd = -1;
      for (const [index, cue] of cues.entries()) {
        if (!cue.words || !Number.isFinite(cue.start) || !Number.isFinite(cue.end) || cue.start < 0 || cue.end <= cue.start) errors.push(`caption cue ${index + 1} has invalid or nonpositive timing.`);
        if (cue.start < previousEnd) errors.push(`caption cue ${index + 1} overlaps or is out of order.`);
        previousEnd = Math.max(previousEnd, cue.end);
        if (cue.lines.length > 2 || cue.lines.some((line) => line.length > 42) || cue.words.length > 84) errors.push(`caption cue ${index + 1} is a paragraph or exceeds readable line limits.`);
        if (!Number.isFinite(cue.duration) || cue.duration <= 0 || cue.words.length / cue.duration > 20) errors.push(`caption cue ${index + 1} exceeds 20 characters per second.`);
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
    if (!Number.isFinite(audio.integratedLufs) || audio.integratedLufs < -17.5 || audio.integratedLufs > -14.5 || !Number.isFinite(audio.truePeakDbtp) || audio.truePeakDbtp > -1) errors.push("audio must measure -16 LUFS ±1.5 and at or below -1 dBTP.");
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
  if (actions && (!Array.isArray(actions.events) || !actions.events.length)) errors.push("action-result review needs observed events.");
  for (const event of actions?.events ?? []) {
    const times = [event.actionAtSeconds, event.resultVisibleAtSeconds, event.spokenResultAtSeconds];
    if (!event.segmentId || times.some((time) => !Number.isFinite(time) || time < 0)) errors.push("action-result event must include finite nonnegative action, visible-result, and spoken-result timing.");
    else if (event.resultVisibleAtSeconds < event.actionAtSeconds || event.spokenResultAtSeconds < event.resultVisibleAtSeconds) errors.push(`action-result event ${event.segmentId} announces a result before the picture proves it.`);
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
