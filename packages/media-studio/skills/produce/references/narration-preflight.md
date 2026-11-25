# Narration preflight

Begin here for new recorded narration in any Media Studio project. Reuse accepted
audio. Keep explicitly approved voices and provider restrictions on existing
jobs. Stock (non-cloned) voices default to eligible Deepgram Flux (`flux-sienna-en`
or `flux-haley-en`) for every entity except ABACare, personal films included. ABACare scripts
(`"entity": "abacare"`) use AssemblyAI on ABACare credit and name a voice on every
turn: cast the clones, Syeda F. Abidi for marketing, parent-facing, social and
general product films, Sarosh for technical and business ones. If that voice cannot run, the quote
picks nothing; report the blocker and never swap in a stock voice. Outside ABACare,
AssemblyAI is chosen only when the script names it (`"provider": "assemblyai"`),
because the owner asked for it in that job. Elsewhere, when the default
is ineligible, the least expensive eligible quoted option wins. Keep voice,
region, performance and timing requirements ahead of list price.

## Check and quote before submitting

Save a JSON file in the job workspace with the exact locked turns. Use the
account and entity approved for the job.

```json
{
  "entity": "personal",
  "longForm": true,
  "region": "us",
  "language": "english",
  "turns": [
    { "speaker": "host", "text": "Start with the decision." },
    { "speaker": "host", "text": "Then show the supporting evidence." }
  ]
}
```

Multiple speakers need an explicit cast for each eligible provider, such as
`"voices": {"assemblyai": "aai-jane"}` on each turn. Set `explicitCast`
to require a cast for all turns in a single-speaker job. A turn with `voices` is limited to its listed choices. Set `keepSeparate` on turns with
independent timing, and `requiresDirection` or `requiresLinkedDialogue` when
the performance depends on it. The AssemblyAI runner verifies an active
first-party stock voice in the requested data zone. Private AssemblyAI owner voices require an explicit job `privateVoiceApprovals` entry with `voice`, matching `entity`, and `ownerApproval`, plus a matching explicit cast on each turn, for example `"voices": {"assemblyai": "sarosh-hussain"}`. `ownerApproval` quotes the owner's request for this job. Only the named owner-approved voices are eligible for ABACare or personal films. The adapter rechecks the provider voice is private, active, in the requested zone, and has current attested consent and unexpired retention before quote and execution.

Use the provider's dashboard to check spendable funds for **this TTS workload**
when its API does not expose that balance. Free transcription credits and
outstanding invoices cannot fund this check. The funding file is an operator
record, kept locally with the job. For each provider, record these fields:

- `entity`, matching the script.
- `source` set to `dashboard`, with an `observedAt` ISO UTC timestamp within
  the last 24 hours.
- `availableUsd`, the spendable USD balance observed for this workload.
- `credentialSha256`, from the command below using the same runtime key.
- For Deepgram credentials with multiple projects, add `projectId` matching
  the checked project.

```text
node scripts/narration-preflight.mjs fingerprint assemblyai
node scripts/narration-preflight.mjs quote job-script.json funding.json voice/assemblyai > narration-quote.json
```

Use the installed `_shared/tools/narration-preflight.mjs` when the host loads a
loose skill rather than a package checkout. A quote without the funding file
still checks public rates and accessible model/voice metadata and reports
unknown funding. The command issues read-only requests and quotes AssemblyAI,
Deepgram Flux and OpenAI Realtime. Keep rate evidence separate from spendable
funds, and estimated use separate from billed use. Dashboard records are
point-in-time observations. Recheck shared balances before additional jobs.
If the CLI reports an interrupted local ledger, run
`node scripts/narration-preflight.mjs recover-ledgers voice/assemblyai`.
This checks existing local ledgers and allows SQLite to roll back an unfinished
write while preserving committed reservations. It does not contact providers.
On renewal, include the existing AssemblyAI output directory. Only missing
takes count against current funding (`remainingUsd`). The total (`estimatedUsd`)
includes prior verified reservations and remains the amount the job cap covers.
The quote only reads prior audio and receipts. An unresolved submission or an
output directory tied to another script or credential makes that directory ineligible.

## Synthesize

After the owner authorizes the exact job, save an approval JSON with `entity`,
the printed `quoteSha256`, `maxUsd`, `outputDir` and `ownerApproval` (the actual approval). Bind the output path to the approved job.
The runner rechecks the current rate and funding before posting any text.

```text
node scripts/narration-preflight.mjs execute job-script.json funding.json narration-quote.json approval.json voice/assemblyai
```

Use Node 22.13 or later and one local output directory per approved script.
Keep the durable `assemblyai-submissions.sqlite3` journal with the job. WAVs and receipts follow the
spoken order. Output hashes support reuse. A submitted request with missing or
invalid output stays fenced for billing reconciliation. The submission marker
records the model, voice, time and character count. The response receipt keeps
the provider request ID and status when received. Use the request ID or the
timestamp, model, voice and character count to reconcile with the provider.
Keep the submission fenced while billing or audio is unresolved. Review pronunciation and
speaker continuity, then align or obtain word timing using the accepted output.

- **AssemblyAI** groups adjacent text from the same speaker and voice within
  the 5,000 Unicode-code-point limit. This is complete-text HTTP synthesis at
  the normal per-character price.
- **Deepgram Flux** uses the existing governed `deepgram_cli.py` complete-text
  batch endpoint. Group by speaker, preserve cut boundaries, keep each request
  within that adapter's 2,000-character cap and honor its UTF-8-byte
  reservation. Selection also checks the adapter's remaining local ledger
  capacity. Keep the separate governed authorization and receipt checks.
- **OpenAI Realtime speech** uses the existing speech adapter at the verified
  standard endpoint rates. Its speech requests have no OpenAI Batch API discount.
  Standalone marketing runs the same pricing and funding checks before any
  new OpenAI voice requests, using the Windows user credential when configured.
- **ElevenLabs** remains an explicit job-specific lane. Use `inspect-elevenlabs model-id` for a read-only check of the live speech multiplier and subscription balance. Reconcile the selected
  model and endpoint against provider history and the actual subscription
  balance. Show an observed estimate separately from the ledger's reservation
  ceiling. Preserve prior approvals and receipts.

Public sources: [AssemblyAI models and rates](https://www.assemblyai.com/docs/getting-started/models),
[AssemblyAI speech limits](https://www.assemblyai.com/docs/tts/api-reference/http-api/create-speech),
[AssemblyAI dashboard billing](https://www.assemblyai.com/docs/billing-and-pricing),
[Deepgram rates](https://deepgram.com/product/text-to-speech),
[Deepgram Flux batch](https://developers.deepgram.com/reference/speak/v-2/audio/generate),
[OpenAI Realtime rates](https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini),
[OpenAI Batch model and endpoint support](https://developers.openai.com/api/docs/guides/batch).
