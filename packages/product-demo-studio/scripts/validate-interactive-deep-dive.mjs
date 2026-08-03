#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const input = process.argv[2];
const errors = [];
const ID = /^[a-z0-9][a-z0-9-]*$/;
const SHA256 = /^[a-f0-9]{64}$/;
const REQUIRED_EVENTS = ["role_selected", "scene_viewed", "proof_interacted", "cta_clicked"];

function fail(path, message) {
  errors.push(`${path}: ${message}`);
}

function uniqueIds(items, path) {
  const seen = new Set();
  for (const [index, item] of items.entries()) {
    if (!ID.test(item?.id ?? "")) fail(`${path}[${index}].id`, "must be a lowercase hyphenated id.");
    if (seen.has(item?.id)) fail(`${path}[${index}].id`, "must be unique.");
    seen.add(item?.id);
  }
  return seen;
}

if (!input || process.argv.length !== 3) {
  console.error("Usage: node validate-interactive-deep-dive.mjs <interactive-deep-dive.json>");
  process.exit(1);
}

let document;
try {
  document = JSON.parse(readFileSync(resolve(input), "utf8"));
} catch (error) {
  console.error(`Interactive deep-dive is unreadable: ${error.message}`);
  process.exit(1);
}

const allowedRoot = new Set([
  "schemaVersion", "experienceId", "narrativeAnchor", "personas", "proofAssets",
  "scenes", "navigation", "instrumentation", "safety",
]);
for (const key of Object.keys(document)) if (!allowedRoot.has(key)) fail("$", `unknown property "${key}".`);
if (document.schemaVersion !== "1.0.0") fail("$.schemaVersion", 'must equal "1.0.0".');
if (!ID.test(document.experienceId ?? "")) fail("$.experienceId", "must be a lowercase hyphenated id.");
if (typeof document.narrativeAnchor !== "string" || !document.narrativeAnchor.trim()) {
  fail("$.narrativeAnchor", "must be a non-empty operational story.");
}
if (!Array.isArray(document.personas) || document.personas.length < 2 || document.personas.length > 4) {
  fail("$.personas", "must contain two to four personas.");
}
if (!Array.isArray(document.proofAssets) || document.proofAssets.length < 1) {
  fail("$.proofAssets", "must contain verified proof assets.");
}
if (!Array.isArray(document.scenes) || document.scenes.length < 5 || document.scenes.length > 15) {
  fail("$.scenes", "must contain five to fifteen operational scenes.");
}

const personaIds = uniqueIds(document.personas ?? [], "$.personas");
for (const [index, persona] of (document.personas ?? []).entries()) {
  if (!persona?.label?.trim() || !persona?.outcome?.trim() ||
      !persona?.cta?.label?.trim() || !persona?.cta?.destination?.trim()) {
    fail(`$.personas[${index}]`, "must define label, outcome, and contextual CTA.");
  }
}
const assetIds = uniqueIds(document.proofAssets ?? [], "$.proofAssets");
for (const [index, asset] of (document.proofAssets ?? []).entries()) {
  if (!["interactive-hotspots", "video-loop", "synthetic-sandbox"].includes(asset?.type)) {
    fail(`$.proofAssets[${index}].type`, "must use an approved interactive proof type.");
  }
  if (!asset?.path?.trim() || !asset?.posterFallback?.trim() || !SHA256.test(asset?.sha256 ?? "") ||
      !Array.isArray(asset?.evidenceIds) || asset.evidenceIds.length < 1) {
    fail(`$.proofAssets[${index}]`, "must bind path, checksum, evidence, and accessible fallback.");
  }
}
const sceneIds = uniqueIds(document.scenes ?? [], "$.scenes");
const usedPersonas = new Set();
for (const [index, scene] of (document.scenes ?? []).entries()) {
  if (scene?.sequence !== index + 1) fail(`$.scenes[${index}].sequence`, "must be contiguous and ordered.");
  if (scene?.deepLink !== `#${scene?.id}`) fail(`$.scenes[${index}].deepLink`, "must equal #<scene-id>.");
  if (!assetIds.has(scene?.proofAssetId)) fail(`$.scenes[${index}].proofAssetId`, "must reference a proof asset.");
  if (!scene?.phase?.trim() || !scene?.title?.trim() || !scene?.trustControl?.trim()) {
    fail(`$.scenes[${index}]`, "must define phase, title, and adjacent trust/control moment.");
  }
  if (!Array.isArray(scene?.personaIds) || scene.personaIds.length < 1) {
    fail(`$.scenes[${index}].personaIds`, "must reference at least one persona.");
  } else {
    for (const personaId of scene.personaIds) {
      if (!personaIds.has(personaId)) fail(`$.scenes[${index}].personaIds`, `unknown persona "${personaId}".`);
      usedPersonas.add(personaId);
    }
  }
  for (const [metricIndex, metric] of (scene?.metrics ?? []).entries()) {
    if (!metric?.label?.trim() || !metric?.value?.trim() || !ID.test(metric?.evidenceId ?? "")) {
      fail(`$.scenes[${index}].metrics[${metricIndex}]`, "metrics require a label, value, and evidence id.");
    }
  }
  if (scene?.automationDisclosure) {
    const disclosure = scene.automationDisclosure;
    if (!Array.isArray(disclosure.sourceClasses) || disclosure.sourceClasses.length < 1 ||
        !disclosure.confidenceLabel?.trim() || !disclosure.limitations?.trim() ||
        !disclosure.humanControl?.trim()) {
      fail(`$.scenes[${index}].automationDisclosure`, "must show sources, confidence label, limitations, and real human control.");
    }
    if (/chain[- ]of[- ]thought|hidden reasoning/i.test(JSON.stringify(disclosure))) {
      fail(`$.scenes[${index}].automationDisclosure`, "must not request private chain-of-thought.");
    }
  }
}
for (const personaId of personaIds) if (!usedPersonas.has(personaId)) fail("$.scenes", `persona "${personaId}" is never used.`);
if (sceneIds.size !== (document.scenes ?? []).length) fail("$.scenes", "scene ids must be unique.");

for (const [key, expected] of Object.entries({
  personaRouter: true,
  stickyJourneyProgress: true,
  directSceneLinks: true,
  persistentContextualCta: true,
  safeAreaValidated: true,
})) {
  if (document.navigation?.[key] !== expected) fail(`$.navigation.${key}`, "must be true.");
}
for (const event of REQUIRED_EVENTS) {
  if (!document.instrumentation?.includes(event)) fail("$.instrumentation", `must include "${event}".`);
}
for (const [key, expected] of Object.entries({
  syntheticDataOnly: true,
  noExternalSideEffects: true,
  keyboardAccessible: true,
  reducedMotionSupported: true,
  sandboxIsolation: "synthetic-only",
})) {
  if (document.safety?.[key] !== expected) fail(`$.safety.${key}`, `must equal ${JSON.stringify(expected)}.`);
}

for (const error of errors) console.error(`[error] ${error}`);
console.log(`Interactive deep-dive checked: ${errors.length} error(s).`);
process.exit(errors.length ? 1 : 0);
