#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};

const pluginRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(pluginRoot, "..", "..");
const parityPath = join(pluginRoot, "policy", "host-parity.json");
const productPolicyPath = join(pluginRoot, "policy", "product-video-policy.json");
const registryPath = join(repositoryRoot, "registry", "capabilities.json");
const liveDeploymentReportPath = flag("--live-deployment-report");
const failures = [];

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    failures.push(`${label} is invalid or unreadable: ${error.message}`);
    return {};
  }
}

if (!existsSync(registryPath)) {
  console.error(`AgentHub capability registry is unavailable: ${registryPath}`);
  process.exit(1);
}
if (!existsSync(parityPath)) {
  console.error(`Product-video host parity policy is unavailable: ${parityPath}`);
  process.exit(1);
}

const parity = readJson(parityPath, "host parity policy");
const productPolicy = readJson(productPolicyPath, "product video policy");
const registry = readJson(registryPath, "AgentHub capability registry");
const capability = registry.capabilities?.find((entry) => entry.id === "product-demo-studio");
if (!capability) failures.push("canonical capability registration is missing");

const actualHosts = (capability?.hostMappings ?? []).map((entry) => entry.hostId).sort();
const expectedHosts = [...(parity.mappedHosts ?? [])].sort();
if (JSON.stringify(actualHosts) !== JSON.stringify(expectedHosts)) {
  failures.push("host parity inventory differs from registry capability mappings");
}
const eligible = new Set(parity.conditionallyEligibleReviewHosts ?? []);
for (const host of eligible) {
  if (!expectedHosts.includes(host)) failures.push(`conditionally eligible host ${host} is not mapped`);
}
if (parity.capabilityVersion !== "1.8.4" ||
    parity.equivalentContract?.unsupportedIsolationDecision !== "PIPELINE_BLOCKED" ||
    parity.executionRule?.liveRunMustRecordNativeReadOnlyEnforcement !== true ||
    parity.executionRule?.shellFreeReadOnlyReviewerAllowed !== true ||
    parity.executionRule?.hostPostValidatorRequired !== true ||
    parity.executionRule?.promptOnlyOrBroadWriteContextMayRelease !== false ||
    parity.executionRule?.cursorDispatchAllowed !== true ||
    parity.validationScope?.defaultMode !== "STATIC_INVENTORY_ONLY" ||
    parity.validationScope?.staticValidationMayClaimLiveParity !== false ||
    parity.validationScope?.liveParityRequiresDeploymentReport !== true) {
  failures.push("host parity policy does not fail closed, distinguish static/live evidence, or enable reauthorized Cursor dispatch");
}
if (parity.executionRule?.agentAuthoredExecutionReceiptAllowed !==
      productPolicy.permissions?.executionEnforcement?.agentsMayAuthorExecutionReceipts ||
    productPolicy.permissions?.executionEnforcement?.executionReceiptIsSecurityAttestation !== false) {
  failures.push("host parity and canonical policy disagree on operational execution-receipt semantics");
}

const contractPaths = [
  parity.equivalentContract?.canonicalPolicy,
  parity.equivalentContract?.findingSchema,
  parity.equivalentContract?.reviewSchema,
  parity.equivalentContract?.reviewerCalibrationSchema,
  parity.equivalentContract?.calibrationReviewResultSchema,
  parity.equivalentContract?.mediaAccelerationSchema,
    parity.equivalentContract?.decisionSchema,
    parity.equivalentContract?.finalVerificationSchema,
    parity.equivalentContract?.executionReceiptSchema,
    parity.equivalentContract?.releaseEvidenceSchema,
    parity.equivalentContract?.reviewDeliverySchema,
    parity.equivalentContract?.interactiveDeepDiveSchema,
];
for (const relativePath of contractPaths) {
  if (!relativePath || !existsSync(join(pluginRoot, relativePath))) {
    failures.push(`equivalent contract file is unavailable: ${relativePath ?? "<missing>"}`);
  }
}

const contractHash = createHash("sha256");
for (const relativePath of [...contractPaths].filter(Boolean).sort()) {
  const fullPath = join(pluginRoot, relativePath);
  if (!existsSync(fullPath)) continue;
  contractHash.update(relativePath.replaceAll("\\", "/"));
  contractHash.update("\0");
  contractHash.update(readFileSync(fullPath));
  contractHash.update("\0");
}
const canonicalContractSha256 = contractHash.digest("hex");

if (liveDeploymentReportPath) {
  if (!existsSync(liveDeploymentReportPath)) {
    failures.push(`live deployment report is unavailable: ${liveDeploymentReportPath}`);
  } else {
    const report = readJson(liveDeploymentReportPath, "live deployment report");
    if (report.schemaVersion !== parity.liveDeploymentReportContract?.schemaVersion ||
        report.capabilityId !== parity.capabilityId ||
        report.capabilityVersion !== parity.capabilityVersion) {
      failures.push("live deployment report identity/version differs from the host parity policy");
    }
    if (report.canonicalContractSha256 !== canonicalContractSha256) {
      failures.push("live deployment report does not reference the current canonical contract bytes");
    }
    if (!report.generatedAt || Number.isNaN(Date.parse(report.generatedAt))) {
      failures.push("live deployment report generatedAt must be a valid timestamp");
    }

    const rows = Array.isArray(report.hosts) ? report.hosts : [];
    const reportedHosts = rows.map((row) => row?.hostId).sort();
    if (JSON.stringify(reportedHosts) !== JSON.stringify(expectedHosts)) {
      failures.push("live deployment report must contain exactly one row for every mapped host");
    }
    const seen = new Set();
    for (const row of rows) {
      const hostId = row?.hostId;
      if (!hostId || seen.has(hostId)) {
        failures.push(`live deployment report contains a missing or duplicate hostId: ${hostId ?? "<missing>"}`);
        continue;
      }
      seen.add(hostId);
      if (row.deployedVersion !== parity.capabilityVersion ||
          row.contractSha256 !== canonicalContractSha256 ||
          row.deploymentStatus !== "DEPLOYED") {
        failures.push(`${hostId}: deployed version/contract/status does not match the canonical capability`);
      }
      if (!Array.isArray(row.deploymentEvidence) ||
          row.deploymentEvidence.length === 0 ||
          row.deploymentEvidence.some((entry) => typeof entry !== "string" || entry.trim() === "")) {
        failures.push(`${hostId}: deploymentEvidence must contain at least one evidence reference`);
      }
      if (eligible.has(hostId)) {
        if (row.nativeReadOnlyEnforcement?.status !== "PASS" ||
            row.smokeTest?.status !== "PASS") {
          failures.push(`${hostId}: live review parity requires passing native read-only enforcement and smoke evidence`);
        }
      } else if (row.releaseEligibility !== "PIPELINE_BLOCKED") {
        failures.push(`${hostId}: a host without verified review isolation must remain PIPELINE_BLOCKED`);
      }
      for (const [label, evidence] of [
        ["nativeReadOnlyEnforcement", row.nativeReadOnlyEnforcement?.evidence],
        ["smokeTest", row.smokeTest?.evidence],
      ]) {
        if (!Array.isArray(evidence) || evidence.length === 0 ||
            evidence.some((entry) => typeof entry !== "string" || entry.trim() === "")) {
          failures.push(`${hostId}: ${label}.evidence must contain at least one evidence reference`);
        }
      }
      if (hostId === "cursor" && row.dispatchAttempted !== true) {
        failures.push("cursor: live report must prove a native smoke dispatch after owner reauthorization");
      }
    }
  }
}

if (failures.length > 0) {
  console.error(`Product-video host parity FAILED (${failures.length}):`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

if (!liveDeploymentReportPath) {
  console.log(
    `PASS (STATIC): ${actualHosts.length} registry mappings reference the current versioned contract inventory. ` +
      "This validates source configuration only; it does not prove live deployment, native isolation, " +
      "smoke-test behavior, or cross-host runtime parity. Supply --live-deployment-report <path> for that gate.",
  );
} else {
  console.log(
    `PASS (LIVE REPORT): ${actualHosts.length} mapped hosts have current deployment, contract, enforcement, ` +
      "and smoke evidence in the supplied report.",
  );
}
