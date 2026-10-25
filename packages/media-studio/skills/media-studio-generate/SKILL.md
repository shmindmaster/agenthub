---
name: media-studio-generate
description: Use when a video or audio job needs provider-routed generation — owner or role voice, images, motif clips, lipsync, portrait, music beds, stings, or transcription — through ElevenLabs or the Local-AI control plane.
---

# Media studio generate

Choose by cost, latency, quality, privacy. Reuse accepted assets first. Load `elevenlabs` (its `SKILL.md` and `references/cost-controls.md`) and `../media-studio/references/content-controls.md` before paid planning. Paid ElevenLabs TTS requires its shared governed CLI; unsupported paid modalities remain disabled. Native connectors and SDK examples must not bypass the ledger. Otherwise use adequate authorized local generation. Load `local-ai-stack`; resolve `$LocalAiControl`. Hour-scale batches also load `long-running-generation`. One heavy GPU job at a time.

Load `../media-studio/references/engagement.md`. Viewer-facing jobs consume **locked** `storyboard.json`, `visual-bible.json`, `direction.json`. Do not invent plates the director did not call.

Owner speech loads `sarosh-audio-voice`: local eligible when adequate; approved hosted clone permitted when ready and worth its cost. Both require identity gates. No new private recordings, clone replacement, or verification implied.

```powershell
& $LocalAiControl status
& $LocalAiControl check
```

Start only the needed route (`voice`, `media`/Comfy, `music`). Do not start Comfy for TTS or music. Skip a beat whose selected take matches the locked narration hash. Do not rerun the whole job for one scene.

## 1. Inputs

| File | Required when |
|---|---|
| `narration.md` / screenplay | always |
| `direction.json` | viewer-facing: register, duration, plates per beat |
| `storyboard.json` | viewer-facing: `sound`, `shotPlan`, silence windows |
| `visual-bible.json` | viewer-facing B-roll / motif |

Missing required file → remit. Do not generate a generic bed and skip the bible.

## 2. Voice

Hosted: use `elevenlabs` (`references/tts.md`). Lock segments, check credits/clone/model readiness and budgets; reuse accepted matching preview or generate one small preview. Save provider receipts under job workspace; run local integrity, ASR, pronunciation, and dual-backend identity gates before selecting owner takes. Decode and gate exact delivery spans again. `Generate-OwnerVoice.ps1` implements the **local backend only**; its receipt format is not a hosted adapter—never fabricate PASS receipts for hosted audio. If assembly requires local receipts, keep that path local until a verified provider receipt adapter exists; report the limitation.

Local viewer-facing speech uses AgentHub-deployed shared tools. `plugin.json` must match 2.0.18. Missing or stale tools block generation until AgentHub syncs from a verified 2.0.18 package; do not default to unknown version.

```powershell
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\_shared\tools'
$manifest = Join-Path $tools 'plugin.json'
$generator = Join-Path $tools 'Generate-OwnerVoice.ps1'
$integrity = Join-Path $tools 'Test-SpeechIntegrity.ps1'
if (-not (Test-Path -LiteralPath $manifest) -or (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).version -ne '2.0.18' -or -not (Test-Path -LiteralPath $generator) -or -not (Test-Path -LiteralPath $integrity)) {
    throw 'Media Studio 2.0.18 voice tools are missing or stale. Deploy them from a verified package before generation.'
}
& pwsh -NoProfile -File $generator -Job $Job
```

Fail-closed pipeline: allowlisted style only (default `02_explaining` from `_identity_probe.json`) → integrity → `ai.ps1 transcribe` (Qwen3-ASR-1.7B) → dual-backend identity → retry → seed → `--premium` → STOP+LOG. Selection ledger before scene concat. Role voices (`ryan`/`vivian`/`aiden`/`joel` from scene `speaker`) get integrity + ASR only, no identity gate.

STOP+LOG from ASR misreading digits already in narration (identity passed): run `pwsh -NoProfile -File (Join-Path $tools 'ReGate-OwnerVoice.ps1') -Job $Job` after the same version check. It re-scores existing `take.wav` with number-normalized WER and looser integrity, writes fresh `PASS.json`—never re-synthesizes.

Script reads narration and `speaker` from `screenplay.json`; it does not parse `storyboard.json` or `visual-bible.json`. **Known gap:** renders whole job on default style, not per-beat `direction.register`. If a beat's register meaningfully differs, generate manually—`ai.ps1 voice qwen-clone --voice sarosh --reference <register-style.wav> --ref-text <sidecar> --text "…"`, gated through `Test-SpeechIntegrity.ps1` and `ai.ps1 voice score --voice sarosh`—splice into `voice/selected/` before scene concat. Do not claim register honored unless done by hand.

**Banned:** inventing style IDs; using `03_firm`/others until allowlisted; GGUF talker/ASR forks; phonetic-respelling Sarosh input; assembling identity/ASR-failing segments.

Pronunciation gate: before audio, runs `ai.ps1 voice pronunciation-risk`, writes `qa/pronunciation-risk.json` (heteronyms with POS reading per occurrence, stress-shift terms, names, acronyms, codes, symbols). Unresolvable heteronym stops run (`coverage.status: FAIL`); fix with `-PronunciationOverrides <json>` or reword. Pass lexicon via `-PronunciationLexicon` (ABACare: `skills/media-studio-capture/references/abacare-lexicon.json`). After integrity/ASR/identity pass, per-scene `ai.ps1 listen` on concatenated audio with canonical transcript and manifest slice; findings regenerate localized segment with new seed, listens again (`-ListenMaxRounds`, default 2), then STOP+LOG. `qa/pronunciation-listen.json` and ledger record reports by sha256. Extend `pronunciations.json` for recurring failures; never respell canonical narration.

Honor `pauseBeforeSeconds`/`holdAfterSeconds` as edit silence, not padded TTS. Mix with `Finish-BriefingStems.ps1` (speech-only loudnorm)—never `-AllowDynamic` on TTS. `Finish-Media.ps1` deployed beside it. Local Qwen3 stems land near −21.5 LUFS, peaks ~−1.6 dBTP, PLR ~19 dB; bare linear pass to −16 LUFS/−1.5 dBTP impossible, `Finish-Media.ps1` refuses dynamic fallback. Every finish path preconditions speech: fixed gain + true-peak limiter (`alimiter=limit=0.8413:attack=5:release=50:level=disabled`), then two-pass linear loudnorm; pass `-LoudnessRange 11` when only LRA blocks linear pass.

## 3. Music and silence

Viewer-facing jobs generate the directed `musicCue: bed` unless `intent: draft` or `music: none`.

| `sound.musicCue` | Generate |
|---|---|
| `bed` | accepted bed or local `ai.ps1 music`; paid cloud disabled pending metered adapter |
| `sting` | accepted SFX or local sting (2–4 s); paid cloud disabled |
| `silence` | **no** music; do not fill gap |
| `none` | skip |

`silenceOnReveal: true` overrides program bed—compose ducks to true quiet. No separate SFX engine: `sfxCue` `whoosh`/`riser`/`impact-soft`/`accent` → sting; `click` → Recast on `screen` beats; else sting. Specialist: `local-ai-stack` `references/music.md`.

Mix with `Finish-Media.ps1 -Speech -Music` so bed ducks. Do not mux unducked bed.

## 4. Pictures

For each `visual-bible.brollPlan`/`imagePrompts` row, reuse accepted plates or select adequate local `ai.ps1 image` route. Paid hosted image/video disabled pending metered adapter. Honor `refuse` (never product UI, metrics, testimonials). Specialist: `references/image.md`.

Motif/lipsync/portrait **only** when `direction` called for that plate. Never Motif or image-to-video a product screenshot (`references/video.md`, `product-picture.md`).

Cloud music, SFX, dubbing, lipsync, video, editing need metered shared adapters before paid generation. Specialist skills describe schemas but do not enable routes. Use accepted assets or authorized local tools.

## 5. Local commands

| Need | Command | Specialist |
|---|---|---|
| Owner/clone TTS | `ai.ps1 voice qwen-clone --voice <id>` | `references/voice.md` |
| Role TTS | `ai.ps1 voice qwen-role` | `references/voice.md` |
| Identity gate | `ai.ps1 voice score --voice sarosh <wav>` | `references/voice.md` |
| Image | `ai.ps1 image single` | `references/image.md` |
| Motif I2V | `ai.ps1 motif --reference <png> --prompt "…" --out <mp4>` | `references/video.md` |
| Lipsync | `ai.ps1 lipsync <video> --audio <wav>` | `references/video.md` |
| Portrait | `ai.ps1 portrait <image>` | `references/video.md` |
| Music | `ai.ps1 music <batch.json>` | `references/music.md` |
| Transcribe | `ai.ps1 transcribe <path>` | `references/voice.md` |
| Listen | `ai.ps1 listen <encoded-media> --output <report.json>`; `--timeline` above 90 s | `references/voice.md` |

## 6. Provenance

Write artifacts and generation scripts/config only into external job workspace. Never copy generated plates, audio, prompts, receipts, helper code, or dependencies into a product repository. Bind path, bytes, SHA-256 in a generation receipt keyed by beat id. Assembly consumes that receipt—an unrecorded copy into `selected/` is not provenance.

## 7. Final check

- [ ] Default style unless beat's register deliberately overridden by hand and re-gated
- [ ] Owner segments identity-scored
- [ ] Bed only if beat asked; stings short; silence beats have no music file
- [ ] Bible B-roll generated with refuse honored
- [ ] Receipt binds every plate compose will mux

Approved Sienna role narration uses the canonical scripts/deepgram_cli.py governed route described in ../media-studio/references/content-controls.md. Quote first; narrator/story approval does not configure a paid budget. Do not execute legacy job-local Deepgram runners or substitute a voice. All five acceptance gates and accepted word alignment still apply.
