---
name: media-studio-generate
description: Use when a video or audio job needs local generation — owner or role voice, images, motif clips, lipsync, portrait, music beds, or transcription — through the Local-AI control plane.
---

# Media studio generate

Load `local-ai-stack` first and resolve `$LocalAiControl`. For hour-scale batches also load `long-running-generation`. One heavy GPU job at a time.

Load `../media-studio/references/engagement.md` (Generate / compose / QA own) for plate choice.

**TTS always.** Viewer-facing jobs also generate the directed music (`musicCue: bed` or `sting`) unless `intent: draft` or `music: none`. Do not start Comfy, Motif, lipsync, or portrait unless the director called for that plate.

Owner voice is local-only. Never ElevenLabs or another hosted TTS for Sarosh.

```powershell
& $LocalAiControl status
& $LocalAiControl check
```

Start only the route you need (`voice`, `media` / Comfy, `music`). Do not start Comfy for TTS or music.

| Need | Command | Specialist |
| --- | --- | --- |
| Owner / clone TTS | `ai.ps1 voice qwen-clone --voice <id>` | `references/voice.md` |
| Role TTS | `ai.ps1 voice qwen-role` | `references/voice.md` |
| Identity gate | `ai.ps1 voice score --voice sarosh <wav>` | `references/voice.md` |
| Image / Visual Bank | `ai.ps1 image single` | `references/image.md` |
| Motif I2V | `ai.ps1 motif --reference <png> --prompt "…" --out <mp4>` | `references/video.md` |
| Lipsync | `ai.ps1 lipsync <video> --audio <wav>` | `references/video.md` |
| Portrait | `ai.ps1 portrait <image>` (specialty) | `references/video.md` |
| Music bed | `ai.ps1 music <batch.json>` | `references/music.md` |
| Transcribe | `ai.ps1 transcribe <path>` | `references/voice.md` |
| Full-program listen | `ai.ps1 listen <encoded-media> --output <report.json>`; add `--timeline <timeline.json>` above 90 seconds | `references/voice.md` |

Score every owner-voice segment before it is composed. Do not respell input to fix pronunciation.

Write artifacts into the job workspace. Bind path, bytes, and SHA-256 in a generation receipt. Assembly consumes that receipt — an unrecorded copy into `selected/` is not provenance.
