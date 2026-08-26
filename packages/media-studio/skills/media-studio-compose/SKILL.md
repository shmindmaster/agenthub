---
name: media-studio-compose
description: Use when assembled video needs FFmpeg, Recast pointer/click finishing, Remotion programmatic composition, captions, or delivery encode.
---

# Media studio compose

Assemble locked plates, audio, and motion into a candidate in this turn. You do not rewrite the screenplay or waive identity gates.

**Rapid default:** reuse the house briefing kit, do not scaffold a new Remotion app.

Kit (runtime, not git): `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`  
Composition `Briefing`, 1600×1000, 30 fps. Put scene JSON in the job workspace and optional WAV in `public/`.

```powershell
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\briefing-kit'
npx remotion render --props <job>\scenes.json Briefing <job>\briefing.mp4
```

Load official Remotion skills (`remotion-markup`, `remotion-render`) when editing the kit. FFmpeg mux when the picture is already stills or clips. Recast/Motif only if those plates exist.

## Pick a compositor

| Job | Tool | How |
| --- | --- | --- |
| Motion slides, lower-thirds, programmatic UI, briefing boards | Remotion | Official `remotion-dev/skills` — `/remotion-create`, `/remotion-markup`, `/remotion-studio`, `/remotion-render`, `/remotion-captions`. Do not vendor those rules here. |
| Captured product trace that needs cursor, click ripple, punch-in zoom | Recast (`playwright-recast`) | Same lane as product-demo-studio-render. Prefer bouncing a true product screencast to that pipeline. |
| Concat, mux, loudness, caption burn-in, format normalize | FFmpeg | Already on PATH. Smallest filter graph that does the job. |
| Motif clip + voice | FFmpeg mux | Do not re-generate motion to "fit" duration; trim or hold. |

Remotion 2.0 skills are a **router plus sub-skills**. Load `/remotion-best-practices` only to choose; then the specific skill. Animate with `useCurrentFrame()` / `interpolate()`; CSS/Tailwind animation classes do not render. Assets in `public/` via `staticFile()`. Preview in Studio before render.

Official Remotion skills are installed globally under `~/.agents/skills` and symlinked into Grok. Claude and Codex stay owner-installed (`npx skills add remotion-dev/skills`) — AgentHub must not install them there.

## Delivery

- Do not overwrite a candidate; new id + checksum each render.
- Captions from the final spoken wording.
- Owner-voice programs still need identity score + local `ai.ps1 listen` on the exact encoded file before anyone calls it done.
- Output stays in the job workspace. Accepted masters may be copied to the owner's Videos tree; never into git.
