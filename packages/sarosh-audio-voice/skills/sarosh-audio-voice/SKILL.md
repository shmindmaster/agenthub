---
name: sarosh-audio-voice
description: Use when Sarosh's spoken voice is needed — a Sarosh voice clone, owner TTS, generated speech in his voice, narration or voice-over delivery, spoken style or delivery, pronunciation of his narration, or a speaker-identity check on his output.
---

# Sarosh Audio Voice

This skill is the audio voice: voice cloning, TTS, generated speech, and
spoken delivery style for Sarosh Hussain. Written tone, style, and structure
are `sarosh-communication`. Do not apply either skill's rules to the other —
a written draft does not need an identity gate, and a voice render does not
need the Bottom Line → Impact → Action framework.

Full command reference: `local-ai-stack` skill,
`references/voice.md`. This skill states the fleet-wide rules; load that
reference for the actual `ai.ps1` invocations, model tiers, and corpus
workflow.

## 1. Local-only, one engine family

Owner voice is a local capability, routed through the Local-AI control plane
(`ai.ps1` / `$LocalAiControl`) only, voice id **`sarosh`**. Never generate or
approximate this speaker through a hosted TTS provider (ElevenLabs or any
other) — a cloud provider cannot produce that speaker and returns a different
one that merely sounds professional. `elevenlabs-tts` enforces the same
boundary from its side: for Sarosh's voice it stops and redirects here.

Production TTS is Qwen3-TTS only (`faster-qwen3-tts` backend). Do not recreate
Chatterbox, `sarosh-qwen`, x-vector-only, or meeting-fine-tune profiles.

```powershell
& $LocalAiControl voice qwen-clone --voice sarosh --premium --text "…" --out out.wav
```

## 2. Never training data, never sent externally without approval

Owner-voice audio, and any corpus derived from it, is not training data for an
external service and is not transmitted for benchmarking. Comparing against a
hosted provider sends only benchmark *text*, and needs the same explicit
approval as any other outbound transmission.

## 3. Speaker-identity gate is mandatory, expression is not

Every owner-voice generation passes a speaker-identity gate before it is
delivered, embedded in a video, or sent to anyone. Identity is measured
against Sarosh's own recordings, not assumed from the fact that the correct
route was used:

```powershell
& $LocalAiControl voice score --voice sarosh <file-or-dir>
```

Expression, emotion, and pacing are adjustable within that constraint —
select the style-bank register (`explaining`, `firm`, `serious`, …) from the
`styles-20260815` bank, default `02_explaining` — never free-text "sound
excited" instructions for this speaker. Speaker identity is the fixed
constraint everything else is adjusted within:

```powershell
& $LocalAiControl voice qwen-clone --voice sarosh `
  --reference "<root>\data\artifacts\media\voice-corpus\voices\sarosh\styles-20260815\02_explaining.wav" `
  --ref-text "<sidecar txt>" --text "…" --out out.wav
```

## 4. Pronunciation is a render-time dictionary, not a text edit

Do not correct pronunciation by respelling input text — it measurably
degrades speaker identity. Pronunciation is a dictionary layer applied at
render time and shared across engines. Canonical input text stays as written;
fix mispronunciation through the pronunciation-risk dictionary, not the
script.

## 5. Legacy engine note — Chatterbox `cfg_weight`

Historical fact, kept for reference only; current production is Qwen3-TTS
(§1), not Chatterbox. If Chatterbox is ever revisited: `cfg_weight` must stay
at its 0.5 default for voice cloning. Lowering it to 0.2–0.3 makes the output
sound like a different person, and it does **not** control speaking pace
despite being documented as if it did — a measured ladder across 0.2–0.5
produced no trend. If output pace needs to change, time-stretch the rendered
audio (formants preserved); never lower `cfg_weight`/`exaggeration` or change
the training data to do it.

## 6. Not a media pipeline

This skill covers the voice render itself, not the finished piece. Video,
screencast, and multi-asset assembly stay with `media-studio`. A long
generation batch (hours, many WAVs) loads `long-running-generation` for job
submission, monitoring, and resume rather than blocking inline.

## 7. Scope split

This skill is the audio voice. Written tone, style, and structure — email,
Slack, Teams, customer messages, status updates, proposals — are
`sarosh-communication`. Load both when a deliverable has both a script and a
spoken render, but keep their rules separate: `sarosh-communication` never
governs identity gating or pronunciation, and this skill never governs
sentence structure or compression.
