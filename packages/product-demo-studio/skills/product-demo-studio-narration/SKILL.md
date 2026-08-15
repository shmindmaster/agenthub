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
available, use the canonical Local-AI route only:

```powershell
D:\Local-AI\ai.ps1 voice qwen-clone --voice sarosh --text "..." --out <segment.wav>
```

Invoke it with the PowerShell call operator, never `pwsh -File`: `ai.ps1` is an
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

If a segment says Sarosh, keep the listening gate as well — the identity score
measures *who* is speaking, not whether the name was pronounced correctly, and
those fail independently. Do not try to fix pronunciation by respelling the
text: of five orthography variants measured, phonetic respelling was the only
one to fail the identity floor on both backends.
