# Voice recipes

Checked 2026-11-06 against Microsoft Learn. One voice per film or series. Reuse a take and regenerate only what changed. Do not generate audio from this page.

Direct ElevenLabs account and API are excluded. Windows Narrator, SAPI, System.Speech, OneCore (David, Zira, Mark, Eva), edge-tts, espeak, say, and HeyGen stock avatar voices are forbidden, including for a rehearsal, a draft, or an audition. HeyGen Voice 1.0 Turbo is a different, frozen speech model. It is not a stock avatar voice and it is not a recipe narrator.

Governed recipe routes are Azure Speech DragonHD (Ava, Andrew, Emma2 and Andrew2) and Deepgram Flux batch synthesis (Haley for new support prompts, Sienna for existing callers). Other recipe speech lanes require a governed adapter and current authorization. If the governed route cannot run, deliver the cut silent with the lines on screen.

Runware is the default media provider for these recipes. Runway web and API wallets are separate. Use Runway Seed Audio 1.0 only when that project is already on a verified Runway route, and the Runway lane stays frozen.

## 1. Everyday reels and social ads

Muse Image, then HeyGen Video 1.0 (1080p, five-second shots, mixed with real ABACare screen recordings). Narration is Fish Audio S2.1 Pro through Runware: voice Laura `e3cd384158934cc9a01029cd7d278634`, model `fishaudio:s2.1@pro`, normal speed, short conversational sentences, restrained emphasis, `[short pause]` between problem and benefit. One quiet instrumental, reused. Published cost $0.015 per 1,000 UTF-8 bytes (2026-11-06). Lane `runware-fish-s2` is frozen.

Example: “You opened a clinic to help families. [short pause] Scheduling, notes, and billing still need your attention. [short pause] Bring the work of running your practice together with ABACare.”

## 2. Cinematic brand films

Nano Banana 2.1 reference images, then MiniMax H3 footage. Narration is Seed Audio 1.0 through Runware, model `bytedance:seed-audio@1.0`, speed, pitch and volume `0`. Prompt an adult American female narrator: warm, grounded, confident, intimate, conversational, clean studio, no music. Add music afterward. About $0.158 per generated minute (2026-11-06). Reuse the generated narrator reference for the series. Lane `runware-seed-audio` is frozen.

For an Azure preview evaluation of expressive brand narration, shortlist `en-US-Harper:MAI-Voice-2.1`. Work in scene-sized segments and use Harper's documented `softvoice` opening, `narrator` body and `hopeful` or `relieved` close. The full and Flash models are public preview and stay outside the governed adapter. See [Microsoft's MAI voice and style catalog](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-voices).

## 3. Product demos, onboarding, feature walkthroughs

Use the actual ABACare screen recording and one short WAV narration segment per screen action. For new conversational walkthroughs select `en-US-Emma2:DragonHDLatestNeural`, or `en-US-Andrew2:DragonHDLatestNeural` for a male voice, with the existing Azure Speech authorization and no style argument. Ava remains the CLI default and fallback. Keep accepted takes and the selected voice for an existing film or series.

For directed narration, the frozen `azure-openai-tts` lane specifies Azure OpenAI `gpt-4o-mini-tts`, deployment version `2025-12-15`, with Marin. Keep delivery instructions separate from spoken text, for example “Warm, clear, and conversational. Explain one action at a time at a moderate pace.” Use Cedar only if the walkthrough needs a second speaker. This option requires a governed MahumTech adapter. The marketing kit's direct OpenAI route is separate.

Catalog, Microsoft Learn, checked 2026-11-06:

| Option | State | Use on this recipe |
| --- | --- | --- |
| `gpt-4o-mini-tts` `2025-12-15` | GA. Retirement 2027-06-15. Global Standard lists East US 2 in the Americas table (region page 2026-11-04). MahumTech is eastus2. | The walkthrough model. Voice Marin. |
| `gpt-4o-mini-tts` `2025-03-20` | Preview. Retirement date 2026-10-15 is already past. | Do not deploy. |
| Audio-out voices Alloy, Ash, Ballad, Coral, Echo, Sage, Shimmer, Verse, Marin, Cedar | Listed on the audio quickstart (2026-10-24) for the audio models. | Marin default. Cedar only as a second speaker. |
| `tts`, `tts-hd` | The Foundry models page (2026-10-29) marks both preview. An older classic retirement table called version 001 generally available. | Not this recipe. |
| `en-US-Ava:DragonHDLatestNeural` | GA DragonHD on the HD voices page. | Callable fallback. |
| `en-US-Andrew:DragonHDLatestNeural` | GA DragonHD. | Callable second Azure voice. Not the Marin substitute. |
| `en-US-Emma2:DragonHDLatestNeural`, `en-US-Andrew2:DragonHDLatestNeural` | GA, optimized for conversational content. | Governed conversational walkthrough voices. |
| Other en-US DragonHD GA personas (Adam, Alloy, Aria, Brian, Davis, Emma, Jenny, Nova, Phoebe, Serena, Steffan) | GA on the same page. | Not the adapter allowlist. |
| MAI-Voice-2.1 and MAI-Voice-2.1-Flash | Public preview, no SLA, not for production. eastus2 is a serving region. en-US managed voices: Ethan, Grant, Harper, Iris, Jasper, Olivia, Sage. Styles use `mstts:express-as`, which this adapter rejects. | Not the walkthrough and not the adapter allowlist. |

GPT Realtime 2.1, GPT Realtime 2.1 Mini, GPT Audio 1.5, GPT Live, Azure Realtime, DragonHD Flash, and multi-speaker voices are in the next section. They are not substitutes for Marin on this walkthrough, and they are not in the SSML adapter.

Sources: [model retirement schedule](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/model-retirement-schedule) (2026-11-05), [region availability](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability) (2026-11-04), [audio quickstart](https://learn.microsoft.com/en-us/azure/foundry/openai/audio-completions-quickstart) (2026-10-24), [HD voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/high-definition-voices), [MAI voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-voices) (2026-09-30).

## Supported Microsoft and Azure OpenAI combinations

Checked 2026-11-06. A row is a supported pair only when the cited page names both the model and the voice or control. A voice list the page does not print stays unassigned. None of these calls exists in `governed_azure_speech.py`. A raw REST or WebSocket call is ungoverned. Do not put a Foundry voice name (`marin`) on an Azure Speech SSML name, or an Azure Speech name on a Foundry audio-out field.

### GPT Realtime 2.1 and 2.1 Mini

The [GPT Realtime 2.1 overview](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/realtime-2) marks both models generally available. `gpt-realtime-2.1` and `gpt-realtime-2.1-mini` are version `2026-07-07`. Deployments are Global Standard and Data Zone Standard. The WebSocket is `wss://<resource>.openai.azure.com/openai/v1/realtime?model=<deployment>` with no date-based `api-version`. Audio events are headerless mono PCM16 at 24 kHz, base64-encoded. `reasoning.effort` is `minimal`, `low`, `medium`, or `high`. Response phases are `commentary` and `final_answer`. GPT Realtime 2.x does not support `truncation` on `session.update`.

Supported output voices, for both models: `alloy`, `ash`, `ballad`, `coral`, `cedar`, `echo`, `marin`, `sage`, `shimmer`, `verse`. The ABACare pair is `marin`. `cedar` is a second speaker only. These short names are not Azure Speech SSML names.

Voice Live can also run `gpt-realtime-2.1` (Pro, including `-datazone` and `-regional`) and `gpt-realtime-2.1-mini` (Standard) with an Azure TTS voice. The [how-to](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/voice-live-how-to) (updated 2026-11-04) example is `type` `azure-standard` and `name` `en-US-Ava:DragonHDLatestNeural`, with optional `temperature` for HD variability. Its speaking-rate prose limits `rate` to standard Azure TTS and custom voices, from `0.5` to `1.5`, and the example on that page also sets `rate` `1.2` on the DragonHD name. `azure-custom` stays gated. No Sarosh clone. Do not put `marin` in the `azure-standard` name.

### GPT Audio 1.5

[Microsoft Foundry](https://ai.azure.com/catalog/models/gpt-audio-1.5) lists `gpt-audio-1.5` version `2026-02-23` as GA and hosted on Azure. It is a gated candidate for directed recorded speech through audio chat completions. The catalog does not name its voices, and the [audio quickstart](https://learn.microsoft.com/en-us/azure/foundry/openai/audio-completions-quickstart) lists voices for other named models. Leave the exact voice pairing unverified, including Marin.

### GPT Live

[What is GPT-Live](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/gpt-live) (published 2026-10-13): model `gpt-live-1`, full-duplex, voice-only output. Quality is not guaranteed to match `gpt-realtime-*`. WebSocket audio is base64 raw 16 kHz or 24 kHz PCM, or 8 kHz G.711 μ-law or A-law.

The [event reference](https://learn.microsoft.com/en-us/azure/foundry/openai/gpt-live-reference) says `audio.output.voice` defaults to `marin` and is immutable after start. It does not list other allowed values. The only confirmed pair is `gpt-live-1` with `audio.output.voice` `marin`. Do not copy the Realtime voice list onto GPT Live. Instructions are immutable after start; add more with `session.instructions.append`.

For a future ABACare integration, [Microsoft documents](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/gpt-live) `delegation: { type: "client" }` in `session.start`. ABACare's backend would continue to authorize and execute delegated work through its existing reasoning and tool routing. Foundry lists `gpt-live-1` version `2026-09-10` as GA. This combination remains gated pending a governed live integration and account verification. [Foundry model catalog](https://ai.azure.com/catalog/models/gpt-live-1)

### Azure Realtime

`azure-realtime` is Microsoft's Voice Live model. It is not a Foundry `marin` deployment. The July 2026 Speech [release notes](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/releasenotes) (page published 2026-11-02) say Azure Realtime speech-to-speech is generally available as of `2026-07-25`, and Voice Live API version `2026-07-15` is generally available and the SDK default. The how-to sample still prints `api-version=2026-04-10`. The same how-to says `azure-realtime` requires API version `2026-01-01-preview` or later. Call it with `2026-07-15`.

Endpoint: `wss://<resource>.services.ai.azure.com/voice-live/realtime?api-version=2026-07-15&model=azure-realtime`. Older resources use `cognitiveservices.azure.com` on the same path. Voice object: `type` `azure-realtime-native` and `name` one of the names below. If omitted, `ava` is the default. These short names are not SSML voices. The July note's "added 12" list is a subset. The how-to table updated 2026-11-04 is the closed set (34 names).

en-US names: `ava` (default), `andrew`, `emma`. The ABACare pair is `ava`. Use `andrew` or `emma` only when that session needs a second en-US native voice. Do not send `marin`.

| Name | Locale |
| --- | --- |
| `aarti` | en-IN |
| `alvaro` | es-ES |
| `andrew` | en-US |
| `antonio` | pt-BR |
| `ava` | en-US |
| `clara` | en-CA |
| `dalia` | es-MX |
| `denise` | fr-FR |
| `diego` | it-IT |
| `diya` | hi-IN |
| `elsa` | it-IT |
| `emma` | en-US |
| `florian` | de-DE |
| `francisca` | pt-BR |
| `hyunsu` | ko-KR |
| `jorge` | es-MX |
| `keita` | ja-JP |
| `liam` | en-CA |
| `meera` | hi-IN |
| `nanami` | ja-JP |
| `natasha` | en-AU |
| `niwat` | th-TH |
| `premwadee` | th-TH |
| `rayn` | en-GB |
| `remy` | fr-FR |
| `seraphina` | de-DE |
| `sonia` | en-GB |
| `sunhi` | ko-KR |
| `sylvie` | fr-CA |
| `thierry` | fr-CA |
| `william` | en-AU |
| `xiaoxiao` | zh-CN |
| `ximena` | es-ES |
| `yunxi` | zh-CN |

### DragonHD Flash

The HD voices page lists Flash without a GA or preview column. Older Speech release notes called Dragon HD Flash preview, so lifecycle on the current table is not established. Regions on that page: `eastus`, `westeurope`, `southeastasia`, `chinanorth3`. Not eastus2. Not the Marin fallback. Not in the adapter. Flash accepts only `zh-CN` and `en-US` text.

en-US rows have no style (`—`). [Language support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts) (2026-11-01) gives the genders:

| Voice | Gender |
| --- | --- |
| `en-US-Tiana:DragonHDFlashLatestNeural` | Female |
| `en-US-Tyler:DragonHDFlashLatestNeural` | Male |
| `en-US-Jimmie:DragonHDFlashLatestNeural` | Male |

Do not send `mstts:express-as` on these three. The HD page also lists zh-CN Flash names `Xiaoxiao`, `Xiaoxiao2`, `Xiaochen`, `Xiaoyi`, `Xiaoyu`, `Xiaohan`, `Xiaoshuang`, `Xiaoyou`, `Yunxi`, `Yunyi`, `Yunxiao`, `Yunhan`, `Yunxia`, and `Yunye`, some with styles. Language support also lists `zh-CN-Xiaoke:DragonHDFlashLatestNeural`, which that HD table does not, and it prints different style sets for some shared names. ABACare does not use a zh-CN Flash style. `MAI-Voice-2-Flash` is a different public-preview model. A language-support type label of "Neural HD Flash" on an MAI row is not a DragonHD Flash voice.

### Multi-speaker

The [SSML voice page](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-voice) documents one control. Voice `en-US-MultiTalker-Ava-Andrew:DragonHDLatestNeural` (HD page status Preview) wraps turns in `mstts:dialog` and `mstts:turn`. The example speakers are only `ava` and `andrew`.

The Speech release notes say that if that LatestNeural name or `en-US-MultiTalker-Ava-Steffan:DragonHDLatestNeural` fails, use `en-US-MultiTalker-Ava-Andrew:DragonHDv1.2Neural` and `en-US-MultiTalker-Ava-Steffan:DragonHDv1.2Neural`. Ava-Steffan was announced as public preview in April 2025. Its turn speakers are not in the SSML example. Do not invent a speaker value for Steffan.

Language support (2026-11-01) also lists `en-Multitalker:DragonHDLatestNeural`, `fr-Multitalker:DragonHDLatestNeural`, and `zh-Multitalker:DragonHDLatestNeural`. Footnote 7 says the multi-talker voice is preview in East US, West Europe, and Southeast Asia, and only `en-US` content is supported. The per-speaker control for those three names was not on the SSML page. They are not in the adapter.

### DragonHD Omni

For future styled narration with caption timing, shortlist `en-us-ava:DragonHDOmniLatestNeural` with `reassuring` or `confident` direction. The [HD voice guide](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/high-definition-voices) documents expressive controls and SDK word-boundary events. A governed Omni path must capture real event timing. The current DragonHD route rejects styles, and Omni and preview podcast voices Ava3 and Andrew3 stay gated.

## 4. Talking presenters

Presenter portrait, then Fish Laura at normal speed, then PVideo 2 Pro Avatar `prunaai:p-video@2-pro-avatar`, 1080p, 20–40 seconds, about $0.06 per second (30 seconds about $1.80). Pass the exact clean audio in. No music in the speech input. Lane `runware-pvideo-avatar` is frozen. This is not a HeyGen stock avatar voice.

## 5. Reusable FAQ, help, and straightforward training

AssemblyAI-TTS-1. One stock US-English voice. Save the returned voice ID for the series. One topic per asset. Cache and regenerate only when the instructions change. $0.015 per 1,000 characters. No emotion tags, SSML, or speed parameter. Not the campaign narrator. Lane `assemblyai-tts` is frozen.

## 6. Live onboarding and support

For prepared support prompts, use governed Deepgram Flux batch synthesis with `scripts/deepgram_cli.py --voice flux-haley-en --expressivity 0` and the provider's normal speed. Omitting `--voice` keeps `flux-sienna-en` and its existing cache keys. Use one or two short sentences and one question at a time. The published rate is $0.045 per 1,000 characters. Streaming and interruption handling require a separate live integration. [Deepgram batch API](https://developers.deepgram.com/reference/speak/v-2/audio/generate)

The Microsoft live layer is named and frozen. Pick one combination from the supported-combinations section and do not mix fields across APIs:

- Turn-based, stronger reasoning: `gpt-realtime-2.1` version `2026-07-07`, voice `marin`, `reasoning.effort` `low`. Use `gpt-realtime-2.1-mini` version `2026-07-07` with the same voice when the session should stay on the smaller model. Audio is headerless mono PCM16 at 24 kHz.
- Full-duplex: `gpt-live-1` with `audio.output.voice` `marin`. One question at a time. Stop playback on interrupt. Do not set another voice.
- Microsoft Azure Realtime: model `azure-realtime`, `type` `azure-realtime-native`, `name` `ava`, API version `2026-07-15`.

Voice Live `gpt-realtime-2.1` with `azure-standard` `en-US-Ava:DragonHDLatestNeural` is a documented pair and is still not this SSML adapter. MAI-Voice-2-Flash on Voice Live (`en-US-Harper:MAI-Voice-2-Flash`, type `azure-standard`) is public preview and is not this recipe. If the callable route cannot run, leave the session silent and put the line on screen.

## Shared finishing

Music is MiniMax Music 2.6 through Runware, instrumental only, one track reused, $0.15 per clip. Lane `runware-minimax-music` is frozen. Keep speech prominent and keep speech, music, effects, and captions separate. Captions are a sidecar `.srt` only. House audio targets stay the composer targets already recorded for Linear SH-3443.
