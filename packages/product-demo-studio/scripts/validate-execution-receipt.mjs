#!/usr/bin/env node
// Validate a read-only execution receipt used as an operational trace, not a security attestation.
// Usage: node validate-execution-receipt.mjs <receipt.json>
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";

const [inputArg] = process.argv.slice(2);
if (!inputArg || process.argv.length !== 3) {
  console.error("Usage: node validate-execution-receipt.mjs <receipt.json>");
  process.exit(1);
}

const inputPath = resolve(inputArg);
const ROLES = new Set(["reviewer", "arbiter", "final-verifier"]);
const DOMAINS = new Set([
  "story-experience",
  "screen-accuracy-compliance",
  "audio-captions-synchronization",
  "technical-frame-integrity",
]);
const MECHANISMS = new Set([
  "host-native-read-only-context",
  "os-filesystem-read-only-sandbox",
  "container-read-only-mount",
  "virtual-machine-read-only-snapshot",
]);
const READ_ONLY_TOOL_CLASSES = new Set([
  "filesystem-read",
  "filesystem-search",
  "structured-data-read",
  "media-inspect",
  "browser-playback-read",
  "process-inspect",
  "version-control-read",
  "github-read",
  "notion-read",
  "linear-read",
  "checksum",
]);
const RECEIPT_ID = /^PVE-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const SHA256 = /^[a-f0-9]{64}$/;
const RFC3339 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const errors = [];

function fail(path, message) { errors.push(`${path}: ${message}`); }
function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function exactObject(value, path, required, optional = []) {
  if (!object(value)) { fail(path, "must be an object."); return false; }
  const allowed = new Set([...required, ...optional]);
  for (const key of required) if (!Object.hasOwn(value, key)) fail(path, `missing required property "${key}".`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(path, `unknown property "${key}".`);
  return true;
}
function safeId(value, path) {
  if (typeof value !== "string" || !SAFE_ID.test(value)) fail(path, "must be a safe identifier.");
}
function timestamp(value, path) {
  if (typeof value !== "string" || !RFC3339.test(value) || !Number.isFinite(Date.parse(value))) {
    fail(path, "must be an RFC 3339 date-time with timezone.");
    return undefined;
  }
  return Date.parse(value);
}
function validateTools(values, path) {
  if (!Array.isArray(values) || values.length === 0) { fail(path, "must contain at least one item."); return; }
  const seen = new Set();
  values.forEach((value, index) => {
    if (!READ_ONLY_TOOL_CLASSES.has(value)) fail(`${path}[${index}]`, "contains an unsupported value.");
    if (seen.has(value)) fail(`${path}[${index}]`, `duplicates "${value}".`);
    seen.add(value);
  });
}

let receipt;
if (!existsSync(inputPath) || !statSync(inputPath).isFile()) {
  fail("$receipt", `does not reference a file: ${inputPath}`);
} else {
  try { receipt = JSON.parse(readFileSync(inputPath, "utf8")); }
  catch (error) { fail("$receipt", `must contain valid JSON: ${error.message}`); }
}

const required = [
  "schemaVersion", "receiptId", "immutable", "role", "contextId", "candidateId",
  "hostId", "mechanism", "readOnly", "writeTools", "permittedReadOnlyTools",
  "startedAt", "completedAt", "issuedAt",
];
if (receipt && exactObject(receipt, "$", required, ["domain", "inputArtifactSha256", "resultPayloadSha256"])) {
  if (receipt.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
  if (typeof receipt.receiptId !== "string" || !RECEIPT_ID.test(receipt.receiptId)) fail("$.receiptId", "must be a canonical PVE identifier.");
  if (receipt.immutable !== true) fail("$.immutable", "must be true.");
  if (!ROLES.has(receipt.role)) fail("$.role", "must be reviewer, arbiter, or final-verifier.");
  if (receipt.role === "reviewer") {
    if (!DOMAINS.has(receipt.domain)) fail("$.domain", "must be a canonical reviewer domain.");
  } else if (Object.hasOwn(receipt, "domain")) fail("$.domain", "is allowed only for reviewer receipts.");
  for (const field of ["contextId", "candidateId", "hostId"]) safeId(receipt[field], `$.${field}`);
  for (const field of ["inputArtifactSha256", "resultPayloadSha256"]) {
    if (Object.hasOwn(receipt, field) && (typeof receipt[field] !== "string" || !SHA256.test(receipt[field]))) fail(`$.${field}`, "must be a lowercase SHA-256 digest.");
  }
  if (!MECHANISMS.has(receipt.mechanism)) fail("$.mechanism", "must identify a supported read-only mechanism.");
  if (receipt.readOnly !== true) fail("$.readOnly", "must be true.");
  if (!Array.isArray(receipt.writeTools) || receipt.writeTools.length !== 0) fail("$.writeTools", "must be an empty array.");
  validateTools(receipt.permittedReadOnlyTools, "$.permittedReadOnlyTools");
  const startedAt = timestamp(receipt.startedAt, "$.startedAt");
  const completedAt = timestamp(receipt.completedAt, "$.completedAt");
  const issuedAt = timestamp(receipt.issuedAt, "$.issuedAt");
  if (startedAt !== undefined && completedAt !== undefined && completedAt < startedAt) fail("$.completedAt", "must not precede startedAt.");
  if (completedAt !== undefined && issuedAt !== undefined && issuedAt < completedAt) fail("$.issuedAt", "must not precede completedAt.");
}

if (errors.length > 0) {
  for (const error of errors) console.error(`[error] ${error}`);
  console.error(`\nExecution receipt checked: ${errors.length} error(s).`);
  process.exit(1);
}
console.log(`Execution receipt checked: PASS (${receipt.receiptId}).`);
