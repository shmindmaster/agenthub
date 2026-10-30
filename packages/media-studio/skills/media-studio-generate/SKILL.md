---
name: media-studio-generate
description: Use when a video or audio job needs provider-routed generation — narration and character voices, still images, avatar presenter clips, music beds and stings from accepted assets, or transcription and ASR checks — through the MahumTech Azure AI Services default, with Deepgram then ElevenLabs as governed fallbacks. Local AI is off.
---

# Media studio generate

## Provider routing — Azure is the default (owner direction 2026-10-29)

Load `references/azure-ai-services.md` before planning any generation. The MahumTech Azure resource `aoai-mrender-4e123a95` (eastus2) is the default provider; within Azure take the cheapest option that passes QA, and escalate only items that fail review.

| Need | Default | Fallback, only when Azure cannot do it or a gate failed |
|---|---|---|
| Narration and character voices | Azure Speech TTS: **standard neural is the default narration voice**; Neural HD and MAI-Voice for cinematic principals and characters (MAI is a preview: fall back to HD if an interjection drops). Run an ASR check on every line. Cast from the voice cast in the reference | Deepgram governed adapter first; ElevenLabs last |
| Transcription and ASR gates | Azure batch transcription for backlogs (private blob + SAS) and fast transcription for one file. Real-time and streaming STT stay on Deepgram (Azure is $1 / hr vs $0.46 / hr) | Deepgram Nova-3 |
| Images | Azure `gpt-image-2.5-flare` at low or medium quality is the default per image (about $0.006 / $0.013); capacity 2 requests/min | Gemini Batch only for volume until the Azure image quota rises; OpenAI |
| Avatar presenter clips | Azure TTS avatar, batch API, prebuilt avatars | none; use Remotion/Recast composition instead |
| Video generation | Sora 2 works but its inference ends 2026-11-02: do not plan around it | Remotion/Recast composition |
| Chat, QA, embeddings, OCR | Embeddings `text-embedding-3-small` and Document Intelligence on Azure. For chat and QA, Anthropic Haiku 5.5 is cheaper than `gpt-5-mini`; keep `gpt-5-mini` as the credit-funded fallback; Flex only on `gpt-6-luna` once its price is confirmed | Anthropic for bulk LLM work |

Rules that apply to every Azure call: never use `AZURE_OPENAI_*` or the Pendoah endpoints; credentials stay in environment variables; hash inputs and reuse accepted takes; quote the price basis in the report; stay inside the credit budget alerts ($400 / $600 / $680). Films and cinematic work cast a distinct, expressive voice per scene and character; **no Sarosh voice clone in films** (owner direction 2026-10-29). Custom avatars, personal voice and professional voice are Limited Access; do not apply without an owner decision (steps are in the reference).

The governed adapters (`scripts/governed_azure_speech.py` with `scripts/governed_azure_speech.md`, `scripts/deepgram_cli.py`, `packages/elevenlabs`) are the ledgered paths for paid speech. **Local AI is off (owner direction 2026-10-29):** never start local models, TTS/STT servers or embedders. The local voice pipeline (`Generate-OwnerVoice.ps1`, `ReGate-OwnerVoice.ps1`) is removed; there is no local voice, music, image, motion, lipsync or portrait route. Artifact paths resolve from `MEDIA_STUDIO_ROOT` (default `D:\Media-Studio`); never hard-code the drive path.

## 0. Before generating

Choose by cost, latency, quality, privacy. Reuse accepted assets first. Load `../media-studio/references/content-controls.md` before paid planning, and `elevenlabs` (its `SKILL.md` and `references/cost-controls.md`) before any ElevenLabs fallback. Native connectors and SDK examples must not bypass the ledger. Unsupported paid modalities stay disabled.

Load `../media-studio/references/engagement.md`. Viewer-facing jobs consume **locked** `storyboard.json`, `visual-bible.json`, `direction.json`. Do not invent plates the director did not call. Skip a beat whose selected take matches the locked narration hash. Do not rerun the whole job for one scene.

Owner speech loads `sarosh-audio-voice`, and only where the owner names his voice for non-film work. Speaker identity is advisory only (owner direction 2026-10-27): never fail, block or re-voice on speaker similarity. Takes still pass integrity and ASR.

## 1. Inputs

| File | Required when |
|---|---|
| `narration.md` / screenplay | always |
| `direction.json` | viewer-facing: register, duration, plates per beat |
| `storyboard.json` | viewer-facing: `sound`, `shotPlan`, silence windows |
| `visual-bible.json` | viewer-facing B-roll |

Missing required file → remit. Do not generate a generic bed and skip the bible.

## 2. Voice

1. **Cast.** One voice per role from the voice cast (`references/azure-ai-services.md` §4); vary the cast across a film. Honor each beat's `direction.register` with the voice tier and its supported style (`<mstts:express-as>` on standard and MAI voices, inline `[tag]` cues on non-Omni HD voices). An unsupported style silently renders neutral, so check `StyleList` first. Record voice, tier and style per beat in the generation receipt.
2. **Quote and synthesize** through a governed adapter. Lock segments, hash the exact input (voice, style, SSML, output format), and reuse an accepted take on a hash match. Save provider receipts under the job workspace. Never fabricate a PASS receipt.
3. **Gate every take before selection** (fail-closed):
   - **Integrity:** the deployed `Test-SpeechIntegrity.ps1` (FFmpeg-based: dead air, level, duration skew against the line, internal silence).
   - **ASR on every line:** hosted STT words compared with the locked script (Azure fast transcription for one file, batch for backlogs, Deepgram Nova-3 for real-time). Wrong words fail the take.
   - **Pronunciation:** a respelling pre-pass in the synthesis input (SSML `sub`/`phoneme` or a provider lexicon) for names, brand terms, acronyms and codes, then the ASR check confirms them. The canonical narration is never respelled; it stays the ASR reference. ABACare lexicon: `skills/media-studio-capture/references/abacare-lexicon.json`.
   - Re-render only the line that failed, on the next tier or the fallback provider. Never re-voice paid audio that already passed; fix recurring pronunciation in the lexicon for the next lines.
4. **Selection ledger** before scene concat. Decode and gate the exact delivery spans again after assembly.

The deployed shared tools must match the package release:

```powershell
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\_shared\tools'
$manifest = Join-Path $tools 'plugin.json'
$integrity = Join-Path $tools 'Test-SpeechIntegrity.ps1'
$stems = Join-Path $tools 'Finish-BriefingStems.ps1'
if (-not (Test-Path -LiteralPath $manifest) -or (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).version -ne '2.0.41' -or -not (Test-Path -LiteralPath $integrity) -or -not (Test-Path -LiteralPath $stems)) {
    throw 'Media Studio 2.0.41 speech tools are missing or stale. Deploy them from a verified package before generation.'
}
& pwsh -NoProfile -File $integrity -Path <take.wav> -Text '<locked line text>' -JsonOut <qa/integrity/<id>.json>
```

**Word clock.** The picture clock comes from the accepted takes: `kit/cloud/cloud-ai.mjs align` writes an ASR-anchored report, which the gates accept only when `job.json` sets `clockPolicy.allowAsrAnchored: true` (`media-studio-qa`). Provider word-boundary events count only as the adapter documents them; never estimate word timing.

**Banned:** inventing voices or styles outside the catalog; assembling integrity- or ASR-failing segments; phonetic respelling of canonical narration; a Sarosh voice clone in a film; **regenerating, re-voicing or rejecting a take because a speaker-similarity score is low** (identity is advisory only, owner direction 2026-10-27).

Honor `pauseBeforeSeconds`/`holdAfterSeconds` as edit silence, not padded TTS. Mix with `Finish-BriefingStems.ps1` (speech-only loudnorm; it preconditions speech with fixed gain and a true-peak limiter, then a two-pass linear loudnorm). `Finish-Media.ps1` is deployed beside it and refuses a dynamic fallback: never pass `-AllowDynamic` on TTS; pass `-LoudnessRange 11` when only LRA blocks the linear pass.

## 3. Music and silence

Viewer-facing jobs supply the directed `musicCue: bed` unless `intent: draft` or `music: none`. Cloud music and SFX stay disabled until a metered shared adapter exists, and there is no local generator: use accepted, licensed assets. A viewer-facing beat that needs a bed or sting with no accepted asset is a blocker to report, not a gap to fill silently.

| `sound.musicCue` | Supply |
|---|---|
| `bed` | accepted bed asset |
| `sting` | accepted SFX or sting (2–4 s) |
| `silence` | **no** music; do not fill gap |
| `none` | skip |

`silenceOnReveal: true` overrides program bed—compose ducks to true quiet. No separate SFX engine: `sfxCue` `whoosh`/`riser`/`impact-soft`/`accent` → sting; `click` → Recast on `screen` beats; else sting.

Mix with `Finish-Media.ps1 -Speech -Music` so bed ducks. Do not mux unducked bed.

## 4. Pictures

For each `visual-bible.brollPlan`/`imagePrompts` row, reuse accepted plates, else generate with Azure `gpt-image-2.5-flare` at low or medium quality (2 requests/min: queue small batches; Gemini Batch only for volume until the quota rises). Redraw only plates that fail review. Honor `refuse` (never product UI, metrics, testimonials).

Motion plates: a directed presenter clip uses the Azure TTS avatar batch API (`subtitleType: none`); other motion is Remotion/Recast composition. Image-to-video, lipsync and portrait animation have no active route (local AI is off; cloud video, dubbing and lipsync need metered shared adapters before paid generation); reuse an accepted plate or return the beat to the director. Never animate a product screenshot (`../media-studio/references/product-picture.md`).

## 5. Provenance

Write artifacts and generation scripts/config only into external job workspace. Never copy generated plates, audio, prompts, receipts, helper code, or dependencies into a product repository. Bind path, bytes, SHA-256, provider, model or voice, and price basis in a generation receipt keyed by beat id. Assembly consumes that receipt—an unrecorded copy into `selected/` is not provenance.

## 6. Final check

- [ ] Every voice cast from the catalog; per-beat register recorded; no Sarosh clone in a film
- [ ] Every segment passed integrity and ASR (identity not a gate); brand terms confirmed by ASR
- [ ] Bed only if beat asked, from an accepted asset; stings short; silence beats have no music file
- [ ] Bible B-roll generated with refuse honored
- [ ] Receipt binds every plate and take compose will mux, with the price basis

Approved Sienna role narration uses the canonical scripts/deepgram_cli.py governed route described in ../media-studio/references/content-controls.md. Quote first; narrator/story approval does not configure a paid budget. Do not execute legacy job-local Deepgram runners or substitute a voice. All five acceptance gates and accepted word alignment still apply.
