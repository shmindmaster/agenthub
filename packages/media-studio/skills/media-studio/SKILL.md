---
name: media-studio
description: Use when the user wants any video, audio, animation, briefing, training clip, explainer, talking-head, webcast, webinar, keynote, documentary, teaser, or live-product screencast from a concept or outline. Single local creative studio. Orchestrates writing, direction, Local-AI generation, Playwright capture, Remotion/FFmpeg compose, and release gates. Replaces product-demo-studio as the public video pack.
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

## 1. Rapid path

1. Infer **`programForm`** then **kind** from `references/program-forms.md`. Create `job.json` in the external workspace and validate that the workspace is outside any source repository. Default `intent: viewer-facing` unless the user asked for a scratch, proxy, or timing pass (`draft`). Set `deliveryProfile` from `references/delivery-profiles.md`. `craftScoreMin` defaults to 85. One promise per film. Recuts of a locked master set `sourceJobId`.
2. Defaults: owner/internal voice `sarosh`; briefing-board 1600×1000 30 fps; duration ~150 wpm (slower for `documentary` / `ai-trust`). Viewer-facing jobs load `references/engagement.md`, `story-craft.md`, `studio-craft.md`, and `program-forms.md` before the writer. Product screencasts use the PDS killer-demo guide plus outcome-first rules in `program-forms.md`.
3. `media-writer` → locked screenplay (`hook`, `sceneRole`, `wiifm`, one hero).
4. `media-storyboard` → timed beats, scored hook (pick internally), archetypes. Then `media-studio-visuals` → `visual-bible.json`.
5. `media-director` → archetype, register, `sound`. `screen` only for a running product.
6. `media-studio-generate` + `local-ai-stack` → TTS. Viewer-facing: also the directed music bed. Motif/lipsync/portrait only when direction called for that plate. `draft` skips those GPU plates and records the skip.
7. Compose: Remotion archetype kit, FFmpeg mux (duck the bed), or Recast for a captured product trace (`media-studio-capture`). Viewer-facing `briefing` / `training` / `explainer` / `series-episode` / `webcast` / `webinar` / `keynote` / `documentary` / `teaser` **requires Remotion** unless `intent: draft` or the user asked for a basic/proxy cut. If Remotion skills are missing, stop and say so — do not silently fall back to static slides. Buyer-facing product forms use **real captured UI**, not an avatar over fake chrome.
8. `media-story-experience-reviewer` on the encoded file. Score < `craftScoreMin` → revise `reviseSceneIds` and rerun. Then `media-studio-qa`: screencast → PDS gates. Other kinds → identity-score, `ai.ps1 listen`, engagement pass, `Inspect-MediaVisualQuality.ps1`.

Owner voice: `ai.ps1 voice qwen-clone --voice sarosh` only.

Viewer-facing explainers, branded films, and series: load `technical-storytelling` and, when installed, third-party `creative-writing-skills`. Descript stays optional finishing (`media-studio-descript`).

## 2. Kind

| Signal | Kind | Path |
| --- | --- | --- |
| Live app walkthrough, demo-worthiness, pointer/click | `product-screencast` | assess (`$Pds\pipeline\commands\demo-assess.md`) → capture → local voice → Recast → QA |
| Series / Receipts episode | `series-episode` | `story-series` then compose here |
| Argument, prep, briefing | `briefing` | Remotion archetype kit + local voice + bed |
| Exam / how-to clip | `training` | Remotion (or FFmpeg if draft) |
| Technical idea, no live product required | `explainer` | Remotion + `story-craft.md` |
| Face + new audio | `talking-head` | voice then `ai.ps1 lipsync` |
| Animate a still | `animation` | Motif and/or Remotion |
| Voiceover or bed only | `audio-only` | `ai.ps1 voice` / `music` |
| One-to-many broadcast, town hall, launch | `webcast` | Remotion speaker+slide, lower-thirds, chapters |
| Taught session with Q&A chapters | `webinar` | Same kit; chapter cards; recorded Q&A |
| Speaker-led argument | `keynote` | Talking-head coverage + slides, not one webcam lock |
| Picture-led film | `documentary` | B-roll, slower VO, silence for image |
| 15–45s hook / social | `teaser` | One promise, no intro |

## 3. product-screencast (was product-demo-studio)

Same fail-closed engine, invoked from here:

1. Config in the external job workspace: `product-demo-studio.config.yaml`. A legacy repo copy may be read once, but never created or updated; copy/translate it externally and record its source hash.
2. Assessment first if never run (`$Pds\pipeline\commands\demo-assess.md`). Feedback instead of a mediocre video is a valid outcome.
3. `media-studio-capture` — Playwright + Recast pointer/click.
4. `media-studio-generate` — local Sarosh, not cloud TTS.
5. `$Pds\scripts` render/preflight.
6. `media-studio-qa` — four domain reviews, arbiter, final verifier.

Live product with real user data → `PIPELINE_BLOCKED`.

If the external workspace cannot be established without touching the product
repository, return `PIPELINE_BLOCKED`. Do not fall back to scaffolding inside
the repo.

## 4. Stop

- Real user data on a live product.
- Owner voice via cloud TTS.
- Invented metrics or customer names.
- Remotion missing for viewer-facing briefing/training/explainer/series-episode/webcast/webinar/keynote/documentary/teaser (unless draft).
- Feature-tour opening or a settings walkthrough posing as a demo.
- Story-experience score below 85.

## 5. Final check

- [ ] Workspace is external; `repositoryWritePolicy: read-only`
- [ ] Crew ran writer → storyboard → visuals → director → generate → compose → critic → QA
- [ ] Viewer-facing: engagement + story-craft + studio-craft loaded; Remotion used when required
- [ ] `programForm` inferred; one promise; real UI is capture when the form is buyer-facing product
- [ ] Critic score ≥ 85 or the job is draft
