---
name: product-demo
description: Use when someone mentions a product demo video, product screencast, live-product walkthrough, product tour, or demo-worthiness assessment. Entry-point router for product-demo-studio. For briefings, training films, explainers, talking-heads, animations, or other non-screencast video, use media-studio instead.
---

# Product demo work — router

Recognize the intent, confirm the two facts every path needs, dispatch. **Do not load the full pipeline skill to answer a question about it** — that skill is the state machine, and it costs an order of magnitude more context than deciding what to run.

## Step 1 — Which intent

| What they want | Route to | Loads |
|---|---|---|
| Briefing, training film, explainer, talking-head, animation, or audio that is not a live-product screencast. | `media-studio` | media-studio router |
| Is this product ready for a demo? Why isn't it? Product-readiness feedback. | load `pipeline/commands/demo-assess.md` | assessment only |
| Make, regenerate, or re-cut a **product screencast** demo. | `media-studio` `/video` (kind `product-screencast`) | full pipeline |
| Prove the review gates still work. Fixtures. Drift. | load `pipeline/commands/demo-calibrate.md` | fixtures only |
| A narrow technical question — TTS provider, ffprobe check, Recast composition, Descript editing. | the matching `product-demo-studio-*` subskill directly | that subskill |
| A composition genuinely needs Remotion and is not this screencast pipeline. | `media-studio-compose` then official Remotion skills | those skills |
| Anything about how the system works, what the outcomes are, what a criterion means. | answer from this file or `docs/`; load nothing | nothing |

**When the intent is a video but the product has never been assessed, load `pipeline/commands/demo-assess.md` first and say why.** A capture run against a product that cannot carry a demo produces a mediocre video or a wasted run. Assessment costs minutes and needs no capture, narration, or render. Public video entry remains media-studio `/video`.

## Step 2 — Confirm two facts, infer neither

**The repo path.** Absolute. If several products exist, ask which — do not guess from the last one mentioned.

**The environment.** `environment.url` in that repo's `product-demo-studio.config.yaml`, and what class it is:

- Resettable demo environment → full assessment, `deterministic-resettable` is evidenceable by reset.
- Live public deployment seeded with demo data → assessment proceeds, but that criterion is evidenced by walking the flow twice and comparing. Record the substitution. A second walk proves reproduction, not resettability.
- Live deployment carrying real user data → stop. `PIPELINE_BLOCKED`. Do not walk flows that may surface another person's data.

No config file → copy `product-demo-studio.config.example.yaml` into the repo and stop. **Never infer a URL, a reset command, a persona, an output location, or a tracker project.**

## Step 3 — Dispatch

Run the command. Do not restate the pipeline, summarize the state machine, or preview what each stage will do. The command owns its own procedure.

## What every path guarantees

Two valid outcomes per episode, and one defect this system exists to prevent:

- **A gated video** — clears correctness, craft, and persuasion. Ship it.
- **Product-Readiness Feedback, no video** — the product cannot carry a demo worth watching today. A build spec with a fix per defect.
- **A mediocre-but-accurate video** — technically correct, boring, feature-centered, nothing that makes anyone lean in. **Never ship this.** Zero videos plus a clear report is a complete, successful run.

If someone asks for a video and the honest answer is feedback, give them feedback. Do not lower the bar to produce an artifact.

## Multiple products

One plugin, any product. Nothing product-specific lives in the plugin — `product-demo-studio.config.yaml` in each repo supplies everything. Assess or produce per repo; never merge two products into one run, and never carry one product's persona, seed data, or brand tokens into another's.

## Before the first run anywhere

Calibration (`pipeline/commands/demo-calibrate.md`) must have passed at least once. Verdicts from uncalibrated reviewers are unproven, and a gate nobody has tested is a gate in name only. If it has never run, say so and run it first.
