# Cost, latency and reuse

Apply this when selecting a provider or planning a paid creative job. Prices,
entitlements and model IDs are live facts: inspect the selected account and
official docs rather than embedding a permanent cheapest-provider ranking.

## Choose an adequate route

| Work | Decision |
| --- | --- |
| Unchanged accepted media or text | Reuse the exact validated artifact; remux/re-edit instead of regenerating. |
| Text, extraction, classification, code, planning | Use the current host or an already-authorized adequate Local-AI, Anthropic, OpenAI or DeepSeek route. Bound context, output and tool loops; use stronger models only where the task needs them. |
| Owner speech | Load sarosh-audio-voice. Use local speech when adequate; the existing hosted clone is permitted when its quality or delivery benefit justifies credits. Both require integrity, ASR and artifact gates; speaker identity is advisory only (never fail, block or re-voice on it). |
| Speech/STT, music, SFX, images, video | Select a real modality-capable endpoint. Prefer adequate local generation or accepted assets; compare live hosted cost, queue time and quality. General LLM availability is not media generation entitlement. |
| Private/regulated source material | Keep the established local/privacy route. A cost saving never authorizes disclosure. |

Local inference has startup, hardware and queue costs. Reuse an already-warm model
for compatible work, avoid reload thrash, and respect the local one-GPU-job rule.
Do not start a local chat model to write career/proposal material; its standing
evidence-first writing workflow still applies. An API key being set does not
prove a working subscription, free credits or a cost ceiling.

## Spend deliberately

- Record provider/workspace, model, modality, current rate/unit, estimated whole-job
  cost, maximum attempts, preview budget and total budget before generation.
  Prefer the cheapest ready model/settings that meet acceptance criteria. Reuse
  a representative accepted preview; do not generate another simply to check health.
- ElevenLabs API/website/model metering can differ. Read live model multipliers;
  Flash/Turbo can cost less than premium speech, but verify clone readiness and
  quality. The shared TTS CLI requires a positive finite `--max-credits` for POST,
  refuses unknown rates/quota and checks the output destination before spending.
  Its mandatory broker reserves that integer maximum atomically against one
  lifetime local ceiling shared across cooperating agents, jobs and credentials.
  Unset ceilings deny purchases. Unknown billing holds the entire reservation;
  verified provider history settles actual credits. No automatic reset is used.
  A provider overrun freezes new spend, but cannot impose a provider-side invoice
  ceiling on unrestricted clients.
- Account `character_limit - character_count` is the current API allowance
  remaining. Do not call that limit the base monthly grant: it can include
  rollover/adjustments. Record reset time; rollover composition/expiry is unknown
  unless the account exposes it. Do not turn on overages, buy credits or upgrade.
- Do not pad narration, generate multiple high-resolution candidates by default,
  re-render a whole sequence for one bad take, or benchmark paid providers merely
  to establish availability. Upgrade resolution/duration only after acceptance.

## Economical feature choices (recheck at use)

| Feature | Initial candidate and escalation |
| --- | --- |
| Hosted TTS | `eleven_v4_turbo` is a value candidate where the endpoint and voice are compatible: listed $0.04/1K characters versus v4 $0.08. v4's premium needs a task-specific fidelity/expression benefit. A catalog entry alone proves neither endpoint nor professional-clone readiness. |
| Existing professional clone | Require a ready model state. If v4/Turbo readiness is absent, use a ready economical Flash model or adequate local speech; never silently enroll/retrain or switch speaker. |
| Offline transcription | Scribe v2 listed $0.22/hour versus realtime $0.39/hour. Pay for realtime only when immediacy matters. Offline keyterms/editing add $0.05/$0.07 per hour; realtime adds $0.08/$0.12. Private audio stays local. |
| Dubbing | v1 listed $0.33/source minute with watermark, $0.50 without; v2 $2.20. Select v2 for required performance/language/fidelity, checking rights, watermark and acceptance. |
| Music / processing / SFX | Music listed $0.15/minute; isolator/changer $0.12/minute. SFX pricing labels minutes but included quantities say generations: resolve units in the selected account/quote before estimating. |

The new API pricing page bills in dollars; an existing account may still expose
a legacy credit allowance. Do not convert its remaining credits into these
dollar rates, minutes or hours without its actual billing contract. Published
rates are not the account's invoice or a measured quality ranking. SFX units
conflict even within the public pricing page; fail closed on unsupported quotes.
Vendor latency claims exclude application/network and whole-job latency.
v4 Turbo is documented for both REST Text to Speech and the Text to Dialogue
WebSocket; the shared CLI implements only REST (including `--with-timestamps`).
A live catalog entry alone does not establish compatibility with a wrapper. Use
the matching documented endpoint/schema and retain success evidence; do not
substitute a model ID blindly or claim every model implemented.

## Batch and prompt cache

- OpenAI and Anthropic offer discounted asynchronous batch processing for supported
  requests. Use it for independent work whose deadline permits the completion
  window; compare current endpoint/model/region terms. A local loop, concurrent
  calls or a single long TTS request is not a billing-discount batch.
- Prompt caching reuses a stable prefix, not arbitrary similar wording. Put stable
  instructions/tools/reference material before variable input, preserve ordering,
  respect tenant/privacy boundaries, and use current model-specific cache controls.
  Do not add filler just to reach a cache threshold.
- OpenAI cache write/read pricing and retention vary by model generation. Count
  cached input and cache writes from usage; do not assume every cache write is free.
  Anthropic has distinct cache-write and cache-read charges; batch/cache discounts
  may combine, but asynchronous cache hits are not guaranteed. DeepSeek documents
  automatic prefix caching and separate hit/miss pricing; verify live model terms.
- Record actual uncached/cached/write/output tokens, retries, wall time and billed
  cost. Claim savings against the same completed workload and quality bar, not a
  theoretical maximum discount. Warm local models and fetched-schema reuse reduce
  latency; they do not create hosted billing discounts.

## Exact asset reuse and recovery

Key by provider/workspace, input hash, model/version, voice/version, every setting,
pronunciation dictionary/version, reference hash, neighboring context/stitch IDs,
seed, normalization, language and output format. Reuse only matching bytes with
their output hash and successful applicable quality receipts. Model or dictionary
changes invalidate the key; an equal seed alone does not establish identical audio.
Keep private caches scoped to their authorized workspace, on the machine.

Deduplicate identical queued/in-flight requests before submission. Retain the
provider request/run ID; poll or retrieve its existing result after a timeout.
Never blindly retry a paid POST. The shared CLI automatically retrieves exact
pending/accepted bytes, deduplicates workers and refuses existing output/receipt
paths. Pending content still needs QA. Expired submitted leases retain their
reservation and block resubmission. Recovery uses the saved request ID and exact
provider history, never prompt similarity. See
`packages/media-studio/skills/media-studio/references/content-controls.md`.
For an intact historical recovery epoch, `packages/elevenlabs/scripts/elevenlabs_cli.py
reconcile --namespace <original-namespace> --cache-workspace <original-workspace>
--cache-key <saved-request-key> --history-id <saved-history-id> --recovery-epoch-manifest <absolute-original-manifest>`
selects the existing epoch under the canonical runtime recovery-epochs directory.
It requires the byte-identical persisted authorization, original ledger and
32-byte namespace salt, matching workspace/key HMAC, unchanged ceiling and saved
receipt. Missing, linked or mismatched accounting fails closed; this route never
initializes or replaces accounting. Provider requests are GET-only and must match
both saved request ID and history item ID. Unknown billing retains the full
reservation. Recovery or settlement preserves historical authorization and does
not authorize another generation or change its generation policy. Omit the
selector to reconcile the primary ledger as before.
Native connectors and unsupported paid endpoints remain disabled in governed
mode. Provider batch and token prompt-cache discounts are not implemented by
this asset broker; do not infer invoiced savings from fixture tests.

## Official references (checked October 14, 2026)

- OpenAI: https://developers.openai.com/api/docs/guides/batch and
  https://developers.openai.com/api/docs/guides/prompt-caching
- Anthropic: https://platform.claude.com/docs/en/about-claude/pricing and
  https://platform.claude.com/docs/en/build-with-claude/batch-processing
- DeepSeek: https://api-docs.deepseek.com/guides/kv_cache/ and
  https://api-docs.deepseek.com/quick_start/pricing/
- ElevenLabs: https://elevenlabs.io/docs/overview/administration/billing and
  https://elevenlabs.io/docs/overview/models and https://elevenlabs.io/pricing/api
