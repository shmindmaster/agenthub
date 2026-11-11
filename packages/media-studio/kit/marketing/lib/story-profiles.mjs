// Story rules keyed by film type. A film is judged by the roles its own form
// needs: a tutorial is not failed for lacking a call to action, and a product
// marketing film is not excused from setting a scene because it is short.
//
// Nothing here names a product. Product name, aliases, disclosure and claim
// policy come from the spec and the product's brand file.

/** Canonical story roles. A beat's storyRole may be any of these or an alias below. */
export const ROLES = Object.freeze([
  'hook', 'context', 'problem', 'solution', 'demonstration', 'proof', 'payoff', 'cta',
  'goal', 'step', 'explanation', 'takeaway', 'recap', 'next-step',
]);

/**
 * Other names people write for the same role, including the seven-role wording
 * used in planning documents ("problem and stakes", "product introduction",
 * "call to action"). A value maps to one or two canonical roles.
 */
export const ROLE_ALIASES = Object.freeze({
  'context-problem': ['context', 'problem'],
  scenario: ['context'], setup: ['context'], 'who-and-where': ['context'],
  'problem-stakes': ['problem'], 'problem-and-stakes': ['problem'], stakes: ['problem'], obstacle: ['problem'],
  'product-introduction': ['solution'], 'product-intro': ['solution'], introduction: ['solution'], intro: ['solution'],
  demo: ['demonstration'], mechanism: ['demonstration'], walkthrough: ['demonstration'],
  evidence: ['proof'], traction: ['proof'],
  result: ['payoff'], outcome: ['payoff'],
  'call-to-action': ['cta'], close: ['cta'], ask: ['cta'],
  task: ['goal'], objective: ['goal'],
  steps: ['step'],
  summary: ['recap'],
  next: ['next-step'], 'next-steps': ['next-step'],
});

const norm = (value) => String(value ?? '').trim().toLowerCase().replace(/[\s_]+/g, '-').replace(/-&-|-and-(?=stakes)/g, '-and-');

/** Canonical roles a beat fills; empty when it has none or the value is unknown. */
export function rolesOf(beat) {
  const raw = norm(beat?.storyRole);
  if (!raw) return [];
  if (ROLES.includes(raw)) return [raw];
  return ROLE_ALIASES[raw] ? [...ROLE_ALIASES[raw]] : [];
}

export const isKnownRole = (value) => { const raw = norm(value); return ROLES.includes(raw) || Boolean(ROLE_ALIASES[raw]); };

/** Field aliases, so a planning document's wording validates without renaming. */
export const NARRATIVE_ALIASES = Object.freeze({
  persona: ['persona', 'person', 'who', 'audiencePersona'],
  situation: ['situation', 'scenario', 'moment', 'where'],
  trigger: ['trigger', 'whatGoesWrong', 'incitingEvent'],
  problem: ['problem', 'obstacle'],
  stakes: ['stakes', 'whyItMatters'],
  solution: ['solution', 'productIntroduction'],
  mechanism: ['mechanism', 'demonstration', 'how'],
  payoff: ['payoff', 'result', 'outcome'],
  emotionalBefore: ['emotionalBefore', 'beforeState', 'feelingBefore'],
  emotionalAfter: ['emotionalAfter', 'afterState', 'feelingAfter'],
  viewerValue: ['viewerValue', 'usefulPayoff', 'value', 'takeaway'],
  goal: ['goal', 'task', 'learningGoal'],
  question: ['question', 'viewerQuestion'],
  ask: ['ask', 'callToAction'],
  change: ['change', 'whatChanged'],
});
export const HOOK_ALIASES = Object.freeze({
  visual: ['visual', 'firstVisual', 'firstImage', 'image'],
  onScreen: ['onScreen', 'onScreenText', 'text'],
  spoken: ['spoken', 'spokenLine', 'line', 'voice'],
  viewerQuestion: ['viewerQuestion', 'question', 'whyCare'],
});

/** First present alias of `field` on `object`. */
export function pick(object, field, aliases) {
  for (const key of aliases[field] || [field]) if (object && object[key] !== undefined && object[key] !== null) return object[key];
  return undefined;
}

/**
 * One film type.
 *   slots       ordered roles the film must contain, each after the one before it
 *   first       role the opening beat must fill (omit for forms with no hook rule)
 *   last        role the final beat must fill (omit when the film may end on its result)
 *   narrative   brief fields that must be stated before production
 *   hookPlan    whether the first picture, on-screen text and spoken line are planned together
 *   hookWords   word limit of the first spoken sentence
 *   named       where the product must be named: a slot, 'early' (first two beats) or null
 *   proofSlot   slot that must be real captured interface when the film claims current behaviour
 *   contextBy   seconds by which the scene must be set
 *   compact     overrides for a cut shorter than compactBelow seconds
 */
export const FILM_TYPES = Object.freeze({
  'product-marketing': {
    summary: 'Viewer-facing film that sells running software: scene, problem, the product by name, proof, a changed result, one ask.',
    slots: ['hook', 'context', 'problem', 'solution', 'demonstration', 'payoff', 'cta'],
    first: 'hook', last: 'cta',
    narrative: ['persona', 'situation', 'trigger', 'problem', 'stakes', 'solution', 'mechanism', 'payoff', 'emotionalBefore', 'emotionalAfter', 'viewerValue'],
    hookPlan: true, hookWords: 12, named: 'solution', proofSlot: 'demonstration', contextBy: 10,
    compactBelow: 25,
    compact: { slots: ['hook', 'demonstration', 'cta'], narrative: [], hookPlan: false, named: 'early', contextBy: null },
  },
  'feature-demo': {
    summary: 'Screencast of one capability for someone already interested: the task, the product doing it, the result.',
    slots: ['context', 'demonstration', 'payoff'],
    narrative: ['persona', 'problem', 'payoff'],
    hookPlan: false, hookWords: 18, named: 'early', proofSlot: 'demonstration', contextBy: 10,
  },
  tutorial: {
    summary: 'How-to: the goal, the steps in order, the finished result.',
    slots: ['goal', 'step', 'payoff'],
    first: 'goal',
    narrative: ['goal'],
    hookPlan: false, hookWords: 20, named: null, proofSlot: null, contextBy: null,
  },
  explainer: {
    summary: 'Explains an idea, change or rule; may show no product interface at all.',
    slots: ['hook', 'explanation', 'takeaway'],
    first: 'hook',
    narrative: ['question', 'viewerValue'],
    hookPlan: false, hookWords: 16, named: null, proofSlot: null, contextBy: null,
  },
  'social-cut': {
    summary: 'Short feed cut: a hook, one piece of proof, and a result or an ask.',
    slots: ['hook', 'demonstration'],
    first: 'hook', endsWith: ['payoff', 'cta'],
    narrative: [],
    hookPlan: false, hookWords: 12, named: 'early', proofSlot: 'demonstration', contextBy: null,
  },
  'founder-pitch': {
    summary: 'Founder or pitch piece: the problem, the answer by name, evidence, the ask.',
    slots: ['hook', 'problem', 'solution', 'proof', 'cta'],
    first: 'hook', last: 'cta',
    narrative: ['problem', 'solution', 'ask'],
    hookPlan: false, hookWords: 16, named: 'solution', proofSlot: null, contextBy: null,
  },
  'internal-update': {
    summary: 'Update for people who already know the product: what changed, the evidence, what happens next.',
    slots: ['context', 'demonstration', 'next-step'],
    narrative: ['change'],
    hookPlan: false, hookWords: 24, named: null, proofSlot: null, contextBy: null,
  },
  story: {
    summary: 'Fiction, day-in-the-life or future vision: a person, a situation and a change. Scene order is free.',
    slots: [],
    narrative: ['persona', 'situation', 'emotionalBefore', 'emotionalAfter'],
    hookPlan: false, hookWords: null, named: null, proofSlot: null, contextBy: null,
  },
  'non-narrative': {
    summary: 'Abstract, ambient, montage or reference piece with a stated organizing principle instead of a story.',
    slots: [],
    narrative: [],
    requiresPrinciple: true,
    hookPlan: false, hookWords: null, named: null, proofSlot: null, contextBy: null,
  },
});

/** A slot may be filled by any of these roles. */
export const SLOT_ROLES = Object.freeze({
  demonstration: ['demonstration', 'proof'],
  proof: ['proof', 'demonstration'],
  payoff: ['payoff', 'recap'],
  takeaway: ['takeaway', 'payoff', 'recap'],
  explanation: ['explanation', 'context', 'demonstration'],
  step: ['step', 'demonstration'],
  goal: ['goal', 'hook', 'context'],
  context: ['context', 'goal'],
  'next-step': ['next-step', 'cta'],
});
export const fills = (slot) => SLOT_ROLES[slot] || [slot];

/** The film type a creative mode implies when the spec does not name one. */
export const DEFAULT_TYPE_BY_MODE = Object.freeze({
  'verified-demo': 'product-marketing',
  hybrid: 'product-marketing',
  explainer: 'explainer',
  educational: 'tutorial',
  documentary: 'explainer',
  'fictional-story': 'story',
  'future-vision': 'story',
  'concept-film': 'story',
  abstract: 'non-narrative',
});

/**
 * Resolve a cut's film type and the rules that apply to it. A cut may set its
 * own filmType, which is how a 20-second social cut of a marketing film is
 * judged as a social cut.
 */
export function resolveFilmType(spec, cut, mode) {
  const requested = cut?.filmType || spec?.filmType;
  const id = requested || DEFAULT_TYPE_BY_MODE[mode] || 'product-marketing';
  const base = FILM_TYPES[id];
  if (!base) return { id, unknown: true, rules: null };
  const seconds = Number(cut?.targetSeconds);
  const compact = base.compact && Number.isFinite(seconds) && seconds < base.compactBelow;
  return { id, unknown: false, compact: Boolean(compact), rules: compact ? { ...base, ...base.compact } : base };
}
