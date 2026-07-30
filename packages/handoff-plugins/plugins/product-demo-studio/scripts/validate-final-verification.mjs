#!/usr/bin/env node
// Validate the fresh final-verifier report and every immutable artifact it cites.
// All artifact paths are resolved relative to the JSON document that contains them.
// Usage: node validate-final-verification.mjs <path-to-final-verification.json>
import { createHash } from "node:crypto";
import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const inputArg = process.argv[2];
if (!inputArg || process.argv.length !== 3) {
  console.error("Usage: node validate-final-verification.mjs <path-to-final-verification.json>");
  process.exit(1);
}

const inputPath = resolve(inputArg);
const scriptDir = dirname(fileURLToPath(import.meta.url));
const REVIEW_DOMAINS = [
  "story-experience",
  "screen-accuracy-compliance",
  "audio-captions-synchronization",
  "technical-frame-integrity",
];
const CHECKS = [
  "candidateIdentity",
  "preflightIdentity",
  "reviewIdentityAndIndependence",
  "arbiterIdentity",
  "rerunPolicy",
  "thresholdsAndFindings",
  "checksumsAndProvenance",
  "playbackAndReproduction",
  "deliveryContents",
];
const SHA256 = /^[a-f0-9]{64}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const VERIFICATION_ID = /^PVV-[A-Z0-9][A-Z0-9-]*-[0-9]{3,}$/;
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

function validateReference(reference, label, containingPath, parseAsJson = true) {
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
  if (reference.bytes !== bytes.length) {
    fail(`${label}.bytes`, `declares ${reference.bytes}, actual file has ${bytes.length}.`);
  }
  const actualSha = digest(bytes);
  if (reference.sha256 !== actualSha) {
    fail(`${label}.sha256`, `declares ${reference.sha256}, actual file is ${actualSha}.`);
  }
  return {
    absolute,
    data: parseAsJson ? parseJson(bytes, `${label}.artifactPath`) : undefined,
  };
}

function validateCandidate(candidate, label, containingPath) {
  if (!exactObject(candidate, label, [
    "candidateId",
    "artifactPath",
    "sha256",
    "bytes",
    "sourceRevision",
    "renderProvenanceId",
  ])) return null;
  if (typeof candidate.candidateId !== "string" || !SAFE_ID.test(candidate.candidateId)) {
    fail(`${label}.candidateId`, "must be a safe candidate identifier.");
  }
  nonEmpty(candidate.sourceRevision, `${label}.sourceRevision`);
  nonEmpty(candidate.renderProvenanceId, `${label}.renderProvenanceId`);
  return validateReference(
    {
      artifactPath: candidate.artifactPath,
      sha256: candidate.sha256,
      bytes: candidate.bytes,
    },
    label,
    containingPath,
    false,
  );
}

function sameCandidate(actual, expected, actualPath, expectedPath, label) {
  if (!object(actual)) {
    fail(label, "must contain a candidate object.");
    return;
  }
  for (const key of ["candidateId", "sha256", "sourceRevision", "renderProvenanceId"]) {
    if (actual[key] !== expected[key]) fail(`${label}.${key}`, `must match final-verification candidate ${key}.`);
  }
  if (!nonEmpty(actual.artifactPath, `${label}.artifactPath`)) return;
  const actualAsset = canonicalPath(dirname(actualPath), actual.artifactPath);
  const expectedAsset = canonicalPath(dirname(expectedPath), expected.artifactPath);
  if (actualAsset !== expectedAsset) {
    fail(`${label}.artifactPath`, "must resolve to the exact final-verification candidate file.");
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

function validateExecutionReceipt(reference, label, expected) {
  if (!exactObject(reference, label, ["receipt", "signature"])) return null;
  const loaded = validateReference(reference.receipt, `${label}.receipt`, inputPath);
  const signature = validateReference(
    reference.signature,
    `${label}.signature`,
    inputPath,
    false,
  );
  if (reference.signature?.bytes !== 64) {
    fail(`${label}.signature.bytes`, "must equal 64 for a raw Ed25519 signature.");
  }
  if (!loaded?.data || !signature) return null;
  const result = spawnSync(process.execPath, [
    resolve(scriptDir, "validate-execution-receipt.mjs"),
    loaded.absolute,
    signature.absolute,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    const detail = `${result.stderr ?? ""}\n${result.stdout ?? ""}`.trim().split(/\r?\n/)[0];
    fail(label, `semantic validator rejected the signed receipt${detail ? `: ${detail}` : "."}`);
    return null;
  }
  for (const [field, value] of Object.entries(expected)) {
    if (loaded.data[field] !== value) {
      fail(`${label}.${field}`, `receipt value ${JSON.stringify(loaded.data[field])} must equal ${JSON.stringify(value)}.`);
    }
  }
  return loaded.data;
}

const report = readJson(inputPath, "$");
if (report) {
  const rootRequired = [
    "schemaVersion",
    "verificationId",
    "candidate",
    "verifier",
    "preflight",
    "reviewReports",
    "arbiterDecision",
    "checks",
    "status",
    "limitations",
    "verifiedAt",
  ];
  if (exactObject(report, "$", rootRequired)) {
    if (report.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
    if (typeof report.verificationId !== "string" || !VERIFICATION_ID.test(report.verificationId)) {
      fail("$.verificationId", "must be a canonical PVV verification identifier.");
    }

    validateCandidate(report.candidate, "$.candidate", inputPath);

    let verifierContext;
    if (exactObject(report.verifier, "$.verifier", [
      "contextId",
      "readOnly",
      "independent",
      "executionReceipt",
    ])) {
      nonEmpty(report.verifier.contextId, "$.verifier.contextId");
      verifierContext = report.verifier.contextId;
      if (report.verifier.readOnly !== true) fail("$.verifier.readOnly", "must be true.");
      if (report.verifier.independent !== true) fail("$.verifier.independent", "must be true.");
      validateExecutionReceipt(report.verifier.executionReceipt, "$.verifier.executionReceipt", {
        role: "final-verifier",
        contextId: report.verifier.contextId,
        candidateId: report.candidate?.candidateId,
        issuedAt: report.verifiedAt,
      });
    }

    const preflightRef = validateReference(report.preflight, "$.preflight", inputPath);
    if (preflightRef?.data) {
      if (preflightRef.data.candidateId !== report.candidate?.candidateId) {
        fail("$.preflight", "must report the same candidateId as final verification.");
      }
      if (preflightRef.data.status !== "PASS") fail("$.preflight", 'must have status "PASS".');
      if (preflightRef.data.readyForIndependentReview !== true) {
        fail("$.preflight", "must have readyForIndependentReview=true.");
      }
    }

    const reviewFiles = new Map();
    const reviewerContexts = new Set();
    if (!Array.isArray(report.reviewReports) || report.reviewReports.length !== 4) {
      fail("$.reviewReports", "must contain exactly four report references.");
    } else {
      report.reviewReports.forEach((reference, index) => {
        const label = `$.reviewReports[${index}]`;
        if (!object(reference)) {
          fail(label, "must be an object.");
          return;
        }
        const { domain, ...artifactReference } = reference;
        if (!REVIEW_DOMAINS.includes(domain)) fail(`${label}.domain`, "must be a canonical review domain.");
        if (reviewFiles.has(domain)) fail(`${label}.domain`, `duplicates "${domain}".`);
        const loaded = validateReference(artifactReference, label, inputPath);
        if (!loaded?.data) return;
        reviewFiles.set(domain, { ...loaded, reference });
        invokeValidator("validate-review-report.mjs", loaded.absolute, label);
        const review = loaded.data;
        if (review.reviewer?.domain !== domain) fail(`${label}.domain`, "must match reviewer.domain in the report.");
        if (review.domainPass !== true) fail(label, "referenced review must have domainPass=true.");
        sameCandidate(review.candidate, report.candidate, loaded.absolute, inputPath, `${label}.candidate`);
        const contextId = review.reviewer?.contextId;
        if (!nonEmpty(contextId, `${label}.reviewer.contextId`)) return;
        if (contextId === verifierContext) fail(`${label}.reviewer.contextId`, "must differ from the final verifier context.");
        if (reviewerContexts.has(contextId)) fail(`${label}.reviewer.contextId`, "must be unique across reviewers.");
        reviewerContexts.add(contextId);
      });
    }
    for (const domain of REVIEW_DOMAINS) {
      if (!reviewFiles.has(domain)) fail("$.reviewReports", `missing "${domain}" report.`);
    }

    const arbiterRef = validateReference(report.arbiterDecision, "$.arbiterDecision", inputPath);
    if (arbiterRef?.data) {
      invokeValidator("validate-release-decision.mjs", arbiterRef.absolute, "$.arbiterDecision");
      const decision = arbiterRef.data;
      if (decision.decision !== "PASS") fail("$.arbiterDecision", 'must contain decision "PASS".');
      sameCandidate(decision.candidate, report.candidate, arbiterRef.absolute, inputPath, "$.arbiterDecision.candidate");
      if (!object(decision.preflight) ||
          decision.preflight.sha256 !== report.preflight?.sha256 ||
          canonicalPath(dirname(arbiterRef.absolute), decision.preflight?.artifactPath ?? "") !==
            canonicalPath(dirname(inputPath), report.preflight?.artifactPath ?? "")) {
        fail("$.arbiterDecision.preflight", "must bind the exact preflight report referenced by final verification.");
      }
      const arbiterContext = decision.arbiter?.contextId;
      if (!nonEmpty(arbiterContext, "$.arbiterDecision.arbiter.contextId")) {
        // nonEmpty records the error.
      } else {
        if (arbiterContext === verifierContext) fail("$.arbiterDecision.arbiter.contextId", "must differ from the final verifier context.");
        if (reviewerContexts.has(arbiterContext)) fail("$.arbiterDecision.arbiter.contextId", "must differ from every reviewer context.");
      }

      if (!Array.isArray(decision.reviewReports) || decision.reviewReports.length !== 4) {
        fail("$.arbiterDecision.reviewReports", "must bind the same four review reports.");
      } else {
        for (const arbiterReport of decision.reviewReports) {
          const finalReport = reviewFiles.get(arbiterReport.domain);
          const label = `$.arbiterDecision.reviewReports.${arbiterReport.domain ?? "unknown"}`;
          if (!finalReport) {
            fail(label, "does not match a final-verification review domain.");
            continue;
          }
          if (arbiterReport.sha256 !== finalReport.reference.sha256) {
            fail(`${label}.sha256`, "must match the final-verification review digest.");
          }
          if (canonicalPath(dirname(arbiterRef.absolute), arbiterReport.reportPath) !==
              canonicalPath(dirname(inputPath), finalReport.reference.artifactPath)) {
            fail(`${label}.reportPath`, "must resolve to the exact report referenced by final verification.");
          }
          const actualReview = finalReport.data;
          if (arbiterReport.score !== actualReview.score) fail(`${label}.score`, "must match the review report.");
          if (arbiterReport.passed !== actualReview.domainPass) fail(`${label}.passed`, "must match the review report.");
          const blockerFindings = actualReview.findings?.filter((finding) => finding.severity === "blocker").length ?? 0;
          const criticalFindings = actualReview.findings?.filter((finding) => finding.severity === "critical").length ?? 0;
          if (arbiterReport.blockerFindings !== blockerFindings) fail(`${label}.blockerFindings`, "must match the review report.");
          if (arbiterReport.criticalFindings !== criticalFindings) fail(`${label}.criticalFindings`, "must match the review report.");
        }
      }
    }

    if (exactObject(report.checks, "$.checks", CHECKS)) {
      for (const name of CHECKS) {
        if (report.checks[name] !== true) fail(`$.checks.${name}`, "must be true.");
      }
    }
    if (report.status !== "PASS") fail("$.status", 'must equal "PASS".');
    if (!Array.isArray(report.limitations) || report.limitations.length !== 0) {
      fail("$.limitations", "must be an empty array for final PASS.");
    }
    if (typeof report.verifiedAt !== "string" || !Number.isFinite(Date.parse(report.verifiedAt))) {
      fail("$.verifiedAt", "must be a valid RFC 3339 date-time.");
    }
  }
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`\nFinal verification checked: ${errors.length} error(s).`);
process.exit(errors.length > 0 ? 1 : 0);
