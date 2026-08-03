#!/usr/bin/env node
// Validate a least-privilege product-video remediation assignment.
// Usage: node validate-remediation-assignment.mjs <path-to-remediation-assignment.json>
import { readFileSync } from "node:fs";

const inputPath = process.argv[2];
if (!inputPath || process.argv.length !== 3) {
  console.error("Usage: node validate-remediation-assignment.mjs <path-to-remediation-assignment.json>");
  process.exit(1);
}

const DOMAINS = new Set([
  "story-script",
  "product-seed-data",
  "capture-playwright",
  "remotion-composition",
  "narration-audio",
  "captions",
  "export-pipeline",
  "infrastructure-assets",
]);
const SHA256 = /^[a-f0-9]{64}$/;
const FINDING_ID = /^PVF-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const ASSIGNMENT_ID = /^PVA-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const DRIVE_OR_ROOT = /^(?:[A-Za-z]:[\\/]|[\\/])/;
const PARENT_SEGMENT = /(?:^|[\\/])\.\.(?:[\\/]|$)/;
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
function uniqueStrings(values, path, { minItems = 0, pattern, repositoryPath = false } = {}) {
  if (!Array.isArray(values)) {
    fail(path, "must be an array.");
    return new Set();
  }
  if (values.length < minItems) fail(path, `must contain at least ${minItems} item(s).`);
  const seen = new Set();
  values.forEach((value, index) => {
    const itemPath = `${path}[${index}]`;
    if (typeof value !== "string" || value.trim().length === 0) fail(itemPath, "must be a non-empty string.");
    else {
      if (pattern && !pattern.test(value)) fail(itemPath, "has an invalid format.");
      if (repositoryPath && (DRIVE_OR_ROOT.test(value) || PARENT_SEGMENT.test(value))) {
        fail(itemPath, "must be repository-relative and must not contain parent traversal.");
      }
    }
    if (seen.has(value)) fail(itemPath, `duplicates "${value}".`);
    seen.add(value);
  });
  return seen;
}

let assignment;
try {
  assignment = JSON.parse(readFileSync(inputPath, "utf8"));
} catch (error) {
  console.error(`[error] ${inputPath}: ${error.message}`);
  process.exit(1);
}

const rootRequired = [
  "schemaVersion",
  "assignmentId",
  "candidateId",
  "domain",
  "assignedFindingIds",
  "permittedFiles",
  "prohibitedFiles",
  "evidence",
  "reproductionSteps",
  "validationCommands",
  "definitionOfDone",
  "permissions",
];
if (exactObject(assignment, "$", rootRequired)) {
  if (assignment.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
  matches(assignment.assignmentId, ASSIGNMENT_ID, "$.assignmentId", "a canonical PVA assignment identifier");
  matches(assignment.candidateId, SAFE_ID, "$.candidateId", "a safe candidate identifier");
  if (!DOMAINS.has(assignment.domain)) fail("$.domain", "must be a canonical remediation domain.");
  uniqueStrings(assignment.assignedFindingIds, "$.assignedFindingIds", { minItems: 1, pattern: FINDING_ID });
  const permitted = uniqueStrings(assignment.permittedFiles, "$.permittedFiles", { minItems: 1, repositoryPath: true });
  const prohibited = uniqueStrings(assignment.prohibitedFiles, "$.prohibitedFiles", { minItems: 1, repositoryPath: true });
  for (const path of permitted) if (prohibited.has(path)) fail("$.permittedFiles", `"${path}" is also prohibited.`);

  if (!Array.isArray(assignment.evidence) || assignment.evidence.length === 0) fail("$.evidence", "must contain at least one immutable evidence reference.");
  else {
    const artifactIds = new Set();
    assignment.evidence.forEach((item, index) => {
      const path = `$.evidence[${index}]`;
      if (!exactObject(item, path, ["artifactId", "artifactPath", "sha256", "description"])) return;
      matches(item.artifactId, SAFE_ID, `${path}.artifactId`, "a safe artifact identifier");
      nonEmpty(item.artifactPath, `${path}.artifactPath`);
      matches(item.sha256, SHA256, `${path}.sha256`, "a lowercase 64-character SHA-256 digest");
      nonEmpty(item.description, `${path}.description`);
      if (artifactIds.has(item.artifactId)) fail(`${path}.artifactId`, `duplicates "${item.artifactId}".`);
      artifactIds.add(item.artifactId);
    });
  }

  uniqueStrings(assignment.reproductionSteps, "$.reproductionSteps", { minItems: 1 });
  if (!Array.isArray(assignment.validationCommands) || assignment.validationCommands.length === 0) {
    fail("$.validationCommands", "must contain at least one deterministic validation command.");
  } else assignment.validationCommands.forEach((item, index) => {
    const path = `$.validationCommands[${index}]`;
    if (!exactObject(item, path, ["command", "expectedResult"])) return;
    nonEmpty(item.command, `${path}.command`);
    nonEmpty(item.expectedResult, `${path}.expectedResult`);
  });
  uniqueStrings(assignment.definitionOfDone, "$.definitionOfDone", { minItems: 1 });

  const permissionNames = [
    "writeScope",
    "mayApproveRelease",
    "destructiveGitAllowed",
    "forcePushAllowed",
    "broadWorkspaceWritesAllowed",
    "mayDeleteSourceEvidence",
  ];
  if (exactObject(assignment.permissions, "$.permissions", permissionNames)) {
    if (assignment.permissions.writeScope !== "assigned-files-only") fail("$.permissions.writeScope", 'must equal "assigned-files-only".');
    for (const name of permissionNames.slice(1)) {
      if (assignment.permissions[name] !== false) fail(`$.permissions.${name}`, "must be false.");
    }
  }
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`\nRemediation assignment checked: ${errors.length} error(s).`);
process.exit(errors.length > 0 ? 1 : 0);
