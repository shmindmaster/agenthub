---
name: product-demo-studio-capture
description: Use when a real product workflow needs deterministic screen capture, walkthrough recording, screenshots, demo evidence, or reproducible UI plates for external finishing.
---

# Product Demo Capture

Capture the real product at a controlled viewport with coherent synthetic state. Capture quality cannot rescue a product defect; route product-fix-required findings back to Product Experience Engineering before master capture.

## Capture contract

1. Verify the deployed commit, authenticated role, seed/reset path, expected workflow, and clean browser profile.
2. Lock viewport, device scale, browser zoom, capture resolution, and crop. Record `plannedActiveRegionCoverage` and `deliveredCrop`; reject wasted framing or insufficient delivered pixel density.
3. Use Playwright CLI for agent-operated capture and Playwright Test when the same sequence must rerun deterministically. Preserve the trace, its sibling high-resolution WebM, console/network evidence, and reset evidence in the external workspace.
4. Record one beat per meaningful action: starting state, locator, interaction, pointer path, visible feedback, result hold, and claim IDs. Type at a readable accelerated pace; never make viewers watch real-time entry.
5. Keep the cursor visible but quiet. Lead the eye before a click, show a restrained click cue, preserve native hover/focus feedback, and use held/trail feedback for drags. Do not add overlays that imply product behavior.
6. Pause on the visible payoff. Narration must not announce a result before it appears.

Validate storyboards with `../../scripts/validate-storyboard.mjs`, capture manifests with `../../scripts/validate-capture-manifest.mjs`, and the bound craft report with `../../scripts/validate-craft-contracts.mjs`. A passing script contract is necessary but does not replace playback review.

Use the source WebM, not trace screenshots, for the final video. Trace frames are metadata fallback only. Keep all capture files outside the product repository.

