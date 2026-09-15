#!/usr/bin/env node
// Validate the normalized persuasion/storyboard contract before narration or final capture.
// Usage: node validate-storyboard.mjs <path-to-storyboard.json>
import { readFileSync } from "node:fs";

const storyboardPath = process.argv[2];
if (!storyboardPath) {
  console.error("Usage: node validate-storyboard.mjs <path-to-storyboard.json>");
  process.exit(1);
}

const parsed = JSON.parse(readFileSync(storyboardPath, "utf8"));
const episodes = Array.isArray(parsed) ? parsed : (parsed.episodes ?? [parsed]);
const LADDER_RUNGS = new Set([
  "feature",
  "outcome",
  "identity",
  "functional-benefit",
  "practical-outcome",
  "emotional-outcome",
  "identity-outcome",
]);
const PAYOFF_RUNGS = new Set([
  "outcome",
  "identity",
  "practical-outcome",
  "emotional-outcome",
  "identity-outcome",
]);
const DEMO_TYPES = new Set([
  "sizzle-hook",
  "guided-discovery-support",
  "onboarding-enablement",
  "internal-handoff",
]);
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
const ZOOM_MODES = new Set(["none", "snap-to-region", "recompose"]);
const PACE_ACTIVITIES = new Set(["meaningful-action", "bounded-wait", "text-entry", "result-hold"]);
const PACE_TREATMENTS = new Set(["real-time", "speed-ramp", "cut", "chunked-entry"]);
const CAPTURE_SURFACES = new Set([
  "page-only",
  "native-browser-fullscreen",
  "mobile-device-frame",
  "intentional-context",
]);
const NAVIGATION_STATES = new Set(["hidden", "collapsed", "required-context"]);
const DELIVERY_TREATMENTS = new Set(["native-full-frame", "crop", "push-in", "recompose"]);
let errors = 0;
let warnings = 0;

function present(value) {
  return typeof value === "string" ? value.trim().length > 0 : value !== undefined && value !== null;
}

for (const [episodeIndex, episode] of episodes.entries()) {
  const label = episode.episodeId ?? `#${episodeIndex}`;
  const fail = (message) => {
    console.error(`[error] ${label}: ${message}`);
    errors++;
  };
  const warn = (message) => {
    console.warn(`[warn] ${label}: ${message}`);
    warnings++;
  };

  for (const field of [
    "episodeId",
    "demoType",
    "audience",
    "audienceContext",
    "persona",
    "problem",
    "outcome",
    "viewerUnits",
    "guardrail",
    "emotionalTarget",
  ]) {
    if (!present(episode[field])) fail(`missing required episode field "${field}".`);
  }
  if (episode.demoType && !DEMO_TYPES.has(episode.demoType)) {
    fail(`demoType must be one of: ${[...DEMO_TYPES].join(", ")}.`);
  }
  if (!Array.isArray(episode.claimIds)) fail('"claimIds" must be an array (empty when no visible/spoken claims exist).');
  if (!Array.isArray(episode.segments) || episode.segments.length === 0) {
    fail('"segments" must be a non-empty array.');
    continue;
  }

  const ids = new Set();
  const ordered = [...episode.segments].sort((a, b) => a.order - b.order);
  episode.segments.forEach((segment, index) => {
    const segmentLabel = segment.id ?? `segment #${index}`;
    for (const field of [
      "id",
      "order",
      "action",
      "expectedState",
      "primaryIdea",
      "wiifm",
      "ladderRung",
      "narration",
      "pronunciation",
      "emphasis",
      "pauseBeforeSeconds",
      "pauseAfterSeconds",
      "expectedAudioDurationSeconds",
      "timelineStartSeconds",
      "eyeDirectionTreatment",
      "interaction",
      "framing",
      "annotations",
      "protectedRegions",
      "pacePatternChange",
      "resultHoldSeconds",
      "intentionalSilence",
      "visibleClaimIds",
    ]) {
      if (!present(segment[field])) fail(`${segmentLabel}: missing "${field}".`);
    }
    if (!Array.isArray(segment.annotations)) fail(`${segmentLabel}: annotations must be an array.`);
    if (Array.isArray(segment.annotations) && segment.annotations.length > 2) {
      fail(`${segmentLabel}: no more than two annotations may be active in one beat.`);
    }
    if (!Array.isArray(segment.protectedRegions)) fail(`${segmentLabel}: protectedRegions must be an array.`);
    if (!Array.isArray(segment.visibleClaimIds)) fail(`${segmentLabel}: visibleClaimIds must be an array.`);
    if (typeof segment.expectedAudioDurationSeconds !== "number" || segment.expectedAudioDurationSeconds < 0) {
      fail(`${segmentLabel}: expectedAudioDurationSeconds must be a non-negative number.`);
    }
    if (typeof segment.resultHoldSeconds !== "number" || segment.resultHoldSeconds < 0) {
      fail(`${segmentLabel}: resultHoldSeconds must be a non-negative number.`);
    }
    if (typeof segment.intentionalSilence !== "boolean") {
      fail(`${segmentLabel}: intentionalSilence must be true or false.`);
    }
    const interaction = segment.interaction;
    if (!interaction || typeof interaction !== "object" || Array.isArray(interaction)) {
      fail(`${segmentLabel}: interaction must be an object.`);
    } else {
      for (const field of ["kind", "target", "cursorBehavior", "timing", "clickCue", "craft", "narrationSync"]) {
        if (!present(interaction[field])) fail(`${segmentLabel}: interaction missing "${field}".`);
      }
      if (interaction.kind && !INTERACTION_KINDS.has(interaction.kind)) {
        fail(`${segmentLabel}: interaction.kind is not a supported screencast action.`);
      }
      if (interaction.clickCue && !CLICK_CUES.has(interaction.clickCue)) {
        fail(`${segmentLabel}: interaction.clickCue must be none, visual, or visual-and-audio.`);
      }
      if (["click", "double-click"].includes(interaction.kind) && interaction.clickCue === "none") {
        fail(`${segmentLabel}: click interactions need a visible click cue.`);
      }
      if (interaction.kind === "none" && interaction.clickCue !== "none") {
        fail(`${segmentLabel}: a non-interactive hold cannot declare a click cue.`);
      }
      const narrationSync = interaction.narrationSync;
      if (!narrationSync || typeof narrationSync !== "object" || Array.isArray(narrationSync)) {
        fail(`${segmentLabel}: interaction.narrationSync must be an object.`);
      } else {
        for (const field of ["cursorLeadSeconds", "actionAtSeconds", "resultVisibleAtSeconds", "spokenResultAtSeconds"]) {
          if (!Number.isFinite(narrationSync[field]) || narrationSync[field] < 0) {
            fail(`${segmentLabel}: interaction.narrationSync.${field} must be a non-negative number.`);
          }
        }
        if (narrationSync.cursorLeadSeconds > 1.5) {
          fail(`${segmentLabel}: interaction.narrationSync.cursorLeadSeconds must not exceed 1.5 seconds.`);
        }
        if (narrationSync.resultVisibleAtSeconds < narrationSync.actionAtSeconds) {
          fail(`${segmentLabel}: the result cannot be visible before the action.`);
        }
        if (narrationSync.spokenResultAtSeconds < narrationSync.resultVisibleAtSeconds) {
          fail(`${segmentLabel}: narration cannot describe the result before it is visible.`);
        }
      }
      const craft = interaction.craft;
      if (!craft || typeof craft !== "object" || Array.isArray(craft)) {
        fail(`${segmentLabel}: interaction.craft must be an object.`);
      } else {
        for (const field of [
          "cursorMotion",
          "cursorMoveMs",
          "settleBeforeActionMs",
          "holdAfterActionMs",
          "cursorScale",
          "feedbackType",
          "feedbackDurationMs",
          "keystrokeOverlay",
        ]) {
          if (!present(craft[field])) fail(`${segmentLabel}: interaction.craft missing "${field}".`);
        }
        if (!FEEDBACK_TYPES.has(craft.feedbackType)) {
          fail(`${segmentLabel}: interaction.craft.feedbackType is invalid.`);
        }
        if (typeof craft.keystrokeOverlay !== "boolean") {
          fail(`${segmentLabel}: interaction.craft.keystrokeOverlay must be true or false.`);
        }
        if (POINTER_KINDS.has(interaction.kind)) {
          if (craft.cursorMotion !== "eased-deceleration") {
            fail(`${segmentLabel}: pointer motion must use eased-deceleration.`);
          }
          if (!Number.isFinite(craft.cursorMoveMs) || craft.cursorMoveMs < 400 || craft.cursorMoveMs > 600) {
            fail(`${segmentLabel}: pointer cursorMoveMs must be between 400 and 600.`);
          }
        }
        if (["click", "double-click"].includes(interaction.kind)) {
          if (!Number.isFinite(craft.settleBeforeActionMs) || craft.settleBeforeActionMs < 250) {
            fail(`${segmentLabel}: clicks require at least 250ms settle before the action.`);
          }
          if (!Number.isFinite(craft.holdAfterActionMs) || craft.holdAfterActionMs < 500) {
            fail(`${segmentLabel}: clicks require at least 500ms hold after the action.`);
          }
          if (craft.feedbackType !== "radial-pulse" ||
              !Number.isFinite(craft.feedbackDurationMs) ||
              craft.feedbackDurationMs < 300 || craft.feedbackDurationMs > 400) {
            fail(`${segmentLabel}: clicks require a 300-400ms radial-pulse feedback cue.`);
          }
          if (typeof craft.feedbackColor !== "string" || craft.feedbackColor.trim() === "" ||
              !Number.isFinite(craft.feedbackOpacity) || craft.feedbackOpacity <= 0 || craft.feedbackOpacity >= 1) {
            fail(`${segmentLabel}: click feedback requires a brand color and semi-transparent opacity.`);
          }
        }
        if (interaction.kind === "move" && craft.feedbackType !== "none") {
          fail(`${segmentLabel}: pointer moves cannot display interaction feedback.`);
        }
        if (interaction.kind === "hover" && craft.feedbackType !== "native-hover") {
          fail(`${segmentLabel}: hover must use the product's native hover state without an overlay.`);
        }
        if (interaction.kind === "drag" && !["drag-held", "drag-trail"].includes(craft.feedbackType)) {
          fail(`${segmentLabel}: drag must use drag-held or drag-trail feedback.`);
        }
        if (interaction.kind === "none" && craft.feedbackType !== "none") {
          fail(`${segmentLabel}: a non-interactive hold cannot declare interaction feedback.`);
        }
        if (interaction.kind === "keyboard" &&
            (craft.feedbackType !== "keystroke-overlay" || craft.keystrokeOverlay !== true)) {
          fail(`${segmentLabel}: shortcut-driven keyboard actions require a keystroke overlay.`);
        }
        if (interaction.kind !== "keyboard" && craft.keystrokeOverlay !== false) {
          fail(`${segmentLabel}: keystrokeOverlay is reserved for shortcut-driven keyboard actions.`);
        }
      }
    }
    const framing = segment.framing;
    if (!framing || typeof framing !== "object" || Array.isArray(framing)) {
      fail(`${segmentLabel}: framing must be an object.`);
    } else {
      for (const field of [
        "surface",
        "activeRegion",
        "irrelevantNavigation",
        "deliveryTreatment",
        "legibilityCheck",
        "smallDelivery",
      ]) {
        if (!present(framing[field])) fail(`${segmentLabel}: framing missing "${field}".`);
      }
      if (framing.surface && !CAPTURE_SURFACES.has(framing.surface)) {
        fail(`${segmentLabel}: framing.surface is not a supported capture surface.`);
      }
      if (framing.irrelevantNavigation && !NAVIGATION_STATES.has(framing.irrelevantNavigation)) {
        fail(`${segmentLabel}: framing.irrelevantNavigation is invalid.`);
      }
      if (framing.deliveryTreatment && !DELIVERY_TREATMENTS.has(framing.deliveryTreatment)) {
        fail(`${segmentLabel}: framing.deliveryTreatment is invalid.`);
      }
      if (typeof framing.smallDelivery !== "boolean") {
        fail(`${segmentLabel}: framing.smallDelivery must be true or false.`);
      }
      if (POINTER_KINDS.has(interaction?.kind)) {
        const minimumCursorScale = framing.smallDelivery === true ? 1.5 : 1;
        if (!Number.isFinite(interaction.craft?.cursorScale) ||
            interaction.craft.cursorScale < minimumCursorScale || interaction.craft.cursorScale > 2) {
          fail(`${segmentLabel}: pointer cursorScale must be between ${minimumCursorScale} and 2 for this delivery context.`);
        }
      }
      const zoom = framing.zoom;
      if (!zoom || typeof zoom !== "object" || Array.isArray(zoom)) {
        fail(`${segmentLabel}: framing.zoom must be an object.`);
      } else {
        for (const field of ["mode", "transitionMs", "changesInBeat", "holdThroughAction", "pullBack", "drift"]) {
          if (!present(zoom[field])) fail(`${segmentLabel}: framing.zoom missing "${field}".`);
        }
        if (!ZOOM_MODES.has(zoom.mode)) fail(`${segmentLabel}: framing.zoom.mode is invalid.`);
        if (!Number.isFinite(zoom.transitionMs) || zoom.transitionMs < 0) {
          fail(`${segmentLabel}: framing.zoom.transitionMs must be a non-negative number.`);
        }
        if (!Number.isInteger(zoom.changesInBeat) || zoom.changesInBeat < 0 || zoom.changesInBeat > 1) {
          fail(`${segmentLabel}: framing.zoom.changesInBeat must be 0 or 1.`);
        }
        if (zoom.drift !== false) fail(`${segmentLabel}: framing zoom may not drift during UI interaction.`);
        if (typeof zoom.holdThroughAction !== "boolean" || typeof zoom.pullBack !== "boolean") {
          fail(`${segmentLabel}: framing.zoom holdThroughAction and pullBack must be booleans.`);
        }
        if (zoom.mode === "snap-to-region") {
          if (!Number.isFinite(zoom.transitionMs) || zoom.transitionMs < 300 || zoom.transitionMs > 500) {
            fail(`${segmentLabel}: snap-to-region transitionMs must be between 300 and 500.`);
          }
          if (zoom.changesInBeat !== 1 || zoom.holdThroughAction !== true) {
            fail(`${segmentLabel}: snap-to-region must be the beat's single zoom change and hold through the action.`);
          }
        }
        if (zoom.mode === "none" && (zoom.transitionMs !== 0 || zoom.changesInBeat !== 0)) {
          fail(`${segmentLabel}: framing.zoom mode none requires zero transition and zero changes.`);
        }
        if (zoom.mode === "recompose" &&
            (zoom.transitionMs !== 0 || zoom.changesInBeat !== 0 || zoom.holdThroughAction !== true || zoom.pullBack !== false)) {
          fail(`${segmentLabel}: recompose is a static variant framing decision and requires zero transition/changes, holdThroughAction=true, and pullBack=false.`);
        }
      }
    }
    const pacing = segment.pacing;
    if (!pacing || typeof pacing !== "object" || Array.isArray(pacing)) {
      fail(`${segmentLabel}: pacing must be an object.`);
    } else {
      for (const field of ["activity", "treatment", "multiplier", "truthTreatment"]) {
        if (!present(pacing[field])) fail(`${segmentLabel}: pacing missing "${field}".`);
      }
      if (!PACE_ACTIVITIES.has(pacing.activity)) fail(`${segmentLabel}: pacing.activity is invalid.`);
      if (!PACE_TREATMENTS.has(pacing.treatment)) fail(`${segmentLabel}: pacing.treatment is invalid.`);
      if (!Number.isFinite(pacing.multiplier) || pacing.multiplier < 0) {
        fail(`${segmentLabel}: pacing.multiplier must be a non-negative number.`);
      }
      if (["meaningful-action", "result-hold"].includes(pacing.activity) &&
          (pacing.treatment !== "real-time" || pacing.multiplier !== 1)) {
        fail(`${segmentLabel}: meaningful actions and result holds must remain real-time.`);
      }
      if (pacing.activity === "bounded-wait" && !(
        pacing.treatment === "cut" ||
        (pacing.treatment === "speed-ramp" && pacing.multiplier >= 4 && pacing.multiplier <= 8)
      )) {
        fail(`${segmentLabel}: bounded waits must be cut or speed-ramped between 4x and 8x.`);
      }
      if (pacing.activity === "text-entry" && !(
        pacing.treatment === "chunked-entry" ||
        (pacing.treatment === "speed-ramp" && pacing.multiplier >= 3 && pacing.multiplier <= 4)
      )) {
        fail(`${segmentLabel}: text entry must be chunked or speed-ramped between 3x and 4x.`);
      }
    }
    if (Array.isArray(segment.annotations)) {
      for (const [annotationIndex, annotation] of segment.annotations.entries()) {
        if (present(annotation?.text)) {
          const words = annotation.text.trim().split(/\s+/).length;
          const minimumHold = words / 2.5 + 0.5;
          if (!Number.isFinite(annotation.holdSeconds) || annotation.holdSeconds < minimumHold) {
            fail(`${segmentLabel}: annotations[${annotationIndex}].holdSeconds must be at least ${minimumHold.toFixed(2)} seconds for its text.`);
          }
        }
      }
    }
    for (const claimId of segment.visibleClaimIds ?? []) {
      if (!episode.claimIds?.includes(claimId)) fail(`${segmentLabel}: visible claim "${claimId}" is undeclared.`);
    }
    if (segment.id && ids.has(segment.id)) fail(`${segmentLabel}: duplicate segment id.`);
    if (segment.id) ids.add(segment.id);
    if (segment.ladderRung && !LADDER_RUNGS.has(segment.ladderRung)) {
      fail(
        `${segmentLabel}: ladderRung must use the primary feature/outcome/identity ladder or a ` +
          `supported refined alias (functional-benefit, practical-outcome, emotional-outcome, identity-outcome).`,
      );
    }
    if (index > 0 && episode.segments[index - 1].order >= segment.order) {
      fail(`${segmentLabel}: segments must already be in strictly increasing order.`);
    }
  });

  const coldOpens = episode.segments.filter((segment) => segment.coldOpen === true);
  if (coldOpens.length !== 1 || coldOpens[0] !== episode.segments[0]) {
    fail("exactly the first segment must be marked coldOpen=true.");
  }
  if (coldOpens[0] && /\b(in this video|welcome to|log(?:in|ging in)|dashboard tour)\b/i.test(coldOpens[0].narration ?? "")) {
    fail("cold-open narration contains a banned preamble/login/tour opening.");
  }

  const heroSegments = episode.segments.filter((segment) => segment.heroMoment === true);
  if (heroSegments.length !== 1) fail("exactly one segment must be marked heroMoment=true.");
  const declaredHero = episode.heroMoment?.segmentId;
  if (!present(declaredHero) || !ids.has(declaredHero)) fail("heroMoment.segmentId must name a real segment.");
  if (heroSegments.length === 1 && declaredHero && heroSegments[0].id !== declaredHero) {
    fail("heroMoment.segmentId must match the segment marked heroMoment=true.");
  }
  for (const field of ["reveal", "staging"] ) {
    if (!present(episode.heroMoment?.[field])) fail(`heroMoment missing "${field}".`);
  }

  const before = episode.beforeState;
  if (!before || !ids.has(before.segmentId) || !present(before.costShown)) {
    fail("beforeState must name a real segment and describe the cost shown.");
  }
  if (typeof before?.durationSeconds !== "number" || before.durationSeconds < 3 || before.durationSeconds > 5) {
    fail("beforeState.durationSeconds must be between 3 and 5 seconds.");
  }

  const payoffSegments = episode.segments.filter((segment) => segment.payoff === true);
  if (payoffSegments.length !== 1) fail("exactly one segment must be marked payoff=true.");
  const payoff = payoffSegments[0];
  if (payoff && !PAYOFF_RUNGS.has(payoff.ladderRung)) {
    fail("the payoff segment must reach the outcome or identity WIIFM rung, not feature/functional-benefit.");
  }

  const starts = ordered.map((segment) => Number(segment.timelineStartSeconds));
  for (let index = 1; index < ordered.length; index++) {
    const gap = starts[index] - starts[index - 1];
    if (Number.isFinite(gap) && gap > 15 && ordered[index].attentionReset !== true) {
      fail(`${ordered[index].id}: ${gap}s since the prior beat without attentionReset=true.`);
    }
  }
  if (episode.segments.length > 1 && !episode.segments.some((segment, index) => index > 0 && segment.attentionReset === true)) {
    warn("no post-opening attention reset is declared; confirm the episode is shorter than 15 seconds.");
  }

  if (episode.problemSolvingOrAi === true && !episode.segments.some((segment) => segment.complexityTaste === true)) {
    fail("problem-solving/AI episodes need one segment marked complexityTaste=true.");
  }
  const endCards = episode.segments.filter((segment) => segment.endCard === true);
  if (endCards.length !== 1) fail("exactly one segment must be marked endCard=true.");
  const guardrails = episode.segments.filter((segment) => segment.guardrail === true);
  if (guardrails.length !== 1) fail("exactly one segment must be marked guardrail=true.");

  const beforeOrder = episode.segments.find((segment) => segment.id === before?.segmentId)?.order;
  const heroOrder = heroSegments[0]?.order;
  const payoffOrder = payoff?.order;
  if (
    Number.isFinite(beforeOrder) &&
    Number.isFinite(heroOrder) &&
    Number.isFinite(payoffOrder) &&
    !(beforeOrder < heroOrder && heroOrder <= payoffOrder)
  ) {
    fail("story order must be before-state -> hero moment -> payoff (hero and payoff may share one beat).");
  }
}

console.log(`\n${episodes.length} storyboard(s) checked: ${errors} error(s), ${warnings} warning(s).`);
process.exit(errors > 0 ? 1 : 0);
