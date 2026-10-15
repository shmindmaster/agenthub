---
name: elevenlabs-tts
description: Use when approved text needs ElevenLabs speech with existing voices, live clone readiness, bounded credits and exact-artifact validation.
---

# ElevenLabs speech

Load `elevenlabs-api` for provider routing. Prefer the host's existing ElevenLabs
speech tool and its live schema. For Sarosh, load `sarosh-audio-voice` first:
use his explicitly approved existing hosted clone when compatible; preserve local
fallback and the mandatory speaker-identity gate. Never substitute a generic voice,
upload private recordings, replace a clone or perform verification by inference.

Read credits with `elevenlabs-account-health`. Select the exact existing voice
from the intended workspace; inspect readiness on the requested model. A missing
professional-clone model state is unknown readiness and blocks that combination.
Choose a ready model explicitly rather than silently changing speaker or model.

## API fallback

The shared CLI owns the provider request and authentication for this fallback;
media callers own segments, timing, cache and composition. It lives at
`packages/elevenlabs/scripts/elevenlabs_cli.py` in AgentHub; loose skills do not
ship the scripts directory.

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli tts --voice-id <id> --model-id <ready-model> --text "Approved preview." --output <new-take.mp3> --max-credits 100 --dry-run
# After a successful preflight, repeat without --dry-run to generate.
```

Every TTS call checks subscription, remaining quota, live model rate and
professional-clone readiness before POST. `--max-credits` limits the estimate;
the provider's final metering may differ. Unknown rates stop the adapter.
`--dry-run` performs only GET requests and writes no artifact. Existing take or
receipt paths are refused. Generation writes a hash-bound `.provenance.json`.

The general default is `ELEVENLABS_MODEL_TTS_DEFAULT` or `eleven_v4`; always pass
a verified compatible model for a professional clone. Output format defaults to
`ELEVENLABS_OUTPUT_FORMAT` or `mp3_44100_192`; check tier support first.

Run `tts --help` for voice settings, normalization, seed, language, output format,
dictionary locators and stitching. Maximum three dictionary locators, and three
neighbor request IDs per side. Never combine previous text with previous request
IDs, or next text with next request IDs. Persist the returned `request_id`.
Controls vary by model: a successful API response does not prove a setting had an
audible effect. Use model-supported direction and a short listening comparison.

Keep the canonical script unchanged; pronunciation belongs in the dictionary
layer. Validate transcript, names/numbers, pacing and technical integrity. Owner
speech also passes local identity checks on selected sources and exact encoded
delivery spans. Generated audio is not an identity pass or owner approval.
