#!/usr/bin/env node
// Validates one or more capture manifests against the shape documented in
// skills/media-studio-capture/SKILL.md. Accepts a single manifest object, a JSON array of
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
const FEEDBACK_TYPES = new Set([
  "none",
  "radial-pulse",
  "drag-held",
  "drag-trail",
  "native-hover",
  "keystroke-overlay",
]);
const POINTER_KINDS = new Set(["move", "hover", "click", "double-click", "drag", "select"]);
const PACE_ACTIVITIES = new Set(["meaningful-action", "bounded-wait", "text-entry", "result-hold"]);
const PACE_TREATMENTS = new Set(["real-time", "speed-ramp", "cut", "chunked-entry"]);

let errorCount = 0;

manifests.forEach((manifest, index) => {
  const label = manifest.scenario ?? manifest.beat ?? `#${index}`;
  const fail = (message) => {
    console.error(`[error] ${label}: ${message}`);
    errorCount++;
  };

  if (!manifest.scenario && !manifest.beat) fail('missing "scenario" or "beat" identifier.');
  if (typeof manifest.storyboardSegmentId !== "string" || manifest.storyboardSegmentId.trim() === "") {
    fail('missing "storyboardSegmentId" alignment identifier.');
  }
  if (!manifest.route) fail('missing "route".');

  if (!manifest.viewport || typeof manifest.viewport.width !== "number" || typeof manifest.viewport.height !== "number" ||
      !Number.isFinite(manifest.viewport.deviceScaleFactor) || manifest.viewport.deviceScaleFactor < 2) {
    fail('missing or invalid "viewport" ({ width, height, deviceScaleFactor >= 2 }).');
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
      "deliveryFrame",
      "deliveredCrop",
      "sourceFrame",
      "smallDelivery",
      "browserZoomPercent",
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
    if (!surface.deliveryFrame || !Number.isFinite(surface.deliveryFrame.width) || surface.deliveryFrame.width <= 0 ||
        !Number.isFinite(surface.deliveryFrame.height) || surface.deliveryFrame.height <= 0) {
      fail('"captureSurface.deliveryFrame" must declare positive delivery width and height.');
    }
    if (!surface.sourceFrame || !Number.isFinite(surface.sourceFrame.width) || surface.sourceFrame.width <= 0 ||
        !Number.isFinite(surface.sourceFrame.height) || surface.sourceFrame.height <= 0) {
      fail('"captureSurface.sourceFrame" must declare positive raw-capture pixel dimensions.');
    } else if (manifest.viewport && (
      surface.sourceFrame.width !== manifest.viewport.width * manifest.viewport.deviceScaleFactor ||
      surface.sourceFrame.height !== manifest.viewport.height * manifest.viewport.deviceScaleFactor
    )) {
      fail('"captureSurface.sourceFrame" must equal viewport dimensions multiplied by deviceScaleFactor.');
    }
    if (!isRect(surface.deliveredCrop)) {
      fail('"captureSurface.deliveredCrop" must be a valid source-CSS-pixel crop rectangle.');
    } else if (manifest.viewport && (
      surface.deliveredCrop.x < 0 || surface.deliveredCrop.y < 0 ||
      surface.deliveredCrop.x + surface.deliveredCrop.width > manifest.viewport.width ||
      surface.deliveredCrop.y + surface.deliveredCrop.height > manifest.viewport.height
    )) {
      fail('"captureSurface.deliveredCrop" must stay within the declared viewport.');
    } else if (surface.deliveryFrame && surface.sourceFrame && manifest.viewport) {
      const horizontalDensity = surface.deliveredCrop.width / manifest.viewport.width * surface.sourceFrame.width / surface.deliveryFrame.width;
      const verticalDensity = surface.deliveredCrop.height / manifest.viewport.height * surface.sourceFrame.height / surface.deliveryFrame.height;
      const effectiveDensity = Math.min(horizontalDensity, verticalDensity);
      if (!Number.isFinite(effectiveDensity) || effectiveDensity < 1) {
        fail('the derived effective delivery pixel density must be at least 1 after crop/recomposition (no upscaling).');
      }
    }
    if (typeof surface.smallDelivery !== "boolean") {
      fail('"captureSurface.smallDelivery" must explicitly declare whether mobile/embedded cursor enlargement applies.');
    }
    if (surface.browserZoomPercent !== 100 && !(
      typeof surface.browserZoomPercent === "number" &&
      surface.browserZoomPercent >= 110 && surface.browserZoomPercent <= 125
    )) {
      fail('"captureSurface.browserZoomPercent" must be 100, or between 110 and 125 with a rationale.');
    }
    if (surface.browserZoomPercent !== 100 &&
        (typeof surface.browserZoomRationale !== "string" || surface.browserZoomRationale.trim() === "")) {
      fail('non-default browser zoom requires "captureSurface.browserZoomRationale".');
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
    for (const field of ["kind", "target", "cursor", "cue", "feedback", "keystrokeOverlay", "pacing", "narrationSync"]) {
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
      if (POINTER_KINDS.has(interaction.kind)) {
        if (!isPoint(cursor.from)) fail('"interaction.cursor.from" must be a [x, y] point.');
        if (!isPoint(cursor.to)) fail('"interaction.cursor.to" must be a [x, y] point.');
        if (!Number.isFinite(cursor.durationMs) || cursor.durationMs < 400 || cursor.durationMs > 600) {
          fail('"interaction.cursor.durationMs" must be between 400 and 600 for deliberate pointer movement.');
        }
        if (cursor.easing !== "eased-deceleration") {
          fail('"interaction.cursor.easing" must be "eased-deceleration".');
        }
        const minimumCursorScale = surface?.smallDelivery === true ? 1.5 : 1;
        if (!Number.isFinite(cursor.scale) || cursor.scale < minimumCursorScale || cursor.scale > 2) {
          fail(`"interaction.cursor.scale" must be between ${minimumCursorScale} and 2 for this delivery context.`);
        }
      }
      if (["click", "double-click"].includes(interaction.kind)) {
        if (!Number.isFinite(cursor.settleBeforeActionMs) || cursor.settleBeforeActionMs < 250) {
          fail('clicks require "interaction.cursor.settleBeforeActionMs" of at least 250.');
        }
        if (!Number.isFinite(cursor.holdAfterActionMs) || cursor.holdAfterActionMs < 500) {
          fail('clicks require "interaction.cursor.holdAfterActionMs" of at least 500.');
        }
      }
    }
    const feedback = interaction.feedback;
    if (!feedback || typeof feedback !== "object" || Array.isArray(feedback)) {
      fail('"interaction.feedback" must be an object.');
    } else {
      if (!FEEDBACK_TYPES.has(feedback.type)) fail('"interaction.feedback.type" is invalid.');
      if (["click", "double-click"].includes(interaction.kind) &&
          (feedback.type !== "radial-pulse" || !Number.isFinite(feedback.durationMs) ||
           feedback.durationMs < 300 || feedback.durationMs > 400)) {
        fail("click feedback must be a 300-400ms radial-pulse.");
      }
      if (["click", "double-click"].includes(interaction.kind) &&
          (typeof feedback.brandColor !== "string" || feedback.brandColor.trim() === "" ||
           !Number.isFinite(feedback.opacity) || feedback.opacity <= 0 || feedback.opacity >= 1)) {
        fail("click feedback requires a brand color and semi-transparent opacity.");
      }
      if (interaction.kind === "move" && feedback.type !== "none") {
        fail("pointer moves cannot display interaction feedback.");
      }
      if (interaction.kind === "hover" && feedback.type !== "native-hover") {
        fail("hover must use the product's native hover state without an overlay.");
      }
      if (interaction.kind === "drag" && !["drag-held", "drag-trail"].includes(feedback.type)) {
        fail("drag must use drag-held or drag-trail feedback.");
      }
      if (interaction.kind === "none" && feedback.type !== "none") {
        fail("non-interactive holds cannot declare interaction feedback.");
      }
    }
    if (typeof interaction.keystrokeOverlay !== "boolean") {
      fail('"interaction.keystrokeOverlay" must be true or false.');
    }
    if (interaction.kind === "keyboard" &&
        (interaction.keystrokeOverlay !== true || feedback?.type !== "keystroke-overlay")) {
      fail("shortcut-driven keyboard actions require a keystroke overlay.");
    }
    if (interaction.kind !== "keyboard" && interaction.keystrokeOverlay !== false) {
      fail("keystrokeOverlay is reserved for shortcut-driven keyboard actions.");
    }
    const pacing = interaction.pacing;
    if (!pacing || typeof pacing !== "object" || Array.isArray(pacing)) {
      fail('"interaction.pacing" must be an object.');
    } else {
      for (const field of ["activity", "treatment", "multiplier", "truthTreatment"]) {
        if (pacing[field] === undefined || pacing[field] === null || pacing[field] === "") {
          fail(`interaction.pacing missing "${field}".`);
        }
      }
      if (!PACE_ACTIVITIES.has(pacing.activity)) fail('"interaction.pacing.activity" is invalid.');
      if (!PACE_TREATMENTS.has(pacing.treatment)) fail('"interaction.pacing.treatment" is invalid.');
      if (!Number.isFinite(pacing.multiplier) || pacing.multiplier < 0) {
        fail('"interaction.pacing.multiplier" must be a non-negative number.');
      }
      if (["meaningful-action", "result-hold"].includes(pacing.activity) &&
          (pacing.treatment !== "real-time" || pacing.multiplier !== 1)) {
        fail("meaningful actions and result holds must remain real-time.");
      }
      if (pacing.activity === "bounded-wait" && !(
        pacing.treatment === "cut" ||
        (pacing.treatment === "speed-ramp" && pacing.multiplier >= 4 && pacing.multiplier <= 8)
      )) fail("bounded waits must be cut or speed-ramped between 4x and 8x.");
      if (pacing.activity === "text-entry" && !(
        pacing.treatment === "chunked-entry" ||
        (pacing.treatment === "speed-ramp" && pacing.multiplier >= 3 && pacing.multiplier <= 4)
      )) fail("text entry must be chunked or speed-ramped between 3x and 4x.");
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
