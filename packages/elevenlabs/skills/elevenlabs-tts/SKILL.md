---
name: elevenlabs-tts
description: Use when approved text needs ElevenLabs speech generation, voice selection, pronunciation control, or segment-level regeneration.
---

# ElevenLabs TTS

Use `scripts/elevenlabs_cli.py tts --text ... --output ...` for explicit audio
generation. The command requires a voice ID from `ELEVENLABS_VOICE_ID` or an
explicit `--voice-id`, and chooses `ELEVENLABS_MODEL_TTS_DEFAULT` unless the
caller supplies `--model-id`.

Product-video callers may also supply the reviewed prerecorded-narration controls:
`--stability`, `--similarity-boost`, `--style`, `--speed`,
`--use-speaker-boost`/`--no-use-speaker-boost`, `--text-normalization`, and
`--previous-text`/`--next-text`. The shared CLI owns the provider request and
authentication; downstream capabilities own only their segment, timing, checksum, and
composition orchestration.

Confirm the requested output path and format before generating media. Health and
voice-list calls are read-only; TTS consumes account quota and should only run
when the user asks for audio.
