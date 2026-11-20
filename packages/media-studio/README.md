# media-studio

The **only public** video/audio/animation plugin. Infer form from the ask
(product demo, briefing, explainer, talking-head, and the rest) and run that
workflow. Live-product screencasts are this pack (Playwright WebM + Recast), not a second plugin.

**Rapid default:** a sentence or a source path is enough. Infer kind and delivery. Still run curation, gap-closure, writer, storyboard, visuals, director, Azure-first generate, Remotion/FFmpeg/Recast, craft critic, QA. Rapid means infer-and-run, not skip craft. Ask the user only when blocked.

Live-product screencasts use Playwright WebM + Recast in this pack (`kit/screencast/record-job.mjs`, `scripts/validate-product-picture.mjs`).

**Viewer-facing** jobs apply `skills/studio/references/story.md`. The screenplay carries story role, WIIFM, and tension; the storyboard carries shot plan, archetype, sound and one eye path per screen beat. Score < 85 from the story-experience review (`review`) does not ship. `intent: draft` skips generated plates and the critic gate. Product-screencast craft uses the product-picture contract. Before capture, `scripts/validate-narration.mjs` applies five-second hook/no-fluff/repetition constraints to **verified demos** but respects other declared creative modes (fiction, future-vision, documentary, abstract, education and hybrid). `scripts/write-story-review.py` similarly uses form-aware pre-capture judgments for non-verified films instead of enforcing an artificial six-beat product plot. For verified product demos, `scripts/validate-demo-scenario.mjs` requires a source-hashed scenario with persona, problem, visible product outcome and CTA; `record-job.mjs` runs `scripts/validate-capture-preflight.mjs` (scene ids, cue keywords, typing budgets) before the first take. After recording, `scripts/validate-pointer-path.mjs` fails any take whose cursor reversed, wandered, over-travelled or scrolled past and returned. Every ratio is captured at its own viewport with device emulation (`job.captureViewports`, `record-job.mjs --ratio`), never cropped out of a desktop take; `scripts/validate-picture-integrity.mjs` fails stretched, upscaled, cropped, barred or undeclared-zoom product footage and a vertical cut recorded at a desktop viewport. After every recut, `scripts/validate-viewer-release.mjs` requires exact-candidate captions, loudness, authored-script pronunciation, visual/title/action-result reviews, the narration check, frame integrity (`scripts/validate-frame-integrity.mjs`), picture integrity, the pointer-path report, the marketing floor on marketing cuts (`scripts/validate-marketing-readiness.mjs`, `references/marketing-readiness.md`) and a stitchable sequence before release. `scripts/build-contact-sheet.mjs` tiles the cue-sheet stills for the human watch-through.

**Technical stories** (`programForm: technical-story`) are product or engineering changes told as 5–8 minute mini documentaries: `skills/studio/references/story.md` holds the beat map and markup rules; `kit/screencast/` holds the compositor, annotation overlay, code-reveal and card renderers with their manifest hints. Product-specific capture notes live under `skills/capture/references/`.

**Product picture** (`skills/studio/references/product-picture.md`): when the subject is a running product, the encoded film is Playwright WebM + Recast (pointer, click, zoom, visible result), not Ken Burns stills mixed with Remotion cards. `scripts/validate-product-picture.mjs` fails closed. Host projections must match `plugin.json`.

Version authority: root `plugin.json` (`3.1.10`). Host projections must match.
Runtime media stays outside AgentHub (`%LOCALAPPDATA%\AgentHub\media-studio` and `MEDIA_STUDIO_ROOT`, default `D:\Media-Studio`). Private show bibles and customer recordings stay outside this repository.

Canonical Remotion kit: `kit/` (scene-archetype library, plus `kit/screencast/` compositor tooling). Runtime copy: `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`. Sync with `scripts/Sync-MediaStudioKit.ps1`.

**Creative forms, not a single product template:** Read
`skills/studio/references/creative-formats.md`. Media Studio supports
verified current-product demos, hybrid films, fictional day-in-the-life
stories, entirely synthetic human scenes, patients/children/families,
documentary, education, abstract visuals and envisioned future interfaces.
The marketing ad `creativeMode` selects these contexts; only the
`verified-demo` form requires the strict source-proven UI flow and
prescribed story beats. Other modes can build their own narrative or
nonlinear structure, with no synthetic-human age ban, default blur,
mandatory text suppression, or arbitrary product-screen percentage.
`truthStatus: verified|proposed|fictional|illustrative` separates factual
current-capability proof from imaginative future scenes. A film-level
concept declaration prevents a proposed feature being mistaken for
a shipping feature without permanent watermarks or obscured artwork.
Marketing-specific lint is not a replacement for the general film
crew's creative development and encoded review.

**Flexible storytelling schemas and preflight:** In addition to the
existing verified-product storyboard, `schemas/creative-storyboard.schema.json`
accepts free-form scene roles, generated images/video/3D, fictional
people, children/patients, full speculative UI, intentional silence,
non-linear order and form-specific transitions. `job.creativeMode`
is available to the wider studio workflow. The general screenplay
review requires independently evidenced judgments of audience,
form-fit, visual-story and representation without forcing a
current-product UI or a hero after scene three. The encoded viewer
review remains mandatory before delivery.

**Media-provider cost/quality selection:** For each missing story asset,
read `skills/produce/references/provider-cost-quality-routing.md`. Reuse actual
product capture, designed diagrams and accepted assets before proposing new
generation. `scripts/route_media.py --catalog` lists available/frozen local
lanes; `scripts/quote-runware-models.mjs` compares **live Runware model
prices** from public official schemas, without spending. AssemblyAI is
an audio/transcript analysis route, Runware offers supplemental multimodal
generation, and ElevenLabs is a conditional high-quality speech/music/SFX
candidate. Listing a model does **not** enable a frozen lane or authorize spend.
Quality/capability, rights and the exact-candidate film review outrank a cheaper quote. Generated UI is welcome in fiction/concepts/vision; only current-product factual demonstrations demand actual captured proof.

**Marketing ads** (5-120 s social and web ads in 16:9, 4:5 and 9:16): `kit/marketing/` is the generator (`mvg.mjs`). A spec of beats, claims with evidence, a voice, an optional music bed and a CTA goes through lint, voice, timing, assets, capture reuse, the `MarketingAd` Remotion composition, QA (including OpenAI vision review of sampled frames) and delivery; spend is capped per run and cumulatively, and every claim must map to evidence. See `kit/marketing/README.md`.

Pre-capture screenplay lint: `scripts/validate-narration.mjs <jobRoot>` then `scripts/write-story-review.py <jobRoot>` (the sync script copies them to `_shared\tools`; the story review fails `no-fluff` without the narration check). It is not a craft pass and does not authorize compose or delivery. Product-screencast still requires `validate-product-picture.mjs`, `validate-demo-scenario.mjs`, `validate-viewer-release.mjs`, and encoded-file review (`product-picture.md`, `RELEASE-EVIDENCE.md`).

Vocabulary reuse alone can misclassify a truth-status qualification. A job may declare `narrationScopeQualifications: [{sceneId, line, reason, evidence: {path, sha256}}]` for an exact sentence explicitly marking proposals as subject to client validation. The in-job JSON evidence must carry `kind: "truthful-scope-qualification"`, `verdict: "PASS"`, `assertion: "proposed-not-client-confirmed"`, the exact `sceneId` and `line`, and a substantive `reason`. This adjudicates only the cumulative vocabulary heuristic; banned language, single-line redundancy and repeated sentences still fail. The report exposes each adjudication and hashes its evidence; release rejects changed evidence or declarations. It does not establish client confirmation or owner approval.

## Product-repository boundary

Product repositories are read-only inputs. Media Studio never adds or changes
video code, Playwright specs, Remotion apps, dependencies, configuration, seed
fixtures, assets, evidence, media, or Git state there. The job config and all
production source live in the external job workspace. Product defects become
readiness feedback and require a separate engineering task.

## Why this exists

Product Demo Studio is a specialized, fail-closed **product screencast** pipeline (Playwright capture, Recast pointer/click, four-domain review). Agents were routing briefings, training films, explainers, talking-heads, and motion-slide pieces through it because it was the only video pack.

This package is the parent studio. Product Demo Studio remains the product-screencast workflow inside it.

## Crew (skills, not a second control plane)

| Skill | Owns | Key references |
| --- | --- | --- |
| `studio` | Single entry point. Asks up to five quick questions (purpose, kind, length and destination, voice, picture), picks the approach, then runs write, produce and finish with state and approvals (`studio_init.py`, `production_status.py`) | `conductor.md`, `video.md`, `forms.md`, `creative-formats.md`, `story.md`, `scenes.md` |
| `script` | Brief, story and locked script, storyboard with a picture for every line; gates before spend | `brief.md`, `develop.md`, `plan.md` |
| `produce` | Screen takes through `ah-browser` (agent-browser `--cursor` or BrowserSkill), governed voice, stills, diagrams, Lottie and music under spend controls | `capture.md`, `generate.md`, `visuals.md`, `voice-recipes.md` |
| `finish` | Compose and render with the official Remotion plugin on sh-forge, loudness, delivery, then a fresh reviewer's score and ship decision | `compose.md`, `render-lanes.md`, `review.md`, `gates.md` |

`studio` is the only front door; `script`, `produce` and `finish` also run alone for one stage of an existing job. `scripts/route_media.py` picks the funded lane for a need from `policy/provider-routing.json` (credits recorded in Linear, frozen lanes stay frozen). `scripts/check_visual_variety.py` fails a film that is words in boxes. The series and explanation schemas live in `schemas/series/` and `schemas/explanation.schema.json`.
Viewer-facing `briefing`, `training`, `explainer`, and `series-episode` require Remotion unless the user asked for a draft/basic cut. Do not vendor Remotion rules — resolve `video.programmatic-composition` to official `remotion-dev/skills`.

## Non-goals

- Do not convert Product Demo Studio into a general filmmaking engine.
- Do not centralize credentials, customer data, or private evidence here.
- Do not start local models, TTS/STT servers or embedders: Local AI is off. Hosted providers only, through the governed adapters. Never use Windows Narrator, SAPI, System.Speech or any other desktop voice.

Governed Deepgram Flux batch TTS uses `scripts/deepgram_cli.py`. Select `--voice flux-haley-en` for prepared support prompts. Existing calls default to Sienna. The CLI quotes by default. Execution requires intact shared accounting or a reviewed owner-authorized bounded epoch. See `skills/produce/references/content-controls.md`.

Cloud render: kit/cloud/cloud-render.mjs runs FFmpeg, Remotion and Recast jobs on a scale-to-zero Azure Container Apps job in the owner's own Azure tenant (upload -> render -> download). Provision with kit/cloud/Provision-CloudRender.ps1; see kit/cloud/README.md. Offline tests: node --test tests/cloud-render.test.mjs.

Runware training stills: `kit/cloud/cloud-ai.mjs illustration` provides an explicitly selected,
synthetic-only, single-model job with resumable polling, a $1 per-job spend bound, private
hash-bound output, a content-hashed output inventory (`jobs/runware/<id>/inventory.json`) and
human review.
See `kit/cloud/README.md` for the job and retention contract. It does not publish an asset,
authorize customer data or establish provider entitlement. Offline tests:
`node --test tests/runware-image.test.mjs`.
