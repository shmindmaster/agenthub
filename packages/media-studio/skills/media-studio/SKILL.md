---
name: media-studio
description: Use when the user wants any video, audio, animation, briefing, training clip, explainer, talking-head, or live-product screencast from a concept or outline. Single local creative studio. Orchestrates writing, direction, Local-AI generation, Playwright capture, Remotion/FFmpeg compose, and release gates. Replaces product-demo-studio as the public video pack.
---

# Media studio — producer

**This is the only public video plugin.** Product Demo Studio is the internal screencast engine (scripts, review agents, Recast). Do not load `product-demo` or `product-demo-studio-*` skills; they are retired.

**Default: rapid.** A concept, outline, or bullets is enough. Infer the rest, run the crew, return a candidate. Rapid means infer-and-run, not skip craft.

Runtime: `%LOCALAPPDATA%\AgentHub\media-studio\<job-id>`. Never write media into AgentHub or a product repo.

**Hard repository boundary:** a product repository is read-only input. Before
the first write, record `repositoryWritePolicy: read-only` and the absolute
external `workspace` in `job.json`. Do not create or modify video code,
Playwright specs, Remotion compositions, dependencies, configuration, seed
fixtures, assets, evidence, generated media, or Git state in the product repo.
If a product change is needed, return Product-Readiness Feedback and open a
separate engineering task only when explicitly authorized.

Screencast engine root:

```powershell
$Pds = Join-Path ($(if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' })) 'packages\product-demo-studio'
```

## Rapid path

1. Infer **kind** (table). Create `job.json` in the external workspace and validate that the workspace is outside any source repository. Default `intent: viewer-facing` unless the user asked for a scratch, proxy, or timing pass (`draft`).
2. Defaults: owner/internal voice `sarosh`; briefings 1600×1000 30 fps; duration ~150 wpm. Viewer-facing jobs load `references/engagement.md` before the writer. Product screencasts use the PDS killer-demo guide instead.
3. `media-writer` → locked screenplay (`hook`, `emotionalTarget`, pauses).
4. `media-director` → visual mode, `musicCue`, hold. `screen` only for a running product.
5. `media-studio-generate` + `local-ai-stack` → TTS. Viewer-facing: also the directed music bed. Motif/lipsync/portrait only when direction called for that plate. `draft` skips those GPU plates and records the skip.
6. Compose: briefing kit Remotion, FFmpeg mux (duck the bed), or Recast for a captured product trace (`media-studio-capture`).
7. `media-studio-qa`: screencast → PDS gates. Other kinds → identity-score, `ai.ps1 listen`, engagement pass on the encoded file.

Owner voice: `ai.ps1 voice qwen-clone --voice sarosh` only.

## Kind

| Signal | Kind | Path |
| --- | --- | --- |
| Live app walkthrough, demo-worthiness, pointer/click | `product-screencast` | assess (`$Pds\commands\demo-assess.md`) → capture → local voice → Recast → QA |
| Series / Receipts episode | `series-episode` | `story-series` then compose here |
| Argument, prep, briefing, slide-led | `briefing` | Remotion kit + local voice + bed |
| Exam / how-to clip | `training` | Remotion or FFmpeg |
| Technical idea, no live product required | `explainer` | Remotion + diagrams |
| Face + new audio | `talking-head` | voice then `ai.ps1 lipsync` |
| Animate a still | `animation` | Motif and/or Remotion |
| Voiceover or bed only | `audio-only` | `ai.ps1 voice` / `music` |

## product-screencast (was product-demo-studio)

Same fail-closed engine, invoked from here:

1. Config in the external job workspace: `product-demo-studio.config.yaml`. A legacy repo copy may be read once, but never created or updated; copy/translate it externally and record its source hash.
2. Assessment first if never run (`$Pds\commands\demo-assess.md`). Feedback instead of a mediocre video is a valid outcome.
3. `media-studio-capture` — Playwright + Recast pointer/click.
4. `media-studio-generate` — local Sarosh, not cloud TTS.
5. `$Pds\scripts` render/preflight.
6. `media-studio-qa` — four domain reviews, arbiter, final verifier.

Live product with real user data → `PIPELINE_BLOCKED`.

If the external workspace cannot be established without touching the product
repository, return `PIPELINE_BLOCKED`. Do not fall back to scaffolding inside
the repo.

## Stop

- Real user data on a live product.
- Owner voice via cloud TTS.
- Invented metrics or customer names.
- Remotion missing for slides → FFmpeg stills + voice, say what was skipped.
