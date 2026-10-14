# Media Studio Remotion kit

Canonical scene-archetype library. Runtime copy:

`%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`

Sync with `packages/media-studio/scripts/Sync-MediaStudioKit.ps1` before render. Do not `create-video` a new app. Composition `Briefing`, native 1600×1000 30 fps.

Each scene sets `archetype` from `scene-archetypes.json`. Consecutive repeats are forbidden unless intentional.

Stakeholder Q&A: set `speaker` to `ryan` | `vivian` | `aiden` for labeled question cards (name + role + short Q). Omit or use `sarosh` for host narration. See `scene-archetypes.md` § Stakeholder Q&A.

`screencast/` is the screencast compositor and annotation layer (`compose-screencast.mjs`, `render-overlay.mjs`, `render-code.mjs`, `render-html.mjs`, `render-card.mjs`). The compositor uses the job's delivery profile, including 16:9, 9:16 and 4:5 campaign frames. It needs `playwright` from this kit's `package.json`; manifest hints and timed graphics are documented in `screencast/README.md`.
