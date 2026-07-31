#!/usr/bin/env node
// Validate a host-emitted execution receipt and its raw detached Ed25519 signature.
// The trusted host/key mapping is selected only by the operator-controlled
// AGENTHUB_EXECUTION_HOST_TRUST_CONFIG environment variable.
// Usage: node validate-execution-receipt.mjs <receipt.json> <receipt.ed25519>
import {
  createHash,
  createPublicKey,
  verify as verifySignature,
} from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";

const [inputArg, signatureArg] = process.argv.slice(2);
if (!inputArg || !signatureArg || process.argv.length !== 4) {
  console.error(
    "Usage: node validate-execution-receipt.mjs <receipt.json> <receipt.ed25519>",
  );
  process.exit(1);
}

const inputPath = resolve(inputArg);
const signaturePath = resolve(signatureArg);
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
const RFC3339 =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
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

function safeId(value, path) {
  return nonEmpty(value, path) && (
    SAFE_ID.test(value) || (fail(path, "must be a safe identifier."), false)
  );
}

function timestamp(value, path) {
  if (typeof value !== "string" || !RFC3339.test(value) || !Number.isFinite(Date.parse(value))) {
    fail(path, "must be an RFC 3339 date-time with timezone.");
    return undefined;
  }
  return Date.parse(value);
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function readRequiredFile(path, label) {
  if (!existsSync(path)) {
    fail(label, `does not reference a file: ${path}`);
    return undefined;
  }
  try {
    if (!statSync(path).isFile()) {
      fail(label, `does not reference a file: ${path}`);
      return undefined;
    }
    return readFileSync(path);
  } catch (error) {
    fail(label, `cannot be read: ${error.message}`);
    return undefined;
  }
}

function parseJson(bytes, label) {
  if (!bytes) return undefined;
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(label, `must contain valid JSON: ${error.message}`);
    return undefined;
  }
}

function validateUniqueEnum(values, path, allowed) {
  if (!Array.isArray(values) || values.length === 0) {
    fail(path, "must contain at least one item.");
    return;
  }
  const seen = new Set();
  values.forEach((value, index) => {
    if (!allowed.has(value)) fail(`${path}[${index}]`, "contains an unsupported value.");
    if (seen.has(value)) fail(`${path}[${index}]`, `duplicates "${value}".`);
    seen.add(value);
  });
}

function loadTrustedHost(receipt) {
  const configuredPath = process.env.AGENTHUB_EXECUTION_HOST_TRUST_CONFIG;
  if (!configuredPath || configuredPath.trim().length === 0) {
    fail(
      "AGENTHUB_EXECUTION_HOST_TRUST_CONFIG",
      "must reference the AgentHub-owned trusted execution-host registry.",
    );
    return undefined;
  }
  const trustPath = resolve(configuredPath);
  const trustBytes = readRequiredFile(trustPath, "AGENTHUB_EXECUTION_HOST_TRUST_CONFIG");
  const trust = parseJson(trustBytes, "AGENTHUB_EXECUTION_HOST_TRUST_CONFIG");
  if (!trust) return undefined;
  if (!exactObject(trust, "$trust", ["schemaVersion", "hosts"])) return undefined;
  if (trust.schemaVersion !== "1.0.0") {
    fail("$trust.schemaVersion", 'must equal "1.0.0".');
  }
  if (!Array.isArray(trust.hosts) || trust.hosts.length === 0) {
    fail("$trust.hosts", "must contain at least one trusted host key.");
    return undefined;
  }

  const identities = new Set();
  let selected;
  trust.hosts.forEach((host, index) => {
    const path = `$trust.hosts[${index}]`;
    const required = [
      "hostId",
      "keyId",
      "enabled",
      "publicKeyPath",
      "publicKeySha256",
      "allowedRoles",
      "allowedMechanisms",
      "allowedReadOnlyTools",
    ];
    if (!exactObject(host, path, required)) return;
    safeId(host.hostId, `${path}.hostId`);
    safeId(host.keyId, `${path}.keyId`);
    const identity = `${host.hostId}\u0000${host.keyId}`;
    if (identities.has(identity)) fail(path, "duplicates a hostId/keyId trust entry.");
    identities.add(identity);
    if (typeof host.enabled !== "boolean") fail(`${path}.enabled`, "must be a boolean.");
    nonEmpty(host.publicKeyPath, `${path}.publicKeyPath`);
    if (typeof host.publicKeySha256 !== "string" || !SHA256.test(host.publicKeySha256)) {
      fail(`${path}.publicKeySha256`, "must be a lowercase SHA-256 digest.");
    }
    validateUniqueEnum(host.allowedRoles, `${path}.allowedRoles`, ROLES);
    validateUniqueEnum(host.allowedMechanisms, `${path}.allowedMechanisms`, MECHANISMS);
    validateUniqueEnum(
      host.allowedReadOnlyTools,
      `${path}.allowedReadOnlyTools`,
      READ_ONLY_TOOL_CLASSES,
    );
    if (host.hostId === receipt?.hostId && host.keyId === receipt?.hostKeyId) {
      selected = { host, path, trustPath };
    }
  });

  if (!selected) {
    fail(
      "$.hostId",
      `host/key "${receipt?.hostId ?? "unknown"}/${receipt?.hostKeyId ?? "unknown"}" is not trusted.`,
    );
    return undefined;
  }
  if (selected.host.enabled !== true) {
    fail(selected.path, "trusted host key is disabled.");
    return undefined;
  }
  return selected;
}

function validateTrustedAuthorization(receipt, selected) {
  if (!selected) return undefined;
  const { host, path, trustPath } = selected;
  if (!host.allowedRoles.includes(receipt.role)) {
    fail("$.role", `is not authorized by ${path}.allowedRoles.`);
  }
  if (!host.allowedMechanisms.includes(receipt.mechanism)) {
    fail("$.mechanism", `is not authorized by ${path}.allowedMechanisms.`);
  }
  if (Array.isArray(receipt.permittedReadOnlyTools)) {
    receipt.permittedReadOnlyTools.forEach((tool, index) => {
      if (!host.allowedReadOnlyTools.includes(tool)) {
        fail(
          `$.permittedReadOnlyTools[${index}]`,
          `is not authorized by ${path}.allowedReadOnlyTools.`,
        );
      }
    });
  }

  if (typeof host.publicKeyPath !== "string" || host.publicKeyPath.trim().length === 0) {
    return undefined;
  }
  const keyPath = resolve(dirname(trustPath), host.publicKeyPath);
  const keyBytes = readRequiredFile(keyPath, `${path}.publicKeyPath`);
  if (!keyBytes) return undefined;
  const keyText = keyBytes.toString("utf8");
  if (!keyText.includes("-----BEGIN PUBLIC KEY-----") || keyText.includes("PRIVATE KEY")) {
    fail(`${path}.publicKeyPath`, "must contain a public-key-only PEM.");
    return undefined;
  }
  try {
    const key = createPublicKey(keyBytes);
    if (key.asymmetricKeyType !== "ed25519") {
      fail(
        `${path}.publicKeyPath`,
        `must contain an Ed25519 public key, found ${key.asymmetricKeyType ?? "unknown"}.`,
      );
      return undefined;
    }
    const fingerprint = digest(key.export({ type: "spki", format: "der" }));
    if (host.publicKeySha256 !== fingerprint) {
      fail(
        `${path}.publicKeySha256`,
        `declares ${host.publicKeySha256}, actual Ed25519 SPKI fingerprint is ${fingerprint}.`,
      );
      return undefined;
    }
    return key;
  } catch (error) {
    fail(`${path}.publicKeyPath`, `is not a valid public key: ${error.message}`);
    return undefined;
  }
}

const receiptBytes = readRequiredFile(inputPath, "$receipt");
const receipt = parseJson(receiptBytes, "$receipt");
const signatureBytes = readRequiredFile(signaturePath, "$signature");

if (signatureBytes && signatureBytes.length !== 64) {
  fail("$signature", "an Ed25519 detached signature must contain exactly 64 raw bytes.");
}

const required = [
  "schemaVersion",
  "receiptId",
  "immutable",
  "role",
  "contextId",
  "candidateId",
  "hostId",
  "hostKeyId",
  "mechanism",
  "readOnly",
  "writeTools",
  "permittedReadOnlyTools",
  "startedAt",
  "completedAt",
  "issuedAt",
];
if (receipt && exactObject(receipt, "$", required, ["domain", "inputArtifactSha256", "resultPayloadSha256"])) {
  if (receipt.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
  if (typeof receipt.receiptId !== "string" || !RECEIPT_ID.test(receipt.receiptId)) {
    fail("$.receiptId", "must be a canonical PVE execution-receipt identifier.");
  }
  if (receipt.immutable !== true) fail("$.immutable", "must be true.");
  if (!ROLES.has(receipt.role)) fail("$.role", "must be reviewer, arbiter, or final-verifier.");
  if (receipt.role === "reviewer") {
    if (!DOMAINS.has(receipt.domain)) fail("$.domain", "must be a canonical reviewer domain.");
  } else if (Object.hasOwn(receipt, "domain")) {
    fail("$.domain", "is allowed only for reviewer receipts.");
  }
  for (const field of ["contextId", "candidateId", "hostId", "hostKeyId"]) {
    safeId(receipt[field], `$.${field}`);
  }
  for (const field of ["inputArtifactSha256", "resultPayloadSha256"]) {
    if (Object.hasOwn(receipt, field) && (typeof receipt[field] !== "string" || !SHA256.test(receipt[field]))) {
      fail(`$.${field}`, "must be a lowercase SHA-256 digest.");
    }
  }
  if (!MECHANISMS.has(receipt.mechanism)) {
    fail("$.mechanism", "must identify a supported host-enforced read-only mechanism.");
  }
  if (receipt.readOnly !== true) fail("$.readOnly", "must be true.");
  if (!Array.isArray(receipt.writeTools) || receipt.writeTools.length !== 0) {
    fail("$.writeTools", "must be an empty array.");
  }
  validateUniqueEnum(
    receipt.permittedReadOnlyTools,
    "$.permittedReadOnlyTools",
    READ_ONLY_TOOL_CLASSES,
  );
  const startedAt = timestamp(receipt.startedAt, "$.startedAt");
  const completedAt = timestamp(receipt.completedAt, "$.completedAt");
  const issuedAt = timestamp(receipt.issuedAt, "$.issuedAt");
  if (startedAt !== undefined && completedAt !== undefined && completedAt < startedAt) {
    fail("$.completedAt", "must not precede startedAt.");
  }
  if (completedAt !== undefined && issuedAt !== undefined && issuedAt < completedAt) {
    fail("$.issuedAt", "must not precede completedAt.");
  }

  const selected = loadTrustedHost(receipt);
  const trustedKey = validateTrustedAuthorization(receipt, selected);
  if (trustedKey && receiptBytes && signatureBytes?.length === 64) {
    let valid = false;
    try {
      valid = verifySignature(null, receiptBytes, trustedKey, signatureBytes);
    } catch (error) {
      fail("$signature", `could not be verified: ${error.message}`);
    }
    if (!valid) {
      fail(
        "$signature",
        "is not a valid Ed25519 signature over the exact execution-receipt bytes from the trusted host key.",
      );
    }
  }
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`\nSigned execution receipt checked: ${errors.length} error(s).`);
process.exit(errors.length > 0 ? 1 : 0);
