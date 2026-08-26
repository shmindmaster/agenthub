# Local-AI video (progressive load)

Load when the task needs motif clips, lipsync, portrait motion, or avatar queues.
Control plane remains `ai.ps1` / `$LocalAiControl`. Images stay in `image.md`;
music stays in `music.md`; speech stays in `voice.md`.

ComfyUI is the image/motif canvas. Do **not** start it for TTS or ACE-Step.

## Motif (primary generated motion)

Capability `video.motif-q8`. Image-to-video on the 16 GB card via Q8 GGUF.

```powershell
& $LocalAiControl motif verify
& $LocalAiControl motif --reference <still.png> --prompt "…" --out <clip.mp4>
```

Defaults from the runner: 640×368 (divisible by 16), 49 frames, 16 fps, 20 steps.
Exact logos, UI chrome, and legal text are compositor work — never Motif.

## Lipsync

Capability `video.lipsync.latentsync-1.5`. Existing talking-head video + new audio.
ByteDance LatentSync 1.5 is the consumer-GPU pick (~8 GB). 1.6 is sharper and
needs ~18 GB — do not silently swap.

```powershell
& $LocalAiControl lipsync <source.mp4> --audio <speech.wav>
```

Requires a visible forward-facing face. Anime/cartoon faces are out of scope.
Generate the voice first (`voice.md`), then lipsync.

## Portrait (specialty)

Capability `video.portrait.liveportrait`. Still → motion. Not the default
talking-head path.

```powershell
& $LocalAiControl portrait <source.png>
```

## Avatar / facefix (specialty)

`ai.ps1 avatar` is WanGP (heavy, 14 GiB guard). `ai.ps1 facefix` is FaceFusion.
Both are on-disk specialty — not the default discovery path. Ask before reclaiming
GPU for them.

## GPU

`policy.gpu_heavy_jobs` is serialized. Motif, lipsync, Comfy, and music must not
share the card. Reclaim only with task authority after identifying the occupant.
