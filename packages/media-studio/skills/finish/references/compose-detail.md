# Workflow detail


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
