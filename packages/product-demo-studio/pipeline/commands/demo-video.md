---
description: Produce a fully gated product demo video, or Product-Readiness Feedback where the product cannot carry one. Runs the full pipeline — assessment, script, capture, narration, render, four-domain review, arbitration, delivery.
argument-hint: "--repo <path> [--episodes <n>] [--workflow <name>] [--recut <format>]"
---

Produce product demo video(s): $ARGUMENTS

Load `pipeline/product-demo-studio/SKILL.md` and follow its state machine. It is authoritative; this file is the entry point and the short list of things that go wrong.

## Preconditions — check before starting, do not infer

1. **Config exists** in the target repo with `environment.url`, `environment.reset`, `output_root`, brand tokens, and voice profile. Missing → copy the example, stop, ask.
2. **Calibration has passed** at least once. Never run → say so and load `pipeline/commands/demo-calibrate.md` first. Verdicts from unproven reviewers are unproven.
3. **The environment class is established** — resettable demo environment, live deployment with demo data, or live deployment with real user data. The third is `PIPELINE_BLOCKED`.
4. **Assessment has run** for the workflows in scope. Not run → load `pipeline/commands/demo-assess.md` first and produce only episodes it cleared.

## Two valid outcomes

**A gated video** for every episode clearing correctness, craft, and persuasion. **Product-Readiness Feedback and no video** for every episode that cannot. Both are complete, successful runs.

A **mediocre-but-accurate video** — correct, boring, feature-centered, no moment that makes anyone lean in — is the defect this pipeline exists to prevent. Never ship one to satisfy a request. Zero videos plus a clear report beats a catalog of adequate ones.

## What blocks, always

- Mocked screens, hardcoded results, recording-only code paths, or edited-over broken behaviour. Demo real working functionality against seeded data or produce nothing.
- Any visible value that does not match the truth sheet.
- Any claim in narration or on screen without evidence in the claim ledger.
- A synthetic-narration master without its AI-voice disclosure — and the same disclosure on every cut-down.
- Real user data, third-party marks you are not licensed to show, or placeholder text on the happy path.

## Where things go

Target repo is **read-only input**. Captures, manifests, narration, renders, evidence, and working memory go to the external video workspace. Only accepted final masters reach `output_root`. Never scaffold into the product source tree.

## Loop caps

Re-edit on a capture-fixable finding is capped at **two attempts**. A third means the finding was not actually capture-fixable — reclassify it, pull the episode, and route it to feedback. Generator and reviewer iterating past that converge on satisfying the reviewer, not on quality.

## Report back

Lead with `videos delivered`, `feedback-only`, or `mixed`. Then: each episode's verdict with deciding criteria, gate results, final filenames and their location, the feedback report path with product-fix-required count by severity, the shortest path to demo-readiness, working-package location, and anything still open.

State what is verified and what is not. Never claim delivery without the file existing at its stated path.
