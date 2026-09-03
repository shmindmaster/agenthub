# Workflow notes (load after the router picks a kind)

Viewer-facing jobs also load `engagement.md`. Kind rows there are the plate/rhythm defaults; this file is sequencing.

## briefing

Designed viewer experiences on the Remotion **archetype** kit, not a stack of dark-field slides. Default profile `briefing-board` 1600×1000. Not a product screencast.

1. Writer locks `screenplay.json` (`story-craft.md`: sceneRole, WIIFM, hook, one hero).
2. Storyboard locks `storyboard.json` (shot plan, archetype, sound, 2–3 scored hooks — pick internally).
3. Visuals locks `visual-bible.json`. Director maps archetypes and registers.
4. Generate owner voice through `ai.ps1 voice qwen-clone --voice sarosh`, identity-score, generate the bed unless `intent: draft`. Render composition `Briefing` from the house kit (do not `create-video` a new app). Sync kit source from `packages/media-studio/kit` first.
5. `Finish-Media.ps1 -Speech -Music`. Craft critic (score ≥ 85) then QA. Exact logos, numbers, and legal text are compositor-set type, never diffusion.

Remotion is required unless `intent: draft` or the user asked for a basic/proxy cut.

## training

Same crew, shorter scenes, one learning outcome per clip. Pattern interrupt between cards. Optional Remotion. `learning-studio` owns the question loop; this studio owns the film around it.

## explainer

`technical-explainer` owns comprehension. Wrap it in `story-craft.md` (Question → Stakes → Wrong intuition → Reveal → Demonstration → Implication → Takeaway). `technical-visualizer` picks the simplest truthful visual that maintains attention. Real UI claims still capture through Playwright. A diagram that never builds is unfinished. Remotion required unless draft.

## talking-head

Voice first, then lipsync. `ai.ps1 lipsync <video> --audio <wav>` (LatentSync 1.5). LivePortrait (`ai.ps1 portrait`) is specialty still-to-motion, not the default talking-head path. Face must stay visible; anime faces are out of scope for LatentSync. Viewer-facing: bed + register change on the payoff line.

## animation

Still from Visual Bank / Klein → Motif I2V (`ai.ps1 motif --reference --prompt --out`). Programmatic UI motion → Remotion, not Motif. Exact diagrams → SVG/Mermaid, never diffusion.

## audio-only

Voice and/or ACE-Step music. Do not start ComfyUI for music. Mix a bed under speech with `Finish-Media.ps1 -Speech -Music` (sidechain duck), then the same two-pass loudness finish. Silence on the key line.

## product-screencast

Do not load retired `product-demo*` skills. Stay in media-studio: `media-studio-capture` (Playwright + Recast), `media-studio-generate` (local voice), `$Pds\scripts` render/preflight, `media-studio-qa`. Keep `product-demo-studio.config.yaml` in the external job workspace; a legacy repo copy is read-only input and must not be created or updated. All capture and composition code stays external. Engagement is the PDS story-experience gate, not `engagement.md`.

## series-episode

`story-series` owns methodology and continuity. Tension/escalation/reveal craft is `story-craft.md`. Compose non-screencast picture here. Mix bed and holds in this studio. Remotion required unless draft.
