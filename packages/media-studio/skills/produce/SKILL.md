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
- Real product footage: drive the browser through `ah-browser` (agent-browser for clean takes; BrowserSkill for a signed-in profile). Record every take with `scripts/browser-take.mjs` (start, move, click, point, type, wheel, stop): it runs `record start <file> --cursor` and writes the timed action log the pointer-path gate reads. Never use real user data. Capture the real running product, never a stand-in, and run it on the authorized remote lane the private compute guidance names; the capture receipt records the lane, the exact product revision and the user role shown. Detail: [capture](references/capture.md), [recording](references/recording.md).
- Voice and narration: governed voice recipes only. [voice recipes](references/voice-recipes.md), [Azure](references/azure.md), [generate](references/generate.md).
- Pictures: charts, diagrams, Lottie, stills and captured screens. [visuals](references/visuals.md), [ladder](references/ladder.md).
- Providers and cost: [provider routing](references/provider-cost-quality-routing.md), [provider plugins](references/provider-plugins.md).
Read when executing a lane for its commands and gates: [capture detail](references/capture-detail.md), [generate detail](references/generate-detail.md).