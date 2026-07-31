#!/usr/bin/env node
// Validate a reviewer calibration record against the installed canonical plugin.
// Usage: node validate-reviewer-calibration.mjs <calibration.json>
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const inputArg = process.argv[2];
if (!inputArg || process.argv.length !== 3) {
  console.error("Usage: node validate-reviewer-calibration.mjs <calibration.json>");
  process.exit(1);
}

const inputPath = resolve(inputArg);
const inputDir = dirname(inputPath);
const scriptDir = dirname(fileURLToPath(import.meta.url));
const pluginDir = resolve(scriptDir, "..");
const executionReceiptValidatorPath = resolve(scriptDir, "validate-execution-receipt.mjs");
const policyPath = resolve(pluginDir, "policy", "product-video-policy.json");
const canonicalRubricPath = resolve(
  pluginDir,
  "skills",
  "product-demo-studio",
  "references",
  "killer-demo-playbook.md",
);
const errors = [];
const FIXTURES = new Map([
  ["buried-hero", "FAIL"],
  ["feature-rung", "FAIL"],
  ["no-hold", "FAIL"],
  ["dead-wait", "FAIL"],
  ["three-heroes", "FAIL"],
  ["clean-pass", "PASS"],
]);
const DOMAINS = new Set([
  "story-experience",
  "screen-accuracy-compliance",
  "audio-captions-synchronization",
  "technical-frame-integrity",
]);
const SHA256 = /^[a-f0-9]{64}$/;

function fail(path, message) {
  errors.push(`${path}: ${message}`);
}

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactObject(value, path, required) {
  if (!object(value)) {
    fail(path, "must be an object.");
    return false;
  }
  const allowed = new Set(required);
  for (const key of required) if (!Object.hasOwn(value, key)) fail(path, `missing required property "${key}".`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(path, `unknown property "${key}".`);
  return true;
}

function nonEmpty(value, path) {
  if (typeof value !== "string" || value.trim().length === 0) fail(path, "must be a non-empty string.");
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function resolveArtifactPath(path, baseDir = inputDir) {
  return isAbsolute(path) ? resolve(path) : resolve(baseDir, path);
}

function artifactReference(value, path, { canonical = false, baseDir = inputDir } = {}) {
  if (!exactObject(value, path, ["artifactPath", "sha256"])) return undefined;
  nonEmpty(value.artifactPath, `${path}.artifactPath`);
  if (typeof value.sha256 !== "string" || !SHA256.test(value.sha256)) {
    fail(`${path}.sha256`, "must be a lowercase 64-character SHA-256 digest.");
  }
  if (typeof value.artifactPath !== "string" || value.artifactPath.trim().length === 0) return undefined;
  const absolutePath = resolveArtifactPath(value.artifactPath, baseDir);
  if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
    fail(`${path}.artifactPath`, `does not reference an existing file (${absolutePath}).`);
    return undefined;
  }
  const actual = sha256(readFileSync(absolutePath));
  if (value.sha256 !== actual) fail(`${path}.sha256`, `does not match the referenced file (actual ${actual}).`);
  if (canonical && absolutePath.toLowerCase() !== canonicalRubricPath.toLowerCase()) {
    fail(`${path}.artifactPath`, `must reference the installed canonical rubric (${canonicalRubricPath}).`);
  }
  return { absolutePath, sha256: actual };
}

function calibrationResultPayload(report) {
  return {
    schemaVersion: report.schemaVersion,
    fixtureId: report.fixtureId,
    candidateId: report.candidateId,
    reviewDomain: report.reviewDomain,
    modelId: report.modelId,
    contextId: report.contextId,
    startedAt: report.startedAt,
    completedAt: report.completedAt,
    checks: report.checks,
    verdict: report.verdict,
  };
}

function validateExecutionReceipt(reference, path, report, reportDir, expectedHashes) {
  if (!exactObject(reference, path, ["receipt", "signature"])) return;
  const load = (value, artifactPath, signature = false) => {
    if (!exactObject(value, artifactPath, ["artifactPath", "sha256", "bytes"])) return undefined;
    const materialized = artifactReference(
      { artifactPath: value.artifactPath, sha256: value.sha256 },
      artifactPath,
      { baseDir: reportDir },
    );
    if (!Number.isInteger(value.bytes) || value.bytes < 1) fail(`${artifactPath}.bytes`, "must be a positive integer.");
    if (materialized && value.bytes !== statSync(materialized.absolutePath).size) {
      fail(`${artifactPath}.bytes`, "does not match the referenced file.");
    }
    if (signature && value.bytes !== 64) fail(`${artifactPath}.bytes`, "must equal 64 for raw Ed25519.");
    return materialized;
  };
  const receipt = load(reference.receipt, `${path}.receipt`);
  const signature = load(reference.signature, `${path}.signature`, true);
  if (!receipt || !signature) return;
  const validation = spawnSync(process.execPath, [
    executionReceiptValidatorPath,
    receipt.absolutePath,
    signature.absolutePath,
  ], { encoding: "utf8" });
  if (validation.status !== 0) {
    fail(path, `fails canonical signature validation: ${(validation.stderr || validation.stdout).trim()}`);
    return;
  }
  try {
    const document = JSON.parse(readFileSync(receipt.absolutePath, "utf8"));
    const expected = {
      role: "reviewer",
      domain: report.reviewDomain,
      contextId: report.contextId,
      candidateId: report.candidateId,
      startedAt: report.startedAt,
      completedAt: report.completedAt,
    };
    for (const [field, value] of Object.entries(expected)) {
      if (document[field] !== value) fail(`${path}.${field}`, `receipt must equal ${JSON.stringify(value)}.`);
    }
    for (const [field, value] of Object.entries(expectedHashes)) {
      if (document[field] !== value) fail(`${path}.${field}`, `signed receipt must bind ${field} to ${value}.`);
    }
  } catch (error) {
    fail(`${path}.receipt`, `contains invalid JSON: ${error.message}`);
  }
}

function validateCalibrationReview(reference, path, fixtureId, expectedVerdict, record) {
  const artifact = artifactReference(reference, path);
  if (!artifact) return;
  let report;
  try {
    report = JSON.parse(readFileSync(artifact.absolutePath, "utf8"));
  } catch (error) {
    fail(path, `must contain valid JSON: ${error.message}`);
    return;
  }
  const reportPath = `${path}.document`;
  if (!exactObject(report, reportPath, [
    "schemaVersion", "fixtureId", "candidateId", "reviewDomain", "modelId", "contextId",
    "startedAt", "completedAt", "executionReceipt", "checks", "verdict",
  ])) return;
  if (report.schemaVersion !== "1.0.0") fail(`${reportPath}.schemaVersion`, 'must equal "1.0.0".');
  if (report.fixtureId !== fixtureId) fail(`${reportPath}.fixtureId`, `must equal ${JSON.stringify(fixtureId)}.`);
  if (report.reviewDomain !== record.reviewDomain) fail(`${reportPath}.reviewDomain`, "must match the calibration domain.");
  if (report.modelId !== record.modelId) fail(`${reportPath}.modelId`, "must match the calibrated model.");
  nonEmpty(report.candidateId, `${reportPath}.candidateId`);
  nonEmpty(report.contextId, `${reportPath}.contextId`);
  if (!Number.isFinite(Date.parse(report.startedAt)) || !Number.isFinite(Date.parse(report.completedAt)) ||
      Date.parse(report.completedAt) < Date.parse(report.startedAt)) {
    fail(reportPath, "must contain an ordered reviewer execution interval.");
  }
  let derivedVerdict = "PASS";
  const evidenceHashes = new Set();
  if (!Array.isArray(report.checks) || report.checks.length === 0) {
    fail(`${reportPath}.checks`, "must contain criterion-level reviewer results.");
    derivedVerdict = "BLOCKED";
  } else {
    const ids = new Set();
    for (const [index, check] of report.checks.entries()) {
      const checkPath = `${reportPath}.checks[${index}]`;
      if (!exactObject(check, checkPath, ["id", "passed", "evidence"])) {
        derivedVerdict = "BLOCKED";
        continue;
      }
      nonEmpty(check.id, `${checkPath}.id`);
      if (ids.has(check.id)) fail(`${checkPath}.id`, "must be unique.");
      ids.add(check.id);
      if (typeof check.passed !== "boolean") fail(`${checkPath}.passed`, "must be boolean.");
      if (check.passed !== true) derivedVerdict = "FAIL";
      if (!Array.isArray(check.evidence) || check.evidence.length === 0) {
        fail(`${checkPath}.evidence`, "must cite at least one immutable evidence artifact.");
        derivedVerdict = "BLOCKED";
      } else {
        check.evidence.forEach((evidence, evidenceIndex) => {
          const materialized = artifactReference(
            evidence,
            `${checkPath}.evidence[${evidenceIndex}]`,
            { baseDir: dirname(artifact.absolutePath) },
          );
          if (materialized) evidenceHashes.add(materialized.sha256);
        });
      }
    }
  }
  if (report.verdict !== derivedVerdict) {
    fail(`${reportPath}.verdict`, `must be derived from criterion results as ${derivedVerdict}.`);
  }
  if (derivedVerdict !== expectedVerdict) {
    fail(reportPath, `derived verdict ${derivedVerdict} must equal canonical expectation ${expectedVerdict}.`);
  }
  if (evidenceHashes.size !== 1) {
    fail(`${reportPath}.checks`, "each calibration fixture must bind exactly one immutable fixture-input artifact.");
  }
  validateExecutionReceipt(
    report.executionReceipt,
    `${reportPath}.executionReceipt`,
    report,
    dirname(artifact.absolutePath),
    {
      inputArtifactSha256: [...evidenceHashes][0],
      resultPayloadSha256: sha256(Buffer.from(JSON.stringify(calibrationResultPayload(report)))),
    },
  );
}

let record;
let policy;
try {
  record = JSON.parse(readFileSync(inputPath, "utf8"));
  policy = JSON.parse(readFileSync(policyPath, "utf8"));
} catch (error) {
  console.error(`[error] ${error.message}`);
  process.exit(1);
}

if (exactObject(record, "$", [
  "schemaVersion",
  "status",
  "pluginVersion",
  "reviewDomain",
  "modelId",
  "canonicalRubric",
  "verticalOverlay",
  "inputContractVersion",
  "completedAt",
  "fixtures",
])) {
  if (record.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
  if (record.status !== "PASS") fail("$.status", 'must equal "PASS"; calibration fails closed.');
  if (record.pluginVersion !== policy.capabilityVersion) {
    fail("$.pluginVersion", `must equal installed capability version ${policy.capabilityVersion}.`);
  }
  if (!DOMAINS.has(record.reviewDomain)) fail("$.reviewDomain", "must be a canonical review domain.");
  nonEmpty(record.modelId, "$.modelId");
  artifactReference(record.canonicalRubric, "$.canonicalRubric", { canonical: true });
  if (record.verticalOverlay !== null) artifactReference(record.verticalOverlay, "$.verticalOverlay");
  if (record.inputContractVersion !== "review-report.schema/1.0.0") {
    fail("$.inputContractVersion", 'must equal "review-report.schema/1.0.0".');
  }
  if (typeof record.completedAt !== "string" || !Number.isFinite(Date.parse(record.completedAt))) {
    fail("$.completedAt", "must be a valid RFC 3339 date-time.");
  }
  if (!Array.isArray(record.fixtures) || record.fixtures.length !== FIXTURES.size) {
    fail("$.fixtures", `must contain exactly ${FIXTURES.size} canonical fixtures.`);
  } else {
    const seen = new Set();
    record.fixtures.forEach((fixture, index) => {
      const path = `$.fixtures[${index}]`;
      if (!exactObject(fixture, path, ["id", "expectedVerdict", "reviewReport"])) return;
      const expected = FIXTURES.get(fixture.id);
      if (!expected) fail(`${path}.id`, "must be a canonical calibration fixture ID.");
      if (seen.has(fixture.id)) fail(`${path}.id`, `duplicates "${fixture.id}".`);
      seen.add(fixture.id);
      if (fixture.expectedVerdict !== expected) fail(`${path}.expectedVerdict`, `must equal ${expected}.`);
      validateCalibrationReview(fixture.reviewReport, `${path}.reviewReport`, fixture.id, expected, record);
    });
    for (const id of FIXTURES.keys()) if (!seen.has(id)) fail("$.fixtures", `missing canonical fixture "${id}".`);
  }
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`\nReviewer calibration checked: ${errors.length} error(s).`);
process.exit(errors.length > 0 ? 1 : 0);
