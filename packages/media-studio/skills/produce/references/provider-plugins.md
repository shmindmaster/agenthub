# Provider plugins

Load when choosing a provider. Before any image, video or audio generation,
name the owning entity, read its live balance and use the provider with the
most usable credit for that entity. Credits fund only their own entity;
startup credits are used before pay-as-you-go but never raise a cap. The
routing table and ledger are kept privately. Stock voices: Deepgram first,
then Azure Speech, then OpenAI TTS; ABACare films use the AssemblyAI clones.
Images: ABACare uses Runware API credit (the `generate_stills.py` default;
the private routing table may name a temporary grant first); other entities
use Azure, then OpenAI. Compare
like-for-like model **prices and outcomes**, not just provider availability.
For a current Runware candidate shortlist, use
`references/provider-cost-quality-routing.md` from the package
and `scripts/quote-runware-models.mjs` (read-only public prices).
Reuse accepted assets. A named provider runs only when a job calls for it
and its own integration, budget and authorization permits the action.
Local AI is off. Paid speech stays on a governed adapter and the shared
spend record. A plugin never bypasses them.

"None found" means checked and absent from `claude plugin list`, `codex plugin list` and the Claude official and community marketplaces. "Not established" means not checked. Key states were checked by name only.

| Provider | Capability | Claude | Codex | Other hosts | Publisher | Cost and credentials | Pick it over the default when |
|---|---|---|---|---|---|---|---|
| Azure AI Speech and Foundry | TTS, STT, images, avatar clips, embeddings, OCR. The plugin adds Azure MCP, Foundry MCP and the `azure-ai` skill | `azure@claude-plugins-official`, enabled | `azure@azure-skills`, enabled | `microsoft/azure-skills`, MIT | Microsoft | MCPP credit. `AZURE_SPEECH_KEY`, `AZURE_AI_SERVICES_KEY` set | Fallback speech after Deepgram, and the default image provider outside ABACare. Use the plugin for resource and Foundry work; speech stays on `scripts/governed_azure_speech.py` |
| AssemblyAI | TTS for ABACare films with the cloned voices (ABACare credit), or a job where the owner asks for it (consented reference recording, 60 day validity, renewable). Also source-audio transcription/second-opinion ASR (Universal-2 and Universal-3.5 Pro), word timestamps, keyterms and optional diarization, speaker identification, PII redaction; richer story-assembly analysis requires an additional adapter | `ah-assemblyai@agenthub`, enabled. Skill `ah-assemblyai:assemblyai`; hosted MCP not signed in | `ah-assemblyai@agenthub`, enabled | `packages/assemblyai/README.md` | AgentHub wrapper over AssemblyAI's hosted MCP | Billed by usage. `ASSEMBLYAI_API_KEY` not set, so `cloud-ai.mjs align --provider assemblyai` is blocked | ABACare films, or a job naming it for a clone, a transcript or a line that failed another route |
| Deepgram | Default for stock (non-cloned) voices: Flux TTS batch REST `POST /v2/speak` through the governed adapter (Flux Sienna and Haley only; Aura-2 has no governed route yet). The adapter refuses quotes once its price policy lapses; re-verify official pricing and update the policy, never bypass it. Nova-3 real-time STT. No self-serve cloning. Select Haley with `--voice flux-haley-en`; existing calls default to Sienna. Streaming TTS requires separate integration. | `deepgram@deepgram-agent-skills`, vendor marketplace `deepgram/skills` | None found | `npx skills add deepgram/skills` | Deepgram | Nova-3 $0.46 / hr, Flux $0.045 / 1,000 characters. |
| ElevenLabs | Speech (v4, v4 Turbo, Flash), Scribe v3 STT, Music v2.5, Sound Effects v3, voice changing/isolation, dubbing; image/video models require separate plan/regional eligibility. The direct account and API are excluded from new recipe defaults | Restricted connector, read-only for this plugin | None found | `npx skills add elevenlabs/skills`, MIT | ElevenLabs | `ELEVENLABS_API_KEY` set. Do not call it for a new film without that reason | Needs a written reason in the job. The Deloitte pursuit films (Revolva, Empowera, CoLedger) stay on it. Lane `elevenlabs-speech` is otherwise frozen. Historical governed jobs stay in `scripts/elevenlabs_cli.py` |
| HeyGen | HyperFrames (HTML with a paused GSAP timeline to video); HeyGen video service. Voice 1.0 Turbo is frozen and is not the presenter path. Presenter speech is Fish Laura into PVideo | `hyperframes@claude-plugins-official`, not installed | `hyperframes@openai-curated-remote`, `heygen@openai-curated-remote`, not installed | `heygen-com/hyperframes` | HeyGen | `HEYGEN_API_KEY` not set. Voice Turbo published $0.004 / 1,000 characters through Runware | A job names it for a picture. Stock avatar voices stay forbidden. Do not call Voice Turbo until `runware-heygen-voice` unfreezes. Pick HyperFrames or Remotion per job, not both |
| Runway | Video, image and audio generation | `runway-api@claude-plugins-official`, enabled; Dev MCP not signed in | `runway-api@openai-curated-remote`, not installed | `runwayml/skills` | Runway | Frozen (Runway, not Runware). `RUNWAYML_API_SECRET` not set | Only when the owner approves a spend |
| Runware | Live model catalogue across images, video, audio/music and optional 3D; existing governed image stills, experimental video route, and research-only quotes across all supported modalities. Other audio/3D generation remains frozen | Media Studio cloud adapter | Media Studio cloud adapter | `kit/cloud/cloud-ai.mjs illustration` | Runware | Startup API credit is read with API task `accountManagement/getDetails`. Runware Serverless is a separate dedicated-GPU product with its own $0 balance; its "critically low" emails do not affect API calls. Never conflate the two pools. Default ABACare image route | Only a named synthetic training job after source, estimated cost and reviewer gates; see `kit/cloud/README.md` |
| Higgsfield | Video generation | None found | None found | None found | Not established | Credits frozen | Only when the owner approves a spend |
| Remotion | Typed React composition and parametrised templates; the compose default | Official agent skills not installed: `npx skills add remotion-dev/skills`. The community plugin loads no skills | `remotion@openai-curated-remote`, enabled | `remotion-dev/skills` | Remotion | Local tool, no generation credit | Authoring a new composition (`compose` skill). Use the official skills; do not restate them |
| Descript | Optional editorial finishing | Native connector | `ah-media-studio@agenthub` plugin MCP | `descriptinc/skills`, MIT, stale | Descript | OAuth. Uses media minutes and AI credits | A job calls for finishing. Never connect both routes in one session |
| Adobe | Image, vector, design and video edits | `adobe-for-creativity@synced`, loaded | None found | `adobe/skills` | Adobe | Account sign-in. Plan cost not established | A job names an Adobe edit |
| Canva | Design, resize, brand check | `canva@synced`, loaded | `canva@openai-curated-remote`, enabled | `canva-sdks/canva-skills` | Canva | Account sign-in. Plan cost not established | A job names a Canva design or brand kit |

Left out: Together AI (`togetherai-skills@claude-plugins-official`), because its audio, image and LLM routes overlap Azure, and its video route is unassessed with `TOGETHER_API_KEY` not set.

Excluded: Codex's `aivideogenerator`, `imagetovideo` and `texttospeech`, because their publisher is not identified.
