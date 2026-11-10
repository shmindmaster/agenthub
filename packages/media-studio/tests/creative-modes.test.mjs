import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { lintSpec } from '../kit/marketing/lib/lint.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';
import { creativeMode, inspectRepresentation } from '../kit/marketing/lib/creative-modes.mjs';

const schema = JSON.parse(readFileSync(new URL('../kit/marketing/ad.schema.json', import.meta.url), 'utf8'));
const io = { specDir: '/synthetic-film', exists: () => true, readText: () => 'approved',
  readJson: () => ({ clips: { C1: { valid: true, clipSeconds: 30, events: { clicks: 0 } } } }) };
const narr = { provider: 'openai', voiceId: 'alloy', model: 'gpt-4o-mini-tts', disclosure: 'end card' };
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
const validateSpec = spec => {
  const errors = validate(schema, spec);
  assert.deepEqual(errors, [], errors.join('\n'));
  return lintSpec(spec, {}, { io, adSchema: schema });
};

test('future vision: synthetic child patients and fully readable imagined UI need no blur, no real product capture', () => {
  const s = base('future-vision');
  const r = validateSpec(s);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
  assert.equal(r.errors.some(x => /people|patient|fake-ui|no-ui/.test(x.code)), false);
});

test('fictional day-in-the-life is free of age, healthcare and screen prohibitions', () => {
  const s = base('fictional-story');
  s.conceptDisclosure = undefined;
  s.labels = 'Film title treatment';
  s.cuts[0].beats[0].truthStatus = 'fictional';
  delete s.cuts[0].beats[0].broll.actor;
  const r = validateSpec(s);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
});

test('abstract and educational films need no six-beat story and no product UI', () => {
  for (const mode of ['abstract', 'educational', 'explainer']) {
    const s = base(mode);
    s.cuts[0].beats[0].truthStatus = 'illustrative';
    delete s.cuts[0].beats[0].broll.depictsProductUI;
    const r = validateSpec(s);
    assert.equal(r.ok, true, JSON.stringify(r.errors));
  }
});

test('fictional scenes are allowed around genuine verified-product footage', () => {
  const s = base('verified-demo');
  s.cuts[0].targetSeconds = 8; // short edit: only claim and picture integrity apply
  s.cuts[0].beats = [
    broll('A fictional family speaks to a realistic doctor in a busy clinic, no blur needed.', 'fictional'),
    { id: 'screen', kind: 'ui', truthStatus: 'verified', narration: 'The operator can review the current result.',
      claims: ['proof'], ui: { sourceJob: '/test/product', clipId: 'C1' } },
  ];
  s.claims = [truth];
  const r = validateSpec(s);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
});

test('hybrid shows real current UI and detailed proposed screens, with film-level concept clarity', () => {
  const s = base('hybrid');
  s.claims = [truth];
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
  s.cuts[0].beats.unshift({ id: 'real-claim', kind: 'card', truthStatus: 'verified',
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
