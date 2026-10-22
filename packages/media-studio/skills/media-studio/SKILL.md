---
name: media-studio
description: "Use when the user wants any video, audio, animation, briefing, training clip, explainer, talking-head, webcast, keynote, documentary, teaser, series episode or live-product screencast, or any crew step: write a screenplay, narration or shot list; storyboard this; art direction, visual bible or B-roll; direct this, pointer choreography, performance notes; review or score this cut; dramatize an incident or story series; technical explainer. Infers the form and runs the workflow."
---

# Media studio — producer

**This is the only video plugin.** The user does not name skills, kinds, or pipeline steps. Infer `programForm` and kind from the ask — product demo, briefing, explainer, talking-head, webcast, teaser, or anything else in the kind table — then run the **full crew**. Do not ask them to pick a plugin. Do not load retired `product-demo*` skills.

**Default: rapid.** A sentence, path, or “make a video from this” is enough. Infer the rest, run the crew, return a candidate. Rapid means infer-and-run, **not skip craft**. A short prompt is not permission to skip curation, gap-closure, story, scenes, or QA.

**Reuse before regenerate.** Recut > recapture > rewrite. On a miss, rerun only `reviseSceneIds` / the failing take. Keep receipt-bound clips that still prove the claim. Do not regen TTS, the bed, or the whole encode for an unchanged scene — remux. Select by cost, latency, quality and privacy: use adequate local tools or authorized provider APIs; reserve ElevenLabs for justified value. Load `elevenlabs` (its `SKILL.md` routes paid planning; `references/cost-controls.md` holds the cost controls) for paid planning and cost controls. Start Local-AI only for a selected local route (`voice` for identity/ASR or local TTS; Comfy only if a plate needs it). One GPU job at a time.

Load `sarosh-audio-voice` for owner speech. Hosted sources retain all identity,
ASR, pronunciation and exact encoded release gates. Read `references/content-controls.md`:
paid REST TTS requires the shared ledger; other paid content routes remain disabled
pending metered adapters. Real product UI remains captured evidence.

**Owner standard (2026-10-15), adding to everything above:**
- **Product honesty before film.** Write the pain, buyer, competitors and native-platform overlap, usage and a one-line "who cares" into the job's plan. A weak product is rebuilt, repositioned or retired, not polished on film.
- **Voice first, word-level sync.** Lock narration, align accepted takes and the exact encode with deployed `ai.ps1 align`, and preserve raw 80 ms-grid reports bound to the take and script hashes. Whisper is a separate transcript check, never the clock. Each scene lasts as long as its narration span.
  - The screen is visible by the line's first content word.
  - The action lands within ±300 ms of the spoken verb.
  - The result holds for at least 1.5 s.
  - A/V drift is at most 40 ms.
- **Live presenter feel.** The cursor moves purposefully to real controls and the real UI responds, with one emphasis per beat. Static, dashboard and diagram beats get a guided cursor, highlight or progressive trace on the element being named. Never a freeze, and no motion for its own sake.
- **Cue sheet and sync gate.** `plan/cue-sheet.json` maps narration → screen → cursor/action → result → camera → transition. `qa/sync.json` is bound to the exact encoded candidate. Then watch and listen to the whole file. Never claim sync or visual quality is verified from a render alone; report limitations.
- **Local-first voice for every asset**, hero cuts and dialogue included. ElevenLabs is only a per-line fallback after a failed story review or audio gate.

## 0. Intake (do not dump this on the user)

A usable ask is: what it is about, plus any source (evidence folder, outline, product). Resolve the selected provider yourself. Do not tell the user to invoke `/local-ai-stack` or name writer/storyboard/director.

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
3. **Write** — `references/writer.md` locks screenplay + narration (`story-craft.md`).
4. **Scenes** — `references/storyboard.md` then `references/visuals.md` then `references/direction.md`.
5. **Generate / compose / critic / QA** — provider-routed voice, Remotion/Recast/FFmpeg, score ≥ 85 (the story-experience review in `media-studio-qa`), then `media-studio-qa`.

Do not jump to encode from screenshots. Do not ship a slide-stack of the ledger. Do not Ken Burns a product PNG and call it a screencast.

Runtime: `%LOCALAPPDATA%\AgentHub\media-studio\<job-id>`. Never write media into AgentHub or a product repo.

Executable gates are shared across hosts. A native plugin may resolve `scripts/`
inside its installed package. Loose-skill hosts (including Cursor and Grok) use
`%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools` for capture and release
validators, owner-voice and finishing helpers, and `RELEASE-EVIDENCE.md` for
their evidence contract. Do not
resolve `scripts/` against the product repository or assume a loose skill includes
package-level scripts. AgentHub deploys these tools with `Sync-MediaStudioKit.ps1`;
a missing tool blocks capture/release until that deployment is repaired.

**Hard repository boundary:** a product repository is read-only input. Before
the first write, record `repositoryWritePolicy: read-only` and the absolute
external `workspace` in `job.json`. Do not create or modify video code,
Playwright specs, Remotion compositions, dependencies, configuration, seed
fixtures, assets, evidence, generated media, or Git state in the product repo.
If a product change is needed, return Product-Readiness Feedback and open a
separate engineering task only when explicitly authorized.

## Crew (one skill, five references)

One skill runs every step. The step guides are references in this skill; the executable steps keep their own skills. Run the steps in order; each step's output is the next step's required input.

| Step | Guide | Output | Schema | Validator |
| --- | --- | --- | --- | --- |
| Write | `references/writer.md` (also dramatized incidents, §5) | `story/screenplay.json`, `narration.md`, `story/screenplay.draft.json` | `schemas/screenplay.schema.json` | `scripts/validate-narration.mjs` → `qa/narration-check.json`; `scripts/write-story-review.py` → `qa/story-review.json` (pre-capture lint) |
| Storyboard | `references/storyboard.md` | `story/storyboard.json` | `schemas/storyboard.schema.json` | `scripts/validate-storyboard.mjs` |
| Visuals | `references/visuals.md` | `visual-bible.json` | `schemas/visual-bible.schema.json` | schema validation |
| Direct | `references/direction.md` (visual choice §6, series technical beats §7) | `direction.json` | none (keyed by beat id) | `scripts/validate-pointer-path.mjs` measures the plan against the take |
| Generate | `media-studio-generate` | voice takes, bed, B-roll, generation receipt | `schemas/job.schema.json` | identity score, `ai.ps1 listen`, `Test-SpeechIntegrity.ps1` |
| Capture | `media-studio-capture` | `capture/clips/*.webm`, `capture/receipt.json` | `schemas/capture-plan.schema.json` | `validate-product-picture.mjs`, `validate-pointer-path.mjs` |
| Compose | `media-studio-compose` (Descript finishing: `references/descript.md` there) | `candidate.mp4` | `schemas/timed-graphics.schema.json` | `validate-encoded-picture.mjs`, `validate-sync.mjs`, `validate-frame-integrity.mjs`, `validate-picture-integrity.mjs` |
| QA + story-experience review | `media-studio-qa` | `qa/story-experience-review.json`, `qa/*.json` | `schemas/story-experience-review.schema.json`, `schemas/visual-quality-report.schema.json` | `validate-viewer-release.mjs`, `validate-marketing-readiness.mjs` |

Supporting references: `engagement.md`, `story-craft.md` (including the "Explainer path" and "No fluff"), `studio-craft.md`, `program-forms.md`, `scene-archetypes.md`, `cursor-flow.md`, `product-picture.md`, `technical-story.md`, `marketing-readiness.md`, `story-review-rubric.md`, `series.md` (kind `series-episode`; schemas in `schemas/series/`; explanation block schema `schemas/explanation.schema.json`); `references/campaigns.md` for a multi-asset campaign (launch, social pack, sales kit, event kit, brand variants, customer story): one brief, one brand kit, one lane per asset, no Prompt OS.

## 1. Rapid path

1. Infer **`programForm`** then **kind** from `references/program-forms.md`. Create `job.json` in the external workspace and validate that the workspace is outside any source repository. Default `intent: viewer-facing` unless the user asked for a scratch, proxy, or timing pass (`draft`). Set `deliveryProfile` from `references/delivery-profiles.md`. `craftScoreMin` defaults to 85. One promise per film. Recuts of a locked master set `sourceJobId`.
2. Defaults: owner/internal voice `sarosh`; briefing-board 1600×1000 30 fps; duration ~150 wpm (slower for `documentary` / `ai-trust`). Viewer-facing jobs load `references/engagement.md`, `story-craft.md`, `studio-craft.md`, and `program-forms.md` before the writer. If a running product is the subject, `kind` is `product-screencast` even when the ask said briefing, tutorial, or walkthrough — load `references/product-picture.md`. Product screencasts use `references/killer-demo-production-guide.md` plus outcome-first rules in `program-forms.md`. A product or engineering **change** told as a story (a fix, an incident, a new capability) is `programForm: technical-story`: load `references/technical-story.md` — 5–8 minutes, hook on the problem, flow overlay, code reveal of the 5–20 lines that matter, before/after, replay, what it means.
3. Write (`references/writer.md`) → locked screenplay (`hook`, `sceneRole`, `wiifm`, one hero) and the no-fluff check (`scripts/validate-narration.mjs` → `qa/narration-check.json`: every line earns its seconds; nothing spoken about synthetic data, versions, revisions or how the film was made; hook and promise inside five seconds; `story-craft.md` → "No fluff").
4. Storyboard (`references/storyboard.md`) → timed beats, scored hook (pick internally), archetypes, one `eyePath` per screen or guided beat (`references/cursor-flow.md`), no build or version chip. Then visuals (`references/visuals.md`) → `visual-bible.json`.
5. Direct (`references/direction.md`) → archetype, register, `sound`, the eye path per beat (start, the one move, rest). `screen` only for a running product. Marketing cuts (`references/marketing-readiness.md`) are directed to win a feed: hook on screen inside two seconds, cuts on the bed, brand end card with one CTA.
6. `media-studio-generate` + `local-ai-stack` → TTS. Viewer-facing: also the directed music bed. Motif/lipsync/portrait only when direction called for that plate. `draft` skips those GPU plates and records the skip.
7. Compose: Remotion archetype kit, FFmpeg mux (duck the bed), or Recast for a captured product trace (`media-studio-capture`). Product-screencast: run `scripts/validate-demo-scenario.mjs` before recording and `scripts/validate-product-picture.mjs` before encode. Viewer-facing `briefing` / `training` / `explainer` / `series-episode` / `webcast` / `webinar` / `keynote` / `documentary` / `teaser` **requires Remotion** unless `intent: draft` or the user asked for a basic/proxy cut. If Remotion skills are missing, stop and say so — do not silently fall back to static slides. Buyer-facing product forms use **real captured UI** with pointer, click, zoom, and visible result (`product-picture.md`), not an avatar over fake chrome and not Ken Burns on a screenshot.
8. Craft review is the story-experience review (`media-studio-qa` → "Story-experience review") on the **encoded** file. Product-screencast also runs `scripts/validate-product-picture.mjs`, `scripts/validate-pointer-path.mjs` (the cursor moved only to what the line named, one direction per beat, no scroll return) and `scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>` after each recut. Score < `craftScoreMin` → revise `reviseSceneIds` and rerun. Then `media-studio-qa`: product-screencast → capture pre-flight, product-picture, pointer-path, encoded-picture, sync, frame-integrity and contact-sheet gates; marketing cuts → the marketing floor (`scripts/validate-marketing-readiness.mjs`: hook inside two seconds, one promise, designed motion, music bed, brand end card and CTA, cuts on the beat, three cited references, "wins the viewer in a feed next to them"); other kinds → the same narration check, identity score, full-program `ai.ps1 listen`, the engagement pass on the encoded file (`engagement.md` Diagnose first), and `Inspect-MediaVisualQuality.ps1`.

Owner voice loads `sarosh-audio-voice`. Local voice remains eligible; paid hosted
speech requires the shared ledger in `references/content-controls.md`. Generated
pending speech is for QA; acceptance and encoded-delivery gates still apply.

Viewer-facing explainers, branded films, and series: the comprehension block is `references/story-craft.md` → "Explainer path" and series methodology is `references/series.md`; when installed, also third-party `creative-writing-skills`. Descript stays optional finishing (`media-studio-compose` → `references/descript.md`).

## 2. Kind

| Signal | Kind | Path |
| --- | --- | --- |
| Running product, workflow, demo, tutorial-in-the-app, pointer/click | `product-screencast` | `product-picture.md` → capture (WebM + Recast) → gated voice → compose → product-picture + QA |
| Series / Receipts episode | `series-episode` | `references/series.md` (truth tags, continuity, assembly) then compose here |
| Argument, prep, briefing | `briefing` | Remotion archetype kit + gated voice + bed |
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

The picture is the demo (`product-picture.md`): muted viewer follows start → configure → act → response → result.

1. `job.json` in the external workspace. A legacy in-repo `product-demo-studio.config.yaml` is read-only input.
2. Product-Readiness Feedback instead of a mediocre video is valid.
3. Writer / storyboard / director lock the causal chain; capture is Playwright WebM + Recast (`record-job.mjs`), one session.
4. Generate speaks the locked narration through the approved provider route. Never Motif a screenshot.
5. `validate-product-picture.mjs` then `media-studio-qa` (mute test). Story review on the encoded file only.

Live product with real user data → `PIPELINE_BLOCKED`.

If the external workspace cannot be established without touching the product
repository, return `PIPELINE_BLOCKED`. Do not fall back to scaffolding inside
the repo.

## 3b. Marketing ads (`mvg`)

A 15-30 s social or web ad uses the deployed `mvg.mjs` and `kit/marketing/README.md`. Run preparation explicitly, then isolated `--stage compose --candidate-id <new-id>`, `--stage qa --candidate-id <id> --local-gates`, and only when releasable `--stage deliver --candidate-id <id>`. QA never composes. `--no-line-chips` / `--no-captions` disables burned captions, not the SRT. Local vision is default and fails closed if unavailable; paid OpenAI requires explicit provider selection.

- Real captured UI (receipt-bound clips from the product's film workspaces) carries every credibility-bearing second. Generated stills, sound effects and music are abstract and assert nothing; no generated people or children, no invented figures, customers or testimonials, never "submitted to a payer".
- Every narration sentence and on-screen text maps to a claim with evidence; `lint` fails closed before any paid call. Budgets are enforced per run and cumulatively; ElevenLabs goes only through the governed adapter in `packages/elevenlabs` (plain `python`, never `python -I`).
- Owner approval (Sarosh, 2026-10-20) covers hosted ElevenLabs (speech, sound effects, music) and OpenAI (images, word timing, vision QA) inside the stated caps for marketing ads; the local-first rule above still governs films. The marketing narrator is never the owner clone or a celebrity sound-alike.
- `deliver` only ships a ratio whose every required gate passed on the exact file (picture, captions, loudness, sync, listen, vision, story >= 85, viewer-release), as `NN - Title (ratio).mp4` with the README row, computing the next free `NN` at deliver time.

## 4. Stop

- Real user data on a live product.
- Owner speech without an approved existing clone and passing identity evidence; new private corpus uploads or verification without authority.
- Invented metrics or customer names.
- Remotion missing for viewer-facing briefing/training/explainer/series-episode/webcast/webinar/keynote/documentary/teaser (unless draft).
- Feature-tour opening or a settings walkthrough posing as a demo.
- Product-screencast whose picture is Ken Burns stills, auto-cards, a slide stack, or a jump from start screen to final result (`product-picture.md`).
- Story-experience score below 85. A pre-capture text-only score is not a pass.
- An addendum or correction clip. Re-record the affected section and re-cut the master.

Delivery: each product or purpose has exactly one folder directly under `F:\My Drive\Videos`, and every film, caption and note sits directly in it: no subfolders of any kind (no `Training`, `Notes`, `Evidence`, `Prospects` or archive folders; QA evidence stays in the media-studio workspace). File names are `NN - Title.mp4` with no product prefix, the `.srt` beside each film; the folder has one `README.md` index; superseded masters and reproducible intermediates are deleted outright, never parked in `_retired` / `_old` folders. Status claims name where the film actually is: merged to dev → in main → deployed → production-verified.

## 5. Final check

- [ ] Workspace is external; `repositoryWritePolicy: read-only`
- [ ] Crew ran writer → storyboard → visuals → direction → generate → compose → critic → QA (the Crew table)
- [ ] Viewer-facing: engagement + story-craft + studio-craft loaded; Remotion used when required
- [ ] `programForm` inferred; one promise; real UI is capture + Recast when the form is a running product (`product-picture.md`)
- [ ] Product-screencast mute test: configuration → action → response → result is on screen
- [ ] Critic score ≥ 85 or the job is draft
