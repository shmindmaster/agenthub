# execution-controls kit

Two contracts every governed-AI product in the portfolio shares, written once
and vendored into each product:

- [Approval capsule](spec/approval-capsule.md) (`approval-capsule/v1`): a
  proposed change bound to the exact payload, subject revision, tenant and
  proposer a reviewer saw; the actor comes from the session; apply is
  idempotent and locked; every outcome, refusals included, writes one audit row.
- [Receipt and replay](spec/receipt.md) (`receipt/v1`): one hash-chained,
  content-free record per consequential step (model call, rule check,
  retrieval, tool call, decision), with a replay key and an OpenTelemetry
  GenAI span mapping.

The demo-side contract lives next door in [`../demo-harness`](../demo-harness/README.md).

## Layout

| Path | What |
|---|---|
| `spec/` | Normative specs |
| `schemas/` | JSON Schemas for proposal, decision record, audit row, receipt |
| `vectors/` | Shared test vectors: canonical JSON, 30 decision cases, a receipt chain with pinned span attributes |
| `ts/` | TypeScript reference implementation (Node 22.6+ runs it directly; no dependencies) |
| `python/execution_controls/` | Python 3.11+ reference implementation (stdlib only; `opentelemetry-api` only for `emit_receipt_span`) |
| `*/adversarial-suite*` | The suite a product runs against its real approval route through an adapter |

Both implementations pass the same vectors, so a proposal hashed in a Python
service verifies in a TypeScript one, and the receipts and span attributes are
byte-identical.

## Adopting it in a product

1. Vendor one language into the product (no runtime dependency on AgentHub):

   ```bash
   node packages/product-experience-engineering/scripts/vendor-execution-controls.mjs --lang python --dest <repo>/apps/api/services/execution_controls
   node packages/product-experience-engineering/scripts/vendor-execution-controls.mjs --lang ts --dest <repo>/server/lib/execution-controls --import-ext js
   ```

   This writes the files plus `KIT_MANIFEST.json`. Add
   `vendor-execution-controls.mjs --check --dest <dir>` (or an equivalent
   hash check in the product's own test runner) so an edited copy fails.

2. Wire the approval route as [spec §5](spec/approval-capsule.md#5-applying)
   says: tenant-scoped lookup, row lock, `decide`, then apply plus record plus
   audit row in one transaction, or the audit row alone.

3. Implement the adversarial suite's adapter against the real route and run it
   in the product's tests. A route that trusts a body actor, skips the lock, or
   forgets to audit a refusal fails a named case.

4. Emit a receipt for each model call, rule check and decision, and send it
   through the product's tracer with `emitReceiptSpan` / `emit_receipt_span`.

5. Show it: the approval card renders the payload, revision, evidence and the
   hash prefix; a refusal is a product state with a way forward; the engine
   badge says `rules` when no model ran.

## Changing the kit

Change the spec, both implementations and the vectors together, run
`tests/validate-kits.ps1`, bump `KIT_VERSION` in `ts/index.ts` and
`python/execution_controls/__init__.py`, then re-vendor into each adopter.
A breaking change to a hashed shape is a new version string
(`approval-capsule/v2`), never an edit to v1.
