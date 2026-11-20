---
name: produce
description: Produces the accepted pieces a video needs (screen takes, narration, voices, stills, diagrams, animation and music) under spend controls. Use when a storyboard is approved and needs footage, voice, images or visuals made. Not for assembly or review; use finish.
---
# Produce
## Workflow contract
1. Use the approved storyboard, picture plan and work list from `script`.
2. Make each asset with the cheapest authorized lane that passes its gate, and record each take with its evidence.
3. Hand `finish` the accepted voice, picture and plates.
4. If a lane is frozen, unpaid or failing, stop that asset and report the exact blocker; keep accepted assets.
## Lanes
- Real product footage: drive clean takes through `ah-browser` and use `scripts/browser-take.mjs` (start, move, click, point, type, wheel, stop) for a cursor recording and the timed action log the pointer-path gate reads. If a selected signed-in profile requires BrowserSkill, its exported MP4 is supplemental footage. See [recording](references/recording.md) for that handoff. Use synthetic data on the real running product and the authorized remote capture lane. Record the lane, exact product revision and user role shown. Detail: [capture](references/capture.md).
- Voice and narration: governed voice recipes only. [voice recipes](references/voice-recipes.md), [Azure](references/azure.md), [generate](references/generate.md).
- Pictures: charts, diagrams, Lottie, stills and captured screens. [visuals](references/visuals.md), [ladder](references/ladder.md).
- Providers and cost: [provider routing](references/provider-cost-quality-routing.md), [provider plugins](references/provider-plugins.md).
Read when executing a lane for its commands and gates: [capture detail](references/capture-detail.md), [generate detail](references/generate-detail.md).
