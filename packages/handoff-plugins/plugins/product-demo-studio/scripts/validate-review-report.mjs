#!/usr/bin/env node
// Validate one independent product-video review report and its canonical findings.
// Usage: node validate-review-report.mjs <path-to-review-report.json>
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const inputArg = process.argv[2];
if (!inputArg || process.argv.length !== 3) {
  console.error("Usage: node validate-review-report.mjs <path-to-review-report.json>");
  process.exit(1);
}
const inputPath = resolve(inputArg);
const scriptDir = dirname(fileURLToPath(import.meta.url));
const executionReceiptValidatorPath = resolve(scriptDir, "validate-execution-receipt.mjs");
const reviewerCalibrationValidatorPath = resolve(scriptDir, "validate-reviewer-calibration.mjs");
const productPolicy = JSON.parse(readFileSync(resolve(scriptDir, "..", "policy", "product-video-policy.json"), "utf8"));

const DOMAINS = new Set([
  "story-experience",
  "screen-accuracy-compliance",
  "audio-captions-synchronization",
  "technical-frame-integrity",
]);
const SEVERITIES = new Set(["blocker", "critical", "major", "minor", "info"]);
const FIX_CLASSIFICATIONS = new Set([
  "story-script",
  "product-seed-data",
  "capture-playwright",
  "remotion-composition",
  "narration-audio",
  "captions",
  "export-pipeline",
  "infrastructure-assets",
]);
const REQUIRED_CHECKS = {
  "story-experience": [
    "hook",
    "before-state",
    "outcome",
    "hero-moment",
    "wiifm",
    "emotional-payoff",
    "pacing",
    "visual-direction",
    "result-holds",
    "ending",
    "story-product-alignment",
  ],
  "screen-accuracy-compliance": [
    "visible-values",
    "product-behavior",
    "permissions",
    "claims",
    "state-freshness",
    "layouts",
    "annotations",
    "branding",
    "privacy",
    "disclosures",
    "content-freshness",
  ],
  "audio-captions-synchronization": [
    "narration-accuracy",
    "pronunciation",
    "pacing",
    "loudness",
    "clipping",
    "music-balance",
    "action-synchronization",
    "pauses",
    "result-holds",
    "caption-accuracy",
    "caption-timing",
    "reading-speed",
    "caption-layout",
    "accessibility",
  ],
  "technical-frame-integrity": [
    "codecs",
    "resolution",
    "aspect-ratio",
    "frame-rate",
    "color",
    "audio-streams",
    "fast-start",
    "checksums",
    "frame-integrity",
    "browser-playback",
    "assets",
    "deterministic-rendering",
    "naming",
    "platform-compatibility",
    "provenance",
  ],
};
const SHA256 = /^[a-f0-9]{64}$/;
const FINDING_ID = /^PVF-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const REPORT_ID = /^PVR-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const CHECK_ID = /^[a-z][a-z0-9-]*$/;
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
  if (typeof value !== "string" || value.trim().length === 0) fail(path, "must be a non-empty string.");
}

function matches(value, pattern, path, description) {
  if (typeof value !== "string" || !pattern.test(value)) fail(path, `must be ${description}.`);
}

function uniqueStrings(values, path, { minItems = 0, pattern } = {}) {
  if (!Array.isArray(values)) {
    fail(path, "must be an array.");
    return;
  }
  if (values.length < minItems) fail(path, `must contain at least ${minItems} item(s).`);
  const seen = new Set();
  values.forEach((value, index) => {
    if (typeof value !== "string" || value.trim().length === 0) fail(`${path}[${index}]`, "must be a non-empty string.");
    else if (pattern && !pattern.test(value)) fail(`${path}[${index}]`, "has an invalid format.");
    if (seen.has(value)) fail(`${path}[${index}]`, `duplicates "${value}".`);
    seen.add(value);
  });
}

function sha(value, path) {
  matches(value, SHA256, path, "a lowercase 64-character SHA-256 digest");
}

function dateTime(value, path) {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) fail(path, "must be a valid RFC 3339 date-time.");
}

function validateExecutionReceipt(reference, path, expected) {
  if (!exactObject(reference, path, ["receipt", "signature"])) return;
  const load = (artifactReference, label, { signature = false } = {}) => {
    if (!exactObject(artifactReference, label, ["artifactPath", "sha256", "bytes"])) return undefined;
    nonEmpty(artifactReference.artifactPath, `${label}.artifactPath`);
    sha(artifactReference.sha256, `${label}.sha256`);
    if (!Number.isInteger(artifactReference.bytes) || artifactReference.bytes < 1) {
      fail(`${label}.bytes`, "must be a positive integer.");
    }
    if (signature && artifactReference.bytes !== 64) {
      fail(`${label}.bytes`, "must equal 64 for a raw Ed25519 signature.");
    }
    if (typeof artifactReference.artifactPath !== "string" ||
        artifactReference.artifactPath.trim().length === 0) return undefined;
    const absolutePath = resolve(dirname(inputPath), artifactReference.artifactPath);
    if (!existsSync(absolutePath)) {
      fail(`${label}.artifactPath`, `does not exist at "${absolutePath}".`);
      return undefined;
    }
    let bytes;
    try {
      if (!statSync(absolutePath).isFile()) {
        fail(`${label}.artifactPath`, "must reference a file.");
        return undefined;
      }
      bytes = readFileSync(absolutePath);
    } catch (error) {
      fail(`${label}.artifactPath`, `cannot be read: ${error.message}`);
      return undefined;
    }
    const actualSha = createHash("sha256").update(bytes).digest("hex");
    if (artifactReference.bytes !== bytes.length) {
      fail(`${label}.bytes`, `does not match the file (actual ${bytes.length}).`);
    }
    if (artifactReference.sha256 !== actualSha) {
      fail(`${label}.sha256`, `does not match the file (actual ${actualSha}).`);
    }
    if (signature && bytes.length !== 64) {
      fail(label, "must contain exactly 64 raw Ed25519 signature bytes.");
    }
    return { absolutePath, bytes };
  };

  const receiptArtifact = load(reference.receipt, `${path}.receipt`);
  const signatureArtifact = load(reference.signature, `${path}.signature`, { signature: true });
  if (!receiptArtifact || !signatureArtifact) return;
  let receipt;
  try {
    receipt = JSON.parse(receiptArtifact.bytes.toString("utf8"));
  } catch (error) {
    fail(`${path}.receipt.artifactPath`, `must contain valid JSON: ${error.message}`);
    return;
  }
  const validation = spawnSync(process.execPath, [
    executionReceiptValidatorPath,
    receiptArtifact.absolutePath,
    signatureArtifact.absolutePath,
  ], {
    encoding: "utf8",
  });
  if (validation.status !== 0) {
    fail(path, `execution receipt fails canonical validation: ${(validation.stderr || validation.stdout).trim()}`);
    return;
  }
  for (const [field, value] of Object.entries(expected)) {
    if (receipt[field] !== value) {
      fail(`${path}.${field}`, `receipt value ${JSON.stringify(receipt[field])} must equal ${JSON.stringify(value)}.`);
    }
  }
}

function artifactReference(value, path, withDescription = false) {
  const required = withDescription
    ? ["artifactId", "artifactPath", "sha256", "description"]
    : ["artifactPath", "sha256"];
  if (!exactObject(value, path, required)) return;
  if (withDescription) {
    matches(value.artifactId, SAFE_ID, `${path}.artifactId`, "a safe artifact identifier");
    nonEmpty(value.description, `${path}.description`);
  }
  nonEmpty(value.artifactPath, `${path}.artifactPath`);
  sha(value.sha256, `${path}.sha256`);
}

function materializedArtifactReference(value, path) {
  if (!exactObject(value, path, ["artifactPath", "sha256"])) return undefined;
  nonEmpty(value.artifactPath, `${path}.artifactPath`);
  sha(value.sha256, `${path}.sha256`);
  if (typeof value.artifactPath !== "string" || value.artifactPath.trim().length === 0) return undefined;
  const absolutePath = resolve(dirname(inputPath), value.artifactPath);
  if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
    fail(`${path}.artifactPath`, `does not reference an existing file (${absolutePath}).`);
    return undefined;
  }
  const bytes = readFileSync(absolutePath);
  const actualSha = createHash("sha256").update(bytes).digest("hex");
  if (value.sha256 !== actualSha) fail(`${path}.sha256`, `does not match the file (actual ${actualSha}).`);
  return { absolutePath, bytes, sha256: actualSha };
}

function validateReviewIntegrity(value, path, reviewer) {
  if (!exactObject(value, path, [
    "canonicalRubric",
    "verticalOverlay",
    "calibrationRecord",
    "modelId",
    "generatorReasoningReceived",
    "priorReviewsReceived",
  ])) return;
  const rubric = materializedArtifactReference(value.canonicalRubric, `${path}.canonicalRubric`);
  const overlay = value.verticalOverlay === null
    ? null
    : materializedArtifactReference(value.verticalOverlay, `${path}.verticalOverlay`);
  const calibrationArtifact = materializedArtifactReference(value.calibrationRecord, `${path}.calibrationRecord`);
  nonEmpty(value.modelId, `${path}.modelId`);
  if (value.generatorReasoningReceived !== false) {
    fail(`${path}.generatorReasoningReceived`, "must be false; generators may not pass reasoning or self-assessment to reviewers.");
  }
  if (value.priorReviewsReceived !== false) {
    fail(`${path}.priorReviewsReceived`, "must be false; isolated reviewers may not receive sibling review reports.");
  }
  if (!calibrationArtifact) return;

  const validation = spawnSync(process.execPath, [reviewerCalibrationValidatorPath, calibrationArtifact.absolutePath], {
    encoding: "utf8",
  });
  if (validation.status !== 0) {
    fail(`${path}.calibrationRecord`, `fails canonical validation: ${(validation.stderr || validation.stdout).trim()}`);
    return;
  }
  let calibration;
  try {
    calibration = JSON.parse(calibrationArtifact.bytes.toString("utf8"));
  } catch (error) {
    fail(`${path}.calibrationRecord.artifactPath`, `must contain valid JSON: ${error.message}`);
    return;
  }
  if (calibration.reviewDomain !== reviewer?.domain) {
    fail(`${path}.calibrationRecord`, `review domain ${JSON.stringify(calibration.reviewDomain)} must equal ${JSON.stringify(reviewer?.domain)}.`);
  }
  if (calibration.modelId !== value.modelId) {
    fail(`${path}.modelId`, `must equal calibrated model ${JSON.stringify(calibration.modelId)}.`);
  }
  if (rubric && calibration.canonicalRubric?.sha256 !== rubric.sha256) {
    fail(`${path}.canonicalRubric.sha256`, "must equal the canonical rubric hash in the calibration record.");
  }
  const calibratedOverlaySha = calibration.verticalOverlay?.sha256 ?? null;
  const reviewOverlaySha = overlay?.sha256 ?? null;
  if (calibratedOverlaySha !== reviewOverlaySha) {
    fail(`${path}.verticalOverlay`, "must match the exact vertical-overlay hash used for calibration.");
  }
  const calibratedAt = Date.parse(calibration.completedAt);
  const reviewStartedAt = Date.parse(reviewer?.startedAt);
  if (Number.isFinite(calibratedAt) && Number.isFinite(reviewStartedAt)) {
    if (calibratedAt > reviewStartedAt) fail(`${path}.calibrationRecord`, "must be completed before review starts.");
    const maximumAgeDays = productPolicy.calibrationPolicy?.maximumAgeDays;
    if (!Number.isInteger(maximumAgeDays) || maximumAgeDays < 1) {
      fail(`${path}.calibrationRecord`, "canonical policy does not define a valid calibration maximum age.");
    } else if (reviewStartedAt - calibratedAt > maximumAgeDays * 24 * 60 * 60 * 1000) {
      fail(`${path}.calibrationRecord`, `is older than the canonical ${maximumAgeDays}-day limit at review start.`);
    }
  }
}

function validateCandidate(value, path) {
  if (!exactObject(value, path, ["candidateId", "artifactPath", "sha256", "sourceRevision", "renderProvenanceId"])) return;
  matches(value.candidateId, SAFE_ID, `${path}.candidateId`, "a safe candidate identifier");
  nonEmpty(value.artifactPath, `${path}.artifactPath`);
  sha(value.sha256, `${path}.sha256`);
  nonEmpty(value.sourceRevision, `${path}.sourceRevision`);
  nonEmpty(value.renderProvenanceId, `${path}.renderProvenanceId`);
}

function validateFinding(value, path, expectedDomain) {
  const required = [
    "schemaVersion",
    "id",
    "category",
    "severity",
    "fixClassification",
    "location",
    "expectedBehavior",
    "observedBehavior",
    "impact",
    "evidence",
    "concreteFix",
    "automatedValidation",
    "confidence",
  ];
  if (!exactObject(value, path, required)) return;
  if (value.schemaVersion !== "1.0.0") fail(`${path}.schemaVersion`, 'must equal "1.0.0".');
  matches(value.id, FINDING_ID, `${path}.id`, "a canonical PVF finding identifier");
  if (!DOMAINS.has(value.category)) fail(`${path}.category`, "must be a canonical review domain.");
  if (expectedDomain && value.category !== expectedDomain) fail(`${path}.category`, `must match reviewer domain "${expectedDomain}".`);
  if (!SEVERITIES.has(value.severity)) fail(`${path}.severity`, "must be blocker, critical, major, minor, or info.");
  if (!FIX_CLASSIFICATIONS.has(value.fixClassification)) fail(`${path}.fixClassification`, "must be a canonical remediation domain.");

  if (exactObject(value.location, `${path}.location`, ["startTimestampMs", "endTimestampMs", "startFrame", "endFrame", "fps"])) {
    for (const field of ["startTimestampMs", "endTimestampMs", "startFrame", "endFrame"]) {
      if (!Number.isInteger(value.location[field]) || value.location[field] < 0) fail(`${path}.location.${field}`, "must be a non-negative integer.");
    }
    if (typeof value.location.fps !== "number" || !Number.isFinite(value.location.fps) || value.location.fps <= 0) {
      fail(`${path}.location.fps`, "must be a finite number greater than zero.");
    }
    if (Number.isInteger(value.location.startTimestampMs) && Number.isInteger(value.location.endTimestampMs) &&
        value.location.endTimestampMs < value.location.startTimestampMs) {
      fail(`${path}.location`, "endTimestampMs must be greater than or equal to startTimestampMs.");
    }
    if (Number.isInteger(value.location.startFrame) && Number.isInteger(value.location.endFrame) &&
        value.location.endFrame < value.location.startFrame) {
      fail(`${path}.location`, "endFrame must be greater than or equal to startFrame.");
    }
    if (value.location.fps > 0) {
      const toleranceMs = Math.ceil(1000 / value.location.fps);
      const startDelta = Math.abs((value.location.startFrame * 1000) / value.location.fps - value.location.startTimestampMs);
      const endDelta = Math.abs((value.location.endFrame * 1000) / value.location.fps - value.location.endTimestampMs);
      if (startDelta > toleranceMs || endDelta > toleranceMs) fail(`${path}.location`, "timestamps and frame ranges must describe the same interval within one frame.");
    }
  }

  for (const field of ["expectedBehavior", "observedBehavior", "impact"]) nonEmpty(value[field], `${path}.${field}`);
  if (!Array.isArray(value.evidence) || value.evidence.length === 0) fail(`${path}.evidence`, "must contain at least one immutable evidence reference.");
  else {
    const artifactIds = new Set();
    value.evidence.forEach((item, index) => {
      artifactReference(item, `${path}.evidence[${index}]`, true);
      if (object(item) && typeof item.artifactId === "string") {
        if (artifactIds.has(item.artifactId)) fail(`${path}.evidence[${index}].artifactId`, "must be unique within the finding.");
        artifactIds.add(item.artifactId);
      }
    });
  }

  if (exactObject(value.concreteFix, `${path}.concreteFix`, ["summary", "steps"])) {
    nonEmpty(value.concreteFix.summary, `${path}.concreteFix.summary`);
    uniqueStrings(value.concreteFix.steps, `${path}.concreteFix.steps`, { minItems: 1 });
  }
  if (exactObject(value.automatedValidation, `${path}.automatedValidation`, ["command", "expectedResult"])) {
    nonEmpty(value.automatedValidation.command, `${path}.automatedValidation.command`);
    nonEmpty(value.automatedValidation.expectedResult, `${path}.automatedValidation.expectedResult`);
  }
  if (typeof value.confidence !== "number" || !Number.isFinite(value.confidence) || value.confidence < 0 || value.confidence > 1) {
    fail(`${path}.confidence`, "must be a finite number from 0 through 1.");
  }
}

let report;
try {
  report = JSON.parse(readFileSync(inputPath, "utf8"));
} catch (error) {
  console.error(`[error] ${inputPath}: ${error.message}`);
  process.exit(1);
}

const rootRequired = [
  "schemaVersion",
  "reportId",
  "status",
  "candidate",
  "reviewer",
  "reviewIntegrity",
  "evidencePackage",
  "summary",
];
const rootOptional = ["score", "checks", "domainPass", "findings", "missingEvidence", "reason"];
if (exactObject(report, "$", rootRequired, rootOptional)) {
  if (report.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
  matches(report.reportId, REPORT_ID, "$.reportId", "a canonical PVR report identifier");
  if (!["COMPLETE", "MALFORMED_INPUT"].includes(report.status)) {
    fail("$.status", 'must be "COMPLETE" or "MALFORMED_INPUT".');
  }
  validateCandidate(report.candidate, "$.candidate");

  let domain;
  if (exactObject(report.reviewer, "$.reviewer", [
    "domain",
    "contextId",
    "readOnly",
    "executionReceipt",
    "startedAt",
    "completedAt",
  ])) {
    domain = report.reviewer.domain;
    if (!DOMAINS.has(domain)) fail("$.reviewer.domain", "must be one of the four canonical review domains.");
    nonEmpty(report.reviewer.contextId, "$.reviewer.contextId");
    if (report.reviewer.readOnly !== true) fail("$.reviewer.readOnly", "must be true.");
    dateTime(report.reviewer.startedAt, "$.reviewer.startedAt");
    dateTime(report.reviewer.completedAt, "$.reviewer.completedAt");
    if (Number.isFinite(Date.parse(report.reviewer.startedAt)) && Number.isFinite(Date.parse(report.reviewer.completedAt)) &&
        Date.parse(report.reviewer.completedAt) < Date.parse(report.reviewer.startedAt)) {
      fail("$.reviewer", "completedAt must not precede startedAt.");
    }
    validateExecutionReceipt(report.reviewer.executionReceipt, "$.reviewer.executionReceipt", {
      role: "reviewer",
      domain,
      contextId: report.reviewer.contextId,
      candidateId: report.candidate?.candidateId,
      startedAt: report.reviewer.startedAt,
      completedAt: report.reviewer.completedAt,
    });
  }
  validateReviewIntegrity(report.reviewIntegrity, "$.reviewIntegrity", report.reviewer);
  artifactReference(report.evidencePackage, "$.evidencePackage");
  nonEmpty(report.summary, "$.summary");

  if (report.status === "MALFORMED_INPUT") {
    for (const field of ["score", "checks", "domainPass", "findings"]) {
      if (Object.hasOwn(report, field)) fail(`$.${field}`, "is forbidden for MALFORMED_INPUT.");
    }
    nonEmpty(report.reason, "$.reason");
    uniqueStrings(report.missingEvidence, "$.missingEvidence", { minItems: 1 });
  } else if (report.status === "COMPLETE") {
    if (Object.hasOwn(report, "missingEvidence")) fail("$.missingEvidence", "is allowed only for MALFORMED_INPUT.");
    if (Object.hasOwn(report, "reason")) fail("$.reason", "is allowed only for MALFORMED_INPUT.");
    if (!Number.isInteger(report.score) || report.score < 0 || report.score > 100) {
      fail("$.score", "must be an integer from 0 through 100.");
    }
    if (typeof report.domainPass !== "boolean") fail("$.domainPass", "must be boolean.");

    const checkIds = new Set();
    let allChecksPassed = true;
    if (!Array.isArray(report.checks) || report.checks.length === 0) fail("$.checks", "must contain review checks.");
    else report.checks.forEach((check, index) => {
      const path = `$.checks[${index}]`;
      if (!exactObject(check, path, ["id", "passed", "evidenceArtifactIds"])) return;
      matches(check.id, CHECK_ID, `${path}.id`, "a lowercase check identifier");
      if (typeof check.passed !== "boolean") fail(`${path}.passed`, "must be boolean.");
      if (check.passed !== true) allChecksPassed = false;
      uniqueStrings(check.evidenceArtifactIds, `${path}.evidenceArtifactIds`, { minItems: 1, pattern: SAFE_ID });
      if (checkIds.has(check.id)) fail(`${path}.id`, `duplicates "${check.id}".`);
      checkIds.add(check.id);
    });
    for (const checkId of REQUIRED_CHECKS[domain] ?? []) {
      if (!checkIds.has(checkId)) fail("$.checks", `missing required ${domain} check "${checkId}".`);
    }

    const findingIds = new Set();
    let highSeverity = false;
    if (!Array.isArray(report.findings)) fail("$.findings", "must be an array.");
    else report.findings.forEach((finding, index) => {
      validateFinding(finding, `$.findings[${index}]`, domain);
      if (object(finding)) {
        if (findingIds.has(finding.id)) fail(`$.findings[${index}].id`, `duplicates "${finding.id}".`);
        findingIds.add(finding.id);
        if (finding.severity === "blocker" || finding.severity === "critical") highSeverity = true;
      }
    });

    const minimumScore = domain === "story-experience" ? 85 : domain === "audio-captions-synchronization" ? 95 : 100;
    if (report.domainPass === true) {
      if (report.score < minimumScore) fail("$.score", `${domain} requires at least ${minimumScore} to pass.`);
      if (!allChecksPassed) fail("$.domainPass", "cannot be true while any check fails.");
      if (highSeverity) fail("$.domainPass", "cannot be true with blocker or critical findings.");
    } else if (Array.isArray(report.findings) && report.findings.length === 0) {
      fail("$.findings", "a failed domain must include at least one concrete finding.");
    }
  }
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`\nReview report checked: ${errors.length} error(s).`);
process.exit(errors.length > 0 ? 1 : 0);
