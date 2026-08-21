---
name: elevenlabs-tts
description: Use when approved text needs ElevenLabs speech generation, voice selection, pronunciation control, or segment-level regeneration.
---

# ElevenLabs TTS

## Check first: is this the owner's own voice?

If the requested narration is Sarosh's voice, **stop and use the local route
instead**. That voice is a local capability with an enrolled speaker profile and
an identity gate; ElevenLabs cannot produce it and will return a different
speaker that merely sounds professional.

```powershell
& '<LOCAL_AI_ROOT>\ai.ps1' voice qwen-clone --voice sarosh --text "..." --out <out.wav>
```

Sarosh moods use the `styles-20260815` style-bank WAVs (not ElevenLabs and not
free-text mood prompts). See the `local-ai-stack` skill for the full Qwen-only
playbook (0.6B Fast default, `--premium` for 1.7B, celebrity-style narrator ids,
mandatory identity gate, call-operator invocation). This mirrors the boundary
`elevenlabs-stt` already enforces for privileged media: some audio belongs on
this machine and nowhere else.

ElevenLabs remains correct for non-owner voices, for stock/character narration,
and for an explicitly requested benchmark comparison against the local engine.
A benchmark run sends the benchmark text to an external provider, so it needs
the same explicit approval any other outbound transmission does.

## Generating

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
