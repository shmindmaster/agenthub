// Creative modes keep a reusable media studio from becoming a single-product
// demo-only pipeline. Classify the truth status of each portrayal, not whether
// a human, patient, clinic, UI, or futuristic scene happens to appear in a prompt.
export const CREATIVE_MODES = Object.freeze([
  'verified-demo', 'hybrid', 'future-vision', 'concept-film',
  'fictional-story', 'explainer', 'documentary', 'educational', 'abstract',
]);
export const VISION_MODES = new Set(['future-vision', 'concept-film']);
export const FLEXIBLE_MODES = new Set(CREATIVE_MODES.filter(x => x !== 'verified-demo'));
export const CONCEPT_STATUSES = new Set(['proposed', 'fictional', 'illustrative']);
export const REALITY_STATUSES = new Set(['verified', ...CONCEPT_STATUSES]);
// A disclosure has to say the thing is not current fact. Bare "vision" or "future" is not that: both are ordinary
// marketing words and one is part of a product name.
export const DECLARATION = /\b(concept(?:ual)?|proposed|envision(?:ed|ing)?|illustrative|fiction(?:al)?|dramati[sz](?:ation|ed)|simulat(?:ion|ed)|prototype|imagined|future vision|not (?:a |yet )?(?:current|available|shipped)|coming soon)\b/i;

/** Modes whose whole premise is invented. */
export const INVENTED_MODES = new Set(['fictional-story', 'future-vision', 'concept-film', 'abstract']);

const cleanText = (v) => String(v || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
/**
 * Does the text name the product? A one-word name must appear with a capital
 * first letter, as a name is written, so a product called "Linear" is not
 * found in "growth is rarely linear". A longer name is matched without case.
 */
export function mentions(text, names) {
  const raw = String(text || '');
  const flat = ` ${cleanText(raw)} `;
  return (names || []).some((name) => {
    const n = cleanText(name);
    if (!n) return false;
    if (n.includes(' ')) return flat.includes(` ${n} `);
    const pattern = new RegExp(`(^|[^A-Za-z0-9])(${n})(?![A-Za-z0-9])`, 'gi');
    for (const match of raw.matchAll(pattern)) if (/^[A-Z]/.test(match[2])) return true;
    return false;
  });
}

/**
 * Does this beat state something as true today? Factual beats need evidence
 * and are held to the claim policies; invented ones are not.
 *
 * A film cannot leave this rule by picking another creativeMode: a captured
 * interface is always a statement about the product, and so is a line that
 * names the product, unless the beat is classified as proposed, fictional or
 * illustrative.
 */
export function beatIsFactual(beat = {}, mode = 'verified-demo', names = []) {
  // Captured interface is the product as it is. No label turns it into fiction.
  if (beat.kind === 'ui') return true;
  if (beat.truthStatus === 'verified') return true;
  // "Proposed" is a claim about the future and is covered by the concept disclosure.
  if (beat.truthStatus === 'proposed') return false;
  const named = mentions(`${beat.narration || ''} ${beat.onScreenText || ''} ${beat.actionTitle || ''}`, names);
  // A scene may be fictional or illustrative. A sentence about what the product does is not made so by a label.
  if (CONCEPT_STATUSES.has(beat.truthStatus)) return named && !INVENTED_MODES.has(mode);
  if (mode === 'verified-demo') return true;
  if (INVENTED_MODES.has(mode)) return false;
  return named;
}

export function creativeMode(spec = {}) {
  if (CREATIVE_MODES.includes(spec.creativeMode)) return spec.creativeMode;
  if (!spec.creativeMode && !spec.product) {
    if (spec.filmType === 'explainer') return 'explainer';
    if (spec.filmType === 'story') return 'fictional-story';
    if (spec.filmType === 'non-narrative') return 'abstract';
  }
  return 'verified-demo';
}

export function conceptBeat(beat = {}) {
  return CONCEPT_STATUSES.has(beat.truthStatus);
}

export function isConceptPresentation(spec = {}, cut = {}) {
  const mode = creativeMode(spec);
  // Any film that shows proposed capability is presenting a concept, whatever mode it declares.
  return VISION_MODES.has(mode) || (mode === 'hybrid' && (cut.beats || []).some(conceptBeat))
    || (cut.beats || []).some((b) => b.truthStatus === 'proposed');
}

// An existing customer-facing product demo is kept strict by default, but a
// concept scene is allowed when the parent mode and representation are explicit.
export function inspectRepresentation(spec, cut, names = []) {
  const errors = [];
  const add = (code, message, where = cut.id) => errors.push({ code, message, where });
  const mode = creativeMode(spec);
  if (spec.creativeMode && !CREATIVE_MODES.includes(spec.creativeMode)) {
    add('creative-mode', `unknown creativeMode: ${spec.creativeMode}`);
  }
  const beats = Array.isArray(cut.beats) ? cut.beats : [];
  for (const beat of beats) {
    const at = `${cut.id}/${beat.id || '?'}`;
    if (beat.truthStatus && !REALITY_STATUSES.has(beat.truthStatus)) {
      add('truth-status', `unknown truthStatus: ${beat.truthStatus}`, at);
    }
    if (beat.kind === 'ui' && CONCEPT_STATUSES.has(beat.truthStatus)) {
      add('representation', `A captured product interface is a statement about the product today and cannot be classified ${beat.truthStatus}. Use a generated shot for an imagined screen, or leave the capture as verified with its evidence.`, at);
    }
    if (mode === 'verified-demo' && beat.truthStatus === 'proposed') {
      add('representation', 'Proposed product functionality is not proof of current behavior: select hybrid, future-vision or concept-film and disclose the distinction. Fictional or illustrative context shots are allowed within verified demos.', at);
    }
  }
  if (isConceptPresentation(spec, cut)) {
    const label = [spec.conceptDisclosure, spec.labels].filter(Boolean).join(' ');
    if (!DECLARATION.test(label)) {
      add('concept-disclosure', 'A film presenting future or proposed product capabilities needs an accurate concept/future-vision disclosure; no permanent watermark or blurring is required.');
    }
  }
  if (INVENTED_MODES.has(mode) && !isConceptPresentation(spec, cut) && names.length
      && beats.some((b) => !b.truthStatus && mentions(`${b.narration || ''} ${b.onScreenText || ''} ${b.actionTitle || ''}`, names))) {
    const label = [spec.conceptDisclosure, spec.labels].filter(Boolean).join(' ');
    if (!DECLARATION.test(label)) {
      add('concept-disclosure', 'This invented film names the product. Say that it is fiction or a concept (conceptDisclosure or labels), or classify the beats that describe what the product does today as verified and give them evidence.');
    }
  }
  if (mode === 'hybrid' && beats.some(b => b.kind === 'broll' && b.broll?.depictsProductUI && !conceptBeat(b))) {
    add('representation', 'Hybrid films must classify generated concept interfaces as proposed, fictional or illustrative; real current-product proof must come from verified capture.');
  }
  return errors;
}
