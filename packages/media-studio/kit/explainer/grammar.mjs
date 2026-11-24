/**
 * The shot grammar: which archetype renders as which composition family, what
 * that family needs, and the film-level rules a storyboard is held to.
 *
 * This file exists because the previous kit declared 22 archetypes and the
 * renderer read exactly one of them (`quote-problem`). A storyboard could say
 * `diagram-build` and still get the generic slide. Here every declared
 * archetype resolves to a family that actually composes the frame.
 */

/** Composition families. One renderer each; `tier` is the default size rung. */
export const FAMILIES = {
  statement: {
    tier: 'xl',
    chrome: 'minimal',
    light: 'behind',
    maxBeats: 3,
    cap: 0.4,
    visual: 'optional',
    kinds: ['hero', 'lower-third'],
    note: 'Type is the picture. No card, no rule, no scene number.',
  },
  number: {
    tier: 'xl',
    chrome: 'minimal',
    light: 'behind',
    maxBeats: 2,
    cap: 0.2,
    visual: 'required',
    kinds: ['stat'],
    note: 'One number owns the frame; the label sits under it, not beside it.',
  },
  contrast: {
    tier: 'l',
    chrome: 'full',
    light: 'seam',
    maxBeats: 8,
    cap: 0.25,
    visual: 'required',
    kinds: ['split', 'beforeafter'],
    note: 'A seam divides two states; the lit side is the answer.',
  },
  mechanism: {
    tier: 'l',
    chrome: 'full',
    light: 'hero',
    maxBeats: 10,
    cap: 0.45,
    visual: 'required',
    kinds: ['flow', 'map', 'svg', 'sequence'],
    note: 'The diagram is the picture: full-bleed, nodes land on their words.',
  },
  layers: {
    tier: 'l',
    chrome: 'full',
    light: 'hero',
    maxBeats: 6,
    cap: 0.2,
    visual: 'required',
    kinds: ['layers'],
    note: 'A stack rises; the active layer lifts and takes the light.',
  },
  timeline: {
    tier: 'l',
    chrome: 'full',
    light: 'rail',
    maxBeats: 6,
    cap: 0.2,
    visual: 'required',
    kinds: ['timeline'],
    note: 'One rail, events dropping on their beats, a playhead with the voice.',
  },
  evidence: {
    tier: 'm',
    chrome: 'full',
    light: 'hero',
    maxBeats: 8,
    cap: 0.3,
    visual: 'required',
    kinds: ['proof', 'table', 'code', 'chart', 'sidecar'],
    note: 'Claim above, evidence large below, source in the footer.',
  },
  quote: {
    tier: 'l',
    chrome: 'none',
    light: 'behind',
    maxBeats: 3,
    cap: 0.2,
    visual: 'required',
    kinds: ['quote'],
    note: 'One sentence, no furniture. Attribution small and low.',
  },
  checklist: {
    tier: 'm',
    chrome: 'full',
    light: 'hero',
    maxBeats: 6,
    cap: 0.2,
    visual: 'required',
    kinds: ['checklist'],
    note: 'Items land one at a time; a drawn check per item.',
  },
  media: {
    tier: 'xl',
    chrome: 'minimal',
    light: 'none',
    maxBeats: 4,
    cap: 0.35,
    visual: 'required',
    kinds: ['still', 'broll', 'screen-in-context'],
    note: 'The picture bleeds; text lives in a scrim, never on a card.',
  },
  sting: {
    tier: 'xl',
    chrome: 'none',
    light: 'behind',
    maxBeats: 1,
    cap: 0.1,
    visual: 'required',
    kinds: ['lottie', 'hero'],
    note: 'A mark, a beat of motion, gone.',
  },
  chapter: {
    tier: 'xl',
    chrome: 'none',
    light: 'behind',
    maxBeats: 1,
    cap: 0.08,
    visual: 'optional',
    kinds: ['chapter'],
    note: 'Number and label; two seconds; the progress bar ticks over.',
  },
  end: {
    tier: 'xl',
    chrome: 'minimal',
    light: 'behind',
    maxBeats: 2,
    cap: 0.1,
    visual: 'optional',
    kinds: ['cta'],
    note: 'One call to action, one line under it, nothing else.',
  },
};

/**
 * Every id in kit/scene-archetypes.json, mapped to the family that renders it.
 * `lower-third` and `speaker-slide` are the only ids whose family is not
 * obvious from the name: both are type-led frames, not a second media format.
 */
export const ARCHETYPE_FAMILY = {
  'cold-open': 'statement',
  'full-bleed-broll': 'media',
  'kinetic-statement': 'statement',
  'kinetic-number': 'number',
  'before-after': 'contrast',
  comparison: 'contrast',
  'diagram-build': 'mechanism',
  timeline: 'timeline',
  'process-flow': 'mechanism',
  'screen-in-context': 'media',
  'talking-head-sidecar': 'media',
  'quote-problem': 'quote',
  'evidence-proof': 'evidence',
  'checklist-build': 'checklist',
  'hero-reveal': 'statement',
  'cta-end-frame': 'end',
  'chapter-card': 'chapter',
  'lower-third': 'statement',
  'speaker-slide': 'evidence',
  'data-chart': 'evidence',
  'drawn-mechanism': 'mechanism',
  'motion-sting': 'sting',
};

/** Film-level numbers the builder and the release gate share. */
export const RULES = {
  minShotSeconds: 1.5,
  maxShotSeconds: 12,
  minHoldSeconds: 1.0,
  firstBeatMaxSeconds: 0.6,
  heroMaxSeconds: 2.0,
  maxStatementShare: 0.35,
  minChapterSeconds: 45,
  maxChapters: 6,
  minTierPerChapter: ['l', 'xl'],
  maxStaticRunSeconds: 2.5,
  minInkCoverage: 0.02,
  minLumaStd: 14,
  cutsPerSecondMin: 1 / 8,
  maxCaptionWords: 7,
  maxCaptionLines: 2,
  maxCaptionLineChars: 42,
};

/**
 * One archetype may be polyglot in the catalogue: `diagram-build` may carry a
 * flow, a layers stack or a system map (kit/scene-archetypes.json). The kind
 * decides the composition, because a stack lit as layers and a flow lit as a
 * diagram are not the same picture. Without this table `layers` was reachable
 * by no plan at all while the doctrine still offered it.
 */
export const ARCHETYPE_KIND_FAMILY = {
  'cold-open': { broll: 'media', still: 'media' },
  'diagram-build': { layers: 'layers' },
  'talking-head-sidecar': { sidecar: 'evidence' },
};

/**
 * Composition family for a shot. Pass the visual kind when there is one: an
 * archetype that can carry more than one kind resolves by kind first, then by
 * its default family. A one-argument call keeps the default route.
 */
export const familyOf = (archetype, kind) =>
  (kind && ARCHETYPE_KIND_FAMILY[archetype]?.[kind]) ?? ARCHETYPE_FAMILY[archetype] ?? null;

export const familySpec = (family) => {
  const found = FAMILIES[family];
  if (!found) throw new Error(`unknown family "${family}"`);
  return found;
};

/** Visual kinds a family accepts; an empty list means type alone is the picture. */
export const kindsOf = (family) => familySpec(family).kinds;

export const allowedArchetypes = () => Object.keys(ARCHETYPE_FAMILY);

/**
 * Structural validation of one shot. Timing rules that need the resolved beat
 * clock live in the builder/gate, which pass the derived numbers in.
 *
 * @returns {{rule: string, message: string}[]}
 */
// The renderer activates a beat at its nearest local frame.
export const beatFitsShot = (seconds, fps, durationFrames) =>
  Number.isFinite(seconds) && seconds >= 0 && Math.round(seconds * fps) < durationFrames;

export const validateShot = (shot, context = {}) => {
  const problems = [];
  const fail = (rule, message) => problems.push({ rule, message, shotId: shot?.id });
  if (!shot || typeof shot !== 'object') {
    fail('shot-shape', 'shot is not an object');
    return problems;
  }
  const family = familyOf(shot.archetype, shot.visual?.kind);
  if (!family) {
    fail('archetype-known', `unknown archetype "${shot.archetype}"`);
    return problems;
  }
  const spec = familySpec(family);
  const kind = shot.visual?.kind;
  const needs = spec.kinds;

  if (spec.visual === 'required' && !kind) {
    fail('visual-required', `${shot.archetype} (${family}) needs a visual of kind ${needs.join(', ')}`);
  } else if (kind && !needs.length) {
    // A type-only family drew its picture from type alone. Accepting a visual
    // here dropped it silently: the shot validated and the frame showed text.
    fail('visual-kind', `${shot.archetype} (${family}) is type-only and cannot carry a "${kind}" visual`);
  } else if (kind && !needs.includes(kind)) {
    fail('visual-kind', `${shot.archetype} (${family}) cannot render visual kind "${kind}"`);
  }
  if (shot.archetype === 'chapter-card' && !shot.title && !shot.visual?.title) {
    fail('chapter-label', 'chapter-card needs a title or visual.title');
  }
  if (shot.archetype === 'cta-end-frame' && !shot.visual?.next && !shot.title) {
    fail('cta-text', 'cta-end-frame needs visual.next or a title');
  }
  const beats = Array.isArray(shot.beats) ? shot.beats.length : 0;
  if (beats > spec.maxBeats) {
    fail('beat-budget', `${shot.archetype} allows ${spec.maxBeats} beats, got ${beats}`);
  }
  const style = context.advisory ?? fail;
  if (typeof shot.durationSeconds === 'number') {
    if (shot.durationSeconds < RULES.minShotSeconds) {
      style('shot-min', `${shot.durationSeconds.toFixed(2)}s is under the ${RULES.minShotSeconds}s floor`);
    }
    if (shot.durationSeconds > RULES.maxShotSeconds && !shot.longShotReason) {
      style('shot-max', `${shot.durationSeconds.toFixed(2)}s is over the ${RULES.maxShotSeconds}s ceiling with no longShotReason`);
    }
  }
  const previousFamily = context.previousFamily;
  if (previousFamily === family && !shot.repeatIsPoint) {
    style('no-consecutive-repeat', `${shot.archetype} repeats ${family} with no repeatIsPoint`);
  }
  return problems;
};

/**
 * Film-level structural rules. Timing checks that need the clock are in the
 * gate; this is what can be judged from the shot list alone.
 */
export const validateFilm = (shots) => {
  const problems = [];
  const fail = (rule, message, shotId) => problems.push({ rule, message, shotId });
  if (!Array.isArray(shots) || !shots.length) {
    fail('film-empty', 'a film needs at least one shot');
    return problems;
  }
  let previousFamily = null;
  shots.forEach((shot) => {
    for (const problem of validateShot(shot, { previousFamily })) problems.push(problem);
    previousFamily = familyOf(shot.archetype, shot.visual?.kind);
  });
  const typeOnly = shots.filter((shot) => ['statement', 'quote', 'number'].includes(familyOf(shot.archetype, shot.visual?.kind))).length;
  if (typeOnly / shots.length > RULES.maxStatementShare) {
    fail(
      'type-only-cap',
      `${typeOnly}/${shots.length} shots are type-only; the cap is ${Math.round(RULES.maxStatementShare * 100)}%`,
    );
  }
  return problems;
};
