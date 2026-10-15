import { test } from "node:test";
import assert from "node:assert/strict";
import { canonicalHash, canonicalJson, CanonicalJsonError } from "../canonical-json.ts";
import { createProposal, decide, verifyProposal, type DecisionRecord } from "../approval-capsule.ts";
import { createReceipt, verifyChain, verifyReceipt, compareReplay, type Receipt } from "../receipt.ts";
import { emitReceiptSpan, receiptSpan } from "../otel-genai.ts";
import { loadVectors, merge, runApprovalCase } from "../vectors.ts";

const canonical = loadVectors("canonical-json.json");
const approval = loadVectors("approval-cases.json");
const receipts = loadVectors("receipts.json");

for (const vector of canonical.cases) {
  test(`canonical-json: ${vector.name}`, () => {
    if (vector.error) {
      assert.throws(() => canonicalJson(vector.input), (error: unknown) => {
        assert.ok(error instanceof CanonicalJsonError);
        assert.match((error as Error).message, new RegExp(vector.error));
        return true;
      });
      return;
    }
    assert.equal(canonicalJson(vector.input), vector.canonical);
    if (vector.hash) assert.equal(canonicalHash(vector.input), vector.hash);
  });
}

test("canonical-json: refuses lone surrogates and class instances", () => {
  assert.throws(() => canonicalJson({ s: "\ud800" }), CanonicalJsonError);
  assert.throws(() => canonicalJson({ d: new Date(0) }), CanonicalJsonError);
  assert.throws(() => canonicalJson({ n: Number.NaN }), CanonicalJsonError);
});

test("approval: base proposal hash is pinned", () => {
  const proposal = createProposal(approval.base.proposalInput);
  assert.equal(proposal.proposalHash, approval.expectedBaseProposalHash);
  assert.ok(verifyProposal(proposal));
});

for (const vector of approval.cases) {
  test(`approval: ${vector.name}`, () => {
    const run = runApprovalCase(approval, vector);
    const { result, expect } = run;
    assert.equal(result.outcome, expect.outcome, JSON.stringify(result));
    assert.equal(result.status, expect.status);
    assert.equal(result.audit.outcome, expect.audit);
    assert.equal(result.audit.status, expect.status);
    if (result.outcome === "refuse") {
      assert.equal(result.code, expect.code);
      assert.equal(result.audit.code, expect.code);
    } else {
      assert.equal(result.audit.code, null);
    }
    if (expect.recordKey) {
      assert.ok(result.outcome === "replay");
      assert.equal((result as { record: DecisionRecord }).record.idempotencyKey, expect.recordKey);
    }
  });
}

test("approval: every proposal field is bound by the hash", () => {
  const base = createProposal(approval.base.proposalInput);
  const variants = [
    { tenantId: "tenant-x" },
    { action: "project.delete" },
    { subject: { id: "proj-43" } },
    { subject: { revision: 6 } },
    { payload: { note: "Vendor slip of 10 days" } },
    { proposedBy: { id: "someone-else" } },
    { expiresAt: "2026-10-30T00:00:00Z" },
    { policyRevision: "policy-2026.11" },
    { createdAt: "2026-10-14T15:00:01Z" },
  ];
  for (const patch of variants) {
    const changed = createProposal(merge(approval.base.proposalInput, patch));
    assert.notEqual(changed.proposalHash, base.proposalHash, JSON.stringify(patch));
  }
});

test("approval: an apply record carries the actor from the session, not the body", () => {
  const proposal = createProposal(approval.base.proposalInput);
  const result = decide({
    proposal,
    request: { proposalHash: proposal.proposalHash, decision: "approve", idempotencyKey: "k" },
    principal: approval.base.principal,
    currentRevision: 7,
    priorDecisions: [],
    policy: approval.base.policy,
    now: approval.base.now,
  });
  assert.equal(result.outcome, "apply");
  if (result.outcome === "apply") {
    assert.equal(result.record.actorId, "user-approver");
    assert.equal(result.record.subjectRevisionBefore, 7);
    assert.match(result.record.requestHash, /^sha256:[0-9a-f]{64}$/);
  }
});

function buildReceipts(): Receipt[] {
  const chain: Receipt[] = [];
  for (const input of receipts.chain) chain.push(createReceipt(input, chain.at(-1) ?? null));
  return chain;
}

test("receipts: pinned hashes and replay keys", () => {
  const chain = buildReceipts();
  chain.forEach((receipt, index) => {
    const expected = receipts.expected[index];
    assert.equal(receipt.receiptHash, expected.receiptHash, `receipt ${index}`);
    assert.equal(receipt.replayKey, expected.replayKey, `replay key ${index}`);
    assert.equal(receipt.retrievalHash ?? null, expected.retrievalHash, `retrieval hash ${index}`);
    assert.ok(verifyReceipt(receipt));
  });
  assert.deepEqual(verifyChain(chain), { ok: true, brokenAt: -1 });
});

test("receipts: tampering with one field breaks that receipt; relinking breaks the chain", () => {
  const chain = buildReceipts();
  const tampered = structuredClone(chain);
  tampered[1].outcome.outputHash = "sha256:" + "f".repeat(64);
  assert.deepEqual(verifyChain(tampered), { ok: false, brokenAt: 1, reason: "receipt_hash" });

  const relinked = structuredClone(chain);
  relinked.splice(1, 1);
  assert.deepEqual(verifyChain(relinked), { ok: false, brokenAt: 1, reason: "chain_link" });

  const forgedKey = structuredClone(chain);
  forgedKey[0].replayKey = "sha256:" + "0".repeat(64);
  forgedKey[0].receiptHash = createReceipt(forgedKey[0]).receiptHash;
  assert.equal(verifyReceipt(forgedKey[0]), false);
});

test("receipts: a replay on the same inputs keeps the replay key", () => {
  const [original] = buildReceipts();
  const replay = createReceipt({ ...receipts.chain[0], receiptId: "rcpt-replay", occurredAt: "2026-10-15T09:00:00Z" });
  assert.deepEqual(compareReplay(original, replay), { sameStep: true, sameOutput: true });
  const changedPrompt = createReceipt(merge(receipts.chain[0], { input: { promptRevision: "review-v8" } }));
  assert.equal(compareReplay(original, changedPrompt).sameStep, false);
});

test("otel: span attributes match the pinned GenAI mapping", () => {
  const chain = buildReceipts();
  chain.forEach((receipt, index) => {
    const span = receiptSpan(receipt);
    assert.equal(span.name, receipts.expected[index].spanName);
    assert.deepEqual(span.attributes, receipts.expected[index].spanAttributes);
  });
});

test("otel: never emits content attributes", () => {
  for (const receipt of buildReceipts()) {
    const keys = Object.keys(receiptSpan(receipt).attributes);
    for (const banned of ["gen_ai.input.messages", "gen_ai.output.messages", "gen_ai.system_instructions", "gen_ai.retrieval.query.text", "gen_ai.tool.call.arguments", "gen_ai.tool.call.result"]) {
      assert.ok(!keys.includes(banned), banned);
    }
  }
});

test("otel: emits through any API-shaped tracer and marks failures as errors", () => {
  const calls: any[] = [];
  const tracer = {
    startSpan(name: string, options: any) {
      const span = { name, options, status: undefined as any, endTime: undefined as any };
      calls.push(span);
      return { setStatus: (status: any) => (span.status = status), end: (endTime?: number) => (span.endTime = endTime) };
    },
  };
  for (const receipt of buildReceipts()) emitReceiptSpan(tracer, receipt);
  assert.equal(calls.length, receipts.chain.length);
  assert.equal(calls[0].options.kind, 2);
  const failed = calls.find((call) => call.options.attributes["app.receipt.outcome"] === "failed");
  assert.ok(failed, "fixture includes a failed model call");
  assert.equal(failed.status.code, 2);
  assert.equal(typeof failed.endTime, "number");
  assert.ok(failed.options.startTime <= failed.endTime);
});

// ---- adversarial suite: proves the suite passes correct wiring and catches bad wiring ----
import { runAdversarialSuite, type CapsuleAdapter } from "../adversarial-suite.ts";
import { refusalBody, type Proposal } from "../approval-capsule.ts";

function inMemoryProduct(options: { trustBodyActor?: boolean } = {}): CapsuleAdapter<any> {
  const principals: Record<string, [string, string, string[]]> = {
    approver: ["u-approver", "t1", ["reviewer"]],
    second_approver: ["u-approver-2", "t1", ["reviewer"]],
    proposer: ["u-proposer", "t1", ["reviewer"]],
    viewer: ["u-viewer", "t1", ["viewer"]],
    other_tenant: ["u-other", "t2", ["reviewer"]],
  };
  return {
    proposerIsUser: true,
    supportsConcurrency: true,
    async setup() {
      const proposal: Proposal = createProposal({
        capsuleId: "cap-1", tenantId: "t1", subject: { type: "task", id: "task-1", revision: 3 },
        action: "task.approve", payload: { status: "approved" }, proposedBy: { kind: "user", id: "u-proposer" },
        createdAt: "2026-10-14T00:00:00Z",
      });
      return { proposal, revision: 3, applied: 0, audit: [] as Array<[string, string | null]>, decisions: [] as DecisionRecord[] };
    },
    async proposal(ctx) { return ctx.proposal; },
    async decide(ctx, call) {
      let [id, tenantId, roles] = principals[call.actor];
      let claimedActorId = call.claimedActorId;
      if (options.trustBodyActor && claimedActorId) { id = claimedActorId; claimedActorId = undefined; }
      const result = decide({
        proposal: ctx.proposal,
        request: { proposalHash: call.proposalHash, decision: call.decision, idempotencyKey: call.idempotencyKey, claimedActorId },
        principal: { id, tenantId, roles }, currentRevision: ctx.revision, priorDecisions: ctx.decisions,
        policy: { approverRoles: ["reviewer"] }, now: "2026-10-14T01:00:00Z",
      });
      ctx.audit.push([result.audit.outcome, result.audit.code]);
      if (result.outcome === "apply" || result.outcome === "reject") ctx.decisions.push(result.record);
      if (result.outcome === "apply") { ctx.applied += 1; ctx.revision += 1; }
      return result.outcome === "refuse" ? { status: result.status, body: refusalBody(result) } : { status: 200, body: { decision: result.record } };
    },
    async changeSubject(ctx) { ctx.revision += 1; },
    async tamperStoredProposal(ctx) { ctx.proposal = { ...ctx.proposal, payload: { status: "rejected" } }; },
    async sideEffects(ctx) { return ctx.applied; },
    async auditOutcomes(ctx) { return ctx.audit; },
  };
}

test("adversarial suite: correct wiring passes every case", async () => {
  const results = await runAdversarialSuite(inMemoryProduct());
  assert.deepEqual(results.filter((r) => !r.passed), []);
  assert.equal(results.length, 14);
});

test("adversarial suite: trusting the body actor is caught", async () => {
  const results = await runAdversarialSuite(inMemoryProduct({ trustBodyActor: true }));
  assert.ok(results.some((r) => r.name === "forged_actor_is_refused" && !r.passed));
});
