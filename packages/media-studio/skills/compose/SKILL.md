---
name: compose
description: Produces an encoded candidate and loudness-mastered delivery file from locked voice, picture and plates. Use when someone asks to assemble, render, cut, mux, duck music, fix loudness or deliver a film. Not for capture or generation; use capture or generate.
---

# Compose

Assemble locked inputs. Do not rewrite the screenplay. Never scaffold or edit a Remotion app, composition, manifest, dependency or render helper in a product repository; work in the shared runtime kit or the job workspace.

Check the runtime first; repair a stale one from `MEDIA_STUDIO_PACKAGE_ROOT`; never guess.

```powershell
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/briefing-kit'
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/_shared/tools'
foreach ($m in "$kit/package.json", "$tools/plugin.json") { if ((Get-Content $m -Raw | ConvertFrom-Json).version -ne '2.4.5') { throw "Stale runtime: $m" } }
```

## Pick the tool

One renderer per job:

- Archetype kit, parametrised templates: Remotion via the official `remotion-dev/skills` (board 1600×1000, 30 fps). Render only after `validate-picture-inputs.mjs` passes.
- Paused GSAP timeline HTML: HyperFrames, when the job names it.
- Captured product: Recast, then `compose-screencast.mjs`.
- Concat, mux, format: FFmpeg, finished by `Finish-Media.ps1`.

## Screencast order

Do not change this order; the picture is built to the voice:

```powershell
node <tools>/build-cue-sheet.mjs <jobRoot>
node <kit>/screencast/compose-screencast.mjs <jobRoot> <base>
node <tools>/build-cue-sheet.mjs <jobRoot> --compose-map output/<base>-compose-map.json
```

When compose stops on a stale cue sheet, short take or action far from its word, recapture; never squeeze the voice. `--no-voice-first` is for drafts only. Rebuild the cue sheet after every compose that changes the picture.

Clip hints in `capture/manifest.json` `clips[]`: `segments`, `trimStart`, `trimEnd`, `speed`, `skip`, `fit: cut|hold|fit|fitpad`, `overlay`. Full table: `kit/screencast/README.md`.

## Loudness master

Finish with the helper, never a hand-written FFmpeg graph; it runs two-pass linear loudnorm and refuses one-pass.

```powershell
pwsh -NoProfile -File "$tools/Finish-Media.ps1" -Action finish -Speech voice.wav -Music bed.wav -Video picture.mp4 -Output candidate-finished.mp4 -Integrated -14 -TruePeak -1
```

Set `loudnessTargetLufs` in `job.json` to the same target. A job with a bed must finish from stems with `-Speech -Music` so the helper ducks the bed. Never mux an unducked bed. Never `-AllowDynamic` on TTS. Do not run a hosted enhancer on voice; regenerate the segment.

Captions are a sidecar `.srt` from `write-captions.mjs`, built from the spoken words. Never embed or burn them in.

## Placement

Capture stays local. Pick the render lane from measured load and report lane and cost.

## Delivery

Use a new id and checksum for each render; never overwrite a reviewed candidate. After `review` passes:

- Deliver to `F:/My Drive/Videos/<Area>/<Customer or company>/`, two folder levels at most. Files are `NN - Title.mp4` with the `.srt` beside them and one `README.md` index. Read `references/library.md` before naming a folder or file.
- Delete a superseded master and its reproducible intermediates. No `_old`, type or archive folders.
- Never put media in git or a product repository. Status names the rung: merged to dev, in main, deployed, production-verified.

## References

- `references/library.md`: Read before delivering. It holds the folder layout, file names and kind words.
- `references/runtime.md`: Read when the runtime check throws.
- `references/briefing.md`: Read when rendering with Remotion.
- `references/loudness.md`: Read when the target is not web or the bed needs tuning.
- `references/render-lanes.md`: Read when the PC is taxed or the job fans out.
- `references/descript.md`: Read when a job wants Descript finishing.
- `../video/references/product-picture.md`: Read when any beat is `screen`.
