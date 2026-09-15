#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";

const input = process.argv[2];
const stagingIndex = process.argv.indexOf("--staging-for");
const stagingTarget = stagingIndex === -1 ? undefined : process.argv[stagingIndex + 1];
const errors = [];
const SHA256 = /^[a-f0-9]{64}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

function fail(path, message) {
  errors.push(`${path}: ${message}`);
}

function exactObject(value, path, required) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(path, "must be an object.");
    return false;
  }
  const allowed = new Set(required);
  for (const key of required) if (!Object.hasOwn(value, key)) fail(path, `missing "${key}".`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(path, `unknown "${key}".`);
  return true;
}

function validateFile(reference, path, root) {
  if (!exactObject(reference, path, ["relativePath", "sha256", "bytes"])) return;
  if (typeof reference.relativePath !== "string" ||
      basename(reference.relativePath) !== reference.relativePath) {
    fail(`${path}.relativePath`, "must be one file name without path traversal.");
    return;
  }
  if (typeof reference.sha256 !== "string" || !SHA256.test(reference.sha256)) {
    fail(`${path}.sha256`, "must be a lowercase SHA-256 digest.");
  }
  if (!Number.isInteger(reference.bytes) || reference.bytes < 1) {
    fail(`${path}.bytes`, "must be a positive integer.");
  }
  const file = join(root, reference.relativePath);
  if (!existsSync(file) || !statSync(file).isFile()) {
    fail(`${path}.relativePath`, `file does not exist: ${file}`);
    return;
  }
  const bytes = readFileSync(file);
  if (bytes.length !== reference.bytes) fail(`${path}.bytes`, `expected ${reference.bytes}, got ${bytes.length}.`);
  const digest = createHash("sha256").update(bytes).digest("hex");
  if (digest !== reference.sha256) fail(`${path}.sha256`, `expected ${reference.sha256}, got ${digest}.`);
}

if (!input ||
    (process.argv.length !== 3 &&
      !(process.argv.length === 5 && stagingIndex === 3 && stagingTarget))) {
  console.error(
    "Usage: node validate-review-delivery.mjs <review-package.json> " +
      "[--staging-for <final-package-directory>]",
  );
  process.exit(1);
}

const manifestPath = resolve(input);
let manifest;
try {
  manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
} catch (error) {
  console.error(`Review delivery manifest is unreadable: ${error.message}`);
  process.exit(1);
}

const rootKeys = [
  "schemaVersion", "classification", "candidate", "sourceRepository", "delivery",
  "gates", "files", "createdAt",
];
if (exactObject(manifest, "$", rootKeys)) {
  if (manifest.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
  if (manifest.classification !== "review-only") fail("$.classification", 'must equal "review-only".');
  if (typeof manifest.sourceRepository !== "string" || !manifest.sourceRepository.trim()) {
    fail("$.sourceRepository", "must be non-empty.");
  }
  if (!Number.isFinite(Date.parse(manifest.createdAt))) fail("$.createdAt", "must be a date-time.");

  if (exactObject(manifest.candidate, "$.candidate", ["candidateId", "artifact"])) {
    if (typeof manifest.candidate.candidateId !== "string" || !SAFE_ID.test(manifest.candidate.candidateId)) {
      fail("$.candidate.candidateId", "must be a safe candidate identifier.");
    }
    validateFile(manifest.candidate.artifact, "$.candidate.artifact", dirname(manifestPath));
  }
  if (exactObject(manifest.delivery, "$.delivery", ["productId", "reviewRoot", "packagePath", "immutable"])) {
    if (manifest.delivery.immutable !== true) fail("$.delivery.immutable", "must be true.");
    const expectedPackagePath = stagingTarget ? resolve(stagingTarget) : dirname(manifestPath);
    if (resolve(manifest.delivery.packagePath) !== expectedPackagePath) {
      fail("$.delivery.packagePath", "must resolve to the final package directory.");
    }
  }
  if (exactObject(manifest.gates, "$.gates", ["arbiterDecision", "finalVerification"])) {
    validateFile(manifest.gates.arbiterDecision, "$.gates.arbiterDecision", dirname(manifestPath));
    validateFile(manifest.gates.finalVerification, "$.gates.finalVerification", dirname(manifestPath));
  }
  if (!Array.isArray(manifest.files) || manifest.files.length < 3) {
    fail("$.files", "must contain at least the candidate, arbiter decision, and final verification.");
  } else {
    const names = new Set();
    manifest.files.forEach((file, index) => {
      validateFile(file, `$.files[${index}]`, dirname(manifestPath));
      if (names.has(file?.relativePath)) fail(`$.files[${index}].relativePath`, "duplicates another file.");
      names.add(file?.relativePath);
    });
    if (manifest.candidate?.artifact?.relativePath &&
        !names.has(manifest.candidate.artifact.relativePath)) {
      fail("$.candidate.artifact.relativePath", "must also appear in $.files.");
    }
  }
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`Review delivery checked: ${errors.length} error(s).`);
process.exit(errors.length ? 1 : 0);
