# Narration preflight

Begin here for new recorded narration in any Media Studio project. Reuse accepted
audio. Keep explicitly approved voices and provider restrictions on existing
jobs. Eligible AssemblyAI stock voices are the first choice for long-form
narration, including a script marked long-form or one with 1,200 or more words.
For short scripts, use the least expensive eligible quoted option. Keep voice,
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
first-party stock voice in the requested data zone. Custom voices require their
own consent and approved adapter.

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
node scripts/narration-preflight.mjs quote job-script.json funding.json > narration-quote.json
```

Use the installed `_shared/tools/narration-preflight.mjs` when the host loads a
loose skill rather than a package checkout. A quote without the funding file
still checks public rates and accessible model/voice metadata and reports
unknown funding. The command issues read-only requests and quotes AssemblyAI,
Deepgram Flux and OpenAI Realtime. Keep rate evidence separate from spendable
funds, and estimated use separate from billed use. Dashboard records are
point-in-time observations. Recheck shared balances before additional jobs.

## Synthesize

After the owner authorizes the exact job, save an approval JSON with `entity`,
the printed `quoteSha256`, `maxUsd` and `ownerApproval` (the actual approval).
The runner rechecks the current rate and funding before posting any text.

```text
node scripts/narration-preflight.mjs execute job-script.json funding.json narration-quote.json approval.json voice/assemblyai
```

Use one output directory per approved script. WAVs and receipts follow the
spoken order. Output hashes support reuse. A submitted request with missing or
invalid output stays fenced for billing reconciliation. Review pronunciation and
speaker continuity, then align or obtain word timing using the accepted output.

- **AssemblyAI** groups adjacent text from the same speaker and voice within
  the 5,000 Unicode-code-point limit. This is complete-text HTTP synthesis at
  the normal per-character price.
- **Deepgram Flux** uses the existing governed `deepgram_cli.py` complete-text
  batch endpoint. Group by speaker, preserve cut boundaries, keep each request
  within that adapter's 2,000-character cap and honor its UTF-8-byte
  reservation. Keep the separate governed authorization and receipt checks.
- **OpenAI Realtime speech** uses the existing speech adapter at the verified
  standard endpoint rates. Its speech requests have no OpenAI Batch API discount.
- **ElevenLabs** remains an explicit job-specific lane. Reconcile the selected
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
