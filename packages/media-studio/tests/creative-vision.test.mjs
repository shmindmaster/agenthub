import test from 'node:test';
import assert from 'node:assert/strict';
import { buildInstructions, evaluate, parseVerdict } from '../kit/marketing/vision-qa.mjs';

const verdict = (issues, label = true) => parseVerdict(JSON.stringify({
  frames: [{ label: 'F01', issues }],
  overall: { labelPresentWhereRequired: label, summary: 'inspection complete' },
}));
const issue = (category, detail = 'visible') => ({
  category, severity: 'high', detail, evidence: 'F01 observable subject',
});

test('vision movie reviewer must not order blurring or ban realistic synthetic people and patients', () => {
  const text = buildInstructions({ spec: {
    product: 'Generic vision product', creativeMode: 'future-vision',
    conceptDisclosure: 'Envisioned future system',
    beats: [{ narration: 'A family uses tomorrow’s technology.' }],
  }, brand: {}, ratio: '9x16' });
  assert.match(text, /Synthetic people of any age/);
  assert.match(text, /patients, clinicians/);
  assert.match(text, /Never flag them merely for appearing/);
  assert.doesNotMatch(text, /Report people-or-children \(high\)/);
  assert.match(text, /no permanent watermark or blurring is required/);
});

test('vision movie with a family and an imagined screen does not fail simply because it is generated', () => {
  const spec = { creativeMode: 'future-vision', conceptDisclosure: 'Envisioned future platform' };
  const r = evaluate(verdict([
    issue('people-or-children', 'realistic fictional pediatric patient'),
    issue('fabricated-ui', 'readable designed future dashboard'),
  ]), { spec });
  assert.equal(r.ok, true, JSON.stringify(r.reasons));
  assert.equal(r.blocking, 0);
});

test('a fully fictional film does not need an unrequested disclosure watermark', () => {
  const r = evaluate(verdict([], false), { spec: { creativeMode: 'fictional-story' } });
  assert.equal(r.ok, true);
});

test('a future feature shown without clear film-level representation still needs reviewer attention', () => {
  const r = evaluate(verdict([], false), { spec: { creativeMode: 'future-vision' } });
  assert.equal(r.ok, false);
  assert.match(r.reasons.join(' '), /disclosure/);
});

test('verified present-day factual errors remain blocking', () => {
  const r = evaluate(verdict([issue('banned-claim', 'unsupported verified functionality')]), {
    spec: { creativeMode: 'verified-demo' },
  });
  assert.equal(r.ok, false);
  assert.equal(r.blocking, 1);
});
