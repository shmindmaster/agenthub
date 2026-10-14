---
name: elevenlabs-stt
description: Use when non-privileged audio needs ElevenLabs transcription, or rendered TTS needs a word-accuracy gate, and the material is confirmed suitable for an external provider.
---

# ElevenLabs Speech-to-Text

The CLI lives at `C:/Repos/shmindmaster/agenthub/packages/elevenlabs/scripts/elevenlabs_cli.py`
(or under `$env:AGENTHUB_ROOT`). Loose-skill installs do not ship `scripts/`,
so call it by that path.

Use this capability only for audio the user has approved for cloud transcription. Read `ELEVENLABS_API_KEY` from the environment and never print, copy, or request its value.

## Data boundary

- Treat legal, discovery, privileged, confidential, or evidence media as local-only by default.
- Do not upload originals from `G:\` or derived content that could reveal protected material to a cloud transcription provider.
- For privileged media, use an approved local transcription workflow and preserve the original and provenance metadata.
- For non-sensitive media, obtain the input path and output destination explicitly, retain timestamps/speaker metadata when available, and write a sidecar provenance record.
- Owner-voice audio is not uploaded for transcription or alignment. Align and gate it locally.

## Integration

Keep this skill provider-specific but repository-neutral. It may feed a transcript into an existing knowledge or discovery ingestion workflow only after the user approves the data boundary. Do not hard-code a model, language, repository, or evidence path.

For an approved, non-sensitive local file, use the bundled CLI:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli transcribe --input <file> --output <transcript.json> --approve-cloud
```

The command refuses `G:\` inputs, requires explicit cloud approval, defaults to `scribe_v2`, and creates a hash-based provenance sidecar next to the transcript. It never accepts remote `source_url` input.

## Models and related endpoints (checked 2026-10-13)

- `scribe_v2` is verified on the fleet account and is the default. Fall back to
  `scribe_v1` only if `scribe_v2` is unavailable; the models page marks it
  deprecated. Transcripts include audio-event tags such as `[chuckles]`, which
  is useful for checking that a v4 audio tag landed.
- `scribe_v2_realtime` (about 150 ms) and `scribe_v2_medical` exist with the
  same API (docs-only). Agents use ASR provider `scribe_realtime` by default.
  Pricing is about $0.22/hour batch and $0.39/hour realtime, plus keyterm
  prompting.
- Useful request fields: `keyterms` (up to 1,000 terms to bias recognition of
  names and product terms), `no_verbatim` (drops fillers; `scribe_v2` only),
  `diarize` / `num_speakers`, `timestamps_granularity`, `transcript_edit`
  (natural-language edit, about 30% surcharge).
  https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- Forced alignment (`POST /v1/forced-alignment` with `file` and the plain
  `text`) returns word timings for a known script: ≤3 GB, ≤10 h, ≤675k chars,
  no diarization (docs-only). Use it for captions on hosted-voice audio.
- Docs list STT concurrency 20 on Creator. Honour 429s with backoff.

## TTS word-accuracy gate

For rendered non-owner TTS, transcribe each new line with `scribe_v2` and pass
it only when both hold:

1. Normalised WER is at or below 0.15. Normalise reference and hypothesis the
   same way: lowercase, strip bracketed audio tags and punctuation, collapse
   whitespace.
2. Every key term in the line (names, product terms, numbers) appears in the
   transcript.

Cache the transcript next to the render under the same content hash. Never
re-transcribe or re-render a line that already passed. Re-render only the
failures. This gate checks words, not speaker identity.
