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
export const DECLARATION = /\b(concept(?:ual)?|proposed|future|envision(?:ed|ing)?|illustrat(?:ion|ive)|fiction(?:al)?|dramatiz(?:ation|ed)|simulation|prototype|imagined|vision)\b/i;

export function creativeMode(spec = {}) {
  return CREATIVE_MODES.includes(spec.creativeMode) ? spec.creativeMode : 'verified-demo';
}

export function conceptBeat(beat = {}) {
  return CONCEPT_STATUSES.has(beat.truthStatus);
}

export function isConceptPresentation(spec = {}, cut = {}) {
  const mode = creativeMode(spec);
  return VISION_MODES.has(mode) || (mode === 'hybrid' && (cut.beats || []).some(conceptBeat));
}

// An existing customer-facing product demo is kept strict by default, but a
// concept scene is allowed when the parent mode and representation are explicit.
export function inspectRepresentation(spec, cut) {
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
    if (mode === 'verified-demo' && conceptBeat(beat)) {
      add('representation', 'Conceptual, dramatized or fictional beats require hybrid, future-vision, fictional-story, or another explicit creativeMode; default verified-demo promises current-function proof.', at);
    }
  }
  if (isConceptPresentation(spec, cut)) {
    const label = [spec.conceptDisclosure, spec.labels].filter(Boolean).join(' ');
    if (!DECLARATION.test(label)) {
      add('concept-disclosure', 'A film presenting future or proposed product capabilities needs an accurate concept/future-vision disclosure; no permanent watermark or blurring is required.');
    }
  }
  if (mode === 'hybrid' && beats.some(b => (b.kind === 'broll' && b.truthStatus !== 'verified') && b.broll?.depictsProductUI && !conceptBeat(b))) {
    add('representation', 'Hybrid films need truthStatus proposed|fictional|illustrative on generated concept UI; do not imply it is the current working product.');
  }
  return errors;
}
