# Creative-media routing: value before model choice
Verified against public Runware, AssemblyAI and ElevenLabs docs, 2026-11-10.
This is a **planning and quote** reference. It does not unfreeze a provider,
grant spend approval, establish remaining credits, or add a runtime adapter.
Authoritative lane statuses are in `policy/provider-routing.json`.
Always honor `skills/generate/references/content-controls.md`.

## Responsibilities, not a universal generation provider

- **AssemblyAI** is primarily a source-audio and encoded-film *understanding*
  lane: transcript, word timestamps, speaker diarization, keyterms, code-switching,
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

## 2026-11-10 candidate shortlist (discovery hints, NOT permanent defaults)

Current public docs and example base prices (always re-quote exact settings):

| Need | Candidate/AIR | Indicative price | Use after approval |
| --- | --- | --- | --- |
| Fast illustrative design | Recraft V4.1 Flash `recraft:v4.1@flash` | ~$0.007/image | Cheap visual concepts and environmental plates. |
| Better image detail/edits | Qwen-Image-3.0 `alibaba:qwen-image@3.0` | ~$0.03/image | Branded story stills when capture/kit cannot express them. |
| Cheap 5s motion draft | MiniMax H3 Max Turbo `minimax:h3@max-turbo` | ~$0.025/s (480p); ~$0.04/s (768p) | B-roll only; grade motion, artifacts, consistency. |
| Reference-rich motion | P-Video-2-Pro `prunaai:p-video@2-pro` | ~$0.01/s in a published cost tier | Use reference inputs/last frames when needed; quote actual recipe. |
| Long/reference-heavy hero video | Wan3.0 `alibaba:wan@3.0` | ~$0.05/s (480p) or higher for more resolution | Only when the story needs the extra controls. |
| Speech voice candidate | Fish Audio S2.1 Pro `fishaudio:s2.1@pro` | ~$0.015/1,000 UTF-8 bytes | Candidate, frozen until governed adapter. |
| Reusable instrumental bed | MiniMax Music 2.6 `minimax:music@2.6` | ~$0.15/generation | Candidate, frozen; reuse accepted track. |
| Optional concept 3D | TRELLIS.2 `microsoft:trellis-2@4b` | ~$0.0077 at published 512 setting | Image-to-3D only; normally unnecessary for SaaS reels. |

These example rates are **not** guarantees of pricing, output quality, or
feature availability. The live `index.json` and each `schema.json` take
precedence; inspect reference restrictions, output types and any model
deprecation before proposing it. Higher fidelity may cost more. A 3D model
is not a replacement for a clear SVG architecture diagram.

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
  and transitions; approved narration; if a *non-claim* emotional still is
  truly needed, first quote Runware Recraft, then optionally a higher-grade
  image model. No need for video or 3D generation by default.
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
- AssemblyAI rates: https://www.assemblyai.com/pricing/
- AssemblyAI Universal-3.5 Pro: https://www.assemblyai.com/docs/pre-recorded-audio/universal-3-5-pro
- ElevenLabs models: https://elevenlabs.io/docs/overview/intro
- ElevenLabs API rates: https://elevenlabs.io/pricing/api
- ElevenLabs music: https://elevenlabs.io/docs/overview/capabilities/music
- ElevenLabs effects: https://elevenlabs.io/docs/overview/capabilities/sound-effects
- ElevenLabs image/video: https://elevenlabs.io/docs/overview/capabilities/image-video
