# Azure AI Services — default provider for media generation

Owner direction 2026-10-29: the MahumTech Azure resource is the **default** AI provider; ElevenLabs, Deepgram, Gemini and personal OpenAI keys are fallbacks. Within Azure, take **the cheapest option that passes QA**, and escalate only the items that fail review.

- Resource: `aoai-mrender-4e123a95` (kind AIServices, S0, **eastus2**), resource group `rg-media-render`, subscription "MahumTech - Partner Azure (MCPP)". Billed to a $700 partner credit; budget alerts at $400 / $600 / $680.
- **Never** use `AZURE_OPENAI_*` or `AZURE_OPENAI_PNDH_*` (Pendoah's `aif-pndh-*` platform is client infrastructure).
- Artifact paths below are relative to `%MEDIA_STUDIO_ROOT%` (today `D:\Local-AI\data\artifacts\media-studio`, moving to `D:\Media-Studio`); keep paths configurable.
- Credentials are environment variables only. Print a variable's name and whether it is set, never its value.
- **Test-first gate (2026-10-29):** each capability was called from this PC with this resource's key before it was routed. Results, quality notes and prices vs what we pay today are in §6; only capabilities marked adopt or fallback there are routed to Azure.
- Facts below were checked 2026-10-29 against Microsoft Learn, the Azure pricing page and the public Retail Prices API (`https://prices.azure.com/api/retail/prices`, filter `serviceName eq 'Foundry Tools' and armRegionName eq 'eastus2'`). Items marked **verified** were also exercised against this resource. **UNVERIFIED** means the source was silent or conflicting; do not budget on it without re-checking.

## 1. Capability table

| Need | Use | Endpoint pattern (eastus2) | Env vars | Price basis (USD, eastus2) | Region / limits | Docs |
|---|---|---|---|---|---|---|
| Voices catalog | `GET voices/list` (free) | `https://eastus2.tts.speech.microsoft.com/cognitiveservices/voices/list`, header `Ocp-Apim-Subscription-Key` — **verified** (969 voices) | `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION` | free | all voices incl. `StyleList` and `RolePlayList` | [REST TTS](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech) |
| TTS, standard neural | Neural voices (incl. `*MultilingualNeural`, `*Neural` with styles/roles) | `POST https://eastus2.tts.speech.microsoft.com/cognitiveservices/v1`, `Content-Type: application/ssml+xml`, `X-Microsoft-OutputFormat`, `User-Agent` — **verified** | same | **$15 / 1M chars** | 30 TPS default on S0; 10 min audio/request | [pricing](https://azure.microsoft.com/en-us/pricing/details/speech/), [SSML](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-voice) |
| TTS, HD | `*:DragonHDLatestNeural`, `*:DragonHDOmniLatestNeural` | same `/cognitiveservices/v1` — **verified** | same | **$22 / 1M chars** (Retail API meter "Neural HD Text to Speech") | eastus2 yes. SSML limits: no `prosody`, `emphasis`, `bookmark`, `viseme`; `express-as` on Omni only; `[excited]`-style bracket tags on both | [HD voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/high-definition-voices) |
| TTS, HD Flash | `en-US-Tiana/Tyler/Jimmie:DragonHDFlashLatestNeural` | same | same | $15 per the pricing page's grouping with Neural; **UNVERIFIED** in the Retail API | listed regions exclude eastus2 in the docs but the voices list returns them: **UNVERIFIED** that synthesis works | [HD voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/high-definition-voices) |
| TTS, MAI-Voice 2 / 2.1 (preview, no SLA) | `en-US-Ethan:MAI-Voice-2.1`, `en-GB-Harry:MAI-Voice-2.1`, … and `…-Flash` | same `/cognitiveservices/v1` with `<mstts:express-as style="determined">` — **verified** (styles worked) | same | **UNVERIFIED**: no MAI voice meter exists in the Retail API and the pricing page prints "N/A". Budget at the HD rate until a bill line shows otherwise | eastus2 yes; per-voice emotion styles (angry, determined, hopeful, whispering, shouting, narrator, audiobook, educational …) | [MAI voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-voices) |
| TTS, batch synthesis | Long scripts, many inputs | `PUT https://eastus2.api.cognitive.microsoft.com/texttospeech/batchsyntheses/{id}?api-version=2024-04-01` (docs show the `{resource}.cognitiveservices.azure.com` host); ZIP output, optional word/sentence boundaries | same | same per-char rate as real time (no discount). Value is throughput, not price | JSON ≤2 MB, ≤10,000 inputs/job; F0 not allowed. Whether HD voices work in batch: docs conflict, **UNVERIFIED** | [batch synthesis](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/batch-synthesis) |
| Personal voice | Clone of a consenting speaker | `/customvoice/…?api-version=2026-01-01` | same | synthesis $24 / 1M chars; storage $600 / 1K profiles | **Limited Access** (see §3). **No Sarosh voice clone in films** | [personal voice](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/personal-voice-overview) |
| Professional (custom neural) voice | Trained voice | deploy to `https://eastus2.voice.speech.microsoft.com/cognitiveservices/v1?deploymentId=…` | same | $24 std / $48 HD per 1M chars; training $52/compute-hr; hosting ~$4.03/hr | **Limited Access** | [limited access](https://learn.microsoft.com/en-us/azure/foundry/responsible-ai/speech-service/text-to-speech/limited-access) |
| STT, batch transcription | Backlogs, anything not needed in minutes | `POST https://eastus2.api.cognitive.microsoft.com/speechtotext/transcriptions:submit?api-version=2024-11-15` — **verified** (WER 0.0, ~66 s per job) | same | **$0.18 / hr** (custom $0.225) | **Needs a private blob URL with a read SAS**; public URLs (GitHub, crbn.us) fail with `InvalidUri`. 1 GB/file, 1,000 files/request. Whisper via batch is **not** in eastus2. Diarization included | [batch transcription](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/batch-transcription-create) |
| STT, fast transcription | One file, answer in seconds — **verified** (WER 0.0, 0.7 s for a 6 s clip) | `POST …/speechtotext/transcriptions:transcribe?api-version=2025-10-15`, multipart `audio` + `definition` | same | **$0.36 / hr** (Retail API); a "Fast Transcription Promo" meter lists $0.10 / hr — **UNVERIFIED** that it applies | <5 h, <500 MB; diarization `{"enabled":true,"maxSpeakers":N}` mono only | [fast transcription](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/fast-transcription-create) |
| STT, real-time / short audio | ≤60 s clips; **pricier than Deepgram Nova-3 streaming ($0.46 / hr): do not route here** | `POST https://eastus2.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=simple`, `Content-Type: audio/wav; codecs=audio/pcm; samplerate=48000` — **verified** (27 clips) | same | **$1 / hr**; real-time diarization add-on $0.30 / hr | 100 concurrent on S0 | [pricing](https://azure.microsoft.com/en-us/pricing/details/speech/) |
| Voice Live API | Interactive voice agents (STT + LLM + TTS + avatar in one WebSocket) | WebSocket on the resource | same | token-priced per LLM tier (Lite / Std / Pro) | ≤60 min/session. **Not** a batch narration pipeline; do not use for films | [Voice Live](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/voice-live) |
| TTS avatar, batch (standard / prebuilt) | A rendered, lip-synced presenter video | `PUT https://eastus2.api.cognitive.microsoft.com/avatar/batchsyntheses/{id}?api-version=2024-08-01` — **verified** (10 s clip, 25 s render) | same | **$1.00 / min** of output video; **$1.35 / min** with an HD voice (Retail API meters "TTS Standard Avatar Batch", "TTS HD Standard Avatar Batch"), plus the TTS characters | **eastus2 supported** (batch, real-time, custom hosting). 2 requests/min on S0, 200 concurrent jobs, ≤20 min per video, payload ≤500 KB. Download the result with the key header | [batch avatar](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/text-to-speech-avatar/batch-synthesis-avatar) |
| TTS avatar, real-time | Live sessions (WebRTC) | Speech SDK | same | $0.50 / min, HD $0.70 / min, billed while the connection is open even when silent | 2 new connections/min; 30 min max | [avatar overview](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/text-to-speech-avatar/what-is-text-to-speech-avatar) |
| Avatar, custom (video / photo) | Your own presenter | same batch endpoint with `customized: true` | same | custom batch $2.00 / min, HD custom $2.70 / min; hosting $0.60 / hr; photo avatar creation $2,000 / 1K | Training only in westus2, southeastasia, westeurope. **Limited Access** (§3) | [custom avatar](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/text-to-speech-avatar/what-is-custom-text-to-speech-avatar) |
| Chat, classification, QA | `gpt-5-mini` deployment | `{AZURE_AI_SERVICES_ENDPOINT}openai/v1/…` (the endpoint ends in `/`); `FOUNDRY_OPENAI_BASE_URL` is the same surface | `AZURE_AI_SERVICES_*`, `FOUNDRY_*` | $0.25 in / $0.03 cached in / $2 out per 1M | Global Standard; retires 2027-02-09. **Verified** (200, 2.5 s). Flex unsupported (400). Pricier than Haiku 5.5 | [pricing](https://azure.microsoft.com/en-us/pricing/details/azure-openai/) |
| Cheaper chat | `gpt-5-nano`; Flex on `gpt-5.6-luna` | same | same | nano $0.05 / $0.01 / $0.40; luna Flex $0.10 in / $0.60 out | `gpt-6-luna` Flex **verified** on the existing `docwise-chat` deployment (another agent owns it); `gpt-5-nano` and `gpt-5.6-luna` are not deployed | [flex](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/flex-processing) |
| Embeddings | `text-embedding-3-small` | `…/openai/v1/embeddings` | same | **$0.022 / 1M tokens** (OpenAI direct $0.02: same) — **verified** (1536 dims) | ≤2,048 inputs and 300K tokens per request | pricing page above |
| Images | `gpt-image-2.5-flare`, `gpt-image-2.5-sunburst` | `…/openai/deployments/{name}/images/generations` and `/images/edits` | same | **verified**; flare low 196 output tokens ≈ **$0.006**, medium 439 ≈ **$0.013** per 1024x1024 image (Gemini 2.5 Flash Image is $0.039, $0.0195 batch); **tokens, no per-image table**: $5 text in, $8 image in, $30 image out per 1M | **capacity 2 = 2 requests/min** (Tier 1). Raise via https://aka.ms/oai/stuquotarequest. Quality `low/medium/high/xhigh/max/auto`; sizes custom, multiples of 16, ≤3840 px edge | [image how-to](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/dall-e), [quotas](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits) |
| Video | Sora 2 (`sora-2`) | `POST …/openai/v1/videos`; 4/8/12 s at 720x1280 or 1280x720 | same | $0.10 / s listed | **Works now, ends soon.** `sora-2` 2025-12-08 deployed in eastus2 (GlobalStandard) and rendered a 4 s 1280x720 clip with audio in 55 s (**verified**), but its lifecycle is Deprecated and inference ends 2026-11-02. No `sora-2-pro` on Azure. Skip | [retirements](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/model-retirement-schedule), [video](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/video-generation) |
| Alternative expressive TTS / STT | `gpt-4o-mini-tts` 2025-12-15, `gpt-4o-mini-transcribe` 2025-12-15 | `…/openai/v1/audio/speech`, `/audio/transcriptions` | same | TTS text in $0.60, audio out $12 per 1M tokens; transcribe audio in $3 per 1M | Not deployed; instruction-steered preset voices | [pricing](https://azure.microsoft.com/en-us/pricing/details/azure-openai/) |
| OCR / layout | Document Intelligence Read, Layout | `POST {AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT}documentintelligence/documentModels/prebuilt-read:analyze?api-version=2024-11-30` | `AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT`, `…_KEY` | Read **$1.50 / 1K pages**; Layout and prebuilt $10 / 1K | eastus2 availability UNVERIFIED | [pricing](https://azure.microsoft.com/en-us/pricing/details/document-intelligence/) |
| Media understanding | Content Understanding | `POST {endpoint}contentunderstanding/analyzers/{id}:analyze?api-version=2025-11-01` | `AZURE_AI_SERVICES_*` | audio $0.36 / hr, video $1 / hr extraction, plus LLM tokens | eastus2 yes; needs default model deployments | [pricing](https://azure.microsoft.com/en-us/pricing/details/content-understanding/) |
| Translation | Translator text | `POST https://api.cognitive.microsofttranslator.com/translate?api-version=3.0` | `AZURE_AI_SERVICES_KEY` + region header | $10 / 1M chars | global | [pricing](https://azure.microsoft.com/en-us/pricing/details/translator/) |
| Vision | Image Analysis 4.0 (`read`, `caption`, `tags`) | `POST {endpoint}computervision/imageanalysis:analyze?api-version=2024-02-01&features=read,caption` | `AZURE_AI_SERVICES_*` | Read and caption $1.50 / 1K; tags and objects $1 / 1K | caption regions UNVERIFIED | [pricing](https://azure.microsoft.com/en-us/pricing/details/computer-vision/) |

### Flex, Batch and caching by model

| Feature | Applies to | Does **not** apply to |
|---|---|---|
| Flex (`service_tier: "flex"` or header `x-ms-service-tier: flex`, 50% off, 429 when capacity is short, client timeout ~900 s) | `gpt-5.6-sol/luna/terra`, `gpt-6-astra/sol/luna`, `gpt-6.1-sol` (Global Standard) | `gpt-5-mini`, `gpt-5-nano`, `gpt-4.1`, o-series, embeddings, images (HTTP 400, no silent fallback) |
| Global Batch (50% off, `completion_window: "24h"`, 100K requests / 200 MB per file) | `gpt-5.4-mini`, `gpt-5.4`, `gpt-5.1`, `gpt-5`, o3, o4-mini, `gpt-4.1` family, `gpt-4o` family | `gpt-5-mini`, `gpt-5-nano`, images; embeddings are not in the model table (UNVERIFIED) |
| Prompt caching (automatic; identical first 1,024 tokens; ~90% off cached input on the gpt-5 family; 5–10 min idle clears it) | every Azure OpenAI model GPT-4o or newer, including `gpt-5-mini` | `prompt_cache_key` and explicit breakpoints are GPT-5.6+ only (older models return 400); 24 h retention is not listed for mini/nano |
| Speech batch (transcription, synthesis) | batch transcription is $0.18 / hr vs $1 / hr real time; batch synthesis has **no** per-character discount | |

Docs: [flex](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/flex-processing), [batch](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/batch), [prompt caching](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/prompt-caching).

## 2. Cheapest-first routing rules

1. **Never pay twice.** Hash the exact input (voice, style, SSML or text, output format) and reuse an accepted take, transcript or image. Remux instead of re-synthesizing. Re-render only the beat that failed review.
2. **TTS.** Standard neural ($15 / 1M chars) is the default narration voice. Step up only where the ear needs it: Neural HD ($22) for cinematic narration and principal characters; MAI-Voice only where per-line emotion styles decide the scene (budget at the HD rate until billing proves otherwise). MAI is a preview: if an interjection or opening word drops, re-render that line on HD. Run an ASR check on every line (a 10-minute narration is about 9,000 characters: about $0.14 standard, about $0.20 HD; TTS is never the cost driver, avatar minutes are).
3. **Characters.** Cast per scene and per character from the voice cast (§4). One voice per role. Vary the cast across a film. No Sarosh clone in films.
4. **Pronunciation.** Brand terms need a respelling pre-pass and an ASR check ("Claude" → "Clowdy" with Deepgram; "cache" came back as "cash" from Azure STT). Fix by lexicon, never by re-voicing paid audio.
5. **STT.** Batch transcription ($0.18 / hr, private blob + read SAS) for backlogs and anything not needed in minutes. Fast transcription ($0.36 / hr) is a fallback for one file now. **Do not route real-time or streaming STT to Azure**: Azure is $1 / hr against Deepgram Nova-3 at $0.46 / hr, so streaming and live ASR gates stay on Deepgram. Diarization is included in batch and fast.
6. **Avatar.** Prebuilt standard avatar through the **batch** API ($1 / min, $1.35 with an HD voice) when the output is a file. Real-time ($0.50 / min) is cheaper per minute but is a live session that bills while open; use it only for interactive demos. Keep clips short, render once, and cache by script hash. Respect 2 requests/min on S0.
7. **Chat and QA.** Measured: `gpt-5-mini` ($0.25 in / $2 out) is **pricier** than Anthropic Haiku 5.5 ($0.10 / $0.50, batch $0.05 / $0.25), and Flex on `gpt-5-mini` returns HTTP 400 `service_tier_not_supported`. Use Haiku first for bulk LLM work; keep `gpt-5-mini` as the Azure fallback (credit-funded). Flex works on `gpt-6-luna` (verified through the existing `docwise-chat` deployment, `service_tier: flex`); its Azure price is UNVERIFIED, so confirm before routing bulk work there. Put the static system prompt and shared context first so cached prefixes (>1,024 tokens) bill at the cached rate, cap output tokens, and strip boilerplate before sending.
8. **Embeddings.** `text-embedding-3-small` only, content-hash skip, incremental updates only.
9. **Images.** `gpt-image-2.5-flare` at low or medium quality is the default per image. It is token-billed with no per-image table; measured low ≈ $0.006 and medium ≈ $0.013 per 1024x1024 image. Redraw only items that fail review. Capacity is 2 requests/min per deployment (flare and sunburst are each at 2 of 2): queue small batches. Use Gemini Batch only for volume until the Azure quota rises; its balance is low. The quota request form is https://aka.ms/oai/stuquotarequest (see §6 for the draft); filing it is an outward-facing step that needs the owner's go.
10. **Video.** Sora 2 renders (verified 2026-10-29, $0.10 / s) but its inference ends 2026-11-02, so do not plan around it. For motion, use avatar clips and Remotion/Recast composition.
11. **Fallbacks.** Deepgram (`scripts/deepgram_cli.py`, governed adapter) is the first fallback for TTS and keeps Nova-3 as the default for real-time STT; ElevenLabs (`packages/elevenlabs`) is last. Gemini Batch covers image volume until the Azure quota rises. Use a fallback only when Azure cannot do the job (a voice or language Azure lacks, a failed ASR or pronunciation gate, a quota wall) and only per line or per item.
12. **Compute.** Azure covers the AI services; renders and encodes follow `media-studio-compose` (local NVENC when the PC is not taxed, else the Azure Container Apps job `caj-media-render` at about $0.0072 per job-minute, Daytona only with the orchestrator's OK). Local AI is off.
13. **Say the price basis** in every report: tier, rate, characters or minutes, and whether the figure came from the pricing page, the Retail API or a bill line.

### Governance carried over from the plugin

`scripts/governed_azure_speech.py` is the existing ledgered Azure TTS adapter (exact-request authorization, shared SQLite ledger, $1 ceiling per job, SDK transport). Production narration jobs that already run through it keep doing so. The direction to use Azure by default does not delete that governor; an owner decision is still needed on whether new Azure speech jobs under the partner credit need a per-job authorization manifest. Auditions, voice-list calls and sub-$5 tests (the 2026-10-29 voice cast and avatar sample) ran as direct REST calls under the task cap, with a spend ledger.

## 3. Limited Access and consent

Prebuilt voices, HD and MAI voices, and **standard and photo prebuilt avatars need no registration** (none found in the docs). These do:

- **Custom avatar (video or photo), personal voice, professional voice, MAI instant cloning**: one intake form, https://aka.ms/customneural (personal voice also https://aka.ms/PersonalVoiceForm). Eligibility is "customers managed by Microsoft" (an account team), for approved use cases only. Requirements: explicit written permission from the talent, the Microsoft talent disclosure, a visible synthetic-media disclosure, a feedback channel.
- **Consent for personal voice**: a recording of the speaker reading "I [first and last name] am aware that recordings of my voice will be used by [company name] to create and use a synthetic version of my voice." The locale matches the training audio. Steps: create a project, `PUT /customvoice/consents/{id}?api-version=2026-01-01` (or multipart POST), then create the personal voice, which returns `speakerProfileId`. Prompt audio is 5–90 s. Use it with `<mstts:ttsembedding speakerProfileId='…'>`.
- **Consent for a custom avatar**: a recorded video of the talent reading a fixed acknowledgement statement, verified against the training footage, kept by Microsoft; at least 10 minutes of training video; training runs in westus2, southeastasia or westeurope, and the model can be hosted in eastus2. Portal: https://aka.ms/customavatar-portal.
- **Probe result on this subscription (2026-10-29, nothing uploaded, nothing applied):** `GET /customvoice/{projects,consents,personalvoices,trainingsets,models,endpoints}` return 200 with empty lists, and creating then deleting a PersonalVoice and a ProfessionalVoice project both succeeded (201 / 204). Project creation is therefore not gated; approval can only be proven at the consent or voice-creation step, which needs real audio and a consent recording. Status: unknown.
- Sample specs: personal voice prompt 5–90 s, wav or mp3 at 16–48 kHz, ≤30 MB; MAI instant cloning 5–60 s. Professional voice about 300 utterances (24 kHz+ wav, mp3 ≥256 kbps), or long or audio-only recordings in Contextual mode; recipes `HD` (expressive) and `MultiStyle`; training about 10 compute hours at $52 (cap $936), hosting $4.03 / hr. Personal voice synthesis is $24 / 1M chars plus about $0.60 per profile per month. Review takes 5–10 business days and needs an organization email.
- Do not apply for any of these from this plugin without an owner decision. The owner has ruled out a Sarosh voice clone for films.

## 4. Voice cast (eastus2, 2026-10-29)

Samples: `%MEDIA_STUDIO_ROOT%\voice-cast\azure-20261029\samples\<id>.wav` (48 kHz mono WAV). Index with style, role fit and measured intelligibility: `…\azure-20261029\voice-cast.json`. Full catalog snapshot: `…\voices-list-raw.json`. Every sample passed an Azure STT round trip (see the index for each WER). The shortlist was chosen from catalog metadata and ASR; a human audition still decides the final cast.

| Role | First choices | Tier |
|---|---|---|
| Cinematic narrator | `en-US-Steffan:DragonHDLatestNeural`, `en-GB-Harry:MAI-Voice-2.1` (`narrator`), `en-US-Grant:MAI-Voice-2.1` (`audiobook`), `en-GB-Ryan:DragonHDLatestNeural`, `en-GB-Emily:MAI-Voice-2.1` (female) | HD / MAI |
| Hero | `en-US-Ethan:MAI-Voice-2.1` (`determined`), `en-US-Olivia:MAI-Voice-2.1` (`hopeful`) | MAI |
| Mentor | `en-US-Andrew:DragonHDLatestNeural`, `en-GB-Ollie:DragonHDLatestNeural` | HD |
| Villain | `en-US-Ethan:MAI-Voice-2.1` (`whispering`), `en-GB-Harry:MAI-Voice-2.1` (`angry`), `en-US-Jasper:MAI-Voice-2.1` | MAI |
| Kid / youthful | `en-US-AnaNeural` (child voice, standard), `en-US-Harper:MAI-Voice-2.1` (`excited`) | std / MAI |
| Explainer / expert | `en-US-Ava:DragonHDLatestNeural`, `en-US-Emma:DragonHDLatestNeural`, `en-US-Sage:MAI-Voice-2.1` (`educational`), `en-US-Brian:DragonHDLatestNeural` | HD / MAI |
| Warm female | `en-US-Serena:DragonHDLatestNeural`, `en-GB-Sonia:DragonHDLatestNeural` | HD |
| Deep male | `en-US-Vance:DragonHDLatestNeural`, `en-US-Tyler:DragonHDLatestNeural` | HD |
| Standard-tier baselines | `en-US-AriaNeural` (`narration-professional`), `en-GB-RyanNeural` (`cheerful`), `en-US-AdamMultilingualNeural`, `en-US-GuyNeural` (`terrified`) | std |

Style syntax: MAI and standard styled voices use `<mstts:express-as style="…">`; DragonHD (non-Omni) voices take inline `[tag]` cues and no `express-as`. List a voice's styles from `StyleList` in the voices list; an unsupported style silently makes the whole element neutral. MAI voices cap their per-voice styles (for example `en-US-Jasper` has none).

## 5. Verified call recipes (2026-10-29)

```text
TTS      POST https://eastus2.tts.speech.microsoft.com/cognitiveservices/v1
         Ocp-Apim-Subscription-Key: <AZURE_SPEECH_KEY>
         Content-Type: application/ssml+xml
         X-Microsoft-OutputFormat: riff-48khz-16bit-mono-pcm
         User-Agent: <app name>
Avatar   PUT https://eastus2.api.cognitive.microsoft.com/avatar/batchsyntheses/{id}?api-version=2024-08-01
         {"inputKind":"SSML","inputs":[{"content":"<speak …><voice name='en-US-Ava:DragonHDLatestNeural'>…</voice></speak>"}],
          "avatarConfig":{"talkingAvatarCharacter":"harry","talkingAvatarStyle":"business","videoFormat":"mp4",
                          "videoCodec":"h264","subtitleType":"none","backgroundColor":"#1B2A41FF"}}
         poll GET the same URL until status is Succeeded (about 25 s for 10 s of video), then GET outputs.result with the key header.
         properties.billingDetails reports talkingAvatarDurationSeconds and hdNeuralCharacters.
```

Avatar options: characters `harry`, `lisa`, `lori`, `max`, `meg`, `rowan`, `celine`, `nia`, `malik` (styles per character in [standard avatars](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/text-to-speech-avatar/standard-avatars)); `subtitleType: "none"` (owner rule: no embedded captions); transparent output is `videoFormat: webm`, `videoCodec: vp9`, `backgroundColor: "#00000000"`; output is 1920x1080 at 25 fps. Gestures are batch-only. Jeff avatars and four Lisa styles are deprecated and disappear in December 2026.

## 6. Test-first gate results (2026-10-29)

Every row was called from this PC with this resource's key and region. Evidence (scripts, JSON, images, clip) is under `%MEDIA_STUDIO_ROOT%\azure-gate-20261029\`; voice samples and the avatar test are under `%MEDIA_STUDIO_ROOT%\voice-cast\azure-20261029\`. "Current" is what we pay today: Deepgram Flux TTS $45 / 1M chars (Aura-2 $30, Aura-1 $15) and Nova-3 streaming $0.46 / hr; ElevenLabs v4 $80 / 1M chars (Turbo $40) and Scribe v2 $0.22 / hr; Gemini 2.5 Flash Image $0.039 ($0.0195 batch); Haiku 5.5 $0.10 / $0.50 per 1M tokens.

| Capability | Accessible | Quality | Azure vs current | Verdict |
|---|---|---|---|---|
| TTS standard neural | Yes | ASR WER 0.0 on 4 of 5 voices | $15 / 1M: cheaper | adopt |
| TTS HD | Yes | WER 0.0 on 11 of 12 voices | $22 / 1M: cheaper | adopt |
| TTS MAI-Voice 2.1 (preview) | Yes, styles honoured | most expressive; two lines lost an opening interjection | price UNVERIFIED, budget at HD | adopt for characters |
| STT real-time | Yes | 22 of 27 clips WER 0.0 | $1.00 / hr vs $0.46: pricier | skip |
| STT fast | Yes | WER 0.0 | $0.36 / hr vs Scribe $0.22: same or pricier | fallback |
| STT batch | Yes, needs blob SAS | WER 0.0 | $0.18 / hr: cheaper | adopt for backlogs |
| Avatar, prebuilt batch | Yes | clean 1080p25, 25 s render for 10 s | $1.00 / min ($1.35 HD voice); no avatar spend today | adopt (credit-funded) |
| Image gpt-image-2.5 | Yes, 13–15 s each, 2 req/min | cinematic even at low | ≈ $0.006 low, $0.013 medium: cheaper than Gemini | adopt |
| Chat gpt-5-mini | Yes | fine | $0.25 / $2 vs Haiku $0.10 / $0.50: pricier | fallback |
| Flex gpt-5-mini | No (HTTP 400) | n/a | n/a | skip |
| Flex gpt-6-luna | Yes | fine | Azure price UNVERIFIED | confirm price first |
| Embeddings | Yes | n/a | $0.022 vs $0.02: same | adopt (credit-funded) |
| Sora 2 | Yes, 4 s 720p with audio in 55 s | good, slightly soft | $0.10 / s | skip (ends 2026-11-02) |
| Document Intelligence Read | Yes | exact text | $1.50 / 1K pages | adopt |
| Personal / professional voice | Project create works (201); consent and voice create untested | n/a | $24 / 1M chars + storage; pro training about $520 | needs Limited Access approval |

Measured costs: avatar 10.5 s ≈ $0.23, Sora 4 s ≈ $0.40, 27 voice samples ≈ $0.05, STT checks ≈ $0.04, images ≈ $0.02.

### Image quota request (draft, not filed)

Image quota is RPM-based per model (eastus2 usage 2026-10-29: `gpt-image-2.5-flare` 2 of 2, `gpt-image-2.5-sunburst` 2 of 2, `gpt-image-2` 2, `gpt-image-1.5` 9, `gpt-image-1-mini` 4). Draft for https://aka.ms/oai/stuquotarequest: subscription `4e123a95-c99f-4816-81ba-8adc55583cfe` (MCPP), resource `aoai-mrender-4e123a95`, region eastus2, model `gpt-image-2.5-flare` and `gpt-image-2.5-sunburst`, deployment type Global Standard, requested rate 30 requests/min each, use case: batch generation of cinematic still frames for product films. Approved quota is added on top of the tier. Submitting it is an external communication; the owner or a session he names files it.

## 7. Sources

Microsoft Learn: [speech regions](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/regions), [text to speech](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/text-to-speech), [quotas and limits](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits), [Foundry model availability](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability). Pricing: [Speech](https://azure.microsoft.com/en-us/pricing/details/speech/), [Azure OpenAI](https://azure.microsoft.com/en-us/pricing/details/azure-openai/), [Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices). Re-check before any large job; prices, retirements and preview status move.
