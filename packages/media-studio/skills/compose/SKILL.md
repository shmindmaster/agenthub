---
name: compose
description: Produces an encoded candidate and loudness-mastered delivery file from locked voice, picture and plates. Use when someone asks to assemble, render, cut, mux, duck music, fix loudness or deliver a film. Not for capture or generation; use capture or generate.
---

# Compose

## Workflow contract

1. Use the accepted assets and receipts, approved plan and valid timing evidence.
2. Build the candidate from the accepted sources, regenerate dependent cues after picture changes and run the delivery gates.
3. Hand `review` the encoded candidate, compose map and matching QA evidence.
4. If a cue, take or receipt is invalid, return that beat to its owning stage and preserve the last accepted candidate.

Assemble locked inputs. Do not rewrite the screenplay. Never scaffold or edit a Remotion app, composition, manifest, dependency or render helper in a product repository; work in the shared runtime kit or the job workspace.

Check the runtime first; repair a stale one from `MEDIA_STUDIO_PACKAGE_ROOT`; never guess.

```powershell
$kit = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/briefing-kit'
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/_shared/tools'
foreach ($m in "$kit/package.json", "$tools/plugin.json") { if ((Get-Content $m -Raw | ConvertFrom-Json).version -ne '2.5.0') { throw "Stale runtime: $m" } }
```

## Pick the tool

One renderer per job:

- Archetype kit, parametrised templates: Remotion via the official `remotion-dev/skills` (board 1600×1000, 30 fps). Render only after `validate-picture-inputs.mjs` passes.
- Paused GSAP timeline HTML: HyperFrames, when the job names it.
- Captured product: Recast, then `compose-screencast.mjs`.
- Concat, mux, format: FFmpeg, finished by `Finish-Media.ps1`.

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

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
