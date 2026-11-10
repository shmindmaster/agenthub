import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectNarrativeArc } from '../kit/marketing/lib/narrative.mjs';
import { estimateBeatSeconds, lintSpec } from '../kit/marketing/lib/lint.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';
import { readFileSync } from 'node:fs';

const outline = () => ({
  persona: 'an ABA clinic coordinator',
  situation: 'preparing the next day of sessions',
  trigger: 'an authorization changes overnight',
  problem: 'a scheduled visit may lack valid authorization',
  stakes: 'the clinic needs to catch problems before sessions begin',
  solution: 'ABACare highlights the authorization status in the workflow',
  mechanism: 'staff reviews the flagged visit and relevant authorization details',
  payoff: 'the coordinator knows which visit needs attention',
  emotionalBefore: 'uncertain whether tomorrow is ready',
  emotionalAfter: 'confident about what needs follow-up',
  viewerValue: 'identify authorization issues before a visit starts',
});
const hookPlan = () => ({
  visual: 'An at-risk scheduled visit, visibly highlighted in the real product.',
  onScreen: 'Tomorrow booked; authorization needs attention.',
  spoken: 'Tomorrow is booked.',
  viewerQuestion: 'Which visit needs review before tomorrow?',
  alternatives: [
    { angle: 'problem', visual: 'A scheduled visit with an authorization warning.', spoken: 'A missing authorization can disrupt tomorrow.' },
    { angle: 'payoff', visual: 'One visit is visibly flagged for attention.', spoken: 'Spot the visit that needs attention.' },
  ],
  selectionReason: 'A familiar morning schedule earns immediate relevance.',
});
const brief = () => ({ product: 'ABACare', narrative: outline(), hookPlan: hookPlan(), cta: { text: 'Book an ABACare walkthrough' } });
const beat = (id, storyRole, narration, kind = 'ui') => ({ id, storyRole, narration, kind });
const goodCut = () => ({
  id: 'main', targetSeconds: 40, ratios: ['9x16'], beats: [
    beat('B1', 'hook', 'Tomorrow is booked. One authorization may not be.', 'ui'),
    beat('B2', 'context-problem', 'A clinic coordinator prepares tomorrow’s schedule but sees a visit at risk.', 'ui'),
    beat('B3', 'solution', 'ABACare brings the authorization status into view.', 'ui'),
    beat('B4', 'demonstration', 'The coordinator opens the visit and checks its authorization details.', 'ui'),
    beat('B5', 'payoff', 'The visit needing attention is clear before the day begins.', 'ui'),
    beat('B6', 'cta', 'Book an ABACare walkthrough.', 'card'),
  ],
});
const check = (spec, cut) => inspectNarrativeArc(spec, cut, estimateBeatSeconds);

test('30-60 second product story passes with context, named solution, UI mechanism, result and CTA', () => {
  assert.deepEqual(check(brief(), goodCut()), []);
});

test('unrelated captured screens without a story cannot pass preflight', () => {
  const cut = goodCut();
  cut.beats = [
    beat('B1', undefined, 'Dashboard overview.', 'ui'),
    beat('B2', undefined, 'Settings panel.', 'ui'),
    beat('B3', undefined, 'The next tab.', 'ui'),
  ];
  const errors = check({ ...brief(), narrative: undefined }, cut);
  assert.ok(errors.some((e) => /needs narrative/.test(e.message)));
  assert.ok(errors.some((e) => /first beat must be a story hook/.test(e.message)));
  assert.ok(errors.some((e) => /Introduce the named software/.test(e.message)));
  assert.ok(errors.some((e) => /changed outcome/.test(e.message)));
});

test('name the software in its solution beat rather than relying on a final logo', () => {
  const cut = goodCut();
  cut.beats[2].narration = 'The dashboard brings the status into view.';
  assert.ok(check(brief(), cut).some((e) => /Introduce ABACare by name/.test(e.message)));
});

test('a contextless montage cannot pass by appending a CTA', () => {
  const cut = goodCut();
  cut.beats.splice(1, 1);
  assert.ok(check(brief(), cut).some((e) => /Show who\/where/.test(e.message)));
  assert.ok(check(brief(), cut).some((e) => /specific problem/.test(e.message)));
});

test('context arrives within ten seconds, not at the end of a UI tour', () => {
  const cut = goodCut();
  cut.beats[0].minSeconds = 13;
  assert.ok(check(brief(), cut).some((e) => /within ten seconds/.test(e.message)));
});

test('a product UI demonstration is required: static cards do not substantiate the mechanism', () => {
  const cut = goodCut();
  cut.beats[3].kind = 'card';
  assert.ok(check(brief(), cut).some((e) => /actual captured product UI/.test(e.message)));
});

test('the payoff must come before the final action', () => {
  const cut = goodCut();
  cut.beats[4].storyRole = 'cta';
  cut.beats[5].storyRole = 'payoff';
  assert.ok(check(brief(), cut).some((e) => /End with one CTA/.test(e.message)));
});

test('a 15-second bumper may compress hook and proof without full six-beat exposition', () => {
  const cut = { id: 'bumper', targetSeconds: 15, beats: [beat('A', undefined, 'A visit gets flagged.', 'ui')] };
  assert.deepEqual(check({ ...brief(), narrative: undefined }, cut), []);
});


test('a marketing video must plan its opening visual, on-screen meaning and spoken hook together', () => {
  const spec = brief();
  delete spec.hookPlan;
  assert.ok(check(spec, goodCut()).some((e) => /need hookPlan/.test(e.message)));
});

test('rejects a hook plan that does not match the line actually narrated', () => {
  const spec = brief();
  spec.hookPlan.spoken = 'Something completely different begins this video.';
  assert.ok(check(spec, goodCut()).some((e) => /must match the actual beginning/.test(e.message)));
});

test('a fake emotional arc with identical before and after does not pass', () => {
  const spec = brief();
  spec.narrative.emotionalAfter = spec.narrative.emotionalBefore;
  assert.ok(check(spec, goodCut()).some((e) => /before-state and after-state must differ/.test(e.message)));
});

test('requires actual viewer value beyond a feature name', () => {
  const spec = brief();
  spec.narrative.viewerValue = 'TBD';
  assert.ok(check(spec, goodCut()).some((e) => /narrative.viewerValue/.test(e.message)));
});

test('final call to action must agree with the approved ask', () => {
  const spec = brief();
  spec.cta.text = 'Download the brochure';
  assert.ok(check(spec, goodCut()).some((e) => /approved CTA text/.test(e.message)));
});

test('product UI proof must occur before the payoff, not be appended afterward', () => {
  const cut = goodCut();
  cut.beats[3].kind = 'card';
  cut.beats.push(beat('B7', 'proof', 'The product shows the result after the ending.', 'ui'));
  assert.ok(check(brief(), cut).some((e) => /actual captured product UI/.test(e.message)));
});

test('marketing lint actually invokes narrative checks before provider spend', () => {
  const cut = goodCut();
  delete cut.beats[0].storyRole;
  const spec = {
    product: 'ABACare',
    narrative: outline(),
    hookPlan: hookPlan(),
    voice: { provider: 'openai', name: 'Narrator', voiceId: 'alloy', model: 'gpt-4o-mini-tts', disclosure: 'end card' },
    labels: 'SYNTHETIC · NO PHI',
    claims: [{ id: 'c1', text: 'An authorization status can be reviewed', evidence: 'approved:reviewed-demo' }],
    cta: { text: 'Book an ABACare walkthrough', url: 'https://example.com/demo', claim: 'c1' },
    cuts: [cut],
  };
  const result = lintSpec(spec, {}, { io: { specDir: '/unused', exists: () => true, readJson: () => ({clips: {}}) } });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.code === 'narrative-arc'), JSON.stringify(result.errors));
});

test('full ad-schema and marketing lint accept a coherent evidence-backed product story', () => {
  const cut = goodCut();
  cut.targetSeconds = 32;
  for (const beat of cut.beats) {
    beat.claims = ['c1'];
    if (beat.kind === 'ui') beat.ui = { sourceJob: '/test/product-capture', clipId: 'C1' };
  }
  const claim = {
    id: 'c1', text: 'Authorized workflow review',
    phrases: cut.beats.flatMap((beat) => beat.narration.split(/(?<=[.!?])\\s+/)),
    evidence: 'approved:product-evidence',
  };
  const spec = {
    id: 'narrative-acceptance', title: 'Authorization Review',
    product: 'ABACare', audience: 'ABA clinic coordinators',
    objective: 'Identify a scheduled visit requiring authorization review',
    narrative: outline(), hookPlan: hookPlan(),
    voice: { provider: 'openai', voiceId: 'alloy', model: 'gpt-4o-mini-tts', disclosure: 'end card' },
    claims: [claim], labels: 'SYNTHETIC · NO PHI',
    cta: { text: 'Book an ABACare walkthrough', url: 'https://example.com/demo', claim: 'c1' },
    cuts: [cut],
  };
  const schema = JSON.parse(readFileSync(new URL('../kit/marketing/ad.schema.json', import.meta.url), 'utf8'));
  const io = {
    specDir: '/test',
    exists: () => true,
    readJson: () => ({ clips: { C1: { valid: true, clipSeconds: 60, events: { clicks: 0 } } } }),
  };
  assert.deepEqual(validate(schema, spec), []);
  const result = lintSpec(spec, {}, { io, adSchema: schema });
  assert.equal(result.ok, true, JSON.stringify(result.errors));
  assert.deepEqual(result.errors, []);
  const changed = structuredClone(spec);
  delete changed.narrative.viewerValue;
  assert.ok(validate(schema, changed).some((e) => /viewerValue/.test(e)));
  assert.equal(lintSpec(changed, {}, { io, adSchema: schema }).ok, false);
});
