---
name: elevenlabs-stt
description: Transcribe non-privileged audio with ElevenLabs Speech-to-Text while preserving a strict local-first policy for privileged, legal, discovery, or sensitive media.
---

# ElevenLabs Speech-to-Text

Use this capability only for audio the user has approved for cloud transcription. Read `ELEVENLABS_API_KEY` from the environment and never print, copy, or request its value.

## Data boundary

- Treat legal, discovery, privileged, confidential, or evidence media as local-only by default.
- Do not upload originals from `G:\` or derived content that could reveal protected material to a cloud transcription provider.
- For privileged media, use an approved local transcription workflow and preserve the original and provenance metadata.
- For non-sensitive media, obtain the input path and output destination explicitly, retain timestamps/speaker metadata when available, and write a sidecar provenance record.

## Integration

Keep this skill provider-specific but repository-neutral. It may feed a transcript into an existing knowledge or discovery ingestion workflow only after the user approves the data boundary. Do not hard-code a model, language, repository, or evidence path.

For an approved, non-sensitive local file, use the bundled CLI:

```powershell
python scripts/elevenlabs_cli.py transcribe --input <file> --output <transcript.json> --approve-cloud
```

The command refuses `G:\` inputs, requires explicit cloud approval, defaults to `scribe_v2`, and creates a hash-based provenance sidecar next to the transcript. It never accepts remote `source_url` input.
