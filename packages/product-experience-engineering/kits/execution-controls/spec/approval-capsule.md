# Approval capsule — `approval-capsule/v1`

An approval capsule binds one proposed change to the exact thing a person
reviewed. If anything the reviewer saw changes before the decision lands, the
decision is refused. The decision, the change and the audit row are written
together, and a repeated decision changes nothing.

Ported from five working implementations surveyed in October 2026: a
row-locked compare-and-swap that answers `409 stale_proposal`; a
`sha256:`-prefixed canonical payload hash with typed denials; an idempotent
replay of the same decision; a snapshot-bound sign-off over append-only
attestations; and a content-addressed, single-use authorization. None of them
blocked self-approval; this spec does by default.

Reference implementations: [`../ts/approval-capsule.ts`](../ts/approval-capsule.ts)
and [`../python/execution_controls/approval_capsule.py`](../python/execution_controls/approval_capsule.py).
Both must pass [`../vectors/approval-cases.json`](../vectors/approval-cases.json).

## 1. Canonical form and hash

Every hash in this kit is `sha256:` followed by 64 lowercase hex characters,
computed over the canonical JSON of a value:

- RFC 8785 (JCS) ordering: object keys sorted by UTF-16 code units, no
  insignificant whitespace, strings escaped as `JSON.stringify` does, UTF-8.
- Integers only, within ±(2^53 − 1). Non-integer numbers are refused; money,
  scores and ratios are strings (`"120.00"`, `"0.91"`).
- Timestamps are ISO 8601 strings in UTC with a `Z` suffix.
- An absent optional field is omitted, never `null`. A `null` inside the
  payload is data and is hashed.
- Lone surrogates, non-string keys, NaN and infinities are refused.

Vectors: [`../vectors/canonical-json.json`](../vectors/canonical-json.json).

## 2. Proposal

A proposal is what an agent, a rule or a person asks to change.

| Field | Required | Meaning |
|---|---|---|
| `capsuleVersion` | yes | `"approval-capsule/v1"` |
| `capsuleId` | yes | Stable id of this proposal |
| `tenantId` | yes | Tenant that owns the subject |
| `subject` | yes | `{ type, id, revision }`: the record the change applies to and the revision it was computed from. `revision` is an integer or an opaque string (ETag, snapshot hash); it is compared as text |
| `action` | yes | Dotted action name, e.g. `project.status.update`, `filing.submit` |
| `payload` | yes | The exact change. What the reviewer sees is rendered from this |
| `proposedBy` | yes | `{ kind: agent \| user \| rule \| system, id }` |
| `createdAt` | yes | When it was proposed |
| `expiresAt` | no | After this instant it can no longer be approved (it can still be rejected) |
| `policyRevision` | no | Policy or rule-pack revision that produced or gates the proposal |
| `evidence` | no | `[{ ref, hash? }]` the reviewer is shown |
| `receiptId` | no | Receipt of the step that produced the proposal ([receipt.md](receipt.md)) |
| `proposalHash` | yes | Hash of every other field, with `capsuleVersion` included |

Every field is bound by the hash. A proposal is immutable once stored; a
changed proposal is a new proposal with a new `capsuleId`.

When the subject's state is broader than one row (a project plus the people
assigned to it, an accounting period's checklist and figures),
`subject.revision` is the canonical hash of that state, computed with this
kit's `canonicalHash`.

## 3. Decision request

| Field | Required | Meaning |
|---|---|---|
| `proposalHash` | yes | The hash the reviewer was shown. The UI must render the proposal from the same object it got this hash from |
| `decision` | yes | `approve` or `reject` |
| `idempotencyKey` | yes | Client-generated, unique per intended decision |
| `claimedActorId` | no | If a client sends an actor id, it is compared to the session and never trusted |
| `reason` | no | Free text; bound into the request hash |

The actor is the authenticated principal (`id`, `tenantId`, `roles`) taken
from the session. It is never read from the request body.

## 4. Decision rules

Evaluated in this order. The first failure refuses with the listed code and
HTTP status; nothing is applied.

| # | Check | Code | Status |
|---|---|---|---|
| 1 | Principal's tenant is the proposal's tenant | `capsule_not_found` | 404 |
| 2 | `claimedActorId`, if sent, equals the principal | `actor_mismatch` | 403 |
| 3 | Stored proposal still hashes to its `proposalHash` | `proposal_tampered` | 409 |
| 4 | Presented `proposalHash` equals the stored one | `proposal_hash_mismatch` | 409 |
| 5 | Principal holds one of the policy's approver roles | `actor_not_authorized` | 403 |
| 6 | Approve only: a `user` proposer is not the approver, unless the policy sets `allowSelfApproval` | `self_approval_forbidden` | 403 |
| 7 | A prior decision with this `idempotencyKey` has the same request hash | `idempotency_key_reused` | 422 |
| 8 | A prior decision on this proposal has the same decision | `already_decided` | 409 |
| 9 | Approve only: `now < expiresAt` | `proposal_expired` | 410 |
| 10 | Approve only: the subject's current revision equals `subject.revision` | `stale_proposal` | 409 |

Rules 7 and 8 return a **replay** (status 200, the original decision record,
no second side effect) when the earlier decision matches: the same key with the
same request, or the same decision under a new key or from a second approver.
Withdrawing (a proposer rejecting their own proposal), rejecting an expired
proposal and rejecting a stale proposal are allowed: rejection changes nothing.

The request hash is the canonical hash of
`{ proposalHash, decision, actorId, reason? }`.

Refusal body, for every adopter:

```json
{ "error": { "code": "stale_proposal", "message": "The record changed after this proposal was made." } }
```

## 5. Applying

The adopter does this in one database transaction:

1. Look up the proposal **scoped by tenant**; if absent, return
   `capsule_not_found` without calling `decide`. (Rule 1 is defense in depth.)
2. Lock the subject (`SELECT … FOR UPDATE`, a serializable transaction with
   retry, or a compare-and-set on the revision) and read its current revision.
3. Load prior decisions for the proposal and for the idempotency key.
4. Call `decide`.
5. On `apply`: perform the change, bump the subject revision, insert the
   decision record and the audit row. On `reject`: insert the record and the
   audit row. On `replay` or `refuse`: insert only the audit row.
6. Commit. The refusal audit row is committed even though no change was made.

Storage constraints: unique `(capsuleId)` for an applied or rejected decision,
unique `(tenantId, idempotencyKey)`, and append-only audit rows (an update or
delete trigger refuses). An in-memory "consumed"
set is not acceptable outside tests.

When the effect is asynchronous (a durable job, a filing submission), the
decision record is the single-use authorization: the worker consumes it once,
under the job's lock, and records the execution outcome as a separate receipt.

## 6. Audit row — `approval-audit/v1`

One row per `decide` call, including every refusal and replay:

`auditVersion, tenantId, capsuleId, action, subjectType, subjectId,
subjectRevision (current), presentedHash, proposalHash, decision, actorId,
idempotencyKey, outcome (applied | rejected | replayed | refused), code,
status, at`.

On `capsule_not_found` the row is written in the caller's tenant, so every
proposal-derived field is null.

## 7. Adversarial suite

[`../python/execution_controls/adversarial_suite.py`](../python/execution_controls/adversarial_suite.py)
and [`../ts/adversarial-suite.ts`](../ts/adversarial-suite.ts) run the same
cases against the product's real route through an adapter: approve applies
once, replay and re-approve apply once, a second approver replays, reject after
approve conflicts, a reused key with a different body fails, stale, tampered,
wrong hash, forged actor, other tenant, and, when they apply to the product,
wrong role (`has_viewer`), self-approval (`proposer_is_user`) and four
concurrent approvals that must apply once (`supports_concurrency`). Every
refusal must leave zero side effects and one `refused` audit row with its code.

## 8. In the product UI

The approval card shows what will change (rendered from the payload), the
subject revision it was computed against, the evidence, who or what proposed
it, the policy revision, and the hash's first 12 characters. A refusal is a
product state, not a toast: "The record changed after this proposal was made"
with a link to the new state and a way to regenerate the proposal.

## 9. Not in v1

Signatures over capsules or receipts. When added: ed25519, a key id derived
from the SHA-256 of the raw public key, rotation by key id, and a hard refusal
to sign with an ephemeral key in production (two of the surveyed
implementations fall back to one today).
