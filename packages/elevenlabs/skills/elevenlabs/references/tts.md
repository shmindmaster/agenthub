# ElevenLabs speech

(Approved text, existing voices, live clone readiness, bounded credits, exact-artifact validation.)

Use `../SKILL.md` for cost/latency/quality routing. Once ElevenLabs is justified,
use the shared governed CLI for every paid speech request. For Sarosh, load
`sarosh-audio-voice` first: local speech is eligible when adequate; the approved
existing hosted clone is permitted when compatible and worth its cost. Speaker identity is advisory only on either route (owner direction 2026-10-27: identity is advisory only; never fail, block or re-voice on speaker similarity). Never substitute a generic voice,
replace a clone or perform verification by inference.

Read credits with `account-health.md`. Select the exact existing voice
from the intended workspace; inspect readiness on the requested model. A missing
professional-clone model state is unknown readiness and blocks that combination.
Choose a ready model explicitly rather than silently changing speaker or model.

## Shared paid route

The shared CLI owns the provider request, authentication, exact cache,
cross-process deduplication and shared reservations. Media callers own segments,
timing, quality review and composition. It lives at
`packages/elevenlabs/scripts/elevenlabs_cli.py` in AgentHub; loose skills do not
ship the scripts directory.

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli tts --voice-id <id> --model-id <ready-model> --text "Approved preview." --output <new-take.mp3> --max-credits <approved-reservation> --cache-workspace <authorized-workspace> --cache-revision <locked-revision> --stability 0.5 --similarity-boost 0.75 --style 0 --speed 1 --use-speaker-boost --text-normalization auto --dry-run
# Generate without --dry-run only within the owner-approved shared ceiling.
```

Every new purchase checks subscription, remaining quota, live model rate and
professional-clone readiness before POST. A positive integer `--max-credits`
reserves that amount atomically against the shared lifetime ceiling. Unknown
billing retains the reservation; verified history settles actual credits.
Provider metering may differ. Unknown rates stop the adapter. Exact repeats
retrieve saved bytes and acceptance state without a POST. Explicit settings and
normalization are required; dictionaries need versions. Read
`packages/media-studio/skills/media-studio/references/content-controls.md`
for budget, recovery, revision and acceptance commands. `pending` audio is for
QA and must not be delivered as accepted content.
`--dry-run` performs only GET requests and writes no artifact. Existing take or
receipt paths are refused. Generation writes a hash-bound `.provenance.json`.

Paid generation requires `--model-id` or `ELEVENLABS_MODEL_TTS_DEFAULT`; there is
no implicit paid premium-model choice. Dry-run discovery defaults to `eleven_flash_v2_5`.
`eleven_v4_turbo` runs on this REST endpoint: the official v4 launch page
(https://elevenlabs.io/v4) lists REST and streaming access, and live `/v1/models`
reported `can_do_text_to_speech` at a 0.5 multiplier on 2026-10-23. Its Text to
Dialogue WebSocket is a separate surface this adapter does not implement.
Always select a verified compatible model for a professional clone.

`--with-timestamps` posts to `/v1/text-to-speech/{voice_id}/with-timestamps`
(https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps).
It writes the decoded audio to `--output` and `<output>.alignment.json` holding
`alignment` and `normalized_alignment` (per-character start/end seconds). It uses
the same preflight, reservation and exact cache; the flag is part of the cache
key. The ledger keeps the provider's JSON body, so the receipt's `output_sha256`
is the audio file and `ledger_asset_sha256` is what acceptance binds. History
recovery returns audio only and cannot rebuild an alignment.

HTTP 429 (rate or concurrency limit) releases that request's reservation, because
nothing was generated; back off and retry the identical request. Every other
failure keeps the reservation and blocks a repeat purchase until reconciled.
For v4, the CLI accepts stability, similarity and `--clone-strength` (finite 0–1,
only for a professional voice fine-tuned on the selected v4 model). Official
October 26 guidance recommends starting at zero: lower strength permits smoother,
more flexible performance while higher strength follows training delivery more
closely. It does not establish voice readiness or guarantee an expressive result.
The CLI refuses v4 `--style`, `--speed` and speaker-boost flags instead of silently
forwarding unsupported controls. Do not use SSML breaks with v4. See
https://elevenlabs.io/docs/changelog/2026/10/26 and
https://elevenlabs.io/docs/api-reference/text-to-speech/convert.
Output format defaults to
`ELEVENLABS_OUTPUT_FORMAT` or `mp3_44100_192`; check tier support first.

Run `tts --help` for voice settings, normalization, seed, language, output format,
dictionary locators and stitching. Maximum three dictionary locators, and three
neighbor request IDs per side. Never combine previous text with previous request
IDs, or next text with next request IDs. The CLI stdout carries `ok`, `output`, `acceptance_state` and `reused`; read the provider `request_id` from the hash-bound `.provenance.json` receipt and persist it.
Controls vary by model: a successful API response does not prove a setting had an
audible effect. Use model-supported direction and a short listening comparison.

Keep the canonical script unchanged; pronunciation belongs in the dictionary
layer. Validate transcript, names/numbers, pacing and technical integrity. Owner
speech also passes the local integrity and ASR checks on selected sources and exact encoded
delivery spans. Speaker similarity may be scored for information only; it never fails,
blocks or triggers regeneration of a take. Generated audio is not owner approval.
