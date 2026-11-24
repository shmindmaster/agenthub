import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { lintSpec } from '../kit/marketing/lib/lint.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';
import { creativeMode, inspectRepresentation } from '../kit/marketing/lib/creative-modes.mjs';

const schema = JSON.parse(readFileSync(new URL('../kit/marketing/ad.schema.json', import.meta.url), 'utf8'));
const io = { specDir: '/synthetic-film', exists: () => true, readText: () => 'approved',
  readJson: () => ({ clips: { C1: { valid: true, clipSeconds: 30, events: { clicks: 0 } } } }) };
const narr = { provider: 'openai', voiceId: 'alloy', model: 'gpt-realtime-2.1-mini', disclosure: 'end card' };
const truth = { id: 'proof', text: 'The operator can review the current result.', phrases: ['operator can review the current result'], evidence: 'approved:captured-product-workflow' };
const broll = (prompt, truthStatus = 'fictional', extra = {}) =>
  ({ id: 'synthetic-scene', kind: 'broll', truthStatus, narration: 'A vivid hypothetical day unfolds.',
     broll: { provider: 'openai-image', prompt, ...extra } });
const base = (creativeMode) => ({
  id: 'generic-film', title: 'A day in the future', product: 'The Envisioned Platform',
  creativeMode, audience: 'People imagining technology', objective: 'Inspire a future possibility',
  voice: narr, labels: 'Concept visualization', conceptDisclosure: 'This is an envisioned future',
  claims: [], cta: { text: 'Explore this possibility', url: 'https://example.com/story' },
  cuts: [{ id: 'main', ratios: ['9x16'], targetSeconds: 40, beats: [
    broll('An unblurred fictional child patient, family and clinician in a bright future clinic with readable imaginary planning dashboard.', 'proposed', { depictsProductUI: true,
      actor: { kind: 'fictional', role: 'child', ageGroup: 'child', name: 'Alex' } }),
    { id: 'final', kind: 'card', narration: 'Explore this possibility.' },
  ] }],
});
// Every form still has to say what it is. A story names a person, a situation
// and a change; a non-narrative piece states its organizing principle; a
// how-to or explainer has a beginning, a middle and an end.
const storyBrief = () => ({
  persona: 'a clinic coordinator in a near-future practice', situation: 'planning the next day of visits',
  emotionalBefore: 'unsure what tomorrow holds', emotionalAfter: 'calm and prepared for the day',
});
const threeBeats = (spec, roles) => {
  const [first, last] = spec.cuts[0].beats;
  spec.cuts[0].beats = [
    { ...first, storyRole: roles[0] },
    { ...first, id: 'middle', storyRole: roles[1], narration: 'The idea is shown one step at a time.' },
    { ...last, storyRole: roles[2] },
  ];
  return spec;
};
const validateSpec = spec => {
  const errors = validate(schema, spec);
  assert.deepEqual(errors, [], errors.join('\n'));
  return lintSpec(spec, {}, { io, adSchema: schema });
};

test('future vision: synthetic child patients and fully readable imagined UI need no blur, no real product capture', () => {
  const s = base('future-vision');
  s.narrative = storyBrief();
  const r = validateSpec(s);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
  assert.equal(r.errors.some(x => /people|patient|fake-ui|no-ui/.test(x.code)), false);
  // A fully specified treatment can carry the vision without a fixed emotional template.
  delete s.narrative;
  assert.equal(validateSpec(s).ok, true);
});

test('fictional day-in-the-life is free of age, healthcare and screen prohibitions', () => {
  const s = base('fictional-story');
  delete s.conceptDisclosure;
  s.labels = 'Film title treatment';
  s.cuts[0].beats[0].truthStatus = 'fictional';
  delete s.cuts[0].beats[0].broll.actor;
  s.narrative = storyBrief();
  const r = validateSpec(s);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
});

test('abstract and educational films need no six-beat story and no product UI', () => {
  const shape = {
    abstract: (s) => { s.organizingPrinciple = 'Colour and motion follow one working day from morning to night.'; },
    educational: (s) => { s.narrative = { goal: 'understand how the planning idea works' }; threeBeats(s, ['goal', 'step', 'payoff']); },
    explainer: (s) => { s.narrative = { question: 'What could planning look like?', viewerValue: 'see one possible workflow end to end' }; threeBeats(s, ['hook', 'explanation', 'takeaway']); },
  };
  for (const mode of ['abstract', 'educational', 'explainer']) {
    const s = base(mode);
    s.cuts[0].beats[0].truthStatus = 'illustrative';
    delete s.cuts[0].beats[0].broll.depictsProductUI;
    shape[mode](s);
    const r = validateSpec(s);
    assert.equal(r.ok, true, `${mode}: ${JSON.stringify(r.errors)}`);
    assert.equal(r.errors.some(e => /no-ui|proof-ui/.test(`${e.code} ${e.rule}`)), false);
  }
  // Declaring a looser mode is not a way out of having a shape at all.
  const bare = base('abstract');
  bare.cuts[0].beats[0].truthStatus = 'illustrative';
  assert.ok(validateSpec(bare).errors.some(e => e.rule === 'story.principle'));
});

test('fictional scenes are allowed around genuine verified-product footage', () => {
  const s = base('verified-demo');
  s.cuts[0].targetSeconds = 8; // short edit: only claim and picture integrity apply
  s.cuts[0].beats = [
    broll('A fictional family speaks to a realistic doctor in a busy clinic, no blur needed.', 'fictional'),
    { id: 'screen', kind: 'ui', truthStatus: 'verified', narration: 'The operator can review the current result.',
      claims: ['proof'], ui: { sourceJob: '/test/product', clipId: 'C1' } },
    { id: 'close', kind: 'card' }, // the disclosure is drawn on a closing card, so a cut must end on one
  ];
  s.claims = [truth];
  const r = validateSpec(s);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
});

test('hybrid shows real current UI and detailed proposed screens, with film-level concept clarity', () => {
  const s = base('hybrid');
  s.claims = [truth];
  s.filmType = 'story';
  s.narrative = storyBrief();
  s.cuts[0].beats.unshift({ id: 'current', kind: 'ui', truthStatus: 'verified',
    narration: 'The operator can review the current result.', claims: ['proof'],
    ui: { sourceJob: '/test/product', clipId: 'C1' } });
  const r = validateSpec(s);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
});

test('conceptual UI in a hybrid must be classified instead of being passed off as actual proof', () => {
  const s = base('hybrid');
  delete s.cuts[0].beats[0].truthStatus;
  const r = validateSpec(s);
  assert.ok(r.errors.some(e => e.code === 'representation'));
});

test('clearly envisioned film requires a concept indication but never a watermark or blur', () => {
  const s = base('future-vision');
  s.labels = 'Ordinary brand title';
  delete s.conceptDisclosure;
  const r = validateSpec(s);
  assert.ok(r.errors.some(e => e.code === 'concept-disclosure'));
});

test('verified-demo cannot present proposed capabilities as shipped', () => {
  const s = base('verified-demo');
  const result = inspectRepresentation(s, s.cuts[0]);
  assert.ok(result.some(e => e.code === 'representation'));
});

test('documentary factual assertions still need a source; reconstructions do not', () => {
  const s = base('documentary');
  s.narrative = { question: 'What happened, and why does it matter?', viewerValue: 'understand the event and its effect' };
  s.cuts[0].beats[0].storyRole = 'explanation';
  s.cuts[0].beats[1].storyRole = 'takeaway';
  s.cuts[0].beats.unshift({ id: 'real-claim', kind: 'card', truthStatus: 'verified', storyRole: 'hook',
    narration: 'This verified event occurred in 2020.' });
  const first = validateSpec(s);
  assert.ok(first.errors.some(e => e.code === 'claim-unmapped'));
  s.cuts[0].beats[0].truthStatus = 'fictional';
  const second = validateSpec(s);
  assert.equal(second.ok, true, JSON.stringify(second.errors));
});

test('mode defaults to current-product behavior only for legacy ads with no selected creativeMode', () => {
  assert.equal(creativeMode({}), 'verified-demo');
  assert.equal(creativeMode({ creativeMode: 'future-vision' }), 'future-vision');
});
