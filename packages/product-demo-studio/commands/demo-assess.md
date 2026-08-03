---
description: Assess whether a product's workflows can carry a demo video worth watching, and write a Product-Readiness Feedback Report where they cannot. Assessment only — no capture, narration, or render.
argument-hint: "--repo <path> [--episodes <n>] [--workflow <name>]"
---

Run demo-readiness assessment: $ARGUMENTS

This is the assessment half of `product-demo-studio` run on its own. It produces verdicts and a feedback report. **It captures nothing, narrates nothing, and renders nothing.** Use it to find out whether a product is ready before spending a capture run on it.

## 0. Config

Read `product-demo-studio.config.yaml` from the target repo. Required: `product`, `environment.url`, `environment.reset`, `work_dir`.

Missing file: copy `product-demo-studio.config.example.yaml` into the repo and stop. **Never infer an environment URL, a reset command, a persona, or a tracker project.**

The target repo is read-only input. The working package goes to `work_dir`, never into the product source tree.

## 1. Establish the environment class

Before anything else, determine what `environment.url` actually points at, and say which it is in the report header:

- **Resettable demo environment** — `environment.reset` works. Full assessment; `deterministic-resettable` is evidenceable.
- **Live public deployment with demo data** — no reset path. Assessment proceeds, but `deterministic-resettable` **cannot be evidenced by reset**. Evidence it by walking the flow twice and comparing, then record the substitution explicitly in the verdict. A second walk proves reproduction, not resettability; do not claim otherwise.
- **Live deployment carrying real user data** — stop. Return `PIPELINE_BLOCKED`. Do not walk flows that may surface another person's data.

If the class cannot be determined, that is `BLOCKED`, not an assumption to make.

## 2. Design candidates

Read the repo to find workflows that work end to end against the seeded data. Write each to `<work_dir>/candidates/<id>.yaml`:

```yaml
id: ep01
persona: <who, with what permissions>
flow: <steps in the running product>
claimed_hero_moment: <the one reveal this is built around>
before_state: <what establishes the cost of today>
wiifm_at_payoff: <the one line, and which rung it lands on>
emotional_target: <relief | confidence | delight | "finally">
cold_open: <where it starts — never a login screen>
```

Three to five candidates unless `--episodes` says otherwise. Each targets one persona and one problem, reaches value fast, and stands alone.

A workflow that does not work end to end is not a candidate. Say so and move on rather than proposing it.

## 3. Assess

One isolated read-only assessment context per candidate, in parallel. Each receives **paths only** — the candidate file and the config. No rubric text, no candidate content inline, no expectations of your own, no other candidate's verdict.

Load the canonical rubric from the installed plugin and record its hash. Walk each flow in the live product at demo resolution, capturing evidence at every state change. Time every wait with a real measurement — "slow" is not a finding, "6.2s with no visible feedback after Reconcile" is.

Every criterion carries evidence, **pass as well as fail**. A criterion that cannot be evidenced goes in `unevidenced_criteria` and the verdict is `BLOCKED` — never `PASS` because nothing looked obviously wrong.

Classify every failure:

- **capture-fixable** — the pipeline resolves it at capture or edit with no product change. Name the exact technique. If you cannot name one, it is not capture-fixable.
- **product-fix-required** — no editing hides it. A wait with no feedback is not fixed by cutting it; the viewer still sees a cut where a result should have appeared.

The pressure is toward `capture-fixable` because it lets the run continue. Resist it. A misclassification here surfaces as a craft failure much later at far higher cost.

Write each verdict to `<work_dir>/verdicts/` before acting on it, then validate:

```
node <plugin>/scripts/validate-demo-readiness.mjs <sheet>
```

## 4. Gate

- Any `BLOCKED` → halt that episode, report the missing evidence, do not retry.
- All `FAIL` → feedback report only.
- Any `PASS` or `CONDITIONAL` → those episodes are cleared for capture; write the feedback report for the rest.

## 5. Report

Write the Product-Readiness Feedback Report per `references/feedback-report-format.md`. **A build spec, not a critique** — repo paths, component names, buildable fixes. Close with the shortest path to demo-readiness: the minimal ordered set of fixes, each stating which episodes it releases.

Report back: the environment class, each candidate's verdict with its deciding criteria, product-fix-required count by severity, the single highest-value fix, the report path, and which episodes are cleared for capture.

Do not write scripts, storyboards, or capture code. That is the full pipeline's job, not this command's.
