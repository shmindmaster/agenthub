#!/usr/bin/env node
// Verify the named human's detached signature over exact script/truth/claim hashes and emit deterministic evidence.
import { createHash, createPublicKey, verify } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";

const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
};
const receiptArg = flag("--receipt");
const signatureArg = flag("--signature");
const outArg = flag("--out");
const candidateId = flag("--candidate-id");
const episodeId = flag("--episode-id");
const artifactIds = {
  receipt: flag("--receipt-artifact-id"),
  signature: flag("--signature-artifact-id"),
  script: flag("--script-artifact-id"),
  truthSheet: flag("--truth-sheet-artifact-id"),
  claimLedger: flag("--claim-ledger-artifact-id"),
  finalCaptureInput: flag("--final-capture-input-artifact-id"),
};
if (!receiptArg || !signatureArg || !outArg || !candidateId || !episodeId || Object.values(artifactIds).some((value) => !value)) {
  console.error("Usage: node validate-script-approval.mjs --receipt <json> --signature <ed25519> --out <report.json> --candidate-id <id> --episode-id <id> --receipt-artifact-id <id> --signature-artifact-id <id> --script-artifact-id <id> --truth-sheet-artifact-id <id> --claim-ledger-artifact-id <id> --final-capture-input-artifact-id <id>");
  process.exit(1);
}

const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const RECEIPT_ID = /^PVS-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const receiptPath = resolve(receiptArg);
const signaturePath = resolve(signatureArg);
const outputPath = resolve(outArg);
const receiptDir = dirname(receiptPath);
const errors = [];
const inputs = [];

function fail(message) {
  errors.push(message);
}

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactObject(value, path, required) {
  if (!object(value)) {
    fail(`${path} must be an object.`);
    return false;
  }
  const allowed = new Set(required);
  for (const key of required) if (!Object.hasOwn(value, key)) fail(`${path} missing required property "${key}".`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(`${path} has unknown property "${key}".`);
  return true;
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function resolveReceiptPath(path) {
  return isAbsolute(path) ? resolve(path) : resolve(receiptDir, path);
}

function artifact(value, path, artifactId) {
  if (!exactObject(value, path, ["artifactPath", "sha256"])) return;
  if (typeof value.artifactPath !== "string" || value.artifactPath.trim().length === 0) {
    fail(`${path}.artifactPath must be non-empty.`);
    return;
  }
  if (typeof value.sha256 !== "string" || !SHA256.test(value.sha256)) {
    fail(`${path}.sha256 must be a lowercase SHA-256 digest.`);
  }
  const absolutePath = resolveReceiptPath(value.artifactPath);
  if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
    fail(`${path}.artifactPath does not reference a file (${absolutePath}).`);
    return;
  }
  const actualSha = sha256(readFileSync(absolutePath));
  if (value.sha256 !== actualSha) fail(`${path}.sha256 does not match the referenced file (actual ${actualSha}).`);
  inputs.push({ artifactId, sha256: actualSha });
}

let receiptBytes;
let signatureBytes;
let receipt;
try {
  receiptBytes = readFileSync(receiptPath);
  signatureBytes = readFileSync(signaturePath);
  receipt = JSON.parse(receiptBytes.toString("utf8"));
} catch (error) {
  console.error(`[error] ${error.message}`);
  process.exit(1);
}

for (const [name, id] of Object.entries(artifactIds)) {
  if (!SAFE_ID.test(id)) fail(`--${name}-artifact-id must be a safe artifact identifier.`);
}
if (!SAFE_ID.test(candidateId)) fail("--candidate-id must be a safe candidate identifier.");
if (!SAFE_ID.test(episodeId)) fail("--episode-id must be a safe episode identifier.");
if (exactObject(receipt, "$", [
  "schemaVersion", "receiptId", "decision", "candidateId", "episodeId", "approver",
  "approverPublicKeySha256", "approvedAt", "finalCaptureInput", "artifacts",
])) {
  if (receipt.schemaVersion !== "1.0.0") fail('$.schemaVersion must equal "1.0.0".');
  if (!RECEIPT_ID.test(receipt.receiptId ?? "")) fail("$.receiptId must be a canonical PVS identifier.");
  if (receipt.decision !== "APPROVED") fail('$.decision must equal "APPROVED".');
  if (receipt.candidateId !== candidateId) fail("$.candidateId must equal the requested immutable candidate lineage ID.");
  if (receipt.episodeId !== episodeId) fail("$.episodeId must equal the requested episode ID.");
  if (exactObject(receipt.approver, "$.approver", ["name", "method"])) {
    if (typeof receipt.approver.name !== "string" || receipt.approver.name.trim().length < 2 || /^(human|user|approver|unknown|n\/a)$/i.test(receipt.approver.name.trim())) {
      fail("$.approver.name must identify the actual human approver, not a placeholder.");
    }
    if (receipt.approver.method !== "detached-ed25519") fail('$.approver.method must equal "detached-ed25519".');
  }
  if (!Number.isFinite(Date.parse(receipt.approvedAt))) fail("$.approvedAt must be a valid RFC 3339 date-time.");
  artifact(receipt.finalCaptureInput, "$.finalCaptureInput", artifactIds.finalCaptureInput);
  if (exactObject(receipt.artifacts, "$.artifacts", ["script", "truthSheet", "claimLedger"])) {
    artifact(receipt.artifacts.script, "$.artifacts.script", artifactIds.script);
    artifact(receipt.artifacts.truthSheet, "$.artifacts.truthSheet", artifactIds.truthSheet);
    artifact(receipt.artifacts.claimLedger, "$.artifacts.claimLedger", artifactIds.claimLedger);
  }
}

const trustedKeyPath = process.env.AGENTHUB_SCRIPT_APPROVER_PUBLIC_KEY;
if (!trustedKeyPath) {
  fail("AGENTHUB_SCRIPT_APPROVER_PUBLIC_KEY must reference the trusted human approver public key PEM.");
} else {
  try {
    const publicKey = createPublicKey(readFileSync(resolve(trustedKeyPath)));
    const fingerprint = sha256(publicKey.export({ type: "spki", format: "der" }));
    if (receipt.approverPublicKeySha256 !== fingerprint) {
      fail(`$.approverPublicKeySha256 does not match the trusted key (actual ${fingerprint}).`);
    }
    if (signatureBytes.length !== 64 || !verify(null, receiptBytes, publicKey, signatureBytes)) {
      fail("signature is not a valid raw Ed25519 signature over the exact approval-receipt bytes.");
    }
  } catch (error) {
    fail(`trusted key or signature could not be verified: ${error.message}`);
  }
}
inputs.unshift(
  { artifactId: artifactIds.receipt, sha256: sha256(receiptBytes) },
  { artifactId: artifactIds.signature, sha256: sha256(signatureBytes) },
);

if (errors.length > 0) {
  for (const error of errors) console.error(`[error] ${error}`);
  console.error(`\nScript approval checked: ${errors.length} error(s).`);
  process.exit(1);
}

const report = {
  schemaVersion: "1.0.0",
  candidateId,
  reportType: "scriptApprovalVerification",
  status: "PASS",
  generator: {
    tool: "product-demo-studio-script-approval-validator",
    version: "1.0.0",
    command: process.argv.map((part) => JSON.stringify(part)).join(" "),
  },
  inputs,
  checks: [{
    id: "human-script-approval",
    passed: true,
    evidenceArtifactIds: Object.values(artifactIds),
  }],
  summary: { total: 1, passed: 1, failed: 0 },
  generatedAt: new Date().toISOString(),
};
mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(`PASS: named human approval is bound to exact script, truth-sheet, and claim-ledger bytes (${receipt.receiptId}).`);
