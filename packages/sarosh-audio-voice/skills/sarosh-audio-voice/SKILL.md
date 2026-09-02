---
name: sarosh-audio-voice
description: Use when Sarosh's spoken voice is needed — a Sarosh voice clone, owner TTS, generated speech in his voice, narration or voice-over delivery, spoken style or delivery, pronunciation of his narration, or a speaker-identity check on his output.
---

# Sarosh Audio Voice

## 1. Objective

Create spoken delivery that is recognizably Sarosh, emotionally appropriate,
intelligible, professionally mastered, and proven against the exact artifact
the listener will receive.

Optimize in this order:

1. **Speaker identity**
2. **Content accuracy**
3. **Intelligibility**
4. **Natural delivery**
5. **Technical quality**
6. **Emotional direction**

The governing rule:

> **Expression may change; speaker identity may not.**

## 2. Scope and routing

This skill is the audio voice: voice cloning, TTS, generated speech, and
spoken delivery style for Sarosh Hussain. `sarosh-writing` governs the
canonical script. `sarosh-communication` governs the concise handoff message.
Do not apply one layer's rules to another: a written draft does not need an
identity gate, and a voice render does not need the Bottom Line → Impact →
Action framework.

Full command reference: `local-ai-stack` skill,
`references/voice.md`. This skill states the fleet-wide rules; load that
reference for the actual `ai.ps1` invocations, model tiers, and corpus
workflow. For video, podcast, or multi-asset production also load
`media-studio`. For hours-long or many-file batches load
`long-running-generation`.

## 3. Local-only, one engine family

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

## 4. Never training data, never sent externally without approval

Owner-voice audio, and any corpus derived from it, is not training data for an
external service and is not transmitted for benchmarking. Comparing against a
hosted provider sends only benchmark *text*, and needs the same explicit
approval as any other outbound transmission.

## 5. Speaker-identity gate is mandatory, expression is not

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

Prefer:

`Use the accepted firm reference and leave a deliberate pause before the conclusion.`

Avoid:

`Make it sound like an excited celebrity narrator.`

```powershell
& $LocalAiControl voice qwen-clone --voice sarosh `
  --reference "<root>\data\artifacts\media\voice-corpus\voices\sarosh\styles-20260815\02_explaining.wav" `
  --ref-text "<sidecar txt>" --text "…" --out out.wav
```

## 6. Pronunciation is a render-time dictionary, not a text edit

Do not correct pronunciation by respelling input text — it measurably
degrades speaker identity. Pronunciation is a dictionary layer applied at
render time and shared across engines. Canonical input text stays as written;
fix mispronunciation through the pronunciation-risk dictionary, not the
script.

## 7. Prove the exact delivery artifact

Lock canonical text with stable segment IDs and create a contextual
pronunciation-risk manifest before generation. Preserve a receipt for every
selected take: script, voice id, model and checkpoint hashes, renderer,
sampling, reference WAV and transcript hashes, output bytes, and SHA-256.

Source proof is necessary but not sufficient:

1. score every selected source segment with both enrolled identity backends;
2. transcribe mastered narration against the locked script;
3. decode the exact mixed and encoded delivery artifact;
4. score its scene-aligned voice spans again;
5. transcribe the decoded delivery audio and compare it to the script;
6. adjudicate every pronunciation-risk occurrence;
7. run full-program `ai.ps1 listen` with contiguous sample coverage;
8. validate loudness, true peak, clipping, silence, synchronization, captions,
   and artifacts against the production brief.

For music-backed programs, the voice is the anchor. Use side-chain ducking,
automation, and deliberate silence so the score does not mask consonants,
names, numbers, or identity features. If source segments pass and encoded
spans fail, remediate the mix or encode; do not waive the identity gate.

An automated listening report is local model perception, not proof that Sarosh
or another human listened.

## 8. Not a media pipeline

This skill covers the voice render itself, not the finished piece. Video,
screencast, and multi-asset assembly stay with `media-studio`. A long
generation batch (hours, many WAVs) loads `long-running-generation` for job
submission, monitoring, and resume rather than blocking inline.

## 9. Written, long-form, and audio boundary

Concise written interaction—email, Slack, Teams, customer messages, status
updates—is `sarosh-communication`. Substantial proposals, presentations,
articles, reports, and narration scripts are `sarosh-writing`. Load all
applicable layers when a deliverable has both a script and a spoken render,
but keep their responsibilities separate.

## 10. Failure handling and release state

Classify a failed segment as identity, pronunciation, content, pacing,
discontinuity, technical integrity, or mix masking. Change the smallest
relevant variable, retry the approved local fast backend, then try a new seed
or accepted style reference, and escalate from 0.6B to premium 1.7B when
warranted. Stop and record the failure instead of using another speaker,
hosted fallback, stock slow backend, or unapproved clone.

Keep these states distinct:

`generated` → `source-identity-passed` → `assembled` → `mastered` →
`exact-encoded-QA-passed` → `private-viewing-ready` → `owner-reviewed` →
`owner-approved` → `externally released`

Only Sarosh's own review establishes owner approval.

## 11. Final check

Before delivering owner-voice audio, verify:

1. Canonical script text did not change during rendering.
2. Every pronunciation-risk occurrence is adjudicated.
3. Every selected source segment passed both identity backends.
4. Exact encoded scene spans passed identity again.
5. Source and encoded ASR match the locked script.
6. Full-program listening covers the complete decoded stream.
7. Loudness, peak, channel, sync, captions, and artifact checks pass.
8. Receipts bind the actual delivered bytes.
9. No owner data or audio left the machine.
10. Owner approval is reported only if Sarosh actually gave it.
