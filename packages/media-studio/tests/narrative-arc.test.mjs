import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectNarrativeArc } from '../kit/marketing/lib/narrative.mjs';
import { estimateBeatSeconds, lintSpec } from '../kit/marketing/lib/lint.mjs';

const outline = () => ({
  persona: 'an ABA clinic coordinator',
  situation: 'preparing the next day of sessions',
  trigger: 'an authorization changes overnight',
  problem: 'a scheduled visit may lack valid authorization',
  stakes: 'the clinic needs to catch problems before sessions begin',
  solution: 'ABACare highlights the authorization status in the workflow',
  mechanism: 'staff reviews the flagged visit and relevant authorization details',
  payoff: 'the coordinator knows which visit needs attention',
});
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
  assert.deepEqual(check({ product: 'ABACare', narrative: outline() }, goodCut()), []);
});

test('unrelated captured screens without a story cannot pass preflight', () => {
  const cut = goodCut();
  cut.beats = [
    beat('B1', undefined, 'Dashboard overview.', 'ui'),
    beat('B2', undefined, 'Settings panel.', 'ui'),
    beat('B3', undefined, 'The next tab.', 'ui'),
  ];
  const errors = check({ product: 'ABACare' }, cut);
  assert.ok(errors.some((e) => /needs narrative/.test(e.message)));
  assert.ok(errors.some((e) => /first beat must be a story hook/.test(e.message)));
  assert.ok(errors.some((e) => /Introduce the named software/.test(e.message)));
  assert.ok(errors.some((e) => /changed outcome/.test(e.message)));
});

test('name the software in its solution beat rather than relying on a final logo', () => {
  const cut = goodCut();
  cut.beats[2].narration = 'The dashboard brings the status into view.';
  assert.ok(check({ product: 'ABACare', narrative: outline() }, cut).some((e) => /Introduce ABACare by name/.test(e.message)));
});

test('a contextless montage cannot pass by appending a CTA', () => {
  const cut = goodCut();
  cut.beats.splice(1, 1);
  assert.ok(check({ product: 'ABACare', narrative: outline() }, cut).some((e) => /Show who\/where/.test(e.message)));
  assert.ok(check({ product: 'ABACare', narrative: outline() }, cut).some((e) => /specific problem/.test(e.message)));
});

test('context arrives within ten seconds, not at the end of a UI tour', () => {
  const cut = goodCut();
  cut.beats[0].minSeconds = 13;
  assert.ok(check({ product: 'ABACare', narrative: outline() }, cut).some((e) => /within ten seconds/.test(e.message)));
});

test('a product UI demonstration is required: static cards do not substantiate the mechanism', () => {
  const cut = goodCut();
  cut.beats[3].kind = 'card';
  assert.ok(check({ product: 'ABACare', narrative: outline() }, cut).some((e) => /actual captured product UI/.test(e.message)));
});

test('the payoff must come before the final action', () => {
  const cut = goodCut();
  cut.beats[4].storyRole = 'cta';
  cut.beats[5].storyRole = 'payoff';
  assert.ok(check({ product: 'ABACare', narrative: outline() }, cut).some((e) => /End with one CTA/.test(e.message)));
});

test('a 15-second bumper may compress hook and proof without full six-beat exposition', () => {
  const cut = { id: 'bumper', targetSeconds: 15, beats: [beat('A', undefined, 'A visit gets flagged.', 'ui')] };
  assert.deepEqual(check({ product: 'ABACare' }, cut), []);
});

test('marketing lint actually invokes narrative checks before provider spend', () => {
  const cut = goodCut();
  delete cut.beats[0].storyRole;
  const spec = {
    product: 'ABACare',
    narrative: outline(),
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
