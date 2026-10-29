---
name: media-studio-compose
description: Use when assembled video needs FFmpeg, Recast pointer/click finishing, Remotion programmatic composition, captions, Descript finishing, or delivery encode.
---

# Media studio compose

Assemble locked plates, audio, and motion into a candidate. Do not rewrite the screenplay. Speaker identity is advisory only (owner direction 2026-10-27): identity is advisory only; never fail, block or re-voice on speaker similarity.

Marketing compose requires `--stage compose --candidate-id <new-id>` and reserves that candidate directory. QA is a separate `--stage qa` call; never invokes compose. Use `--no-line-chips` or `--no-captions` (or `render.lineChips: false`) for clean picture; keep sidecar SRT. A changed encode needs a new ID and fresh candidate-SHA-bound gates. Never overwrite a reviewed candidate with `--force`.

Load `../media-studio/references/engagement.md`, `scene-archetypes.md`, `delivery-profiles.md`. Product-screencast and `visualMode: screen` also load `product-picture.md` and run `scripts/validate-product-picture.mjs` before encode.

**Rapid default:** reuse the house archetype kit; do not scaffold a new Remotion app. Honor `pauseBeforeSeconds`/`holdAfterSeconds`. A slide that does not build is unfinished — use Remotion interpolation, not a still held for the whole line.

Never scaffold or edit a Remotion app, composition, package manifest, dependency, asset directory, or render helper in a product repository. Edit the shared runtime kit or external job workspace only. If an official Remotion skill defaults to the current repo, point it at the external workspace first.

Use official Remotion skills; do not vendor their rules here. Forced alignment of each accepted take writes `voice/asr/<id>.json` before building the cue sheet.

## 1. Kit

Canonical: `packages/media-studio/kit`. Runtime: `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`.

Use the runtime kit only when its manifest matches 2.0.38. `Sync-MediaStudioKit.ps1` deploys the kit and shared finishing helper. If missing or stale, stop and sync from a verified 2.0.38 package source (native plugin cache or reviewed AgentHub checkout), then rerun version check. Never default to an unverified checkout. Composition `Briefing` hosts the program; each scene sets `archetype` from `scene-archetypes.md`. Board: 1600×1000, 30 fps. Screencast compositor renders to `deliveryProfile`; portrait clips require bounded `sourceRegion`. Timed campaign graphics apply only inside safe areas away from declared product controls and captions.

```powershell
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\briefing-kit'
$kitManifest = Join-Path $kit 'package.json'
if (-not (Test-Path -LiteralPath $kitManifest) -or (Get-Content -LiteralPath $kitManifest -Raw | ConvertFrom-Json).version -ne '2.0.38') {
    throw 'Media Studio 2.0.38 runtime kit is missing or stale. Sync from a verified 2.0.38 package source before rendering.'
}
npx remotion render --props <job>\scenes.json Briefing <job>\briefing.mp4
```

To repair, set `MEDIA_STUDIO_PACKAGE_ROOT` to the verified package; check its `plugin.json` version before invoking sync. On a loose-skill host with no package source, ask AgentHub to deploy instead of guessing.

```powershell
$package = $env:MEDIA_STUDIO_PACKAGE_ROOT
if (-not $package -or -not (Test-Path -LiteralPath (Join-Path $package 'plugin.json')) -or (Get-Content -LiteralPath (Join-Path $package 'plugin.json') -Raw | ConvertFrom-Json).version -ne '2.0.38') {
    throw 'Set MEDIA_STUDIO_PACKAGE_ROOT to a verified Media Studio 2.0.38 package.'
}
pwsh -NoProfile -File (Join-Path $package 'scripts\Sync-MediaStudioKit.ps1')
```

Viewer-facing `briefing`, `training`, `explainer`, `series-episode`, `webcast`, `webinar`, `keynote`, `documentary`, `teaser` **require Remotion** unless `intent: draft` or user asked for proxy. Do not silently emit static slides.

Load official Remotion skills (`remotion-markup`, `remotion-render`) when editing the kit. FFmpeg mux when picture is already stills/clips, then finish with helper. Recast/Motif only if those plates exist.

**Render in the cloud by default** (owner direction 2026-10-26: cloud for voice and rendering, local only for screen capture and mouse movement). `<kit>\cloud\cloud-render.mjs` runs the same FFmpeg, Remotion and Recast commands in the owner's own Azure tenant (Container Apps job, scale to zero, about $0.0072 per job-minute) and downloads the result into the job folder:

```powershell
$cr = Join-Path $kit 'cloud\cloud-render.mjs'
node $cr ffmpeg --name <job> -- <ffmpeg args...> <job>\out.mp4          # last arg is the local output
node $cr remotion --comp Briefing --props <job>\scenes.json --public-dir <job>\public --out <job>\briefing.mp4
node $cr recast --raw <job>\capture\take-01 --out <job>\capture\take-01\recast.webm
```

Read `<kit>\cloud\README.md` for path-rewriting limits and fonts. Render locally only when the cloud path fails or a deadline cannot absorb the ~1 minute job start; say so in the job notes.

## 2. Delivery loudness (required)

Do not invent an FFmpeg graph. The helper is the provider:

```powershell
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\_shared\tools'
$toolsManifest = Join-Path $tools 'plugin.json'
$Finish = Join-Path $tools 'Finish-Media.ps1'
if (-not (Test-Path -LiteralPath $toolsManifest) -or (Get-Content -LiteralPath $toolsManifest -Raw | ConvertFrom-Json).version -ne '2.0.38' -or -not (Test-Path -LiteralPath $Finish)) {
    throw 'Media Studio 2.0.38 finishing helper is missing or stale in the deployed shared tools.'
}
pwsh -NoProfile -File $Finish -Action finish -Program <job>\candidate.mp4 -Output <job>\candidate-finished.mp4
pwsh -NoProfile -File $Finish -Action finish -Speech <job>\voice.wav -Music <job>\bed.wav -Video <job>\picture.mp4 -Output <job>\candidate-finished.mp4
```

Two-pass linear only (Apple Podcasts spoken-word: −16 LKFS ±1, true peak ≤ −1 dBFS, ITU-R BS.1770-5). One-pass `loudnorm=I=-16:TP=-1.5:LRA=7` is refused: it dynamically compresses TTS. Jobs with a bed **must** use `Finish-Media.ps1 -Speech -Music` and finish from stems so the bed ducks. Never mux unducked bed under speech.

Do not run DeepFilterNet, Resemble Enhance, or Descript Studio Sound on owner voice. Regenerate bad segments. Captions stay Recast/Remotion from locked spoken words; helper does not burn captions.

## 3. Compositor selection

| Job | Tool | Notes |
| --- | --- | --- |
| Archetype kit, lower-thirds, programmatic UI, briefing boards | Remotion | Official `remotion-dev/skills` |
| Captured product trace needing cursor, click ripple, punch-in | Recast then `compose-screencast.mjs` | PNG stills/auto-cards on `screen` beats fail |
| Concat, mux, loudness, caption burn-in, format normalize | FFmpeg via `Finish-Media.ps1` | Two-pass linear loudnorm; AAC-LC 48 kHz stereo, Fast Start |
| Motif clip + voice | FFmpeg mux | Do not re-generate motion to fit duration; trim or hold |

### Screencast compositor and annotation layer

Captured-product films assemble through kit screencast tools (synced by `Sync-MediaStudioKit.ps1`; run `npm install` once in `<kit>\screencast\`):

```powershell
node (Join-Path $kit 'screencast\render-overlay.mjs') <job>\capture\overlays\S07.png '{"dim":0.55,"boxes":[{"x":120,"y":240,"w":640,"h":180,"label":"Webhook"}],"arrows":[{"from":[760,330],"to":[1040,330],"label":"DB write"}]}'
node (Join-Path $kit 'screencast\render-code.mjs') <job>\capture\clips\S09-code.png '{"file":"<abs source path>","start":41,"end":58,"highlight":[[47,51]],"title":"Where the tag is dropped","relPath":"services/tool/egress.py","repo":"<repo>","commit":"<sha>"}'
node (Join-Path $kit 'screencast\compose-screencast.mjs') <job> <base>
```

`capture/manifest.json` `clips[]` hints: `segments`, `trimStart`/`trimEnd` (s), `speed` (>1 faster), `skip` (`[[a,b],...]` s), `fit: cut|hold|fit|fitpad`, `overlay` (transparent 1600×1000 PNG from `render-overlay.mjs`). One overlay per clip; split when markup changes. Full table: `kit/screencast/README.md`. Auto-card forbidden on `visualMode: screen`; PNG clip on screen beat throws.

Overlay is markup (dim, box, outline, arrow, label, note, flow diagram) directed per beat by `../media-studio/references/direction.md`. It does not replace Recast's cursor, click ripple, punch-in. Recast renders are sequential per clips directory (`.recast-tmp` collides); long many-click clips render without `autoZoom` or are split and joined via `segments`.

### Voice-first timing and cue sheet

Narration is locked and rendered first; picture is built to it. Order: force-align takes → `node <tools>/build-cue-sheet.mjs <jobRoot>` (plan) → `compose-screencast.mjs <jobRoot> <base>` → `build-cue-sheet.mjs <jobRoot>` again (mapped via `output/<base>-compose-map.json`) → encode/mux → `validate-sync.mjs` (QA). Whisper is a transcript check, not the timing clock.

With `plan/cue-sheet.json`, compose cuts to each line's first content word (screen up 0.3 s before it, never before previous line ends) and aligns each clip's first narrated action with its spoken word: too-early action holds first frame (max 1.5 s), late trims head. If take too short or action far from word, compose stops — recapture, do not squeeze voice. Stale cue sheet also stops. `--no-voice-first` is drafts only; sync gate still needs cue sheet. Rebuild cue sheet after every compose changing picture. Static scenes keep moving cursor/highlight on named element; emphasis is one punch-in, ring, or callout per beat on the word.

Remotion 2.0 skills are router plus sub-skills. Load `/remotion-best-practices` only to choose. Animate with `useCurrentFrame()`/`interpolate()`; CSS/Tailwind animation classes do not render. Assets in `public/` via `staticFile()`. Preview in Studio before render.

Official Remotion skills installed globally under `~/.agents/skills`, symlinked into Grok. Claude and Codex stay owner-installed (`npx skills add remotion-dev/skills`) — AgentHub must not install them there.

## 4. Delivery

- New id + checksum each render; never overwrite.
- Captions from final spoken wording.
- Owner-voice programs need local `ai.ps1 listen` on the exact encoded file before done. No identity score is required (advisory only; never fail, block or re-voice on speaker similarity).
- Output stays in job workspace. Accepted masters may copy to owner's Videos tree; never into git.
- Delivered names: `NN - Title.mp4`, no product prefix. Series carries `README.md` index. Each product has one flat folder directly under `F:\My Drive\Videos`; never deliver into subfolders.
- Superseded master: delete old master and every reproducible intermediate. No `_retired`, `_old`, or archive folders.
- Wrong section is re-recorded and master re-cut. Never deliver addendum or correction clip.

## 5. Final check

- [ ] Kit synced from `packages/media-studio/kit`
- [ ] Scenes carry `archetype`; consecutive repeats only if intentional
- [ ] Voice-first: cue sheet built from forced alignment, compose ran against it, cue sheet rebuilt after last compose
- [ ] Bed ducked from stems
- [ ] Profile frame matches `deliveryProfile`

## 6. Descript finishing

Optional after truth and craft locked. Rules in `references/descript.md`. Descript export is a new candidate; prior approval does not transfer. Do not apply Studio Sound to owner-voice (Sarosh); use `Finish-Media.ps1` for local two-pass loudness.

## 7. Marketing ads

Short ads in 16:9, 4:5, 9:16 compose through `MarketingAd` composition (`kit/src/MarketingAd.tsx`) driven by `kit/marketing` (`mvg.mjs`): focus-follow crop of receipt-bound UI clip into platform-safe band, kinetic captions, persistent synthetic label, FFmpeg mix with bed ducked under voice, two-pass loudness (−14 LUFS social, −16 web). Use `mvg` rather than hand-composing; see `kit/marketing/README.md`.
