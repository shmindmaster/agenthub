---
description: Prove independent review still rejects known defects and accepts a clean candidate. Runs both calibration fixture sets and validates the result with validate-reviewer-calibration.mjs.
argument-hint: "[--set worthiness|craft|all] [--domain <review-domain>] [--fixture <id>]"
---

Run reviewer calibration: $ARGUMENTS

Read `pipeline/product-demo-studio/references/reviewer-calibration.md` first. It is the contract; this command is the procedure.

## 0. Verify the fixtures before trusting them

```
node ${PRODUCT_DEMO_STUDIO_ROOT}/scripts/verify-fixtures.mjs
```

Exit 1 means a fixture has drifted — checksum mismatch, a master that no longer decodes, or an expected readiness sheet that `validate-demo-readiness.mjs` now rejects. **Stop.** A calibration result computed against drifted fixtures is worthless. Rebuild with `build-craft-fixtures.mjs` or `build-worthiness-fixtures.mjs` only after diagnosing why it changed.

Exit 2 means the fixtures are absent. That is `PIPELINE_BLOCKED`, not a pass.

## 1. Worthiness set — running applications

Serve them, then point one isolated read-only assessment context at each:

```
node ${PRODUCT_DEMO_STUDIO_ROOT}/scripts/serve-worthiness-fixtures.mjs    # http://localhost:8977/<id>/
```

Five fixtures: `clean-pass`, `dead-wait`, `illegible`, `unstable`, `no-hero`. Each has a `<id>.expected-readiness.json` giving the required verdict, the criterion that must trip, and its classification.

**Do not tell the assessment context which fixture it is walking, what is planted, or what it is expected to find.** Give it the URL and the candidate. Nothing else.

Each context produces a demo-readiness sheet. Validate every one:

```
node ${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-demo-readiness.mjs <sheet>
```

Then compare against the expected sheet on three axes: the verdict, the criterion that failed, and its classification. A fixture that trips the right verdict via the wrong criterion has not detected the planted defect — it found something else, and that is a failure.

`illegible` must come back `capture-fixable`. `dead-wait` must not. That pair is the classification boundary; getting one right and the other wrong means the boundary has moved.

## 2. Craft set — rendered masters

Six fixtures under `fixtures/craft/`, matching the fixed `fixtureId` enum in `schemas/reviewer-calibration.schema.json`. Each carries a checksum-bound master, `storyboard.json`, `transcript.srt`, `timing-deltas.json`, and `expected-criteria.json`.

Give each reviewer the master, the storyboard, the transcript, and the timing deltas. **The timing deltas are what make the craft judgment checkable** — `stateChangeToCutMs` on a hero beat converts "the payoff felt rushed" into a number the reviewer can cite. `no-hold` holds its hero 600ms; `clean-pass` holds 4000ms.

Run once per `reviewDomain` you are calibrating. Fresh isolated read-only contexts, canonical rubric loaded from the installed plugin, no generator reasoning in the handoff.

## 3. Record the result

Assemble one `reviewer-calibration.json` per domain per `schemas/reviewer-calibration.schema.json`: plugin version, rubric and overlay hashes, model id, `completedAt`, and exactly six fixture entries with their review-report references. Then:

```
node ${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-reviewer-calibration.mjs <path>
```

The validator derives the observed verdict from criterion results. Do not hand-author `observedVerdict`. Missing evidence or a missing receipt is `BLOCKED`, never `PASS`.

## 4. Report and act

Print a table of set, fixture, expected, observed, criterion matched, and pass or fail.

**If a known-bad fixture passes, or either `clean-pass` fails, return `PIPELINE_BLOCKED`.** Treat every production verdict since the last successful calibration as suspect — not merely the current one — and rerun affected reviews from immutable artifacts once the cause is fixed.

Diagnose in this order: rubric text, reviewer brief, model, input contract, fixture. **Never adjust a fixture to match a result.**

`clean-pass` failing matters as much as a defective fixture passing. It detects drift toward over-rejection, which looks like diligence and is equally broken.
