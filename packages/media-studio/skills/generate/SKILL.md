---
name: generate
description: Produces accepted narration, character takes, stills and presenter clips under spend controls. Use when a job needs voices, TTS, images, a music bed, transcription or a provider choice. Not for mixing or encoding; use compose.
---

# Generate

Work from locked inputs. Viewer-facing jobs need `narration.md` or the screenplay, `storyboard.json`, `visual-bible.json` and `direction.json`; a missing file goes back to `video`. Do not invent a plate the director did not call.

Hash each input (voice, style, SSML, format) and reuse an accepted take or plate on a match. Never re-voice audio that passed, and do not rerun a job for one scene. Write only to the external job workspace. Never copy generated plates, audio, prompts or helpers into a product repository.

## Routing

Azure first, cheapest option that passes QA. Escalate only the item that failed.

| Need | Default | Escape hatch |
| --- | --- | --- |
| Narration | Azure standard neural | Neural HD or Dragon HD Omni for principals, then Deepgram for a line that failed a gate |
| Take ASR | `cloud-ai.mjs align` on Azure fast transcription | `--provider assemblyai` only when a job names it |
| Backlog transcription | Azure batch | `gpt-4o-mini-transcribe`; `gpt-transcribe` for quality |
| Real-time STT | Deepgram Nova-3 | None; Azure costs twice as much |
| Stills | `gpt-image-2.5-flare`, low then medium | `gpt-image-2.5-sunburst` for premium; Gemini Batch for volume |
| Presenter clip | Azure TTS avatar, batch, prebuilt | Remotion composition |
| Chat, script review | Anthropic Haiku for bulk | `gpt-6-luna` on grounded input, then `gpt-6.1-sol` |
| Hero video | Approved shots only | Remotion or Recast composition |

Paid speech runs only through a governed adapter. A connector, SDK sample or raw REST call is ungoverned, even for one line. ElevenLabs speech runs only for an owner-authorized job, through `scripts/elevenlabs_cli.py` and an immutable manifest naming the exact voice and job workspace (`references/content-controls.md`); without one it stays blocked. ElevenLabs sound effects, music and STT stay disabled. Higgsfield and Runway credits are frozen until the owner approves. Local AI is off. Never use `AZURE_OPENAI_*` or Pendoah endpoints.

## Voice

Cast one distinct, expressive voice per character from `references/azure.md`, and honour each beat's `direction.register` with a style the voice supports. No Sarosh voice clone: the adapter's owner manifest is the only exception, and it exists per job, never by default. Run this loop for every line:

```text
- [ ] Quote, then synthesize through the governed adapter
- [ ] Integrity: Test-SpeechIntegrity.ps1 (dead air, level, duration, internal silence)
- [ ] ASR: word error rate against the locked script, clipping, truncation, pace
- [ ] Names and brand terms confirmed by ASR; fix misses in the lexicon, never in the script
- [ ] Failed: re-render that line on the next tier and repeat
- [ ] Passed: record voice, tier, style and hashes in the generation record
```

Speaker similarity is advisory. Do not fail, block or re-voice on it, however low the score.

```powershell
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/_shared/tools'
if ((Get-Content "$tools/plugin.json" -Raw | ConvertFrom-Json).version -ne '2.1.2') { throw 'Speech tools are stale. Deploy the 2.1.0 package first.' }
pwsh -NoProfile -File "$tools/Test-SpeechIntegrity.ps1" -Path <take.wav> -Text '<locked line>' -JsonOut qa/integrity/<id>.json
```

Treat `pauseBeforeSeconds` and `holdAfterSeconds` as edit silence, not padded TTS. The word clock comes from `node <kit>/cloud/cloud-ai.mjs align` on accepted takes (`review`). Never estimate word timing.

## Music

Viewer-facing jobs supply the directed `musicCue: bed` unless `intent: draft` or `music: none`. Music and sound effects come from accepted, licensed assets. A beat that needs one with no accepted asset is a blocker to report, not a gap to fill.

| `sound.musicCue` | Supply |
| --- | --- |
| `bed` | Accepted bed asset |
| `sting` | Accepted sting, 2 to 4 s |
| `silence` | No music file |
| `none` | Skip |

## Pictures

For each `brollPlan` or `imagePrompts` row in `visual-bible.json`, reuse an accepted plate or generate one, and honour `refuse`: never product UI, metrics or testimonials. Stills are limited to 2 requests a minute per model, so queue small batches. Redraw only plates that fail review. Never animate a product screenshot.

Bind path, bytes, SHA-256, provider, model or voice, and price basis per beat in the generation record. An unrecorded copy into `selected/` does not count. Report tier, rate, quantity and source.

## References

| File | Read when |
| --- | --- |
| `references/azure.md` | Planning any generation: deployments, routes, prices, voice cast, voice craft, take QA |
| `references/content-controls.md` | Before any paid call: spend controls, quote and execute, a blocked or failed call |
| `references/provider-plugins.md` | Choosing a provider beyond Azure |
| `../capture/references/abacare-lexicon.json` | Pronunciation for ABACare films |
