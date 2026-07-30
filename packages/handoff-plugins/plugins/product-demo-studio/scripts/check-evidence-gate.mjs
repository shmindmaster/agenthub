#!/usr/bin/env node
// Fail-closed publication gate. Approval is accepted only from a detached
// Ed25519 signature over an immutable receipt bound to the exact candidate,
// PASS arbiter decision, and PASS mandatory terminal independent final-verification report.
//
// Usage: node check-evidence-gate.mjs --manifest <path> [--text <path>]
import { createHash, createPublicKey, verify as verifySignature } from "node:crypto";
import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
function flag(name) {
  const index = args.indexOf(name);
  return index !== -1 ? args[index + 1] : undefined;
}

const allowedFlags = new Set(["--manifest", "--text"]);
const seenFlags = new Set();
let argumentsValid = true;
for (let index = 0; index < args.length; index += 2) {
  const name = args[index];
  const value = args[index + 1];
  if (!allowedFlags.has(name) || seenFlags.has(name) || value === undefined || value.startsWith("--")) {
    argumentsValid = false;
    break;
  }
  seenFlags.add(name);
}
const manifestArg = flag("--manifest");
if (!argumentsValid || !manifestArg) {
  console.error("Usage: node check-evidence-gate.mjs --manifest <path> [--text <path>]");
  console.error("Approval requires a durable manifest; inline approval flags are not supported.");
  process.exit(1);
}

const manifestPath = resolve(manifestArg);
const manifestDir = dirname(manifestPath);
const scriptDir = dirname(fileURLToPath(import.meta.url));
const SHA256 = /^[a-f0-9]{64}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const RECEIPT_ID = /^PVA-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const PLACEHOLDER_NAMES = new Set(["", "todo", "tbd", "reviewer", "changeme", "xxx", "agent", "ai"]);
const errors = [];

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
  for (const key of required) {
    if (!Object.hasOwn(value, key)) fail(path, `missing required property "${key}".`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(path, `unknown property "${key}".`);
  }
  return true;
}

function nonEmpty(value, path) {
  if (typeof value !== "string" || value.trim().length === 0) {
    fail(path, "must be a non-empty string.");
    return false;
  }
  return true;
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonicalPath(baseDir, artifactPath) {
  const absolute = resolve(baseDir, artifactPath);
  const canonical = existsSync(absolute) ? realpathSync.native(absolute) : absolute;
  return process.platform === "win32" ? canonical.toLowerCase() : canonical;
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(label, `cannot be read as JSON: ${error.message}`);
    return null;
  }
}

function parseJson(bytes, label) {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(label, `cannot be read as JSON: ${error.message}`);
    return null;
  }
}

function validateFile(reference, label, containingPath, parseAsJson = false) {
  if (!exactObject(reference, label, ["artifactPath", "sha256", "bytes"])) return null;
  if (!nonEmpty(reference.artifactPath, `${label}.artifactPath`)) return null;
  if (typeof reference.sha256 !== "string" || !SHA256.test(reference.sha256)) {
    fail(`${label}.sha256`, "must be a lowercase 64-character SHA-256 digest.");
  }
  if (!Number.isInteger(reference.bytes) || reference.bytes < 1) {
    fail(`${label}.bytes`, "must be a positive integer.");
  }

  const absolute = resolve(dirname(containingPath), reference.artifactPath);
  if (!existsSync(absolute)) {
    fail(`${label}.artifactPath`, `does not exist: ${absolute}`);
    return null;
  }
  let stat;
  try {
    stat = statSync(absolute);
  } catch (error) {
    fail(`${label}.artifactPath`, `cannot be inspected: ${error.message}`);
    return null;
  }
  if (!stat.isFile()) {
    fail(`${label}.artifactPath`, "must reference a file.");
    return null;
  }
  let bytes;
  try {
    bytes = readFileSync(absolute);
  } catch (error) {
    fail(`${label}.artifactPath`, `cannot be read: ${error.message}`);
    return null;
  }
  if (bytes.length !== reference.bytes) {
    fail(`${label}.bytes`, `declares ${reference.bytes}, actual file has ${bytes.length}.`);
  }
  const actualSha = digest(bytes);
  if (actualSha !== reference.sha256) {
    fail(`${label}.sha256`, `declares ${reference.sha256}, actual file is ${actualSha}.`);
  }
  return {
    absolute,
    bytes,
    data: parseAsJson ? parseJson(bytes, `${label}.artifactPath`) : null,
  };
}

function loadTrustedPublicationKey() {
  const configuredPath = process.env.AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY;
  if (!configuredPath || configuredPath.trim().length === 0) {
    fail(
      "AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY",
      "must reference the trusted Ed25519 public key PEM used for publication approval.",
    );
    return null;
  }
  const absolute = resolve(configuredPath);
  if (!existsSync(absolute)) {
    fail("AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY", `does not reference a file: ${absolute}`);
    return null;
  }
  try {
    if (!statSync(absolute).isFile()) {
      fail("AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY", `does not reference a file: ${absolute}`);
      return null;
    }
  } catch (error) {
    fail("AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY", `cannot be inspected: ${error.message}`);
    return null;
  }
  let pem;
  try {
    pem = readFileSync(absolute);
  } catch (error) {
    fail("AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY", `cannot be read: ${error.message}`);
    return null;
  }
  const pemText = pem.toString("utf8");
  if (!pemText.includes("-----BEGIN PUBLIC KEY-----") || pemText.includes("PRIVATE KEY")) {
    fail(
      "AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY",
      "must contain a public-key-only PEM; private-key material is forbidden.",
    );
    return null;
  }
  try {
    const key = createPublicKey(pem);
    if (key.asymmetricKeyType !== "ed25519") {
      fail(
        "AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY",
        `must contain an Ed25519 public key, found ${key.asymmetricKeyType ?? "unknown"}.`,
      );
      return null;
    }
    const fingerprint = digest(key.export({ type: "spki", format: "der" }));
    return { absolute, key, fingerprint };
  } catch (error) {
    fail("AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY", `is not a valid public key: ${error.message}`);
    return null;
  }
}

function validateApprovalReceipt(receipt, manifest) {
  const path = "$.approvalReceipt.document";
  const required = [
    "schemaVersion",
    "receiptId",
    "signatureAlgorithm",
    "approverPublicKeySha256",
    "candidateId",
    "candidateSha256",
    "candidateBytes",
    "arbiterDecisionSha256",
    "finalVerificationSha256",
    "reviewerIdentity",
    "reviewedAt",
    "classification",
    "watchThroughStatus",
    "syntheticDataConfirmed",
    "redactionNotes",
  ];
  if (!exactObject(receipt, path, required)) return;
  if (receipt.schemaVersion !== "1.0.0") fail(`${path}.schemaVersion`, 'must equal "1.0.0".');
  if (typeof receipt.receiptId !== "string" || !RECEIPT_ID.test(receipt.receiptId)) {
    fail(`${path}.receiptId`, "must be a canonical PVA approval-receipt identifier.");
  }
  if (receipt.signatureAlgorithm !== "Ed25519") {
    fail(`${path}.signatureAlgorithm`, 'must equal "Ed25519".');
  }
  if (typeof receipt.approverPublicKeySha256 !== "string" ||
      !SHA256.test(receipt.approverPublicKeySha256)) {
    fail(`${path}.approverPublicKeySha256`, "must be a lowercase SHA-256 digest.");
  }
  if (receipt.candidateId !== manifest.candidateId) {
    fail(`${path}.candidateId`, "must match manifest candidateId.");
  }
  if (receipt.candidateSha256 !== manifest.sha256) {
    fail(`${path}.candidateSha256`, "must match the exact publication asset digest.");
  }
  if (receipt.candidateBytes !== manifest.bytes) {
    fail(`${path}.candidateBytes`, "must match the exact publication asset byte count.");
  }
  if (receipt.arbiterDecisionSha256 !== manifest.arbiterDecision?.sha256) {
    fail(`${path}.arbiterDecisionSha256`, "must match the exact PASS arbiter decision digest.");
  }
  if (receipt.finalVerificationSha256 !== manifest.finalVerification?.sha256) {
    fail(`${path}.finalVerificationSha256`, "must match the exact PASS final-verification digest.");
  }
  if (!nonEmpty(receipt.reviewerIdentity, `${path}.reviewerIdentity`) ||
      PLACEHOLDER_NAMES.has(receipt.reviewerIdentity.toLowerCase().trim())) {
    fail(`${path}.reviewerIdentity`, "must identify the human publication approver.");
  }
  if (typeof receipt.reviewedAt !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(receipt.reviewedAt) ||
      !Number.isFinite(Date.parse(receipt.reviewedAt))) {
    fail(`${path}.reviewedAt`, "must be a valid RFC 3339 date-time with timezone.");
  }
  if (receipt.classification !== "approved") {
    fail(`${path}.classification`, 'must equal "approved" for publication.');
  }
  if (receipt.watchThroughStatus !== "completed") {
    fail(`${path}.watchThroughStatus`, "must record the human watch-through as completed.");
  }
  if (receipt.syntheticDataConfirmed !== true) {
    fail(`${path}.syntheticDataConfirmed`, "must be true for publication.");
  }
  if (typeof receipt.redactionNotes !== "string") {
    fail(`${path}.redactionNotes`, "must be a string.");
  }
}

function invokeValidator(scriptName, artifactPath, label) {
  const result = spawnSync(process.execPath, [resolve(scriptDir, scriptName), artifactPath], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    const detail = `${result.stderr ?? ""}\n${result.stdout ?? ""}`.trim().split(/\r?\n/)[0];
    fail(label, `semantic validator rejected the artifact${detail ? `: ${detail}` : "."}`);
    return false;
  }
  return true;
}

if (!existsSync(manifestPath)) {
  console.error(`--manifest path does not exist: ${manifestPath}`);
  process.exit(1);
}

const manifest = readJson(manifestPath, "$");
if (manifest) {
  const required = [
    "schemaVersion",
    "candidateId",
    "assetPath",
    "sha256",
    "bytes",
    "arbiterDecision",
    "finalVerification",
    "approvalReceipt",
    "approvalSignature",
  ];
  if (exactObject(manifest, "$", required)) {
    if (manifest.schemaVersion !== "2.0.0") fail("$.schemaVersion", 'must equal "2.0.0".');
    if (typeof manifest.candidateId !== "string" || !SAFE_ID.test(manifest.candidateId)) {
      fail("$.candidateId", "must be a safe candidate identifier.");
    }

    const asset = validateFile(
      {
        artifactPath: manifest.assetPath,
        sha256: manifest.sha256,
        bytes: manifest.bytes,
      },
      "$.asset",
      manifestPath,
    );

    const arbiter = validateFile(manifest.arbiterDecision, "$.arbiterDecision", manifestPath, true);
    if (arbiter?.data) {
      invokeValidator("validate-release-decision.mjs", arbiter.absolute, "$.arbiterDecision");
      if (arbiter.data.decision !== "PASS") fail("$.arbiterDecision", 'must contain decision "PASS".');
      if (arbiter.data.candidate?.candidateId !== manifest.candidateId) {
        fail("$.arbiterDecision.candidate.candidateId", "must match manifest candidateId.");
      }
      if (arbiter.data.candidate?.sha256 !== manifest.sha256) {
        fail("$.arbiterDecision.candidate.sha256", "must match the exact publication asset digest.");
      }
      if (typeof arbiter.data.candidate?.artifactPath !== "string" ||
          canonicalPath(dirname(arbiter.absolute), arbiter.data.candidate.artifactPath) !==
          canonicalPath(manifestDir, manifest.assetPath)) {
        fail("$.arbiterDecision.candidate.artifactPath", "must resolve to the exact publication asset.");
      }
    }

    const finalVerification = validateFile(
      manifest.finalVerification,
      "$.finalVerification",
      manifestPath,
      true,
    );
    if (finalVerification?.data) {
      invokeValidator("validate-final-verification.mjs", finalVerification.absolute, "$.finalVerification");
      const finalReport = finalVerification.data;
      if (finalReport.status !== "PASS") fail("$.finalVerification", 'must have status "PASS".');
      if (finalReport.candidate?.candidateId !== manifest.candidateId) {
        fail("$.finalVerification.candidate.candidateId", "must match manifest candidateId.");
      }
      if (finalReport.candidate?.sha256 !== manifest.sha256) {
        fail("$.finalVerification.candidate.sha256", "must match the exact publication asset digest.");
      }
      if (finalReport.candidate?.bytes !== manifest.bytes) {
        fail("$.finalVerification.candidate.bytes", "must match the exact publication asset byte count.");
      }
      if (typeof finalReport.candidate?.artifactPath !== "string" ||
          canonicalPath(dirname(finalVerification.absolute), finalReport.candidate.artifactPath) !==
          canonicalPath(manifestDir, manifest.assetPath)) {
        fail("$.finalVerification.candidate.artifactPath", "must resolve to the exact publication asset.");
      }
      if (arbiter && (
        finalReport.arbiterDecision?.sha256 !== manifest.arbiterDecision.sha256 ||
        finalReport.arbiterDecision?.bytes !== manifest.arbiterDecision.bytes ||
        canonicalPath(dirname(finalVerification.absolute), finalReport.arbiterDecision?.artifactPath ?? "") !==
          canonicalPath(manifestDir, manifest.arbiterDecision.artifactPath)
      )) {
        fail("$.finalVerification.arbiterDecision", "must bind the exact arbiter decision in this manifest.");
      }
    }

    const approvalReceipt = validateFile(
      manifest.approvalReceipt,
      "$.approvalReceipt",
      manifestPath,
      true,
    );
    const approvalSignature = validateFile(
      manifest.approvalSignature,
      "$.approvalSignature",
      manifestPath,
    );
    if (approvalReceipt?.data) validateApprovalReceipt(approvalReceipt.data, manifest);

    const trustedKey = loadTrustedPublicationKey();
    if (trustedKey && approvalReceipt?.data) {
      if (approvalReceipt.data.approverPublicKeySha256 !== trustedKey.fingerprint) {
        fail(
          "$.approvalReceipt.document.approverPublicKeySha256",
          `does not match the trusted public key fingerprint ${trustedKey.fingerprint}.`,
        );
      }
    }
    if (approvalSignature?.bytes && approvalSignature.bytes.length !== 64) {
      fail("$.approvalSignature.bytes", "an Ed25519 detached signature must contain exactly 64 raw bytes.");
    }
    if (trustedKey && approvalReceipt?.bytes && approvalSignature?.bytes?.length === 64) {
      let signatureValid = false;
      try {
        signatureValid = verifySignature(
          null,
          approvalReceipt.bytes,
          trustedKey.key,
          approvalSignature.bytes,
        );
      } catch (error) {
        fail("$.approvalSignature", `could not be verified: ${error.message}`);
      }
      if (!signatureValid) {
        fail(
          "$.approvalSignature",
          "is not a valid Ed25519 signature over the exact approval-receipt bytes from the trusted key.",
        );
      }
    }

    if (!asset) fail("$.asset", "must resolve to the exact publication asset.");
  }
}

const textArg = flag("--text");
let textPath;
if (textArg) {
  textPath = resolve(textArg);
  if (!existsSync(textPath) || !statSync(textPath).isFile()) {
    fail("--text", `does not reference a readable file: ${textPath}`);
  }
}

if (errors.length > 0) {
  console.error(`Evidence gate FAILED for ${manifest?.assetPath ?? manifestPath}:`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log(`Evidence gate passed for ${manifest.assetPath} (candidate: ${manifest.candidateId}).`);

if (textPath) {
  const text = readFileSync(textPath, "utf8");
  const heuristics = [
    { name: "email address", pattern: /[\w.+-]+@[\w-]+\.[\w.-]+/g },
    { name: "SSN-like pattern", pattern: /\b\d{3}-\d{2}-\d{4}\b/g },
    { name: "phone-like pattern", pattern: /\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b/g },
    { name: "dollar figure", pattern: /\$\s?\d[\d,]*(\.\d+)?/g },
    {
      name: "common secret/token shape",
      pattern: /\b(sk|pk|ghp|gho|xox[baprs]|AIza|AKIA)[A-Za-z0-9_-]{10,}\b/g,
    },
  ];

  let warned = false;
  for (const { name, pattern } of heuristics) {
    const matches = text.match(pattern);
    if (matches && matches.length > 0) {
      warned = true;
      console.warn(`  warning: found ${matches.length} possible ${name}(s) in ${textPath} -- review before reuse.`);
    }
  }
  if (!warned) {
    console.log(`  no heuristic matches in ${textPath} (this is not a guarantee -- it is a first-pass assist).`);
  }
}
