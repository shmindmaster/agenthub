// The gate must fail for the right reason. Each test mutates one thing in a
// film that otherwise passes, so a green run means every rule can actually fire.
import test from 'node:test';
import assert from 'node:assert/strict';
import { judge, metricsFacts } from '../kit/explainer/validate-explainer-release.mjs';
import { build, clone, cueSheet } from './fixtures/explainer/fixture.mjs';

const rules = (verdict) => verdict.failed.map((entry) => entry.rule);
const warnings = (verdict) => verdict.warnings.map((entry) => entry.rule);
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

test('a shot that lands and cuts fails', () => {
  const film = clone(props());
  film.shots[1].holdSeconds = 0.4;
  const verdict = judge({ props: film, cueSheet });
  assert.equal(verdict.ok, false);
  assert.ok(rules(verdict).includes('hold'));
});

test('a film of type-only frames fails', () => {
  const film = clone(props());
  for (const shot of film.shots.slice(0, 4)) {
    shot.archetype = 'kinetic-statement';
    shot.family = 'statement';
    delete shot.visual;
  }
  const verdict = judge({ props: film, cueSheet });
  assert.ok(rules(verdict).includes('type-only-cap'));
});

test('the same family twice in a row fails unless the repeat is the point', () => {
  const film = clone(props());
  film.shots[1].archetype = 'kinetic-statement';
  film.shots[1].family = 'statement';
  delete film.shots[1].visual;
  assert.ok(rules(judge({ props: film, cueSheet })).includes('no-consecutive-repeat'));
  film.shots[1].repeatIsPoint = true;
  assert.equal(rules(judge({ props: film, cueSheet })).includes('no-consecutive-repeat'), false);
});

test('a chapter with no large or full-frame shot fails', () => {
  const film = clone(props());
  for (const shot of film.shots.slice(3)) {
    shot.archetype = 'evidence-proof';
    shot.family = 'evidence';
    shot.visual = { kind: 'proof', claim: 'c', evidence: 'e' };
    shot.repeatIsPoint = true;
  }
  assert.ok(rules(judge({ props: film, cueSheet })).includes('chapter-hero'));
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

test('measured static runs, empty stretches and unbound receipts fail', () => {
  const still = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestStaticSeconds: 3.2 } },
    propsSha256: 'ABC',
  });
  assert.ok(rules(still).includes('static-run'));

  const empty = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestEmptyRunSeconds: 2.0 } },
    propsSha256: 'ABC',
  });
  assert.ok(rules(empty).includes('empty-frame'));

  const unbound = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'OTHER', film: { longestStaticSeconds: 0.2 } },
    propsSha256: 'ABC',
  });
  assert.ok(rules(unbound).includes('metrics-binding'));
});

test('a small hero and background debris warn, and strict makes warnings fatal', () => {
  const soft = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestStaticSeconds: 0.1, heroMedianPx: 100, debrisMax: 14 } },
    propsSha256: 'ABC',
  });
  assert.equal(soft.ok, true);
  assert.deepEqual(warnings(soft).sort(), ['debris', 'hero-small']);

  const strict = judge({
    props: props(),
    cueSheet,
    metrics: { propsSha256: 'ABC', film: { longestStaticSeconds: 0.1, heroMedianPx: 100 } },
    propsSha256: 'ABC',
    strict: true,
  });
  assert.equal(strict.ok, false);
  assert.ok(rules(strict).includes('hero-small-strict'));
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
