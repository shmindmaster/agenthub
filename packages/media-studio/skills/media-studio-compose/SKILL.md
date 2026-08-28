---
name: media-studio-compose
description: Use when assembled video needs FFmpeg, Recast pointer/click finishing, Remotion programmatic composition, captions, or delivery encode.
---

# Media studio compose

Assemble locked plates, audio, and motion into a candidate in this turn. You do not rewrite the screenplay or waive identity gates.

Load `../media-studio/references/engagement.md` (Generate / compose / QA own) for pause/hold, duck, and build-in.

**Rapid default:** reuse the house briefing kit, do not scaffold a new Remotion app. Honor `pauseBeforeSeconds` / `holdAfterSeconds`. A slide that does not build is unfinished — use Remotion interpolation, not a still held for the whole line.

Never scaffold or edit a Remotion app, composition, package manifest,
dependency, asset directory, or render helper in a product repository. Edit the
shared runtime kit or the external job workspace only. If an official Remotion
skill defaults to the current repo, point it at the external workspace first.

Kit (runtime, not git): `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`  
Composition `Briefing`, 1600×1000, 30 fps. Put scene JSON in the job workspace and optional WAV in `public/`.

```powershell
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\briefing-kit'
npx remotion render --props <job>\scenes.json Briefing <job>\briefing.mp4
```

Load official Remotion skills (`remotion-markup`, `remotion-render`) when editing the kit. FFmpeg mux when the picture is already stills or clips, then finish with the helper below. Recast/Motif only if those plates exist.

## Delivery loudness (required)

Do not invent an FFmpeg graph. The helper is the provider:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Finish = Join-Path $Hub 'packages\media-studio\scripts\Finish-Media.ps1'
pwsh -NoProfile -File $Finish -Action finish -Program <job>\candidate.mp4 -Output <job>\candidate-finished.mp4
pwsh -NoProfile -File $Finish -Action finish -Speech <job>\voice.wav -Music <job>\bed.wav -Video <job>\picture.mp4 -Output <job>\candidate-finished.mp4
```

Two-pass linear only. That matches Apple Podcasts spoken-word (−16 LKFS ±1, true peak ≤ −1 dBFS, ITU-R BS.1770-5) and the Product Demo Studio gate. One-pass `loudnorm=I=-16:TP=-1.5:LRA=7` is refused: it dynamically compresses TTS takes.

Viewer-facing jobs with a bed **must** finish from stems (`-Speech -Music`) so the bed ducks. Do not mux an unducked bed under speech.

Do not run DeepFilterNet, Resemble Enhance, or Descript Studio Sound on owner voice. Regenerate a bad segment. Captions stay Recast/Remotion from the locked spoken words; this helper does not burn captions.

## Pick a compositor

| Job | Tool | How |
| --- | --- | --- |
| Motion slides, lower-thirds, programmatic UI, briefing boards | Remotion | Official `remotion-dev/skills` — `/remotion-create`, `/remotion-markup`, `/remotion-studio`, `/remotion-render`, `/remotion-captions`. Do not vendor those rules here. |
| Captured product trace that needs cursor, click ripple, punch-in zoom | Recast (`playwright-recast`) | `media-studio-capture` then this compose step. Do not load retired `product-demo*` skills. |
| Concat, mux, loudness, caption burn-in, format normalize | FFmpeg via `Finish-Media.ps1` | Two-pass **linear** loudnorm `I=-16:TP=-1.5:LRA=7`. Never one-pass (that mode is dynamic pumping). Music duck required when a bed exists. AAC-LC 48 kHz stereo, Fast Start. |
| Motif clip + voice | FFmpeg mux | Do not re-generate motion to "fit" duration; trim or hold. |

Remotion 2.0 skills are a **router plus sub-skills**. Load `/remotion-best-practices` only to choose; then the specific skill. Animate with `useCurrentFrame()` / `interpolate()`; CSS/Tailwind animation classes do not render. Assets in `public/` via `staticFile()`. Preview in Studio before render.

Official Remotion skills are installed globally under `~/.agents/skills` and symlinked into Grok. Claude and Codex stay owner-installed (`npx skills add remotion-dev/skills`) — AgentHub must not install them there.

## Delivery

- Do not overwrite a candidate; new id + checksum each render.
- Captions from the final spoken wording.
- Owner-voice programs still need identity score + local `ai.ps1 listen` on the exact encoded file before anyone calls it done.
- Output stays in the job workspace. Accepted masters may be copied to the owner's Videos tree; never into git.
