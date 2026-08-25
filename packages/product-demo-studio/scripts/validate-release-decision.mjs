#!/usr/bin/env node
// Validate one read-only arbiter decision and every referenced immutable artifact.
// All paths in the decision and referenced reports are resolved from the decision directory.
// Usage: node validate-release-decision.mjs <path-to-release-decision.json>
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const inputArgument = process.argv[2];
if (!inputArgument || process.argv.length !== 3) {
  console.error("Usage: node validate-release-decision.mjs <path-to-release-decision.json>");
  process.exit(1);
}

const inputPath = resolve(inputArgument);
const decisionDir = dirname(inputPath);
const scriptDir = dirname(fileURLToPath(import.meta.url));
const canonicalPolicyPath = resolve(scriptDir, "..", "policy", "product-video-policy.json");
const canonicalPreflightSchemaPath = resolve(scriptDir, "..", "schemas", "preflight-report.schema.json");
const reviewValidatorPath = resolve(scriptDir, "validate-review-report.mjs");
const executionReceiptValidatorPath = resolve(scriptDir, "validate-execution-receipt.mjs");
const preflightValidatorPath = resolve(scriptDir, "preflight.mjs");
const readinessValidatorPath = resolve(scriptDir, "validate-demo-readiness.mjs");
const DOMAINS = [
  "story-experience",
  "screen-accuracy-compliance",
  "audio-captions-synchronization",
  "technical-frame-integrity",
];
const DECISIONS = new Set(["PASS", "REMEDIATE", "PRODUCT_BLOCKED", "PIPELINE_BLOCKED"]);
const DISPOSITIONS = new Set(["accepted", "rejected-unsupported", "duplicate"]);
const SHA256 = /^[a-f0-9]{64}$/;
const FINDING_ID = /^PVF-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const DECISION_ID = /^PVD-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const PREFLIGHT_ID = /^PVP-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const AUDIO_REPORT_ID = /^PVAR-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const AUDIO_ADJUDICATION_ID = /^PVAA-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const errors = [];

function fail(path, message) {
  errors.push(`${path}: ${message}`);
}

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactObject(value, path, required, optional = []) {
  if (!object(value)) {
    fail(path, "must be an object.");
    return false;
  }
  const allowed = new Set([...required, ...optional]);
  for (const key of required) if (!Object.hasOwn(value, key)) fail(path, `missing required property "${key}".`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(path, `unknown property "${key}".`);
  return true;
}

function nonEmpty(value, path) {
  if (typeof value !== "string" || value.trim().length === 0) {
    fail(path, "must be a non-empty string.");
    return false;
  }
  return true;
}

function matches(value, pattern, path, description) {
  if (typeof value !== "string" || !pattern.test(value)) {
    fail(path, `must be ${description}.`);
    return false;
  }
  return true;
}

function sha(value, path) {
  return matches(value, SHA256, path, "a lowercase 64-character SHA-256 digest");
}

function dateTime(value, path) {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) fail(path, "must be a valid RFC 3339 date-time.");
}

function uniqueStrings(values, path, { minItems = 0, pattern } = {}) {
  if (!Array.isArray(values)) {
    fail(path, "must be an array.");
    return new Set();
  }
  if (values.length < minItems) fail(path, `must contain at least ${minItems} item(s).`);
  const seen = new Set();
  values.forEach((value, index) => {
    if (typeof value !== "string" || value.trim().length === 0) fail(`${path}[${index}]`, "must be a non-empty string.");
    else if (pattern && !pattern.test(value)) fail(`${path}[${index}]`, "has an invalid format.");
    if (seen.has(value)) fail(`${path}[${index}]`, `duplicates "${value}".`);
    seen.add(value);
  });
  return seen;
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function resolveDecisionPath(value, path) {
  if (!nonEmpty(value, path)) return undefined;
  return resolve(decisionDir, value);
}

function readArtifact(pathValue, expectedSha, jsonPath) {
  const absolutePath = resolveDecisionPath(pathValue, `${jsonPath}.artifactPath`);
  if (!sha(expectedSha, `${jsonPath}.sha256`) || !absolutePath) return undefined;
  if (!existsSync(absolutePath)) {
    fail(`${jsonPath}.artifactPath`, `does not exist at "${absolutePath}".`);
    return undefined;
  }
  let stats;
  try {
    stats = statSync(absolutePath);
  } catch (error) {
    fail(`${jsonPath}.artifactPath`, `cannot be inspected: ${error.message}`);
    return undefined;
  }
  if (!stats.isFile()) {
    fail(`${jsonPath}.artifactPath`, "must reference a file.");
    return undefined;
  }
  let bytes;
  try {
    bytes = readFileSync(absolutePath);
  } catch (error) {
    fail(`${jsonPath}.artifactPath`, `cannot be read: ${error.message}`);
    return undefined;
  }
  const actualSha = digest(bytes);
  if (actualSha !== expectedSha) fail(`${jsonPath}.sha256`, `does not match "${absolutePath}" (actual ${actualSha}).`);
  return { absolutePath, bytes, actualSha, size: stats.size };
}

function parseJsonArtifact(artifact, jsonPath) {
  if (!artifact) return undefined;
  try {
    return JSON.parse(artifact.bytes.toString("utf8"));
  } catch (error) {
    fail(jsonPath, `must contain valid JSON: ${error.message}`);
    return undefined;
  }
}

function validateCandidate(value, path, { requireBytes = true, requireDecodableVideo = requireBytes } = {}) {
  const required = ["candidateId", "artifactPath", "sha256", "sourceRevision", "renderProvenanceId"];
  if (requireBytes) required.splice(3, 0, "bytes");
  if (!exactObject(value, path, required)) return undefined;
  matches(value.candidateId, SAFE_ID, `${path}.candidateId`, "a safe candidate identifier");
  nonEmpty(value.artifactPath, `${path}.artifactPath`);
  sha(value.sha256, `${path}.sha256`);
  if (requireBytes && (!Number.isInteger(value.bytes) || value.bytes < 1)) fail(`${path}.bytes`, "must be a positive integer.");
  nonEmpty(value.sourceRevision, `${path}.sourceRevision`);
  nonEmpty(value.renderProvenanceId, `${path}.renderProvenanceId`);
  const artifact = readArtifact(value.artifactPath, value.sha256, path);
  if (artifact && requireBytes && artifact.size !== value.bytes) {
    fail(`${path}.bytes`, `does not match "${artifact.absolutePath}" (actual ${artifact.size}).`);
  }
  if (artifact && requireDecodableVideo) {
    const probe = spawnSync("ffprobe", [
      "-v", "error",
      "-show_entries", "format=duration:stream=codec_type",
      "-of", "json",
      artifact.absolutePath,
    ], { encoding: "utf8" });
    if (probe.status !== 0) {
      fail(`${path}.artifactPath`, `is not a decodable media candidate: ${(probe.stderr || probe.stdout).trim()}`);
    } else {
      try {
        const metadata = JSON.parse(probe.stdout);
        const duration = Number(metadata.format?.duration);
        const hasVideo = metadata.streams?.some((stream) => stream.codec_type === "video");
        if (!hasVideo || !Number.isFinite(duration) || duration <= 0) {
          fail(`${path}.artifactPath`, "must contain a non-empty video stream.");
        }
      } catch (error) {
        fail(`${path}.artifactPath`, `ffprobe returned invalid JSON: ${error.message}`);
      }
    }
  }
  return artifact
    ? {
        candidateId: value.candidateId,
        absolutePath: artifact.absolutePath,
        sha256: value.sha256,
        sourceRevision: value.sourceRevision,
        renderProvenanceId: value.renderProvenanceId,
      }
    : undefined;
}

function validateRecomputedPreflight(evidenceArtifact, storedPreflight, candidate, path) {
  if (!evidenceArtifact || !storedPreflight || !candidate) return;
  const root = mkdtempSync(resolve(tmpdir(), "product-demo-studio-release-preflight-"));
  const outPath = resolve(root, "recomputed-preflight.json");
  try {
    const result = spawnSync(process.execPath, [
      preflightValidatorPath,
      "--evidence-package", evidenceArtifact.absolutePath,
      "--out", outPath,
    ], { encoding: "utf8" });
    if (result.status !== 0 || !existsSync(outPath)) {
      fail(path, `bound evidence package does not pass canonical preflight: ${(result.stderr || result.stdout).trim()}`);
      return;
    }
    let recomputed;
    let evidence;
    try {
      recomputed = JSON.parse(readFileSync(outPath, "utf8"));
      evidence = JSON.parse(evidenceArtifact.bytes.toString("utf8"));
    } catch (error) {
      fail(path, `cannot parse recomputed preflight/evidence package: ${error.message}`);
      return;
    }
    if (recomputed.status !== "PASS" || recomputed.readyForIndependentReview !== true) {
      fail(path, "recomputed canonical preflight did not pass.");
    }
    if (recomputed.candidateId !== storedPreflight.candidateId ||
        recomputed.candidateId !== candidate.candidateId) {
      fail(path, "recomputed preflight candidateId differs from the stored preflight or decision.");
    }
    const storedChecks = new Map((storedPreflight.checks ?? []).map((check) => [check.id, check]));
    for (const check of recomputed.checks ?? []) {
      const stored = storedChecks.get(check.id);
      if (!stored || stored.passed !== check.passed ||
          JSON.stringify([...(stored.evidenceArtifactIds ?? [])].sort()) !==
            JSON.stringify([...(check.evidenceArtifactIds ?? [])].sort())) {
        fail(path, `stored preflight check "${check.id}" differs from recomputed evidence.`);
      }
    }

    const mediaId = evidence.candidate?.mediaArtifactId;
    const mediaArtifact = evidence.artifacts?.find((artifactValue) => artifactValue.artifactId === mediaId);
    if (!mediaArtifact) {
      fail(path, "evidence package candidate does not identify a media artifact.");
      return;
    }
    const mediaPath = resolve(dirname(evidenceArtifact.absolutePath), mediaArtifact.artifactPath);
    if (mediaPath !== candidate.absolutePath ||
        mediaArtifact.sha256 !== candidate.sha256 ||
        mediaArtifact.bytes !== statSync(candidate.absolutePath).size) {
      fail(path, "evidence package media artifact does not bind the exact release candidate bytes.");
    }
    if (evidence.provenance?.source?.revision !== candidate.sourceRevision) {
      fail(path, "evidence package source revision differs from the release candidate.");
    }
    if (evidence.provenance?.render?.renderId !== candidate.renderProvenanceId) {
      fail(path, "evidence package render provenance differs from the release candidate.");
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function sameCandidate(actual, expected, path) {
  if (!actual || !expected) return;
  for (const field of ["candidateId", "absolutePath", "sha256", "sourceRevision", "renderProvenanceId"]) {
    if (actual[field] !== expected[field]) fail(path, `${field} does not match the release candidate.`);
  }
}

function probeCandidateDuration(candidate, path) {
  if (!candidate) return undefined;
  const probe = spawnSync("ffprobe", [
    "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", candidate.absolutePath,
  ], { encoding: "utf8" });
  const duration = Number(probe.stdout?.trim());
  if (probe.status !== 0 || !Number.isFinite(duration) || duration <= 0) {
    fail(path, `could not probe a positive candidate duration: ${(probe.stderr || probe.stdout).trim()}`);
    return undefined;
  }
  return duration;
}

function decodeCandidateFrameSha(candidate, seconds, path) {
  if (!candidate || !Number.isFinite(seconds) || seconds < 0) return undefined;
  const result = spawnSync("ffmpeg", [
    "-v", "error",
    "-ss", seconds.toFixed(6),
    "-i", candidate.absolutePath,
    "-frames:v", "1",
    "-an",
    "-pix_fmt", "rgb24",
    "-f", "rawvideo",
    "-",
  ], { encoding: null, maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
    const detail = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8") : String(result.stderr ?? "");
    fail(path, `could not decode candidate frame at ${seconds.toFixed(6)}s: ${detail.trim() || `ffmpeg exited ${result.status}`}`);
    return undefined;
  }
  return digest(result.stdout);
}

function validateBoundArtifactReference(reference, path) {
  if (!exactObject(reference, path, ["artifactPath", "sha256", "bytes"])) return undefined;
  if (!Number.isInteger(reference.bytes) || reference.bytes < 1) fail(`${path}.bytes`, "must be a positive integer.");
  const artifact = readArtifact(reference.artifactPath, reference.sha256, path);
  if (artifact && artifact.size !== reference.bytes) {
    fail(`${path}.bytes`, `does not match "${artifact.absolutePath}" (actual ${artifact.size}).`);
  }
  return artifact;
}

function sameArtifactReference(actual, expected, path) {
  if (!object(actual) || !object(expected)) return;
  for (const field of ["sha256", "bytes"]) {
    if (actual[field] !== expected[field]) fail(`${path}.${field}`, "does not match the bound perception report.");
  }
  const actualPath = resolveDecisionPath(actual.artifactPath, `${path}.artifactPath`);
  const expectedPath = resolveDecisionPath(expected.artifactPath, `${path}.artifactPath`);
  if (actualPath && expectedPath && actualPath !== expectedPath) {
    fail(`${path}.artifactPath`, "does not identify the bound perception report.");
  }
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (object(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function validateModelReceipt(reference, nativeModel, path) {
  const artifact = validateBoundArtifactReference(reference, path);
  const receipt = parseJsonArtifact(artifact, `${path}.document`);
  if (!object(receipt)) return undefined;
  if (!exactObject(receipt, `${path}.document`, ["schemaVersion", "modelId", "revision", "license", "artifacts", "installedAt"])) return receipt;
  if (receipt.schemaVersion !== "1.0.0") fail(`${path}.document.schemaVersion`, 'must equal "1.0.0".');
  nonEmpty(receipt.modelId, `${path}.document.modelId`);
  nonEmpty(receipt.revision, `${path}.document.revision`);
  nonEmpty(receipt.license, `${path}.document.license`);
  dateTime(receipt.installedAt, `${path}.document.installedAt`);
  if (nativeModel) {
    if (receipt.modelId !== nativeModel.id) fail(`${path}.document.modelId`, "must match the native listen report model id.");
    if (receipt.revision !== nativeModel.revision) fail(`${path}.document.revision`, "must match the native listen report model revision.");
    const canonicalReceiptSha = digest(Buffer.from(canonicalJson(receipt), "utf8"));
    if (canonicalReceiptSha !== nativeModel.receiptSha256) {
      fail(`${path}.document`, `canonical receipt hash does not match the native listen report (actual ${canonicalReceiptSha}).`);
    }
  }
  if (!Array.isArray(receipt.artifacts) || receipt.artifacts.length === 0) {
    fail(`${path}.document.artifacts`, "must bind at least one model artifact hash.");
  } else {
    receipt.artifacts.forEach((entry, index) => {
      const entryPath = `${path}.document.artifacts[${index}]`;
      if (!exactObject(entry, entryPath, ["path", "bytes", "sha256"])) return;
      nonEmpty(entry.path, `${entryPath}.path`);
      if (!Number.isInteger(entry.bytes) || entry.bytes < 1) fail(`${entryPath}.bytes`, "must be a positive integer.");
      sha(entry.sha256, `${entryPath}.sha256`);
    });
  }
  return receipt;
}

function validateNativeDecodedAudio(decoded, candidate, path) {
  if (!exactObject(decoded, path, [
    "artifactPath", "sha256", "bytes", "sampleRate", "channels", "bitsPerSample",
    "sampleCount", "durationSeconds", "coverage", "sourceAudioStream", "sourceProbe", "decoder",
  ])) return;
  const decodedArtifact = validateBoundArtifactReference({
    artifactPath: decoded.artifactPath,
    sha256: decoded.sha256,
    bytes: decoded.bytes,
  }, path);
  if (decoded.sampleRate !== 16000) fail(`${path}.sampleRate`, "must equal 16000.");
  if (decoded.channels !== 1) fail(`${path}.channels`, "must equal 1.");
  if (decoded.bitsPerSample !== 16) fail(`${path}.bitsPerSample`, "must equal 16.");
  if (!Number.isInteger(decoded.sampleCount) || decoded.sampleCount < 1) fail(`${path}.sampleCount`, "must be a positive integer.");
  if (typeof decoded.durationSeconds !== "number" || decoded.durationSeconds <= 0) fail(`${path}.durationSeconds`, "must be positive.");
  if (Number.isInteger(decoded.sampleCount) && Math.abs(decoded.durationSeconds - (decoded.sampleCount / 16000)) > 0.000001) {
    fail(`${path}.durationSeconds`, "must equal sampleCount / 16000.");
  }
  if (exactObject(decoded.coverage, `${path}.coverage`, ["startSample", "endSampleExclusive", "expectedSamples", "continuous"])) {
    if (decoded.coverage.startSample !== 0) fail(`${path}.coverage.startSample`, "must equal 0.");
    if (decoded.coverage.endSampleExclusive !== decoded.sampleCount) fail(`${path}.coverage.endSampleExclusive`, "must equal sampleCount.");
    if (decoded.coverage.expectedSamples !== decoded.sampleCount) fail(`${path}.coverage.expectedSamples`, "must equal sampleCount.");
    if (decoded.coverage.continuous !== true) fail(`${path}.coverage.continuous`, "must be true.");
  }
  if (!object(decoded.sourceAudioStream) || decoded.sourceAudioStream.codec_type !== "audio") {
    fail(`${path}.sourceAudioStream`, "must identify the source audio stream.");
  }
  if (!object(decoded.sourceProbe)) fail(`${path}.sourceProbe`, "must be an object.");
  let ffmpegPath = "ffmpeg";
  if (exactObject(decoded.decoder, `${path}.decoder`, ["ffmpegPath", "ffmpegSha256", "version", "commandSha256"])) {
    nonEmpty(decoded.decoder.ffmpegPath, `${path}.decoder.ffmpegPath`);
    sha(decoded.decoder.ffmpegSha256, `${path}.decoder.ffmpegSha256`);
    nonEmpty(decoded.decoder.version, `${path}.decoder.version`);
    sha(decoded.decoder.commandSha256, `${path}.decoder.commandSha256`);
    const ffmpegArtifact = readArtifact(decoded.decoder.ffmpegPath, decoded.decoder.ffmpegSha256, `${path}.decoder`);
    if (ffmpegArtifact) ffmpegPath = ffmpegArtifact.absolutePath;
  }

  const rawBytes = Number.isInteger(decoded.sampleCount) ? decoded.sampleCount * 2 : 0;
  if (!Number.isSafeInteger(rawBytes) || rawBytes < 1 || rawBytes > 512 * 1024 * 1024) {
    fail(`${path}.sampleCount`, "decoded PCM must be non-empty and no larger than 512 MiB.");
    return;
  }
  const decode = (input) => spawnSync(ffmpegPath, [
    "-v", "error", "-i", input, "-map", "0:a:0", "-vn", "-sn", "-dn",
    "-ac", "1", "-ar", "16000", "-acodec", "pcm_s16le", "-f", "s16le", "-",
  ], { encoding: null, maxBuffer: Math.max(16 * 1024 * 1024, rawBytes + 64 * 1024) });
  if (candidate && decodedArtifact) {
    const candidateDecode = decode(candidate.absolutePath);
    const artifactDecode = decode(decodedArtifact.absolutePath);
    for (const [label, result] of [["candidate", candidateDecode], ["decoded artifact", artifactDecode]]) {
      if (result.status !== 0 || !Buffer.isBuffer(result.stdout)) {
        const detail = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8") : String(result.stderr ?? "");
        fail(path, `could not decode ${label}: ${detail.trim() || `ffmpeg exited ${result.status}`}`);
      }
    }
    if (Buffer.isBuffer(candidateDecode.stdout) && Buffer.isBuffer(artifactDecode.stdout)) {
      if (candidateDecode.stdout.length !== rawBytes) fail(`${path}.sampleCount`, `does not match deterministic candidate decode (${candidateDecode.stdout.length / 2} samples).`);
      if (!candidateDecode.stdout.equals(artifactDecode.stdout)) fail(path, "decoded artifact PCM does not match the exact candidate decode.");
    }
  }
}

function validateCalibrationCase(value, path, expectedStatus, {
  releaseCandidate,
  candidateNativeReport,
  candidateNativeArtifact,
  listenerModelReceipt,
  expectedModel,
  expectedPromptVersion,
  expectedPromptSha256,
} = {}) {
  if (!exactObject(value, path, ["caseId", "audio", "nativeReport", "rawResponse", "expectedStatus", "observedStatus"])) return undefined;
  matches(value.caseId, SAFE_ID, `${path}.caseId`, "a safe calibration case identifier");
  const audioArtifact = validateBoundArtifactReference(value.audio, `${path}.audio`);
  if (audioArtifact) {
    const probe = spawnSync("ffprobe", [
      "-v", "error", "-select_streams", "a:0",
      "-show_entries", "stream=codec_type", "-of", "json", audioArtifact.absolutePath,
    ], { encoding: "utf8" });
    if (probe.status !== 0) {
      fail(`${path}.audio`, `must be decodable audio evidence: ${(probe.stderr || probe.stdout).trim()}`);
    } else {
      try {
        const metadata = JSON.parse(probe.stdout);
        if (!metadata.streams?.some((stream) => stream.codec_type === "audio")) {
          fail(`${path}.audio`, "must contain an audio stream.");
        }
      } catch (error) {
        fail(`${path}.audio`, `ffprobe returned invalid JSON: ${error.message}`);
      }
    }
  }
  const nativeArtifact = validateBoundArtifactReference(value.nativeReport, `${path}.nativeReport`);
  const rawResponseArtifact = validateBoundArtifactReference(value.rawResponse, `${path}.rawResponse`);
  if (value.expectedStatus !== expectedStatus) fail(`${path}.expectedStatus`, `must equal ${expectedStatus}.`);
  if (value.observedStatus !== expectedStatus) fail(`${path}.observedStatus`, `must equal ${expectedStatus}.`);

  if (audioArtifact && releaseCandidate?.sha256 === value.audio.sha256) {
    fail(`${path}.audio.sha256`, "must be independent from the release candidate audio.");
  }
  if (nativeArtifact && candidateNativeArtifact) {
    if (nativeArtifact.absolutePath === candidateNativeArtifact.absolutePath || nativeArtifact.actualSha === candidateNativeArtifact.actualSha) {
      fail(`${path}.nativeReport`, "must be a distinct native ai.ps1 listen report, not the candidate report.");
    }
  }

  const nativeReport = parseJsonArtifact(nativeArtifact, `${path}.nativeReport.document`);
  const nativePath = `${path}.nativeReport.document`;
  let nativeCandidate;
  let reportId;
  if (object(nativeReport) && exactObject(nativeReport, nativePath, [
    "schemaVersion", "reportId", "status", "candidate", "decodedAudio", "model", "request",
    "execution", "checks", "findings", "summary", "generatedAt",
  ])) {
    if (nativeReport.schemaVersion !== "1.0.0") fail(`${nativePath}.schemaVersion`, 'must equal "1.0.0".');
    reportId = nativeReport.reportId;
    nativeCandidate = validateCandidate(nativeReport.candidate, `${nativePath}.candidate`, { requireDecodableVideo: false });
    if (nativeCandidate && audioArtifact) {
      const audioPath = resolveDecisionPath(value.audio.artifactPath, `${path}.audio.artifactPath`);
      if (nativeCandidate.absolutePath !== audioPath || nativeCandidate.sha256 !== value.audio.sha256 || nativeReport.candidate.bytes !== value.audio.bytes) {
        fail(`${nativePath}.candidate`, "must bind the exact calibration audio path, hash, and bytes.");
      }
      if (nativeReport.reportId !== `LAPR-${value.audio.sha256.slice(0, 16)}`) {
        fail(`${nativePath}.reportId`, "must be the native ai.ps1 listen id derived from the calibration audio SHA-256.");
      }
    }
    if (releaseCandidate && nativeCandidate) {
      if (nativeCandidate.candidateId === releaseCandidate.candidateId) fail(`${nativePath}.candidate.candidateId`, "must identify an independent calibration input.");
      if (nativeCandidate.sha256 === releaseCandidate.sha256) fail(`${nativePath}.candidate.sha256`, "must differ from the release candidate.");
    }
    if (candidateNativeReport?.reportId && nativeReport.reportId === candidateNativeReport.reportId) {
      fail(`${nativePath}.reportId`, "must differ from the candidate native report id.");
    }
    validateNativeDecodedAudio(nativeReport.decodedAudio, nativeCandidate, `${nativePath}.decodedAudio`);

    let nativeModel;
    if (exactObject(nativeReport.model, `${nativePath}.model`, [
      "id", "revision", "license", "receiptSha256", "torch", "transformers", "device", "peakVramBytes",
    ])) {
      for (const field of ["id", "revision", "license", "torch", "transformers", "device"]) nonEmpty(nativeReport.model[field], `${nativePath}.model.${field}`);
      sha(nativeReport.model.receiptSha256, `${nativePath}.model.receiptSha256`);
      if (!Number.isInteger(nativeReport.model.peakVramBytes) || nativeReport.model.peakVramBytes < 1) {
        fail(`${nativePath}.model.peakVramBytes`, "must be a positive integer.");
      }
      nativeModel = nativeReport.model;
      if (expectedModel) {
        for (const field of ["id", "revision", "receiptSha256"]) {
          if (nativeModel[field] !== expectedModel[field]) fail(`${nativePath}.model.${field}`, "must match the candidate listen report model identity.");
        }
      }
      validateModelReceipt(listenerModelReceipt, nativeModel, `${path}.modelReceipt`);
    }

    if (exactObject(nativeReport.request, `${nativePath}.request`, [
      "promptVersion", "promptSha256", "transcript", "pronunciationManifest", "generation", "modelResponse",
    ])) {
      nonEmpty(nativeReport.request.promptVersion, `${nativePath}.request.promptVersion`);
      sha(nativeReport.request.promptSha256, `${nativePath}.request.promptSha256`);
      if (expectedPromptVersion && nativeReport.request.promptVersion !== expectedPromptVersion) {
        fail(`${nativePath}.request.promptVersion`, "must match the candidate listen report prompt version.");
      }
      if (expectedPromptSha256 && nativeReport.request.promptSha256 !== expectedPromptSha256) {
        fail(`${nativePath}.request.promptSha256`, "must match the candidate listen report prompt hash.");
      }
      for (const field of ["transcript", "pronunciationManifest"]) {
        if (nativeReport.request[field] !== null) validateBoundArtifactReference(nativeReport.request[field], `${nativePath}.request.${field}`);
      }
      if (exactObject(nativeReport.request.generation, `${nativePath}.request.generation`, ["doSample", "seed", "maxNewTokens"])) {
        if (nativeReport.request.generation.doSample !== false) fail(`${nativePath}.request.generation.doSample`, "must be false.");
        if (nativeReport.request.generation.seed !== 0) fail(`${nativePath}.request.generation.seed`, "must equal 0.");
        if (!Number.isInteger(nativeReport.request.generation.maxNewTokens) || nativeReport.request.generation.maxNewTokens < 1) {
          fail(`${nativePath}.request.generation.maxNewTokens`, "must be a positive integer.");
        }
      }
      validateBoundArtifactReference(nativeReport.request.modelResponse, `${nativePath}.request.modelResponse`);
      if (rawResponseArtifact) sameArtifactReference(nativeReport.request.modelResponse, value.rawResponse, `${nativePath}.request.modelResponse`);
    }

    if (exactObject(nativeReport.execution, `${nativePath}.execution`, [
      "startedAt", "completedAt", "durationSeconds", "localFilesOnly", "remoteInputs",
    ])) {
      dateTime(nativeReport.execution.startedAt, `${nativePath}.execution.startedAt`);
      dateTime(nativeReport.execution.completedAt, `${nativePath}.execution.completedAt`);
      if (Date.parse(nativeReport.execution.completedAt) < Date.parse(nativeReport.execution.startedAt)) fail(`${nativePath}.execution`, "completedAt must not precede startedAt.");
      if (typeof nativeReport.execution.durationSeconds !== "number" || nativeReport.execution.durationSeconds < 0) fail(`${nativePath}.execution.durationSeconds`, "must be non-negative.");
      if (nativeReport.execution.localFilesOnly !== true) fail(`${nativePath}.execution.localFilesOnly`, "must be true.");
      if (nativeReport.execution.remoteInputs !== false) fail(`${nativePath}.execution.remoteInputs`, "must be false.");
    }

    const perceptionChecks = new Set([
      "full-program", "pronunciation", "delivery-and-pacing", "artifacts-and-discontinuities",
    ]);
    const allChecksPassed = validatePassFailChecks(nativeReport.checks, `${nativePath}.checks`, perceptionChecks, "audio-perception");
    let findingCount = 0;
    if (!Array.isArray(nativeReport.findings)) {
      fail(`${nativePath}.findings`, "must be an array.");
    } else {
      const findingIds = new Set();
      findingCount = nativeReport.findings.length;
      nativeReport.findings.forEach((finding, index) => {
        const findingPath = `${nativePath}.findings[${index}]`;
        if (!exactObject(finding, findingPath, ["id", "checkId", "severity", "startSeconds", "endSeconds", "description"])) return;
        matches(finding.id, FINDING_ID, `${findingPath}.id`, "a canonical product-video finding identifier");
        if (findingIds.has(finding.id)) fail(`${findingPath}.id`, `duplicates "${finding.id}".`);
        findingIds.add(finding.id);
        if (!perceptionChecks.has(finding.checkId)) fail(`${findingPath}.checkId`, "must name a canonical audio-perception check.");
        if (!["BLOCKER", "WARNING"].includes(finding.severity)) fail(`${findingPath}.severity`, "must be BLOCKER or WARNING.");
        for (const field of ["startSeconds", "endSeconds"]) {
          if (finding[field] !== null && (typeof finding[field] !== "number" || finding[field] < 0)) fail(`${findingPath}.${field}`, "must be null or a non-negative number.");
        }
        nonEmpty(finding.description, `${findingPath}.description`);
      });
    }
    nonEmpty(nativeReport.summary, `${nativePath}.summary`);
    if (nativeReport.status !== expectedStatus) fail(`${nativePath}.status`, `must equal calibration observed status ${expectedStatus}.`);
    if (expectedStatus === "PASS" && (!allChecksPassed || findingCount !== 0)) fail(nativePath, "PASS requires all four audio checks to pass and no findings.");
    if (expectedStatus === "FAIL" && (allChecksPassed || findingCount === 0)) fail(nativePath, "FAIL requires a failed check and finding.");
    dateTime(nativeReport.generatedAt, `${nativePath}.generatedAt`);
    if (nativeReport.generatedAt !== nativeReport.execution?.completedAt) fail(`${nativePath}.generatedAt`, "must equal execution.completedAt.");
  }
  return { caseId: value.caseId, reportId, nativeArtifact, nativeCandidate };
}

function validatePassFailChecks(checks, path, requiredCheckIds, noun) {
  const seen = new Set();
  if (!Array.isArray(checks) || checks.length !== requiredCheckIds.size) {
    fail(path, `must contain exactly ${requiredCheckIds.size} ${noun} checks.`);
  } else {
    checks.forEach((check, index) => {
      const checkPath = `${path}[${index}]`;
      if (!exactObject(check, checkPath, ["id", "passed", "notes"])) return;
      if (!requiredCheckIds.has(check.id)) fail(`${checkPath}.id`, `is not a canonical ${noun} check.`);
      if (seen.has(check.id)) fail(`${checkPath}.id`, `duplicates "${check.id}".`);
      seen.add(check.id);
      if (typeof check.passed !== "boolean") fail(`${checkPath}.passed`, "must be boolean.");
      nonEmpty(check.notes, `${checkPath}.notes`);
    });
  }
  for (const id of requiredCheckIds) if (!seen.has(id)) fail(path, `missing "${id}".`);
  return Array.isArray(checks) && checks.every((check) => check?.passed === true);
}

function validateCandidateAudioApproval(reference, candidate, path, policy, decisionTimestamp, { requirePass = false } = {}) {
  if (!exactObject(reference, path, ["perceptionReport", "adjudication"])) return undefined;
  const reportArtifact = validateBoundArtifactReference(reference.perceptionReport, `${path}.perceptionReport`);
  const report = parseJsonArtifact(reportArtifact, `${path}.perceptionReport.document`);
  if (!object(report)) return undefined;
  const reportPath = `${path}.perceptionReport.document`;
  if (!exactObject(report, reportPath, [
    "schemaVersion", "reportId", "candidate", "listener", "calibration", "status", "generatedAt",
  ])) return undefined;
  if (report.schemaVersion !== "1.1.0") fail(`${reportPath}.schemaVersion`, 'must equal "1.1.0".');
  matches(report.reportId, AUDIO_REPORT_ID, `${reportPath}.reportId`, "a canonical audio-perception report identifier");
  const reportCandidate = validateCandidate(report.candidate, `${reportPath}.candidate`);
  sameCandidate(reportCandidate, candidate, `${reportPath}.candidate`);

  let nativeReport;
  let nativeReportArtifact;
  let listeningModel;
  let promptVersion;
  let promptSha256;
  let analysisCompletedAt;
  let reportFindings = new Set();
  if (exactObject(report.listener, `${reportPath}.listener`, ["kind", "controlPlane", "command", "localOnly", "report", "modelReceipt"])) {
    if (report.listener.kind !== "local-audio-model") fail(`${reportPath}.listener.kind`, 'must equal "local-audio-model".');
    if (report.listener.controlPlane !== "ai.ps1") fail(`${reportPath}.listener.controlPlane`, 'must equal "ai.ps1".');
    if (report.listener.command !== "listen") fail(`${reportPath}.listener.command`, 'must equal "listen".');
    if (report.listener.localOnly !== true) fail(`${reportPath}.listener.localOnly`, "must be true.");
    nativeReportArtifact = validateBoundArtifactReference(report.listener.report, `${reportPath}.listener.report`);
    nativeReport = parseJsonArtifact(nativeReportArtifact, `${reportPath}.listener.report.document`);
    const nativePath = `${reportPath}.listener.report.document`;
    if (object(nativeReport) && exactObject(nativeReport, nativePath, [
      "schemaVersion", "reportId", "status", "candidate", "decodedAudio", "model", "request",
      "execution", "checks", "findings", "summary", "generatedAt",
    ])) {
      if (nativeReport.schemaVersion !== "1.0.0") fail(`${nativePath}.schemaVersion`, 'must equal "1.0.0".');
      const nativeCandidate = validateCandidate(nativeReport.candidate, `${nativePath}.candidate`);
      sameCandidate(nativeCandidate, candidate, `${nativePath}.candidate`);
      if (candidate?.sha256 && nativeReport.reportId !== `LAPR-${candidate.sha256.slice(0, 16)}`) {
        fail(`${nativePath}.reportId`, "must be the native ai.ps1 listen id derived from the candidate SHA-256.");
      }
      validateNativeDecodedAudio(nativeReport.decodedAudio, nativeCandidate, `${nativePath}.decodedAudio`);
      if (exactObject(nativeReport.model, `${nativePath}.model`, [
        "id", "revision", "license", "receiptSha256", "torch", "transformers", "device", "peakVramBytes",
      ])) {
        nonEmpty(nativeReport.model.id, `${nativePath}.model.id`);
        nonEmpty(nativeReport.model.revision, `${nativePath}.model.revision`);
        nonEmpty(nativeReport.model.license, `${nativePath}.model.license`);
        sha(nativeReport.model.receiptSha256, `${nativePath}.model.receiptSha256`);
        nonEmpty(nativeReport.model.torch, `${nativePath}.model.torch`);
        nonEmpty(nativeReport.model.transformers, `${nativePath}.model.transformers`);
        nonEmpty(nativeReport.model.device, `${nativePath}.model.device`);
        if (!Number.isInteger(nativeReport.model.peakVramBytes) || nativeReport.model.peakVramBytes < 1) {
          fail(`${nativePath}.model.peakVramBytes`, "must be a positive integer.");
        }
        listeningModel = nativeReport.model;
        validateModelReceipt(report.listener.modelReceipt, listeningModel, `${reportPath}.listener.modelReceipt`);
      }
      if (exactObject(nativeReport.request, `${nativePath}.request`, [
        "promptVersion", "promptSha256", "transcript", "pronunciationManifest", "generation", "modelResponse",
      ])) {
        if (nonEmpty(nativeReport.request.promptVersion, `${nativePath}.request.promptVersion`)) promptVersion = nativeReport.request.promptVersion;
        if (sha(nativeReport.request.promptSha256, `${nativePath}.request.promptSha256`)) promptSha256 = nativeReport.request.promptSha256;
        for (const field of ["transcript", "pronunciationManifest"]) {
          if (nativeReport.request[field] !== null) validateBoundArtifactReference(nativeReport.request[field], `${nativePath}.request.${field}`);
        }
        if (exactObject(nativeReport.request.generation, `${nativePath}.request.generation`, ["doSample", "seed", "maxNewTokens"])) {
          if (nativeReport.request.generation.doSample !== false) fail(`${nativePath}.request.generation.doSample`, "must be false.");
          if (nativeReport.request.generation.seed !== 0) fail(`${nativePath}.request.generation.seed`, "must equal 0.");
          if (!Number.isInteger(nativeReport.request.generation.maxNewTokens) || nativeReport.request.generation.maxNewTokens < 1) {
            fail(`${nativePath}.request.generation.maxNewTokens`, "must be a positive integer.");
          }
        }
        validateBoundArtifactReference(nativeReport.request.modelResponse, `${nativePath}.request.modelResponse`);
      }
      if (exactObject(nativeReport.execution, `${nativePath}.execution`, [
        "startedAt", "completedAt", "durationSeconds", "localFilesOnly", "remoteInputs",
      ])) {
        dateTime(nativeReport.execution.startedAt, `${nativePath}.execution.startedAt`);
        dateTime(nativeReport.execution.completedAt, `${nativePath}.execution.completedAt`);
        analysisCompletedAt = Date.parse(nativeReport.execution.completedAt);
        if (analysisCompletedAt < Date.parse(nativeReport.execution.startedAt)) fail(`${nativePath}.execution`, "completedAt must not precede startedAt.");
        if (typeof nativeReport.execution.durationSeconds !== "number" || nativeReport.execution.durationSeconds < 0) fail(`${nativePath}.execution.durationSeconds`, "must be non-negative.");
        if (nativeReport.execution.localFilesOnly !== true) fail(`${nativePath}.execution.localFilesOnly`, "must be true.");
        if (nativeReport.execution.remoteInputs !== false) fail(`${nativePath}.execution.remoteInputs`, "must be false.");
      }
      const perceptionChecks = new Set([
        "full-program", "pronunciation", "delivery-and-pacing", "artifacts-and-discontinuities",
      ]);
      const allPerceptionChecksPassed = validatePassFailChecks(nativeReport.checks, `${nativePath}.checks`, perceptionChecks, "audio-perception");
      if (!Array.isArray(nativeReport.findings)) {
        fail(`${nativePath}.findings`, "must be an array.");
      } else {
        reportFindings = new Set();
        nativeReport.findings.forEach((finding, index) => {
          const findingPath = `${nativePath}.findings[${index}]`;
          if (!exactObject(finding, findingPath, ["id", "checkId", "severity", "startSeconds", "endSeconds", "description"])) return;
          matches(finding.id, FINDING_ID, `${findingPath}.id`, "a canonical product-video finding identifier");
          if (reportFindings.has(finding.id)) fail(`${findingPath}.id`, `duplicates "${finding.id}".`);
          reportFindings.add(finding.id);
          if (!perceptionChecks.has(finding.checkId)) fail(`${findingPath}.checkId`, "must name a canonical audio-perception check.");
          if (!["BLOCKER", "WARNING"].includes(finding.severity)) fail(`${findingPath}.severity`, "must be BLOCKER or WARNING.");
          for (const field of ["startSeconds", "endSeconds"]) {
            if (finding[field] !== null && (typeof finding[field] !== "number" || finding[field] < 0)) fail(`${findingPath}.${field}`, "must be null or a non-negative number.");
          }
          nonEmpty(finding.description, `${findingPath}.description`);
        });
      }
      nonEmpty(nativeReport.summary, `${nativePath}.summary`);
      if (!["PASS", "FAIL"].includes(nativeReport.status)) fail(`${nativePath}.status`, "must be PASS or FAIL.");
      if (nativeReport.status === "PASS" && (!allPerceptionChecksPassed || reportFindings.size !== 0)) fail(nativePath, "PASS requires all four audio checks to pass and no findings.");
      if (nativeReport.status === "FAIL" && (allPerceptionChecksPassed || reportFindings.size === 0)) fail(nativePath, "FAIL requires a failed check and finding.");
      dateTime(nativeReport.generatedAt, `${nativePath}.generatedAt`);
      if (nativeReport.generatedAt !== nativeReport.execution?.completedAt) fail(`${nativePath}.generatedAt`, "must equal execution.completedAt.");
    }
  }

  let calibrationEvaluatedAt;
  let calibrationValidUntil;
  if (exactObject(report.calibration, `${reportPath}.calibration`, [
    "calibrationId", "promptVersion", "promptSha256", "model", "evaluatedAt", "validUntil", "knownGood", "knownBad",
  ])) {
    matches(report.calibration.calibrationId, /^PVAC-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/, `${reportPath}.calibration.calibrationId`, "a canonical audio calibration identifier");
    nonEmpty(report.calibration.promptVersion, `${reportPath}.calibration.promptVersion`);
    if (promptVersion && report.calibration.promptVersion !== promptVersion) {
      fail(`${reportPath}.calibration.promptVersion`, "must match the candidate native report prompt version.");
    }
    sha(report.calibration.promptSha256, `${reportPath}.calibration.promptSha256`);
    if (promptSha256 && report.calibration.promptSha256 !== promptSha256) {
      fail(`${reportPath}.calibration.promptSha256`, "must match the candidate native report prompt hash.");
    }
    let calibrationModel;
    if (exactObject(report.calibration.model, `${reportPath}.calibration.model`, ["id", "revision", "receiptSha256"])) {
      nonEmpty(report.calibration.model.id, `${reportPath}.calibration.model.id`);
      nonEmpty(report.calibration.model.revision, `${reportPath}.calibration.model.revision`);
      sha(report.calibration.model.receiptSha256, `${reportPath}.calibration.model.receiptSha256`);
      calibrationModel = report.calibration.model;
    }
    if (calibrationModel && listeningModel) {
      for (const field of ["id", "revision", "receiptSha256"]) {
        if (calibrationModel[field] !== listeningModel[field]) fail(`${reportPath}.calibration.model.${field}`, "must match the native listen report model identity.");
      }
    }
    dateTime(report.calibration.evaluatedAt, `${reportPath}.calibration.evaluatedAt`);
    dateTime(report.calibration.validUntil, `${reportPath}.calibration.validUntil`);
    calibrationEvaluatedAt = Date.parse(report.calibration.evaluatedAt);
    calibrationValidUntil = Date.parse(report.calibration.validUntil);
    const maximumAgeHours = policy?.maximumCalibrationAgeHours;
    if (!Number.isInteger(maximumAgeHours) || maximumAgeHours < 1) {
      fail(`${path}.policy.maximumCalibrationAgeHours`, "must be a positive integer.");
    } else if (Number.isFinite(calibrationEvaluatedAt) && Number.isFinite(calibrationValidUntil)) {
      const calibrationHours = (calibrationValidUntil - calibrationEvaluatedAt) / 3_600_000;
      if (calibrationHours <= 0 || calibrationHours > maximumAgeHours) {
        fail(`${reportPath}.calibration`, `validUntil must be after evaluatedAt by no more than ${maximumAgeHours} hours.`);
      }
    }
    const calibrationContext = {
      releaseCandidate: candidate,
      candidateNativeReport: nativeReport,
      candidateNativeArtifact: nativeReportArtifact,
      listenerModelReceipt: report.listener?.modelReceipt,
      expectedModel: listeningModel,
      expectedPromptVersion: promptVersion,
      expectedPromptSha256: promptSha256,
    };
    const knownGood = validateCalibrationCase(report.calibration.knownGood, `${reportPath}.calibration.knownGood`, "PASS", calibrationContext);
    const knownBad = validateCalibrationCase(report.calibration.knownBad, `${reportPath}.calibration.knownBad`, "FAIL", calibrationContext);
    if (knownGood?.caseId && knownBad?.caseId && knownGood.caseId === knownBad.caseId) {
      fail(`${reportPath}.calibration`, "known-good and known-bad calibration must use distinct cases.");
    }
    if (knownGood?.reportId && knownBad?.reportId && knownGood.reportId === knownBad.reportId) {
      fail(`${reportPath}.calibration`, "known-good and known-bad calibration must use distinct native report ids.");
    }
    if (knownGood?.nativeArtifact && knownBad?.nativeArtifact &&
        (knownGood.nativeArtifact.absolutePath === knownBad.nativeArtifact.absolutePath ||
         knownGood.nativeArtifact.actualSha === knownBad.nativeArtifact.actualSha)) {
      fail(`${reportPath}.calibration`, "known-good and known-bad calibration must bind distinct native ai.ps1 listen reports.");
    }
    if (knownGood?.nativeCandidate && knownBad?.nativeCandidate && knownGood.nativeCandidate.sha256 === knownBad.nativeCandidate.sha256) {
      fail(`${reportPath}.calibration`, "known-good and known-bad calibration must use distinct audio bytes.");
    }
  }

  const reportGeneratedAt = Date.parse(report.generatedAt);
  dateTime(report.generatedAt, `${reportPath}.generatedAt`);
  if (Number.isFinite(reportGeneratedAt) && Number.isFinite(analysisCompletedAt) && reportGeneratedAt < analysisCompletedAt) {
    fail(`${reportPath}.generatedAt`, "must not precede completed audio perception.");
  }
  if (Number.isFinite(reportGeneratedAt) && Number.isFinite(calibrationEvaluatedAt) && reportGeneratedAt < calibrationEvaluatedAt) {
    fail(`${reportPath}.calibration.evaluatedAt`, "calibration must exist before the perception report is generated.");
  }
  if (Number.isFinite(reportGeneratedAt) && Number.isFinite(calibrationValidUntil) && reportGeneratedAt > calibrationValidUntil) {
    fail(`${reportPath}.calibration.validUntil`, "calibration was stale when the perception report was generated.");
  }
  if (Number.isFinite(decisionTimestamp) && Number.isFinite(calibrationValidUntil) && decisionTimestamp > calibrationValidUntil) {
    fail(`${reportPath}.calibration.validUntil`, "calibration was stale when the release decision was made.");
  }
  if (Number.isFinite(decisionTimestamp) && Number.isFinite(reportGeneratedAt) && decisionTimestamp < reportGeneratedAt) {
    fail(`${reportPath}.generatedAt`, "must not postdate the release decision.");
  }
  if (!["PASS", "FAIL"].includes(report.status)) fail(`${reportPath}.status`, "must be PASS or FAIL.");
  if (nativeReport && report.status !== nativeReport.status) fail(`${reportPath}.status`, "must match the native ai.ps1 listen report.");
  const reportResult = { ...report, findings: [...reportFindings] };

  const adjudicationArtifact = validateBoundArtifactReference(reference.adjudication, `${path}.adjudication`);
  const adjudication = parseJsonArtifact(adjudicationArtifact, `${path}.adjudication.document`);
  if (!object(adjudication)) return { report: reportResult };
  const adjudicationPath = `${path}.adjudication.document`;
  if (!exactObject(adjudication, adjudicationPath, [
    "schemaVersion", "adjudicationId", "candidate", "perceptionReport", "reviewer",
    "checks", "findings", "status", "generatedAt",
  ])) return { report: reportResult };
  if (adjudication.schemaVersion !== "1.0.0") fail(`${adjudicationPath}.schemaVersion`, 'must equal "1.0.0".');
  matches(adjudication.adjudicationId, AUDIO_ADJUDICATION_ID, `${adjudicationPath}.adjudicationId`, "a canonical audio adjudication identifier");
  const adjudicationCandidate = validateCandidate(adjudication.candidate, `${adjudicationPath}.candidate`);
  sameCandidate(adjudicationCandidate, candidate, `${adjudicationPath}.candidate`);
  if (exactObject(adjudication.perceptionReport, `${adjudicationPath}.perceptionReport`, ["artifactPath", "sha256", "bytes"])) {
    sameArtifactReference(adjudication.perceptionReport, reference.perceptionReport, `${adjudicationPath}.perceptionReport`);
  }
  if (exactObject(adjudication.reviewer, `${adjudicationPath}.reviewer`, [
    "role", "contextId", "readOnly", "independent", "executionReceipt",
  ])) {
    if (adjudication.reviewer.role !== "audio-captions-sync-reviewer") {
      fail(`${adjudicationPath}.reviewer.role`, 'must equal "audio-captions-sync-reviewer".');
    }
    nonEmpty(adjudication.reviewer.contextId, `${adjudicationPath}.reviewer.contextId`);
    if (adjudication.reviewer.readOnly !== true) fail(`${adjudicationPath}.reviewer.readOnly`, "must be true.");
    if (adjudication.reviewer.independent !== true) fail(`${adjudicationPath}.reviewer.independent`, "must be true.");
    validateExecutionReceipt(adjudication.reviewer.executionReceipt, `${adjudicationPath}.reviewer.executionReceipt`, {
      role: "reviewer",
      domain: "audio-captions-synchronization",
      contextId: adjudication.reviewer.contextId,
      candidateId: candidate?.candidateId,
    });
  }
  const adjudicationChecks = new Set([
    "candidate-binding", "decoded-sample-coverage", "model-provenance",
    "prompt-and-raw-response", "calibration", "audio-criteria",
  ]);
  const allAdjudicationChecksPassed = validatePassFailChecks(adjudication.checks, `${adjudicationPath}.checks`, adjudicationChecks, "audio-adjudication");
  const adjudicationFindings = uniqueStrings(adjudication.findings, `${adjudicationPath}.findings`, { pattern: FINDING_ID });
  if (!["PASS", "FAIL"].includes(adjudication.status)) fail(`${adjudicationPath}.status`, "must be PASS or FAIL.");
  if (adjudication.status === "PASS" && (!allAdjudicationChecksPassed || adjudicationFindings.size !== 0 || report.status !== "PASS")) {
    fail(adjudicationPath, "PASS requires a passing perception report, all adjudication checks to pass, and no findings.");
  }
  if (adjudication.status === "FAIL" && (allAdjudicationChecksPassed || adjudicationFindings.size === 0)) {
    fail(adjudicationPath, "FAIL requires at least one failed adjudication check and one finding.");
  }
  const adjudicationGeneratedAt = Date.parse(adjudication.generatedAt);
  dateTime(adjudication.generatedAt, `${adjudicationPath}.generatedAt`);
  if (Number.isFinite(adjudicationGeneratedAt) && Number.isFinite(reportGeneratedAt) && adjudicationGeneratedAt < reportGeneratedAt) {
    fail(`${adjudicationPath}.generatedAt`, "must not precede the perception report.");
  }
  if (Number.isFinite(decisionTimestamp) && Number.isFinite(adjudicationGeneratedAt) && adjudicationGeneratedAt > decisionTimestamp) {
    fail(`${adjudicationPath}.generatedAt`, "must not postdate the release decision.");
  }
  if (requirePass && (report.status !== "PASS" || adjudication.status !== "PASS")) {
    fail(path, "release PASS requires both the local audio-perception report and independent adjudication to pass.");
  }
  return { report: reportResult, adjudication };
}

function validateEditorialAudit(reference, candidate, path) {
  if (!exactObject(reference, path, ["artifactPath", "sha256", "bytes"])) return undefined;
  if (!Number.isInteger(reference.bytes) || reference.bytes < 1) fail(`${path}.bytes`, "must be a positive integer.");
  const artifact = readArtifact(reference.artifactPath, reference.sha256, path);
  if (!artifact) return undefined;
  if (artifact.size !== reference.bytes) fail(`${path}.bytes`, `does not match "${artifact.absolutePath}" (actual ${artifact.size}).`);
  const audit = parseJsonArtifact(artifact, `${path}.document`);
  if (!object(audit)) return undefined;
  if (!exactObject(audit, `${path}.document`, [
    "schemaVersion", "auditId", "candidate", "auditor", "fullPlayback",
    "phaseChecks", "findings", "status", "generatedAt",
  ])) return undefined;
  if (audit.schemaVersion !== "1.0.0") fail(`${path}.document.schemaVersion`, 'must equal "1.0.0".');
  matches(audit.auditId, /^PVEA-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/, `${path}.document.auditId`, "a canonical editorial audit identifier");
  const auditCandidate = validateCandidate(audit.candidate, `${path}.document.candidate`);
  sameCandidate(auditCandidate, candidate, `${path}.document.candidate`);
  if (!exactObject(audit.auditor, `${path}.document.auditor`, ["role", "contextId"])) return undefined;
  if (audit.auditor.role !== "orchestrator") fail(`${path}.document.auditor.role`, "must equal orchestrator.");
  nonEmpty(audit.auditor.contextId, `${path}.document.auditor.contextId`);
  if (!exactObject(audit.fullPlayback, `${path}.document.fullPlayback`, [
    "continuous", "mediaDurationSeconds", "startedAt", "completedAt",
  ])) return undefined;
  if (audit.fullPlayback.continuous !== true) fail(`${path}.document.fullPlayback.continuous`, "must be true.");
  if (!Number.isFinite(audit.fullPlayback.mediaDurationSeconds) || audit.fullPlayback.mediaDurationSeconds <= 0) {
    fail(`${path}.document.fullPlayback.mediaDurationSeconds`, "must be positive.");
  }
  dateTime(audit.fullPlayback.startedAt, `${path}.document.fullPlayback.startedAt`);
  dateTime(audit.fullPlayback.completedAt, `${path}.document.fullPlayback.completedAt`);
  const elapsedSeconds = (Date.parse(audit.fullPlayback.completedAt) - Date.parse(audit.fullPlayback.startedAt)) / 1000;
  if (Number.isFinite(elapsedSeconds) && elapsedSeconds + 0.001 < audit.fullPlayback.mediaDurationSeconds) {
    fail(`${path}.document.fullPlayback`, "continuous playback interval is shorter than the candidate duration.");
  }
  const actualDuration = probeCandidateDuration(auditCandidate, `${path}.document.fullPlayback.mediaDurationSeconds`);
  if (Number.isFinite(actualDuration) &&
      Math.abs(actualDuration - audit.fullPlayback.mediaDurationSeconds) > 0.05) {
    fail(`${path}.document.fullPlayback.mediaDurationSeconds`, "does not match the exact candidate media duration.");
  }
  const requiredPhases = new Set([
    "opening-promise", "transitions-and-focus", "hero-before-action-result",
    "screen-cleanliness", "responsive-legibility", "cta-and-impact", "stable-final-hold",
  ]);
  const phases = new Set();
  if (!Array.isArray(audit.phaseChecks) || audit.phaseChecks.length !== requiredPhases.size) {
    fail(`${path}.document.phaseChecks`, `must contain exactly ${requiredPhases.size} phase checks.`);
  } else {
    audit.phaseChecks.forEach((check, index) => {
      const checkPath = `${path}.document.phaseChecks[${index}]`;
      if (!exactObject(check, checkPath, ["phase", "passed", "evidence"])) return;
      if (!requiredPhases.has(check.phase)) fail(`${checkPath}.phase`, "is not a canonical editorial phase.");
      if (phases.has(check.phase)) fail(`${checkPath}.phase`, `duplicates "${check.phase}".`);
      phases.add(check.phase);
      if (check.passed !== true) fail(`${checkPath}.passed`, "must be true for release arbitration.");
      if (!Array.isArray(check.evidence) || check.evidence.length === 0) {
        fail(`${checkPath}.evidence`, "must contain at least one candidate-bound phase evidence record.");
      } else {
        check.evidence.forEach((evidence, evidenceIndex) => {
          const evidencePath = `${checkPath}.evidence[${evidenceIndex}]`;
          if (!object(evidence)) {
            fail(evidencePath, "must be an object.");
            return;
          }
          const artifactEvidence = evidence.kind === "artifact";
          const required = artifactEvidence
            ? ["kind", "artifactPath", "sha256", "bytes", "candidateSha256", "timestampSeconds"]
            : ["kind", "candidateSha256", "timestampSeconds", "frameSha256"];
          if (!exactObject(evidence, evidencePath, required)) return;
          if (!["artifact", "frame-timestamp"].includes(evidence.kind)) {
            fail(`${evidencePath}.kind`, "must be artifact or frame-timestamp.");
          }
          sha(evidence.candidateSha256, `${evidencePath}.candidateSha256`);
          if (candidate && evidence.candidateSha256 !== candidate.sha256) {
            fail(`${evidencePath}.candidateSha256`, "does not match the exact release candidate bytes.");
          }
          if (!Number.isFinite(evidence.timestampSeconds) || evidence.timestampSeconds < 0 ||
              (Number.isFinite(actualDuration) && evidence.timestampSeconds >= actualDuration)) {
            fail(`${evidencePath}.timestampSeconds`, "must identify a decodable timestamp inside the exact candidate duration.");
          }
          if (artifactEvidence) {
            if (!Number.isInteger(evidence.bytes) || evidence.bytes < 1) fail(`${evidencePath}.bytes`, "must be a positive integer.");
            const evidenceArtifact = readArtifact(evidence.artifactPath, evidence.sha256, evidencePath);
            if (evidenceArtifact && evidenceArtifact.size !== evidence.bytes) {
              fail(`${evidencePath}.bytes`, `does not match "${evidenceArtifact.absolutePath}" (actual ${evidenceArtifact.size}).`);
            }
          } else if (evidence.kind === "frame-timestamp") {
            sha(evidence.frameSha256, `${evidencePath}.frameSha256`);
            const decodedSha = decodeCandidateFrameSha(auditCandidate, evidence.timestampSeconds, evidencePath);
            if (decodedSha && decodedSha !== evidence.frameSha256) {
              fail(`${evidencePath}.frameSha256`, "does not match the decoded exact-candidate frame at timestampSeconds.");
            }
          }
        });
      }
    });
  }
  for (const phase of requiredPhases) if (!phases.has(phase)) fail(`${path}.document.phaseChecks`, `missing "${phase}".`);
  if (!Array.isArray(audit.findings) || audit.findings.length !== 0) fail(`${path}.document.findings`, "must be empty for release arbitration.");
  if (audit.status !== "PASS") fail(`${path}.document.status`, "must be PASS for release arbitration.");
  dateTime(audit.generatedAt, `${path}.document.generatedAt`);
  return audit;
}

function validateArtifactReference(value, path) {
  if (!exactObject(value, path, ["artifactPath", "sha256"])) return undefined;
  return readArtifact(value.artifactPath, value.sha256, path);
}

function validateExecutionReceipt(reference, path, expected) {
  if (!exactObject(reference, path, ["receipt"])) return undefined;
  const load = (artifactReference, label) => {
    if (!exactObject(artifactReference, label, ["artifactPath", "sha256", "bytes"])) return undefined;
    if (!Number.isInteger(artifactReference.bytes) || artifactReference.bytes < 1) {
      fail(`${label}.bytes`, "must be a positive integer.");
    }
    const artifact = readArtifact(
      artifactReference.artifactPath,
      artifactReference.sha256,
      label,
    );
    if (!artifact) return undefined;
    if (artifact.size !== artifactReference.bytes) {
      fail(`${label}.bytes`, `does not match "${artifact.absolutePath}" (actual ${artifact.size}).`);
    }
    return artifact;
  };
  const artifact = load(reference.receipt, `${path}.receipt`);
  if (!artifact) return undefined;
  const receipt = parseJsonArtifact(artifact, `${path}.receipt`);
  if (!receipt) return undefined;
  const validation = spawnSync(process.execPath, [
    executionReceiptValidatorPath,
    artifact.absolutePath,
  ], {
    encoding: "utf8",
  });
  if (validation.status !== 0) {
    fail(path, `execution receipt fails canonical validation: ${(validation.stderr || validation.stdout).trim()}`);
    return undefined;
  }
  for (const [field, value] of Object.entries(expected)) {
    if (receipt[field] !== value) {
      fail(`${path}.${field}`, `receipt value ${JSON.stringify(receipt[field])} must equal ${JSON.stringify(value)}.`);
    }
  }
  return receipt;
}

function validatePreflightDocument(report, path, expectedCheckIds, expectedSubsystems, { requirePass = false } = {}) {
  if (!object(report)) {
    fail(path, "must be a JSON object.");
    return undefined;
  }
  const required = [
    "schemaVersion",
    "reportId",
    "candidateId",
    "evidencePackage",
    "policyVersion",
    "startedAt",
    "completedAt",
    "checks",
    "failures",
    "summary",
    "status",
    "readyForIndependentReview",
  ];
  exactObject(report, path, required);
  if (report.schemaVersion !== "1.0.0") fail(`${path}.schemaVersion`, 'must equal "1.0.0".');
  matches(report.reportId, PREFLIGHT_ID, `${path}.reportId`, "a canonical PVP preflight identifier");
  matches(report.candidateId, SAFE_ID, `${path}.candidateId`, "a safe candidate identifier");
  if (!object(report.evidencePackage)) fail(`${path}.evidencePackage`, "must be an artifact reference.");
  else exactObject(report.evidencePackage, `${path}.evidencePackage`, ["artifactPath", "sha256"]);
  nonEmpty(report.policyVersion, `${path}.policyVersion`);
  dateTime(report.startedAt, `${path}.startedAt`);
  dateTime(report.completedAt, `${path}.completedAt`);
  if (Number.isFinite(Date.parse(report.startedAt)) && Number.isFinite(Date.parse(report.completedAt)) &&
      Date.parse(report.completedAt) < Date.parse(report.startedAt)) {
    fail(path, "completedAt must not precede startedAt.");
  }
  const checkIds = new Set();
  let passedChecks = 0;
  const expectedCheckCount = expectedCheckIds.size;
  if (!Array.isArray(report.checks) || report.checks.length !== expectedCheckCount) {
    fail(`${path}.checks`, `must contain exactly ${expectedCheckCount} checks.`);
  }
  else report.checks.forEach((check, index) => {
    const checkPath = `${path}.checks[${index}]`;
    if (!exactObject(check, checkPath, ["id", "subsystem", "passed", "evidenceArtifactIds"]) ||
        !nonEmpty(check.id, `${checkPath}.id`)) return;
    if (checkIds.has(check.id)) fail(`${checkPath}.id`, `duplicates "${check.id}".`);
    checkIds.add(check.id);
    if (!expectedSubsystems.has(check.subsystem)) fail(`${checkPath}.subsystem`, "must be a canonical remediation subsystem.");
    if (typeof check.passed !== "boolean") fail(`${checkPath}.passed`, "must be boolean.");
    if (check.passed === true) passedChecks++;
    uniqueStrings(check.evidenceArtifactIds, `${checkPath}.evidenceArtifactIds`, { minItems: 1, pattern: SAFE_ID });
  });
  for (const checkId of expectedCheckIds) {
    if (!checkIds.has(checkId)) fail(`${path}.checks`, `missing canonical preflight check "${checkId}".`);
  }
  for (const checkId of checkIds) {
    if (!expectedCheckIds.has(checkId)) fail(`${path}.checks`, `contains unknown preflight check "${checkId}".`);
  }
  if (!Array.isArray(report.failures)) fail(`${path}.failures`, "must be an array.");
  else report.failures.forEach((failure, index) => {
    const failurePath = `${path}.failures[${index}]`;
    if (!exactObject(failure, failurePath, [
      "id",
      "checkId",
      "subsystem",
      "severity",
      "expectedBehavior",
      "observedBehavior",
      "evidenceArtifactIds",
      "concreteFix",
      "validationCommand",
    ])) return;
    matches(failure.id, /^PVF-PREFLIGHT-[0-9]{3,}$/, `${failurePath}.id`, "a canonical preflight finding identifier");
    if (!expectedCheckIds.has(failure.checkId)) fail(`${failurePath}.checkId`, "must be a canonical preflight check.");
    if (!expectedSubsystems.has(failure.subsystem)) fail(`${failurePath}.subsystem`, "must be a canonical remediation subsystem.");
    if (!["blocker", "critical", "major"].includes(failure.severity)) {
      fail(`${failurePath}.severity`, "must be blocker, critical, or major.");
    }
    nonEmpty(failure.expectedBehavior, `${failurePath}.expectedBehavior`);
    nonEmpty(failure.observedBehavior, `${failurePath}.observedBehavior`);
    uniqueStrings(failure.evidenceArtifactIds, `${failurePath}.evidenceArtifactIds`, { minItems: 1, pattern: SAFE_ID });
    nonEmpty(failure.concreteFix, `${failurePath}.concreteFix`);
    nonEmpty(failure.validationCommand, `${failurePath}.validationCommand`);
  });
  if (!object(report.summary)) fail(`${path}.summary`, "must be an object.");
  else {
    exactObject(report.summary, `${path}.summary`, ["total", "passed", "failed"]);
    if (report.summary.total !== expectedCheckCount) fail(`${path}.summary.total`, `must equal ${expectedCheckCount}.`);
    if (report.summary.passed !== passedChecks) fail(`${path}.summary.passed`, `must equal derived passed count ${passedChecks}.`);
    const failedChecks = expectedCheckCount - passedChecks;
    if (report.summary.failed !== failedChecks) fail(`${path}.summary.failed`, `must equal derived failed count ${failedChecks}.`);
  }
  if (report.status !== "PASS" && report.status !== "FAIL") fail(`${path}.status`, "must be PASS or FAIL.");
  if (report.status === "PASS") {
    if (passedChecks !== expectedCheckCount || report.failures?.length !== 0 || report.readyForIndependentReview !== true) {
      fail(path, "PASS requires all checks passed, no failures, and readyForIndependentReview=true.");
    }
  } else if (report.readyForIndependentReview !== false) {
    fail(`${path}.readyForIndependentReview`, "must be false for FAIL.");
  }
  if (requirePass && (report.status !== "PASS" || report.readyForIndependentReview !== true)) {
    fail(path, "PASS or REMEDIATE requires a passing preflight ready for independent review.");
  }
  return report;
}

let decision;
try {
  decision = JSON.parse(readFileSync(inputPath, "utf8"));
} catch (error) {
  console.error(`[error] ${inputPath}: ${error.message}`);
  process.exit(1);
}

let canonicalPolicy;
let canonicalPolicyBytes;
let canonicalPreflightSchema;
try {
  canonicalPolicyBytes = readFileSync(canonicalPolicyPath);
  canonicalPolicy = JSON.parse(canonicalPolicyBytes.toString("utf8"));
  canonicalPreflightSchema = JSON.parse(readFileSync(canonicalPreflightSchemaPath, "utf8"));
} catch (error) {
  console.error(`[error] canonical release authority cannot be loaded: ${error.message}`);
  process.exit(1);
}

const canonicalPolicySha = digest(canonicalPolicyBytes);
const canonicalPreflightCheckIds = new Set(canonicalPreflightSchema?.$defs?.checkId?.enum ?? []);
const canonicalPreflightSubsystems = new Set(canonicalPreflightSchema?.$defs?.subsystem?.enum ?? []);
if (canonicalPreflightCheckIds.size !== 20) {
  console.error(`[error] ${canonicalPreflightSchemaPath}: must define exactly 20 unique preflight check IDs.`);
  process.exit(1);
}
if (canonicalPreflightSubsystems.size === 0) {
  console.error(`[error] ${canonicalPreflightSchemaPath}: must define canonical preflight subsystems.`);
  process.exit(1);
}
const commonRequired = ["schemaVersion", "decisionId", "arbiter", "policy", "decision", "rationale", "decidedAt"];
const optional = [
  "candidate",
  "preflight",
  "editorialAudit",
  "candidateAudioApproval",
  "reviewReports",
  "releaseChecks",
  "findingDispositions",
  "evidenceValidation",
  "remediationPlan",
  "blocker",
];

if (exactObject(decision, "$", commonRequired, optional)) {
  if (decision.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
  matches(decision.decisionId, DECISION_ID, "$.decisionId", "a canonical PVD decision identifier");
  if (!DECISIONS.has(decision.decision)) fail("$.decision", "must be PASS, REMEDIATE, PRODUCT_BLOCKED, or PIPELINE_BLOCKED.");
  nonEmpty(decision.rationale, "$.rationale");
  dateTime(decision.decidedAt, "$.decidedAt");
  const fullReleaseDecision = decision.decision === "PASS" || decision.decision === "REMEDIATE";

  if (exactObject(decision.arbiter, "$.arbiter", ["contextId", "readOnly", "executionReceipt"])) {
    nonEmpty(decision.arbiter.contextId, "$.arbiter.contextId");
    if (decision.arbiter.readOnly !== true) fail("$.arbiter.readOnly", "must be true.");
    validateExecutionReceipt(decision.arbiter.executionReceipt, "$.arbiter.executionReceipt", {
      role: "arbiter",
      contextId: decision.arbiter.contextId,
      candidateId: decision.candidate?.candidateId ?? "NO-CANDIDATE",
    });
  }

  let releasePolicy;
  if (exactObject(decision.policy, "$.policy", ["artifactPath", "sha256", "policyVersion"])) {
    const policyArtifact = readArtifact(decision.policy.artifactPath, decision.policy.sha256, "$.policy");
    const referencedPolicy = parseJsonArtifact(policyArtifact, "$.policy");
    if (decision.policy.sha256 !== canonicalPolicySha) fail("$.policy.sha256", "must match the canonical product-video policy digest.");
    if (referencedPolicy && JSON.stringify(referencedPolicy) !== JSON.stringify(canonicalPolicy)) {
      fail("$.policy.artifactPath", "does not contain the canonical product-video policy.");
    }
    if (decision.policy.policyVersion !== canonicalPolicy.schemaVersion) {
      fail("$.policy.policyVersion", `must equal canonical policy schemaVersion "${canonicalPolicy.schemaVersion}".`);
    }
    releasePolicy = canonicalPolicy.releasePolicy;
  }
  if (!object(releasePolicy)) fail("$.policy", "canonical policy is missing releasePolicy.");
  const policyCheckNames = uniqueStrings(releasePolicy?.completePassChecks, "$.policy.completePassChecks", {
    minItems: 1,
    pattern: /^[a-z][A-Za-z0-9]*$/,
  });
  for (const field of [
    "maximumBlockerFindings",
    "maximumCriticalFindings",
    "minimumStoryExperienceScore",
    "minimumAudioCaptionsSynchronizationScore",
  ]) {
    if (!Number.isInteger(releasePolicy?.[field]) || releasePolicy[field] < 0) fail(`$.policy.${field}`, "must be a non-negative integer.");
  }
  if (!Array.isArray(releasePolicy?.decisions) || !releasePolicy.decisions.includes(decision.decision)) {
    fail("$.decision", "is not allowed by the canonical release policy.");
  }

  let candidate;
  if (Object.hasOwn(decision, "candidate")) candidate = validateCandidate(decision.candidate, "$.candidate");
  else if (fullReleaseDecision) fail("$.candidate", `is required for ${decision.decision}.`);

  if (Object.hasOwn(decision, "editorialAudit")) {
    validateEditorialAudit(decision.editorialAudit, candidate, "$.editorialAudit");
  } else if (fullReleaseDecision) {
    fail("$.editorialAudit", `is required for ${decision.decision}.`);
  }

  let candidateAudioApproval;
  if (Object.hasOwn(decision, "candidateAudioApproval")) {
    candidateAudioApproval = validateCandidateAudioApproval(
      decision.candidateAudioApproval,
      candidate,
      "$.candidateAudioApproval",
      canonicalPolicy.candidateAudioPerceptionPolicy,
      Date.parse(decision.decidedAt),
      {
      requirePass: decision.decision === "PASS",
      },
    );
  } else if (fullReleaseDecision) {
    fail("$.candidateAudioApproval", `is required for ${decision.decision}.`);
  }

  let preflight;
  let commonEvidence;
  if (Object.hasOwn(decision, "preflight")) {
    const preflightArtifact = validateArtifactReference(decision.preflight, "$.preflight");
    preflight = validatePreflightDocument(
      parseJsonArtifact(preflightArtifact, "$.preflight"),
      "$.preflight.document",
      canonicalPreflightCheckIds,
      canonicalPreflightSubsystems,
      { requirePass: fullReleaseDecision },
    );
    if (preflight) {
      if (candidate && preflight.candidateId !== candidate.candidateId) fail("$.preflight", "candidateId does not match the release candidate.");
      if (preflight.policyVersion !== canonicalPolicy.schemaVersion) {
        fail("$.preflight.policyVersion", `must equal canonical policy schemaVersion "${canonicalPolicy.schemaVersion}".`);
      }
      commonEvidence = validateArtifactReference(preflight.evidencePackage, "$.preflight.document.evidencePackage");
    }
  } else if (fullReleaseDecision) {
    fail("$.preflight", `is required for ${decision.decision}.`);
  }

  const reportsByDomain = new Map();
  const contextIds = new Set();
  const allFindings = new Map();
  let malformedReviewEncountered = false;
  if (Object.hasOwn(decision, "reviewReports")) {
    if (!Array.isArray(decision.reviewReports) || decision.reviewReports.length !== 4) {
      fail("$.reviewReports", "must contain exactly four review report references.");
    } else {
      decision.reviewReports.forEach((reference, index) => {
        const path = `$.reviewReports[${index}]`;
        if (!object(reference)) {
          fail(path, "must be an object.");
          return;
        }
        const status = reference.status;
        const required = status === "MALFORMED_INPUT"
          ? ["domain", "reportPath", "sha256", "status"]
          : ["domain", "reportPath", "sha256", "status", "score", "passed", "findingCount", "blockerFindings", "criticalFindings"];
        if (!exactObject(reference, path, required)) return;
        if (!DOMAINS.includes(reference.domain)) fail(`${path}.domain`, "must be a canonical review domain.");
        if (reportsByDomain.has(reference.domain)) fail(`${path}.domain`, `duplicates "${reference.domain}".`);
        reportsByDomain.set(reference.domain, reference);
        const reportArtifact = readArtifact(reference.reportPath, reference.sha256, path);
        const report = parseJsonArtifact(reportArtifact, path);
        if (!reportArtifact || !report) return;

        const validation = spawnSync(process.execPath, [reviewValidatorPath, reportArtifact.absolutePath], { encoding: "utf8" });
        if (validation.status !== 0) {
          fail(path, `referenced report fails canonical validation: ${(validation.stderr || validation.stdout).trim()}`);
          return;
        }
        if (report.status !== reference.status) fail(`${path}.status`, `must equal loaded report status "${report.status}".`);
        if (report.reviewer?.domain !== reference.domain) fail(`${path}.domain`, `must equal loaded reviewer domain "${report.reviewer?.domain}".`);
        if (!nonEmpty(report.reviewer?.contextId, `${path}.report.reviewer.contextId`)) return;
        if (contextIds.has(report.reviewer.contextId)) fail(path, `reviewer contextId "${report.reviewer.contextId}" is not isolated.`);
        contextIds.add(report.reviewer.contextId);

        const reportCandidate = validateCandidate(report.candidate, `${path}.report.candidate`, { requireBytes: false });
        if (candidate) sameCandidate(reportCandidate, candidate, `${path}.report.candidate`);
        else if (reportCandidate) {
          if (!candidate) candidate = reportCandidate;
          else sameCandidate(reportCandidate, candidate, `${path}.report.candidate`);
        }
        const reportEvidence = validateArtifactReference(report.evidencePackage, `${path}.report.evidencePackage`);
        if (reportEvidence) {
          if (!commonEvidence) commonEvidence = reportEvidence;
          else if (reportEvidence.absolutePath !== commonEvidence.absolutePath || reportEvidence.actualSha !== commonEvidence.actualSha) {
            fail(`${path}.report.evidencePackage`, "must match the preflight and all other review evidence packages.");
          }
        }

        if (report.status === "MALFORMED_INPUT") {
          malformedReviewEncountered = true;
          if (reference.status !== "MALFORMED_INPUT") fail(`${path}.status`, "must summarize MALFORMED_INPUT.");
          return;
        }
        if (report.status !== "COMPLETE") {
          fail(`${path}.report.status`, "must be COMPLETE or MALFORMED_INPUT.");
          malformedReviewEncountered = true;
          return;
        }
        const findings = Array.isArray(report.findings) ? report.findings : [];
        const blockerCount = findings.filter((finding) => finding.severity === "blocker").length;
        const criticalCount = findings.filter((finding) => finding.severity === "critical").length;
        const derived = {
          score: report.score,
          passed: report.domainPass,
          findingCount: findings.length,
          blockerFindings: blockerCount,
          criticalFindings: criticalCount,
        };
        for (const [field, value] of Object.entries(derived)) {
          if (reference[field] !== value) fail(`${path}.${field}`, `must equal derived report value ${JSON.stringify(value)}.`);
        }
        for (const finding of findings) {
          if (allFindings.has(finding.id)) fail(`${path}.report.findings`, `finding ID "${finding.id}" appears in more than one report.`);
          else allFindings.set(finding.id, finding);
        }
      });
    }
    for (const domain of DOMAINS) if (!reportsByDomain.has(domain)) fail("$.reviewReports", `missing "${domain}" report.`);
  } else if (fullReleaseDecision) {
    fail("$.reviewReports", `is required for ${decision.decision}.`);
  }
  if (contextIds.has(decision.arbiter?.contextId)) {
    fail("$.arbiter.contextId", "must differ from every reviewer contextId.");
  }
  if (candidateAudioApproval) {
    const audioFindingIds = new Set([
      ...(candidateAudioApproval.report?.findings ?? []),
      ...(candidateAudioApproval.adjudication?.findings ?? []),
    ]);
    for (const findingId of audioFindingIds) {
      if (!allFindings.has(findingId)) {
        fail("$.candidateAudioApproval", `audio finding "${findingId}" must also be reported by an independent domain review.`);
      }
    }
  }

  if (malformedReviewEncountered && decision.decision !== "PIPELINE_BLOCKED") {
    fail("$.decision", "a MALFORMED_INPUT review report forces PIPELINE_BLOCKED.");
  }
  if (fullReleaseDecision) {
    for (const reference of reportsByDomain.values()) {
      if (reference.status !== "COMPLETE") fail("$.reviewReports", `${decision.decision} requires four COMPLETE review reports.`);
    }
    if (!commonEvidence) {
      fail("$.preflight.document.evidencePackage", "must bind an existing immutable evidence package.");
    } else {
      validateRecomputedPreflight(
        commonEvidence,
        preflight,
        candidate,
        "$.preflight.document.evidencePackage",
      );
    }
  }

  let allReleaseChecksPass = false;
  if (Object.hasOwn(decision, "releaseChecks")) {
    const requiredChecks = [...policyCheckNames];
    if (exactObject(decision.releaseChecks, "$.releaseChecks", requiredChecks)) {
      allReleaseChecksPass = true;
      for (const name of requiredChecks) {
        if (typeof decision.releaseChecks[name] !== "boolean") fail(`$.releaseChecks.${name}`, "must be boolean.");
        if (decision.releaseChecks[name] !== true) allReleaseChecksPass = false;
      }
    }
  } else if (fullReleaseDecision) {
    fail("$.releaseChecks", `is required for ${decision.decision}.`);
  }

  const dispositions = new Map();
  if (Object.hasOwn(decision, "findingDispositions")) {
    if (!Array.isArray(decision.findingDispositions)) fail("$.findingDispositions", "must be an array.");
    else decision.findingDispositions.forEach((item, index) => {
      const path = `$.findingDispositions[${index}]`;
      if (!exactObject(item, path, ["findingId", "disposition", "rationale", "evidenceArtifactIds"], ["canonicalFindingId"])) return;
      matches(item.findingId, FINDING_ID, `${path}.findingId`, "a canonical PVF finding identifier");
      if (dispositions.has(item.findingId)) fail(`${path}.findingId`, `duplicates "${item.findingId}".`);
      dispositions.set(item.findingId, item);
      if (!DISPOSITIONS.has(item.disposition)) fail(`${path}.disposition`, "must be accepted, rejected-unsupported, or duplicate.");
      nonEmpty(item.rationale, `${path}.rationale`);
      const dispositionEvidence = uniqueStrings(item.evidenceArtifactIds, `${path}.evidenceArtifactIds`, { minItems: 1, pattern: SAFE_ID });
      const actualFinding = allFindings.get(item.findingId);
      if (!actualFinding) fail(`${path}.findingId`, "does not exist in any referenced review report.");
      else {
        const actualEvidence = new Set((actualFinding.evidence ?? []).map((evidence) => evidence.artifactId));
        for (const artifactId of dispositionEvidence) {
          if (!actualEvidence.has(artifactId)) fail(`${path}.evidenceArtifactIds`, `"${artifactId}" is not evidence on finding "${item.findingId}".`);
        }
      }
      if (item.disposition === "duplicate") {
        matches(item.canonicalFindingId, FINDING_ID, `${path}.canonicalFindingId`, "a canonical PVF finding identifier");
        if (item.canonicalFindingId === item.findingId) fail(`${path}.canonicalFindingId`, "must differ from findingId.");
      } else if (Object.hasOwn(item, "canonicalFindingId")) {
        fail(`${path}.canonicalFindingId`, "is allowed only for duplicate findings.");
      }
    });
  } else if (fullReleaseDecision || allFindings.size > 0) {
    fail("$.findingDispositions", "is required when review reports are arbitrated.");
  }
  for (const findingId of allFindings.keys()) {
    if (!dispositions.has(findingId)) fail("$.findingDispositions", `missing exactly one disposition for finding "${findingId}".`);
  }
  for (const [findingId, item] of dispositions) {
    if (item.disposition === "duplicate") {
      const canonical = dispositions.get(item.canonicalFindingId);
      if (!allFindings.has(item.canonicalFindingId) || !canonical || canonical.disposition !== "accepted") {
        fail(`$.findingDispositions.${findingId}`, "must reference an actual accepted canonical finding.");
      }
    }
  }

  let evidenceComplete = false;
  const evidenceFields = ["allReportsValidated", "unsupportedFindingsRejected", "overlapsDeduplicated", "contradictionsResolved"];
  if (Object.hasOwn(decision, "evidenceValidation")) {
    if (exactObject(decision.evidenceValidation, "$.evidenceValidation", evidenceFields)) {
      evidenceComplete = true;
      for (const field of evidenceFields) {
        if (typeof decision.evidenceValidation[field] !== "boolean") fail(`$.evidenceValidation.${field}`, "must be boolean.");
        if (decision.evidenceValidation[field] !== true) evidenceComplete = false;
      }
    }
  } else if (fullReleaseDecision) {
    fail("$.evidenceValidation", `is required for ${decision.decision}.`);
  }

  const acceptedFindingIds = new Set(
    [...dispositions].filter(([, item]) => item.disposition === "accepted").map(([id]) => id),
  );
  if (decision.decision === "REMEDIATE") {
    if (!exactObject(decision.remediationPlan, "$.remediationPlan", [
      "attempt", "findingFamilyFingerprint", "priorDecisions", "findingIds", "assignmentPaths",
    ])) {
      // exactObject records the missing or malformed plan.
    } else {
      if (!Number.isInteger(decision.remediationPlan.attempt) || decision.remediationPlan.attempt < 1) {
        fail("$.remediationPlan.attempt", "must be a positive sequential automated remediation attempt.");
      }
      sha(decision.remediationPlan.findingFamilyFingerprint, "$.remediationPlan.findingFamilyFingerprint");
      const expectedHistoryLength = Number.isInteger(decision.remediationPlan.attempt)
        ? decision.remediationPlan.attempt - 1
        : 0;
      if (!Array.isArray(decision.remediationPlan.priorDecisions) ||
          decision.remediationPlan.priorDecisions.length !== expectedHistoryLength) {
        fail("$.remediationPlan.priorDecisions", `must contain exactly ${expectedHistoryLength} immutable prior decision(s) for attempt ${decision.remediationPlan.attempt}.`);
      } else {
        for (const [index, reference] of decision.remediationPlan.priorDecisions.entries()) {
          const artifact = validateArtifactReference(reference, `$.remediationPlan.priorDecisions[${index}]`);
          const prior = parseJsonArtifact(artifact, `$.remediationPlan.priorDecisions[${index}].document`);
          if (!prior) continue;
          const validation = spawnSync(process.execPath, [fileURLToPath(import.meta.url), artifact.absolutePath], { encoding: "utf8" });
          if (validation.status !== 0) {
            fail(`$.remediationPlan.priorDecisions[${index}]`, `prior decision fails canonical validation: ${(validation.stderr || validation.stdout).trim()}`);
            continue;
          }
          if (prior.decision !== "REMEDIATE" || prior.remediationPlan?.attempt !== index + 1 ||
              prior.remediationPlan?.findingFamilyFingerprint !== decision.remediationPlan.findingFamilyFingerprint) {
            fail(`$.remediationPlan.priorDecisions[${index}]`, "must be the preceding REMEDIATE decision for the same finding family and sequential attempt.");
          }
          if (prior.candidate?.candidateId === decision.candidate?.candidateId) {
            fail(`$.remediationPlan.priorDecisions[${index}]`, "must reference a prior immutable candidate, not the current candidate.");
          }
          if (Number.isFinite(Date.parse(prior.decidedAt)) && Number.isFinite(Date.parse(decision.decidedAt)) &&
              Date.parse(prior.decidedAt) >= Date.parse(decision.decidedAt)) {
            fail(`$.remediationPlan.priorDecisions[${index}]`, "must precede the current decision time.");
          }
        }
      }
      const planIds = uniqueStrings(decision.remediationPlan.findingIds, "$.remediationPlan.findingIds", {
        minItems: 1,
        pattern: FINDING_ID,
      });
      const assignmentPaths = uniqueStrings(decision.remediationPlan.assignmentPaths, "$.remediationPlan.assignmentPaths", {
        minItems: 1,
      });
      for (const id of planIds) if (!acceptedFindingIds.has(id)) fail("$.remediationPlan.findingIds", `"${id}" is not an accepted finding.`);
      for (const id of acceptedFindingIds) if (!planIds.has(id)) fail("$.remediationPlan.findingIds", `missing accepted finding "${id}".`);
      const familyBasis = [...new Map([...planIds].sort().map((id) => {
        const finding = allFindings.get(id);
        const routing = finding ? {
          category: finding.category,
          fixClassification: finding.fixClassification,
        } : { category: "unknown", fixClassification: "unknown" };
        return [`${routing.category}\u0000${routing.fixClassification}`, routing];
      })).values()].sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
      const derivedFamilyFingerprint = digest(Buffer.from(JSON.stringify(familyBasis)));
      if (decision.remediationPlan.findingFamilyFingerprint !== derivedFamilyFingerprint) {
        fail(
          "$.remediationPlan.findingFamilyFingerprint",
          `must be derived from stable accepted-finding category/routing lineage (${derivedFamilyFingerprint}), not IDs or mutable review wording.`,
        );
      }
      for (const assignmentPath of assignmentPaths) {
        const absolutePath = resolveDecisionPath(assignmentPath, "$.remediationPlan.assignmentPaths");
        if (absolutePath && (!existsSync(absolutePath) || !statSync(absolutePath).isFile())) {
          fail("$.remediationPlan.assignmentPaths", `"${assignmentPath}" does not reference an existing file.`);
        }
      }
    }
  } else if (Object.hasOwn(decision, "remediationPlan")) {
    fail("$.remediationPlan", `is not allowed for ${decision.decision}.`);
  }

  if (decision.decision === "PRODUCT_BLOCKED" || decision.decision === "PIPELINE_BLOCKED") {
    if (exactObject(decision.blocker, "$.blocker", ["classification", "summary", "evidence"])) {
      const expected = decision.decision === "PRODUCT_BLOCKED" ? "product" : "pipeline";
      const requiredEvidenceType = decision.decision === "PRODUCT_BLOCKED" ? "readiness" : "preflight";
      if (decision.blocker.classification !== expected) fail("$.blocker.classification", `must equal "${expected}".`);
      nonEmpty(decision.blocker.summary, "$.blocker.summary");
      if (!Array.isArray(decision.blocker.evidence) || decision.blocker.evidence.length === 0) {
        fail("$.blocker.evidence", "must contain immutable readiness or preflight evidence.");
      } else {
        const evidencePaths = new Set();
        decision.blocker.evidence.forEach((reference, index) => {
          const path = `$.blocker.evidence[${index}]`;
          if (!exactObject(reference, path, ["evidenceType", "artifactPath", "sha256", "immutable"])) return;
          if (reference.evidenceType !== "readiness" && reference.evidenceType !== "preflight") {
            fail(`${path}.evidenceType`, "must be readiness or preflight.");
          }
          if (reference.evidenceType !== requiredEvidenceType) {
            fail(
              `${path}.evidenceType`,
              `${decision.decision} requires "${requiredEvidenceType}" blocker evidence.`,
            );
          }
          if (reference.immutable !== true) fail(`${path}.immutable`, "must be true.");
          const artifact = readArtifact(reference.artifactPath, reference.sha256, path);
          if (artifact) {
            if (evidencePaths.has(artifact.absolutePath)) fail(`${path}.artifactPath`, "duplicates blocker evidence.");
            evidencePaths.add(artifact.absolutePath);
            const document = parseJsonArtifact(artifact, path);
            if (reference.evidenceType === "preflight") {
              const blockerPreflight = validatePreflightDocument(
                document,
                `${path}.document`,
                canonicalPreflightCheckIds,
                canonicalPreflightSubsystems,
              );
              if (blockerPreflight?.evidencePackage) {
                validateArtifactReference(blockerPreflight.evidencePackage, `${path}.document.evidencePackage`);
              }
            }
            else {
              const validation = spawnSync(
                process.execPath,
                [readinessValidatorPath, artifact.absolutePath],
                { encoding: "utf8" },
              );
              if (validation.status !== 0) {
                fail(
                  `${path}.document`,
                  `does not pass the canonical demo-readiness validator: ${(validation.stderr || validation.stdout).trim()}`,
                );
              }
              const episodes = Array.isArray(document) ? document : (document?.episodes ?? [document]);
              if (episodes.length === 0 || episodes.some((episode) => episode?.verdict !== "FAIL")) {
                fail(`${path}.document`, "PRODUCT_BLOCKED readiness evidence must contain only FAIL verdicts.");
              }
            }
          }
        });
      }
    }
  } else if (Object.hasOwn(decision, "blocker")) {
    fail("$.blocker", `is not allowed for ${decision.decision}.`);
  }

  if (decision.decision === "PASS") {
    const story = reportsByDomain.get("story-experience");
    const audio = reportsByDomain.get("audio-captions-synchronization");
    if (story?.score < releasePolicy?.minimumStoryExperienceScore) {
      fail("$.reviewReports", `PASS requires story-experience score at least ${releasePolicy?.minimumStoryExperienceScore}.`);
    }
    if (audio?.score < releasePolicy?.minimumAudioCaptionsSynchronizationScore) {
      fail("$.reviewReports", `PASS requires audio-captions-synchronization score at least ${releasePolicy?.minimumAudioCaptionsSynchronizationScore}.`);
    }
    let blockers = 0;
    let criticals = 0;
    for (const report of reportsByDomain.values()) {
      if (report.status !== "COMPLETE" || report.passed !== true) fail("$.reviewReports", `PASS requires ${report.domain} COMPLETE and passed=true.`);
      blockers += report.blockerFindings ?? 0;
      criticals += report.criticalFindings ?? 0;
    }
    if (blockers > releasePolicy?.maximumBlockerFindings) {
      fail("$.reviewReports", `PASS permits at most ${releasePolicy?.maximumBlockerFindings} blocker findings.`);
    }
    if (criticals > releasePolicy?.maximumCriticalFindings) {
      fail("$.reviewReports", `PASS permits at most ${releasePolicy?.maximumCriticalFindings} critical findings.`);
    }
    if (!allReleaseChecksPass) fail("$.releaseChecks", "every canonical complete-pass check must pass for PASS.");
    if (!evidenceComplete) fail("$.evidenceValidation", "all evidence-validation gates must pass for PASS.");
  }
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`\nRelease decision checked: ${errors.length} error(s).`);
process.exit(errors.length > 0 ? 1 : 0);
