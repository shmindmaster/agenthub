#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const expectedVersion = "1.7.2";
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
const qoder = readJson(".qoder-plugin/plugin.json");
const portable = readJson("plugin.json");
for (const [name, manifest] of [
  ["Claude", claude],
  ["Codex", codex],
  ["Cursor", cursor],
  ["Qoder", qoder],
]) {
  if (manifest.name !== "product-demo-studio") failures.push(`${name} manifest has wrong plugin name`);
  if (manifest.version !== expectedVersion) failures.push(`${name} manifest version must be ${expectedVersion}`);
}
if (new Set([claude.version, codex.version, cursor.version, qoder.version]).size !== 1) {
  failures.push("host-native plugin manifest versions differ");
}
if (portable.name !== "product-demo-studio") failures.push("portable Copilot/Antigravity manifest has wrong plugin name");
if (!Object.keys(portable).every((key) => ["name", "description"].includes(key))) {
  failures.push("portable manifest exceeds the Antigravity schema");
}

const agents = [
  "audio-captions-sync-reviewer.agent.md",
  "automated-preflight.agent.md",
  "capture-product-state-generator.agent.md",
  "composition-render-generator.agent.md",
  "episode-architect.agent.md",
  "final-verifier.agent.md",
  "narration-audio-generator.agent.md",
  "release-arbiter.agent.md",
  "remediation-agent.agent.md",
  "screen-accuracy-compliance-reviewer.agent.md",
  "script-storyboard-generator.agent.md",
  "story-experience-reviewer.agent.md",
  "technical-frame-integrity-reviewer.agent.md",
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
  "calibration-review-result.schema.json",
  "delivery-spec.schema.json",
  "deterministic-report.schema.json",
  "evidence-package.schema.json",
  "execution-receipt.schema.json",
  "final-verification.schema.json",
  "interactive-deep-dive.schema.json",
  "media-acceleration.schema.json",
  "preflight-report.schema.json",
  "review-delivery.schema.json",
  "release-evidence.schema.json",
  "release-decision.schema.json",
  "remediation-assignment.schema.json",
  "reviewer-calibration.schema.json",
  "review-report.schema.json",
  "video-finding.schema.json",
]);
requireFiles(
  "policy",
  [".gitattributes", "host-manifests.json", "host-parity.json", "product-video-policy.json"],
  { exact: true },
);
// The router is the cheap entry point; the commands are the only user-invocable
// surface. Both are required — a host that loads the pipeline skill directly
// pays an order of magnitude more context to answer a routing question.
requireFiles("skills/product-demo", ["SKILL.md"], { exact: true });
requireFiles("commands", ["demo-assess.md", "demo-calibrate.md", "demo-video.md"], { exact: true });
requireFiles("docs", ["EXECUTION.md", "USING-AGAINST-ANY-PRODUCT.md"], { exact: true });
requireFiles("scripts", [
  "build-craft-fixtures.mjs",
  "build-worthiness-fixtures.mjs",
  "check-evidence-gate.mjs",
  "detect-media-acceleration.mjs",
  "serve-worthiness-fixtures.mjs",
  "validate-host-manifests.mjs",
  "verify-fixtures.mjs",
  "package-review.mjs",
  "preflight.mjs",
  "storyboard.example.json",
  "validate-capture-manifest.mjs",
  "validate-craft-contracts.mjs",
  "validate-execution-receipt.mjs",
  "validate-host-parity.mjs",
  "validate-final-verification.mjs",
  "validate-interactive-deep-dive.mjs",
  "validate-release-decision.mjs",
  "validate-remediation-assignment.mjs",
  "validate-reviewer-calibration.mjs",
  "validate-review-report.mjs",
  "validate-review-delivery.mjs",
  "validate-storyboard.mjs",
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
    policy.permissions?.executionEnforcement?.hostNativeReadOnlyRoleRequired !== true ||
    policy.permissions?.executionEnforcement?.executionReceiptsRecordDeclaredContext !== true ||
    policy.permissions?.executionEnforcement?.executionReceiptIsSecurityAttestation !== false ||
    policy.permissions?.executionEnforcement?.agentsMayAuthorExecutionReceipts !== true) {
  failures.push("policy does not fail closed when host-enforced read-only isolation is unavailable");
}
if (policy.connectorPolicy?.descriptEditCreatesNewCandidate !== true ||
    policy.connectorPolicy?.unchecksumableDescriptOutputDecision !== "PIPELINE_BLOCKED") {
  failures.push("policy does not invalidate Descript edits or block unchecksumable outputs");
}
if (policy.reviewDeliveryPolicy?.agentHubRegistry !== "registry/product-video-delivery.json" ||
    policy.reviewDeliveryPolicy?.classification !== "review-only" ||
    policy.reviewDeliveryPolicy?.requiresArbiterPass !== true ||
    policy.reviewDeliveryPolicy?.requiresFinalVerifierPass !== true ||
    policy.reviewDeliveryPolicy?.immutableCandidateDirectory !== true ||
    policy.reviewDeliveryPolicy?.overwriteAllowed !== false ||
    policy.reviewDeliveryPolicy?.firstHumanTouchpoint !== "final-presentation" ||
    policy.reviewDeliveryPolicy?.automatedAcceptanceRequired !== true) {
  failures.push("policy does not enforce immutable automated acceptance before final presentation");
}
if (policy.captureQualityPolicy?.guidedScreencastRequired !== true ||
    policy.captureQualityPolicy?.pageOnlyOrNativeFullscreenPreferred !== true ||
    policy.captureQualityPolicy?.extraneousBrowserOrOsChromeAllowedOnlyAsEvidence !== true ||
    policy.captureQualityPolicy?.minimumPlannedActiveRegionCoverage !== 0.5 ||
    policy.captureQualityPolicy?.minimumCaptureDeviceScaleFactor !== 2 ||
    policy.captureQualityPolicy?.minimumEffectiveDeliveryPixelDensity !== 1 ||
    policy.captureQualityPolicy?.pointerMoveMilliseconds?.minimum !== 400 ||
    policy.captureQualityPolicy?.pointerMoveMilliseconds?.maximum !== 600 ||
    policy.captureQualityPolicy?.clickSettleMilliseconds !== 250 ||
    policy.captureQualityPolicy?.clickHoldMilliseconds !== 500 ||
    policy.captureQualityPolicy?.clickPulseMilliseconds?.minimum !== 300 ||
    policy.captureQualityPolicy?.clickPulseMilliseconds?.maximum !== 400 ||
    policy.captureQualityPolicy?.clickPulseBrandColorRequired !== true ||
    policy.captureQualityPolicy?.clickPulseSemiTransparent !== true ||
    policy.captureQualityPolicy?.smallDeliveryCursorScale?.minimum !== 1.5 ||
    policy.captureQualityPolicy?.smallDeliveryCursorScale?.maximum !== 2 ||
    policy.captureQualityPolicy?.zoomTransitionMilliseconds?.minimum !== 300 ||
    policy.captureQualityPolicy?.zoomTransitionMilliseconds?.maximum !== 500 ||
    policy.captureQualityPolicy?.maximumZoomChangesPerBeat !== 1 ||
    policy.captureQualityPolicy?.uiCameraDriftAllowed !== false ||
    policy.captureQualityPolicy?.boundedWaitSpeedMultiplier?.minimum !== 4 ||
    policy.captureQualityPolicy?.boundedWaitSpeedMultiplier?.maximum !== 8 ||
    policy.captureQualityPolicy?.textEntrySpeedMultiplier?.minimum !== 3 ||
    policy.captureQualityPolicy?.textEntrySpeedMultiplier?.maximum !== 4 ||
    policy.captureQualityPolicy?.annotationWordsPerSecond !== 2.5 ||
    policy.captureQualityPolicy?.annotationReadingBufferSeconds !== 0.5 ||
    policy.captureQualityPolicy?.truthfulLatencyTreatmentRequired !== true ||
    policy.captureQualityPolicy?.realProductActionAndStateTransitionRequired !== true ||
    policy.captureQualityPolicy?.visibleClickCueRequired !== true ||
    policy.captureQualityPolicy?.resultVisibleBeforeSpokenResult !== true) {
  failures.push("policy does not enforce screen-space utilization and guided-screencast choreography");
}
if (policy.hardwareAccelerationPolicy?.capabilityDetectionRequired !== true ||
    policy.hardwareAccelerationPolicy?.compatibleGpuPreferred !== true ||
    policy.hardwareAccelerationPolicy?.agentReasoningRequiresLocalGpu !== false ||
    policy.hardwareAccelerationPolicy?.cpuFallbackAllowed !== true ||
    policy.hardwareAccelerationPolicy?.cpuFallbackReasonRequired !== true ||
    policy.hardwareAccelerationPolicy?.outputEquivalenceValidationRequired !== true ||
    policy.hardwareAccelerationPolicy?.accelerationManifestRequiredInRenderProvenance !== true) {
  failures.push("policy does not prefer compatible media acceleration with deterministic, documented CPU fallback");
}
if (policy.reviewIndependencePolicy?.generatorMayReviewOwnOutput !== false ||
    policy.reviewIndependencePolicy?.generatorReasoningPassedToReviewer !== false ||
    policy.reviewIndependencePolicy?.reviewerLoadsCanonicalRubricDirectly !== true ||
    policy.reviewIndependencePolicy?.rubricAndOverlayContentHashesRequired !== true ||
    policy.reviewIndependencePolicy?.evidenceRequiredForPassAndFail !== true ||
    policy.reviewIndependencePolicy?.unevidencedCriterionDecision !== "PIPELINE_BLOCKED" ||
    policy.autonomyPolicy?.humanInteractionBeforeFinalPresentationAllowed !== false ||
    policy.autonomyPolicy?.acceptanceIsAutomated !== true ||
    policy.autonomyPolicy?.continuousEvaluationAndRemediationRequired !== true ||
    policy.autonomyPolicy?.terminalHumanTouchpoint !== "final-presentation" ||
    policy.remediationCyclePolicy?.fixedAttemptLimit !== false ||
    policy.remediationCyclePolicy?.continueUntilPassOrEvidenceBackedBlocker !== true ||
    policy.verticalRubricOverlayPolicy?.mayRemoveBaseCriteria !== false ||
    policy.verticalRubricOverlayPolicy?.mayWeakenBaseThresholds !== false ||
    policy.calibrationPolicy?.knownBadAndCleanPassRequired !== true ||
    policy.calibrationPolicy?.missingOrFailedCalibrationDecision !== "PIPELINE_BLOCKED" ||
    policy.seededRuntimePolicy?.liveSeededEnvironmentRequiredForWorthinessAssessment !== true ||
    policy.narrationTimingPolicy?.shortestStreamTruncationAllowed !== false) {
  failures.push("policy does not enforce reviewer independence, calibration, autonomous refinement, seeded-runtime evidence, and narration timing");
}
if (policy.permissions?.finalVerifier?.mandatoryTerminalGate !== true ||
    policy.permissions?.finalVerifier?.runsAfterArbiterPass !== true ||
    policy.releasePolicy?.terminalIndependentReview?.required !== true ||
    policy.releasePolicy?.terminalIndependentReview?.role !== "final-verifier" ||
    policy.releasePolicy?.terminalIndependentReview?.runsAfter !== "arbiter-pass" ||
    policy.releasePolicy?.terminalIndependentReview?.freshReadOnlyContextRequired !== true ||
    policy.releasePolicy?.terminalIndependentReview?.mustBindExactFinalCandidate !== true ||
    policy.releasePolicy?.terminalIndependentReview?.publicationPackagingRequiresPass !== true ||
    policy.releasePolicy?.terminalIndependentReview?.failureDecision !== "PIPELINE_BLOCKED" ||
    policy.rerunPolicy?.freshFinalIndependentReviewAfterEveryArbiterPass !== true) {
  failures.push("policy does not require the terminal independent reviewer/verifier after arbiter PASS");
}
const hostParityPolicy = readJson("policy/host-parity.json");
if (hostParityPolicy.validationScope?.defaultMode !== "STATIC_INVENTORY_ONLY" ||
    hostParityPolicy.validationScope?.staticValidationMayClaimLiveParity !== false ||
    hostParityPolicy.validationScope?.liveParityRequiresDeploymentReport !== true) {
  failures.push("host parity policy does not distinguish static inventory from live deployment evidence");
}

const requiredText = [
  ["README.md", "four independent"],
  ["README.md", "GPU-first media work"],
  ["skills/product-demo-studio/SKILL.md", "Release Arbiter"],
  ["skills/product-demo-studio/SKILL.md", "first human touchpoint is the final presentation"],
  ["skills/product-demo-studio/SKILL.md", "detect-media-acceleration.mjs"],
  ["skills/product-demo-studio-qa/SKILL.md", "schemas/video-finding.schema.json"],
  ["agents/final-verifier.agent.md", "mandatory terminal independent reviewer and verifier"],
  ["skills/product-demo-studio-qa/SKILL.md", "mandatory final independent review and verification"],
  ["skills/product-demo-studio/SKILL.md", "private review-delivery lane"],
  ["skills/product-demo-studio-capture/SKILL.md", "plannedActiveRegionCoverage"],
  ["skills/product-demo-studio-capture/SKILL.md", "deliveredCrop"],
  ["skills/product-demo-studio-narration/SKILL.md", "pointer lead → real action"],
  ["agents/script-storyboard-generator.agent.md", "structured `interaction` contract"],
  ["skills/product-demo-studio/references/interactive-product-deep-dives.md", "Rejected absolutes"],
  ["skills/product-demo-studio/references/interactive-product-deep-dives.md", "DOM record/replay systems such as rrweb"],
  ["skills/product-demo-studio/references/repository-native-capture-compositor-patterns.md", "Treat CDP screencast frames as variable-rate"],
  ["skills/product-demo-studio/references/repository-native-capture-compositor-patterns.md", "A compositor smoke pass is not release"],
  ["skills/product-demo-studio/references/reviewer-calibration.md", "known-bad fixture passes"],
  ["scripts/validate-reviewer-calibration.mjs", "derived verdict"],
  ["skills/product-demo-studio/references/product-pipeline-compatibility.md", "Product-pipeline compatibility"],
  ["policy/product-video-policy.json", '"terminalHumanTouchpoint": "final-presentation"'],
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

const hostManifestValidation = spawnSync(process.execPath, [join(root, "scripts", "validate-host-manifests.mjs")], {
  encoding: "utf8",
});
if (hostManifestValidation.status !== 0) {
  failures.push(
    `Host manifest validation failed: ${(hostManifestValidation.stderr || hostManifestValidation.stdout).trim()}`,
  );
}

// Fixture sources must be present even though the rendered masters are
// gitignored. Calibration rebuilds the masters; it cannot rebuild the catalogs,
// the expected-readiness sheets, or the craft stills.
requireFiles("fixtures/craft", ["catalog.json"]);
requireFiles("fixtures/worthiness", [
  "catalog.json",
  "clean-pass.expected-readiness.json",
  "dead-wait.expected-readiness.json",
  "illegible.expected-readiness.json",
  "no-hero.expected-readiness.json",
  "unstable.expected-readiness.json",
]);
requireFiles("fixtures/craft/_stills", [
  "s1_before.png",
  "s2_working.png",
  "s3_hero.png",
  "s4_guardrail.png",
  "s5_hero_b.png",
  "s6_hero_c.png",
  "s7_endcard.png",
]);

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
  "package-review",
  "package",
]) {
  const markerIndex = orchestrationOutput.indexOf(marker, previousMarkerIndex + 1);
  if (markerIndex === -1) {
    failures.push(`video-cli orchestration is missing ordered stage ${marker}`);
    break;
  }
  previousMarkerIndex = markerIndex;
}
if (!orchestrationOutput.includes("No render or edit is allowed after verification")) {
  failures.push("video-cli orchestration does not explicitly prohibit post-verification rerendering");
}
const deprecatedFinalRender = spawnSync(process.execPath, [videoCliPath, "render-final", "--repo", root], {
  encoding: "utf8",
});
if (deprecatedFinalRender.status !== 2 ||
    !`${deprecatedFinalRender.stdout}\n${deprecatedFinalRender.stderr}`.includes("post-verification rerender")) {
  failures.push('video-cli "render-final" does not fail closed with migration guidance');
}

if (failures.length > 0) {
  console.error(`Product Demo Studio package validation FAILED (${failures.length}):`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`PASS: Product Demo Studio ${expectedVersion} has one canonical agent, schema, and validation surface.`);
