---
name: elevenlabs-tts
description: Generate ElevenLabs text-to-speech audio through the shared environment-backed CLI.
---

# ElevenLabs TTS

Use `scripts/elevenlabs_cli.py tts --text ... --output ...` for explicit audio
generation. The command requires a voice ID from `ELEVENLABS_VOICE_ID` or an
explicit `--voice-id`, and chooses `ELEVENLABS_MODEL_TTS_DEFAULT` unless the
caller supplies `--model-id`.

Confirm the requested output path and format before generating media. Health and
voice-list calls are read-only; TTS consumes account quota and should only run
when the user asks for audio.
