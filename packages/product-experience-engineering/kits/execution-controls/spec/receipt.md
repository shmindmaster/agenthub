# Receipt and replay — `receipt/v1`

A receipt records one consequential step well enough to explain it later and
to replay it: what went in, which engine and revisions ran, what evidence it
used, and what came out. It holds hashes and ids, never prompt text, document
text or personal data, so a receipt can be shown on screen, exported and
emitted to telemetry without leaking anything.

Reference implementations: [`../ts/receipt.ts`](../ts/receipt.ts),
[`../ts/otel-genai.ts`](../ts/otel-genai.ts) and their Python twins. Both must
reproduce [`../vectors/receipts.json`](../vectors/receipts.json), including the
span attributes. Hashing is the canonical form in
[approval-capsule.md §1](approval-capsule.md#1-canonical-form-and-hash).

## 1. Fields

| Field | Required | Meaning |
|---|---|---|
| `receiptVersion` | yes | `"receipt/v1"` |
| `receiptId`, `tenantId`, `occurredAt` | yes | `occurredAt` is when the step finished |
| `durationMs` | no | Integer milliseconds |
| `kind` | yes | `model_call`, `rule_check`, `retrieval`, `tool_call`, `decision` |
| `engine` | yes | `model`, `rules`, `model+rules`, `human`. Shown in the UI as the engine badge; deterministic checks say `rules` |
| `subject` | no | `{ type, id, revision }`, same shape as the capsule |
| `input` | yes | `{ hash, promptName?, promptRevision?, policyRevision?, rulePackRevision? }`: hash of the exact input and the revisions that shaped it |
| `retrieval` | no | `{ dataSourceId?, queryHash, topK?, documents: [{ id, hash, revision?, score? }] }`; scores are strings. An object without a `documents` key (for example `{}`) is absent: no `retrievalHash`, no part in the `replayKey`, in both languages. `documents: []` is a retrieval that found nothing and is hashed |
| `retrievalHash` | derived | Canonical hash of `retrieval`; omitted when `retrieval` is absent |
| `model` | no | `{ provider, requestModel, responseModel?, operation?, responseId?, finishReasons?, usage?: { inputTokens, outputTokens, cacheReadInputTokens, cacheWriteInputTokens } }` |
| `tool` | no | `{ name, callId? }` |
| `evidence` | no | `[{ ref, hash, span?: { start, end } }]`: the exact sources the output relied on |
| `outcome` | yes | `{ status: succeeded \| failed \| refused \| fallback, code?, outputHash?, fallbackEngine? }` |
| `approval` | no | `{ capsuleId, proposalHash, decision, actorId }` for `decision` receipts |
| `trace` | no | `{ traceId, spanId }` of the emitting span |
| `replayKey` | derived | Canonical hash of `{ kind, engine, input, retrievalHash, requestModel, tool }` |
| `prevReceiptHash` | derived | `receiptHash` of the previous receipt in the chain, or `null` |
| `receiptHash` | derived | Canonical hash of every other field |

Absent optional fields are omitted, never `null`: `createReceipt` removes
`null` and `undefined` at every depth of its input, in both languages.

Failures are receipts too. A model call that times out is a `failed` receipt
with `code: "timeout"`; the rule-based answer that replaced it is a
`rule_check` receipt with `status: "fallback"`. The demo shows both. Nothing is
simulated.

## 2. Chain

Receipts for one subject (or one run) form a hash chain through
`prevReceiptHash`, like an append-only hash-chained ledger. `verifyChain` reports the first
receipt whose hash fails (`receipt_hash`) or whose link fails (`chain_link`).

A chain is verified from a known head: `verifyChain(receipts, expectedPrev)`
(`verify_chain(receipts, expected_prev)`) requires the first receipt's
`prevReceiptHash` to equal `expectedPrev`, which is `null` for a chain that
starts at its beginning and the previous receipt's `receiptHash` for a slice.
A forged first link, or a chain whose head was dropped, fails with
`chain_link` at index 0. Dropping receipts from the tail leaves a valid
chain, so tail truncation is only detectable against an external anchor: the
latest `receiptHash` held somewhere the chain's writer cannot edit (a
separate table, a log line, a signed checkpoint).

Store receipts append-only. A Receipt Explorer renders the chain and lets a
viewer change one byte and watch verification fail at that receipt.

## 3. Replay

Two receipts with the same `replayKey` ran the same step on the same inputs
with the same revisions and model. `compareReplay(original, replay)` reports
`sameStep` and `sameOutput`. A replay with a new prompt revision or model has a
different key by construction, so "what changed" is always answerable.

## 4. OpenTelemetry

`receiptSpan` maps a receipt to one span using the OpenTelemetry GenAI
semantic conventions (now maintained at
`github.com/open-telemetry/semantic-conventions-genai`; checked 2026-10-14).
`emitReceiptSpan(tracer, receipt)` sends it through any `@opentelemetry/api`
tracer (TypeScript) or `opentelemetry-api` tracer (Python).

| Receipt | Span name | Attributes |
|---|---|---|
| `model_call` | `{operation} {requestModel}`, kind CLIENT | `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.response.model`, `gen_ai.response.id`, `gen_ai.response.finish_reasons`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `gen_ai.usage.cache_read.input_tokens`, `gen_ai.usage.cache_write.input_tokens`, `gen_ai.prompt.name`, `gen_ai.prompt.version` |
| `retrieval` | `retrieval {dataSourceId}`, kind CLIENT | `gen_ai.operation.name=retrieval`, `gen_ai.data_source.id`, `gen_ai.retrieval.top_k` |
| `tool_call` | `execute_tool {name}` | `gen_ai.operation.name=execute_tool`, `gen_ai.tool.name`, `gen_ai.tool.call.id` |
| `rule_check`, `decision` | `rule_check`, `decision` | No `gen_ai.*`: these are not GenAI operations |

Every span also carries `app.receipt.id`, `.hash`, `.kind`, `.engine`,
`.replay_key`, `.outcome`, `.input_hash`, `.output_hash`, `.policy_revision`,
`.rule_pack_revision`, `.retrieval_hash`, `.fallback_engine`, `app.tenant.id`
and, for decisions, `app.approval.capsule_id`, `.proposal_hash`, `.decision`.
A `failed` receipt sets span status ERROR and `error.type` to the outcome code.

Use `gen_ai.provider.name`, not the retired `gen_ai.system`, and never put an
orchestration framework's name where the provider belongs. Content attributes (`gen_ai.input.messages`,
`gen_ai.output.messages`, `gen_ai.system_instructions`,
`gen_ai.retrieval.query.text`, tool arguments and results) are never emitted:
prompts are trade-secret and content may be personal data.

## 5. Mapping existing records

| Existing record | Maps to |
|---|---|
| Hash-chained ledger entry `{seq, kind, actor, subject, payload, payload_sha256, prev_sha256, sha256}` | `prevReceiptHash`/`receiptHash` chain; `payload_sha256` → `input.hash`; its kinds → `kind` |
| Rule-engine change receipt kept in a JSON column on the record | `rule_check` receipt, `engine: rules`, `input.rulePackRevision`, changed inputs hashed into `input.hash` |
| Per-review token usage and a `source_model` column on decisions | `model_call` receipt per review, `decision` receipt per resolve |
| Append-only sign-off attestations bound to a snapshot hash | `decision` receipt with `subject.revision` = snapshot hash |
