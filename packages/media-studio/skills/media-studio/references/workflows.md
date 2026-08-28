# Workflow notes (load after the router picks a kind)

Viewer-facing jobs also load `engagement.md`. Kind rows there are the plate/rhythm defaults; this file is sequencing.

## briefing

Narrated motion slides. Measured example class: ~24 min, 1600×1000, H.264 + AAC 48 kHz, dark field, yellow headline, color-coded bullets, owner voice, ducked bed. Not a product screencast.

1. Writer locks a screenplay: one idea per scene, hook in 5–8s, spoken words canonical (no phonetic respelling).
2. Director sets slide layout, emphasis color, Remotion build-in, hold time, `musicCue`. Motion teaches order; decoration is refused.
3. Generate owner voice through `ai.ps1 voice qwen-clone --voice sarosh`, identity-score, generate the bed unless `intent: draft`, then render the house kit `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit` composition `Briefing` (do not `create-video` a new app).
4. `Finish-Media.ps1 -Speech -Music` for duck + two-pass linear loudness (−16 LUFS / −1.5 dBTP) and AAC 48 kHz. Recast/Remotion burn captions from the locked spoken words.

Exact logos, numbers, and legal text are compositor-set type, never diffusion.

## training

Same crew, shorter scenes, one learning outcome per clip. Pattern interrupt between cards. Optional Remotion. `learning-studio` owns the question loop; this studio owns the film around it.

## explainer

`technical-explainer` + `technical-visualizer` choose screen vs diagram vs animation vs narration-only. This studio then writes, generates, and composes. Real UI claims still capture through product-demo-studio / Playwright. A diagram that never builds is a still — treat it as unfinished for viewer-facing.

## talking-head

Voice first, then lipsync. `ai.ps1 lipsync <video> --audio <wav>` (LatentSync 1.5). LivePortrait (`ai.ps1 portrait`) is specialty still-to-motion, not the default talking-head path. Face must stay visible; anime faces are out of scope for LatentSync. Viewer-facing: bed + register change on the payoff line.

## animation

Still from Visual Bank / Klein → Motif I2V (`ai.ps1 motif --reference --prompt --out`). Programmatic UI motion → Remotion, not Motif. Exact diagrams → SVG/Mermaid, never diffusion.

## audio-only

Voice and/or ACE-Step music. Do not start ComfyUI for music. Mix a bed under speech with `Finish-Media.ps1 -Speech -Music` (sidechain duck), then the same two-pass loudness finish. Silence on the key line.

## product-screencast

Do not load retired `product-demo*` skills. Stay in media-studio: `media-studio-capture` (Playwright + Recast), `media-studio-generate` (local voice), `$Pds\scripts` render/preflight, `media-studio-qa`. Keep `product-demo-studio.config.yaml` in the external job workspace; a legacy repo copy is read-only input and must not be created or updated. All capture and composition code stays external. Engagement is the PDS story-experience gate, not `engagement.md`.

## series-episode

`story-series` owns methodology. Compose non-screencast picture here. Mix bed and holds in this studio.
