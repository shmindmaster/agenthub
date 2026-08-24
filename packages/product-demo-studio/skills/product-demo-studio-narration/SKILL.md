---
name: product-demo-studio-narration
description: Use when an approved product-video script needs voiceover, text-to-speech, timing metadata, pronunciation control, or segment-level regeneration.
---

# Product Demo Narration

Narration explains viewer value without racing the interface or claiming more than the evidence supports.

## Contract

1. Lock the storyboard, claim IDs, pronunciation notes, voice, provider, and disclosure requirements before generation.
2. Write short spoken sentences around one problem, one hero moment, the visible result, a trust/control beat, and one next step. Prefer plain language to feature enumeration.
3. Time each beat as `pointer lead → real action → visible feedback → result hold → spoken interpretation`. Never speak the result before it is visible.
4. Generate by stable segment ID so one correction does not regenerate the whole track. Preserve text, provider/model, voice, settings, duration, timestamps, and hashes.
5. Normalize gently; do not hide clipped speech, bad pronunciation, room noise, or pacing defects with aggressive processing.
6. Produce captions from the final spoken wording, then verify words, timing, line breaks, safe area, and readability against the exact candidate.

Use `../../scripts/generate-narration.mjs` for the canonical segment workflow. OpenAI is the minimal external-workspace dependency; ElevenLabs is optional through the shared ElevenLabs capability. Sensitive or privileged audio remains local-first.

When the narration is explicitly Sarosh's voice and the local stack is
available, use the canonical Local-AI route only (see `local-ai-stack`):

```powershell
D:\Local-AI\ai.ps1 voice qwen-clone --voice sarosh `
  --reference "D:\Local-AI\data\artifacts\media\voice-corpus\voices\sarosh\styles-20260815\02_explaining.wav" `
  --ref-text "<sidecar txt contents>" --text "..." --out <segment.wav>
```

Default clone is **0.6B Base + faster-qwen3-tts**; add `--premium` for 1.7B.
Expressiveness = style WAV, not free-text mood. Identity-gate before ship.
Celebrity-style narrators (Morgan Freeman-style → `narrator-calm-authoritative`,
etc.) are first-class enrolled clones — resolve via `ai.ps1 catalog` / the
`local-ai-stack` voice bank; never invent new clones or call Kokoro.

Invoke with the PowerShell call operator, never `pwsh -File`: `ai.ps1` is an
advanced script, so `--out` prefix-matches `-OutVariable`/`-OutBuffer` and the
script aborts with "the parameter name 'out' is ambiguous" before it runs. From
Node or any non-PowerShell caller, use `scripts/generate-narration.mjs`
(`--provider local`), which already handles this and passes text through the
environment so quotes cannot break the command.

Do not use or recreate Chatterbox Sarosh profiles, `sarosh-qwen`, x-vector-only
cloning, meeting/singing profiles, shootout baselines, or loose Sarosh
references. Preserve the canonical profile settings and validate each final
segment for words, pacing, pronunciation, identity, duration, and hash.

**Score every owner-voice segment before it ships:**

```powershell
D:\Local-AI\ai.ps1 voice score --voice sarosh <segment-or-dir>
```

It returns two independent speaker embeddings and exits non-zero if either
falls below a floor derived from the owner's own recordings. This is not
optional: retro-scoring 148 already-delivered brief segments found 6 below the
floor, one at less than half of it, in audio that had already gone out.

If a segment says Sarosh, keep the system-owned full-candidate listening gate as well — the identity score
measures *who* is speaking, not whether the name was pronounced correctly, and
those fail independently. Do not try to fix pronunciation by respelling the
text: of five orthography variants measured, phonetic respelling was the only
one to fail the identity floor on both backends.

## Owner-voice pronunciation and mastering gate

Before generating an owner-voice batch, create a pronunciation-risk manifest
that enumerates every occurrence of a heteronym, irregular spelling, stress
shift, proper noun, loanword, acronym, initialism, symbol, and domain term. A
heteronym entry must bind the exact segment and surrounding text to its meaning,
part of speech, intended IPA, and spoken form. For example, `resume` as a verb is
`/rɪˈzuːm/`, while résumé as a noun is `/ˈrɛzəmeɪ/`; `record` and `records` also
need their noun-or-verb sense recorded. The spoken form is review evidence, not
permission to mutate the canonical script.

Owner-voice input text stays canonical. Apply approved pronunciation handling
through the shared Local-AI dictionary layer at render time; never phonetic-
respell Sarosh's input. ASR is a content check, not a complete pronunciation
oracle: homophones, proper nouns, stress, and accent can pass ASR while sounding
wrong. Every risk occurrence therefore remains blocked until the orchestrator or isolated audio
reviewer records pass or fail against the intended meaning and pronunciation. This is a listening
requirement, not a recurring owner-approval dependency.

Use full ICL with the purpose-recorded style WAV and its exact sidecar transcript.
Validate references as mono WAV at 24 kHz or higher and 16-bit or higher, with at
least 60 percent speech density, no unexplained gap over two seconds, matching
language, and immutable hashes. Prefer 10–15 seconds when a validated style
reference exists; a shorter purpose-recorded reference may be used only when its
identity and delivery evidence already pass.

Generate immutable attempts in semantic sentence, breath, or scene-beat chunks;
do not split on an arbitrary character count. Use restrained punctuation to
shape natural pauses, never punctuation clutter to force acting. Regenerate only
the failed stable segment, never time-stretch speech, and do not dynamically
compress individual TTS takes. Detect clipped words, echoed reference tails, and
abrupt endings; do not blindly trim a fixed tail duration. The final program mix
may use gain plus a transparent true-peak limiter to meet delivery loudness, but
the exact mastered candidate must pass listening, caption timing, integrated
loudness, true peak, ASR/content, and both speaker-identity backends.

Do not accept a route name as generation provenance. Record the resolved local
checkpoint and config hash, `base`/`1b7`/12 Hz model identity, backend, language,
ICL and sampling settings, canonical and rendered text, reference audio and
transcript hashes, output hash, and exact selected attempt for every stable
segment. Assembly must consume a hash-bound selection ledger; an unrecorded copy
into a `selected` folder is a release failure.

Run ASR twice at the program boundary: once on the exact mastered narration WAV
and once on audio extracted from the exact encoded delivery video. Bind every
ASR result to the source path, byte count, and SHA-256, then compare both with
the locked script. A transcript that does not name and hash its audio source is
stale by default. The candidate listening artifact is the
`../../schemas/candidate-listening-receipt.schema.json` record for full continuous playback of the
encoded candidate. It binds the exact candidate path, SHA-256, byte count, source revision, render
provenance, and ffprobe duration. A discontinuous pronunciation excerpt reel is only
supplemental and must be labeled `DISCONTINUOUS EXCERPTS`; never use it as the
sole approval file.
