#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const expectedVersion = "1.1.0";
const failures = [];

function readJson(relativePath) {
  try {
    return JSON.parse(readFileSync(join(root, relativePath), "utf8"));
  } catch (error) {
    failures.push(`${relativePath}: invalid or unreadable JSON (${error.message})`);
    return {};
  }
}

function requireFiles(relativeRoot, expectedNames, { exact = false } = {}) {
  const fullRoot = join(root, relativeRoot);
  const actual = existsSync(fullRoot)
    ? readdirSync(fullRoot, { withFileTypes: true }).filter((entry) => entry.isFile()).map((entry) => entry.name)
    : [];
  for (const name of expectedNames) {
    if (!actual.includes(name)) failures.push(`${relativeRoot}/${name}: required file missing`);
  }
  if (exact) {
    for (const name of actual) {
      if (!expectedNames.includes(name)) failures.push(`${relativeRoot}/${name}: unregistered parallel or obsolete file`);
    }
  }
}

const claude = readJson(".claude-plugin/plugin.json");
const codex = readJson(".codex-plugin/plugin.json");
const cursor = readJson(".cursor-plugin/plugin.json");
const devin = readJson(".devin-plugin/plugin.json");
const qoder = readJson(".qoder-plugin/plugin.json");
for (const [name, manifest] of [
  ["Claude", claude],
  ["Codex", codex],
  ["Cursor", cursor],
  ["Devin", devin],
  ["Qoder", qoder],
]) {
  if (manifest.name !== "product-demo-studio") failures.push(`${name} manifest has wrong plugin name`);
  if (manifest.version !== expectedVersion) failures.push(`${name} manifest version must be ${expectedVersion}`);
}
if (new Set([claude.version, codex.version, cursor.version, devin.version, qoder.version]).size !== 1) {
  failures.push("host-native plugin manifest versions differ");
}

const agents = [
  "audio-captions-sync-reviewer.md",
  "automated-preflight.md",
  "capture-product-state-generator.md",
  "composition-render-generator.md",
  "episode-architect.md",
  "final-verifier.md",
  "narration-audio-generator.md",
  "release-arbiter.md",
  "remediation-agent.md",
  "screen-accuracy-compliance-reviewer.md",
  "script-storyboard-generator.md",
  "story-experience-reviewer.md",
  "technical-frame-integrity-reviewer.md",
];
requireFiles("agents", agents, { exact: true });
const readOnlyAgents = agents.filter((name) => {
  const source = readFileSync(join(root, "agents", name), "utf8");
  return /^readonly:\s*true\s*$/m.test(source);
});
if (readOnlyAgents.length !== 6) {
  failures.push(`agents: expected six readonly:true roles, found ${readOnlyAgents.length}`);
}
for (const name of readOnlyAgents) {
  const source = readFileSync(join(root, "agents", name), "utf8");
  const tools = /^tools:\s*(.+)$/m.exec(source)?.[1] ?? "";
  if (/(^|,\s*)Bash(\s*,|$)/.test(tools) || /(^|,\s*)(?:Edit|Write)(\s*,|$)/.test(tools)) {
    failures.push(`agents/${name}: read-only role exposes Bash, Edit, or Write`);
  }
}

requireFiles("schemas", [
  "delivery-spec.schema.json",
  "deterministic-report.schema.json",
  "evidence-package.schema.json",
  "execution-host-trust.schema.json",
  "execution-receipt.schema.json",
  "final-verification.schema.json",
  "preflight-report.schema.json",
  "release-evidence.schema.json",
  "release-decision.schema.json",
  "remediation-assignment.schema.json",
  "review-report.schema.json",
  "video-finding.schema.json",
]);
requireFiles("policy", [".gitattributes", "host-parity.json", "product-video-policy.json"], { exact: true });
requireFiles("scripts", [
  "check-evidence-gate.mjs",
  "preflight.mjs",
  "validate-execution-receipt.mjs",
  "validate-host-parity.mjs",
  "validate-final-verification.mjs",
  "validate-release-decision.mjs",
  "validate-remotion-rules.mjs",
  "validate-remediation-assignment.mjs",
  "validate-review-report.mjs",
]);

const policy = readJson("policy/product-video-policy.json");
const expectedCompleteChecks = [
  "accuracy",
  "compliance",
  "privacy",
  "technicalIntegrity",
  "browserPlayback",
  "claims",
  "checksums",
  "provenance",
  "captions",
  "synchronization",
  "visualIntegrity",
];
if (policy.capabilityVersion !== expectedVersion) failures.push("policy capabilityVersion differs from package version");
if (JSON.stringify(policy.releasePolicy?.completePassChecks) !== JSON.stringify(expectedCompleteChecks)) {
  failures.push("policy completePassChecks differ from the canonical eleven-check release contract");
}
if (policy.permissions?.executionEnforcement?.instructionOnlyIsolationIsSufficient !== false ||
    policy.permissions?.executionEnforcement?.unsupportedHostDecision !== "PIPELINE_BLOCKED" ||
    policy.permissions?.executionEnforcement?.executionReceiptsMustBeHostSigned !== true ||
    policy.permissions?.executionEnforcement?.agentsMayAuthorExecutionReceipts !== false ||
    policy.permissions?.executionEnforcement?.trustedHostRegistryEnvironmentVariable !==
      "AGENTHUB_EXECUTION_HOST_TRUST_CONFIG") {
  failures.push("policy does not fail closed when host-enforced read-only isolation is unavailable");
}
if (policy.connectorPolicy?.descriptEditCreatesNewCandidate !== true ||
    policy.connectorPolicy?.unchecksumableDescriptOutputDecision !== "PIPELINE_BLOCKED") {
  failures.push("policy does not invalidate Descript edits or block unchecksumable outputs");
}
const hostParityPolicy = readJson("policy/host-parity.json");
if (hostParityPolicy.validationScope?.defaultMode !== "STATIC_INVENTORY_ONLY" ||
    hostParityPolicy.validationScope?.staticValidationMayClaimLiveParity !== false ||
    hostParityPolicy.validationScope?.liveParityRequiresDeploymentReport !== true) {
  failures.push("host parity policy does not distinguish static inventory from live deployment evidence");
}

const requiredText = [
  ["README.md", "four independent"],
  ["skills/product-demo-studio/SKILL.md", "Release Arbiter"],
  ["skills/product-demo-studio-qa/SKILL.md", "schemas/video-finding.schema.json"],
  ["skills/product-demo-studio/references/product-pipeline-compatibility.md", "Product-pipeline compatibility"],
  ["policy/product-video-policy.json", '"humanPublicationAttestationSeparate": true'],
];
for (const [relativePath, marker] of requiredText) {
  const fullPath = join(root, relativePath);
  if (!existsSync(fullPath) || !readFileSync(fullPath, "utf8").includes(marker)) {
    failures.push(`${relativePath}: missing required marker "${marker}"`);
  }
}

const obsoleteNames = new Set([
  "audio-reviewer.md",
  "product-truth-reviewer.md",
  "story-reviewer.md",
  "technical-reviewer.md",
  "visual-reviewer.md",
]);
for (const name of obsoleteNames) {
  if (existsSync(join(root, "agents", name))) failures.push(`agents/${name}: obsolete five-role reviewer remains active`);
}

const remotionValidation = spawnSync(process.execPath, [join(root, "scripts", "validate-remotion-rules.mjs")], {
  encoding: "utf8",
});
if (remotionValidation.status !== 0) {
  failures.push(`Remotion rule provenance validation failed: ${(remotionValidation.stderr || remotionValidation.stdout).trim()}`);
}

const hostParityValidation = spawnSync(process.execPath, [join(root, "scripts", "validate-host-parity.mjs")], {
  encoding: "utf8",
});
if (hostParityValidation.status !== 0) {
  failures.push(`Host parity validation failed: ${(hostParityValidation.stderr || hostParityValidation.stdout).trim()}`);
} else {
  const output = `${hostParityValidation.stdout}\n${hostParityValidation.stderr}`;
  if (!output.includes("PASS (STATIC)") || !output.includes("does not prove live deployment")) {
    failures.push("default host parity validation does not identify itself as static-only");
  }
}
const missingLiveParityValidation = spawnSync(
  process.execPath,
  [join(root, "scripts", "validate-host-parity.mjs"), "--live-deployment-report", join(root, "missing-live-report.json")],
  { encoding: "utf8" },
);
if (missingLiveParityValidation.status === 0) {
  failures.push("host parity validation accepts a missing live deployment report");
}

const technicalChecksSource = readFileSync(join(root, "scripts", "technical-checks.mjs"), "utf8");
for (const [label, pattern] of [
  ["black-frame", /report\.checks\.blackFrames\s*=\s*\{[\s\S]*?status:\s*status\s*===\s*0\s*\?\s*"ok"\s*:\s*"error"/],
  ["freeze-frame", /report\.checks\.freezeFrames\s*=\s*\{[\s\S]*?status:\s*status\s*===\s*0\s*\?\s*"ok"\s*:\s*"error"/],
  ["silence", /report\.checks\.silence\s*=\s*\{[\s\S]*?status:\s*status\s*===\s*0\s*\?\s*"ok"\s*:\s*"error"/],
  ["clipping", /report\.checks\.clipping\s*=\s*\{[\s\S]*?status:\s*status\s*===\s*0\s*\?\s*"ok"\s*:\s*"error"/],
  ["loudness", /status\s*!==\s*0[\s\S]*?report\.checks\.loudness\s*=\s*\{[\s\S]*?status:\s*"error"/],
]) {
  if (!pattern.test(technicalChecksSource)) {
    failures.push(`technical checks do not fail closed when FFmpeg ${label} analysis exits nonzero`);
  }
}

const narrationSource = readFileSync(join(root, "scripts", "generate-narration.mjs"), "utf8");
if (!/env:\s*\{\s*\.\.\.process\.env,\s*ELEVENLABS_API_KEY:\s*apiKey\s*\}/.test(narrationSource)) {
  failures.push("ElevenLabs custom API-key environment is not securely mapped to the canonical child variable");
}

const videoCliPath = join(root, "scripts", "video-cli.mjs");
const orchestration = spawnSync(process.execPath, [videoCliPath, "all", "--repo", root], {
  encoding: "utf8",
});
const orchestrationOutput = `${orchestration.stdout}\n${orchestration.stderr}`;
if (orchestration.status !== 2) {
  failures.push('video-cli "all" must remain nonzero guidance rather than a release gate');
}
let previousMarkerIndex = -1;
for (const marker of [
  "render-candidate",
  "evidence-package",
  "preflight",
  "review",
  "arbitrate",
  "final-verifier",
  "signed-human-evidence",
  "package",
]) {
  const markerIndex = orchestrationOutput.indexOf(marker, previousMarkerIndex + 1);
  if (markerIndex === -1) {
    failures.push(`video-cli orchestration is missing ordered stage ${marker}`);
    break;
  }
  previousMarkerIndex = markerIndex;
}
if (!orchestrationOutput.includes("No render or edit is allowed after verification or approval")) {
  failures.push("video-cli orchestration does not explicitly prohibit post-approval rerendering");
}
const deprecatedFinalRender = spawnSync(process.execPath, [videoCliPath, "render-final", "--repo", root], {
  encoding: "utf8",
});
if (deprecatedFinalRender.status !== 2 ||
    !`${deprecatedFinalRender.stdout}\n${deprecatedFinalRender.stderr}`.includes("post-approval rerender")) {
  failures.push('video-cli "render-final" does not fail closed with migration guidance');
}

if (failures.length > 0) {
  console.error(`Product Demo Studio package validation FAILED (${failures.length}):`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`PASS: Product Demo Studio ${expectedVersion} has one canonical agent, schema, and validation surface.`);
