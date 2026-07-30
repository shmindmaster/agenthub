#!/usr/bin/env node
// Validates one or more capture manifests against the shape documented in
// skills/product-demo-studio-capture/SKILL.md. Accepts a single manifest object, a JSON array of
// manifests, or an object with a top-level "captures" array.
// Usage: node validate-capture-manifest.mjs <path-to-manifest.json>
import { readFileSync } from "node:fs";

const manifestPath = process.argv[2];
if (!manifestPath) {
  console.error("Usage: node validate-capture-manifest.mjs <path-to-manifest.json>");
  process.exit(1);
}

const parsed = JSON.parse(readFileSync(manifestPath, "utf8"));
const manifests = Array.isArray(parsed) ? parsed : (parsed.captures ?? [parsed]);

function isRect(value) {
  return (
    value &&
    typeof value.x === "number" &&
    typeof value.y === "number" &&
    typeof value.width === "number" &&
    value.width > 0 &&
    typeof value.height === "number" &&
    value.height > 0
  );
}

function isPoint(value) {
  return Array.isArray(value) && value.length === 2 && value.every((n) => typeof n === "number");
}

const CAPTURE_SURFACES = new Set([
  "page-only",
  "native-browser-fullscreen",
  "mobile-device-frame",
  "intentional-context",
]);
const CHROME_STATES = new Set(["none", "required-context"]);
const NAVIGATION_STATES = new Set(["hidden", "collapsed", "required-context"]);
const DELIVERY_TREATMENTS = new Set(["native-full-frame", "crop", "push-in", "recompose"]);
const INTERACTION_KINDS = new Set([
  "none",
  "move",
  "hover",
  "click",
  "double-click",
  "type",
  "scroll",
  "drag",
  "select",
  "keyboard",
]);
const CLICK_CUES = new Set(["none", "visual", "visual-and-audio"]);

let errorCount = 0;

manifests.forEach((manifest, index) => {
  const label = manifest.scenario ?? manifest.beat ?? `#${index}`;
  const fail = (message) => {
    console.error(`[error] ${label}: ${message}`);
    errorCount++;
  };

  if (!manifest.scenario && !manifest.beat) fail('missing "scenario" or "beat" identifier.');
  if (!manifest.route) fail('missing "route".');

  if (!manifest.viewport || typeof manifest.viewport.width !== "number" || typeof manifest.viewport.height !== "number") {
    fail('missing or invalid "viewport" ({ width, height }).');
  }

  const surface = manifest.captureSurface;
  if (!surface || typeof surface !== "object" || Array.isArray(surface)) {
    fail('missing "captureSurface" screen-space contract.');
  } else {
    for (const field of [
      "mode",
      "extraneousChrome",
      "irrelevantNavigation",
      "plannedTreatment",
      "plannedActiveRegionCoverage",
      "deliveryLegibility",
    ]) {
      if (surface[field] === undefined || surface[field] === null || surface[field] === "") {
        fail(`captureSurface missing "${field}".`);
      }
    }
    if (surface.mode && !CAPTURE_SURFACES.has(surface.mode)) {
      fail('"captureSurface.mode" is not supported.');
    }
    if (surface.extraneousChrome && !CHROME_STATES.has(surface.extraneousChrome)) {
      fail('"captureSurface.extraneousChrome" must be none or required-context.');
    }
    if (surface.extraneousChrome === "required-context" && surface.mode !== "intentional-context") {
      fail('extraneous browser/OS chrome is allowed only for "intentional-context" evidence.');
    }
    if (surface.irrelevantNavigation && !NAVIGATION_STATES.has(surface.irrelevantNavigation)) {
      fail('"captureSurface.irrelevantNavigation" is invalid.');
    }
    if (surface.plannedTreatment && !DELIVERY_TREATMENTS.has(surface.plannedTreatment)) {
      fail('"captureSurface.plannedTreatment" is invalid.');
    }
    if (typeof surface.plannedActiveRegionCoverage !== "number" ||
        surface.plannedActiveRegionCoverage < 0.5 ||
        surface.plannedActiveRegionCoverage > 1) {
      fail('"captureSurface.plannedActiveRegionCoverage" must be between 0.5 and 1.');
    }
    if (surface.deliveryLegibility !== "pass") {
      fail('"captureSurface.deliveryLegibility" must be "pass" at final delivery size.');
    }
  }

  if (manifest.focus !== undefined && !isRect(manifest.focus)) {
    fail('"focus" must be a rect ({ x, y, width, height } with positive width/height).');
  }

  if (manifest.protectedRegions !== undefined) {
    if (!Array.isArray(manifest.protectedRegions)) {
      fail('"protectedRegions" must be an array of rects.');
    } else {
      manifest.protectedRegions.forEach((region, i) => {
        if (!isRect(region)) fail(`protectedRegions[${i}] is not a valid rect.`);
      });
    }
  }

  const interaction = manifest.interaction;
  if (!interaction || typeof interaction !== "object" || Array.isArray(interaction)) {
    fail('missing "interaction" screencast choreography.');
  } else {
    for (const field of ["kind", "target", "cursor", "cue", "narrationSync"]) {
      if (interaction[field] === undefined || interaction[field] === null || interaction[field] === "") {
        fail(`interaction missing "${field}".`);
      }
    }
    if (interaction.kind && !INTERACTION_KINDS.has(interaction.kind)) {
      fail('"interaction.kind" is not supported.');
    }
    if (interaction.cue && !CLICK_CUES.has(interaction.cue)) {
      fail('"interaction.cue" must be none, visual, or visual-and-audio.');
    }
    if (["click", "double-click"].includes(interaction.kind) && interaction.cue === "none") {
      fail("click interactions require a visible click cue.");
    }
    if (interaction.kind === "none" && interaction.cue !== "none") {
      fail("non-interactive holds cannot declare a click cue.");
    }
    if (interaction.kind !== "none" && typeof interaction.target !== "string") {
      fail('"interaction.target" must name the real product control or region.');
    }
    const cursor = interaction.cursor;
    if (!cursor || typeof cursor !== "object" || Array.isArray(cursor)) {
      fail('"interaction.cursor" must be an object.');
    } else {
      if (!isPoint(cursor.park)) fail('"interaction.cursor.park" must be a [x, y] point.');
      if (interaction.kind !== "none") {
        if (!isPoint(cursor.from)) fail('"interaction.cursor.from" must be a [x, y] point.');
        if (!isPoint(cursor.to)) fail('"interaction.cursor.to" must be a [x, y] point.');
        if (!Number.isFinite(cursor.durationMs) || cursor.durationMs < 200 || cursor.durationMs > 2500) {
          fail('"interaction.cursor.durationMs" must be between 200 and 2500.');
        }
      }
    }
    const sync = interaction.narrationSync;
    if (!sync || typeof sync !== "object" || Array.isArray(sync)) {
      fail('"interaction.narrationSync" must be an object.');
    } else {
      for (const field of [
        "cursorLeadSeconds",
        "actionAtSeconds",
        "resultVisibleAtSeconds",
        "spokenResultAtSeconds",
      ]) {
        if (!Number.isFinite(sync[field]) || sync[field] < 0) {
          fail(`interaction.narrationSync.${field} must be a non-negative number.`);
        }
      }
      if (Number.isFinite(sync.cursorLeadSeconds) && sync.cursorLeadSeconds > 1.5) {
        fail("interaction.narrationSync.cursorLeadSeconds must not exceed 1.5 seconds.");
      }
      if (Number.isFinite(sync.actionAtSeconds) &&
          Number.isFinite(sync.resultVisibleAtSeconds) &&
          sync.resultVisibleAtSeconds < sync.actionAtSeconds) {
        fail("the result cannot be visible before the declared action.");
      }
      if (Number.isFinite(sync.resultVisibleAtSeconds) &&
          Number.isFinite(sync.spokenResultAtSeconds) &&
          sync.spokenResultAtSeconds < sync.resultVisibleAtSeconds) {
        fail("the narration cannot describe the result before it is visible.");
      }
    }
  }

  if (!manifest.focus && (!manifest.protectedRegions || manifest.protectedRegions.length === 0)) {
    console.warn(
      `[warn] ${label}: no "focus" and no "protectedRegions" -- overlay placement has nothing to ` +
        "avoid, which is only correct for scenes with no on-screen product UI.",
    );
  }
});

console.log(`\n${manifests.length} manifest(s) checked: ${errorCount} error(s).`);
process.exit(errorCount > 0 ? 1 : 0);
