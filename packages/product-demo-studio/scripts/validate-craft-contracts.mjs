#!/usr/bin/env node
// Produce a checksum-bound deterministic report for storyboard, capture, and final-render craft contracts.
// Usage: node validate-craft-contracts.mjs --candidate-id <id> --storyboard <path>
//   --storyboard-artifact-id <id> --capture-manifest <path> --capture-artifact-id <id>
//   --capture-evidence <path> --capture-evidence-artifact-id <id>
//   --render-timing <path> --render-timing-artifact-id <id>
//   --media <path> --media-artifact-id <id> --out <path>
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
};
const candidateId = flag("--candidate-id");
const storyboardPath = flag("--storyboard");
const storyboardArtifactId = flag("--storyboard-artifact-id");
const capturePath = flag("--capture-manifest");
const captureArtifactId = flag("--capture-artifact-id");
const captureEvidencePath = flag("--capture-evidence");
const captureEvidenceArtifactId = flag("--capture-evidence-artifact-id");
const rawCapturePath = flag("--raw-capture");
const rawCaptureArtifactId = flag("--raw-capture-artifact-id");
const renderTimingPath = flag("--render-timing");
const renderTimingArtifactId = flag("--render-timing-artifact-id");
const mediaPath = flag("--media");
const mediaArtifactId = flag("--media-artifact-id");
const outPath = flag("--out");
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

if (![candidateId, storyboardArtifactId, captureArtifactId, captureEvidenceArtifactId, rawCaptureArtifactId,
      renderTimingArtifactId, mediaArtifactId]
    .every((value) => SAFE_ID.test(value ?? "")) ||
    !storyboardPath || !capturePath || !captureEvidencePath || !rawCapturePath ||
    !renderTimingPath || !mediaPath || !outPath) {
  console.error(
    "Usage: node validate-craft-contracts.mjs --candidate-id <id> --storyboard <path> " +
    "--storyboard-artifact-id <id> --capture-manifest <path> --capture-artifact-id <id> " +
    "--capture-evidence <path> --capture-evidence-artifact-id <id> " +
    "--raw-capture <path> --raw-capture-artifact-id <id> " +
    "--render-timing <path> --render-timing-artifact-id <id> " +
    "--media <path> --media-artifact-id <id> --out <path>",
  );
  process.exit(2);
}

for (const [label, path] of [
  ["storyboard", storyboardPath],
  ["capture manifest", capturePath],
  ["capture evidence", captureEvidencePath],
  ["raw capture", rawCapturePath],
  ["render timing", renderTimingPath],
  ["final media", mediaPath],
]) {
  if (!existsSync(resolve(path))) {
    console.error(`Could not evaluate: ${label} does not exist at ${resolve(path)}.`);
    process.exit(2);
  }
}

const scriptDir = dirname(fileURLToPath(import.meta.url));
const command = process.argv.map((value) => JSON.stringify(value)).join(" ");
const generatedAt = new Date().toISOString();
const run = (script, path) => spawnSync(process.execPath, [resolve(scriptDir, script), resolve(path)], {
  encoding: "utf8",
});
const storyboardResult = run("validate-storyboard.mjs", storyboardPath);
const captureResult = run("validate-capture-manifest.mjs", capturePath);
const readJson = (path) => JSON.parse(readFileSync(resolve(path), "utf8"));
const decodeFrame = (seconds) => {
  const result = spawnSync("ffmpeg", [
    "-v", "error",
    "-ss", Number(seconds).toFixed(6),
    "-i", resolve(mediaPath),
    "-frames:v", "1",
    "-an",
    "-pix_fmt", "rgb24",
    "-f", "rawvideo",
    "-",
  ], { encoding: null, maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
    const detail = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8") : String(result.stderr ?? "");
    return { error: detail.trim() || `ffmpeg exited ${result.status}` };
  }
  return {
    bytes: result.stdout,
    sha256: createHash("sha256").update(result.stdout).digest("hex"),
  };
};
const decodeFrameHash = (seconds) => {
  const decoded = decodeFrame(seconds);
  return decoded.error ? decoded : { sha256: decoded.sha256 };
};
const analysisDimensions = (width, height) => {
  const analysisWidth = 320;
  const analysisHeight = Math.max(2, Math.round((height * analysisWidth / width) / 2) * 2);
  return { width: analysisWidth, height: analysisHeight };
};
const decodeAnalysisFrame = (seconds, width, height) => {
  const dimensions = analysisDimensions(width, height);
  const result = spawnSync("ffmpeg", [
    "-v", "error",
    "-ss", Number(seconds).toFixed(6),
    "-i", resolve(mediaPath),
    "-frames:v", "1",
    "-an",
    "-vf", `scale=${dimensions.width}:${dimensions.height}:flags=area,format=rgb24`,
    "-f", "rawvideo",
    "-",
  ], { encoding: null, maxBuffer: 16 * 1024 * 1024 });
  if (result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
    const detail = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8") : String(result.stderr ?? "");
    return { error: detail.trim() || `ffmpeg exited ${result.status}` };
  }
  return { bytes: result.stdout, ...dimensions };
};
const decodeAnalysisRange = (startSeconds, endSeconds, width, height) => {
  const dimensions = analysisDimensions(width, height);
  const durationSeconds = Math.max(0, endSeconds - startSeconds);
  const result = spawnSync("ffmpeg", [
    "-v", "error",
    "-i", resolve(mediaPath),
    "-ss", Number(startSeconds).toFixed(6),
    "-t", Number(durationSeconds).toFixed(6),
    "-map", "0:v:0",
    "-an",
    "-vf", `scale=${dimensions.width}:${dimensions.height}:flags=area,format=rgb24`,
    "-fps_mode", "passthrough",
    "-f", "rawvideo",
    "-",
  ], { encoding: null, maxBuffer: 256 * 1024 * 1024 });
  if (result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
    const detail = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8") : String(result.stderr ?? "");
    return { error: detail.trim() || `ffmpeg exited ${result.status}` };
  }
  const frameBytes = dimensions.width * dimensions.height * 3;
  if (result.stdout.length % frameBytes !== 0) return { error: "decoded analysis range is not frame aligned" };
  const frames = [];
  for (let offset = 0; offset < result.stdout.length; offset += frameBytes) {
    frames.push(result.stdout.subarray(offset, offset + frameBytes));
  }
  return { frames, ...dimensions };
};
const compareAnalysisFrames = (baseline, frame, changedChannelThreshold = 8) => {
  if (!Buffer.isBuffer(baseline) || !Buffer.isBuffer(frame) || baseline.length !== frame.length || baseline.length === 0) {
    return { error: "analysis frames have incompatible byte lengths" };
  }
  let totalDifference = 0;
  let changedPixels = 0;
  for (let index = 0; index < baseline.length; index += 3) {
    const red = Math.abs(baseline[index] - frame[index]);
    const green = Math.abs(baseline[index + 1] - frame[index + 1]);
    const blue = Math.abs(baseline[index + 2] - frame[index + 2]);
    totalDifference += red + green + blue;
    if (Math.max(red, green, blue) > changedChannelThreshold) changedPixels += 1;
  }
  return {
    meanAbsoluteDifference: totalDifference / baseline.length,
    changedPixelRatio: changedPixels / (baseline.length / 3),
  };
};
let alignmentErrors = [];
let measurements = [];
let renderMeasurements = [];
let sourceFrameBound = false;
let sourceGeometry = null;
let mediaProbe = null;
try {
  const storyboardDocument = readJson(storyboardPath);
  const captureDocument = readJson(capturePath);
  const captureEvidence = readJson(captureEvidencePath);
  const episodes = Array.isArray(storyboardDocument)
    ? storyboardDocument
    : (storyboardDocument.episodes ?? [storyboardDocument]);
  const captures = Array.isArray(captureDocument) ? captureDocument : (captureDocument.captures ?? [captureDocument]);
  const segments = new Map();
  for (const episode of episodes) {
    for (const segment of episode.segments ?? []) {
      const key = `${episode.episodeId}:${segment.id}`;
      if (segments.has(key)) alignmentErrors.push(`duplicate storyboard beat ${key}`);
      segments.set(key, { episode, segment });
    }
  }
  if (captureEvidence.candidateId !== candidateId) alignmentErrors.push("capture evidence candidateId does not match");
  const probe = spawnSync("ffprobe", [
    "-v", "error",
    "-select_streams", "v:0",
    "-show_entries", "stream=width,height",
    "-of", "json",
    resolve(rawCapturePath),
  ], { encoding: "utf8" });
  if (probe.status !== 0) {
    alignmentErrors.push(`raw capture geometry probe failed: ${(probe.stderr || probe.stdout).trim()}`);
  } else {
    const stream = JSON.parse(probe.stdout).streams?.[0];
    if (!Number.isInteger(stream?.width) || !Number.isInteger(stream?.height) || stream.width < 1 || stream.height < 1) {
      alignmentErrors.push("raw capture geometry probe returned no positive video dimensions");
    } else {
      sourceGeometry = {
        width: stream.width,
        height: stream.height,
        rawCaptureArtifactId,
        probe: "ffprobe",
      };
    }
  }
  const evidenceBeats = new Map();
  for (const beat of captureEvidence.beats ?? []) {
    const key = `${beat.episodeId}:${beat.storyboardSegmentId}`;
    if (evidenceBeats.has(key)) alignmentErrors.push(`duplicate capture-evidence beat ${key}`);
    evidenceBeats.set(key, beat);
  }
  sourceFrameBound = captures.length > 0 && captures.every((capture) => (
    capture.captureSurface?.sourceFrame?.width === sourceGeometry?.width &&
    capture.captureSurface?.sourceFrame?.height === sourceGeometry?.height
  ));
  if (captureEvidence.sourceFrame?.width !== sourceGeometry?.width ||
      captureEvidence.sourceFrame?.height !== sourceGeometry?.height) {
    alignmentErrors.push("capture evidence sourceFrame does not match probed raw capture bytes");
  }
  if (!sourceFrameBound) alignmentErrors.push("manifest sourceFrame does not match probed raw capture bytes");

  const captureKeys = new Set();
  for (const capture of captures) {
    const segmentId = capture.storyboardSegmentId;
    const key = `${capture.scenario}:${segmentId}`;
    if (captureKeys.has(key)) alignmentErrors.push(`duplicate capture manifest beat ${key}`);
    captureKeys.add(key);
    const entry = segments.get(key);
    const beat = evidenceBeats.get(key);
    if (!entry) {
      alignmentErrors.push(`${segmentId ?? "unknown"}: no matching storyboard episode/segment`);
      continue;
    }
    if (!beat) {
      alignmentErrors.push(`${segmentId}: no matching capture-evidence timing beat`);
      continue;
    }
    if (capture.interaction?.kind !== entry.segment.interaction?.kind) {
      alignmentErrors.push(`${segmentId}: interaction kind differs between storyboard and capture`);
    }
    if (capture.interaction?.target !== entry.segment.interaction?.target) {
      alignmentErrors.push(`${segmentId}: interaction target differs between storyboard and capture`);
    }
    const storyboardSync = entry.segment.interaction?.narrationSync;
    const manifestSync = capture.interaction?.narrationSync;
    for (const field of ["cursorLeadSeconds", "actionAtSeconds", "resultVisibleAtSeconds", "spokenResultAtSeconds"]) {
      if (!Number.isFinite(beat[field]) || beat[field] !== manifestSync?.[field] || beat[field] !== storyboardSync?.[field]) {
        alignmentErrors.push(`${segmentId}: ${field} differs across storyboard, manifest, and capture evidence`);
      }
    }
    if (!Number.isFinite(beat.cutAtSeconds) || beat.cutAtSeconds < beat.resultVisibleAtSeconds) {
      alignmentErrors.push(`${segmentId}: cutAtSeconds must be at or after the visible result`);
      continue;
    }
    measurements.push({
      beatId: `${capture.scenario}.${segmentId}`,
      cursorLeadSeconds: beat.cursorLeadSeconds,
      actionToResultSeconds: beat.resultVisibleAtSeconds - beat.actionAtSeconds,
      resultToSpokenSeconds: beat.spokenResultAtSeconds - beat.resultVisibleAtSeconds,
      resultHoldToCutSeconds: beat.cutAtSeconds - beat.resultVisibleAtSeconds,
      evidenceArtifactIds: [captureEvidenceArtifactId],
    });
  }
  for (const key of segments.keys()) {
    if (!captureKeys.has(key)) alignmentErrors.push(`${key}: storyboard beat has no capture manifest`);
    if (!evidenceBeats.has(key)) alignmentErrors.push(`${key}: storyboard beat has no capture-evidence timing beat`);
  }
  for (const key of captureKeys) if (!segments.has(key)) alignmentErrors.push(`${key}: capture manifest has no storyboard beat`);
  for (const key of evidenceBeats.keys()) if (!segments.has(key)) alignmentErrors.push(`${key}: capture evidence has no storyboard beat`);
  if (captureKeys.size !== segments.size || evidenceBeats.size !== segments.size) {
    alignmentErrors.push("storyboard, capture manifest, and capture evidence must form a complete one-to-one beat mapping");
  }

  const renderTiming = readJson(renderTimingPath);
  if (renderTiming.schemaVersion !== "1.0.0") alignmentErrors.push("render timing schemaVersion must be 1.0.0");
  if (renderTiming.candidateId !== candidateId) alignmentErrors.push("render timing candidateId does not match");
  if (renderTiming.status !== "PASS") alignmentErrors.push("render timing status must be PASS");
  if (!Number.isFinite(renderTiming.durationSeconds) || renderTiming.durationSeconds <= 0) {
    alignmentErrors.push("render timing durationSeconds must be positive");
  }
  if (!Number.isFinite(renderTiming.fps) || renderTiming.fps <= 0) {
    alignmentErrors.push("render timing fps must be positive");
  }

  const mediaProbeResult = spawnSync("ffprobe", [
    "-v", "error",
    "-select_streams", "v:0",
    "-show_entries", "stream=avg_frame_rate,width,height:format=duration",
    "-of", "json",
    resolve(mediaPath),
  ], { encoding: "utf8" });
  if (mediaProbeResult.status !== 0) {
    alignmentErrors.push(`final media probe failed: ${(mediaProbeResult.stderr || mediaProbeResult.stdout).trim()}`);
  } else {
    const probed = JSON.parse(mediaProbeResult.stdout);
    const durationSeconds = Number(probed.format?.duration);
    const stream = probed.streams?.[0];
    const width = Number(stream?.width);
    const height = Number(stream?.height);
    const [numerator, denominator] = String(stream?.avg_frame_rate ?? "0/1")
      .split("/").map(Number);
    const fps = denominator > 0 ? numerator / denominator : 0;
    if (!Number.isFinite(durationSeconds) || durationSeconds <= 0 || !Number.isFinite(fps) || fps <= 0 ||
        !Number.isInteger(width) || width < 1 || !Number.isInteger(height) || height < 1) {
      alignmentErrors.push("final media probe returned no positive duration/fps/dimensions");
    } else {
      mediaProbe = { durationSeconds, fps, width, height, mediaArtifactId, probe: "ffprobe" };
      const frameTolerance = 1 / fps + 0.001;
      if (Math.abs(renderTiming.durationSeconds - durationSeconds) > frameTolerance) {
        alignmentErrors.push("render timing duration does not match final media bytes");
      }
      if (Math.abs(renderTiming.fps - fps) > 0.01) {
        alignmentErrors.push("render timing fps does not match final media bytes");
      }
    }
  }

  const renderedBeats = new Map();
  for (const beat of renderTiming.beats ?? []) {
    const episodeId = beat.episodeId ?? renderTiming.episodeId;
    const segmentId = beat.storyboardSegmentId ?? beat.beatId;
    const key = `${episodeId}:${segmentId}`;
    if (renderedBeats.has(key)) alignmentErrors.push(`duplicate render-timing beat ${key}`);
    renderedBeats.set(key, beat);
  }
  const tolerance = mediaProbe ? 1 / mediaProbe.fps + 0.001 : 0.035;
  const orderedSegments = [...segments.entries()].sort(([, left], [, right]) => (
    left.segment.timelineStartSeconds - right.segment.timelineStartSeconds
  ));
  for (let index = 0; index < orderedSegments.length; index += 1) {
    const [key, entry] = orderedSegments[index];
    const rendered = renderedBeats.get(key);
    if (!rendered) {
      alignmentErrors.push(`${key}: storyboard beat has no render-timing beat`);
      continue;
    }
    const nextStart = orderedSegments[index + 1]?.[1]?.segment?.timelineStartSeconds;
    const expectedStart = entry.segment.timelineStartSeconds;
    const expectedAction = expectedStart + entry.segment.interaction.narrationSync.actionAtSeconds;
    const expectedResult = expectedStart + entry.segment.interaction.narrationSync.resultVisibleAtSeconds;
    const renderedStart = rendered.startsAtSeconds;
    const renderedEnd = rendered.endsAtSeconds;
    const renderedAction = rendered.actionAtSeconds;
    const renderedResult = rendered.resultVisibleAtSeconds;
    for (const [field, value] of [
      ["startsAtSeconds", renderedStart], ["endsAtSeconds", renderedEnd],
      ["actionAtSeconds", renderedAction], ["resultVisibleAtSeconds", renderedResult],
    ]) {
      if (!Number.isFinite(value) || value < 0) alignmentErrors.push(`${key}: ${field} must be a non-negative number`);
    }
    if (Number.isFinite(renderedStart) && Math.abs(renderedStart - expectedStart) > tolerance) {
      alignmentErrors.push(`${key}: rendered start differs from storyboard timeline`);
    }
    if (Number.isFinite(renderedAction) && Math.abs(renderedAction - expectedAction) > tolerance) {
      alignmentErrors.push(`${key}: rendered action differs from storyboard timeline`);
    }
    if (Number.isFinite(renderedResult) && Math.abs(renderedResult - expectedResult) > tolerance) {
      alignmentErrors.push(`${key}: rendered result differs from storyboard timeline`);
    }
    if (Number.isFinite(nextStart) && Number.isFinite(renderedEnd) && Math.abs(renderedEnd - nextStart) > tolerance) {
      alignmentErrors.push(`${key}: rendered end differs from the next storyboard beat`);
    }
    if (Number.isFinite(renderedStart) && Number.isFinite(renderedEnd) && renderedEnd <= renderedStart) {
      alignmentErrors.push(`${key}: rendered beat has no positive duration`);
    }
    const resultHoldSeconds = Number.isFinite(renderedEnd) && Number.isFinite(renderedResult)
      ? renderedEnd - renderedResult
      : -1;
    if (entry.segment.heroMoment && resultHoldSeconds + tolerance < entry.segment.resultHoldSeconds) {
      alignmentErrors.push(`${key}: rendered hero result hold is shorter than the storyboard contract`);
    }
    let frameHashesVerified = false;
    const endSampleAt = Number.isFinite(renderedEnd)
      ? Math.max(renderedStart, renderedEnd - (mediaProbe ? 1 / mediaProbe.fps : 1 / renderTiming.fps))
      : renderedEnd;
    const frameSamples = {
      start: renderedStart,
      action: renderedAction,
      result: renderedResult,
      end: endSampleAt,
    };
    const declaredFrameHashes = rendered.frameHashes;
    if (!declaredFrameHashes || typeof declaredFrameHashes !== "object") {
      alignmentErrors.push(`${key}: render-timing beat must checksum-bind decoded start/action/result/end frames`);
    } else {
      frameHashesVerified = true;
      for (const [phase, seconds] of Object.entries(frameSamples)) {
        const declared = declaredFrameHashes[phase];
        const decoded = Number.isFinite(seconds) ? decodeFrameHash(seconds) : { error: "invalid timestamp" };
        if (!/^[a-f0-9]{64}$/.test(declared ?? "") || decoded.error || decoded.sha256 !== declared) {
          frameHashesVerified = false;
          alignmentErrors.push(`${key}: ${phase} frame hash does not match decoded final media bytes${decoded.error ? ` (${decoded.error})` : ""}`);
        }
      }
    }
    const stateChangeRequired = entry.segment.interaction?.kind !== "hold";
    let stateChangeVerified = null;
    let stateChangeMeanAbsoluteDifference = null;
    let stateChangePixelRatio = null;
    const stateChangeMeanThreshold = 0.5;
    const stateChangePixelRatioThreshold = 0.001;
    if (stateChangeRequired && mediaProbe && Number.isFinite(renderedAction) && Number.isFinite(renderedResult)) {
      const beforeActionAt = Math.max(renderedStart, renderedAction - (1 / mediaProbe.fps));
      const beforeActionFrame = decodeAnalysisFrame(beforeActionAt, mediaProbe.width, mediaProbe.height);
      const resultFrame = decodeAnalysisFrame(renderedResult, mediaProbe.width, mediaProbe.height);
      if (beforeActionFrame.error || resultFrame.error) {
        alignmentErrors.push(`${key}: could not decode causal before/result frames`);
        stateChangeVerified = false;
      } else {
        const comparison = compareAnalysisFrames(beforeActionFrame.bytes, resultFrame.bytes);
        if (comparison.error) {
          alignmentErrors.push(`${key}: could not compare causal before/result frames (${comparison.error})`);
          stateChangeVerified = false;
        } else {
          stateChangeMeanAbsoluteDifference = comparison.meanAbsoluteDifference;
          stateChangePixelRatio = comparison.changedPixelRatio;
          stateChangeVerified = comparison.meanAbsoluteDifference >= stateChangeMeanThreshold ||
            comparison.changedPixelRatio >= stateChangePixelRatioThreshold;
          if (!stateChangeVerified) {
            alignmentErrors.push(`${key}: encoded action/result frames do not show a meaningful visible state change`);
          }
        }
      }
    }
    let stableHoldSeconds = null;
    let stableFrameSampleCount = 0;
    let stableFramesStable = null;
    let stableFrameMaxMeanAbsoluteDifference = null;
    let stableFrameMaxChangedPixelRatio = null;
    const stableFrameThreshold = entry.segment.endCard ? 1 : null;
    const stableFrameChangedPixelRatioThreshold = entry.segment.endCard ? 0.0005 : null;
    if (entry.segment.endCard) {
      if (!Number.isFinite(rendered.stableFromSeconds)) {
        alignmentErrors.push(`${key}: end-card beat must declare stableFromSeconds`);
      } else {
        stableHoldSeconds = renderedEnd - rendered.stableFromSeconds;
        if (rendered.stableFromSeconds < renderedStart - tolerance || stableHoldSeconds + tolerance < 3) {
          alignmentErrors.push(`${key}: final end card must be fully stable for at least three seconds`);
        } else {
          const decodedRange = mediaProbe
            ? decodeAnalysisRange(rendered.stableFromSeconds, renderedEnd, mediaProbe.width, mediaProbe.height)
            : { error: "media probe unavailable" };
          if (decodedRange.error) {
            alignmentErrors.push(`${key}: could not decode every stable end-card frame (${decodedRange.error})`);
            stableFramesStable = false;
          } else {
            const stableFrames = decodedRange.frames;
            stableFrameSampleCount = stableFrames.length;
            if (stableFrames.length >= 2) {
              const baseline = stableFrames[0];
              let maxMeanDifference = 0;
              let maxChangedPixelRatio = 0;
              for (const frame of stableFrames.slice(1)) {
                const comparison = compareAnalysisFrames(baseline, frame);
                if (comparison.error) {
                  stableFramesStable = false;
                  break;
                }
                maxMeanDifference = Math.max(maxMeanDifference, comparison.meanAbsoluteDifference);
                maxChangedPixelRatio = Math.max(maxChangedPixelRatio, comparison.changedPixelRatio);
              }
              stableFrameMaxMeanAbsoluteDifference = maxMeanDifference;
              stableFrameMaxChangedPixelRatio = maxChangedPixelRatio;
              stableFramesStable = stableFramesStable !== false &&
                maxMeanDifference <= stableFrameThreshold &&
                maxChangedPixelRatio <= stableFrameChangedPixelRatioThreshold;
            } else {
              stableFramesStable = false;
            }
          }
          if (!stableFramesStable) {
            const differenceDetail = Number.isFinite(stableFrameMaxMeanAbsoluteDifference)
              ? ` (max mean RGB difference ${stableFrameMaxMeanAbsoluteDifference.toFixed(4)}, ` +
                `max changed-pixel ratio ${(stableFrameMaxChangedPixelRatio ?? 0).toFixed(6)})`
              : "";
            alignmentErrors.push(`${key}: final end card changes after stableFromSeconds${differenceDetail}`);
          }
        }
      }
    }
    if ([renderedStart, renderedEnd, renderedAction, renderedResult].every(Number.isFinite)) {
      renderMeasurements.push({
        beatId: `${entry.episode.episodeId}.${entry.segment.id}`,
        startDeltaSeconds: Math.abs(renderedStart - expectedStart),
        actionDeltaSeconds: Math.abs(renderedAction - expectedAction),
        resultDeltaSeconds: Math.abs(renderedResult - expectedResult),
        endDeltaSeconds: Number.isFinite(nextStart) ? Math.abs(renderedEnd - nextStart) : 0,
        resultHoldSeconds: Math.max(0, resultHoldSeconds),
        stableHoldSeconds,
        frameHashesVerified,
        stateChangeRequired,
        stateChangeVerified,
        stateChangeMeanAbsoluteDifference,
        stateChangePixelRatio,
        stateChangeMeanThreshold,
        stateChangePixelRatioThreshold,
        stableFrameSampleCount,
        stableFramesStable,
        stableFrameMaxMeanAbsoluteDifference,
        stableFrameMaxChangedPixelRatio,
        stableFrameThreshold,
        stableFrameChangedPixelRatioThreshold,
        evidenceArtifactIds: [renderTimingArtifactId, mediaArtifactId],
      });
    }
  }
  for (const key of renderedBeats.keys()) {
    if (!segments.has(key)) alignmentErrors.push(`${key}: render-timing beat has no storyboard beat`);
  }
  if (renderedBeats.size !== segments.size) {
    alignmentErrors.push("storyboard and render timing must form a complete one-to-one beat mapping");
  }
  const firstRendered = orderedSegments.length > 0 ? renderedBeats.get(orderedSegments[0][0]) : null;
  const lastRendered = orderedSegments.length > 0 ? renderedBeats.get(orderedSegments.at(-1)[0]) : null;
  if (!firstRendered || Math.abs(firstRendered.startsAtSeconds) > tolerance) {
    alignmentErrors.push("final render must start on the first storyboard beat at zero seconds");
  }
  if (lastRendered && mediaProbe && Math.abs(lastRendered.endsAtSeconds - mediaProbe.durationSeconds) > tolerance) {
    alignmentErrors.push("final render must end on the last storyboard beat");
  }
} catch (error) {
  alignmentErrors.push(`capture/storyboard alignment could not be evaluated: ${error.message}`);
}
const checks = [
  {
    id: "storyboard-craft-contract",
    passed: storyboardResult.status === 0,
    evidenceArtifactIds: [storyboardArtifactId],
  },
  {
    id: "capture-manifest-craft-contract",
    passed: captureResult.status === 0 && sourceFrameBound,
    evidenceArtifactIds: [captureArtifactId, captureEvidenceArtifactId, rawCaptureArtifactId],
  },
  {
    id: "beat-timing-deltas",
    passed: storyboardResult.status === 0 && captureResult.status === 0 && alignmentErrors.length === 0,
    evidenceArtifactIds: [storyboardArtifactId, captureArtifactId, captureEvidenceArtifactId, rawCaptureArtifactId],
  },
  {
    id: "rendered-story-contract",
    passed: storyboardResult.status === 0 && alignmentErrors.length === 0 && mediaProbe !== null,
    evidenceArtifactIds: [storyboardArtifactId, renderTimingArtifactId, mediaArtifactId],
  },
];
const failed = checks.filter((check) => !check.passed).length;
const hash = (path) => createHash("sha256").update(readFileSync(resolve(path))).digest("hex");
const report = {
  schemaVersion: "1.0.0",
  candidateId,
  reportType: "craftContractValidation",
  status: failed === 0 ? "PASS" : "FAIL",
  generator: {
    tool: "product-demo-studio-craft-contract-validator",
    version: "1.1.0",
    command,
  },
  inputs: [
    { artifactId: storyboardArtifactId, sha256: hash(storyboardPath) },
    { artifactId: captureArtifactId, sha256: hash(capturePath) },
    { artifactId: captureEvidenceArtifactId, sha256: hash(captureEvidencePath) },
    { artifactId: rawCaptureArtifactId, sha256: hash(rawCapturePath) },
    { artifactId: renderTimingArtifactId, sha256: hash(renderTimingPath) },
    { artifactId: mediaArtifactId, sha256: hash(mediaPath) },
  ],
  checks,
  measurements,
  renderMeasurements,
  sourceGeometry,
  mediaProbe,
  summary: { total: checks.length, passed: checks.length - failed, failed },
  generatedAt,
};

mkdirSync(dirname(resolve(outPath)), { recursive: true });
writeFileSync(resolve(outPath), `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(`Craft contract report: ${resolve(outPath)}`);
for (const error of alignmentErrors) console.error(`[error] ${error}`);
process.exit(failed === 0 ? 0 : 1);
