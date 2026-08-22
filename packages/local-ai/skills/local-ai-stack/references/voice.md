# Local-AI voice (progressive load)

Load only when the task needs TTS, STT, voice identity, or voice corpus work.
Control plane remains `ai.ps1` / `$LocalAiControl`.

## Voice TTS — FROZEN (Qwen3-TTS only)

> **Qwen3-TTS is the only production TTS family. `faster-qwen3-tts` is the only
> Qwen inference backend. 0.6B Base = default clone; 1.7B Base = premium clone;
> 0.6B CustomVoice = generic presets; 1.7B CustomVoice = directed/`instruct`;
> VoiceDesign = create then enroll. Full ICL + cached prompts + hot CUDA graphs.
> Kokoro removed. Stock `qwen_tts` / `Qwen3TTSModel` production route disabled —
> no silent fallback.**

Authoritative disk policy (do not fork a second catalogue into AgentHub):

- `$LocalAiRoot\data\artifacts\media\voice-corpus\PRODUCTION-VOICE-POLICY.md`
- `$LocalAiRoot\data\artifacts\media\voice-corpus\VOICE-MAP.md`
- `$LocalAiRoot\data\artifacts\media\voice-corpus\library.json`
- `$LocalAiRoot\data\artifacts\media\voice-corpus\AGENTS.md`
- `$LocalAiRoot\data\artifacts\media\voice-corpus\PRONUNCIATION-RISK-POLICY.md`

Architecture:

```text
YOUR VOICE BANK → QWEN VOICE ROUTER
  → 0.6B Base Fast (DEFAULT clone) | 1.7B Base Fast (PREMIUM)
  → 0.6B CustomVoice Fast (DEFAULT role) | 1.7B CustomVoice Fast (instruct)
  → 1.7B VoiceDesign Fast (FACTORY only)
  → faster-qwen3-tts CUDA Graphs → RTX 5060 Ti
```

Do **not** add Docker, vLLM, Triton, or FlashAttention for TTS speed. Native
Windows CUDA venv (`runtimes\media\voice-qwen-fast`) only.

### STOP — first-class voices (celebrity names are style labels)

| Display name | Canonical id | Default render |
| --- | --- | --- |
| **Sarosh** | `sarosh` | 0.6B Base Fast (identity-gated) |
| **Morgan Freeman-style** | `narrator-calm-authoritative` | 0.6B Base Fast |
| **Matthew McConaughey-style** | `narrator-conversational-charismatic` | 0.6B Base Fast |
| **Michael Caine-style** | `narrator-deliberate-mentor` | 0.6B Base Fast |
| **David Attenborough-style** | `narrator-natural-history-documentary` | 0.6B Base Fast |
| Relaxed Storyteller | `narrator-relaxed-storyteller` | 0.6B Base Fast |
| Documentary Scholar | `narrator-documentary-scholar` | 0.6B Base Fast |
| Technical Instructor | `narrator-technical-instructor` | 0.6B Base Fast |
| Aiden / Ryan / Uncle_Fu / Vivian / Serena / Dylan / Eric / Ono_Anna / Sohee | `role-*` | 0.6B CV Fast |

Never invent a new clone because “Morgan Freeman isn’t a folder name.” Resolve
via `ai.ps1 catalog "Morgan"` / `library.json` aliases. Public copy: **“-style”**
persona — not an impersonation claim. Voice id is stable; model size is only the
renderer (`preferred_tier=premium` → 1.7B, same id).

Former Kokoro / `smoke-narrator` / `af_heart` → **`role-aiden`** (retired alias
with `redirect_to`). Do not call Kokoro.

### Router

1. Existing clone → `qwen-clone` 0.6B Fast → need premium? → `--premium` (1.7B)
2. Generic preset → `qwen-role` 0.6B CustomVoice Fast
3. Preset + acting/`--instruction` → 1.7B CustomVoice Fast (0.6B lacks full NL instruct)
4. Brand-new persona → `qwen` VoiceDesign Fast → approve → enroll → Base Fast thereafter

```powershell
& $LocalAiControl voice qwen-clone --voice narrator-calm-authoritative --text "…" --out out.wav
& $LocalAiControl voice qwen-clone --voice sarosh --premium --text "…" --out out.wav
& $LocalAiControl voice qwen-role --speaker Aiden --text "…" --out out.wav
& $LocalAiControl voice qwen-role --speaker Ryan --instruction "restrained anger, deliberate pace" --text "…" --out out.wav
```

**Invoke with the call operator, never `pwsh -File`.** `--out` prefix-matches
`-OutVariable`/`-OutBuffer`. From non-PowerShell, pass text through the
environment:

```powershell
pwsh -NoProfile -Command "& '<root>\ai.ps1' voice qwen-clone --voice $env:V --text $env:T --out $env:O"
```

If anything requests stock `qwen_tts` / slow backend:

```text
ERROR: Slow Qwen TTS backend disabled.
Use faster-qwen3-tts.
```

Fail → retry fast → new seed → escalate 0.6→1.7 Fast → STOP+LOG. Never silent
stock fallback. One bad WAV ≠ abandon the backend.

### Sarosh (identity-gated)

Expressiveness = style WAV + `.txt` from
`voices\sarosh\styles-20260815\` (default `02_explaining`) — **not** free-text
`instruct`. Profile locks `do_sample: false`. `reference.wav` is the identity
score anchor only.

```powershell
& $LocalAiControl voice qwen-clone --voice sarosh `
  --reference "<root>\data\artifacts\media\voice-corpus\voices\sarosh\styles-20260815\02_explaining.wav" `
  --ref-text "<sidecar txt>" --text "…" --out out.wav
& $LocalAiControl voice score --voice sarosh <file-or-dir>
```

Do not recreate Chatterbox / `sarosh-qwen` / x-vector-only / meeting-fine-tune
profiles. Do not fix pronunciation by respelling text (fails identity floor).

#### Pronunciation-risk contract

Every owner-voice batch requires a contextual pronunciation-risk manifest before
generation. Enumerate heteronyms, irregular spellings, noun/verb stress shifts,
proper nouns, loanwords, acronyms, initialisms, symbols, and domain terms by
stable segment and occurrence. Record meaning or part of speech, intended IPA,
spoken form, source text, and listening status. `resume` as a verb
(`/rɪˈzuːm/`) and résumé as a noun (`/ˈrɛzəmeɪ/`) are separate occurrences, as
are noun and verb senses of `record`.

The dictionary layer may guide a renderer, but canonical Sarosh input text must
not be phonetic-respelled. ASR verifies words; it cannot by itself approve
homophones, names, stress, or accent. Keep every pronunciation-risk occurrence
blocked until a human listening check verifies the intended sense and sound.

Reference inputs use a purpose-recorded style WAV plus its exact transcript:
mono, 24 kHz or higher, 16-bit or higher, matching language, at least 60 percent
speech density, no unexplained pause longer than two seconds, and immutable
hashes. Prefer 10–15 seconds, while allowing a shorter measured reference only
when existing identity evidence passes. Generate immutable semantic sentence,
breath, or scene chunks—not arbitrary character blocks. Keep punctuation
restrained, never time-stretch speech, never dynamically compress an individual
take, and detect rather than blindly trim tail artifacts. A final program master
may use gain plus a transparent true-peak limiter; it still requires listening,
caption synchronization, loudness, true-peak, ASR/content, and both identity
backends to pass.

### Ops

- Full **ICL** for enrolled clones (ref WAV + exact transcript). x-vector only
  with an explicit reason.
- Cache clone prompts once per process; keep the model hot (warmup / CUDA graphs
  once; no per-line reload).
- Offline/episode: **non-streaming**; group jobs by model then voice. Resident
  default = 0.6B Base; load other variants for grouped jobs.
- Live UI: stream chunk ≈ 4–8.
- Advanced sampling (`temperature`, `top_k`, …) under Advanced only — don’t
  randomize per line; use 1.7B CV `instruct` for acting.
- Languages (Qwen): Chinese, English, Japanese, Korean, German, French, Russian,
  Portuguese, Spanish, Italian.

### Specialty engines

`voice.voxcpm2`, `voice.indextts25`, `voice.bestof`, `voice.performance` remain
specialty — not production defaults. Do not expand the production TTS family
unless Qwen fails a measured requirement.

### Building or extending the owner voice corpus

Training and reference material is assembled by the refinery, never by hand:

```powershell
& $LocalAiControl corpus <sources|ingest|map|calibrate|select|transcribe|classify|report>
```

Source audio is read-only. Path denylist fails closed. Mined pools cannot reach
Gold without provenance. New VoiceDesign personas: generate once → enroll into
`library.json` with aliases → produce with Base clone thereafter.
