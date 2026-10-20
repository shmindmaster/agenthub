---
name: media-studio-generate
description: Use when a video or audio job needs provider-routed generation — owner or role voice, images, motif clips, lipsync, portrait, music beds, stings, or transcription — through ElevenLabs or the Local-AI control plane.
---

# Media studio generate

Choose by cost, latency, quality and privacy. Reuse accepted assets first. Load `elevenlabs-api` and `../media-studio/references/content-controls.md` before paid planning. Paid ElevenLabs TTS requires its shared governed CLI; unsupported paid modalities remain disabled. Native connectors and SDK examples must not bypass the ledger. Use adequate authorized local generation otherwise. Load `local-ai-stack` and resolve `$LocalAiControl` for local generation or validation. For hour-scale batches also load `long-running-generation`. One heavy GPU job at a time.

Load `../media-studio/references/engagement.md`. Viewer-facing jobs consume **locked** `storyboard.json`, `visual-bible.json`, and `direction.json`. Do not invent plates the director did not call.

Owner speech loads `sarosh-audio-voice`: local speech is eligible when adequate; the approved existing hosted clone is permitted when ready and worth its cost. Both require identity gates. No new private recordings, clone replacement or verification is implied.

```powershell
& $LocalAiControl status
& $LocalAiControl check
```

Start only the route you need (`voice`, `media` / Comfy, `music`). Do not start Comfy for TTS or music. Skip a beat whose selected take already matches the locked narration hash. Do not rerun the whole job for one scene.

## 1. Inputs

| File | Required when |
| --- | --- |
| `narration.md` / screenplay | always |
| `direction.json` | viewer-facing: register, duration, plates per beat |
| `storyboard.json` | viewer-facing: `sound`, `shotPlan`, silence windows |
| `visual-bible.json` | viewer-facing B-roll / motif |

If a required file is missing, remit. Do not generate a generic bed and skip the bible.

## 2. Voice

Use `elevenlabs-tts` for hosted speech. Lock segments, check credits and clone/model
readiness and whole-job/preview budgets; reuse an accepted matching preview or
generate one small preview. Save provider receipts under the job
workspace; run local integrity, ASR, pronunciation and dual-backend identity gates
before selecting owner takes. Decode and gate exact delivery spans again.
`Generate-OwnerVoice.ps1` implements the **local backend only**. Its local receipt
format is not a hosted adapter: never fabricate its PASS receipts for hosted audio.
If the selected assembly path requires those local receipts, keep that path local
until a verified provider receipt adapter exists; report that limitation explicitly.

For local viewer-facing owner/role speech use `Generate-OwnerVoice.ps1`:

Use the AgentHub-deployed shared tools on native-plugin and loose-skill hosts. Their `plugin.json` must match this skill's 1.7.3 release. Missing or stale tools block generation until AgentHub syncs the kit from a verified 1.7.3 package; do not default to a checkout of unknown version.

```powershell
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\_shared\tools'
$manifest = Join-Path $tools 'plugin.json'
$generator = Join-Path $tools 'Generate-OwnerVoice.ps1'
$integrity = Join-Path $tools 'Test-SpeechIntegrity.ps1'
if (-not (Test-Path -LiteralPath $manifest) -or (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).version -ne '1.7.3' -or -not (Test-Path -LiteralPath $generator) -or -not (Test-Path -LiteralPath $integrity)) {
    throw 'Media Studio 1.7.3 voice tools are missing or stale. Deploy them from a verified package before generation.'
}
& pwsh -NoProfile -File $generator -Job $Job
```

That path is fail-closed: allowlisted style only (default `02_explaining` from `_identity_probe.json`) → integrity → `ai.ps1 transcribe` (Qwen3-ASR-1.7B) → dual-backend identity → retry → seed → `--premium` → STOP+LOG. Selection ledger before scene concat. Role voices (`ryan` / `vivian` / `aiden` / `joel` from each scene's `speaker`, matching the kit's stakeholder cast) get integrity + ASR only, no identity gate.

If a STOP+LOG segment failed only because the ASR misread digits/numbers already present in the narration (identity passed, wording didn't), do not regenerate TTS: run `pwsh -NoProfile -File (Join-Path $tools 'ReGate-OwnerVoice.ps1') -Job $Job` after the same deployed-version check. It re-scores the existing `take.wav` files with number-normalized WER and looser integrity and writes fresh `PASS.json` receipts in place — it never re-synthesizes audio.

`Generate-OwnerVoice.ps1` reads narration and `speaker` straight from `screenplay.json`; it does not parse `storyboard.json` or `visual-bible.json` itself — those still drive Sections 3 and 4 below by hand. **Known gap: it renders the whole job on one allowlisted default style, not per-beat `direction.register`.** `media-director` still names a style-bank register per beat in `direction.json` (`explaining`, `firm`, `serious`, …), but the batch script does not read or switch on it. If a beat's called register meaningfully differs from the default, generate that one segment manually — `ai.ps1 voice qwen-clone --voice sarosh --reference <register-style.wav> --ref-text <sidecar> --text "…"`, gated through `Test-SpeechIntegrity.ps1` and `ai.ps1 voice score --voice sarosh` — and splice it into `voice/selected/` before scene concat. Do not claim a beat's register was honored unless you did this by hand; the automated path always uses the default.

**Banned:** inventing style IDs (`04_serious`); using `03_firm` / other styles until allowlisted; GGUF talker/ASR forks; phonetic-respelling Sarosh input; assembling identity/ASR-failing segments.

Pronunciation is a gate inside `Generate-OwnerVoice.ps1`, not a note: before any audio it runs `ai.ps1 voice pronunciation-risk` over the canonical segments and writes `qa/pronunciation-risk.json` (heteronyms with a part-of-speech reading per occurrence — `resume`/`résumé`, `record`/`records`, `content` — plus stress-shift clinical terms, names, acronyms, codes, symbols). A heteronym whose reading cannot be inferred stops the run (`coverage.status: FAIL`); record the reading with `-PronunciationOverrides <json>` (`{ "S05_02": { "record": "verb" } }`) or reword. Pass the product lexicon with `-PronunciationLexicon` (ABACare: `skills/media-studio-capture/references/abacare-lexicon.json`). After the takes pass integrity, ASR and identity, the script runs per-scene `ai.ps1 listen` on the concatenated scene audio with the canonical transcript and that scene's slice of the manifest; any pronunciation, pacing or artifact finding regenerates the localized segment with a new seed and listens again (`-ListenMaxRounds`, default 2), then STOP+LOG. `qa/pronunciation-listen.json` and the selection ledger record every report by sha256. Extend `pronunciations.json` when a term keeps failing; never respell the canonical narration.

Honor `pauseBeforeSeconds` / `holdAfterSeconds` as edit silence, not padded TTS — on `product-screencast` that silence is the product responding. Speak the locked `narration.md` / `screenplay.json`. Mix with `(Join-Path $tools 'Finish-BriefingStems.ps1')` (speech-only loudnorm) — never `-AllowDynamic` on TTS. Its `Finish-Media.ps1` dependency is deployed beside it. Local TTS stems (Qwen3) land near -21.5 LUFS with peaks at about -1.6 dBTP, a peak-to-loudness ratio of ~19 dB, so a bare linear pass to -16 LUFS / -1.5 dBTP is impossible and `Finish-Media.ps1` refuses the dynamic fallback. Every finish path (briefing stems and product-screencast mux alike) preconditions the speech first: fixed gain plus a true-peak limiter (`alimiter=limit=0.8413:attack=5:release=50:level=disabled`), then the two-pass linear loudnorm; pass `-LoudnessRange 11` when only LRA blocks the linear pass.

## 3. Music and silence

Viewer-facing jobs also generate the directed music (`musicCue: bed` or `sting`) unless `intent: draft` or `music: none`.

| Storyboard `sound.musicCue` | Generate |
| --- | --- |
| `bed` | one accepted bed or adequate local `ai.ps1 music`; paid cloud music is disabled pending a metered adapter |
| `sting` | an accepted short SFX or local sting (2–4s hit); paid cloud SFX is disabled pending a metered adapter |
| `silence` | **no** music on that beat. Do not fill the gap. |
| `none` | skip |

`silenceOnReveal: true` on a beat overrides a program bed for that hold — compose ducks to true quiet. The local fallback has **no** separate SFX engine: `sfxCue` `whoosh` / `riser` / `impact-soft` / `accent` maps to a sting; `click` is Recast on `screen` beats; else sting. Specialist: `local-ai-stack` `references/music.md`.

Mix later with `Finish-Media.ps1 -Speech -Music` so the bed ducks. Do not mux an unducked bed.

## 4. Pictures the bible called for

For each `visual-bible.brollPlan` / `imagePrompts` row, reuse accepted plates or select an adequate local `ai.ps1 image` route. Paid hosted image/video generation is disabled pending a metered shared adapter. Honor `refuse` (never product UI, metrics, testimonials). Specialist: `references/image.md`.

Motif / lipsync / portrait **only** when `direction` called for that plate. Never Motif or image-to-video a product screenshot (`references/video.md`, `product-picture.md`).

Cloud music, SFX, dubbing, lipsync, video and editing need metered shared adapters
before paid generation. Specialist skills may describe schemas but do not enable
these routes. Use existing accepted assets or adequate authorized local tools.

## 5. Local generation commands

| Need | Command | Specialist |
| --- | --- | --- |
| Owner / clone TTS | `ai.ps1 voice qwen-clone --voice <id>` | `references/voice.md` |
| Role TTS | `ai.ps1 voice qwen-role` | `references/voice.md` |
| Identity gate | `ai.ps1 voice score --voice sarosh <wav>` | `references/voice.md` |
| Image / Visual Bank | `ai.ps1 image single` | `references/image.md` |
| Motif I2V | `ai.ps1 motif --reference <png> --prompt "…" --out <mp4>` | `references/video.md` |
| Lipsync | `ai.ps1 lipsync <video> --audio <wav>` | `references/video.md` |
| Portrait | `ai.ps1 portrait <image>` (specialty) | `references/video.md` |
| Music bed or sting | `ai.ps1 music <batch.json>` | `references/music.md` |
| Transcribe | `ai.ps1 transcribe <path>` | `references/voice.md` |
| Full-program listen | `ai.ps1 listen <encoded-media> --output <report.json>`; `--timeline` above 90s | `references/voice.md` |

## 6. Provenance

Write artifacts and any generation scripts/config only into the external job
workspace. Never copy generated plates, audio, prompts, model receipts, helper
code, or dependencies into a product repository. Bind path, bytes, and SHA-256
in a generation receipt keyed by beat id (voice, bed/sting, each B-roll still).
Assembly consumes that receipt — an unrecorded copy into `selected/` is not
provenance.

## 7. Final check

- [ ] Default style used unless a beat's `direction.register` was deliberately overridden by hand and re-gated
- [ ] Owner segments identity-scored
- [ ] Bed generated only if a beat asked for `bed`; stings are short; silence beats have no music file
- [ ] Bible B-roll generated with refuse honored
- [ ] Receipt binds every plate compose will mux
