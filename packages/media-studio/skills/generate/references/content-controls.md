# Content controls

Paid speech runs only through a governed adapter, which reserves the maximum in the shared spend record before calling the provider. A connector, SDK example, provider UI or raw REST call is ungoverned, even for one line.

| Provider | Adapter | Bucket | Caps |
|---|---|---|---|
| Azure TTS | `scripts/governed_azure_speech.py` | `azure-speech/usd-micros`, per workspace under `%LOCALAPPDATA%/AgentHub/runtime/azure-speech-jobs` | `azure-speech-new-provider-job` $1. `azure-speech-bounded-standard-job` at most 150,000 microdollars. Extension at most $0.69 inside the $1 |
| Deepgram Flux Sienna TTS | `scripts/deepgram_cli.py` | `deepgram/usd-micros` under `%LOCALAPPDATA%/AgentHub/runtime/content-controls` | No budget row means disabled. Recovery epoch at most $3 |
| ElevenLabs | None | `elevenlabs/credits` | Blocked. `kit/marketing/lib/providers/elevenlabs.mjs` fails closed until `MVG_ELEVENLABS_CLI` names a governed adapter |

Disabled: speech-to-text adapters, sound effects, music, avatar submission, voice fallback, automatic retry. `cloud-ai.mjs align` is outside the spend record, so report it. On Codex, `scripts/content_host_controls.py --apply` blocks the ElevenLabs app; it needs a new session.

## Quote, then execute

Deepgram, up to 2,000 characters at 45 microdollars per UTF-8 byte. Offline quote:

`python scripts/deepgram_cli.py --text-file <f> --workspace <w> --revision <r> --dictionary-revision <d> --expressivity <0-1>`

Add `--execute --output <absent.wav> --receipt <absent.json>` after approval.

Azure: `quote()` returns `cache_key` and `maximum_usd_micros`. The owner's immutable manifest lists `allowed_cache_keys` (1 to 128). Then call `generate(text, authorization_manifest=..., use_sdk=True, ...)`. An exact repeat reuses stored audio free.

`python scripts/content_control.py status` shows ceilings and commitments. `configure` and `freeze` are owner steps. Never raise a ceiling to get a request through. Expired price policies (`VALID_THROUGH`, `PRICE_VALID_THROUGH`) fail closed.

## Blocked or failed call

Stop and report the stage and `cache_key`. A failure, including HTTP 429, keeps the full reservation and fences that request. Do not retry, change `--revision`, edit the database, or switch provider. The one release is `content_control.py release-prepared` for an expired reservation that never submitted. `generate_manual_retake` allows two owner-granted Azure replacements. Missing `ledger.sqlite3` or `namespace-salt`: restore both together, never start fresh. A recovery epoch needs an owner manifest (`_epoch_policy` in `governed_deepgram.py`).

## Accept

Generated audio stays `pending`. `python scripts/content_control.py accept --namespace <n> --cache-key <k> --manifest <private-gates.json>`. Required gates are `content`, `pronunciation`, `listening` and `artifact`, each with `pass`, `output_sha256`, `evidence_path`, `evidence_sha256` and `reviewer`. `identity` is advisory. Never write a pass for an unrun check.
