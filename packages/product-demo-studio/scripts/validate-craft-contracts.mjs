#!/usr/bin/env node
// Produce a checksum-bound deterministic report for the storyboard and capture-manifest craft contracts.
// Usage: node validate-craft-contracts.mjs --candidate-id <id> --storyboard <path>
//   --storyboard-artifact-id <id> --capture-manifest <path> --capture-artifact-id <id>
//   --capture-evidence <path> --capture-evidence-artifact-id <id> --out <path>
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
const outPath = flag("--out");
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

if (![candidateId, storyboardArtifactId, captureArtifactId, captureEvidenceArtifactId, rawCaptureArtifactId]
    .every((value) => SAFE_ID.test(value ?? "")) ||
    !storyboardPath || !capturePath || !captureEvidencePath || !rawCapturePath || !outPath) {
  console.error(
    "Usage: node validate-craft-contracts.mjs --candidate-id <id> --storyboard <path> " +
    "--storyboard-artifact-id <id> --capture-manifest <path> --capture-artifact-id <id> " +
    "--capture-evidence <path> --capture-evidence-artifact-id <id> " +
    "--raw-capture <path> --raw-capture-artifact-id <id> --out <path>",
  );
  process.exit(2);
}

for (const [label, path] of [
  ["storyboard", storyboardPath],
  ["capture manifest", capturePath],
  ["capture evidence", captureEvidencePath],
  ["raw capture", rawCapturePath],
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
let alignmentErrors = [];
let measurements = [];
let sourceFrameBound = false;
let sourceGeometry = null;
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
    version: "1.0.0",
    command,
  },
  inputs: [
    { artifactId: storyboardArtifactId, sha256: hash(storyboardPath) },
    { artifactId: captureArtifactId, sha256: hash(capturePath) },
    { artifactId: captureEvidenceArtifactId, sha256: hash(captureEvidencePath) },
    { artifactId: rawCaptureArtifactId, sha256: hash(rawCapturePath) },
  ],
  checks,
  measurements,
  sourceGeometry,
  summary: { total: checks.length, passed: checks.length - failed, failed },
  generatedAt,
};

mkdirSync(dirname(resolve(outPath)), { recursive: true });
writeFileSync(resolve(outPath), `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(`Craft contract report: ${resolve(outPath)}`);
for (const error of alignmentErrors) console.error(`[error] ${error}`);
process.exit(failed === 0 ? 0 : 1);
