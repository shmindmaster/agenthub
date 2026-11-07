---
name: generate
description: Produces accepted narration, character takes, stills and presenter clips under spend controls. Use when a job needs voices, TTS, images, a music bed, transcription or a provider choice. Not for mixing or encoding; use compose.
---

# Generate

Work from locked inputs. Viewer-facing jobs need `narration.md` or the screenplay, `storyboard.json`, `visual-bible.json` and `direction.json`; a missing file goes back to `video`. Do not invent a plate the director did not call.

Hash each input (voice, style, SSML, format) and reuse an accepted take or plate on a match. Never re-voice audio that passed, and do not rerun a job for one scene. Write only to the external job workspace. Never copy generated plates, audio, prompts or helpers into a product repository.

## Routing

Azure first, cheapest option that passes QA. Escalate only the item that failed. Default, then escape hatch:

- Narration follows `references/voice-recipes.md`. Governed film voices are GA DragonHD Ava, Andrew, Emma2 and Andrew2.
- Take ASR: `cloud-ai.mjs align` on Azure fast transcription; `--provider assemblyai` only when a job names it.
- Stills: `gpt-image-2.5-flare`, low then medium; `gpt-image-2.5-sunburst` premium, Gemini Batch volume.
- Hero video: approved shots only; Remotion or Recast composition.
- Transcription, presenter clip, script review: routing table in `references/takes-and-plates.md`.

Paid speech runs only through a governed adapter. A connector, SDK sample or raw REST call is ungoverned, even for one line. The direct ElevenLabs account and API are excluded from these recipes. ElevenLabs sound effects, music and STT stay disabled. Higgsfield and Runway credits are frozen until the owner approves. Local AI is off. Use `AZURE_OPENAI_*` and `FOUNDRY_*` only while the endpoint host is `mt-foundary-resource` (MahumTech); never use `AZURE_OPENAI_PNDH_*`, `aif-pndh-*` or any `pndh` host (Pendoah client infrastructure).

## Voice

Use each beat's `direction.register` to guide the performance. Pass style controls only where the governed voice supports them, and shape the rest with script phrasing and edit silence.

Use `references/voice-recipes.md` to select one voice per film or series. For new walkthroughs choose DragonHD Emma2 or Andrew2, with Ava as fallback. The Azure Speech adapter takes no style argument for these voices. Use governed Deepgram batch synthesis with Haley for prepared support prompts. The reference distinguishes callable choices from gated candidates, including Azure OpenAI Marin for directed narration. Reuse accepted takes. If the governed route cannot run, deliver the cut silent with the lines on screen. Desktop speech and HeyGen stock avatar voices are forbidden at every stage. No Sarosh voice clone. Each new line passes the take loop. Speaker similarity is advisory. Add pauses in the edit and use measured word timing.

## Music and pictures

Viewer-facing jobs supply the directed `musicCue: bed` unless `intent: draft` or `music: none`. Music and sound effects come only from accepted, licensed assets; a missing one is a blocker to report, not a gap to fill.

Honour `refuse`: never product UI, metrics or testimonials. Never animate a product screenshot. Bind each plate, with its price basis, in the generation record, and report tier, rate, quantity and source.

## References

- `references/takes-and-plates.md`: Read when running the take loop or supplying a music cue or plate.
- `references/voice-recipes.md`: Read when choosing a voice. It records the six recipes and the supported Microsoft voice and control pairs, with GA or preview where the page states it.
- `references/azure.md`: Read when planning any generation: deployments, prices, the callable speech adapter, and take QA.
- `references/content-controls.md`: Read when about to make any paid call, or a call is blocked or failed.
- `references/provider-plugins.md`: Read when choosing a provider beyond Azure.
- `scripts/route_media.py --catalog`: Run first when planning any generation; it prints every lane, scripted or by hand, with mode, cost and how.
- `references/stills.md`: Read when a scene needs a generated photograph: quote, lanes, cache, ledger.
- `references/irukadark.md`: Read when a scene needs a generated clip (approved hero shot) or a by-hand picture or track from IrukaDark.
- `../capture/references/abacare-lexicon.json`: Read when pronouncing ABACare film names.
