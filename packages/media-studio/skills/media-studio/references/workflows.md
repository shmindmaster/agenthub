# Workflow notes (load after the router picks a kind)

## briefing

Narrated motion slides. Measured example class: ~24 min, 1600×1000, H.264 + AAC 48 kHz, dark field, yellow headline, color-coded bullets, owner voice. Not a product screencast.

1. Writer locks a screenplay: one idea per scene, spoken words canonical (no phonetic respelling).
2. Director sets slide layout, emphasis color, hold time. Motion teaches order; decoration is refused.
3. Generate owner voice through `ai.ps1 voice qwen-clone --voice sarosh`, identity-score, then render the house kit `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit` composition `Briefing` (do not `create-video` a new app).
4. FFmpeg only for delivery normalize / caption burn-in.

Exact logos, numbers, and legal text are compositor-set type, never diffusion.

## training

Same crew, shorter scenes, one learning outcome per clip. Optional Remotion. `learning-studio` owns the question loop; this studio owns the film around it.

## explainer

`technical-explainer` + `technical-visualizer` choose screen vs diagram vs animation vs narration-only. This studio then writes, generates, and composes. Real UI claims still capture through product-demo-studio / Playwright.

## talking-head

Voice first, then lipsync. `ai.ps1 lipsync <video> --audio <wav>` (LatentSync 1.5). LivePortrait (`ai.ps1 portrait`) is specialty still-to-motion, not the default talking-head path. Face must stay visible; anime faces are out of scope for LatentSync.

## animation

Still from Visual Bank / Klein → Motif I2V (`ai.ps1 motif --reference --prompt --out`). Programmatic UI motion → Remotion, not Motif. Exact diagrams → SVG/Mermaid, never diffusion.

## audio-only

Voice and/or ACE-Step music. Do not start ComfyUI for music. Mix a bed under speech after both exist.

## product-screencast

Do not load retired `product-demo*` skills. Stay in media-studio: `media-studio-capture` (Playwright + Recast), `media-studio-generate` (local voice), `$Pds\scripts` render/preflight, `media-studio-qa`. Product-repo config filename stays `product-demo-studio.config.yaml`.

## series-episode

`story-series` owns methodology. Compose non-screencast picture here.
