import { test } from "node:test";
import assert from "node:assert/strict";
import { canonicalHash, canonicalJson, CanonicalJsonError } from "../canonical-json.ts";
import { createProposal, decide, proposalHashOf, requestHashOf, verifyProposal, CAPSULE_VERSION, type DecisionRecord } from "../approval-capsule.ts";
import { createReceipt, verifyChain, verifyReceipt, compareReplay, type Receipt } from "../receipt.ts";
import { KIT_VERSION } from "../index.ts";
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

function inMemoryProduct(options: { trustBodyActor?: boolean; applyOnConflict?: boolean } = {}): CapsuleAdapter<any> {
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
      if (options.applyOnConflict && result.outcome === "refuse" && result.code === "already_decided") ctx.applied += 1;
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

test("adversarial suite: a conflicting reject that still applies a change is caught", async () => {
  const results = await runAdversarialSuite(inMemoryProduct({ applyOnConflict: true }));
  assert.ok(results.some((r) => r.name === "reject_after_approve_conflicts" && !r.passed));
});

test("adversarial suite: a missing lock is caught by the concurrency case", async () => {
  const racy = inMemoryProduct();
  racy.decide = async (ctx, call) => {
    const prior = [...ctx.decisions];
    const revision = ctx.revision;
    await new Promise((resolve) => setImmediate(resolve));
    const result = decide({
      proposal: ctx.proposal,
      request: { proposalHash: call.proposalHash, decision: call.decision, idempotencyKey: call.idempotencyKey },
      principal: { id: "u-approver", tenantId: "t1", roles: ["reviewer"] },
      currentRevision: revision, priorDecisions: prior,
      policy: { approverRoles: ["reviewer"] }, now: "2026-10-14T01:00:00Z",
    });
    ctx.audit.push([result.audit.outcome, result.audit.code]);
    if (result.outcome === "apply") { ctx.decisions.push(result.record); ctx.applied += 1; }
    return result.outcome === "refuse" ? { status: result.status, body: refusalBody(result) } : { status: 200, body: {} };
  };
  const results = await runAdversarialSuite(racy);
  assert.ok(results.some((r) => r.name === "concurrent_approvals_apply_once" && !r.passed));
});

test("adversarial suite: each concurrent call is invoked from its own macrotask", async () => {
  const product = inMemoryProduct();
  const innerSetup = product.setup.bind(product);
  const innerDecide = product.decide.bind(product);
  const innerSideEffects = product.sideEffects.bind(product);
  let seen: boolean[] = [];
  product.setup = async () => ({ ...(await innerSetup()), tick: false, tickAtEntry: [] as boolean[] });
  product.proposal = async (ctx) => {
    // A macrotask queued just before the concurrent calls: each call must run after it.
    ctx.tick = false;
    setImmediate(() => { ctx.tick = true; });
    return ctx.proposal;
  };
  product.decide = async (ctx, call) => {
    if (call.idempotencyKey.startsWith("adversarial-key-c")) ctx.tickAtEntry.push(ctx.tick);
    return innerDecide(ctx, call);
  };
  product.sideEffects = async (ctx) => {
    if (ctx.tickAtEntry.length) seen = ctx.tickAtEntry;
    return innerSideEffects(ctx);
  };
  await runAdversarialSuite(product);
  assert.deepEqual(seen, [true, true, true, true]);
});

// ---- 1.1.0 fixes ----
const baseInput = approval.base.proposalInput;
const NO_EXPIRY_HASH = "sha256:9bb74b5cfa1d2995ac7d78ca37ba9131abec1de36558e1dd2f2ef158fed3438c";

function storedWith(patch: Record<string, unknown>) {
  // What an older writer could have stored: a valid hash over whatever it held.
  const body: any = { ...createProposal(baseInput), ...patch };
  delete body.proposalHash;
  return { ...body, proposalHash: proposalHashOf(body) };
}

function approveAt(proposal: any, now: string, decision: string = "approve") {
  return decide({
    proposal,
    request: { proposalHash: proposal.proposalHash, decision: decision as any, idempotencyKey: "k" },
    principal: approval.base.principal,
    currentRevision: 7,
    priorDecisions: [],
    policy: approval.base.policy,
    now,
  });
}

test("expiry fails closed: an unparseable expiresAt is expired", () => {
  for (const expiresAt of ["garbage", "2026-10-15T15:00:00", "2026-10-15T15:00:00+00:00", "2026-02-30T00:00:00Z", "2026-10-15", ""]) {
    const result = approveAt(storedWith({ expiresAt }), approval.base.now);
    assert.equal(result.outcome, "refuse", expiresAt);
    assert.equal((result as any).code, "proposal_expired", expiresAt);
  }
});

test("expiry fails closed: an unparseable now is expired", () => {
  const proposal = createProposal(baseInput);
  for (const now of ["garbage", "2026-10-14T16:00:00", "2026-10-14T16:00:00+00:00", ""]) {
    const result = approveAt(proposal, now);
    assert.equal(result.outcome, "refuse", now);
    assert.equal((result as any).code, "proposal_expired", now);
  }
  const { expiresAt: _omit, ...noExpiry } = baseInput;
  assert.equal((approveAt(createProposal(noExpiry), "garbage") as any).code, "proposal_expired");
});

test("expiry: a reject is still allowed when the timestamps cannot be parsed", () => {
  assert.equal(approveAt(storedWith({ expiresAt: "garbage" }), "garbage", "reject").outcome, "reject");
});

test("expiry: fractional seconds in a Z timestamp are accepted", () => {
  assert.equal(approveAt(storedWith({ expiresAt: "2026-10-15T15:00:00.500Z" }), approval.base.now).outcome, "apply");
});

test("createProposal rejects a createdAt or expiresAt that is not a Z-suffixed ISO timestamp", () => {
  for (const patch of [
    { createdAt: "garbage" }, { createdAt: "2026-10-14T15:00:00" }, { createdAt: "2026-10-14T15:00:00+00:00" },
    { expiresAt: "tomorrow" }, { expiresAt: "2026-10-15T15:00:00+02:00" }, { expiresAt: "2026-13-01T00:00:00Z" },
    { createdAt: 5 },
  ]) {
    assert.throws(() => createProposal({ ...baseInput, ...patch } as any), Error, JSON.stringify(patch));
  }
});

test("verifyChain anchors the head: a forged first prev and a missing head both fail", () => {
  const chain = buildReceipts();
  const forgedHead = createReceipt(receipts.chain[0], { receiptHash: "sha256:" + "1".repeat(64) } as Receipt);
  assert.ok(verifyReceipt(forgedHead));
  assert.deepEqual(verifyChain([forgedHead]), { ok: false, brokenAt: 0, reason: "chain_link" });
  assert.deepEqual(verifyChain(chain.slice(1)), { ok: false, brokenAt: 0, reason: "chain_link" });
});

test("verifyChain accepts a slice when given its known head", () => {
  const chain = buildReceipts();
  assert.deepEqual(verifyChain(chain.slice(1), chain[0].receiptHash), { ok: true, brokenAt: -1 });
  assert.deepEqual(verifyChain(chain, null), { ok: true, brokenAt: -1 });
  assert.deepEqual(verifyChain(chain.slice(1), "sha256:" + "2".repeat(64)), { ok: false, brokenAt: 0, reason: "chain_link" });
});

test("null means absent: createProposal drops top-level nulls and keeps payload nulls", () => {
  const { expiresAt: _e, policyRevision: _p, ...rest } = baseInput;
  const dropped = createProposal({ ...baseInput, expiresAt: null, policyRevision: undefined } as any);
  assert.ok(!("expiresAt" in dropped) && !("policyRevision" in dropped));
  assert.equal(createProposal({ ...rest }).proposalHash, createProposal({ ...rest, expiresAt: null, policyRevision: null } as any).proposalHash);
  const withPayloadNull = createProposal({ ...rest, payload: { owner: null } });
  assert.notEqual(withPayloadNull.proposalHash, createProposal({ ...rest, payload: {} }).proposalHash);
});

test("null means absent: an expiresAt of null hashes like an absent one (same literal as Python)", () => {
  const { expiresAt: _e, ...rest } = baseInput;
  assert.equal(createProposal({ ...rest, expiresAt: null } as any).proposalHash, NO_EXPIRY_HASH);
  assert.equal(createProposal(rest).proposalHash, NO_EXPIRY_HASH);
});

test("null means absent: a stored proposal reloaded with a null expiresAt still verifies and never expires", () => {
  const { expiresAt: _e, ...rest } = baseInput;
  const reloaded = { ...createProposal(rest), expiresAt: null } as any;
  assert.ok(verifyProposal(reloaded));
  assert.equal(approveAt(reloaded, "2030-01-01T00:00:00Z").outcome, "apply");
});

test("null means absent: reason null hashes and records like no reason", () => {
  const hash = "sha256:" + "a".repeat(64);
  assert.equal(
    requestHashOf({ proposalHash: hash, decision: "approve", idempotencyKey: "k", reason: null } as any, "u1"),
    requestHashOf({ proposalHash: hash, decision: "approve", idempotencyKey: "k" }, "u1"),
  );
  const proposal = createProposal(baseInput);
  const result = decide({
    proposal, request: { proposalHash: proposal.proposalHash, decision: "approve", idempotencyKey: "k", reason: null } as any,
    principal: approval.base.principal, currentRevision: 7, priorDecisions: [], policy: approval.base.policy, now: approval.base.now,
  });
  assert.equal(result.outcome, "apply");
  assert.ok(!("reason" in (result as any).record));
});

test("null means absent: a null claimedActorId is ignored", () => {
  const proposal = createProposal(baseInput);
  const result = decide({
    proposal, request: { proposalHash: proposal.proposalHash, decision: "approve", idempotencyKey: "k", claimedActorId: null } as any,
    principal: approval.base.principal, currentRevision: 7, priorDecisions: [], policy: approval.base.policy, now: approval.base.now,
  });
  assert.equal(result.outcome, "apply");
});

const RECEIPT_MIN = {
  receiptId: "rcpt-x", tenantId: "t1", occurredAt: "2026-10-14T15:00:00Z", kind: "retrieval", engine: "rules",
  input: { hash: "sha256:" + "a".repeat(64) }, outcome: { status: "succeeded" },
} as const;
const MIN_RECEIPT_HASH = "sha256:333426c67398ac6b6f620e127171a5d962a5788fea2260426c4872fcecc5245b";
const MIN_REPLAY_KEY = "sha256:0d5edfdd1c40ba44d6e6bdc84b543b0c1504792101dec69731eb01ed868c1947";
const EMPTY_RETRIEVAL_RECEIPT_HASH = "sha256:ca17d88c30195d798040ee4ac5443f50c36c0b68a315ae014d73358a8e321197";

test("null means absent: createReceipt prunes nulls recursively like Python", () => {
  const receipt = createReceipt({ ...RECEIPT_MIN, durationMs: null, subject: null, outcome: { status: "succeeded", code: null, outputHash: undefined } } as any);
  assert.equal(receipt.receiptHash, MIN_RECEIPT_HASH);
  assert.equal(receipt.replayKey, MIN_REPLAY_KEY);
  assert.ok(!("durationMs" in receipt) && !("code" in receipt.outcome));
  assert.ok(verifyReceipt(receipt));
});

test("empty retrieval: an object without documents is absent for retrievalHash, replayKey and verification", () => {
  const receipt = createReceipt({ ...RECEIPT_MIN, retrieval: {} } as any);
  assert.equal(receipt.retrievalHash, undefined);
  assert.equal(receipt.replayKey, MIN_REPLAY_KEY);
  assert.equal(receipt.receiptHash, EMPTY_RETRIEVAL_RECEIPT_HASH);
  assert.ok(verifyReceipt(receipt));
  const withDocuments = createReceipt({ ...RECEIPT_MIN, retrieval: { queryHash: "sha256:" + "b".repeat(64), documents: [] } } as any);
  assert.match(withDocuments.retrievalHash ?? "", /^sha256:[0-9a-f]{64}$/);
});

test("decide refuses a decision that is not exactly approve or reject", () => {
  const proposal = createProposal(baseInput);
  for (const decision of ["approved", "APPROVE", "", undefined, null, 1]) {
    assert.throws(
      () => decide({
        proposal, request: { proposalHash: proposal.proposalHash, decision: decision as any, idempotencyKey: "k" },
        principal: approval.base.principal, currentRevision: 7, priorDecisions: [], policy: approval.base.policy, now: approval.base.now,
      }),
      TypeError,
      String(decision),
    );
  }
});

test("capsuleVersion is bound: a stored version other than v1 fails verification", () => {
  const evil = { ...createProposal(baseInput), capsuleVersion: "evil" } as any;
  assert.equal(verifyProposal(evil), false);
  assert.equal((approveAt(evil, approval.base.now) as any).code, "proposal_tampered");
  // Even with the hash recomputed over the forged version, the version is refused.
  const rehashed = storedWith({ capsuleVersion: "evil" });
  assert.equal(verifyProposal(rehashed), false);
  assert.notEqual(rehashed.proposalHash, createProposal(baseInput).proposalHash);
  assert.equal((approveAt(rehashed, approval.base.now) as any).code, "proposal_tampered");
  assert.equal(CAPSULE_VERSION, "approval-capsule/v1");
});

test("otel timing floors to integer milliseconds like Date.parse", () => {
  const at = (occurredAt: string) => receiptSpan(createReceipt({ ...RECEIPT_MIN, occurredAt } as any)).endTimeMs;
  assert.equal(at("2026-10-14T15:00:00.9996Z"), 1791990000999);
  assert.equal(at("2026-10-14T15:00:00.001500Z"), 1791990000001);
});

test("KIT_VERSION is 1.1.1", () => {
  assert.equal(KIT_VERSION, "1.1.1");
});
