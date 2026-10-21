# media-studio

The **only public** video/audio/animation plugin. Infer form from the ask
(product demo, briefing, explainer, talking-head, and the rest) and run that
workflow. Live-product screencasts are this pack (Playwright WebM + Recast), not a second plugin.

**Rapid default:** a sentence or a source path is enough. Infer kind and delivery. Still run curation, gap-closure, writer, storyboard, visuals, director, Local-AI generate, Remotion/FFmpeg/Recast, craft critic, QA. Rapid means infer-and-run, not skip craft. Ask the user only when blocked.

Live-product screencasts use Playwright WebM + Recast in this pack (`kit/screencast/record-job.mjs`, `scripts/validate-product-picture.mjs`). Retired `product-demo*` skills must not be loaded.

**Viewer-facing** jobs apply `skills/media-studio/references/engagement.md` and `story-craft.md`. The screenplay carries story role, WIIFM, and tension; the storyboard carries shot plan, archetype, sound and one eye path per screen beat. Score < 85 from the story-experience review (`media-studio-qa`) does not ship. `intent: draft` skips GPU plates and the critic gate. Product-screencast craft uses `killer-demo-production-guide.md` plus product-picture. Before capture, `scripts/validate-narration.mjs` holds the locked script to the no-fluff rule (every line earns its seconds; no greeting, meta, recap, process, version or synthetic-data talk; hook and promise inside five seconds; synthetic disclosure as a caption or end card; fluff per minute and a words-cut report) and `scripts/validate-demo-scenario.mjs` requires a source-hashed synthetic scenario with one persona, problem, hero, visible outcome, coherent case/target continuity, and a CTA; `record-job.mjs` runs `scripts/validate-capture-preflight.mjs` (scene ids, cue keywords, typing budgets) before the first take. After recording, `scripts/validate-pointer-path.mjs` fails any take whose cursor reversed, wandered, over-travelled or scrolled past and returned. Every ratio is captured at its own viewport with device emulation (`job.captureViewports`, `record-job.mjs --ratio`), never cropped out of a desktop take; `scripts/validate-picture-integrity.mjs` fails stretched, upscaled, cropped, barred or undeclared-zoom product footage and a vertical cut recorded at a desktop viewport. After every recut, `scripts/validate-viewer-release.mjs` requires exact-candidate captions, loudness, authored-script pronunciation, visual/title/action-result reviews, the narration check, frame integrity (`scripts/validate-frame-integrity.mjs`), picture integrity, the pointer-path report, the marketing floor on marketing cuts (`scripts/validate-marketing-readiness.mjs`, `references/marketing-readiness.md`) and a stitchable sequence before release. `scripts/build-contact-sheet.mjs` tiles the cue-sheet stills for the human watch-through.

**Technical stories** (`programForm: technical-story`) are product or engineering changes told as 5–8 minute mini documentaries: `skills/media-studio/references/technical-story.md` holds the beat map and markup rules; `kit/screencast/` holds the compositor, annotation overlay, code-reveal and card renderers with their manifest hints. Product-specific capture notes live under `skills/media-studio-capture/references/`.

**Product picture** (`skills/media-studio/references/product-picture.md`): when the subject is a running product, the encoded film is Playwright WebM + Recast (pointer, click, zoom, visible result), not Ken Burns stills mixed with Remotion cards. `scripts/validate-product-picture.mjs` fails closed. Host projections must match `plugin.json`.

Version authority: root `plugin.json` (`2.0.0`). Host projections must match.
Runtime media stays outside AgentHub (`%LOCALAPPDATA%\AgentHub\media-studio` and `D:\Local-AI\data\artifacts`). Private show bibles and customer recordings stay outside this repository.

Canonical Remotion kit: `kit/` (scene-archetype library, plus `kit/screencast/` compositor tooling). Runtime copy: `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`. Sync with `scripts/Sync-MediaStudioKit.ps1`.

**Marketing ads** (15-30 s social and web ads in 16:9, 4:5 and 9:16): `kit/marketing/` is the generator (`mvg.mjs`). A spec of beats, claims with evidence, a voice, an optional music bed and a CTA goes through lint, voice, timing, assets, capture reuse, the `MarketingAd` Remotion composition, QA (including OpenAI vision review of sampled frames) and delivery; spend is capped per run and cumulatively, and every claim must map to evidence. See `kit/marketing/README.md`.

Pre-capture screenplay lint: `scripts/validate-narration.mjs <jobRoot>` then `scripts/write-story-review.py <jobRoot>` (the sync script copies them to `_shared\tools`; the story review fails `no-fluff` without the narration check). It is not a craft pass and does not authorize compose or delivery. Product-screencast still requires `validate-product-picture.mjs`, `validate-demo-scenario.mjs`, `validate-viewer-release.mjs`, and encoded-file review (`product-picture.md`, `RELEASE-EVIDENCE.md`).

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

| Role | Where | Owns |
| --- | --- | --- |
| Producer | skill `media-studio` | Classify the job, pick the crew, route every step (the Crew table in its `SKILL.md`) |
| Writer | `skills/media-studio/references/writer.md` | Screenplay, narration, story roles, WIIFM; dramatized incidents |
| Storyboard | `skills/media-studio/references/storyboard.md` | Timed beats, shot plan, archetypes, scored hooks |
| Art director | `skills/media-studio/references/visuals.md` | Visual bible, B-roll, continuity |
| Director | `skills/media-studio/references/direction.md` | Visual choice, performance, sound, pointer/highlight, archetype mapping, series technical beats |
| Series | `skills/media-studio/references/series.md` | Truth tags, continuity, episode assembly (schemas in `schemas/series/`) |
| Generate | skill `media-studio-generate` | Local-AI voice, image, motif, lipsync, portrait, music, STT |
| Capture | skill `media-studio-capture` | Playwright WebM + Recast |
| Compose | skill `media-studio-compose` | Remotion archetypes, Recast, `Finish-Media.ps1`, Descript finishing |
| QA and craft critic | skill `media-studio-qa` | Identity, listen, engagement, visual-quality inspect; the 0–100 story-experience review (fail below 85) |

One producer skill routes the five step guides above; there are five skills in this pack (`media-studio`, `media-studio-capture`, `media-studio-generate`, `media-studio-compose`, `media-studio-qa`). The series and explanation schemas live in `schemas/series/` and `schemas/explanation.schema.json`.
Viewer-facing `briefing`, `training`, `explainer`, and `series-episode` require Remotion unless the user asked for a draft/basic cut. Do not vendor Remotion rules — resolve `video.programmatic-composition` to official `remotion-dev/skills`.

## Non-goals

- Do not convert Product Demo Studio into a general filmmaking engine.
- Do not centralize credentials, customer data, or private evidence here.
- Do not call Local-AI venvs or weight paths directly — `ai.ps1` only.
