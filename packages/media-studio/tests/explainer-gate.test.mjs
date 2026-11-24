// The gate must fail for the right reason. Each test mutates one thing in a
// film that otherwise passes, so a green run means every rule can actually fire.
import test from 'node:test';
import assert from 'node:assert/strict';
import { judge, metricsFacts } from '../kit/explainer/validate-explainer-release.mjs';
import { build, clone, cueSheet } from './fixtures/explainer/fixture.mjs';

const rules = (verdict) => verdict.failed.map((entry) => entry.rule);
const warnings = (verdict) => verdict.warnings.map((entry) => entry.rule);
const advisories = (verdict) => verdict.advisories.map(({ rule }) => rule);
const props = () => build().props;

test('a measured-ready film passes, with the unmeasured composition called out', () => {
  const verdict = judge({ props: props(), cueSheet });
  assert.equal(verdict.ok, true, JSON.stringify(verdict.failed));
  assert.deepEqual(warnings(verdict), ['metrics-missing']);
});

test('a release that claims to be measured but supplies no frames fails', () => {
  const verdict = judge({ props: props(), cueSheet, requireMetrics: true });
  assert.equal(verdict.ok, false);
  assert.ok(rules(verdict).includes('metrics-missing'));
});

test('a short landing hold is advisory', () => {
  const film = clone(props());
  film.shots[1].holdSeconds = 0.4;
  const verdict = judge({ props: film, cueSheet });
  assert.equal(verdict.ok, true);
  assert.ok(advisories(verdict).includes('hold'));
});

test('a film of type-only frames gets an advisory', () => {
  const film = clone(props());
  for (const shot of film.shots.slice(0, 4)) {
    shot.archetype = 'kinetic-statement';
    shot.family = 'statement';
    delete shot.visual;
  }
  const verdict = judge({ props: film, cueSheet });
  assert.ok(advisories(verdict).includes('type-only-cap'));
});

test('the same family twice in a row is flagged unless the repeat is the point', () => {
  const film = clone(props());
  film.shots[1].archetype = 'kinetic-statement';
  film.shots[1].family = 'statement';
  delete film.shots[1].visual;
  assert.ok(advisories(judge({ props: film, cueSheet })).includes('no-consecutive-repeat'));
  film.shots[1].repeatIsPoint = true;
  assert.equal(advisories(judge({ props: film, cueSheet })).includes('no-consecutive-repeat'), false);
});

test('a chapter with no large or full-frame shot is flagged', () => {
  const film = clone(props());
  for (const shot of film.shots.slice(3)) {
    shot.archetype = 'evidence-proof';
    shot.family = 'evidence';
    shot.visual = { kind: 'proof', claim: 'c', evidence: 'e' };
    shot.repeatIsPoint = true;
  }
  assert.ok(advisories(judge({ props: film, cueSheet })).includes('chapter-hero'));
});

test('the clock must add up, and a gap between shots is a failure', () => {
  const drift = clone(props());
  drift.totalSeconds = 27;
  assert.ok(rules(judge({ props: drift, cueSheet })).includes('duration-exact'));

  const gap = clone(props());
  gap.shots[2].startFrame += 3;
  assert.ok(rules(judge({ props: gap, cueSheet })).includes('shot-contiguous'));
});

test('chapters must tile the film', () => {
  const film = clone(props());
  film.film.chapters[1].startFrame += 1;
  assert.ok(rules(judge({ props: film, cueSheet })).includes('chapter-contiguous'));
});

test('the picture must cover every cue in order', () => {
  const film = clone(props());
  film.shots.pop();
  assert.ok(rules(judge({ props: film, cueSheet })).includes('cue-coverage'));
});

test('a vertical frame is refused rather than letterboxed', () => {
  const film = clone(props());
  film.film.width = 1080;
  film.film.height = 1920;
  assert.ok(rules(judge({ props: film, cueSheet })).includes('aspect'));
});

test('static and sparse frames are advisory while unbound receipts fail', () => {
  const still = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestStaticSeconds: 3.2 } },
    propsSha256: 'ABC',
  });
  assert.ok(advisories(still).includes('static-run'));

  const empty = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestEmptyRunSeconds: 2.0 } },
    propsSha256: 'ABC',
  });
  assert.ok(advisories(empty).includes('empty-frame'));

  const unbound = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'OTHER', film: { longestStaticSeconds: 0.2 } },
    propsSha256: 'ABC',
  });
  assert.ok(rules(unbound).includes('metrics-binding'));
});

test('a small hero and background debris remain advisory in strict mode', () => {
  const soft = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestStaticSeconds: 0.1, heroMedianPx: 100, debrisMax: 14 } },
    propsSha256: 'ABC',
  });
  assert.equal(soft.ok, true);
  assert.deepEqual(advisories(soft).sort(), ['debris', 'hero-small']);

  const strict = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestStaticSeconds: 0.1, heroMedianPx: 100 } },
    propsSha256: 'ABC',
    strict: true,
  });
  assert.equal(strict.ok, true);
  assert.ok(advisories(strict).includes('hero-small'));
});

test('the encoded film must agree with the props', () => {
  const wrong = judge({ props: props(), cueSheet, encoded: { probed: true, seconds: 30, sha256: 'X' } });
  assert.ok(rules(wrong).includes('encoded-duration'));
  const unprobed = judge({ props: props(), cueSheet, encoded: { probed: false, seconds: 0, sha256: 'X' } });
  assert.equal(unprobed.ok, true);
  assert.ok(warnings(unprobed).includes('encoded-unprobed'));
});

test('the metrics reader tolerates the receipt shapes a render host can produce', () => {
  const fromRuns = metricsFacts({ fps: 30, staticRuns: [{ seconds: 1.1 }, { seconds: 2.4 }] });
  assert.equal(fromRuns.longestStaticSeconds, 2.4);
  const fromFilm = metricsFacts({ film: { longestStaticSeconds: 0.3, heroMedianPx: 220, cuts: 12 }, fps: 30 });
  assert.equal(fromFilm.heroMedianPx, 220);
  assert.equal(fromFilm.cuts, 12);
  const empty = metricsFacts({ film: { longestEmptyRunFrames: 60 }, fps: 30 });
  assert.equal(empty.emptySeconds, 2);
});

test('release reports aesthetic metrics and refuses sparse or mismatched evidence', () => {
  const picture = props();
  const encoded = { sha256: 'CANDIDATE', bytes: 1024, probed: true, seconds: picture.totalSeconds };
  const frameReport = {
    propsSha256: 'PROPS',
    encoded,
    frames: 780,
    complete: true,
    ok: true,
    perShot: picture.shots.map(({ id }) => ({ id, sampled: 1 })),
  };
  const check = (patch) => judge({
    props: picture,
    propsSha256: 'PROPS',
    requireMetrics: true,
    metrics: { ...frameReport, ...patch },
    encoded,
  });
  assert.equal(check({}).ok, true);
  assert.ok(advisories(check({ ok: false })).includes('metrics-style'));
  assert.ok(rules(check({ complete: false })).includes('metrics-coverage'));
  assert.ok(rules(check({ perShot: frameReport.perShot.slice(1) })).includes('metrics-coverage'));
  assert.ok(rules(check({ encoded: { ...encoded, sha256: 'OTHER' } })).includes('metrics-encoded-binding'));
});
