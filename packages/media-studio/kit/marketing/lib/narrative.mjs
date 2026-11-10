// Structural story gate for viewer-facing marketing cuts. Runs before any paid media calls.
// This is not a semantic/cinematic review: the encoded-file critic still judges whether
// the stated scenario, software mechanism and payoff are actually understandable on screen.
const REQUIRED = ['persona', 'situation', 'trigger', 'problem', 'stakes', 'solution', 'mechanism', 'payoff', 'emotionalBefore', 'emotionalAfter', 'viewerValue'];
const HOOK_COMPONENTS = ['visual', 'onScreen', 'spoken', 'viewerQuestion'];
const ROLES = new Set(['hook', 'context', 'problem', 'context-problem', 'solution', 'demonstration', 'proof', 'payoff', 'cta']);
const words = (v) => String(v || '').trim().split(/\s+/).filter(Boolean);
const clean = (v) => String(v || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const meaningful = (v) => words(v).length >= 2 && !/^(?:tbd|n\/a|placeholder|todo|unknown)$/i.test(String(v).trim());

/**
 * A longer marketing cut must be a causal, intelligible mini-story, not a list
 * of unconnected captured screens. A deliberately short (<25s) bumper remains
 * eligible for a compressed hook -> proof -> action format.
 *
 * @param {object} spec Complete ad specification.
 * @param {object} cut One normalized cut.
 * @param {function} estimateBeatSeconds Existing marketing timing estimate.
 * @returns {Array<{code:string,message:string,where:string}>}
 */
export function inspectNarrativeArc(spec, cut, estimateBeatSeconds) {
  const duration = Number(cut.targetSeconds);
  if (!(duration >= 10)) return []; // <10s micro-bumpers still have ordinary claim/readiness gates
  const errors = [];
  const add = (message, where = cut.id) => errors.push({ code: 'narrative-arc', message, where });
  const beats = Array.isArray(cut.beats) ? cut.beats : [];
  if (duration < 25) {
    // A 10–24s teaser has no time for a full narrative but cannot be
    // a random montage. Hook → one real UI proof → next action.
    if (beats.length < 2) add('A 10–24s teaser needs a hook, real product evidence and a final CTA; a single unrelated clip is not a story.');
    const first = beats[0];
    const last = beats.at(-1);
    if (first?.storyRole !== 'hook') add('A teaser must open with a pain/outcome hook.', `${cut.id}/${first?.id || 'opening'}`);
    if (last?.storyRole !== 'cta') add('A teaser must finish with a clear CTA.', `${cut.id}/${last?.id || 'ending'}`);
    const proof = beats.slice(0, -1).some(b => b.kind === 'ui' && ['hook','demonstration','proof','payoff'].includes(b.storyRole));
    if (!proof) add('A teaser about running software needs at least one genuine receipt-bound product UI proof beat before the CTA.');
    const earlyText = beats.slice(0, Math.min(2, beats.length)).map(b => `${b.narration || ''} ${b.onScreenText || ''}`).join(' ');
    if (clean(spec.product) && !clean(earlyText).includes(clean(spec.product))) {
      add(`Identify ${spec.product} in the early teaser, spoken or on screen; do not reveal the software only after the demonstration.`);
    }
    if (last?.storyRole === 'cta' && clean(spec.cta?.text) && !clean(`${last.narration || ''} ${last.onScreenText || ''}`).includes(clean(spec.cta.text))) {
      add('Teaser last beat must carry the approved CTA text.', `${cut.id}/${last.id}`);
    }
    return errors;
  }
  const narrative = cut.narrative || spec.narrative;
  if (!narrative || typeof narrative !== 'object' || Array.isArray(narrative)) {
    add('A 25s+ cut needs narrative { persona, situation, trigger, problem, stakes, solution, mechanism, payoff } before production.');
  } else {
    for (const field of REQUIRED) if (!meaningful(narrative[field])) add(`narrative.${field} must state a concrete ${field}, not an empty label.`);
    if (meaningful(narrative.emotionalBefore) && meaningful(narrative.emotionalAfter) && clean(narrative.emotionalBefore) === clean(narrative.emotionalAfter)) {
      add('The emotional before-state and after-state must differ; show what changed for the viewer.');
    }
  }
  const hookPlan = cut.hookPlan || spec.hookPlan;
  if (!hookPlan || typeof hookPlan !== 'object' || Array.isArray(hookPlan)) {
    add('The first five seconds need hookPlan { visual, onScreen, spoken, viewerQuestion } so picture, text and voice establish a shared reason to watch.');
  } else {
    for (const field of HOOK_COMPONENTS) if (!meaningful(hookPlan[field])) add(`hookPlan.${field} must describe its own clear opening component.`);
  }

  if (!beats.length) { add('Cut has no beats.'); return errors; }
  for (const beat of beats) {
    if (!ROLES.has(beat.storyRole)) add(`Beat ${beat.id} needs a valid storyRole (hook, context, problem, context-problem, solution, demonstration, proof, payoff, cta).`, `${cut.id}/${beat.id}`);
  }
  const first = (role) => beats.findIndex((b) => b.storyRole === role);
  const firstAny = (...roles) => beats.findIndex((b) => roles.includes(b.storyRole));
  const opening = beats[0];
  if (opening.storyRole !== 'hook') add('The first beat must be a story hook (pain or payoff), not an unexplained UI or logo.', `${cut.id}/${opening.id}`);
  const hookLine = String(opening.narration || opening.onScreenText || '').split(/[.!?]/)[0];
  if (words(hookLine).length > 12) add('First hook sentence exceeds 12 words (approximately five seconds at 150 wpm).', `${cut.id}/${opening.id}`);
  if (words(opening.narration || opening.onScreenText).length < 3) add('Opening hook must convey a concrete pain or payoff.', `${cut.id}/${opening.id}`);
  if (meaningful(hookPlan?.spoken) && !clean(opening.narration || '').startsWith(clean(hookPlan.spoken))) {
    add('The hookPlan spoken line must match the actual beginning of the first narration beat; a proposed hook alone is not a rendered hook.', `${cut.id}/${opening.id}`);
  }

  const context = firstAny('context', 'context-problem');
  const problem = firstAny('problem', 'context-problem');
  const solution = first('solution');
  const demonstration = firstAny('demonstration', 'proof');
  const payoff = first('payoff');
  const cta = first('cta');
  if (context < 1) add('Show who/where the scenario is about after the hook and before the solution (context or context-problem beat).');
  if (problem < 1) add('Show a specific problem or obstacle, not a feature list (problem or context-problem beat).');
  if (solution < 1) add('Introduce the named software as the answer to that problem (solution beat).');
  if (context > 0 && problem > 0 && solution > 0 && (context >= solution || problem >= solution)) add('Scenario and problem must precede the software solution.');
  if (demonstration < 1 || (solution >= 0 && demonstration <= solution)) add('Demonstrate the mechanism after the software introduction (demonstration or proof beat).');
  if (demonstration >= 0 && !beats.slice(demonstration, payoff >= 0 ? payoff : undefined).some((b) => ['demonstration', 'proof'].includes(b.storyRole) && b.kind === 'ui')) {
    add('A product mechanism/proof beat must show actual captured product UI, not just a title or b-roll.');
  }
  if (payoff < 1 || (demonstration >= 0 && payoff <= demonstration)) add('Show a changed outcome after the demonstration (payoff beat).');
  if (cta < 1 || cta !== beats.length - 1 || (payoff >= 0 && cta <= payoff)) add('End with one CTA after the payoff, not a sudden cutoff.');
  if (cta >= 0 && clean(spec.cta?.text) && !clean(`${beats[cta].narration || ''} ${beats[cta].onScreenText || ''}`).includes(clean(spec.cta.text))) {
    add('The last beat must carry the approved CTA text: do not switch to another ask at the end.', `${cut.id}/${beats[cta].id}`);
  }

  if (context > 0 && typeof estimateBeatSeconds === 'function') {
    const contextAt = beats.slice(0, context).reduce((sum, b) => sum + estimateBeatSeconds(b), 0);
    if (contextAt > 10) add(`The scene/context starts around ${contextAt.toFixed(1)}s; ground the viewer within ten seconds.`);
  }
  if (context >= 0 && words(beats[context].narration || beats[context].onScreenText).length < 5) {
    add('The context beat needs a real, intelligible scenario line.', `${cut.id}/${beats[context].id}`);
  }
  if (solution >= 0 && clean(spec.product) && !clean(`${beats[solution].narration || ''} ${beats[solution].onScreenText || ''}`).includes(clean(spec.product))) {
    add(`Introduce ${spec.product} by name in the solution beat, spoken or on screen.`, `${cut.id}/${beats[solution].id}`);
  }
  if (payoff >= 0 && words(beats[payoff].narration || beats[payoff].onScreenText).length < 4) {
    add('The payoff must explicitly describe the changed result, not another random screen.', `${cut.id}/${beats[payoff].id}`);
  }
  return errors;
}
