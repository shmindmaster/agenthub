---
name: media-studio-compose
description: Use when assembled video needs FFmpeg, Recast pointer/click finishing, Remotion programmatic composition, captions, or delivery encode.
---

# Media studio compose

Assemble locked plates, audio, and motion into a candidate in this turn. You do not rewrite the screenplay or waive identity gates.

Load `../media-studio/references/engagement.md`, `scene-archetypes.md`, and `delivery-profiles.md`. Product-screencast and `visualMode: screen` also load `product-picture.md` and run `scripts/validate-product-picture.mjs` before encode.

**Rapid default:** reuse the house archetype kit, do not scaffold a new Remotion app. Honor `pauseBeforeSeconds` / `holdAfterSeconds`. A slide that does not build is unfinished — use Remotion interpolation, not a still held for the whole line.

Never scaffold or edit a Remotion app, composition, package manifest,
dependency, asset directory, or render helper in a product repository. Edit the
shared runtime kit or the external job workspace only. If an official Remotion
skill defaults to the current repo, point it at the external workspace first.

## 1. Kit

Canonical source: `packages/media-studio/kit`  
Runtime copy: `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`

Sync `kit/src` into the runtime kit before render if the runtime copy is missing or older. Composition `Briefing` still hosts the program; each scene sets `archetype` from `scene-archetypes.md`. Native frame 1600×1000 30 fps; letterbox or scale to `deliveryProfile`.

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
pwsh -NoProfile -File (Join-Path $Hub 'packages\media-studio\scripts\Sync-MediaStudioKit.ps1')
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\briefing-kit'
npx remotion render --props <job>\scenes.json Briefing <job>\briefing.mp4
```

Viewer-facing `briefing`, `training`, `explainer`, `series-episode`, `webcast`, `webinar`, `keynote`, `documentary`, and `teaser` **require Remotion** unless `intent: draft` or the user asked for a basic/proxy cut. Do not silently emit static slides.

Load official Remotion skills (`remotion-markup`, `remotion-render`) when editing the kit. FFmpeg mux when the picture is already stills or clips, then finish with the helper below. Recast/Motif only if those plates exist.

## 2. Delivery loudness (required)

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

## 3. Pick a compositor

| Job | Tool | How |
| --- | --- | --- |
| Archetype kit, lower-thirds, programmatic UI, briefing boards | Remotion | Official `remotion-dev/skills`. Do not vendor those rules here. |
| Captured product trace that needs cursor, click ripple, punch-in zoom | Recast (`playwright-recast`) then `compose-screencast.mjs` | `media-studio-capture` then this compose step. PNG stills and auto-cards on `screen` beats fail (`product-picture.md`). |
| Concat, mux, loudness, caption burn-in, format normalize | FFmpeg via `Finish-Media.ps1` | Two-pass **linear** loudnorm. Music duck required when a bed exists. AAC-LC 48 kHz stereo, Fast Start. |
| Motif clip + voice | FFmpeg mux | Do not re-generate motion to "fit" duration; trim or hold. |

### Screencast compositor and annotation layer

Captured-product films (product screencasts, `programForm: technical-story`) assemble through the kit's screencast tools, synced to `<runtime kit>\screencast\` by the same `Sync-MediaStudioKit.ps1` (run `npm install` once there so `playwright` resolves):

```powershell
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\briefing-kit'
node (Join-Path $kit 'screencast\render-overlay.mjs') <job>\capture\overlays\S07.png '{"dim":0.55,"boxes":[{"x":120,"y":240,"w":640,"h":180,"label":"Webhook"}],"arrows":[{"from":[760,330],"to":[1040,330],"label":"DB write"}]}'
node (Join-Path $kit 'screencast\render-code.mjs') <job>\capture\clips\S09-code.png '{"file":"<abs source path>","start":41,"end":58,"highlight":[[47,51]],"title":"Where the tag is dropped","relPath":"services/tool/egress.py","repo":"<repo>","commit":"<sha>"}'
node (Join-Path $kit 'screencast\compose-screencast.mjs') <job> <base>
```

`capture/manifest.json` `clips[]` hints, applied per clip by the compositor: `segments` (segment or scene ids), `trimStart` / `trimEnd` (seconds), `speed` (>1 = faster, for real waits), `skip` (`[[a,b],...]` seconds to drop), `fit: cut|hold|fit|fitpad`, and `overlay` (a transparent 1600×1000 PNG from `render-overlay.mjs`, composited over the scaled frame for that clip's segments). One overlay per clip; split the clip when the markup changes. Full table: `kit/screencast/README.md`. Auto-card is forbidden on `visualMode: screen`; a PNG clip on a screen beat throws.

The overlay is markup (dim, box, outline, arrow, label, note, flow diagram), directed per beat by `media-director` for technical stories. It is not a second engagement rubric and it does not replace Recast's cursor, click ripple, and punch-in. Recast renders are sequential per clips directory (`.recast-tmp` collides); long many-click clips render without `autoZoom` or are split and joined here through `segments`.

Remotion 2.0 skills are a **router plus sub-skills**. Load `/remotion-best-practices` only to choose; then the specific skill. Animate with `useCurrentFrame()` / `interpolate()`; CSS/Tailwind animation classes do not render. Assets in `public/` via `staticFile()`. Preview in Studio before render.

Official Remotion skills are installed globally under `~/.agents/skills` and symlinked into Grok. Claude and Codex stay owner-installed (`npx skills add remotion-dev/skills`) — AgentHub must not install them there.

## 4. Delivery

- Do not overwrite a candidate; new id + checksum each render.
- Captions from the final spoken wording.
- Owner-voice programs still need identity score + local `ai.ps1 listen` on the exact encoded file before anyone calls it done.
- Output stays in the job workspace. Accepted masters may be copied to the owner's Videos tree; never into git.
- Delivered file names are `NN - Title.mp4` with no product prefix (`03 - The tag that never landed.mp4`). A delivered series carries a `README.md` index in its folder.
- When a master is superseded, delete the old master and every reproducible intermediate outright. No `_retired`, `_old`, or archive folders; the job workspace and git history are the record.
- A wrong section is re-recorded and the master re-cut. Never deliver an addendum or correction clip.

## 5. Final check

- [ ] Kit synced from `packages/media-studio/kit`
- [ ] Scenes carry `archetype`; consecutive repeats only if intentional
- [ ] Bed ducked from stems
- [ ] Profile frame matches `deliveryProfile`
