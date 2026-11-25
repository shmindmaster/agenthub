# Hosted AI steps and Runware stills

Renders run on Daytona (`skills/finish/references/render-lanes.md`), never on this PC.

## Hosted AI steps: cloud-ai.mjs

```
node cloud-ai.mjs align  --take <take.wav> --script <locked-script.txt> --out voice/align/<id>.json   # or qa/encoded-alignment.json
node cloud-ai.mjs review --files <script.md> [...] --rubric <text|file> --threshold 85 --out review.json
node cloud-ai.mjs qa     --images <contact-sheet.jpg> [...] --prompt <context> --out qa.json [--client]
```

* **align**: Azure fast transcription (sh-speech F0 by default; `--provider azure-s0|deepgram|assemblyai` only when named) word times, anchored token by
  token to the locked script. Exact matches keep the acoustic onset. Numbers, currency, contractions and hyphenated
  compounds are matched by spoken form. A word the ASR heard differently gets a precisionLimited onset bounded by
  its neighbours. The report is `cloud-speech/script-alignment/1` with method **`asr-anchored-alignment`**, on the
  native 80 ms grid with take/script SHA-256 binding and an `agreement` block. It is not forced alignment: the
  picture, cue-sheet, word-sync and release gates refuse it unless the job opts in with
  `job.json` `"clockPolicy": { "allowAsrAnchored": true }`. Even then the sync gate re-checks at least 90% exact
  onsets and no precisionLimited run over 6. Without the opt-in, treat it as a cross-check. A report below those limits is written to `<out>.failed.json`, never to `--out`, and the command exits 1.
  * Measured 2026-10-26 against the forced aligner retired with Local AI (historical comparison): exact-word onsets agreed to a median of 0–80 ms, p90 80 ms.
  * Coverage: 214/232 exact on an 89 s narration, and 100% on two lab takes.
  * Word-sync: offset 0 ms and drift 0 ms.
* **review / qa**: Anthropic (latest Opus) only by default. There is no automatic fallback to a different paid
  provider: exhausted credit, an auth failure or a free-tier quota refusal stops with the blocker named, and
  `--provider azure-openai|gemini|openai` must be passed to use another (Azure OpenAI is `gpt-6-luna` by default, or `gpt-6.1-sol`, on
  resource `mt-foundary-resource`, Entra auth, key auth disabled). Rate-limit retries stay on the same provider. `--client` material never goes to Anthropic and
  defaults to Azure OpenAI in the owner's tenant. The report has score 0–100, pass, findings with fixes, provider,
  model and usage. Exit 0 means pass.
* **Deadlines**: a model or speech call is cut off after 300 s plus the time its upload needs at 2 Mbit/s, body included. A call that times out
  (or returns HTTP 504 or 524) stops as `timed out` and is not sent again, because the provider may still finish and charge for it:
  check its usage before rerunning. For review and qa, other 429 and 5xx answers are retried twice, waiting at most 20 s whatever `retry-after` says.
* `--provider azure-openai` reads `%LOCALAPPDATA%\AgentHub\media-studio\cloud-render.json`:
  `{ "subscriptionId": "<id>", "azureOpenAI": { "endpoint": "https://<account>.cognitiveservices.azure.com/", "deployment": "gpt-6-luna" } }`.
* Keys are read by name from the environment, then the Windows user environment, and are never printed.

### Synthetic Runware training stills

`cloud-ai.mjs illustration --provider runware` is separate from product capture and produces
one or more **illustrative** stills, never a published training asset. It supports only
`runware:z-image@0` and synthetic source material. Product repositories remain read-only
media inputs; put the private input JSON and synthetic source file in `MEDIA_STUDIO_ROOT`
(or `%LOCALAPPDATA%\AgentHub\media-studio`). The adapter snapshots and hashes the source,
records the source revision, objective, scope, prompt/config hashes and cost estimate, and
stores downloaded PNGs by content hash in that workspace. New job directories are private
to the local owner and SYSTEM on Windows, or mode `0700` on POSIX. If the Windows ACL
cannot be restricted, preparation fails before copying the source. Maintain those OS
permissions and a private workspace parent; the adapter cannot secure pre-existing
parent directories or distinguish people using the same OS account. A local job
identifier is not an authorization credential.
Acceptance is blocked until every requested result has been safely retrieved or rejected;
a batch with missing, unsafe, expired or failed results cannot produce an accepted asset.

The private input for `--action prepare` supplies `provider`, `model`,
`region: "provider-managed"`, `scope` (`tenant`,
`project`), `source` (`id`, `version`, `sha256`, `objective`, `rights: "synthetic"`, and
absolute `file`), `prompt`, `width`, `height`, `steps`, `numberResults`, `ttlSeconds`,
`revision`, future `retainUntil`, and `estimate` (`usd`, `basis`). The SHA-256 must match
the source file. The result gives the job `id` and `taskUUID`; preparing the same request
reuses that job. The fixed Runware endpoint has no established geographic residency
guarantee; the adapter does not switch regions or providers.

For `submit`, another private JSON file supplies `id`, `scope`, the current source
`version` and `sha256`, and an explicit `maxEstimatedUsd`. Set `RUNWARE_API_KEY` in the
server environment; it is not accepted from the input file. The ceiling admits an
**estimate**, not a guaranteed provider charge: this model is billed by compute time.
The adapter records `includeCost` results when the provider supplies them, including
unusable outputs. `reportedOutputCostSumUsd` sums those returned fields and
`allOutputCostsReported` only indicates that each requested output had a cost; neither
is a reconciliation against the provider's bill. Submit persists its task identity
before the single paid request.
After a timeout, use `resume` with `id` and `scope` to poll the same `taskUUID`; never
resubmit automatically. `status` and `cancel` take the same fields. Local cancellation
does not cancel the provider charge. Status distinguishes queued, generating,
downloading and partial work from assets available for review.

`review` takes those fields plus the current `source`, `imageSha256`, `reviewer`, and
`decision`. Acceptance also requires `altText`, `textEquivalent`, and `checklist` values
of `true` for `sequence`, `ppe`, `hazards`, `accessibility` and `contentSafe`. Rejection
requires `reason`. Review is bound to the downloaded bytes and current selected source;
it is not a product assignment, identity verification or safety certification. A newer
job selection, changed source, missing file or modified hash prevents acceptance.
The CLI omits review text and the estimate basis from status output; authorized callers
can inspect the private job manifest when the full evidence is needed.
The local scope check prevents accidental cross-job access; it is not an enterprise
authorization service. Product systems must separately authenticate and authorize access
and SME release.

The job records a retention deadline and refuses submission, polling and review after it;
its effective status becomes `retention-expired`. An operator can call
`purge-expired` with `id`, `scope` and `confirmExpiredDeletion: true` after that deadline
to remove the request, source snapshot and recorded owned output files; this is manual,
not a scheduled job. It retains the job's audit metadata, and does not remove the
operator-supplied source or CLI input files; the operator must manage their retention.
Provider URLs are temporary and never stored in the job manifest; an expired URL remains
an explicit failure.

**Spend bound.** Both the prepared `estimate.usd` and the submit `maxEstimatedUsd` are capped
at `$1` per job (`MAX_JOB_CEILING_USD`); a larger job requires a reviewed code change. Each
job sends at most one paid `imageInference` request; recovery only polls `getResponse`.
When provider-reported costs exceed the authorized ceiling, `cost.reportedExceedsCeiling`
is `true` in status and inventory output.

**Output inventory (consumer contract).** Every state change rewrites
`<workspace>/jobs/runware/<id>/inventory.json` (schema
`media-studio/runware-output-inventory/1`). `--action inventory` (input: `id`, `scope`)
recomputes it live and prints it with review text redacted, plus `inventoryObject`.
Fields:

* `job`: `id`, `taskUUID`, `status`, `effectiveStatus`, `selected`, `scope`, `provider`,
  `requestedModel`, `actualModel`, `region`, `promptSha256`, `configSha256`,
  `numberResults`, `retainUntil`, `createdAt`, `submittedAt`.
* `source`: `id`, `version`, `sha256`, `objective`, `rights`. `cost`: as in status.
* `complete`: every requested result has been returned and none is still downloading.
* `outputs[]`: one row per provider result, including unsafe, failed, expired, rejected
  and purged ones: `index`, `imageUUID`, `status`, `sha256`, `bytes`, `mediaType`,
  `width`, `height`, `storageObject` (path relative to the workspace, `/`-separated),
  `costUsd`, `providerSafety`, `error`, `review`.
* `approved[]`: only `accepted` outputs of a job that is still the current selection,
  within retention and not canceled, failed or purged: `sha256`, `storageObject`, `bytes`,
  `mediaType`, `width`, `height`, `altText`, `textEquivalent`, `reviewer`, `reviewedAt`.

A consumer (for example Empowera SH-3721) imports only `approved[]`, re-hashes each
`storageObject` and rejects any mismatch, checks `source.version`/`source.sha256` against
the SOP revision it is attaching to, and still applies its own SME release. A superseding
job rewrites the old job's inventory with `selected: false` and an empty `approved[]`;
consumers should prefer the live `inventory` action over a cached file.
No live Runware request or entitlement check is implied by installing this adapter.
