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
    slots: ['explanation', 'takeaway'],
    narrative: ['question', 'viewerValue'],
    hookPlan: false, hookWords: null, named: null, proofSlot: null, contextBy: null,
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
    summary: 'Fiction, day-in-the-life or future vision. The brief determines the story and scene order.',
    slots: [],
    narrative: [],
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
  const profile = COMMUNICATION_PROFILES[cut?.communicationProfile || spec?.communicationProfile];
  const requested = cut?.filmType || spec?.filmType || profile?.filmType;
  const id = requested || DEFAULT_TYPE_BY_MODE[mode] || 'product-marketing';
  const base = FILM_TYPES[id];
  if (!base) return { id, unknown: true, rules: null };
  const seconds = Number(cut?.targetSeconds);
  const compact = base.compact && Number.isFinite(seconds) && seconds < base.compactBelow;
  return { id, unknown: false, compact: Boolean(compact), rules: compact ? { ...base, ...base.compact } : base };
}

// Communication profiles select existing film types; they do not select a
// creative mode or relax factual representation and capture requirements.
//
// The first three profiles prove product behaviour. The six engagement profiles
// below them are forms with their own ordered sections, so a brief declares each
// beat's `section` and the checks run against the profile's list. Fields:
//   ceilingSeconds   recommended runtime. Advisory: the brief's maxDurationSeconds governs.
//   sections         ordered; `optional` ones may be left out.
//   cadences         status-update only: a cut may narrow the list or the ceiling.
//   measuredNumbers  sections that always need a measured-benefit claim.
//   measuredIfNumber sections that need one only when they state a number.
//   sectionFields    fields a beat of that section must state.
//   oneAsk           at most one beat fills the cta or next-step role.
const engagement = (filmType, ceilingSeconds, sections, extra = {}) => ({ filmType, proofMoments: 0, ceilingSeconds, sections, ...extra });

export const COMMUNICATION_PROFILES = Object.freeze({
  'consulting-demo': { filmType: 'feature-demo', proofMoments: 3 },
  'technical-walkthrough': { filmType: 'tutorial', proofMoments: 1 },
  'product-update': { filmType: 'internal-update', proofMoments: 1 },
  pitch: engagement('founder-pitch', 180, ['recommendation', 'why-change', 'cost-of-inaction', 'new-way', 'why-us', 'options', 'ask'],
    { optional: ['options'], measuredIfNumber: ['cost-of-inaction'], oneAsk: true }),
  proposal: engagement('explainer', 300, ['recommendation', 'understanding', 'approach', 'team', 'timeline', 'options', 'investment', 'next-step'],
    { optional: ['options'], sectionFields: { investment: ['assumptions', 'exclusions'] }, oneAsk: true }),
  'status-update': engagement('internal-update', 120, ['status', 'done', 'next', 'risks', 'decisions', 'plan-vs-actual'],
    { cadences: { weekly: { ceilingSeconds: 90 }, steering: { sections: ['plan-vs-actual', 'risks', 'decisions', 'next'] } } }),
  kickoff: engagement('explainer', 240, ['objectives', 'scope', 'governance', 'team', 'timeline', 'risks', 'first-30-days']),
  'final-readout': engagement('explainer', 480, ['recommendation', 'findings', 'roadmap', 'business-case', 'next-step'], { oneAsk: true }),
  'value-review': engagement('explainer', 180, ['baseline', 'realized', 'evidence', 'next-step'],
    { measuredNumbers: ['baseline', 'realized'], oneAsk: true }),
});

const text = (value) => typeof value === 'string' && Boolean(value.trim());
const refs = (value) => Array.isArray(value) && value.length > 0 && value.every(text);

function inspectDecisionBrief(brief, cut, estimateSeconds, add) {
  for (const key of ['primaryAudience', 'viewerDecision', 'primaryTakeaway']) if (!text(brief[key])) add(`brief.${key}`, `${key} must state the audience, decision or answer.`);
  const context = brief.audienceContext;
  if (!['confirmed-discovery', 'hypothesis', 'fictional-scenario'].includes(context?.problemStatus)) add('problem-status', 'Declare confirmed-discovery, hypothesis or fictional-scenario.');
  if (context?.problemStatus === 'confirmed-discovery' && !refs(context.sourceRefs)) add('discovery-source', 'Confirmed discovery needs attributable sourceRefs.');
  if (!text(brief.nextStep?.action) || !brief.nextStep?.owner || !Object.hasOwn(brief.nextStep, 'agreedDate')) add('next-step', 'Declare one nextStep action, owner and agreedDate (null when none is agreed).');
  if (brief.nextStep?.agreedDate !== null && brief.nextStep?.agreedDate !== undefined && (!/^\d{4}-\d{2}-\d{2}$/.test(brief.nextStep.agreedDate) || !refs(brief.nextStep.sourceRefs))) add('commitment-source', 'An agreed date needs YYYY-MM-DD and sourceRefs; otherwise use null.');
  const ceiling = Number(brief.maxDurationSeconds);
  const duration = cut.beats.reduce((sum, b) => sum + estimateSeconds(b), 0);
  if (!Number.isFinite(ceiling) || ceiling <= 0) add('duration', 'The approved brief must supply maxDurationSeconds.');
  else if (Math.max(duration, Number(cut.targetSeconds) || 0) > ceiling) add('duration', 'Scene totals exceed the approved ceiling; revise the plan before voice generation.');
  if (!['selectable', 'open', 'sidecar'].includes(brief.captionPolicy?.mode) || !text(brief.captionPolicy?.deliverySurface)) add('captions', 'Choose captionPolicy mode and deliverySurface for this export.');
  if (!text(brief.audioDirection?.narratorIdentity) || !text(brief.audioDirection?.delivery) || !['none', 'restrained-bed', 'compare-bed-and-silence'].includes(brief.audioDirection?.musicTreatment)) add('audio-direction', 'Pin the narrator, delivery and music treatment; no music is a valid choice.');
}

function inspectEvidenceClaim(claim, b, context, add) {
  if (!text(claim.text) || !refs(claim.sourceRefs)) add('claim-source', 'Each claim needs text and sourceRefs.', b);
  if (!['product-behavior', 'measured-benefit', 'proposed-interface', 'customer-priority', 'illustrative-scenario'].includes(claim.scope)) add('claim-scope', 'Unknown claim evidence scope.', b);
  for (const [key, allowed] of Object.entries({ implementationState: ['implemented', 'proposed'], dataType: ['synthetic', 'customer', 'public'], aiExecutionMode: ['live', 'recorded', 'stubbed', 'none'], businessValidation: ['unvalidated', 'measured', 'discovery-confirmed'] })) {
    if (!allowed.includes(claim[key])) add('claim-dimensions', `Declare ${key} independently for every claim.`, b);
  }
  if (claim.scope === 'product-behavior' && (claim.implementationState !== 'implemented' || b.kind !== 'ui' || !['FACT', undefined].includes(b.truth))) add('product-proof', 'Product behavior requires implemented, factual product UI proof.', b);
  if (claim.scope === 'measured-benefit' && (claim.businessValidation !== 'measured' || claim.dataType === 'synthetic' || !['baseline', 'comparison', 'population', 'method', 'timeWindow'].every((key) => text(claim.measurement?.[key])))) add('measurement', 'Customer benefit needs non-synthetic measured baseline, comparison, population, method and timeWindow.', b);
  if (claim.scope === 'customer-priority' && (claim.businessValidation !== 'discovery-confirmed' || context?.problemStatus !== 'confirmed-discovery')) add('customer-priority', 'Customer priority requires attributable confirmed discovery.', b);
  if (['proposed-interface', 'illustrative-scenario'].includes(claim.scope) && !text(claim.visibleLabel)) add('visible-label', 'Proposed or illustrative content needs a visible label.', b);
  if (claim.scope === 'product-behavior') {
    for (const key of ['actor', 'object', 'action', 'systemResponse', 'result', 'significance']) if (!text(b.uiProof?.[key])) add('action-result', `uiProof.${key} must identify the visible causal chain.`, b);
  }
}

function inspectTakeaway(b, titles, context, add) {
  const title = String(b.actionTitle || '').trim();
  if (title.split(/\s+/).length < 4 || title.split(/\s+/).length > 18 || !/[.!?]$/.test(title)) add('action-title', 'Use a 4–18 word full-sentence takeaway title, separate from onScreen text.', b);
  if (titles.has(title.toLowerCase())) add('distinct-title', 'Each substantive scene needs a distinct conclusion.', b);
  titles.add(title.toLowerCase());
  if (!text(b.supportingArgument) || !refs(b.proofRefs)) add('argument-proof', 'Bind the supportingArgument and proofRefs to this takeaway.', b);
  if (!Array.isArray(b.evidenceClaims) || !b.evidenceClaims.length) add('claim-scope', 'Declare claims and their evidence scopes for each substantive scene.', b);
  for (const claim of b.evidenceClaims || []) inspectEvidenceClaim(claim, b, context, add);
}

function inspectIntegration(id, brief, add) {
  if (id === 'technical-walkthrough') {
    if (!text(brief.scenarioRecord) || !refs(brief.integrationFlow) || !['source', 'intake', 'transformation', 'rules-ai', 'human-decision', 'output', 'acknowledgment-or-exception'].every((step, i) => brief.integrationFlow[i] === step)) add('integration-flow', 'Follow one scenarioRecord through source, intake, transformation, rules-ai, human-decision, output, acknowledgment-or-exception.');
    if (!['demonstrated-adapter', 'file-import', 'proposed'].includes(brief.integrationStatus)) add('integration-status', 'Declare demonstrated-adapter, file-import or proposed; never imply a file upload is live sync.');
  }
}

const realDate = (value) => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
};

/** The overall status chip, its risks and its decisions. A green chip over an open problem is the case to catch. */
function inspectStatus(brief, add) {
  if (!['red', 'amber', 'green'].includes(brief.rag)) add('status.rag', 'Declare the overall rag as red, amber or green.');
  if (!realDate(brief.ragSince)) add('status.rag-since', 'Declare ragSince (YYYY-MM-DD): the date the status last changed.');
  if (!realDate(brief.statusDate)) add('status.status-date', 'Declare statusDate (YYYY-MM-DD): the day this update reports on.');
  const risks = Array.isArray(brief.risks) ? brief.risks : null;
  const decisions = Array.isArray(brief.decisions) ? brief.decisions : null;
  if (!risks) add('status.risks', 'Declare risks as a list; an empty list says there are none.');
  if (!decisions) add('status.decisions', 'Declare decisions as a list; an empty list says none are needed.');
  for (const [i, risk] of (risks || []).entries()) {
    if (!['description', 'owner', 'impact', 'mitigation'].every((key) => text(risk?.[key]))) add('status.risk-fields', `Risk ${i + 1} needs a description, owner, impact and mitigation.`);
  }
  for (const [i, decision] of (decisions || []).entries()) {
    if (!text(decision?.decision) || !text(decision?.owner) || !decision || !Object.hasOwn(decision, 'dueDate')) add('status.decision-fields', `Decision ${i + 1} needs the decision, an owner and a dueDate (null when none is agreed).`);
    else if (decision.dueDate !== null && decision.dueDate !== undefined && (!realDate(decision.dueDate) || !refs(decision.sourceRefs))) add('status.decision-date', `Decision ${i + 1}: an agreed dueDate needs YYYY-MM-DD and sourceRefs; otherwise use null.`);
  }
  if (brief.rag !== 'green') return;
  const unowned = (risks || []).some((risk) => !text(risk?.owner));
  const overdue = realDate(brief.statusDate) && (decisions || []).some((d) => realDate(d?.dueDate) && d.dueDate < brief.statusDate);
  if (unowned || overdue) add('status.green-with-open-issues', `Status is green, but ${unowned ? 'a risk has no owner' : 'a decision is overdue'}. Show amber or red, or fix the record.`);
}

const NUMBER = /[0-9]|(two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|dozens?|hundreds?|thousands?|millions?|billions?|twice|double[sd]?|triple[sd]?|half|halve[sd]?|quarter|third|percent)/i;
const statesNumber = (b) => NUMBER.test(['narration', 'voice', 'actionTitle', 'supportingArgument', 'onScreen', 'onScreenText', 'title', 'text'].map((key) => (typeof b[key] === 'string' ? b[key] : '')).join(' '));

/** Sections, options and the one-ask rule for the engagement profiles. */
function inspectEngagement(id, profile, brief, cut, add) {
  let sections = profile.sections;
  if (profile.cadences && brief.cadence !== undefined) {
    const cadence = profile.cadences[brief.cadence];
    if (cadence) sections = cadence.sections || sections;
    else add('cadence', `Unknown cadence: ${brief.cadence}. Use ${Object.keys(profile.cadences).join(' or ')}.`);
  }
  const optional = new Set(profile.optional || []);
  const beats = cut.beats;
  if (beats.length && beats[0].section !== sections[0]) add('section.first', `Open on the ${sections[0]} section: the first beat declares section "${sections[0]}".`, beats[0]);
  let at = -1;
  for (const b of beats) {
    if (b.section === undefined) continue;
    const index = sections.indexOf(b.section);
    if (index < 0) add('section.unknown', `Unknown section "${b.section}" for ${id}. Use one of: ${sections.join(', ')}.`, b);
    else if (index < at) add('section.order', `Section "${b.section}" comes after "${sections[at]}". Order for ${id}: ${sections.join(' > ')}.`, b);
    else at = index;
  }
  for (const section of sections) {
    if (!optional.has(section) && !beats.some((b) => b.section === section)) add('section.missing', `Add the "${section}" section: a beat with section "${section}".`);
  }
  for (const b of beats.filter((beat) => beat.section === 'options')) {
    const options = b.options;
    if (!Array.isArray(options) || options.length < 2 || options.length > 3) add('options.count', 'Show two or three options.', b);
    else {
      if (options.filter((o) => o?.recommended === true).length !== 1) add('options.recommended', 'Mark exactly one option as recommended.', b);
      if (!options.every((o) => text(o?.label))) add('options.label', 'Give every option a label.', b);
    }
  }
  for (const [section, fields] of Object.entries(profile.sectionFields || {})) {
    for (const b of beats.filter((beat) => beat.section === section)) {
      for (const field of fields) if (!refs(b[field])) add('section-fields', `The ${section} scene must state ${field} as a list of short statements.`, b);
    }
  }
  for (const section of [...(profile.measuredNumbers || []), ...(profile.measuredIfNumber || [])]) {
    const always = profile.measuredNumbers?.includes(section);
    for (const b of beats.filter((beat) => beat.section === section && (always || statesNumber(beat)))) {
      if (!b.evidenceClaims?.some((c) => c.scope === 'measured-benefit')) add('measured-number', `The ${section} scene shows a number, so it needs a measured-benefit claim with its source and measurement.`, b);
    }
  }
  const asks = beats.filter((b) => rolesOf(b).some((r) => ['cta', 'next-step'].includes(r)));
  if (profile.oneAsk && asks.length > 1) add('one-ask', 'One ask per video: keep one cta or next-step beat. A second ask belongs in a second video.', asks[1]);
}

/** Planning checks shared by the pre-capture gate and marketing lint. */
export function inspectCommunication(spec, cut, estimateSeconds) {
  const id = cut.communicationProfile || spec.communicationProfile;
  if (!id) return [];
  const findings = [];
  const add = (rule, message, beat) => findings.push({ code: 'communication', rule: `communication.${rule}`, message, where: beat ? `${cut.id}/${beat.id}` : cut.id });
  const profile = COMMUNICATION_PROFILES[id];
  if (!profile) { add('profile', `Unknown communicationProfile: ${id}`); return findings; }
  const brief = { ...spec, ...cut };
  inspectDecisionBrief(brief, cut, estimateSeconds, add);
  const substantive = cut.beats.filter((b) => !rolesOf(b).some((r) => ['hook', 'cta', 'next-step'].includes(r)));
  const titles = new Set();
  for (const b of substantive) inspectTakeaway(b, titles, brief.audienceContext, add);
  const moments = substantive.filter((b) => b.evidenceClaims?.some((c) => c.scope === 'product-behavior'));
  if (new Set(moments.map((b) => (b.proofRefs || []).join('|'))).size < profile.proofMoments) add('proof-moments', `This profile needs ${profile.proofMoments} distinct product proof moment(s).`);
  if (!refs(brief.limitations)) add('limitations', 'Retain explicit limitations in every cut, including short variants.');
  inspectIntegration(id, brief, add);
  if (profile.sections) inspectEngagement(id, profile, brief, cut, add);
  if (id === 'status-update') inspectStatus(brief, add);
  return findings;
}
