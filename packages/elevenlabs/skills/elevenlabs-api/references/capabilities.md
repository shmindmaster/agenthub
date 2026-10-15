# ElevenLabs capability map

Governed-mode constraint: this is a provider capability catalog, not permission
to generate. Only the shared CLI REST TTS adapter currently enforces metering.
Other paid rows remain disabled until a shared adapter exists. Native Flows,
SDKs and specialist skills must not bypass this restriction. Read
`packages/media-studio/skills/media-studio/references/content-controls.md`.


Load only the row needed. This is a routing map, not an account entitlement or
successful-execution claim. Discover current tool/node schemas in the selected
workspace; consult official API documentation for repository integrations.

| Need | Preferred surface | Checks / specialist |
| --- | --- | --- |
| Single voice, dialogue, streaming speech, timing | Native speech / Flows TTS; shared CLI single-voice fallback | `elevenlabs-tts`; live models, exact voice, clone readiness, dictionaries, output tier |
| Transcription, diarization, realtime ASR, alignment | Official STT/speech-engine tools or API | `elevenlabs-stt`; explicit cloud approval for audio, local route for private evidence |
| Music, composition plans, edits, stems, video-to-music | Native music / Flows; official music skill | Duration, model-specific metering, instrumental/vocal choice; reuse accepted stems |
| SFX, loops, audio effects | Native SFX / audio-effects node | Duration and prompt scope; avoid rerunning full tracks for one effect |
| Image generation, transforms, references | Native Flows image-generation / image-transform | Current region/model list, aspect ratio, resolution, reference permissions |
| Video, image-to-video, lipsync, enhancement, avatars | Native Flows video-generation and supported nodes | Per-model schema, duration, inputs, cost; avatar node may list no available model |
| Dubbing audio/video, translations, edits | Native dubbing nodes or official dubbing skill/API | Languages, speakers, rights, output timestamps; API versions and enterprise edit access differ |
| Existing clone, voice design/remix, voice changer/isolation | Native voice tools and official specialist skills | Existing voice discovery first; design/save creates state, verification/enrollment requires authority |
| Studio, audiobooks, podcasts/GenFM, Audio Native | Native Studio/UI or documented Studio API | API access may be separately gated; project creation is not delivery |
| Flows composition and media editing | Native composition graph | Create once, connect typed ports, run only necessary nodes, poll run IDs, reuse assets |
| Conversational agents, Speech Engine, tools/procedures, KB, tests, telephony | Official ElevenLabs Agents/Architect skills and native agent tools | Inspect agent first, isolate changes/tests, explicit authority for launches/calls/config mutations |

Native Flows exposes provider model catalogs beyond ElevenLabs' own models.
Do not assume every advertised model, output format or operation is included in
the same subscription or API key. UI, OAuth MCP and REST access are independent
evidence; record each as checked-success, checked-denied or unchecked.

For native generation, discover node types before selecting a model, create a
single flow, add/reuse nodes and references, generate a small preview, then poll
the returned run ID. Inspect results before downstream composition. Never upload
private references merely because the connector offers an upload tool.

Sources (refresh when used):
- [Native creative MCP](https://elevenlabs.io/blog/introducing-voice-music-image-and-video-generation-in-the-elevenlabs-mcp)
- [Hosted MCP setup](https://elevenlabs.io/mcp)
- [Official specialist skills](https://github.com/elevenlabs/skills)
- [API reference](https://elevenlabs.io/docs/api-reference/introduction)
- [Studio API information](https://elevenlabs.io/docs/api-reference/studio-api-information)
