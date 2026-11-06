# Azure AI Services

Azure is the default provider. Take the cheapest tier that passes QA and escalate only the item that failed. Prices are eastus2 retail list rates unless marked measured, not a bill. Report tier, rate, quantity and price source. Re-check before a large job.

## Resource

`mt-foundary-resource` (AIServices S0, eastus2, resource group `mcpp-purchase`), billed to the MCPP partner credit.

Env vars (print set or not, never a value): `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION`, `AZURE_AI_SERVICES_ENDPOINT` (ends in `/`), `AZURE_AI_SERVICES_KEY`, `AZURE_AI_SERVICES_REGION`, `FOUNDRY_OPENAI_BASE_URL`, `AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT`, `AZURE_DOCUMENT_INTELLIGENCE_KEY`.

Use `AZURE_OPENAI_*` and `FOUNDRY_*` only while the endpoint host is `mt-foundary-resource` (MahumTech); never use `AZURE_OPENAI_PNDH_*`, `aif-pndh-*` or any `pndh` host (Pendoah client infrastructure).

## Deployments

| Use | Deployment |
|---|---|
| Chat | `gpt-6-luna`, `gpt-6.1-sol` |
| Images, 2 requests a minute per model | `gpt-image-2.5-flare` (default), `gpt-image-2.5-sunburst` (premium) |
| STT | `gpt-4o-mini-transcribe` ($0.18 / hr), `gpt-transcribe` ($0.27 / hr, quality), `gpt-4o-transcribe-diarize` |
| TTS | `gpt-4o-mini-tts` |
| Embeddings | `text-embedding-3-small`, `text-embedding-3-large-146950` |

STT must call `/openai/deployments/{name}/audio/transcriptions?api-version=2025-04-01-preview`, because the `/openai/v1` transcription route returns 404. For images, test one low-quality call at `{AZURE_AI_SERVICES_ENDPOINT}openai/deployments/{name}/images/generations` before a batch.

## Capabilities

| Need | Route | Price | Run with |
|---|---|---|---|
| Voice list, `StyleList` | `GET https://eastus2.tts.speech.microsoft.com/cognitiveservices/voices/list` | free | REST |
| Narration | Standard neural | $15 / 1M chars | adapter |
| Cinematic principals | Neural HD, Dragon HD Omni | $22 / 1M chars | adapter, Ava and Andrew only |
| Emotion per line | MAI-Voice 2.1 (preview) | no meter; budget at $22 | not in adapter |
| Take ASR, one file | Fast transcription | $0.36 / hr | `cloud-ai.mjs align` |
| Backlog | Batch transcription; private blob URL with read SAS (public URLs fail `InvalidUri`) | $0.18 / hr | REST |
| Model transcription | `gpt-4o-mini-transcribe`, `gpt-transcribe`; `gpt-4o-transcribe-diarize` for speakers, at `/openai/deployments/{name}/audio/transcriptions?api-version=2025-04-01-preview` | $0.18, $0.27 / hr | REST |
| Real-time, streaming | Deepgram Nova-3. Azure is $1 / hr | $0.46 / hr | `DEEPGRAM_API_KEY` |
| Stills | `gpt-image-2.5-flare`; `-sunburst` for premium | measured about $0.006 low, $0.013 medium per 1024x1024 | REST |
| Presenter clip | Prebuilt avatar, batch | $1 / min, $1.35 with HD voice, plus characters | not enabled |
| Script, frame review | `gpt-6-luna` on grounded input, escalate to `gpt-6.1-sol` | $0.10 / $0.50, $2 / $10 per 1M | `cloud-ai.mjs review`, `qa` with `--provider azure-openai` |
| Embeddings, OCR | `text-embedding-3-small`; Document Intelligence `prebuilt-read` | $0.022 / 1M tokens; $1.50 / 1K pages | REST |

`cloud-ai.mjs` is `kit/cloud/cloud-ai.mjs`. On a block it stops and never moves to another paid provider. `qa` and `review` default to Anthropic.

## Speech adapter

`scripts/governed_azure_speech.py` is the only narration path in this plugin. Windows Narrator, SAPI, System.Speech, OneCore (David, Zira, Mark, Eva) and any other desktop voice are forbidden, including for a rehearsal or a draft. If this adapter cannot run, deliver the cut silent with the lines on screen. Read `scripts/governed_azure_speech.md` first. Call `quote()`, then `generate(..., use_sdk=True)`, with 1 to 6,000 characters and only these voices:

- `en-US-Ava:DragonHDLatestNeural`, `en-US-Andrew:DragonHDLatestNeural`, no style.
- `en-US-JennyNeural` and `en-US-GuyNeural` with `friendly`, `en-US-AriaNeural` with `narration-professional`.

`paragraphs`, rate -10 to 0 percent and pauses of 250 to 700 ms work on standard voices only. It rejects caller XML and has no Omni, MAI, phoneme, multitalker or avatar route. Every other cast voice needs adapter support and an owner grant first. Direct REST for "just one line" is ungoverned paid speech.

## Voice cast

A human audition decides. Reuse samples first: `$MEDIA_STUDIO_ROOT/voice-cast/azure-20261029/samples/`, index `voice-cast.json` one level up.

| Role | Voices (style) |
|---|---|
| Narrator | `en-US-Steffan:DragonHDLatestNeural`, `en-GB-Harry:MAI-Voice-2.1` (`narrator`), `en-GB-Emily:MAI-Voice-2.1` |
| Hero | `en-US-Ethan:MAI-Voice-2.1` (`determined`), `en-US-Olivia:MAI-Voice-2.1` (`hopeful`) |
| Mentor | `en-US-Andrew:DragonHDLatestNeural`, `en-GB-Ollie:DragonHDLatestNeural` |
| Villain | `en-US-Ethan:MAI-Voice-2.1` (`whispering`), `en-GB-Harry:MAI-Voice-2.1` (`angry`) |
| Youth | `en-US-AnaNeural`, `en-US-Harper:MAI-Voice-2.1` (`excited`) |
| Explainer | `en-US-Ava:DragonHDLatestNeural`, `en-US-AriaNeural` (`narration-professional`) |
| Warm, deep | `en-US-Serena:DragonHDLatestNeural`, `en-US-Vance:DragonHDLatestNeural` |

## Voice craft

1. One distinct voice per character. No Sarosh clone.
2. A style per line. Dragon HD Omni and Neural HD predict style from text and take style prompts: `[excited]` cues on HD, `<mstts:express-as>` on Omni, MAI and styled standard voices.
3. Let the model infer prosody. Use SSML only for pronunciation, breaks and rate. Pronunciation comes from `scripts/pronunciation_lexicon.json` through `quote(..., pronunciations=[...])` (standard voices only; the adapter writes the `<phoneme>` markup, never the caller). Run `scripts/check_script_terms.py` on the locked script first and pass its `pin` list. HD has no `prosody`, `emphasis`, `bookmark` or `viseme`.
4. Use HD speaking styles only on voices with English as the primary language.
5. Check `StyleList` first. An unsupported style silently renders the whole element neutral.
6. A/B voices on the real script.
7. Respell names and brand terms in the synthesis input only, under a versioned `dictionary_revision`. The locked script stays the ASR reference.
8. If MAI drops an opening word or interjection, re-render that line on HD.

## Take QA

Re-render only the failing line, on the next tier.

1. `node kit/cloud/cloud-ai.mjs align --take <take.wav> --script <locked-script.txt> --out voice/align/<id>.json`. Default `azure` is the free tier on `AZURE_SPEECH_*`. `--provider azure-s0` uses `AZURE_AI_SERVICES_*`; `deepgram` and `assemblyai` run only when named. `exactRatio` under 0.9 or `longestUnmatchedRun` over 6 writes `<out>.failed.json` and exits 1.
2. Word error rate: compare `heard` with the script; no script computes it. A wrong word fails the take. Unmatched final words mean truncation.
3. `scripts/Test-SpeechIntegrity.ps1 -Path <take> -Text <line>` fails peak under -40 dB, mean under -45 dB, under 0.35 s, duration outside 0.35 to 4.5 times the 150 wpm estimate, and internal silence over 2.5 s. Pace comes from its duration fields. It does not fail clipping: treat `maxVolumeDb` at 0 as clipped (starting point).
4. Speaker similarity is advisory. Never fail or re-voice on it.
5. Use `word_boundaries` only when `alignment_status` is `AZURE_SDK_EVENTS`. Never estimate timing.

## Images

`POST {AZURE_AI_SERVICES_ENDPOINT}openai/v1/images/generations`, header `api-key`, body `{model, prompt, size, quality, n}`, result `data[0].b64_json`. Limit 2 requests/min per deployment, so queue small batches. The owner files the quota form (https://aka.ms/oai/stuquotarequest); until then Gemini Batch ($0.0195) covers volume.

## Avatar clips

Not enabled: a job needs adapter support and an owner grant. Contract: `PUT https://eastus2.api.cognitive.microsoft.com/avatar/batchsyntheses/{id}?api-version=2024-08-01`, `avatarConfig` with `harry`/`business`, `lisa`, `lori`, `max` or `meg`, `videoFormat` mp4, `videoCodec` h264, `subtitleType: none`. Input is text or SSML, not a WAV, so audio and lips come from one synthesis. 2 requests/min.

## Credit and access

- Budget alerts: `mcpp-purchase` has none. Ask the owner to set $400, $600 and $680 before heavy jobs.
- Limited Access needs an owner decision before applying: custom avatar, personal voice, professional voice, MAI instant cloning (https://aka.ms/customneural).
