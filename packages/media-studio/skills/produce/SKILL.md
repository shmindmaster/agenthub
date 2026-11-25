---
name: produce
description: Use when a ready storyboard needs footage, narration, stills, diagrams, animation or music.
---
# Produce
## Workflow contract
1. Use the internally accepted storyboard, picture plan and work list from `script`.
2. Make each asset with the cheapest authorized lane that passes its gate, and record each take with its evidence.
3. Hand `finish` the accepted voice, picture and plates.
4. If a lane is frozen, unpaid or failing, stop that asset and report the exact blocker; keep accepted assets.
## Make the pictures the brief calls for

Build code views, designed diagrams, simulations, synthetic UI, generated scenes, text or captures as the brief requires. A slow or static shot can give the viewer time to read or think. Keep provider eligibility, rights, privacy, credentials and spend checks in force.

## Record product interactions in verified footage

Capture the state before the action, the actual interaction and its visible result. Keep role, period, record and revision consistent with the spoken claim. In a stable frame, use a readable highlight or an enlarged detail of the actual field as the speaker names it. Show meaningful content changes; a camera drift across an idle screen adds no evidence. Keep sourced portraits steady and advance the relevant role or question on cue. Label illustrative footage and synthetic tenant data where a viewer could mistake them for case evidence.

Use official spoken clips and owner recordings as pronunciation guides. Compare in context, keep an original reading that is close, and repair an uneven reading with the same narrator's natural take or a newly recorded full sentence in the approved voice. Preserve the surrounding cadence and possessive endings. Introduce a different speaker at a deliberate sentence or passage boundary.

## Lanes
- Real product footage: drive clean takes through `ah-browser` and use `scripts/browser-take.mjs` (start, move, click, point, type, wheel, stop) for a cursor recording and the timed action log the pointer-path gate reads. If a selected signed-in profile requires BrowserSkill, its exported MP4 is supplemental footage. See [recording](references/recording.md) for that handoff. Use synthetic data on the real running product and the authorized remote capture lane. Record the lane, exact product revision and user role shown. Detail: [capture](references/capture.md).
- Voice and narration: run the [current rates and funding preflight](references/narration-preflight.md) before new synthesis. Deepgram Flux is the default. AssemblyAI and ElevenLabs are for ABACare films, or a job where the owner asks for them by name. Keep accepted takes and explicitly pinned casts. Use the chosen governed adapter. [voice recipes](references/voice-recipes.md), [Azure](references/azure.md), [generate](references/generate.md).
- Pictures: charts, diagrams, Lottie, stills and captured screens. [visuals](references/visuals.md), [ladder](references/ladder.md).
- For animation that serves the brief, use a [narration-led explainer shot](references/explainer-shots.md), the shot clock, the existing kit and the accepted assets.
- Self-hosted GPU lab (image, edit, video, talk, voice, transcribe, music): not chat-model picker entries; use `scripts/daytona_media_client.py` or `scripts/media_lab_ui.py`.
- Providers and cost: [provider routing](references/provider-cost-quality-routing.md), [provider plugins](references/provider-plugins.md).
Read when executing a lane for its commands and gates: [capture detail](references/capture-detail.md), [generate detail](references/generate-detail.md).
