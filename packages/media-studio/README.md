# media-studio

The **public** video/audio/animation plugin. Replaces product-demo-studio as the skill pack agents load.

**Rapid default:** a concept, outline, or bullet list is enough. Writer → director → Local-AI generate → Remotion/FFmpeg/Recast compose.

Live-product screencasts still use the gated Playwright + Recast + four-domain engine that lives in `packages/product-demo-studio` (pipeline, scripts, agents). Those `product-demo*` **skills are retired**; `media-studio` invokes that engine.

**Heavy GPU** (Motif, lipsync, music) is opt-in.

Version authority: root `plugin.json` (`1.1.0`). Host projections must match.
Runtime media stays outside AgentHub (`%LOCALAPPDATA%\AgentHub\media-studio` and `D:\Local-AI\data\artifacts`). Private show bibles and customer recordings stay outside this repository.

## Why this exists

Product Demo Studio is a specialized, fail-closed **product screencast** pipeline (Playwright capture, Recast pointer/click, four-domain review). Agents were routing briefings, training films, explainers, talking-heads, and motion-slide pieces through it because it was the only video pack.

This package is the parent studio. Product Demo Studio remains the product-screencast workflow inside it.

## Crew (skills, not a second control plane)

| Role | Skill | Owns |
| --- | --- | --- |
| Producer | `media-studio` | Classify the job, pick the crew, bounce specialized pipelines |
| Writer | `media-writer` | Screenplay, narration script, shot list |
| Director | `media-director` | Visual plan, scene design, pointer/highlight choreography, performance |
| Generate | `media-studio-generate` | Local-AI voice, image, motif, lipsync, portrait, music, STT |
| Compose | `media-studio-compose` | Remotion, Recast, FFmpeg assembly |

Do not vendor Remotion rules. Resolve `video.programmatic-composition` to the official `remotion-dev/skills` pack.

## Non-goals

- Do not convert Product Demo Studio into a general filmmaking engine.
- Do not centralize credentials, customer data, or private evidence here.
- Do not call Local-AI venvs or weight paths directly — `ai.ps1` only.
