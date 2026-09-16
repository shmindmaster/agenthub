---
name: media-studio
description: Use when the user wants any video, audio, animation, briefing, training clip, explainer, talking-head, webcast, webinar, keynote, documentary, teaser, or live-product screencast from a concept or outline. Infer the form from the ask and run that workflow. Single local creative studio. Orchestrates writing, direction, Local-AI generation, Playwright capture, Remotion/FFmpeg compose, and release gates.
---

# Media studio — producer

**This is the only video plugin.** The user does not name skills, kinds, or pipeline steps. Infer `programForm` and kind from the ask — product demo, briefing, explainer, talking-head, webcast, teaser, or anything else in the kind table — then run the **full crew**. Do not ask them to pick a plugin. Do not load retired `product-demo*` skills.

**Default: rapid.** A sentence, path, or “make a video from this” is enough. Infer the rest, run the crew, return a candidate. Rapid means infer-and-run, **not skip craft**. A short prompt is not permission to skip curation, gap-closure, story, scenes, or QA.

## 0. Intake (do not dump this on the user)

A usable ask is: what it is about, plus any source (evidence folder, outline, product). Load Local-AI yourself. Do not tell the user to invoke `/local-ai-stack` or name writer/storyboard/director.

**Infer, do not ask:**

| Need | Default |
| --- | --- |
| Kind / form | Kind table + `program-forms.md`. A running product as the subject is `product-screencast` (`product-picture.md`) |
| Audience | `private` if they said private/internal/for me; else infer from source |
| Voice | `sarosh` |
| Intent | `viewer-facing` (craft ≥ 85) unless they asked for a scratch/proxy |
| Workspace | `%LOCALAPPDATA%\AgentHub\media-studio\<slug>` |
| Delivery | Path they named, else `registry/product-video-delivery.json` `reviewRoot` for that product |
| Plates | Named evidence tree; prefer `*annotated*` / markup shots over raw; do not recapture live prod |

**Ask at most one question, and only if blocked:** no source at all; live production with real user data (`PIPELINE_BLOCKED` — do not offer to proceed); destination unknown and the product is not in the delivery registry. Do not ask them to choose kind, act structure, tone, duration, or which skills to load.

**Always run, even when the prompt is one line:**

1. **Curate** — read the source; pick plates (annotated first); drop noise.
2. **Close gaps** — product-screencast: Product-Readiness Feedback instead of a mediocre video is a valid stop. Load `references/product-picture.md`. Evidence briefing: ledger status is the truth (merged ≠ deployed); missing plates get a spoken/typed beat, not invented UI.
3. **Write** — `media-writer` locks screenplay + narration (`story-craft.md`).
4. **Scenes** — `media-storyboard` then `media-studio-visuals` then `media-director`.
5. **Generate / compose / critic / QA** — Local-AI voice, Remotion/Recast/FFmpeg, score ≥ 85, then `media-studio-qa`.

Do not jump to encode from screenshots. Do not ship a slide-stack of the ledger. Do not Ken Burns a product PNG and call it a screencast.

Runtime: `%LOCALAPPDATA%\AgentHub\media-studio\<job-id>`. Never write media into AgentHub or a product repo.

**Hard repository boundary:** a product repository is read-only input. Before
the first write, record `repositoryWritePolicy: read-only` and the absolute
external `workspace` in `job.json`. Do not create or modify video code,
Playwright specs, Remotion compositions, dependencies, configuration, seed
fixtures, assets, evidence, generated media, or Git state in the product repo.
If a product change is needed, return Product-Readiness Feedback and open a
separate engineering task only when explicitly authorized.

## 1. Rapid path

1. Infer **`programForm`** then **kind** from `references/program-forms.md`. Create `job.json` in the external workspace and validate that the workspace is outside any source repository. Default `intent: viewer-facing` unless the user asked for a scratch, proxy, or timing pass (`draft`). Set `deliveryProfile` from `references/delivery-profiles.md`. `craftScoreMin` defaults to 85. One promise per film. Recuts of a locked master set `sourceJobId`.
2. Defaults: owner/internal voice `sarosh`; briefing-board 1600×1000 30 fps; duration ~150 wpm (slower for `documentary` / `ai-trust`). Viewer-facing jobs load `references/engagement.md`, `story-craft.md`, `studio-craft.md`, and `program-forms.md` before the writer. If a running product is the subject, `kind` is `product-screencast` even when the ask said briefing, tutorial, or walkthrough — load `references/product-picture.md`. Product screencasts use `references/killer-demo-production-guide.md` plus outcome-first rules in `program-forms.md`. A product or engineering **change** told as a story (a fix, an incident, a new capability) is `programForm: technical-story`: load `references/technical-story.md` — 5–8 minutes, hook on the problem, flow overlay, code reveal of the 5–20 lines that matter, before/after, replay, what it means.
3. `media-writer` → locked screenplay (`hook`, `sceneRole`, `wiifm`, one hero).
4. `media-storyboard` → timed beats, scored hook (pick internally), archetypes. Then `media-studio-visuals` → `visual-bible.json`.
5. `media-director` → archetype, register, `sound`. `screen` only for a running product.
6. `media-studio-generate` + `local-ai-stack` → TTS. Viewer-facing: also the directed music bed. Motif/lipsync/portrait only when direction called for that plate. `draft` skips those GPU plates and records the skip.
7. Compose: Remotion archetype kit, FFmpeg mux (duck the bed), or Recast for a captured product trace (`media-studio-capture`). Product-screencast: run `scripts/validate-product-picture.mjs` before encode. Viewer-facing `briefing` / `training` / `explainer` / `series-episode` / `webcast` / `webinar` / `keynote` / `documentary` / `teaser` **requires Remotion** unless `intent: draft` or the user asked for a basic/proxy cut. If Remotion skills are missing, stop and say so — do not silently fall back to static slides. Buyer-facing product forms use **real captured UI** with pointer, click, zoom, and visible result (`product-picture.md`), not an avatar over fake chrome and not Ken Burns on a screenshot.
8. Craft review is `media-story-experience-reviewer` on the **encoded** file. Product-screencast also runs `scripts/validate-product-picture.mjs`. Score < `craftScoreMin` → revise `reviseSceneIds` and rerun. Then `media-studio-qa`.

Owner voice: `ai.ps1 voice qwen-clone --voice sarosh` only.

Viewer-facing explainers, branded films, and series: load `technical-storytelling` and, when installed, third-party `creative-writing-skills`. Descript stays optional finishing (`media-studio-descript`).

## 2. Kind

| Signal | Kind | Path |
| --- | --- | --- |
| Running product, workflow, demo, tutorial-in-the-app, pointer/click | `product-screencast` | `product-picture.md` → capture (WebM + Recast) → local voice → compose → product-picture + QA |
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

## 3. product-screencast

1. Job config is `job.json` in the external workspace. A legacy `product-demo-studio.config.yaml` in a product repo may be read once, then translated out; never create or update one in the product repo.
2. Product-Readiness Feedback instead of a mediocre video is a valid outcome.
3. `media-studio-capture` — Playwright WebM + Recast via `kit/screencast/record-job.mjs`. PNG plates are diagnostic only.
4. `media-studio-generate` — local Sarosh, not cloud TTS. Never Motif a product screenshot.
5. `scripts/validate-product-picture.mjs` before encode.
6. `media-studio-qa` — product-picture + encoded-file review. Story review on the encoded file only.

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
- Product-screencast whose picture is Ken Burns stills, auto-cards, or a slide stack (`product-picture.md`).
- Story-experience score below 85. A pre-capture text-only score is not a pass.
- An addendum or correction clip. Re-record the affected section and re-cut the master.

Delivery: file names are `NN - Title.mp4` with no product prefix; a delivered series has a `README.md` index; superseded masters and reproducible intermediates are deleted outright, never parked in `_retired` / `_old` folders. Status claims name where the film actually is: merged to dev → in main → deployed → production-verified.

## 5. Final check

- [ ] Workspace is external; `repositoryWritePolicy: read-only`
- [ ] Crew ran writer → storyboard → visuals → director → generate → compose → critic → QA
- [ ] Viewer-facing: engagement + story-craft + studio-craft loaded; Remotion used when required
- [ ] `programForm` inferred; one promise; real UI is capture + Recast when the form is a running product (`product-picture.md`)
- [ ] Critic score ≥ 85 or the job is draft
