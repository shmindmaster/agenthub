#!/usr/bin/env node
// Validate normalized demo-worthiness sheets before committing an episode to master production.
// Usage: node validate-demo-readiness.mjs <path-to-readiness.json>
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
let manifestPath;
let targetRevision;
let expectedHandoffPath;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--target-revision") targetRevision = args[++i];
  else if (args[i] === "--expected-handoff-path") expectedHandoffPath = args[++i];
  else if (!manifestPath) manifestPath = args[i];
  else {
    console.error(`Unknown argument: ${args[i]}`);
    process.exit(1);
  }
}
if (!manifestPath) {
  console.error("Usage: node validate-demo-readiness.mjs <path-to-readiness.json> [--target-revision <revision>] [--expected-handoff-path <path>]");
  process.exit(1);
}

const CRITERIA = [
  "single-clear-outcome",
  "fast-to-value",
  "clean-believable-states",
  "visual-stability",
  "legibility",
  "bounded-feedback-rich-waits",
  "discoverable-primary-action",
  "deterministic-resettable",
  "visible-guardrail",
  "hero-moment-exists",
  "polish-baseline",
];
const VERDICTS = new Set(["PASS", "CONDITIONAL", "FAIL"]);
const CLASSIFICATIONS = new Set(["capture-fixable", "product-fix-required"]);
const SEVERITIES = new Set(["blocks", "degrades", "minor", "blocks-video", "degrades-video"]);

const parsed = JSON.parse(readFileSync(manifestPath, "utf8"));
const episodes = Array.isArray(parsed) ? parsed : (parsed.episodes ?? [parsed]);
let errors = 0;

function present(value) {
  return typeof value === "string" ? value.trim().length > 0 : value !== undefined && value !== null;
}

for (const [episodeIndex, episode] of episodes.entries()) {
  const label = episode.episodeId ?? `#${episodeIndex}`;
  const fail = (message) => {
    console.error(`[error] ${label}: ${message}`);
    errors++;
  };

  for (const field of ["episodeId", "workflow", "assessedEnvironment", "assessedRevision", "persona", "verdict"]) {
    if (!present(episode[field])) fail(`missing required field "${field}".`);
  }
  if (!Array.isArray(episode.permissions) || episode.permissions.length === 0 || episode.permissions.some((value) => !present(value))) {
    fail('"permissions" must contain at least one explicit role or permission.');
  }

  const upstream = episode.productExperienceHandoff;
  if (!upstream || typeof upstream !== "object" || Array.isArray(upstream)) {
    fail('missing "productExperienceHandoff" from prepare-product-for-demo.');
  } else {
    for (const field of ["assessmentOwner", "assessedRevision", "assessedEnvironment", "workflow", "persona", "heroMoment", "handoffPath", "afterVerdict", "handoffDecision"]) {
      if (!present(upstream[field])) fail(`productExperienceHandoff missing "${field}".`);
    }
    if (upstream.assessmentOwner !== "product-experience-engineering") fail('productExperienceHandoff assessmentOwner must be "product-experience-engineering".');
    if (upstream.afterVerdict !== "DEMO-READY") fail("productExperienceHandoff must be DEMO-READY before video production.");
    if (upstream.handoffDecision !== "PROCEED") fail("productExperienceHandoff must explicitly say PROCEED.");
    if (!Array.isArray(upstream.permissions) || upstream.permissions.length === 0 || upstream.permissions.some((value) => !present(value))) {
      fail("productExperienceHandoff permissions must contain at least one explicit role or permission.");
    }
    for (const field of ["fixture", "seedCommand", "resetCommand"]) {
      if (!present(upstream.seedProfile?.[field])) fail(`productExperienceHandoff seedProfile missing "${field}".`);
    }
    if (upstream.workflow !== episode.workflow) fail("productExperienceHandoff workflow does not match the video candidate.");
    if (upstream.assessedEnvironment !== episode.assessedEnvironment) fail("productExperienceHandoff environment does not match the video assessment.");
    if (upstream.assessedRevision !== episode.assessedRevision) fail("productExperienceHandoff revision does not match the video assessment.");
    if (upstream.persona !== episode.persona) fail("productExperienceHandoff persona does not match the video candidate.");
    if (targetRevision && upstream.assessedRevision !== targetRevision) fail("productExperienceHandoff is stale for --target-revision.");
    if (expectedHandoffPath && upstream.handoffPath !== expectedHandoffPath) fail("productExperienceHandoff path does not match --expected-handoff-path.");

    if (!Array.isArray(upstream.criteria)) {
      fail("productExperienceHandoff must contain all eleven passing criteria.");
    } else {
      const upstreamIds = new Set();
      for (const criterion of upstream.criteria) {
        if (!present(criterion?.id)) {
          fail("productExperienceHandoff criterion missing id.");
          continue;
        }
        if (upstreamIds.has(criterion.id)) fail(`productExperienceHandoff duplicates criterion "${criterion.id}".`);
        upstreamIds.add(criterion.id);
        if (criterion.passed !== true) fail(`productExperienceHandoff criterion "${criterion.id}" must pass.`);
        if (!Array.isArray(criterion.evidence) || criterion.evidence.length === 0 || criterion.evidence.some((value) => !present(value))) {
          fail(`productExperienceHandoff criterion "${criterion.id}" needs evidence.`);
        }
      }
      for (const id of CRITERIA) if (!upstreamIds.has(id)) fail(`productExperienceHandoff missing criterion "${id}".`);
      for (const id of upstreamIds) if (!CRITERIA.includes(id)) fail(`productExperienceHandoff contains unknown criterion "${id}".`);
    }
  }
  if (episode.verdict && !VERDICTS.has(episode.verdict)) {
    fail(`verdict must be one of: ${[...VERDICTS].join(", ")}.`);
  }

  if (!Array.isArray(episode.criteria)) {
    fail('"criteria" must be an array containing all eleven rubric criteria.');
    continue;
  }

  const byId = new Map();
  for (const criterion of episode.criteria) {
    if (!criterion?.id) {
      fail("criterion missing id.");
      continue;
    }
    if (byId.has(criterion.id)) fail(`duplicate criterion "${criterion.id}".`);
    byId.set(criterion.id, criterion);
    if (typeof criterion.passed !== "boolean") fail(`${criterion.id}: "passed" must be boolean.`);
    if (!Array.isArray(criterion.evidence) || criterion.evidence.length === 0 || criterion.evidence.some((e) => !present(e))) {
      fail(`${criterion.id}: include at least one evidence reference.`);
    }
    if (criterion.passed === false && !CLASSIFICATIONS.has(criterion.classification)) {
      fail(`${criterion.id}: a failure needs classification capture-fixable or product-fix-required.`);
    }
    if (criterion.passed === true && criterion.classification) {
      fail(`${criterion.id}: a passing criterion must not carry a failure classification.`);
    }
  }
  for (const id of CRITERIA) if (!byId.has(id)) fail(`missing rubric criterion "${id}".`);
  for (const id of byId.keys()) if (!CRITERIA.includes(id)) fail(`unknown rubric criterion "${id}".`);

  const failed = [...byId.values()].filter((criterion) => criterion.passed === false);
  const captureFailures = failed.filter((criterion) => criterion.classification === "capture-fixable");
  const productFailures = failed.filter((criterion) => criterion.classification === "product-fix-required");

  if (episode.verdict === "PASS" && failed.length > 0) fail("PASS cannot contain failed criteria.");
  if (episode.verdict === "CONDITIONAL" && (captureFailures.length === 0 || productFailures.length > 0)) {
    fail("CONDITIONAL requires at least one capture-fixable failure and no product-fix-required failures.");
  }
  if (episode.verdict === "FAIL" && productFailures.length === 0) {
    fail("FAIL requires at least one product-fix-required criterion.");
  }

  const captureFixes = episode.captureFixes ?? [];
  if (captureFailures.length > 0 && (!Array.isArray(captureFixes) || captureFixes.length === 0)) {
    fail("capture-fixable failures require explicit captureFixes.");
  }

  const productFixes = episode.productFixes ?? [];
  if (productFailures.length > 0 && (!Array.isArray(productFixes) || productFixes.length === 0)) {
    fail("product-fix-required failures require productFixes entries.");
  }
  for (const [fixIndex, fix] of productFixes.entries()) {
    for (const field of ["id", "principle", "observedBehavior", "viewerImpact", "suggestedFix"]) {
      if (!present(fix?.[field])) fail(`productFixes[${fixIndex}] missing "${field}".`);
    }
    if (!Array.isArray(fix?.evidence) || fix.evidence.length === 0) {
      fail(`productFixes[${fixIndex}] needs evidence references.`);
    }
    if (!SEVERITIES.has(fix?.severity)) {
      fail(`productFixes[${fixIndex}] severity must be one of: ${[...SEVERITIES].join(", ")}.`);
    }
  }
  if (episode.verdict === "FAIL" && !present(episode.feedbackPath ?? episode.uxFeedbackPath)) {
    fail('FAIL requires "feedbackPath" in the configured work directory (legacy "uxFeedbackPath" is accepted).');
  }
  if (episode.verdict === "FAIL" && !present(episode.shortestPathToReady)) {
    fail('FAIL requires "shortestPathToReady".');
  }
}

console.log(`\n${episodes.length} readiness sheet(s) checked: ${errors} error(s).`);
process.exit(errors > 0 ? 1 : 0);
