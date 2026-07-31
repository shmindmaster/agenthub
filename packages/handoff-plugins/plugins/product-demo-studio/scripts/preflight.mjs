#!/usr/bin/env node
// Fail-closed deterministic gate for one immutable Product Demo Studio evidence package.
// Usage: node preflight.mjs --evidence-package <package.json> --out <preflight-report.json>
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
};
const packagePath = flag("--evidence-package");
const outPath = flag("--out");
if (!packagePath || !outPath) {
  console.error("Usage: node preflight.mjs --evidence-package <package.json> --out <preflight-report.json>");
  process.exit(1);
}

const CHECKS = [
  ["artifact-completeness", "infrastructure-assets"],
  ["script-narration-caption-parity", "narration-audio"],
  ["names-dates-numbers-claims", "story-script"],
  ["caption-overflow-obstruction-speed-safe-areas", "captions"],
  ["audio-loudness", "narration-audio"],
  ["audio-clipping", "narration-audio"],
  ["audio-silence", "narration-audio"],
  ["frame-black", "export-pipeline"],
  ["frame-frozen", "export-pipeline"],
  ["frame-duplicate", "export-pipeline"],
  ["frame-corruption", "export-pipeline"],
  ["asset-completeness", "infrastructure-assets"],
  ["storyboard-craft-contract", "story-script"],
  ["capture-manifest-craft-contract", "capture-playwright"],
  ["beat-timing-deltas", "capture-playwright"],
  ["browser-console-network", "capture-playwright"],
  ["render-errors", "remotion-composition"],
  ["output-specifications", "export-pipeline"],
  ["checksums-provenance", "infrastructure-assets"],
];
const CHECK_IDS = new Set(CHECKS.map(([id]) => id));
const REPORT_TYPES = [
  "mediaMetadata",
  "framesAndContactSheets",
  "sceneBoundaries",
  "frameIntegrity",
  "audioQuality",
  "asrWordTimestamps",
  "captionTimingAndLayout",
  "ocrVisibleText",
  "motionAnalysis",
  "browserPlayback",
  "browserConsole",
  "browserNetwork",
  "technicalDelivery",
  "claimVerification",
  "truthSheetVerification",
  "craftContractValidation",
];
const scriptDir = dirname(fileURLToPath(import.meta.url));
const canonicalPolicy = JSON.parse(
  readFileSync(resolve(scriptDir, "..", "policy", "product-video-policy.json"), "utf8"),
);
const allowedGenerators = canonicalPolicy.deterministicEvidence?.allowedGeneratorsByReportType ?? {};
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const SHA256 = /^[a-f0-9]{64}$/;
const packageAbsolute = resolve(packagePath);
const packageDir = dirname(packageAbsolute);
const packageBytes = existsSync(packageAbsolute) ? readFileSync(packageAbsolute) : Buffer.from("");
const packageSha = createHash("sha256").update(packageBytes).digest("hex");
const startedAt = new Date().toISOString();
const errors = [];
const checkEvidence = new Map(CHECKS.map(([id]) => [id, new Set(["evidence-package"])]));
const checkErrors = new Map(CHECKS.map(([id]) => [id, []]));

function fail(checkId, message, evidenceIds = []) {
  errors.push(`${checkId}: ${message}`);
  checkErrors.get(checkId)?.push(message);
  for (const id of evidenceIds) {
    if (typeof id === "string" && SAFE_ID.test(id)) checkEvidence.get(checkId)?.add(id);
  }
}

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonEmpty(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function hashFile(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function artifactPath(value) {
  return isAbsolute(value) ? resolve(value) : resolve(packageDir, value);
}

function runCanonicalValidator(scriptName, validatorArgs, checkIds, evidenceIds) {
  const validationDir = mkdtempSync(resolve(tmpdir(), "product-demo-preflight-"));
  const outputPath = resolve(validationDir, "canonical-report.json");
  const result = spawnSync(process.execPath, [resolve(scriptDir, scriptName), ...validatorArgs, "--out", outputPath], {
    encoding: "utf8",
    env: process.env,
  });
  rmSync(validationDir, { recursive: true, force: true });
  if (result.status === 0) return;
  const detail = (result.stderr || result.stdout || `validator exited ${result.status}`).trim();
  for (const checkId of checkIds) {
    fail(checkId, `canonical ${scriptName} rerun failed: ${detail}`, evidenceIds);
  }
}

function oneArtifactOfType(inputArtifacts, type) {
  const matches = inputArtifacts.filter((artifact) => artifact.type === type);
  return matches.length === 1 ? matches[0] : null;
}

let evidencePackage = {};
try {
  evidencePackage = JSON.parse(packageBytes.toString("utf8"));
} catch (error) {
  fail("artifact-completeness", `evidence package is missing or invalid JSON: ${error.message}`);
}

const candidateId = object(evidencePackage.candidate) && SAFE_ID.test(evidencePackage.candidate.candidateId ?? "")
  ? evidencePackage.candidate.candidateId
  : "invalid-candidate";
if (evidencePackage.schemaVersion !== "1.0.0") {
  fail("artifact-completeness", 'evidence package schemaVersion must equal "1.0.0".');
}
if (!object(evidencePackage.candidate) || evidencePackage.candidate.immutable !== true) {
  fail("checksums-provenance", "candidate must be explicitly immutable.");
}

const artifacts = new Map();
if (!Array.isArray(evidencePackage.artifacts) || evidencePackage.artifacts.length === 0) {
  fail("artifact-completeness", "artifacts must contain at least one item.");
} else {
  for (const [index, artifact] of evidencePackage.artifacts.entries()) {
    if (!object(artifact) || !SAFE_ID.test(artifact.artifactId ?? "")) {
      fail("artifact-completeness", `artifacts[${index}] has an invalid artifactId.`);
      continue;
    }
    const id = artifact.artifactId;
    checkEvidence.get("artifact-completeness").add(id);
    checkEvidence.get("asset-completeness").add(id);
    checkEvidence.get("checksums-provenance").add(id);
    if (artifacts.has(id)) {
      fail("artifact-completeness", `artifactId "${id}" is duplicated.`, [id]);
      continue;
    }
    artifacts.set(id, artifact);
    if (!nonEmpty(artifact.artifactPath)) {
      fail("artifact-completeness", `artifact "${id}" has no artifactPath.`, [id]);
      continue;
    }
    const fullPath = artifactPath(artifact.artifactPath);
    if (!existsSync(fullPath)) {
      fail("asset-completeness", `artifact "${id}" is missing at ${fullPath}.`, [id]);
      continue;
    }
    const stat = statSync(fullPath);
    if (!stat.isFile()) {
      fail("asset-completeness", `artifact "${id}" is not a file.`, [id]);
      continue;
    }
    if (!Number.isInteger(artifact.bytes) || artifact.bytes !== stat.size) {
      fail("asset-completeness", `artifact "${id}" byte count does not match current bytes.`, [id]);
    }
    if (!SHA256.test(artifact.sha256 ?? "")) {
      fail("checksums-provenance", `artifact "${id}" has an invalid SHA-256 value.`, [id]);
    } else if (hashFile(fullPath) !== artifact.sha256) {
      fail("checksums-provenance", `artifact "${id}" checksum does not match current bytes.`, [id]);
    }
    if (!nonEmpty(artifact.mediaType) || !nonEmpty(artifact.type)) {
      fail("artifact-completeness", `artifact "${id}" is missing type or mediaType.`, [id]);
    }
  }
}

function validateReference(reference, label, checkId) {
  if (!object(reference) || !SAFE_ID.test(reference.artifactId ?? "")) {
    fail(checkId, `${label} is not a valid artifact reference.`);
    return null;
  }
  const artifact = artifacts.get(reference.artifactId);
  if (!artifact) {
    fail(checkId, `${label} references unknown artifact "${reference.artifactId}".`, [reference.artifactId]);
    return null;
  }
  checkEvidence.get(checkId).add(reference.artifactId);
  if (reference.artifactPath !== artifact.artifactPath || reference.sha256 !== artifact.sha256) {
    fail(checkId, `${label} does not match the canonical artifact path/checksum.`, [reference.artifactId]);
  }
  return artifact;
}

const mediaId = evidencePackage.candidate?.mediaArtifactId;
const mediaArtifact = typeof mediaId === "string" ? artifacts.get(mediaId) : null;
if (!mediaArtifact || mediaArtifact.type !== "video") {
  fail("artifact-completeness", "candidate.mediaArtifactId must reference a video artifact.", [mediaId]);
}

const provenance = evidencePackage.provenance;
if (!object(provenance) || !object(provenance.source) || !object(provenance.build) ||
    !object(provenance.configuration) || !object(provenance.capture) || !object(provenance.render)) {
  fail("checksums-provenance", "source/build/configuration/capture/render provenance is incomplete.");
} else {
  if (!nonEmpty(provenance.source.repository) || !nonEmpty(provenance.source.revision) ||
      provenance.source.dirty !== false) {
    fail("checksums-provenance", "source provenance requires repository, revision, and dirty=false.");
  }
  validateReference(provenance.build.manifest, "provenance.build.manifest", "checksums-provenance");
  validateReference(provenance.configuration.manifest, "provenance.configuration.manifest", "checksums-provenance");
  const rawCaptureArtifact = validateReference(
    provenance.capture.rawCapture,
    "provenance.capture.rawCapture",
    "checksums-provenance",
  );
  if (rawCaptureArtifact?.type !== "raw-capture") {
    fail("checksums-provenance", "provenance.capture.rawCapture must reference a raw-capture artifact.", [rawCaptureArtifact?.artifactId]);
  }
  for (const field of ["captureId", "command", "startedAt", "completedAt"]) {
    if (!nonEmpty(provenance.capture[field])) fail("checksums-provenance", `provenance.capture.${field} is required.`);
  }
  const captureStartedAt = Date.parse(provenance.capture.startedAt);
  const captureCompletedAt = Date.parse(provenance.capture.completedAt);
  if (!Number.isFinite(captureStartedAt) || !Number.isFinite(captureCompletedAt) || captureCompletedAt < captureStartedAt) {
    fail("checksums-provenance", "capture provenance must contain an ordered start/completion interval.");
  }
  validateReference(provenance.render.environmentManifest, "provenance.render.environmentManifest", "checksums-provenance");
  const accelerationArtifact = validateReference(
    provenance.render.accelerationManifest,
    "provenance.render.accelerationManifest",
    "checksums-provenance",
  );
  if (accelerationArtifact) {
    try {
      const acceleration = JSON.parse(readFileSync(artifactPath(accelerationArtifact.artifactPath), "utf8"));
      if (!object(acceleration) || !["gpu-preferred", "cpu-fallback"].includes(acceleration.mode) ||
          !object(acceleration.selection) || !nonEmpty(acceleration.selection.videoEncoder) ||
          !["cuda", "cpu"].includes(acceleration.selection.mediaInferenceDevice)) {
        fail("checksums-provenance", "render acceleration manifest is malformed.", [accelerationArtifact.artifactId]);
      } else {
        const usableNvenc = Array.isArray(acceleration.ffmpeg?.usableNvencEncoders)
          ? acceleration.ffmpeg.usableNvencEncoders
          : [];
        const cudaUsable = acceleration.inference?.cudaUsable === true;
        const selectedNvenc = usableNvenc.includes(acceleration.selection.videoEncoder);
        const selectedCuda = acceleration.selection.mediaInferenceDevice === "cuda" && cudaUsable;
        const expectedMode = selectedNvenc || selectedCuda ? "gpu-preferred" : "cpu-fallback";
        if (acceleration.mode !== expectedMode) {
          fail("checksums-provenance", `acceleration mode must be derived from the selected, functionally probed paths as ${expectedMode}.`, [accelerationArtifact.artifactId]);
        }
        if (acceleration.selection.videoEncoder !== "libx264" && !selectedNvenc) {
          fail("checksums-provenance", "selected video encoder must be libx264 or an NVENC encoder that passed the recorded functional probe.", [accelerationArtifact.artifactId]);
        }
        if (acceleration.selection.mediaInferenceDevice === "cuda" && !cudaUsable) {
          fail("checksums-provenance", "selected CUDA inference device did not pass the recorded functional probe.", [accelerationArtifact.artifactId]);
        }
        if (acceleration.mode === "gpu-preferred" && acceleration.nvidia?.available !== true) {
          fail("checksums-provenance", "GPU-preferred render provenance does not prove a compatible GPU was detected.", [accelerationArtifact.artifactId]);
        }
      }
      if (acceleration.mode === "cpu-fallback" && !nonEmpty(acceleration.fallbackReason)) {
        fail("checksums-provenance", "CPU fallback requires a recorded capability or compatibility reason.", [accelerationArtifact.artifactId]);
      } else if ((acceleration.selection.videoEncoder === "libx264" ||
                  acceleration.selection.mediaInferenceDevice === "cpu") && !nonEmpty(acceleration.fallbackReason)) {
        fail("checksums-provenance", "Any partial CPU media fallback requires a recorded functional-probe reason.", [accelerationArtifact.artifactId]);
      }
    } catch (error) {
      fail("checksums-provenance", `render acceleration manifest is invalid JSON: ${error.message}`, [accelerationArtifact.artifactId]);
    }
  }
  for (const field of ["renderId", "renderer", "pipelineVersion", "command", "startedAt", "completedAt"]) {
    if (!nonEmpty(provenance.render[field])) fail("checksums-provenance", `provenance.render.${field} is required.`);
  }
  if (Number.isFinite(Date.parse(provenance.render.startedAt)) &&
      Number.isFinite(Date.parse(provenance.render.completedAt)) &&
      Date.parse(provenance.render.completedAt) < Date.parse(provenance.render.startedAt)) {
    fail("checksums-provenance", "render completedAt precedes startedAt.");
  }
}

const aggregate = new Map(CHECKS.map(([id]) => [id, []]));
if (!object(evidencePackage.reports)) {
  fail("artifact-completeness", "reports object is missing.");
} else {
  const extraReports = Object.keys(evidencePackage.reports).filter((name) => !REPORT_TYPES.includes(name));
  for (const name of extraReports) fail("artifact-completeness", `unknown deterministic report "${name}".`);

  for (const reportType of REPORT_TYPES) {
    const reference = evidencePackage.reports[reportType];
    const artifact = validateReference(reference, `reports.${reportType}`, "artifact-completeness");
    if (!artifact || !object(reference)) continue;
    if (reference.candidateId !== candidateId || reference.reportType !== reportType ||
        !["PASS", "FAIL"].includes(reference.status) || !Number.isFinite(Date.parse(reference.generatedAt))) {
      fail("artifact-completeness", `reports.${reportType} immutable metadata is invalid.`, [reference.artifactId]);
      continue;
    }
    const fullPath = artifactPath(artifact.artifactPath);
    if (!existsSync(fullPath)) continue;
    let report;
    try {
      report = JSON.parse(readFileSync(fullPath, "utf8"));
    } catch (error) {
      fail("artifact-completeness", `reports.${reportType} is invalid JSON: ${error.message}`, [reference.artifactId]);
      continue;
    }
    if (!object(report) || report.schemaVersion !== "1.0.0" || report.candidateId !== candidateId ||
        report.reportType !== reportType || report.status !== reference.status ||
        report.generatedAt !== reference.generatedAt) {
      fail("artifact-completeness", `reports.${reportType} envelope does not match its immutable reference.`, [reference.artifactId]);
      continue;
    }
    if (!object(report.generator) || !nonEmpty(report.generator.tool) ||
        !nonEmpty(report.generator.version) || !nonEmpty(report.generator.command) ||
        !Array.isArray(allowedGenerators[reportType]) ||
        !allowedGenerators[reportType].includes(report.generator.tool)) {
      fail(
        "checksums-provenance",
        `reports.${reportType} generator is not registered for this report type or lacks version/command provenance.`,
        [reference.artifactId],
      );
    }
    const reportInputIds = new Set();
    if (!Array.isArray(report.inputs) || report.inputs.length === 0) {
      fail("checksums-provenance", `reports.${reportType} has no checksum-bound inputs.`, [reference.artifactId]);
    } else {
      for (const input of report.inputs) {
        if (!object(input) || !SAFE_ID.test(input.artifactId ?? "") ||
            !/^[a-f0-9]{64}$/.test(input.sha256 ?? "")) {
          fail("checksums-provenance", `reports.${reportType} contains a malformed input reference.`, [reference.artifactId]);
          continue;
        }
        if (reportInputIds.has(input.artifactId)) {
          fail("checksums-provenance", `reports.${reportType} duplicates input "${input.artifactId}".`, [reference.artifactId]);
          continue;
        }
        reportInputIds.add(input.artifactId);
        const inputArtifact = artifacts.get(input.artifactId);
        if (!inputArtifact || inputArtifact.sha256 !== input.sha256) {
          fail(
            "checksums-provenance",
            `reports.${reportType} input "${input.artifactId}" does not match a canonical artifact checksum.`,
            [reference.artifactId, input.artifactId],
          );
        }
      }
    }
    if (reportType === "craftContractValidation") {
      const inputArtifacts = [...reportInputIds].map((id) => artifacts.get(id)).filter(Boolean);
      if (inputArtifacts.filter((artifact) => artifact.type === "storyboard").length !== 1) {
        fail("storyboard-craft-contract", "craft contract validation must bind exactly one storyboard artifact.", [reference.artifactId]);
      }
      if (inputArtifacts.filter((artifact) => artifact.type === "capture-manifest").length !== 1) {
        fail("capture-manifest-craft-contract", "craft contract validation must bind exactly one capture-manifest artifact.", [reference.artifactId]);
      }
      if (inputArtifacts.filter((artifact) => artifact.type === "capture-evidence").length !== 1) {
        fail("beat-timing-deltas", "craft contract validation must bind exactly one raw capture-evidence artifact.", [reference.artifactId]);
      }
      if (inputArtifacts.filter((artifact) => artifact.type === "raw-capture").length !== 1) {
        fail("capture-manifest-craft-contract", "craft contract validation must bind exactly one probed raw-capture artifact.", [reference.artifactId]);
      }
      const storyboard = oneArtifactOfType(inputArtifacts, "storyboard");
      const captureManifest = oneArtifactOfType(inputArtifacts, "capture-manifest");
      const captureEvidence = oneArtifactOfType(inputArtifacts, "capture-evidence");
      const rawCapture = oneArtifactOfType(inputArtifacts, "raw-capture");
      if (storyboard && captureManifest && captureEvidence && rawCapture) {
        if (rawCapture.artifactId !== provenance?.capture?.rawCapture?.artifactId) {
          fail("capture-manifest-craft-contract", "craft validation raw capture does not match immutable capture provenance.", [rawCapture.artifactId]);
        }
        runCanonicalValidator("validate-craft-contracts.mjs", [
          "--candidate-id", candidateId,
          "--storyboard", artifactPath(storyboard.artifactPath),
          "--storyboard-artifact-id", storyboard.artifactId,
          "--capture-manifest", artifactPath(captureManifest.artifactPath),
          "--capture-artifact-id", captureManifest.artifactId,
          "--capture-evidence", artifactPath(captureEvidence.artifactPath),
          "--capture-evidence-artifact-id", captureEvidence.artifactId,
          "--raw-capture", artifactPath(rawCapture.artifactPath),
          "--raw-capture-artifact-id", rawCapture.artifactId,
        ], ["storyboard-craft-contract", "capture-manifest-craft-contract", "beat-timing-deltas"], [
          reference.artifactId, storyboard.artifactId, captureManifest.artifactId, captureEvidence.artifactId, rawCapture.artifactId,
        ]);
      }
    }
    if (!Array.isArray(report.checks) || report.checks.length === 0 || !object(report.summary)) {
      fail("artifact-completeness", `reports.${reportType} has no deterministic checks/summary.`, [reference.artifactId]);
      continue;
    }
    const seen = new Set();
    let passed = 0;
    let failed = 0;
    for (const check of report.checks) {
      if (!object(check) || !CHECK_IDS.has(check.id) || typeof check.passed !== "boolean" ||
          !Array.isArray(check.evidenceArtifactIds) || check.evidenceArtifactIds.length === 0) {
        fail("artifact-completeness", `reports.${reportType} contains a malformed check.`, [reference.artifactId]);
        continue;
      }
      if (seen.has(check.id)) {
        fail("artifact-completeness", `reports.${reportType} duplicates check "${check.id}".`, [reference.artifactId]);
        continue;
      }
      seen.add(check.id);
      const evidenceIds = new Set([reference.artifactId]);
      for (const id of check.evidenceArtifactIds) {
        if (!artifacts.has(id)) {
          fail(check.id, `reports.${reportType} check references unknown artifact "${id}".`, [reference.artifactId]);
        } else {
          evidenceIds.add(id);
          if (!reportInputIds.has(id)) {
            fail(
              "checksums-provenance",
              `reports.${reportType} check evidence "${id}" is not checksum-bound in report.inputs.`,
              [reference.artifactId, id],
            );
          }
        }
      }
      if (reportType === "craftContractValidation") {
        const requiredType = check.id === "storyboard-craft-contract"
          ? "storyboard"
          : check.id === "capture-manifest-craft-contract"
            ? "capture-manifest"
            : check.id === "beat-timing-deltas"
              ? "capture-evidence"
              : null;
        if (!requiredType || !check.evidenceArtifactIds.some((id) => artifacts.get(id)?.type === requiredType)) {
          fail(check.id, `craft contract check must cite its checksum-bound ${requiredType ?? "canonical"} input.`, [reference.artifactId]);
        }
      }
      aggregate.get(check.id).push({ passed: check.passed, reportType, evidenceIds });
      if (check.passed) passed += 1;
      else failed += 1;
    }
    if (report.summary.total !== report.checks.length || report.summary.passed !== passed ||
        report.summary.failed !== failed || (report.status === "PASS") !== (failed === 0)) {
      fail("artifact-completeness", `reports.${reportType} status/summary does not match its checks.`, [reference.artifactId]);
    }
    if (reportType === "craftContractValidation" &&
        (seen.size !== 3 || !seen.has("storyboard-craft-contract") ||
         !seen.has("capture-manifest-craft-contract") || !seen.has("beat-timing-deltas"))) {
      fail("artifact-completeness", "craft contract validation must contain exactly storyboard, capture-manifest, and beat-timing checks.", [reference.artifactId]);
    }
    if (reportType === "craftContractValidation") {
      if (!Array.isArray(report.measurements) || report.measurements.length === 0) {
        fail("beat-timing-deltas", "craft contract validation has no per-beat timing measurements.", [reference.artifactId]);
      } else {
        for (const measurement of report.measurements) {
          if (!object(measurement) || !SAFE_ID.test(measurement.beatId ?? "") ||
              !["cursorLeadSeconds", "actionToResultSeconds", "resultToSpokenSeconds", "resultHoldToCutSeconds"]
                .every((field) => Number.isFinite(measurement[field]) && measurement[field] >= 0) ||
              !Array.isArray(measurement.evidenceArtifactIds) ||
              !measurement.evidenceArtifactIds.some((id) => artifacts.get(id)?.type === "capture-evidence")) {
            fail("beat-timing-deltas", "craft contract validation contains malformed or unbound timing measurements.", [reference.artifactId]);
          }
        }
      }
      if (!object(report.sourceGeometry) || !Number.isInteger(report.sourceGeometry.width) ||
          !Number.isInteger(report.sourceGeometry.height) || report.sourceGeometry.width < 1 ||
          report.sourceGeometry.height < 1 || report.sourceGeometry.probe !== "ffprobe" ||
          artifacts.get(report.sourceGeometry.rawCaptureArtifactId)?.type !== "raw-capture" ||
          !reportInputIds.has(report.sourceGeometry.rawCaptureArtifactId)) {
        fail("capture-manifest-craft-contract", "craft contract validation lacks ffprobe-derived geometry bound to its raw-capture input.", [reference.artifactId]);
      }
    }
  }
}

for (const [checkId] of CHECKS) {
  const occurrences = aggregate.get(checkId);
  if (occurrences.length === 0) {
    fail(checkId, `no deterministic report supplied the required "${checkId}" check.`);
    continue;
  }
  for (const occurrence of occurrences) {
    for (const id of occurrence.evidenceIds) checkEvidence.get(checkId).add(id);
    if (!occurrence.passed) fail(checkId, `${occurrence.reportType} reported failure.`, [...occurrence.evidenceIds]);
  }
}

const reportChecks = CHECKS.map(([id, subsystem]) => ({
  id,
  subsystem,
  passed: checkErrors.get(id).length === 0,
  evidenceArtifactIds: [...checkEvidence.get(id)].sort(),
}));
const failedChecks = reportChecks.filter((check) => !check.passed);
const failures = failedChecks.map((check, index) => ({
  id: `PVF-PREFLIGHT-${String(index + 1).padStart(3, "0")}`,
  checkId: check.id,
  subsystem: check.subsystem,
  severity: ["artifact-completeness", "checksums-provenance"].includes(check.id) ? "blocker" : "critical",
  expectedBehavior: `Deterministic preflight check "${check.id}" passes for the immutable candidate.`,
  observedBehavior: checkErrors.get(check.id).join(" "),
  evidenceArtifactIds: check.evidenceArtifactIds,
  concreteFix: `Correct the ${check.subsystem} source/report and generate a new immutable evidence package.`,
  validationCommand: `node "${process.argv[1]}" --evidence-package "${packageAbsolute}" --out "${resolve(outPath)}"`,
}));
const completedAt = new Date().toISOString();
const output = {
  schemaVersion: "1.0.0",
  reportId: `PVP-PREFLIGHT-${completedAt.replace(/\D/g, "")}`,
  candidateId,
  evidencePackage: {
    artifactPath: packageAbsolute,
    sha256: packageSha,
  },
  policyVersion: "1.0.0",
  startedAt,
  completedAt,
  checks: reportChecks,
  failures,
  summary: {
    total: CHECKS.length,
    passed: CHECKS.length - failedChecks.length,
    failed: failedChecks.length,
  },
  status: failedChecks.length === 0 ? "PASS" : "FAIL",
  readyForIndependentReview: failedChecks.length === 0,
};

mkdirSync(dirname(resolve(outPath)), { recursive: true });
writeFileSync(resolve(outPath), `${JSON.stringify(output, null, 2)}\n`, "utf8");
console.log(`Preflight report: ${resolve(outPath)}`);
if (failedChecks.length === 0) {
  console.log("PASS: immutable evidence package is ready for four independent reviews.");
} else {
  console.error(`FAIL: ${failedChecks.length} of ${CHECKS.length} preflight checks failed.`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}
