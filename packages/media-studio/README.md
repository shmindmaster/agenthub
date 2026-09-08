# media-studio

The **only public** video/audio/animation plugin. Infer form from the ask
(product demo, briefing, explainer, talking-head, and the rest) and run that
workflow. Product-demo-studio is the internal screencast engine, not a second
plugin.

**Rapid default:** a sentence or a source path is enough. Infer kind and delivery. Still run curation, gap-closure, writer, storyboard, visuals, director, Local-AI generate, Remotion/FFmpeg/Recast, craft critic, QA. Rapid means infer-and-run, not skip craft. Ask the user only when blocked.

Live-product screencasts still use the gated Playwright + Recast + four-domain engine that lives in `packages/product-demo-studio` (pipeline, scripts, agents). Those `product-demo*` **skills are retired**; `media-studio` invokes that engine.

**Viewer-facing** jobs apply `skills/media-studio/references/engagement.md` and `story-craft.md`. The screenplay carries story role, WIIFM, and tension; the storyboard carries shot plan, archetype, and sound. Score < 85 from `media-story-experience-reviewer` does not ship. `intent: draft` skips GPU plates and the critic gate. Product-screencast craft stays in the PDS killer-demo guide.

**Technical stories** (`programForm: technical-story`) are product or engineering changes told as 5–8 minute mini documentaries: `skills/media-studio/references/technical-story.md` holds the beat map and markup rules; `kit/screencast/` holds the compositor, annotation overlay, code-reveal and card renderers with their manifest hints. Product-specific capture notes live under `skills/media-studio-capture/references/`.

Version authority: root `plugin.json` (`1.5.4`). Host projections must match.
Runtime media stays outside AgentHub (`%LOCALAPPDATA%\AgentHub\media-studio` and `D:\Local-AI\data\artifacts`). Private show bibles and customer recordings stay outside this repository.

Canonical Remotion kit: `kit/` (scene-archetype library, plus `kit/screencast/` compositor tooling). Runtime copy: `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`. Sync with `scripts/Sync-MediaStudioKit.ps1`.

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

| Role | Skill | Owns |
| --- | --- | --- |
| Producer | `media-studio` | Classify the job, pick the crew, bounce specialized pipelines |
| Writer | `media-writer` | Screenplay, narration, story roles, WIIFM |
| Storyboard | `media-storyboard` | Timed beats, shot plan, archetypes, scored hooks |
| Art director | `media-studio-visuals` | Visual bible, B-roll, continuity |
| Director | `media-director` | Performance, sound, pointer/highlight, archetype mapping |
| Generate | `media-studio-generate` | Local-AI voice, image, motif, lipsync, portrait, music, STT |
| Compose | `media-studio-compose` | Remotion archetypes, Recast, `Finish-Media.ps1` |
| Craft critic | `media-story-experience-reviewer` | 0–100 story/experience score; fail below 85 |
| QA | `media-studio-qa` | Identity, listen, engagement, visual-quality inspect |

Viewer-facing `briefing`, `training`, `explainer`, and `series-episode` require Remotion unless the user asked for a draft/basic cut. Do not vendor Remotion rules — resolve `video.programmatic-composition` to official `remotion-dev/skills`.

## Non-goals

- Do not convert Product Demo Studio into a general filmmaking engine.
- Do not centralize credentials, customer data, or private evidence here.
- Do not call Local-AI venvs or weight paths directly — `ai.ps1` only.
