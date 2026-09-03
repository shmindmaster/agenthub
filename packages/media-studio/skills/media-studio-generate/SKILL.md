---
name: media-studio-generate
description: Use when a video or audio job needs local generation — owner or role voice, images, motif clips, lipsync, portrait, music beds, stings, or transcription — through the Local-AI control plane.
---

# Media studio generate

Load `local-ai-stack` first and resolve `$LocalAiControl`. For hour-scale batches also load `long-running-generation`. One heavy GPU job at a time.

Load `../media-studio/references/engagement.md`. Viewer-facing jobs consume **locked** `storyboard.json`, `visual-bible.json`, and `direction.json`. Do not invent plates the director did not call.

Owner voice is local-only. Never ElevenLabs or another hosted TTS for Sarosh.

```powershell
& $LocalAiControl status
& $LocalAiControl check
```

Start only the route you need (`voice`, `media` / Comfy, `music`). Do not start Comfy for TTS or music.

## 1. Inputs

| File | Required when |
| --- | --- |
| `narration.md` / screenplay | always |
| `direction.json` | viewer-facing: register, duration, plates per beat |
| `storyboard.json` | viewer-facing: `sound`, `shotPlan`, silence windows |
| `visual-bible.json` | viewer-facing B-roll / motif |

If a required file is missing, remit. Do not generate a generic bed and skip the bible.

## 2. Voice

TTS **always**. Per beat, use `direction.register` (Sarosh style-bank: `explaining`, `firm`, `serious`, …). Do not write free-text "sound excited". Do not respell.

```powershell
& $LocalAiControl voice qwen-clone --voice sarosh --reference <style.wav> --ref-text <sidecar> --text "…" --out <beat>.wav
& $LocalAiControl voice score --voice sarosh <wav>
```

Score every owner-voice segment before compose. Honor `pauseBeforeSeconds` / `holdAfterSeconds` as silence in the edit, not as padded TTS.

## 3. Music and silence

Viewer-facing jobs also generate the directed music (`musicCue: bed` or `sting`) unless `intent: draft` or `music: none`.

| Storyboard `sound.musicCue` | Generate |
| --- | --- |
| `bed` | one ACE-Step bed for the program (`ai.ps1 music`) |
| `sting` | a **short** ACE-Step sting (2–4s hit), not a second full bed |
| `silence` | **no** music on that beat. Do not fill the gap. |
| `none` | skip |

`silenceOnReveal: true` on a beat overrides a program bed for that hold — compose ducks to true quiet. There is **no** separate SFX engine: `sfxCue` `whoosh` / `riser` / `impact-soft` / `accent` maps to a sting; `click` is Recast on `screen` beats; else sting. Specialist: `local-ai-stack` `references/music.md`.

Mix later with `Finish-Media.ps1 -Speech -Music` so the bed ducks. Do not mux an unducked bed.

## 4. Pictures the bible called for

For each `visual-bible.brollPlan` / `imagePrompts` row, run `ai.ps1 image` with that prompt. Honor `refuse` (never product UI, metrics, testimonials). Specialist: `references/image.md`.

Motif / lipsync / portrait **only** when `direction` called for that plate.

## 5. Commands

| Need | Command | Specialist |
| --- | --- | --- |
| Owner / clone TTS | `ai.ps1 voice qwen-clone --voice <id>` | `references/voice.md` |
| Role TTS | `ai.ps1 voice qwen-role` | `references/voice.md` |
| Identity gate | `ai.ps1 voice score --voice sarosh <wav>` | `references/voice.md` |
| Image / Visual Bank | `ai.ps1 image single` | `references/image.md` |
| Motif I2V | `ai.ps1 motif --reference <png> --prompt "…" --out <mp4>` | `references/video.md` |
| Lipsync | `ai.ps1 lipsync <video> --audio <wav>` | `references/video.md` |
| Portrait | `ai.ps1 portrait <image>` (specialty) | `references/video.md` |
| Music bed or sting | `ai.ps1 music <batch.json>` | `references/music.md` |
| Transcribe | `ai.ps1 transcribe <path>` | `references/voice.md` |
| Full-program listen | `ai.ps1 listen <encoded-media> --output <report.json>`; `--timeline` above 90s | `references/voice.md` |

## 6. Provenance

Write artifacts and any generation scripts/config only into the external job
workspace. Never copy generated plates, audio, prompts, model receipts, helper
code, or dependencies into a product repository. Bind path, bytes, and SHA-256
in a generation receipt keyed by beat id (voice, bed/sting, each B-roll still).
Assembly consumes that receipt — an unrecorded copy into `selected/` is not
provenance.

## 7. Final check

- [ ] Direction register used per beat
- [ ] Owner segments identity-scored
- [ ] Bed generated only if a beat asked for `bed`; stings are short; silence beats have no music file
- [ ] Bible B-roll generated with refuse honored
- [ ] Receipt binds every plate compose will mux
