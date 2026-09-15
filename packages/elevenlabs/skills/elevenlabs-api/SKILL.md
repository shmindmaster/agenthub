---
name: elevenlabs-api
description: Use when a repository needs direct ElevenLabs API access or provider-level voice and media operations beyond the focused STT and TTS skills.
---

# ElevenLabs API

Use `ELEVENLABS_API_KEY` from the user environment. Never print, copy, or ask
the user to paste its value. Prefer the bundled CLI for health, voice discovery,
and TTS operations.

Keep integrations provider-neutral: callers may be creative, product, voice,
video, telephony, or agent projects. Do not hard-code a repository name, voice
ID, model, or output directory when an environment override or explicit prompt
provides one.
