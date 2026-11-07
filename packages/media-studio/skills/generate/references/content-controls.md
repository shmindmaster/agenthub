# Content controls

Paid speech runs only through a governed adapter, which reserves the maximum in the shared spend record before calling the provider. A connector, SDK example, provider UI or raw REST call is ungoverned, even for one line.

| Provider | Adapter | Bucket | Caps |
|---|---|---|---|
| Azure TTS | `scripts/governed_azure_speech.py` | `azure-speech/usd-micros`, per workspace under `%LOCALAPPDATA%/AgentHub/runtime/azure-speech-jobs` | `azure-speech-new-provider-job` $1. `azure-speech-bounded-standard-job` at most 150,000 microdollars. Extension at most $0.69 inside the $1 |
| Deepgram Flux batch TTS | `scripts/deepgram_cli.py` | `deepgram/usd-micros` under `%LOCALAPPDATA%/AgentHub/runtime/content-controls` | No budget row means disabled. Recovery epoch at most $3 |
| ElevenLabs speech | `scripts/elevenlabs_cli.py` | `elevenlabs/credits`, per job under `<RuntimeRoot>/content-recovery-epochs/<epoch_id>` | Owner-authorized jobs only. With no manifest it refuses before any network call. The manifest sets the ceiling inside the limit below |

Disabled: speech-to-text adapters, sound effects, music, avatar submission, voice fallback, automatic retry. `kit/marketing/lib/providers/elevenlabs.mjs` throws on sound effects and music, and the adapter has no such command. `cloud-ai.mjs align` is outside the spend record, so report it. On Codex, `scripts/content_host_controls.py --apply` blocks the ElevenLabs app; it needs a new session.

## Quote, then execute

Deepgram, up to 2,000 characters at 45 microdollars per UTF-8 byte. Offline quote:

`python scripts/deepgram_cli.py --text-file <f> --workspace <w> --revision <r> --dictionary-revision <d> --voice flux-haley-en --expressivity 0`

Omitting `--voice` preserves `flux-sienna-en` and its existing cache keys. The selected model is included in the quote and receipt.

Add `--execute --output <absent.wav> --receipt <absent.json>` after approval.

Azure: `quote()` returns `cache_key` and `maximum_usd_micros`. The owner's immutable manifest lists `allowed_cache_keys` (1 to 128). Then call `generate(text, authorization_manifest=..., use_sdk=True, ...)`. An exact repeat reuses stored audio free.

`python scripts/content_control.py status` shows ceilings and commitments. `configure` and `freeze` are owner steps. Never raise a ceiling to get a request through. Expired price policies (`VALID_THROUGH`, `PRICE_VALID_THROUGH`) fail closed.

## ElevenLabs job

Owner-authorized only. No Sarosh voice clone stays the rule; a clone runs only for a job whose private manifest names it. There is no default voice, model or budget, and a ceiling in the default ledger authorizes nothing. Never put a real voice ID in this repository.

The manifest is a procedural control, not a security boundary. It keeps a cooperating agent on the approved request, and it stops nothing else: any process running as this user with the key could write a manifest or call the API directly.

Owner setup, once per Windows machine. The route reads the per-user registry value `HKCU\Software\AgentHub` `RuntimeRoot`, never the environment:

`reg add HKCU\Software\AgentHub /v RuntimeRoot /t REG_SZ /d <absolute-folder> /f`

Run it from a normal shell. The folder must sit outside LocalAppData and must already hold `content-recovery-epochs`. The `python.exe` alias runs Python in a virtualized view of LocalAppData, and the known-folder API returns the same path in both views, so a folder there can be two different directories depending on how Python started. With the value unset or invalid, the route refuses before any state. macOS and Linux use `.local/share/AgentHub/runtime` under the account's home directory from the user database, never `HOME`.

Then carry the old accounting over, before the first paid call. Epochs from before the pin stay where they were, and each launch route sees different ones, so run this offline step once as `py -3 scripts/elevenlabs_cli.py adopt-old-epochs` and once with the installed interpreter by its full path. It copies each visible ledger under the root, skips one already copied, and contacts no provider. A route that runs a paid call also fences on the old epochs it can see itself; an old epoch visible only to a route that never ran this step stays outside the fence.

Quote each locked line. This is offline and needs no credential or manifest:

`python scripts/elevenlabs_cli.py quote --text <t> --voice-id <v> --model-id eleven_v4 --cache-workspace <w> --cache-revision <r> --stability <0-1> --similarity-boost <0-1> --text-normalization <auto|on|off>`

Add `--previous-text`, `--next-text`, `--pronunciation-dictionary <id:version>` and `--output-format` when the job uses them; each changes the request hash. `eleven_v4` takes stability and similarity only, and the adapter refuses `--style`, `--speed` and speaker boost. `eleven_multilingual_v2` needs all three. Use plain `python`, never `python -I`.

The owner then writes two private files outside this repository, with absolute paths:

- Inventory proof: `kind` `elevenlabs-new-input-inventory`, `enumerated_scopes` (non-empty), `new_text_sha256`, `historical_text_sha256`, `ambiguous_text_sha256`.
- Manifest: `kind` `elevenlabs-owner-authorized-project-epoch-v2`, `epoch_id` (`elevenlabs-project-...`, lowercase, up to 64 characters), `workspace`, `voice_id`, `model_id` (`eleven_v4` or `eleven_multilingual_v2`), `output_format`, `request_revision`, `pronunciation_locators_sha256`, `allowed_text_sha256` (equal to the proof's new texts), `allowed_requests` (1 to 20 `text_sha256` and `request_sha256` pairs), `inventory_proof` (`path`, `sha256`), `historical_accounting` `UNKNOWN`, `historical_requests` `FENCED`, and `maximum_credits`, `owner_authorized_maximum_credits` and `owner_authorization`.

Ceiling. An `eleven_v4` manifest approves any integer from 1 to `project_limit` in `content_runtime.py`: `maximum_credits` and `owner_authorized_maximum_credits` hold that integer, and `owner_authorization` reads exactly `Approve <n> existing credits`, with commas, such as `Approve 1,000 existing credits` for 1000. An `eleven_multilingual_v2` manifest has one fixed grant: all three must equal `project_limit` and `project_approval` exactly. A correction repeats its parent's `owner_authorization`.

Check, then execute after approval. `--dry-run` makes read-only calls and writes nothing:

`python scripts/elevenlabs_cli.py tts <same flags> --output <absent.mp3> --authorization-manifest <manifest> --dry-run`

`python scripts/elevenlabs_cli.py tts <same flags> --output <absent.mp3> --authorization-manifest <manifest> --max-credits <integer>`

The first paid call copies the manifest into the epoch and creates its ledger; after that any changed byte is refused. Live overages must read as off, and a professional voice must be `fine_tuned` on the pinned model. A correction uses `elevenlabs-project-delivery-correction-v1` with a hash-bound parent, and a job pinned to `eleven_v4` stays on it.

A request hash is one purchase. Before any paid call the adapter reads every other epoch under the root, and every old epoch this launch route can see, and refuses a hash it finds there, whether purchased, unresolved or fenced, and it refuses if another epoch's accounting can't be read. A rotated key gets no second purchase of a hash in the same epoch either. A retake needs a changed request, such as a new `--cache-revision`, quoted into a new manifest. That is a new purchase, so it is an owner decision: the fence matches exact hashes and can't tell it is the same line. The check across epochs isn't atomic, so run one new epoch's first purchase at a time.

`mvg` keeps its `speech()` call. Set `MVG_ELEVENLABS_CLI` to this script in the AgentHub checkout and `MVG_ELEVENLABS_AUTHORIZATION` to the manifest. Quote with the job's workspace ID and `--cache-revision mvg-voice-v1`. For a clone, set `voice.ownerVoice` to true and state it in `voice.disclosure`: lint reads the same manifest and passes only that exact voice ID, and the delivery note says it is a clone.

After a failure, `python scripts/elevenlabs_cli.py reconcile --authorization-manifest <original-manifest> --namespace <n> --cache-workspace <w> --cache-key <k> --history-id <h>` recovers exact bytes with GET requests and settles actual credits. It needs the provider history ID and intact accounting, and never resubmits. `content_control.py status`, `accept` and `release-prepared` read only the default ledger.

Rotating the key: `reconcile` and `accept` match the key that submitted, so they refuse under a new key, and the new key can't buy that hash. Keep the old key until the job is reconciled.

Stranded credits: `reconcile` needs the request ID bound at submission. A response lost before its headers arrive leaves no receipt, so that request can't be reconciled. It stays fenced and keeps its full reservation, whether or not the provider charged. Report those credits as stranded. Never buy the request again to clear them.

## Blocked or failed call

Stop and report the stage and `cache_key`. A failure, including HTTP 429, keeps the full reservation and fences that request. Do not retry, change `--revision`, edit the database, or switch provider. The one release is `content_control.py release-prepared` for an expired reservation that never submitted. `generate_manual_retake` allows two owner-granted Azure replacements. Missing `ledger.sqlite3` or `namespace-salt`: restore both together, never start fresh. A recovery epoch needs an owner manifest (`_epoch_policy` in `governed_deepgram.py`).

## Accept

Generated audio stays `pending`. `python scripts/content_control.py accept --namespace <n> --cache-key <k> --manifest <private-gates.json>`. For an ElevenLabs job use `python scripts/elevenlabs_cli.py accept --authorization-manifest <original-manifest> --namespace <n> --cache-workspace <w> --cache-key <k> --gates <private-gates.json>`. Required gates are `content`, `pronunciation`, `listening` and `artifact`, each with `pass`, `output_sha256`, `evidence_path`, `evidence_sha256` and `reviewer`. `identity` is advisory. Never write a pass for an unrun check.
