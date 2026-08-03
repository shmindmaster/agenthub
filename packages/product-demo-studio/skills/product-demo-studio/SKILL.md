---
name: product-demo-studio
description: Use when a product workflow needs demo-worthiness assessment, video planning, capture, narration, rendering, critique, inventory, or an interactive product deep-dive.
---

# Product Demo Studio

Produce one of two honest outcomes: a professionally finished, fully gated video or concise Product-Readiness Feedback. Product repositories are read-only inputs. Traces, narration, caches, evidence, and render candidates stay in the external workspace created by `../../scripts/scaffold-video-workspace.mjs`; accepted videos go to the product path in `../../../../registry/product-video-delivery.json`.

## Route

1. Require the current `product-experience-engineering:prepare-product-for-demo` handoff. If the workflow is not reachable, truthful, seeded, resettable, and visually coherent, stop with product feedback.
2. Dispatch `../../agents/episode-architect.agent.md`, then `../../agents/script-storyboard-generator.agent.md`. Bind every spoken or visible claim to evidence.
3. Use `product-demo-studio-capture` with `../../agents/capture-product-state-generator.agent.md` for real product state and deterministic action timing.
4. Use `product-demo-studio-narration` and `../../agents/narration-audio-generator.agent.md` after the storyboard is locked.
5. Use `product-demo-studio-render` and `../../agents/composition-render-generator.agent.md` for the proxy and final candidate. Run `../../scripts/detect-media-acceleration.mjs`; GPU preference is evidence, not an assumption.
6. Use `product-demo-studio-qa`. Automated preflight must pass before exactly four independent domain reviews. The Release Arbiter may pass, remediate, product-block, or pipeline-block; it cannot waive a gate.
7. Remediation uses `../../agents/remediation-agent.agent.md`, followed by a new render and the affected reviews. No render or edit is allowed after verification.
8. After arbiter PASS, dispatch `../../agents/final-verifier.agent.md`. The first human touchpoint is the final presentation or the explicit blocked result, not unfinished production debris.

## Production rules

- Capture with Playwright CLI or Playwright Test. Finish normal demos with Recast for cursor, click, animated zoom, pacing, and voice timing. Use `page.setContent()` for title and end cards. Use FFmpeg only for delivery normalization and caption burn-in.
- Use coherent synthetic data and dedicated accounts. Never show credentials, customer data, unrelated tabs, notifications, or unstable environments.
- Keep pointer motion purposeful, focus visible, result holds long enough to read, and narration behind the action it describes.
- Use the private review-delivery lane only after the immutable candidate, evidence, four reviews, arbiter decision, and final verification agree on the same bytes.
- Remotion is an exceptional compositor, not the default. When a concept genuinely needs it, use the official `remotion:remotion-best-practices` capability rather than vendoring its rules here.

Read `references/killer-demo-playbook.md` only for story/craft decisions and `references/killer-demo-production-guide.md` only for detailed production constraints. Do not reproduce those guides in the product repository.

