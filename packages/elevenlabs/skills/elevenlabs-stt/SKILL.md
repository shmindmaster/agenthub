---
name: elevenlabs-stt
description: Use when assessing hosted transcription eligibility; paid transcription is disabled pending a metered shared adapter.
---

# ElevenLabs transcription

Hosted transcription currently fails closed. The canonical
`packages/elevenlabs/scripts/elevenlabs_cli.py` refuses `transcribe` before an
upload. Native tools, SDK examples and Flows must not bypass the shared budget.
A duration/model quote, atomic reservation, durable receipt and recovery adapter
are required before enabling this modality. Load `elevenlabs-api` and
`packages/media-studio/skills/media-studio/references/content-controls.md`.

Use an authorized local transcription route meanwhile. Legal, privileged,
confidential and evidence media stay local by default. Never upload originals
from protected drives or derived protected material. Owner-voice alignment and
word checks remain local. Cloud approval alone does not enable this paid route.

Preserve originals and provenance. For a TTS word gate, compare normalized ASR
against approved text, require a normalized word error rate at or below 0.15
and all key terms/numbers, and retain the exact output hash and evidence.
Normalize both texts identically: lowercase, remove bracketed audio tags and
punctuation, and collapse whitespace. A word pass is not a speaker-identity pass. Do not regenerate
passing audio merely to rerun a local check.

Endpoint reference for future adapter work:
https://elevenlabs.io/docs/api-reference/speech-to-text/convert.
