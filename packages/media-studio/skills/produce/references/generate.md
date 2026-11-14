# Generate

## Workflow contract

1. Use the approved storyboard, locked lines, asset register and budget.
2. Resume from accepted takes, select the governed voice recipe or eligible asset lane, and validate the receipt before accepting a new take.
3. Hand `compose` accepted assets, receipts and required timing or alignment evidence.
4. If the route is frozen, the quote is unapproved or the receipt mismatches, stop before accepting or retrying.

Work from locked inputs. Viewer-facing jobs need `narration.md` or the screenplay, `storyboard.json`, `visual-bible.json` and `direction.json`; a missing file goes back to `video`. Do not invent a plate the director did not call.

Hash each input (voice, style, SSML, format) and reuse an accepted take or plate on a match. Never re-voice audio that passed, and do not rerun a job for one scene. Write only to the external job workspace. Never copy generated plates, audio, prompts or helpers into a product repository.

## Routing

Begin with verified, reusable assets and a beat-specific quality floor; Azure
is the funded default where its governed output meets that floor. Then compare
eligible specialist providers at the **same** resolution, length and
capability. Cheapest **acceptable** result wins, not the cheapest provider
name or account credit. The legacy `route_media.py` sorts lane readiness;
it does not perform per-model economic comparison. Run
`scripts/quote-runware-models.mjs` to compare Runware candidates from
official live schemas; unquoted models stay unpriced, never silently free.
Use `references/provider-cost-quality-routing.md` for AssemblyAI,
ElevenLabs and Runware modality and model choices. Escalate only the asset
that failed. Default, then escape hatch:

- Narration follows `references/voice-recipes.md`. Governed film voices are GA DragonHD Ava, Andrew, Emma2 and Andrew2.
- Take ASR: `cloud-ai.mjs align` on Azure fast transcription; `--provider assemblyai` only when a job names it.
- Stills: existing approved Azure `gpt-image-2.5-flare` remains callable.
  Runware's proven `runware:z-image@0` remains the only model accepted by
  the current `generate_stills.py` fixed-payload adapter. For alternative
  imagery, compare **live** FLUX 3 Klein (cheap/fast), Qwen-Image-2.1-Turbo
  (reference-edit challenger), MiniMax H3 Image (detail), and GPT-Image-2.6
  Sunburst (SVG/GIF/complex artwork). Quote all from official schemas,
  verify quality, and add a model-specific governed adapter before any
  switch; Seedream 5.5 is **coming-soon** as of Nov 10, 2026.
- Supplemental video: product UI comes exclusively from genuine
  Playwright/Recast capture. For a non-claim, humanizing 4–8s office-context
  scene, compare H3 Lite vs Highspeed using the same approved synthetic
  still, duration and output resolution; Gemini Omni Flash for reference
  continuity/native audio; P-Video Replace only when replacing a person
  in an existing rights-cleared clip. Published discounts are temporary
  and must be re-quoted. All generated hero shots need an actual governed
  adapter, approval, review and Remotion/Recast/FFmpeg composition.
- Transcription, presenter clip, script review: routing table in
  `references/takes-and-plates.md`. Cheap HeyGen Voice 1.0 Turbo and
  its capacity-limited Free variant are **audition candidates**, not
  production-ready narration; ElevenLabs/AssemblyAI/Azure comparisons
  remain subject to their separate adapter and usage authorization.

Paid speech runs only through a governed adapter. A connector, SDK
sample or raw REST call is ungoverned, even for one line. AssemblyAI
can independently check source audio, transcript and word timing when a
job explicitly names that authorized route; it does not generate
video. Runware can quote image, video, audio/music and 3D from its
current live catalogue; only individually governed and authorized lanes
can generate. ElevenLabs offers high-quality expressive voice, Scribe
transcription, Music v2.5, SFX v3 and specialist editing/dubbing, but
the direct ElevenLabs account and API remain excluded from new
recipes until authorization. The governed adapter covers speech,
dialogue, sound effects and music for owner-authorized jobs;
ElevenLabs STT stays disabled. An available model, accessible API key or reported
credit is not an authorization. Higgsfield and Runway credits are frozen until the owner approves. Local AI is off. Use `AZURE_OPENAI_*` and `FOUNDRY_*` only while the endpoint host is `mt-foundary-resource` (MahumTech); never use `AZURE_OPENAI_PNDH_*`, `aif-pndh-*` or any `pndh` host (Pendoah client infrastructure).

## Voice

Use each beat's `direction.register` to guide the performance. Pass style controls only where the governed voice supports them, and shape the rest with script phrasing and edit silence.

Use `references/voice-recipes.md` to select one voice per film or series. For new walkthroughs choose DragonHD Emma2 or Andrew2, with Ava as fallback. The Azure Speech adapter takes no style argument for these voices. Use governed Deepgram batch synthesis with Haley for prepared support prompts. The reference distinguishes callable choices from gated candidates, including Azure OpenAI Marin for directed narration. Reuse accepted takes. If the governed route cannot run, deliver the cut silent with the lines on screen. Desktop speech and HeyGen stock avatar voices are forbidden at every stage. No Sarosh voice clone. Each new line passes the take loop. Speaker similarity is advisory. Add pauses in the edit and use measured word timing.

## References

- `references/takes-and-plates.md`: Read when running the take loop or supplying a music cue or plate.
- `references/voice-recipes.md`: Read when choosing a voice. It records the six recipes and the supported Microsoft voice and control pairs, with GA or preview where the page states it.
- `references/azure.md`: Read when planning any generation: deployments, prices, the callable speech adapter, and take QA.
- `references/content-controls.md`: Read when about to make any paid call, or a call is blocked or failed.
- `references/provider-plugins.md`: Read when choosing a provider beyond Azure.
- `references/provider-cost-quality-routing.md`: Read before deciding on any image, video, sound, 3D, voice or analysis model; cite current model-specific price and quality evidence. Use `scripts/quote-runware-models.mjs` for no-spend Runware model/schema quotes.
- `scripts/route_media.py --catalog`: Run first when planning any generation; it prints every lane, scripted or by hand, with mode, cost and how.
- `references/stills.md`: Read when a scene needs a generated photograph: quote, lanes, cache, ledger.
- `references/irukadark.md`: Read when a scene needs a generated clip (approved hero shot) or a by-hand picture or track from IrukaDark.
- `../capture/references/abacare-lexicon.json`: Read when pronouncing ABACare film names.

Read when executing this skill for its detailed commands and gates. [Workflow detail](generate-detail.md)
