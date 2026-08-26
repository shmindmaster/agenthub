---
name: media-studio
description: Use when the user wants any video, audio, animation, briefing, training clip, explainer, talking-head, or live-product screencast from a concept or outline. Single local creative studio. Orchestrates writing, direction, Local-AI generation, Playwright capture, Remotion/FFmpeg compose, and release gates. Replaces product-demo-studio as the public video pack.
---

# Media studio — producer

**This is the only public video plugin.** Product Demo Studio is the internal screencast engine (scripts, review agents, Recast). Do not load `product-demo` or `product-demo-studio-*` skills; they are retired.

**Default: rapid.** A concept, outline, or bullets is enough. Infer the rest, run the crew, return a candidate.

Runtime: `%LOCALAPPDATA%\AgentHub\media-studio\<job-id>`. Never write media into AgentHub or a product repo.

Screencast engine root:

```powershell
$Pds = Join-Path ($(if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' })) 'packages\product-demo-studio'
```

## Rapid path

1. Infer **kind** (table). Create `job.json`.
2. Defaults: owner/internal voice `sarosh`; briefings 1600×1000 30 fps; duration ~150 wpm.
3. `media-writer` → locked screenplay.
4. `media-director` → visual mode. `screen` only for a running product.
5. `media-studio-generate` + `local-ai-stack` → TTS. Skip Motif/lipsync/music unless needed.
6. Compose: briefing kit Remotion, FFmpeg mux, or Recast for a captured product trace (`media-studio-capture`).
7. Screencast kind also runs `media-studio-qa` (PDS gates, local `ai.ps1 listen`). Other kinds: identity-score owner voice and stop.

Owner voice: `ai.ps1 voice qwen-clone --voice sarosh` only.

## Kind

| Signal | Kind | Path |
| --- | --- | --- |
| Live app walkthrough, demo-worthiness, pointer/click | `product-screencast` | assess (`$Pds\commands\demo-assess.md`) → capture → local voice → Recast → QA |
| Series / Receipts episode | `series-episode` | `story-series` then compose here |
| Argument, prep, briefing, slide-led | `briefing` | Remotion kit + local voice |
| Exam / how-to clip | `training` | Remotion or FFmpeg |
| Technical idea, no live product required | `explainer` | Remotion + diagrams |
| Face + new audio | `talking-head` | voice then `ai.ps1 lipsync` |
| Animate a still | `animation` | Motif and/or Remotion |
| Voiceover or bed only | `audio-only` | `ai.ps1 voice` / `music` |

## product-screencast (was product-demo-studio)

Same fail-closed engine, invoked from here:

1. Config in the product repo: `product-demo-studio.config.yaml` (filename kept; it is product-repo config, not a skill).
2. Assessment first if never run (`$Pds\commands\demo-assess.md`). Feedback instead of a mediocre video is a valid outcome.
3. `media-studio-capture` — Playwright + Recast pointer/click.
4. `media-studio-generate` — local Sarosh, not cloud TTS.
5. `$Pds\scripts` render/preflight.
6. `media-studio-qa` — four domain reviews, arbiter, final verifier.

Live product with real user data → `PIPELINE_BLOCKED`.

## Stop

- Real user data on a live product.
- Owner voice via cloud TTS.
- Invented metrics or customer names.
- Remotion missing for slides → FFmpeg stills + voice, say what was skipped.
