---
name: media-studio
description: "Use when the user wants any video, audio, animation, briefing, training clip, explainer, talking-head, webcast, keynote, documentary, teaser, series episode or live-product screencast, or any crew step: write a screenplay, narration or shot list; storyboard this; art direction, visual bible or B-roll; direct this, pointer choreography, performance notes; review or score this cut; dramatize an incident or story series; technical explainer. Infers the form and runs the workflow."
---

# Media studio — producer

**This is the only video plugin.** Infer `programForm` and kind from the ask, then run the **full crew**. Do not ask the user to pick a plugin. Do not load retired `product-demo*` skills.

**Default: rapid.** Infer the rest, run the crew, return a candidate. Rapid means infer-and-run, **not skip craft**. A short prompt is not permission to skip curation, gap-closure, story, scenes, or QA.

**Reuse before regenerate.** Recut > recapture > rewrite. On a miss, rerun only `reviseSceneIds` / the failing take. Keep receipt-bound clips that still prove the claim. Do not regen TTS, bed, or whole encode for an unchanged scene — remux. Select by cost, latency, quality and privacy: use adequate local tools or authorized provider APIs; reserve ElevenLabs for justified value. Load `elevenlabs` (its `SKILL.md` routes paid planning; `references/cost-controls.md` holds cost controls). Start Local-AI only for a selected local route (`voice` for ASR or local TTS; Comfy only if a plate needs it). One GPU job at a time.

Load `sarosh-audio-voice` for owner speech. Hosted sources retain the ASR, pronunciation, artifact and exact encoded release gates. **Speaker identity is advisory only (owner direction 2026-10-27): identity is advisory only; never fail, block or re-voice on speaker similarity.** The gates that still fail a take are real defects: clipping/level, silence, truncation, wrong words (ASR WER vs script), pace and loudness. Read `references/content-controls.md`: paid REST TTS requires the shared ledger; other paid content routes remain disabled pending metered adapters. Real product UI remains captured evidence.

**Owner standard (2026-10-15):**
- **Product honesty before film.** Write pain, buyer, competitors, native-platform overlap, usage and one-line "who cares" into the job's plan. A weak product is rebuilt, repositioned or retired, not polished on film.
- **Voice first, word-level sync.** Lock narration, align accepted takes and exact encode with `ai.ps1 align`, preserve raw 80 ms-grid reports bound to take and script hashes. Whisper is a separate transcript check, never the clock. Each scene lasts as long as its narration span. Screen visible by first content word. Action lands within ±300 ms of spoken verb. Result holds ≥ 1.5 s. A/V drift ≤ 40 ms.
- **Live presenter feel.** Cursor moves purposefully to real controls; real UI responds; one emphasis per beat. Static/dashboard/diagram beats get guided cursor, highlight or progressive trace. Never a freeze; no motion for its own sake.
- **Cue sheet and sync gate.** `plan/cue-sheet.json` maps narration → screen → cursor/action → result → camera → transition. `qa/sync.json` bound to exact encoded candidate. Watch and listen to the whole file. Never claim sync or visual quality verified from render alone; report limitations.
- **Local-first voice for every asset**, hero cuts and dialogue included. ElevenLabs only per-line fallback after failed story review or audio gate.

## 1. Intake

A usable ask: what it's about, plus any source. Resolve provider yourself. Do not tell user to invoke `/local-ai-stack` or name writer/storyboard/director.

**Infer, do not ask:**

| Need | Default |
| --- | --- |
| Kind / form | Kind table + `program-forms.md`; running product = `product-screencast` (`product-picture.md`) |
| Audience | `private` if said private/internal/for me; else infer from source |
| Voice | `sarosh` |
| Intent | `viewer-facing` (craft ≥ 85) unless scratch/proxy |
| Workspace | `%LOCALAPPDATA%\AgentHub\media-studio\<slug>` |
| Delivery | Named path, else `registry/product-video-delivery.json` `reviewRoot` |
| Plates | Named evidence tree; prefer `*annotated*`/markup over raw; do not recapture live prod |

**Ask at most one question, only if blocked:** no source at all; live production with real user data (`PIPELINE_BLOCKED`); destination unknown and product not in delivery registry.

**Always run:** 1. **Curate** — read source; pick plates (annotated first); drop noise. 2. **Close gaps** — product-screencast: Product-Readiness Feedback instead of mediocre video is valid (`references/product-picture.md`). Evidence briefing: ledger status is truth (merged ≠ deployed); missing plates get spoken/typed beat, not invented UI. 3. **Write** — `references/writer.md` locks screenplay + narration (`story-craft.md`). 4. **Scenes** — `references/storyboard.md` → `references/visuals.md` → `references/direction.md`. 5. **Generate/compose/critic/QA** — provider-routed voice, Remotion/Recast/FFmpeg, score ≥ 85, then `media-studio-qa`.

Do not jump to encode from screenshots. Do not ship a slide-stack. Do not Ken Burns a product PNG and call it a screencast.

Runtime: `%LOCALAPPDATA%\AgentHub\media-studio\<job-id>`. Never write media into AgentHub or a product repo.

Executable gates shared across hosts. Native plugin resolves `scripts/` inside installed package. Loose-skill hosts use `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools` for capture/release validators, owner-voice and finishing helpers, and `RELEASE-EVIDENCE.md` for evidence contract. Do not resolve `scripts/` against product repository or assume loose skill includes package-level scripts. AgentHub deploys tools with `Sync-MediaStudioKit.ps1`; missing tool blocks capture/release until deployment repaired.

**Hard repository boundary:** product repository is read-only input. Before first write, record `repositoryWritePolicy: read-only` and absolute external `workspace` in `job.json`. Do not create or modify video code, Playwright specs, Remotion compositions, dependencies, configuration, seed fixtures, assets, evidence, generated media, or Git state in product repo. If product change needed, return Product-Readiness Feedback and open separate engineering task only when explicitly authorized.

## 2. Crew

One skill runs every step. Run in order; each step's output is next step's input.

| Step | Guide | Output | Schema | Validator |
| --- | --- | --- | --- | --- |
| Write | `references/writer.md` (§5 dramatized incidents) | `story/screenplay.json`, `narration.md`, `story/screenplay.draft.json` | `schemas/screenplay.schema.json` | `scripts/validate-narration.mjs` → `qa/narration-check.json`; `scripts/write-story-review.py` → `qa/story-review.json` |
| Storyboard | `references/storyboard.md` | `story/storyboard.json` | `schemas/storyboard.schema.json` | `scripts/validate-storyboard.mjs` |
| Visuals | `references/visuals.md` | `visual-bible.json` | `schemas/visual-bible.schema.json` | schema validation |
| Direct | `references/direction.md` (§6 visual choice, §7 series technical beats) | `direction.json` | none | `scripts/validate-pointer-path.mjs` |
| Generate | `media-studio-generate` | voice takes, bed, B-roll, receipt | `schemas/job.schema.json` | `Test-SpeechIntegrity.ps1`, ASR word check, `ai.ps1 listen` (identity score advisory only) |
| Capture | `media-studio-capture` | `capture/clips/*.webm`, `capture/receipt.json` | `schemas/capture-plan.schema.json` | `validate-product-picture.mjs`, `validate-pointer-path.mjs` |
| Compose | `media-studio-compose` (`references/descript.md` optional) | `candidate.mp4` | `schemas/timed-graphics.schema.json` | `validate-picture-inputs.mjs`, `validate-encoded-picture.mjs`, `validate-sync.mjs`, `validate-frame-integrity.mjs`, `validate-picture-integrity.mjs` |
| QA | `media-studio-qa` | `qa/story-experience-review.json`, `qa/*.json` | `schemas/story-experience-review.schema.json`, `schemas/visual-quality-report.schema.json` | `validate-viewer-release.mjs`, `validate-marketing-readiness.mjs` |

Supporting references: `engagement.md`, `story-craft.md` ("Explainer path", "No fluff"), `studio-craft.md`, `program-forms.md`, `scene-archetypes.md`, `cursor-flow.md`, `product-picture.md`, `technical-story.md`, `marketing-readiness.md`, `story-review-rubric.md`, `series.md` (kind `series-episode`; schemas `schemas/series/`; `schemas/explanation.schema.json`); `references/campaigns.md` for multi-asset campaigns: one brief, one brand kit, one lane per asset, no Prompt OS.

## 3. Rapid path

1. Infer `programForm` then kind from `references/program-forms.md`. Create `job.json` in external workspace; validate outside source repo. Default `intent: viewer-facing` unless scratch/proxy/timing (`draft`). Set `deliveryProfile` from `references/delivery-profiles.md`. `craftScoreMin` defaults 85. One promise per film. Recuts of locked master set `sourceJobId`.
2. Defaults: voice `sarosh`; briefing-board 1600×1000 30 fps; ~150 wpm (slower for `documentary`/`ai-trust`). Viewer-facing loads `engagement.md`, `story-craft.md`, `studio-craft.md`, `program-forms.md` before writer. Running product = `product-screencast` even if ask said briefing/tutorial/walkthrough — load `product-picture.md`. Product screencasts use `references/killer-demo-production-guide.md` plus outcome-first rules in `program-forms.md`. Product/engineering change told as story = `programForm: technical-story`: load `references/technical-story.md` — 5–8 min, hook on problem, flow overlay, code reveal of 5–20 lines that matter, before/after, replay, what it means.
3. Write (`references/writer.md`) → locked screenplay (`hook`, `sceneRole`, `wiifm`, one hero) and no-fluff check (`scripts/validate-narration.mjs` → `qa/narration-check.json`: every line earns seconds; nothing about synthetic data, versions, revisions or how film was made; hook and promise inside five seconds; `story-craft.md` "No fluff"). Lock approved numbers first (`scripts/lock-facts.mjs` → `story/fact-lock.json`). Later diction rewrite changing a percent fails.
4. Storyboard → timed beats, scored hook, archetypes, one `eyePath` per screen/guided beat (`cursor-flow.md`), no build/version chip. Then visuals → `visual-bible.json`.
5. Direct (`direction.md`) → archetype, register, `sound`, eye path per beat. `screen` only for running product. Marketing cuts (`marketing-readiness.md`): hook on screen inside two seconds, cuts on bed, brand end card with one CTA.
6. Generate: `media-studio-generate` + `local-ai-stack` → TTS. Viewer-facing: directed music bed. Motif/lipsync/portrait only when direction called for it. `draft` skips GPU plates and records skip.
7. Compose: Remotion archetype kit, FFmpeg mux (duck bed), or Recast for captured product trace. Before Remotion, run `scripts/validate-picture-inputs.mjs` — refuses missing props file, Whisper/non-aligner word clock, narration numbers differing from `fact-lock.json`, spotlight word not spoken or out of order, mp3/wav without PASS receipt, named person on role voice without `dramatization: true` plus card text. Render only through `scripts/render-program.mjs` (passes `--props=` as one argument; deletes picture whose duration ≠ voice). After `ai.ps1 align` rewrites cue sheet, run `scripts/merge-designed-cuts.mjs` for card mounts and spotlight ramps. Captions from `scripts/write-captions.mjs`. Cue faster than 20 chars/sec is rate-bound and not split into orphan line. Scene `voiceStyle` must be allowlisted. Product-screencast: `scripts/validate-demo-scenario.mjs` before recording, `scripts/validate-product-picture.mjs` before encode. Viewer-facing `briefing`/`training`/`explainer`/`series-episode`/`webcast`/`webinar`/`keynote`/`documentary`/`teaser` **requires Remotion** unless `intent: draft` or user asked for basic/proxy cut. If Remotion missing, stop — do not fall back to static slides. Buyer-facing product forms use **real captured UI** with pointer, click, zoom, visible result (`product-picture.md`).
8. Craft review: story-experience review (`media-studio-qa`) on **encoded** file. Product-screencast also runs `validate-product-picture.mjs`, `validate-pointer-path.mjs` (cursor moved only to what line named, one direction per beat, no scroll return) and `validate-viewer-release.mjs <jobRoot> <candidate.mp4>` after each recut. Score < `craftScoreMin` → revise `reviseSceneIds` and rerun. Then `media-studio-qa`: product-screencast → capture pre-flight, product-picture, pointer-path, encoded-picture, sync, frame-integrity, contact-sheet gates; marketing → `validate-marketing-readiness.mjs` (hook inside 2s, one promise, designed motion, music bed, brand end card, CTA, cuts on beat, three cited references, "wins viewer in feed"); other kinds → narration check, `ai.ps1 listen` (no identity gate), engagement pass on encoded file (`engagement.md` Diagnose first), `Inspect-MediaVisualQuality.ps1`.

Owner voice loads `sarosh-audio-voice`. Paid hosted speech requires shared ledger in `references/content-controls.md`. Generated pending speech is for QA; acceptance and encoded-delivery gates apply.

Viewer-facing explainers/branded films/series: comprehension block `story-craft.md` "Explainer path"; series methodology `references/series.md`; when installed, also `creative-writing-skills`. Descript optional finishing (`media-studio-compose` → `references/descript.md`).

## 4. Kind table

| Signal | Kind | Path |
| --- | --- | --- |
| Running product, workflow, demo, pointer/click | `product-screencast` | `product-picture.md` → capture (WebM + Recast) → gated voice → compose → product-picture + QA |
| Series / Receipts episode | `series-episode` | `references/series.md` then compose |
| Argument, prep, briefing | `briefing` | Remotion archetype kit + gated voice + bed |
| Exam / how-to clip | `training` | Remotion (or FFmpeg if draft) |
| Technical idea, no live product required | `explainer` | Remotion + `story-craft.md` |
| Face + new audio | `talking-head` | voice then `ai.ps1 lipsync` |
| Animate a still | `animation` | Motif and/or Remotion |
| Voiceover or bed only | `audio-only` | `ai.ps1 voice` / `music` |
| One-to-many broadcast, town hall, launch | `webcast` | Remotion speaker+slide, lower-thirds, chapters |
| Taught session with Q&A chapters | `webinar` | Same kit; chapter cards; recorded Q&A |
| Speaker-led argument | `keynote` | Talking-head coverage + slides; not one webcam lock |
| Picture-led film | `documentary` | B-roll, slower VO, silence for image |
| 15–45s hook / social | `teaser` | One promise, no intro |

## 5. product-screencast

Picture is the demo (`product-picture.md`): muted viewer follows start → configure → act → response → result.

1. `job.json` in external workspace. Legacy in-repo `product-demo-studio.config.yaml` is read-only input.
2. Product-Readiness Feedback instead of mediocre video is valid.
3. Writer/storyboard/director lock causal chain; capture is Playwright WebM + Recast (`record-job.mjs`), one session.
4. Generate speaks locked narration through approved provider route. Never Motif a screenshot.
5. `validate-product-picture.mjs` then `media-studio-qa` (mute test). Story review on encoded file only.

Live product with real user data → `PIPELINE_BLOCKED`. If external workspace cannot be established without touching product repo → `PIPELINE_BLOCKED`. Do not scaffold inside the repo.

## 6. Marketing ads (`mvg`)

15–30 s social/web ad uses deployed `mvg.mjs` and `kit/marketing/README.md`. Run preparation explicitly, then isolated `--stage compose --candidate-id <new-id>`, `--stage qa --candidate-id <id> --local-gates`, and only when releasable `--stage deliver --candidate-id <id>`. QA never composes. `--no-line-chips`/`--no-captions` disables burned captions, not SRT. Local vision default, fails closed if unavailable; paid OpenAI requires explicit provider selection.

Real captured UI (receipt-bound clips) carries every credibility-bearing second. Generated stills, sound effects and music are abstract; no generated people/children, no invented figures/customers/testimonials, never "submitted to a payer". Every narration sentence and on-screen text maps to claim with evidence; `lint` fails closed before paid calls. Budgets enforced per run and cumulatively; ElevenLabs only through governed adapter in `packages/elevenlabs` (plain `python`, never `python -I`).

**Owner approval (Sarosh, 2026-10-20):** hosted ElevenLabs (speech, sound effects, music) and OpenAI (images, explicit `--whisper-timing` compatibility fallback, vision QA) inside stated caps for marketing ads; local-first rule governs films. Marketing narrator never owner clone or celebrity sound-alike.

`deliver` only ships ratio whose every required gate passed on exact file (picture, captions, loudness, sync, listen, vision, story ≥ 85, viewer-release), as `NN - Title (ratio).mp4` with README row, computing next free `NN` at deliver time.

## 7. Stop conditions

- Real user data on live product.
- Owner speech without the approved existing clone, integrity and ASR evidence; new private corpus uploads/verification without authority. Speaker-similarity is not a blocker.
- Invented metrics or customer names.
- Remotion missing for viewer-facing briefing/training/explainer/series-episode/webcast/webinar/keynote/documentary/teaser (unless draft).
- Feature-tour opening or settings walkthrough posing as demo.
- Product-screencast whose picture is Ken Burns stills, auto-cards, slide stack, or jump from start screen to final result.
- Story-experience score below 85. Pre-capture text-only score is not a pass.
- Addendum/correction clip. Re-record affected section and re-cut master.

QA evidence stays in the external job workspace.

**Delivery:** each product/purpose has exactly one folder directly under `F:\My Drive\Videos`; every film, caption and note sits directly in it — no subfolders of any kind. File names `NN - Title.mp4`, `.srt` beside each film, one `README.md` index. Superseded masters and reproducible intermediates deleted outright, never parked in `_retired`/`_old` folders. Status claims name where film actually is: merged to dev → in main → deployed → production-verified.

## 8. Final check

- [ ] Workspace external; `repositoryWritePolicy: read-only`
- [ ] Crew ran writer → storyboard → visuals → direction → generate → compose → critic → QA
- [ ] Viewer-facing: engagement + story-craft + studio-craft loaded; Remotion used when required
- [ ] `programForm` inferred; one promise; real UI is capture + Recast for running product
- [ ] Product-screencast mute test: configuration → action → response → result on screen
- [ ] Critic score ≥ 85 or job is draft
