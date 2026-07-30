---
name: product-demo-studio-qa
description: >
  Fail-closed product-video preflight, evidence extraction, four-domain independent review,
  release arbitration, least-privilege remediation, rerender, and mandatory final independent
  review and verification.
  Use after a proxy/final render or when validating truth, persuasion, screen accuracy, privacy,
  audio, captions, synchronization, accessibility, frame integrity, playback, or reproducibility.
---

## Authority and boundary

This is the canonical Product Demo Studio review/release contract. Resolve
`PRODUCT_DEMO_STUDIO_ROOT` through the router skill. Use product-local capture/render tooling; do
not copy a product runtime, data, authentication state, media, or credentials into AgentHub.

Generation agents cannot approve release. Reviewers, the arbiter, and the mandatory terminal
independent reviewer/verifier are fresh,
isolated, and read-only; each writes only its own report. Remediation agents write only the files
named in a validated assignment and cannot approve their work.

The executing host or AgentHub adapter must enforce that read-only isolation and record the
enforcement evidence. Prompt instructions and plugin-wide tool declarations are not a security
boundary. If the host cannot prove isolation from write-capable tools, stop with
`PIPELINE_BLOCKED`.

Machine `PASS` does not fabricate external-publication approval. Before any asset crosses the
external reuse boundary, a named human must complete a start-to-finish watch-through with captions
on and off, confirm synthetic data and redaction, and sign the exact publication-approval receipt
with the trusted Ed25519 private key outside the agent runtime. `check-evidence-gate.mjs` verifies
the raw detached signature against the public-key-only PEM named by
`AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY`. Agents must never create, copy, or request the private
key, and an editable name/classification in the release manifest is never approval.

## Immutable candidate and evidence package

Give every stage one immutable `candidateId`. The evidence package must conform to
`schemas/evidence-package.schema.json` and include:

- master/variant media metadata and SHA-256 checksums;
- frames, contact sheets, scene boundaries, frame-integrity, and motion reports;
- audio loudness, clipping, artifact, silence, ASR, word-timestamp, and caption-layout reports;
- OCR-visible text and values;
- browser playback, console, network, assertion, capture, and redaction reports;
- episode brief, script/storyboard, truth sheet, claim ledger, and claim verification;
- source commit, product build, configuration, inputs, tool versions, render command, and logs.

Use deterministic tools for measurable facts and reviewers only for judgment. Missing or stale
evidence is a pipeline failure, not permission to infer a pass.

## Signed publication approval

`schemas/release-evidence.schema.json` describes the unsigned evidence graph. It references the
candidate, arbiter decision, final verification, approval receipt, and detached signature by exact
path, SHA-256, and byte count. The separately signed receipt is strict JSON with exactly:

- `schemaVersion: "1.0.0"` and a unique `PVA-...-001` `receiptId`;
- `signatureAlgorithm: "Ed25519"` and `approverPublicKeySha256`, calculated from the trusted
  public key's DER SPKI bytes;
- `candidateId`, `candidateSha256`, and `candidateBytes`;
- `arbiterDecisionSha256` and `finalVerificationSha256`;
- `reviewerIdentity`, RFC 3339 `reviewedAt`, `classification: "approved"`,
  `watchThroughStatus: "completed"`, `syntheticDataConfirmed: true`, and `redactionNotes`.

Sign the exact receipt file bytes in the human-controlled approval system and store the raw
64-byte Ed25519 signature as a separate artifact. Then run:

```bash
AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY=/trusted/path/publication-approver.pem \
  node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/check-evidence-gate.mjs" \
  --manifest <release-evidence.json>
```

The public key environment variable is a trust decision supplied by the operator. A manifest,
receipt, or agent cannot select its own trusted key.

## Stage 1 — deterministic preflight

Run technical inspection and package preflight before independent review:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/technical-checks.mjs" \
  --video <candidate.mp4> \
  --out <evidence-dir>/technical \
  --spec <delivery-spec.json> \
  --candidate-id <candidate-id> \
  --artifact-id <media-artifact-id> \
  --deterministic-out <evidence-dir>/deterministic

node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/preflight.mjs" \
  --evidence-package <evidence-package.json> --out <preflight-report.json>
```

Preflight fails on missing artifacts; script/narration/ASR/caption or claim differences; wrong
names, dates, numbers, values, or states; caption overflow/obstruction/speed/safe-area failures;
loudness, clipping, artifact, ducking, or unintended-silence failures; black/frozen/duplicate/
corrupt frames; browser, console, network, capture, asset, font, decode, or render errors; invalid
output specifications; or incomplete/mismatched checksums and provenance.

Route failures to the responsible generator. Do not dispatch reviewers until preflight passes.

## Stage 2 — four independent reviewers

Dispatch all four isolated prompts against the same immutable candidate and evidence package:

| Domain | Prompt | Pass standard |
|---|---|---|
| Story and Experience | `agents/story-experience-reviewer.md` | Persuasive and polished; score >= 85 |
| Screen, Accuracy, and Compliance | `agents/screen-accuracy-compliance-reviewer.md` | Accuracy, claims, privacy, compliance, and playback all pass |
| Audio, Captions, and Synchronization | `agents/audio-captions-sync-reviewer.md` | Audio/captions/sync/accessibility all pass; score >= 95 |
| Technical and Frame Integrity | `agents/technical-frame-integrity-reviewer.md` | Delivery, frames, checksums, provenance, playback, and reproducibility all pass |

Use packaged agents when the host supports enforceable read-only contexts. Otherwise create four
independent read-only subagent contexts from these files. If host capacity is lower than four, use fresh isolated waves;
never collapse domains into one opinion or let one reviewer read another review before writing its
own.

If the host cannot enforce those contexts as read-only, do not simulate isolation with prompt
text. Record the missing enforcement evidence and return `PIPELINE_BLOCKED`.
The host must emit and sign the exact execution receipt. Validate its detached Ed25519 signature
against the operator-owned registry selected by `AGENTHUB_EXECUTION_HOST_TRUST_CONFIG`. An agent
may consume this receipt but may never author or sign it. Unknown or disabled keys, unauthorized
roles/mechanisms/tools, missing trust configuration, or receipt/signature drift fail closed.

Each report must conform to `schemas/review-report.schema.json`. Every finding must conform to
`schemas/video-finding.schema.json` and contain:

- unique ID, category, severity, and fix classification;
- exact timestamps and frame range;
- expected and observed behavior;
- viewer or release impact;
- direct evidence;
- concrete fix and automated validation;
- confidence.

Validate each report:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-review-report.mjs" <review-report.json>
```

Reject vague, duplicated, malformed, speculative, unsupported, or wrong-candidate findings.

## Stage 3 — release arbitration

Run `agents/release-arbiter.md` in a fresh read-only context with the preflight and four validated
reports. The arbiter validates evidence, deduplicates overlap, resolves contradictions using
evidence or a fresh targeted review, applies thresholds, routes retained findings, and writes one
decision conforming to `schemas/release-decision.schema.json`.

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-release-decision.mjs" \
  <release-decision.json>
```

Allowed decisions:

- `PASS`
- `REMEDIATE`
- `PRODUCT_BLOCKED`
- `PIPELINE_BLOCKED`

`PASS` requires zero blocker/critical findings, Story and Experience >= 85, Audio/Captions/Sync
>= 95, and complete passes for accuracy, compliance, privacy, technical integrity, browser
playback, claims, checksums, and provenance.

Only deduplicated product-level defects may become Linear issues, and only during an authorized
product task. Video edits and AgentHub capability defects do not belong in a product tracker.

## Stage 4 — least-privilege remediation

For `REMEDIATE`, create independent assignments by subsystem:

- story and script;
- product or seed data;
- capture and Playwright;
- Remotion composition;
- narration and audio;
- captions;
- export pipeline;
- infrastructure and assets.

Each assignment must conform to `schemas/remediation-assignment.schema.json` and include only its
finding IDs, permitted files, prohibited files, evidence, reproduction/validation commands, and
definition of done.

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-remediation-assignment.mjs" \
  <assignment.json>
```

The remediation agent reproduces, finds root cause, improves automated coverage where feasible,
implements the smallest coherent fix, runs targeted validation, and reports exact changed files,
commands, results, and evidence. It cannot approve its work or conceal a product defect in editing.

## Stage 5 — rerender and fresh review

After any relevant product, data, source, media, configuration, or environment change:

1. Create a new immutable candidate.
2. Rerender from source.
3. Regenerate the complete evidence package.
4. Use fresh reviewer contexts.
5. Rerun every affected domain.
6. Always rerun technical integrity, synchronization, accuracy, privacy, and compliance.
7. Obtain a new arbiter decision.

Never reuse previous passes across a candidate change or weaken thresholds. Continue until `PASS`
or evidence proves a genuine `PRODUCT_BLOCKED` or `PIPELINE_BLOCKED` result.

## Stage 6 — mandatory final independent review and verification

After arbiter `PASS`, dispatch `agents/final-verifier.md` as the mandatory terminal independent
reviewer and verifier in a fresh read-only context. A candidate cannot be packaged, delivered, or
released without this role's schema-valid `PASS` report for the exact unchanged candidate. It
independently checks candidate/report identities, changed-source invalidation, thresholds,
checksums, provenance, playback, reproduction, and delivery-folder contents. Only after this final
report returns `PASS` may the human approver create and sign a receipt that binds the candidate
SHA-256/bytes, arbiter SHA-256, final-verification SHA-256, reviewer identity/time, `approved`
classification, completed watch-through, synthetic-data confirmation, redaction notes, and trusted
public-key fingerprint. The gate verifies the receipt and its raw 64-byte Ed25519 signature;
missing or untrusted keys, modified receipts, and stale signatures fail.

## Quality bar

A technically valid but ineffective video fails. A persuasive video that misrepresents the product
fails. Release only truthful, persuasive, visually polished, synchronized, accessible, private,
compliant, technically valid, and reproducible videos.

Every episode must have a clear audience/outcome, felt before-state, one protected hero moment,
visible payoff, trust/control moment, and clear next step. A precise product-readiness report with
zero videos is valid; a mediocre video is not.
