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
      for (const field of ["kind", "target", "cursorBehavior", "timing", "clickCue"]) {
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
