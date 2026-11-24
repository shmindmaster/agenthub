import { creativeMode, inspectRepresentation } from './creative-modes.mjs';
import { FILM_TYPES, HOOK_ALIASES, NARRATIVE_ALIASES, fills, isKnownRole, pick, resolveFilmType, rolesOf, inspectCommunication } from './story-profiles.mjs';

// Structural story gate. Runs before any paid media call.
//
// It checks that a film's plan has the parts its own form needs, in an order a
// first-time viewer can follow. It is not a review of the finished film: the
// encoded-file critic still judges whether the scene, the mechanism and the
// result are actually understandable on screen.
//
// Every finding carries a stable `rule` id. A spec may waive a story rule with
// a recorded reason (spec.storyOverrides); the finding is then returned with
// `waived` set and the caller logs it instead of failing. Truth and evidence
// rules are not story rules and cannot be waived here.

const words = (v) => String(v || '').trim().split(/\s+/).filter(Boolean);
const clean = (v) => String(v || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const meaningful = (v) => words(v).length >= 2 && !/^(?:tbd|n\/a|placeholder|todo|unknown|lorem)\b/i.test(String(v).trim());
/** The first sentence, split on sentence ends and not on the dot in "$1.5" or "Dr.". */
const firstSentence = (v) => String(v || '').trim().split(/(?<=[.!?])\s+(?=[A-Z0-9"'“(])/)[0] || '';
const beatText = (beat) => `${beat?.narration || ''} ${beat?.onScreenText || ''} ${beat?.actionTitle || ''}`;

/** Every name the product may be introduced by: the spec's, plus the brand file's spoken or written variants. */
export function productNames(spec, brand) {
  return [...new Set([spec?.product, brand?.product, ...(brand?.productNames || [])].map(clean).filter(Boolean))];
}
const namesProduct = (text, names) => { const t = ` ${clean(text)} `; return names.some((n) => t.includes(` ${n} `)); };

/** Waivers a spec declares: rule id (or a `prefix.*`) to reason. */
export function storyOverrides(spec, cut) {
  const list = [...(Array.isArray(spec?.storyOverrides) ? spec.storyOverrides : []), ...(Array.isArray(cut?.storyOverrides) ? cut.storyOverrides : [])];
  return list.filter((o) => o && typeof o === 'object');
}
const overrideFor = (overrides, rule) => overrides.find((o) => o.rule === rule || (typeof o.rule === 'string' && o.rule.endsWith('.*') && rule.startsWith(o.rule.slice(0, -1))));

/**
 * @param {object} spec Complete film specification.
 * @param {object} cut One normalized cut.
 * @param {function} estimateBeatSeconds Timing estimate for one beat.
 * @param {{brand?: object}} [options] The product's brand file, for its name variants.
 * @returns {Array<{code:string,rule:string,message:string,where:string,waived?:string}>}
 */
export function inspectNarrativeArc(spec, cut, estimateBeatSeconds, options = {}) {
  const findings = inspectRepresentation(spec, cut, productNames(spec, options.brand)).map((f) => ({ rule: `truth.${f.code}`, ...f }));
  findings.push(...inspectCommunication(spec, cut, estimateBeatSeconds));
  const mode = creativeMode(spec, cut);
  const overrides = storyOverrides(spec, cut);
  const add = (rule, message, where = cut.id) => findings.push({ code: 'narrative-arc', rule: `story.${rule}`, message, where });
  const finish = () => {
    for (const o of overrides) {
      if (typeof o.rule !== 'string' || !o.rule.startsWith('story.')) {
        findings.push({ code: 'story-override', rule: 'override.scope', message: `storyOverrides can waive story rules only (story.*); "${o.rule}" is not one. Truth and evidence rules are never waived.`, where: cut.id });
      } else if (!meaningful(o.reason) || words(o.reason).length < 4) {
        findings.push({ code: 'story-override', rule: 'override.reason', message: `The override of ${o.rule} needs a reason a reviewer can weigh (who decided and why), not a placeholder.`, where: cut.id });
      }
    }
    return findings.map((f) => {
      if (!f.rule.startsWith('story.')) return f;
      const o = overrideFor(overrides, f.rule);
      return o && meaningful(o.reason) && words(o.reason).length >= 4 ? { ...f, waived: String(o.reason) } : f;
    });
  };

  // Judge the film by how long it will really run: a "24 second" cut that estimates at 28 is not a teaser.
  const estimated = typeof estimateBeatSeconds === 'function' && Array.isArray(cut.beats) ? cut.beats.reduce((sum, b) => sum + estimateBeatSeconds(b), 0) : 0;
  const duration = Math.max(Number(cut.targetSeconds) || 0, estimated);
  const type = resolveFilmType(spec, { ...cut, targetSeconds: duration || cut.targetSeconds }, mode);
  if (type.unknown) {
    findings.push({ code: 'film-type', rule: 'film.type', message: `unknown filmType "${type.id}". Use one of: ${Object.keys(FILM_TYPES).join(', ')}.`, where: cut.id });
    return finish();
  }
  const rules = type.rules;
  // A bumper under ten seconds has room for one idea and keeps only the ordinary gates.
  if (duration > 0 && duration < 10) return finish();
  const beats = Array.isArray(cut.beats) ? cut.beats : [];
  const names = productNames(spec, options.brand);
  const productLabel = spec.product || options.brand?.product || 'the product';

  if (rules.requiresPrinciple && !meaningful(cut.organizingPrinciple || spec.organizingPrinciple)) {
    add('principle', 'A non-narrative film must state its organizingPrinciple (what orders the shots and what the viewer should leave with), so a montage is a decision and not an accident.');
  }

  const narrative = cut.narrative || spec.narrative;
  const marketing = type.id === 'product-marketing';
  const teaser = marketing && type.compact;

  if (teaser) {
    // A 10 to 24 second cut has no room for a full arc but cannot be a random montage.
    if (beats.length < 2) add('teaser.shape', 'A 10–24s teaser needs a hook, real product evidence and a final CTA; a single unrelated clip is not a story.');
    const first = beats[0];
    const last = beats.at(-1);
    if (!rolesOf(first).includes('hook')) add('hook-first', 'A teaser must open with a pain/outcome hook.', `${cut.id}/${first?.id || 'opening'}`);
    if (!rolesOf(last).includes('cta')) add('cta-last', 'A teaser must finish with a clear CTA.', `${cut.id}/${last?.id || 'ending'}`);
    const proof = beats.slice(0, -1).some((b) => b.kind === 'ui' && rolesOf(b).some((r) => ['hook', 'demonstration', 'proof', 'payoff'].includes(r)));
    if (!proof && mode === 'verified-demo') add('proof-ui', 'A teaser about running software needs at least one genuine receipt-bound product UI proof beat before the CTA.');
    const earlyText = beats.slice(0, Math.min(2, beats.length)).map(beatText).join(' ');
    if (names.length && !namesProduct(earlyText, names)) add('product-named', `Identify ${productLabel} in the early teaser, spoken or on screen; do not reveal the software only after the demonstration.`);
    if (rolesOf(last).includes('cta') && clean(spec.cta?.text) && !clean(beatText(last)).includes(clean(spec.cta.text))) {
      add('cta-text', 'Teaser last beat must carry the approved CTA text.', `${cut.id}/${last.id}`);
    }
    return finish();
  }

  // The brief: what must be decided before anything is captured or generated.
  if (rules.narrative.length) {
    if (!narrative || typeof narrative !== 'object' || Array.isArray(narrative)) {
      add('narrative', marketing
        ? 'A 25s+ cut needs narrative { persona, situation, trigger, problem, stakes, solution, mechanism, payoff } before production.'
        : `A ${type.id} film needs narrative { ${rules.narrative.join(', ')} } before production.`);
    } else {
      for (const field of rules.narrative) {
        if (!meaningful(pick(narrative, field, NARRATIVE_ALIASES))) add(`narrative.${field}`, `narrative.${field} must state a concrete ${field}, not an empty label.`);
      }
      const before = pick(narrative, 'emotionalBefore', NARRATIVE_ALIASES);
      const after = pick(narrative, 'emotionalAfter', NARRATIVE_ALIASES);
      if (meaningful(before) && meaningful(after) && clean(before) === clean(after)) {
        add('narrative.change', 'The emotional before-state and after-state must differ; show what changed for the viewer.');
      }
    }
  }
  const hookPlan = cut.hookPlan || spec.hookPlan;
  const planned = (field) => pick(hookPlan, field, HOOK_ALIASES);
  if (rules.hookPlan) {
    if (!hookPlan || typeof hookPlan !== 'object' || Array.isArray(hookPlan)) {
      add('hook-plan', 'The first five seconds need hookPlan { visual, onScreen, spoken, viewerQuestion } so picture, text and voice establish a shared reason to watch.');
    } else {
      const muted = !String((Array.isArray(cut.beats) ? cut.beats[0] : null)?.narration || '').trim();
      for (const field of Object.keys(HOOK_ALIASES)) {
        if (field === 'spoken' && muted && meaningful(planned('onScreen'))) continue; // a muted opening is carried by its text
        if (!meaningful(planned(field))) add(`hook-plan.${field}`, `hookPlan.${field} must describe its own clear opening component.`);
      }
    }
  }

  if (!beats.length) { add('beats', 'Cut has no beats.'); return finish(); }
  if (!rules.slots.length && !rules.first && !rules.last) return finish(); // free-order forms
  for (const beat of beats) {
    if (!isKnownRole(beat.storyRole)) add('role', `Beat ${beat.id} needs a valid storyRole (${marketing ? 'hook, context, problem, context-problem, solution, demonstration, proof, payoff, cta' : [...new Set(rules.slots.flatMap(fills))].join(', ') || 'see check-story --types'}).`, `${cut.id}/${beat.id}`);
  }
  const indexOfSlot = (slot, from = 0) => beats.findIndex((b, i) => i >= from && rolesOf(b).some((r) => fills(slot).includes(r)));
  const opening = beats[0];
  const lastBeat = beats.at(-1);

  if (rules.first && !rolesOf(opening).some((r) => fills(rules.first).includes(r))) {
    add(rules.first === 'hook' ? 'hook-first' : 'opening', rules.first === 'hook'
      ? 'The first beat must be a story hook (pain or payoff), not an unexplained UI or logo.'
      : `A ${type.id} film opens by stating its ${rules.first}.`, `${cut.id}/${opening.id}`);
  }
  if (rules.hookWords) {
    const hookLine = firstSentence(opening.narration || opening.onScreenText);
    if (words(hookLine).length > rules.hookWords) {
      add('hook-length', rules.hookWords === 12
        ? 'First hook sentence exceeds 12 words (approximately five seconds at 150 wpm).'
        : `The opening sentence exceeds ${rules.hookWords} words; say the point of the film first.`, `${cut.id}/${opening.id}`);
    }
  }
  if (rules.first === 'hook' && words(opening.narration || opening.onScreenText).length < 3) add('hook-substance', 'Opening hook must convey a concrete pain or payoff.', `${cut.id}/${opening.id}`);
  // A hook may be spoken or, for a feed that plays muted, carried by on-screen text alone.
  const openingSpoken = clean(opening.narration || '');
  const hookMatches = openingSpoken
    ? openingSpoken.startsWith(clean(planned('spoken')))
    : clean(opening.onScreenText || '').startsWith(clean(planned('onScreen'))) && Boolean(clean(planned('onScreen')));
  if (rules.hookPlan && (meaningful(planned('spoken')) || !openingSpoken) && hookPlan && !hookMatches) {
    add('hook-plan.match', 'The hookPlan spoken line must match the actual beginning of the first narration beat; a proposed hook alone is not a rendered hook.', `${cut.id}/${opening.id}`);
  }

  if (marketing) {
    const at = (slot) => indexOfSlot(slot);
    const context = at('context');
    const problem = at('problem');
    const solution = at('solution');
    // The demonstration that counts is the first one after the product is introduced.
    const demonstration = solution >= 0 ? indexOfSlot('demonstration', solution + 1) : at('demonstration');
    const payoff = beats.findIndex((b) => rolesOf(b).includes('payoff'));
    const cta = beats.findIndex((b) => rolesOf(b).includes('cta'));
    if (context < 1) add('context', 'Show who/where the scenario is about after the hook and before the solution (context or context-problem beat).');
    if (problem < 1) add('problem', 'Show a specific problem or obstacle, not a feature list (problem or context-problem beat).');
    if (solution < 1) add('solution', 'Introduce the named software as the answer to that problem (solution beat).');
    if (context > 0 && problem > 0 && solution > 0 && (context >= solution || problem >= solution)) add('order', 'Scenario and problem must precede the software solution.');
    if (demonstration < 1) add('demonstration', 'Demonstrate the mechanism after the software introduction (demonstration or proof beat).');
    if (mode === 'verified-demo' && demonstration >= 0 && !beats.slice(demonstration, payoff > demonstration ? payoff : undefined).some((b) => rolesOf(b).some((r) => ['demonstration', 'proof'].includes(r)) && b.kind === 'ui')) {
      add('proof-ui', 'A product mechanism/proof beat must show actual captured product UI, not just a title or b-roll.');
    }
    if (payoff < 1 || (demonstration >= 0 && payoff <= demonstration)) add('payoff', 'Show a changed outcome after the demonstration (payoff beat).');
    if (cta < 1 || cta !== beats.length - 1 || (payoff >= 0 && cta <= payoff)) add('cta-last', 'End with one CTA after the payoff, not a sudden cutoff.');
    if (cta >= 0 && clean(spec.cta?.text) && !clean(beatText(beats[cta])).includes(clean(spec.cta.text))) {
      add('cta-text', 'The last beat must carry the approved CTA text: do not switch to another ask at the end.', `${cut.id}/${beats[cta].id}`);
    }
    if (beats.filter((b) => rolesOf(b).includes('cta')).length > 1) add('cta-single', 'One call to action per film; a second ask dilutes the first.');
    if (context > 0 && typeof estimateBeatSeconds === 'function' && rules.contextBy) {
      const contextAt = beats.slice(0, context).reduce((sum, b) => sum + estimateBeatSeconds(b), 0);
      if (contextAt > rules.contextBy) add('context-late', `The scene/context starts around ${contextAt.toFixed(1)}s; ground the viewer within ten seconds.`);
    }
    if (context >= 0 && words(beats[context].narration || beats[context].onScreenText).length < 5) {
      add('context-substance', 'The context beat needs a real, intelligible scenario line.', `${cut.id}/${beats[context].id}`);
    }
    if (solution >= 0 && names.length && !namesProduct(beatText(beats[solution]), names)) {
      add('product-named', `Introduce ${productLabel} by name in the solution beat, spoken or on screen.`, `${cut.id}/${beats[solution].id}`);
    }
    if (payoff >= 0 && words(beats[payoff].narration || beats[payoff].onScreenText).length < 4) {
      add('payoff-substance', 'The payoff must explicitly describe the changed result, not another random screen.', `${cut.id}/${beats[payoff].id}`);
    }
    return finish();
  }

  // Every other film type: its slots, in order.
  let cursor = 0;
  const found = {};
  for (const slot of rules.slots) {
    const index = indexOfSlot(slot, cursor);
    if (index < 0) {
      const anywhere = indexOfSlot(slot) >= 0;
      add(anywhere ? 'order' : slot, anywhere
        ? `In a ${type.id} film the ${slot} comes after the ${rules.slots[rules.slots.indexOf(slot) - 1]}; reorder the beats or declare the form that fits.`
        : `A ${type.id} film needs a ${slot} beat (storyRole ${fills(slot).join(' or ')}). ${FILM_TYPES[type.id].summary}`);
    } else { found[slot] = index; cursor = index; } // the same beat may fill two slots (context-problem)
  }
  if (rules.last && !rolesOf(lastBeat).some((r) => fills(rules.last).includes(r))) add('cta-last', `A ${type.id} film ends on its ${rules.last === 'cta' ? 'one call to action' : rules.last}.`, `${cut.id}/${lastBeat.id}`);
  if (rules.endsWith && !rolesOf(lastBeat).some((r) => rules.endsWith.includes(r))) add('ending', `A ${type.id} film ends on a result or an ask (${rules.endsWith.join(' or ')}), not mid-demonstration.`, `${cut.id}/${lastBeat.id}`);
  if (beats.filter((b) => rolesOf(b).includes('cta')).length > 1) add('cta-single', 'One call to action per film; a second ask dilutes the first.');
  if (rolesOf(lastBeat).includes('cta') && clean(spec.cta?.text) && !clean(beatText(lastBeat)).includes(clean(spec.cta.text))) {
    add('cta-text', 'The last beat must carry the approved CTA text: do not switch to another ask at the end.', `${cut.id}/${lastBeat.id}`);
  }
  if (rules.named && names.length) {
    const where = rules.named === 'early' ? beats.slice(0, Math.min(2, beats.length)) : (found[rules.named] !== undefined ? [beats[found[rules.named]]] : []);
    if (where.length && !namesProduct(where.map(beatText).join(' '), names)) {
      add('product-named', rules.named === 'early'
        ? `Name ${productLabel} in the first two beats, spoken or on screen, so the viewer knows what they are looking at.`
        : `Introduce ${productLabel} by name in the ${rules.named} beat, spoken or on screen.`);
    }
  }
  if (rules.proofSlot && mode === 'verified-demo' && found[rules.proofSlot] !== undefined
      && !beats.some((b) => b.kind === 'ui' && rolesOf(b).some((r) => fills(rules.proofSlot).includes(r)))) {
    add('proof-ui', 'A product mechanism/proof beat must show actual captured product UI, not just a title or b-roll.');
  }
  if (rules.contextBy && found.context > 0 && typeof estimateBeatSeconds === 'function') {
    const contextAt = beats.slice(0, found.context).reduce((sum, b) => sum + estimateBeatSeconds(b), 0);
    if (contextAt > rules.contextBy) add('context-late', `The scene/context starts around ${contextAt.toFixed(1)}s; ground the viewer within ten seconds.`);
  }
  return finish();
}

/** A one-screen description of what a film type requires, for a planner or a failed-gate message. */
export function describeFilmType(id) {
  const t = FILM_TYPES[id];
  if (!t) return null;
  return { id, summary: t.summary, slots: t.slots, opensWith: t.first || null, endsWith: t.last || t.endsWith || null, briefFields: t.narrative, hookPlan: t.hookPlan, firstSentenceWords: t.hookWords, productNamed: t.named, compactBelowSeconds: t.compactBelow || null };
}
