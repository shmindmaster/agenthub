# Media Studio Remotion kit

Canonical scene-archetype library. Runtime copy:

`%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`

Sync with `packages/media-studio/scripts/Sync-MediaStudioKit.ps1` before render. Do not `create-video` a new app. Composition `Briefing`, native 1600×1000 30 fps.

Each scene sets `archetype` from `scene-archetypes.json`. Consecutive repeats are forbidden unless intentional.

`screencast/` is the screencast compositor and annotation layer (`compose-screencast.mjs`, `render-overlay.mjs`, `render-code.mjs`, `render-html.mjs`, `render-card.mjs`). It needs `playwright` from this kit's `package.json`; manifest hints are documented in `screencast/README.md`.
