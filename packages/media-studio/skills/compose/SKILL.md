---
name: compose
description: Produces an encoded candidate and loudness-mastered delivery file from locked voice, picture and plates. Use when someone asks to assemble, render, cut, mux, duck music, fix loudness or deliver a film. Not for capture or generation; use capture or generate.
---

# Compose

Assemble locked inputs. Do not rewrite the screenplay. Never scaffold or edit a Remotion app, composition, manifest, dependency or render helper in a product repository; work in the shared runtime kit or the job workspace. If an official Remotion skill defaults to the current repo, point it at the workspace first.

Check the runtime first:

```powershell
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/briefing-kit'
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/_shared/tools'
foreach ($m in "$kit/package.json", "$tools/plugin.json") { if ((Get-Content $m -Raw | ConvertFrom-Json).version -ne '2.1.1') { throw "Stale runtime: $m" } }
```

To repair, set `MEDIA_STUDIO_PACKAGE_ROOT` to a package whose `plugin.json` version is `'2.1.0'`, then run `pwsh -NoProfile -File "$env:MEDIA_STUDIO_PACKAGE_ROOT/scripts/Sync-MediaStudioKit.ps1"`. With no package source, ask for an AgentHub deploy instead of guessing.

## Pick the tool

One renderer per job.

| Job | Tool |
| --- | --- |
| Archetype kit, parametrised templates | Remotion. Use the official agent skills (`remotion-dev/skills`), do not restate them |
| HTML with a paused GSAP timeline | HyperFrames, when the job names it |
| Captured product | Recast, then `compose-screencast.mjs` |
| Concat, mux, format | FFmpeg, finished by `Finish-Media.ps1` |

Composition `Briefing` hosts the program; each scene sets `archetype`. The board is 1600×1000 at 30 fps. Render with `node scripts/render-program.mjs` after `validate-picture-inputs.mjs` passes. A slide that does not build is unfinished.

## Screencast order

Do not change this order, because the picture is built to the voice:

```powershell
node <tools>/build-cue-sheet.mjs <jobRoot>
node <kit>/screencast/compose-screencast.mjs <jobRoot> <base>
node <tools>/build-cue-sheet.mjs <jobRoot> --compose-map output/<base>-compose-map.json
```

Compose stops on a stale cue sheet, a take too short, or an action far from its word. Recapture; never squeeze the voice. `--no-voice-first` is for drafts only. Rebuild the cue sheet after every compose that changes the picture.

Clip hints in `capture/manifest.json` `clips[]`: `segments`, `trimStart`, `trimEnd`, `speed`, `skip`, `fit: cut|hold|fit|fitpad`, `overlay`. Full table: `kit/screencast/README.md`. Read `../video/references/product-picture.md` for any `screen` beat.

## Loudness master

Finish with the helper. Do not hand-write an FFmpeg graph. It runs two-pass linear loudnorm and refuses one-pass.

```powershell
pwsh -NoProfile -File "$tools/Finish-Media.ps1" -Action finish -Speech voice.wav -Music bed.wav -Video picture.mp4 -Output candidate-finished.mp4 -Integrated -14 -TruePeak -1
```

| Target | `-Integrated` | `-TruePeak` |
| --- | --- | --- |
| YouTube, web (about) | -14 | -1 |
| Podcast, spoken word | -16 | -1 |
| Broadcast, EBU R128 | -23 | -1 |

Set `loudnessTargetLufs` in `job.json` to the same target; the release gate defaults to -16. A job with a bed must finish from stems with `-Speech -Music` so the helper ducks the bed (asplit, sidechaincompress, amix; 200 ms attack, 800 ms release). Start the bed about -18 dB under speech and adjust by ear. Never mux an unducked bed. If only LRA blocks the linear pass, add `-LoudnessRange 11`; never `-AllowDynamic` on TTS. Do not run a hosted enhancer on voice; regenerate the segment.

Captions are a sidecar `.srt` from `write-captions.mjs`, built from the spoken words. Never embed or burn them in.

## Placement

Capture stays local. Pick the render lane from measured load and report lane and cost. Read `references/render-lanes.md` when the PC is taxed or the job fans out.

## Delivery

Use a new id and checksum for each render; never overwrite a reviewed candidate. After `review` passes:

- One flat folder per product directly under `F:/My Drive/Videos`, no subfolders. Files are `NN - Title.mp4` with the `.srt` beside them and one `README.md` index.
- Delete a superseded master and its reproducible intermediates. No `_old` or archive folders.
- Never put media in git or a product repository. Status names the rung: merged to dev, in main, deployed, production-verified.

Read `references/descript.md` when a job asks for optional Descript finishing.
