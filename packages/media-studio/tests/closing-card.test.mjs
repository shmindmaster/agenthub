// Closing card without a CTA, the end-card hold, brand-driven caption plate, and a non-black first frame.
// Pure: builds the MarketingAd props from synthetic timelines, no render. Run: node --test tests/closing-card.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const href = (...p) => pathToFileURL(join(pkg, ...p)).href;
const { buildRatioPlan, cutHasCta } = await import(href('kit', 'marketing', 'lib', 'stages', 'compose.mjs'));
const { holdFinalBeat, finalHoldOf } = await import(href('kit', 'marketing', 'lib', 'stages', 'timing.mjs'));
const { buildGateWorkspace } = await import(href('kit', 'marketing', 'lib', 'gates.mjs'));
const { entrance, plateRgb, DEFAULT_CAPTION_PLATE } = await import(href('kit', 'marketing', 'lib', 'layout.mjs'));

const brand = (colors = {}) => ({ product: 'Sample Product', colors: { primary: '#2255cc', foreground: '#10203a', background: '#f5f7fa', accent: '#cc7700', ...colors }, fonts: { display: 'Sans', body: 'Sans', files: [] } });
const ctxFor = (spec, b = brand()) => ({ spec: { labels: 'SYNTHETIC', voice: {}, ...spec }, brand: b, jobDir: '.', flags: {} });
const cutOf = (extra = {}) => ({ id: 'main', ratios: ['16x9'], beats: [
  { id: 'open', kind: 'title', actionTitle: 'The line that opens the film' },
  { id: 'close', kind: 'card', actionTitle: 'The outcome the film ends on', onScreenText: 'One supporting line' },
], ...extra });
const timeline = { durationSeconds: 8, segments: [
  { id: 'open', startSeconds: 0, durationSeconds: 4, words: [] },
  { id: 'close', startSeconds: 4, durationSeconds: 4, words: [{ word: 'Done', start: 4.5, end: 5.5 }] },
] };
const plan = (spec, cut = cutOf(), b = brand()) => buildRatioPlan(ctxFor(spec, b), cut, '16x9', { timeline, captions: [], voice: { lines: [] }, assets: { items: [] }, capture: [] });

test('a spec with a cta keeps the exact end-card props (no closing fields, no plate colour)', () => {
  const { props } = plan({ cta: { text: 'Try it', url: 'https://example.com/go' } });
  assert.deepEqual(props.cta, { text: 'Try it', displayUrl: 'example.com/go' });
  assert.deepEqual(props.beats[1], { id: 'close', kind: 'card', startSec: 4, durationSec: 4, headline: 'The outcome the film ends on', isCta: true });
  assert.deepEqual(Object.keys(props.brand.colors), ['primary', 'foreground', 'background', 'accent', 'onPrimary']);
  assert.equal(props.durationSec, 8);
});

test('without a cta the last card is a closing card: headline plus support, no cta prop, never marked isCta', () => {
  const { props } = plan({});
  assert.equal('cta' in props, false);
  assert.deepEqual(props.beats[1], { id: 'close', kind: 'card', startSec: 4, durationSec: 4, headline: 'The outcome the film ends on', isCta: false, isClosing: true, support: 'One supporting line' });
});

test('a closing card with no distinct support text carries none', () => {
  const cut = cutOf({ beats: [{ id: 'open', kind: 'title', actionTitle: 'The line that opens the film' }, { id: 'close', kind: 'card', onScreenText: 'Only line' }] });
  const last = plan({}, cut).props.beats[1];
  assert.equal(last.headline, 'Only line');
  assert.equal('support' in last, false);
});

test('holdFinalBeat grows the timeline to hold after the last spoken word, even when the final beat is silent', () => {
  const spoken = { durationSeconds: 8, segments: [
    { id: 'open', startSeconds: 0, durationSeconds: 4, speechSeconds: 3, lineStartSeconds: 0.3, words: [{ word: 'Hi', start: 0.4, end: 3.1 }], text: 'Hi' },
    { id: 'close', startSeconds: 4, durationSeconds: 4, speechSeconds: 0, lineStartSeconds: null, words: [], text: '' },
  ] };
  assert.equal(holdFinalBeat(spoken, 0), spoken, 'no hold: the same object');
  assert.equal(holdFinalBeat(spoken, undefined), spoken);
  assert.equal(holdFinalBeat(spoken, 4), spoken, 'speech ends at 3.3, so 4 s of hold ends at 7.3: already held');
  const held = holdFinalBeat(spoken, 6);
  assert.equal(held.durationSeconds, 9.3, 'measured from the last speech (3.3), not from the silent beat');
  assert.equal(held.segments[1].durationSeconds, 5.3);
  assert.equal(held.segments[0], spoken.segments[0]);
  assert.equal(finalHoldOf({ finalHoldSeconds: 2 }, { finalHoldSeconds: 5 }), 5, 'the cut wins over the spec');
  assert.equal(finalHoldOf({ finalHoldSeconds: 2 }, {}), 2);
  assert.equal(finalHoldOf({}, {}), 0);
});

test('with a hold, the timeline, the gate inputs, the compose map and the props all read the same length', (t) => {
  const spoken = { durationSeconds: 8, segments: [
    { id: 'open', startSeconds: 0, durationSeconds: 4, speechSeconds: 3, lineStartSeconds: 0.3, words: [{ word: 'Hi', start: 0.4, end: 3.1 }], text: 'Hi' },
    { id: 'close', startSeconds: 4, durationSeconds: 4, speechSeconds: 1, lineStartSeconds: 4.3, words: [{ word: 'Done', start: 4.5, end: 5.5 }], text: 'Done' },
  ] };
  const timeline = holdFinalBeat(spoken, 4);
  assert.equal(timeline.durationSeconds, 9.5);
  const spec = { id: 'hold-film', product: 'Sample Product', title: 'Hold', labels: 'SYNTHETIC', voice: {}, finalHoldSeconds: 4 };
  const cut = cutOf();
  const p = buildRatioPlan({ spec, brand: brand(), jobDir: '.', flags: {} }, cut, '16x9', { timeline, captions: [], voice: { lines: [] }, assets: { items: [] }, capture: [] });
  const root = mkdtempSync(join(tmpdir(), 'closing-hold-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const composeMap = { groups: p.groups };
  buildGateWorkspace({ root, spec, brand: brand(), cut, ratio: '16x9', timeline, composeMap, clips: [], asr: {}, loudnessLufs: -16 });
  const read = (...a) => JSON.parse(readFileSync(join(root, ...a), 'utf8'));
  const last = timeline.segments[1];
  assert.equal(read('story', 'narration-timeline.json').durationSeconds, 9.5);
  assert.equal(read('qa', 'listen-timeline.json').durationSeconds, 9.5);
  assert.equal(read('qa', 'listen-timeline.json').segments[1].sceneEndSeconds, 9.5);
  assert.equal(p.props.durationSec, 9.5);
  assert.equal(p.durationSeconds, 9.5);
  assert.equal(p.props.beats[1].durationSec, 5.5);
  assert.equal(p.gateSegments[1].startSeconds + p.gateSegments[1].durationSeconds, 9.5);
  assert.equal(composeMap.groups[1].startSeconds + composeMap.groups[1].needSeconds, 9.5);
  assert.equal(last.startSeconds + last.durationSeconds, 9.5, 'the deliver row reads timeline.durationSeconds: the same 9.5');
});

test('a spec without finalHoldSeconds keeps the timeline unchanged', () => {
  const tl = { durationSeconds: 8, segments: [{ id: 'a', startSeconds: 0, durationSeconds: 8, speechSeconds: 1, lineStartSeconds: 0.3, words: [], text: 'x' }] };
  assert.equal(holdFinalBeat(tl, finalHoldOf({}, {})), tl);
  assert.equal(JSON.stringify(holdFinalBeat(tl, finalHoldOf({}, {}))), JSON.stringify(tl));
});

test('the end card draws spec.cta only on a cut whose film type has a cta slot or that has a cta-role beat', () => {
  const spec = { cta: { text: 'Go', url: 'https://example.com' } };
  assert.equal(cutHasCta({}, cutOf()), false, 'no spec cta');
  assert.equal(cutHasCta(spec, { ...cutOf(), filmType: 'product-marketing' }), true);
  assert.equal(cutHasCta(spec, { ...cutOf(), filmType: 'explainer' }), false, 'a type without the slot');
  assert.equal(cutHasCta(spec, { ...cutOf(), filmType: 'explainer', beats: [{ id: 'x', kind: 'card', storyRole: 'cta' }] }), true, 'a cta-role beat');
  assert.equal(cutHasCta(spec, cutOf()), true, 'undeclared film type keeps the old behaviour');
});

test('the caption plate colour follows the brand and defaults to the original navy', () => {
  assert.equal(plateRgb(DEFAULT_CAPTION_PLATE), '15, 23, 42');
  assert.equal(plateRgb(undefined), '15, 23, 42');
  assert.equal(plateRgb('nope'), '15, 23, 42');
  assert.equal(plateRgb('#102030'), '16, 32, 48');
  assert.equal(plan({}, cutOf(), brand({ captionPlate: '#102030' })).props.brand.colors.captionPlate, '#102030');
  assert.equal('captionPlate' in plan({}).props.brand.colors, false);
});

test('frame 0 of the first beat is never empty; later beats still fade up from transparent', () => {
  const fps = 30;
  assert.equal(entrance(0, fps, { first: true, at: 0.5 * fps, risePx: 40 }).opacity, 1);
  assert.equal(entrance(0, fps, { first: true, at: 0, risePx: 40 }).opacity, 1);
  assert.ok(entrance(0, fps, { first: true, at: 0, risePx: 40 }).rise > 0, 'the rise motion still runs');
  assert.equal(entrance(0, fps, { at: 0, risePx: 40 }).opacity, 0, 'a non-first beat still starts transparent (the gate is real)');
  assert.equal(entrance(fps, fps, { at: 0, risePx: 40 }).opacity, 1);
  assert.equal(entrance(fps, fps, { at: 0, risePx: 40 }).rise, 0);
});
