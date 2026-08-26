# Reviewer calibration — fixture catalog addendum

Supplements `reviewer-calibration.md`. That file remains the enforcement contract; this one records what the fixtures are, why there are two sets, and how to rebuild them.

## Two sets, because two things are being reviewed

The original catalog listed six fixtures as rendered masters, including `dead-wait` against the `bounded-waits` criterion. That is a category error, and it surfaced the moment the fixtures were built.

**Demo-worthiness is assessed against a running product.** A rendered master cannot exercise it — the assessment measures wait feedback, layout stability under load, and legibility at product scale, none of which survive being flattened into a video. Its fixtures are therefore small static applications.

**Craft and persuasion are assessed against a rendered master.** Hero staging, hold duration, and payoff rung exist only in the edit. Its fixtures are rendered masters.

`dead-wait` appears in both sets and means different things in each: a running app whose wait has no feedback, and a master with the wait left uncut. `verify-fixtures.mjs` fails if the two artifacts are ever the same file.

This has a useful consequence. **The worthiness gate is calibratable with no product and no seeded environment** — the applications are served locally, so calibration can precede any real assessment.

## Worthiness set — `fixtures/worthiness/`

Five static applications over one plausible flow (invoice reconciliation), one planted defect each. Served by `scripts/serve-worthiness-fixtures.mjs` on port 8977.

| Fixture | Expected | Criterion | Classification | Measured |
|---|---|---|---|---|
| `clean-pass` | PASS | — | — | result at 1896ms, determinate progress |
| `dead-wait` | FAIL | `bounded-feedback-rich-waits` | product-fix-required | result at 6398ms, no feedback |
| `illegible` | CONDITIONAL | `legibility` | capture-fixable | body 9px, headline 10px low-contrast |
| `unstable` | FAIL | `visual-stability` | product-fix-required | shift at 900ms; 1500px table in 940px container |
| `no-hero` | FAIL | `hero-moment-exists` | product-fix-required | result at 67ms, no surprising state change |

Each carries `<id>.expected-readiness.json` in the shape `validate-demo-readiness.mjs` accepts, so the expectations are machine-checked rather than prose.

**`illegible` and `dead-wait` test the classification boundary from both sides.** Small text is resolved by a punch-in at capture. A wait with no feedback is not resolved by cutting it — the viewer still sees a cut where a result should have appeared. A set containing only product-fix-required cases tests half the judgment that matters.

**`no-hero` is the hardest.** Nothing is broken: the flow is clean, fast, legible, stable, deterministic, and has a visible guardrail. It simply contains no reveal worth building a video around. A reviewer that passes it has stopped applying the criterion that separates a useful product from a demo-worthy one.

Every expected readiness sheet carries an upstream `productExperienceHandoff` of `DEMO-READY` / `PROCEED` with all eleven criteria passing. That is deliberate — the fixtures test whether the video-side assessment will independently disagree with an upstream PROCEED. A fixture whose handoff already flagged the defect would prove nothing.

## Craft set — `fixtures/craft/`

Six rendered masters matching the fixed `fixtureId` enum in `schemas/reviewer-calibration.schema.json`. Each differs from `clean-pass` in exactly one property.

| Fixture | Expected | Criterion | Classification | Planted |
|---|---|---|---|---|
| `clean-pass` | PASS | — | — | correct arc, hero held 4000ms, identity-rung payoff |
| `no-hold` | FAIL | `results-land` | capture-fixable | hero cut 600ms after the reveal |
| `buried-hero` | FAIL | `hero-moment-staged` | capture-fixable | hero at 37% of runtime, two beats after it |
| `three-heroes` | FAIL | `single-hero` | capture-fixable | three competing reveals of equal weight |
| `dead-wait` | FAIL | `bounded-waits` | product-fix-required | 6.5s on one frame, uncut |
| `feature-rung` | FAIL | `wiifm-rung` | capture-fixable | identical visuals, feature-rung narration |

`feature-rung` shares its shot list with `clean-pass` byte for byte. Only the transcript differs. A reviewer that passes it is reading the pictures and not the argument.

Companion artifacts per fixture: `storyboard.json` (beat boundaries, hero flags, narration), `transcript.srt`, `timing-deltas.json`, `expected-criteria.json`.

**`timing-deltas.json` is the most useful of these.** `stateChangeToCutMs` is the hold on each beat, `heroCount` and `heroPositionRatio` locate the reveals, and `longestStaticStretchMs` feeds the pattern-interrupt check. Judging pacing from still frames is genuinely hard; judging it from measured intervals is not. Push as much of the craft gate into these numbers as the criteria allow and leave the reviewer only the part that requires taste.

## Rebuilding

```
node scripts/build-worthiness-fixtures.mjs      # catalog + expected readiness sheets
node scripts/build-craft-fixtures.mjs           # masters + companions + catalog
node scripts/verify-fixtures.mjs                # checksums, decode, cross-validation
```

The craft build is byte-reproducible: the noise bed is seeded, `-fflags +bitexact` strips encoder version strings and creation timestamps, and the shot list is fixed. A rebuild that changes a checksum means an input changed, not the encoder.

`verify-fixtures.mjs` exits 0 pass, 1 drift, 2 could-not-evaluate. It also enforces two structural properties independent of any individual fixture: each set must contain a clean fixture, and the worthiness set must contain at least one capture-fixable case.

## When to add a fixture

Whenever a defect reaches final presentation. That is the signal a criterion is not being evaluated, and the fixture is what stops it recurring. Add to the worthiness set freely. The craft `fixtureId` enum is fixed at six in the schema, so a new craft fixture requires a schema change and a version bump.
