# Creative-media routing: value before model choice
Verified against public Runware, AssemblyAI and ElevenLabs docs, 2026-11-10.
This is a **planning and quote** reference. It does not unfreeze a provider,
grant spend approval, establish remaining credits, or add a runtime adapter.
Authoritative lane statuses are in `policy/provider-routing.json`.
Always honor `skills/produce/references/content-controls.md`.

## Responsibilities, not a universal generation provider

- **AssemblyAI** is the default for eligible long-form stock synthesis after the [live narration preflight](narration-preflight.md). It also supports source-audio and encoded-film understanding: transcript, word timestamps, speaker diarization, keyterms, code-switching,
  checks that the final narration actually says what was scripted. Existing
  integration: `kit/cloud/cloud-ai.mjs align --provider assemblyai`.
  Its separate richer narrative/diarization QA is a **future integration**, not
  an automatically running stage. Useful for user-supplied recordings when
  approved and authorized; never substitute ASR confidence for a human film review.
- **Runware** is a model-marketplace/inference route for supplemental **image,
  video, audio, music, 3D** and editing. The existing `runware-image` adapter is
  real, `runware-video` has not been proven in production, and the other
  modality-specific lanes remain frozen until governed integration and spend
  approval. Do not assume models are callable merely because they are in the
  catalogue. A model's own schema defines supported input modes and constraints.
- **ElevenLabs** offers expressive speech, speech-to-text, forced alignment,
  music, effects, dubbing, voice isolation/changing, and some image/video
  workflows. Existing governed historical speech adapter is **not** blanket
  permission for new films. Direct speech, music and effects remain excluded/
  frozen until the owner explicitly changes that rule for the task. The Creative
  Image/Video API requires a suitable plan, regional availability and supported
  specific model; do not use it as a default product screen source.

## Routing order (applies to *each missing beat asset*)

1. **Story first:** start from the approved audience, pain, storyline, visual
   evidence, `viewerValue` and storyboard. For each beat identify the *reason*
   the asset is needed, not just a model or modality.
2. **No purchase when existing media solves it:** actual product recording via
   Playwright/Recast; licensed footage; charts, diagrams, Lottie/SVG, and
   Remotion/FFmpeg motion built from facts; reuse verified media and audio.
   No animated screenshot, hallucinated customer testimony or fabricated UI.
3. **Discover what's possible:** classify `image`, `video`, `speech`,
   `transcription`, `music`, `sound-effect`, `3d` or `edit`. Run
   `route_media.py --catalog` to honor local approvals, then check the
   **current** Runware models index for live IDs/capabilities. For Runware
   candidate prices use `node scripts/quote-runware-models.mjs --models
   <ids> --capability <capability> --seconds 5 --label 480p` (or `--list`).
   The quote reads `info["x-pricing"]` from each official model schema; it
   makes **no generation calls** or key requests. Some pricing is
   configuration-dependent, compute-priced or opaque: report a manual quote,
   never infer it from an unrelated model or a sample cost.
4. **Compare like-for-like:** task type, input images/references, ratio,
   resolution, output count, requested length, audio, privacy/retention,
   commercial license, source-identity requirements, latency, total expected
   price and credit expiry. Paid account credits are a subsidy, not a permission
   or a substitute for the quote.
5. **Quality floor beats price:** prefer the *cheapest capable* live model
   whose accepted samples meet the beat's goals: legible composition,
   continuity, visual truth, voice naturalness, timing, accessibility and no
   visual hallucinations. Never automatically promote the cheapest model to
   "best quality." A model with an ambiguous price is **not** a $0 option.
6. **Pre-spend consent and accounting:** check `status=ready|conditional|frozen`;
   if frozen, preserve the proposed asset but refuse the call. Show
   provider/model/AIR/version, estimated charge, per-run and cumulative
   ceiling, target entity, output artifact and exact authorization. Bound
   every request to a job workspace; no silent upgrades, retries, added
   variants or premium fallback. Reconcile the provider's actual cost receipt.
7. **Build/review:** generate only accepted assets, store prompt/model/seed,
   license, input/source hash, result hash and spend, then inspect actual
   frames/audio. Wrong visual, robotic voice, broken continuity, misleading
   claims or failed sync => reject/recut; a completed inference task does
   not constitute an accepted media asset.

## Runware shootout: target media, full cost and actual status (2026-11-10)

The **live model index** is the availability authority, not a marketing page,
example price or discount banner. Every listed figure below is a published
base rate or illustrative measured run, **not** a controlled side-by-side
quality/speed test. Never assert one model wins image fidelity without
sampling the same prompts at equal output size and comparing accepted results.

### Images and editable scene setting

| Candidate (public model ID) | Published cost and time | Best role | Limitation |
| --- | --- | --- | --- |
| `bfl-flux-3-image-klein` | ~$0.006 for 1024², ~3s measured; compute billed, not flat price | First-pass adult-office/environment stills and rapid low-cost variants | Actual runtime, resolution, steps and hardware determine cost; examine faces and hands. |
| `alibaba-qwen-image-2-1-turbo` | $0.0141/image, ~17–31s examples | Prompt-based edits, multi-reference image composition, controlled graphic ideation | Up to 10 references; not SVG/GIF output. Keep for a same-prompt quality comparator. |
| `minimax-h3-image` | ~$0.0311 typical; sample text-to-image $0.0176–$0.0189 at ~16s | Detailed cinematic still or high-resolution scene | Per-token priced; 50%-off promotion is **4K images only**, through Nov 17, 2026. Do not apply 50% to every request. |
| `minimax-h3-image-highspeed` | ~$0.0573 typical; samples ~$0.0418–$0.0743, 13–21s | When generation turnaround has measurable value | Premium image-token rates for speed; test whether the savings in edit time exceed charges. Same core parameters as H3 Image. |
| `openai-gpt-image-2-6-sunburst` | ~$0.0703 typical; examples $0.0374 GIF, $0.0431 image, $0.0634 SVG | Complex hero artwork, precise edits, specialist SVG or small GIF assets | Token billed; SVG incurs **second language-authoring charge**; GIF uses a spritesheet, up to 16 frames; neither SVG nor GIF supports referenceImages. Not normal cheap batch image. |
| `bytedance-seedream-5-5` | Advertised $0.02 up to 1.5K, $0.027 at 2K, input images and individual layers extra | Future layer-separated poster/context scene creation | **Status coming-soon** in official live index as of Nov 10; NEVER route/generate yet. Inspect `bytedance-seedream-5-0-pro` or `-flash` as separate live alternatives, without assuming identical layers/features. |
| `alibaba-qwen-image-3-0` | ~$0.03/image in published example | Higher-tier comparator, useful where another model fails typography/consistency | Not automatically better than cheaper Qwen 2.1 Turbo or Klein for the task. |

**Recommended default candidate** for *illustrative story imagery*: FLUX 3
Klein when fast/cost-effective results are accepted, with Qwen 2.1 Turbo
as a more controlled editing comparator. H3 Image and GPT-Image
Sunburst should be escalation/specialist choices. Seedream 5.5 remains
in discovery-only until Runware marks it live and its actual execution
is verified. Preserve source proofs and render all real UI via Playwright.

### SVG, GIF, layering and branded animation

- First use **hand-drawn safe SVG / Lottie / Remotion** for exact diagrams,
  icons, recurring logos, UI-adjacent typography and brand motion. This
  ensures predictable edits and is free of per-image inference charges.
- Sunburst SVG: `outputFormat: SVG` triggers an image-generation pass
  followed by a **separate SVG authoring model**, billed at that model's
  input/output rates; quote the whole two-stage recipe. It is useful only
  when a complex illustration genuinely reduces manual design time.
  Validate SVG for layout, legibility, paths, text, licensing and safety:
  remove scripts, event handlers, external fetches, embedded active
  content and untrusted references before Remotion/FFmpeg composition.
- Sunburst GIF: `outputFormat: GIF`; 2–16 frames generated as a
  spritesheet, sliced and looped. More frames reduce available per-frame
  resolution. Use for tiny non-claim motion marks or concepts, **not**
  full-screen human-video, precise product interface, or long reels.
- Sunburst SVG/GIF **cannot accept reference images** in the current
  schema. Do not promise brand-photo editing/identity consistency in
  these output modes. Output limits and cost vary with SVG author model
  and GIF frameCount/size.
- Seedream 5.5's advertised layer decomposition can add up to 99
  individually billed output layers; it is not production-ready yet.
  Editable layouts are better assembled locally with known geometry.

### Video, image-to-video and video editing

| Candidate | Published cost and run examples | Best use | Exclusion |
| --- | --- | --- | --- |
| `minimax-h3-lite` | **50% off through Dec 31, 2026:** $0.0125/s at 480p; $0.02/s at 768p; ~41s request average | First 4–8s synthetic context shots, low-cost proof of a storyboard idea | Not product UI. Audio/reference input options must be matched to the model schema. |
| `minimax-h3-highspeed` | **50% off through Dec 31, 2026:** $0.02/s at 480p, $0.03/s at 768p; ~41s mean with variable examples | Faster/better candidate for approved hero beats | Try same scene vs Lite; price alone does not establish quality. |
| `minimax-h3-max-turbo` | Published from $0.025/s (480p) | Additional visual-quality challenger for action-heavy scenes | Compare with H3 Lite/Highspeed at equal 768p and referenced input. |
| `google-gemini-omni-flash-1-2` | $0.02/s at 360p, $0.07/s at 720p, $0.10/s at 1080p; ~1m26s/request | Reference-based character/setting consistency, synced audio, edits/extension; up to 15s clips | More expensive than H3 Lite at useful resolution; no invented UI. |
| `prunaai-p-video-2-pro-replace` | **50% off through Nov 19, 2026:** $0.025/s at 480p, $0.05/s 768p, $0.06/s 1080p; ~1m52s/request | Specialist **person replacement in an existing, licensed clip**, source sound/motion maintained | NOT a text-to-video/hero generator. Human likeness/consent required, no deceptive real-customer/clinician impersonation. |
| `klingai-video-4-0-flash` | **15% off through Nov 10, 2026:** $0.0799/s at 720p without video input, $0.107/s with video input | Higher-cost motion/reference edit challenger if H3 fails | Promotion expires **today**, not a durable price. Re-quote after midnight. |
| `alibaba-wan3-0` | Published from $0.05/s (480p) | Specific advanced control where tested alternatives fail | Generally unnecessary for a 30–45s SaaS product reel. |

**Do not substitute `prunaai-p-video-2-pro-replace` for the ordinary
`prunaai-p-video-2-pro` video generator:** replacement requires existing
source footage and photo(s) of the substitute subject. Gemini Omni Flash
1.2 is a **video** generator/editor, not a still-image model or general
multimodal thinking provider.

### Very low-cost voice alternatives

| Model | Published rate | Suitable use |
| --- | --- | --- |
| `heygen-voice-1-0-turbo-free` | Free/shared limited capacity; timing and availability **not guaranteed** | Optional rehearsal and non-deadline drafts; no production SLA, never the only reliable path. |
| `heygen-voice-1-0-turbo` | $0.000004 per character ($0.004/1,000), ~11s/request example | Budget scripted short-form narration challenger if it passes audition and a governed adapter is approved. |
| `heygen-voice-1-0` | $0.00003 per character ($0.03/1,000), ~13s/request example | Voice quality/control challenger, not economical vs Turbo until audible gain is shown. |
| `fishaudio:s2.1@pro` | ~$0.015 per 1,000 UTF-8 bytes | Expressive alternative to compare with authorized Azure/ElevenLabs. |

A 400-character Turbo voice request would list at ~$0.0016 before
extras; the public/free variant is suitable only for disposable drafts.
These models support optional voice cloning; **do not clone any real
person without explicit rights and consent**. Keep the same approved
narrator across episodes. All these new Runware voice lanes remain
frozen pending a governed, budgeted adapter and a voice audition.
The existing approved Azure narration route remains the safe default.

### Audience-specific composition and creative scope

**There is no universal ABACare screen-percentage quota.** For a
verified product demo, authentic receipt-bound screens will usually
be the core of its functional proof. For a product vision, fictional
day-in-the-life film, educational dramatization, abstract animation,
future clinic, children's story or conceptual documentary, the movie
may be **100% generated**. Human scenes and synthetically composed
interfaces are not automatically "filler"; they may carry the
whole narrative. Realism, age and industry are artistic choices.

Photoreal synthetic people may include fictional adults, minors,
patients, clinicians, workers or families; characters and interfaces
may be fully legible. Do not blur or constrain them merely because
they were generated. For a sequence, choose a consistent character
design, visual bible, camera language, motion and world logic.
A speculative product UI is an *envisioned design*, not evidence
that the current shipping software performs that action; classify it
as proposed/fictional and disclose the concept status naturally at
film level when needed.

A synthetic patient is not real PHI. If the source includes real
patient/customer/employee data, require the proper permission and
provider handling independently. Real-person likenesses require
rights/consent. Character creativity is not carte blanche to make
false documentary testimonials or real-world healthcare claims.

**Model comparison scorecard** (same task, quality and output size):
1. Does the output fulfill the scene's real or envisioned creative goal?
2. Is character, setting and invented-UI continuity convincing?
3. Are typography, anatomy, interactions and framing legible and coherent?
4. Does it maintain the chosen truth/representation status?
5. What are actual rejection/retry rates and generation latency?
6. What is total accepted asset cost, including input references,
   upscales, retries, commercial rights and editing time?
7. Does a free illustration, licensed source, model-generated scene
   or current-product capture best serve *this* film's requirements?

No automatic model spend. Respect the configured provider statuses,
cost caps and permissions. Do not convert a temporary discount
into a permanent default.

### Repeatable A/B test (requires explicit paid authorization)

Using the **same three approved prompts**: (1) generic adult coordinator
at a desk noticing a work problem; (2) minimal high-contrast background
matching brand colors; (3) non-claim transition/motion scene, compare
Klein, Qwen 2.1 Turbo, H3 Image and optionally Sunburst on equal 9:16
outputs. For video, compare H3 Lite and Highspeed on the **same
accepted still** at the same resolution and duration; consider Gemini
only if continuity/native audio is needed. Measure actual provider
cost receipts, generation latency, reject/retry count and a human
storyboard/quality score. Reuse winning assets and their model/input
hashes, not a blanket provider preference. This task is research and
PR guidance only: **no inference or paid generation performed**.

## AssemblyAI: intelligibility and timing review

Preferred first pass for source audio: current Azure/Deepgram facilities if
they are already approved, then AssemblyAI when the purpose warrants it.
As of 2026-11-10, Universal-2 is listed at $0.15/hr, Universal-3.5 Pro
at $0.21/hr pre-recorded. The enhanced 3.5 Pro supports keyterms (paid
add-on), natural language prompting, diarization and language features.
Pricing depends on enabled add-ons and model. Use these functions for:
- independently transcribing user-provided stakeholder recordings;
- locating spoken claims and timestamps, checking narrative pacing and
  the script's actual spoken content against the exact encoded soundtrack;
- identifying a missing context/setup line or incomplete answer (with
  visual reviewer; ASR alone cannot know what is on screen);
- comparing high-stakes proper names/brand terms with a second transcript.

No patient/customer recordings or PHI move to AssemblyAI without
appropriate legal/contractual authorization. Do not claim a diarization
or audio-intelligence workflow exists in AgentHub unless it was executed
and documented by a new adapter.

## ElevenLabs: high-quality speech and finishing candidates

Candidate model guidance from official 2026-11-10 docs:
- `eleven_v4_turbo`: lively, low-latency voice; published API from
  ~$0.04/1,000 characters. Compare to governed Azure DragonHD for clean,
  credible B2B explanation before raising spend.
- `eleven_v4`: more expressive and deliberate actor narration; published
  ~$0.08/1,000 characters. Reserve for a voice-critical film where listeners
  prefer it, not every short ad.
- `eleven_flash_v2_5`: low-cost/high-throughput routine voice candidate.
  Preserve exact pronunciation and one narrator across a campaign.
- `scribe_v3`: independent STT/word-level timestamp candidate; published
  ~$0.20/hour. Compare accuracy and feature charges with AssemblyAI and
  Azure rather than treating it as automatically superior.
- `music_v2_5`: instrumental music or purposeful emotional build; published
  API reference from ~$0.15/minute and commercial rights depend on plan.
  Don't regenerate a bed for every cut; reuse licensed/hash-accepted stems.
- `eleven_text_to_sound_v3`: prompt-directed SFX, short purposeful cues.
  The older v2 is documented for removal March 1, 2027. Never use random
  whooshes as a substitute for a story turn.
- Dubbing/voice isolation/voice changer: specialist repair and localization
  routes, with explicit consent and voice rights. Image/video in ElevenCreative
  have separate model, regional and paid API requirements; not a fallback to
  synthesized product UI.

The direct ElevenLabs spend restrictions remain in force. New model
availability in their docs is **not** proof a governed adapter or owner
authorization exists.

## Selection examples (no provider calls implied)

- An ABACare authorization reel: **real UI** for the flagged schedule,
  authorization details and resolution; free Remotion/SVG for context
  and transitions; approved narration; if a *non-claim* emotional
  still is truly needed, compare Runware FLUX 3 Klein and Qwen 2.1
  Turbo on the identical brief before escalation to H3 Image/Sunburst.
  A 4–6s H3 Lite context shot can be justified, but no need for 3D.
- A fictionalized clinic-opening hero with a presenter: a governed voice
  candidate (Azure first; ElevenLabs if authorized and auditioned); synthetic
  reference still from Runware; an optional short generated presenter/hero
  shot only if a genuinely visual moment adds value. Capture real software
  separately for the product promise. All characters are synthetic.
- A demo cut that sounds wrong: first inspect the exact audio/captions;
  compare authored script to AssemblyAI or ElevenLabs STT (authorized);
  fix a failed line and timestamp, not the entire video. Then listen to a
  short, bounded voice audition with a governed provider before re-encoding.

## Official references

- Runware live index: https://runware.ai/docs/models/index.json
- Runware model schema: https://runware.ai/docs/models-api/model-schemas
- Runware dynamic prices: https://runware.ai/docs/models-api/pricing
- FLUX 3 Klein: https://runware.ai/docs/models/bfl-flux-3-image-klein
- Qwen Image 2.1 Turbo: https://runware.ai/docs/models/alibaba-qwen-image-2-1-turbo
- GPT Image 2.6 Sunburst SVG/GIF: https://runware.ai/docs/models/openai-gpt-image-2-6-sunburst
- Seedream 5.5 (coming-soon): https://runware.ai/docs/models/bytedance-seedream-5-5
- MiniMax H3 Lite: https://runware.ai/docs/models/minimax-h3-lite
- MiniMax H3 Highspeed: https://runware.ai/docs/models/minimax-h3-highspeed
- Gemini Omni Flash 1.2: https://runware.ai/docs/models/google-gemini-omni-flash-1-2
- P-Video Replace: https://runware.ai/docs/models/prunaai-p-video-2-pro-replace
- Kling 4.0 Flash: https://runware.ai/docs/models/klingai-video-4-0-flash
- HeyGen Turbo Free: https://runware.ai/docs/models/heygen-voice-1-0-turbo-free
- AssemblyAI rates: https://www.assemblyai.com/pricing/
- AssemblyAI Universal-3.5 Pro: https://www.assemblyai.com/docs/pre-recorded-audio/universal-3-5-pro
- ElevenLabs models: https://elevenlabs.io/docs/overview/intro
- ElevenLabs API rates: https://elevenlabs.io/pricing/api
- ElevenLabs music: https://elevenlabs.io/docs/overview/capabilities/music
- ElevenLabs effects: https://elevenlabs.io/docs/overview/capabilities/sound-effects
- ElevenLabs image/video: https://elevenlabs.io/docs/overview/capabilities/image-video
