# Takes, music and plates

## Routing table

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

## Take loop

Run this loop for every line:

```text
- [ ] Quote, then synthesize through the governed adapter
- [ ] Integrity: Test-SpeechIntegrity.ps1 (dead air, level, duration, internal silence)
- [ ] ASR: word error rate against the locked script, clipping, truncation, pace
- [ ] Names and brand terms confirmed by ASR; fix misses in the lexicon, never in the script
- [ ] Failed: re-render that line on the next tier and repeat
- [ ] Passed: record voice, tier, style and hashes in the generation record
```

Speaker similarity is advisory. Do not fail, block or re-voice on it, however low the score.

Run the integrity check with this exact command; do not change it:

```powershell
$tools = Join-Path $env:LOCALAPPDATA 'AgentHub/media-studio/_shared/tools'
if ((Get-Content "$tools/plugin.json" -Raw | ConvertFrom-Json).version -ne '2.1.3') { throw 'Speech tools are stale. Deploy the current media-studio package first.' }
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
