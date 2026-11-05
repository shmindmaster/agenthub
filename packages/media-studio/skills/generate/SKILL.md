---
name: generate
description: Produces accepted narration, character takes, stills and presenter clips under spend controls. Use when a job needs voices, TTS, images, a music bed, transcription or a provider choice. Not for mixing or encoding; use compose.
---

# Generate

Work from locked inputs. Viewer-facing jobs need `narration.md` or the screenplay, `storyboard.json`, `visual-bible.json` and `direction.json`; a missing file goes back to `video`. Do not invent a plate the director did not call.

Hash each input (voice, style, SSML, format) and reuse an accepted take or plate on a match. Never re-voice audio that passed, and do not rerun a job for one scene. Write only to the external job workspace. Never copy generated plates, audio, prompts or helpers into a product repository.

## Routing

Azure first, cheapest option that passes QA. Escalate only the item that failed. Default, then escape hatch:

- Narration: Azure standard neural; Neural HD or Dragon HD Omni for principals, then Deepgram for a line that failed a gate.
- Take ASR: `cloud-ai.mjs align` on Azure fast transcription; `--provider assemblyai` only when a job names it.
- Stills: `gpt-image-2.5-flare`, low then medium; `gpt-image-2.5-sunburst` premium, Gemini Batch volume.
- Hero video: approved shots only; Remotion or Recast composition.
- Transcription, presenter clip, script review: routing table in `references/takes-and-plates.md`.

Paid speech runs only through a governed adapter. A connector, SDK sample or raw REST call is ungoverned, even for one line. ElevenLabs speech runs only for an owner-authorized job, through `scripts/elevenlabs_cli.py` and an immutable manifest naming the exact voice and job workspace; without one it stays blocked. ElevenLabs sound effects, music and STT stay disabled. Higgsfield and Runway credits are frozen until the owner approves. Local AI is off. Use `AZURE_OPENAI_*` and `FOUNDRY_*` only while the endpoint host is `mt-foundary-resource` (MahumTech); never use `AZURE_OPENAI_PNDH_*`, `aif-pndh-*` or any `pndh` host (Pendoah client infrastructure).

## Voice

Cast one distinct, expressive voice per character, and honour each beat's `direction.register` with a style the voice supports. No Sarosh voice clone: the adapter's owner manifest is the only exception, and it exists per job, never by default. Every line passes the take loop; re-render a failure on the next tier. Speaker similarity is advisory; never fail, block or re-voice on it. Pauses are edit silence, not padded TTS. Never estimate word timing.

## Music and pictures

Viewer-facing jobs supply the directed `musicCue: bed` unless `intent: draft` or `music: none`. Music and sound effects come only from accepted, licensed assets; a missing one is a blocker to report, not a gap to fill.

Honour `refuse`: never product UI, metrics or testimonials. Never animate a product screenshot. Bind each plate, with its price basis, in the generation record, and report tier, rate, quantity and source.

## References

- `references/takes-and-plates.md`: Read when running the take loop or supplying a music cue or plate.
- `references/azure.md`: Read when planning any generation: deployments, prices, voice cast and craft, take QA.
- `references/content-controls.md`: Read when about to make any paid call, or a call is blocked or failed.
- `references/provider-plugins.md`: Read when choosing a provider beyond Azure.
- `../capture/references/abacare-lexicon.json`: Read when pronouncing ABACare film names.
