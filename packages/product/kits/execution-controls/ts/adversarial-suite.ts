// execution-controls kit: adversarial suite for an adopter's real approval path.
//
// The vectors in ../vectors/ prove `decide` itself. This suite proves the
// product wired it correctly: the route binds the actor from the session,
// holds the lock, applies at most once, and audits every refusal. Implement
// `CapsuleAdapter` against the product (test client plus database) and call
// `assertAdversarialSuite(adapter)` from the product's own tests. Each case
// starts from `adapter.setup()`. Same cases as the Python suite.

export type Actor = "approver" | "second_approver" | "proposer" | "viewer" | "other_tenant";

export interface DecideCall {
  actor: Actor;
  proposalHash: string;
  decision: "approve" | "reject";
  idempotencyKey: string;
  claimedActorId?: string;
}

export interface CapsuleAdapter<Ctx = unknown> {
  /** True when the proposer is a person who could try to approve their own proposal. */
  proposerIsUser: boolean;
  /** False when every participant may decide; the viewer case is then skipped. Default true. */
  hasViewer?: boolean;
  supportsConcurrency?: boolean;
  setup(): Promise<Ctx>;
  proposal(ctx: Ctx): Promise<{ proposalHash: string }>;
  decide(ctx: Ctx, call: DecideCall): Promise<{ status: number; body: any }>;
  changeSubject(ctx: Ctx): Promise<void>;
  tamperStoredProposal(ctx: Ctx): Promise<void>;
  sideEffects(ctx: Ctx): Promise<number>;
  auditOutcomes(ctx: Ctx): Promise<Array<[string, string | null]>>;
}

export interface CaseResult {
  name: string;
  passed: boolean;
  detail?: string;
}

class Fail extends Error {}

function expect(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Fail(message);
}

const codeOf = (body: any): string | undefined => body?.error?.code;

export function adversarialCases<Ctx>(adapter: CapsuleAdapter<Ctx>): Array<[string, () => Promise<void>]> {
  const approve = async (ctx: Ctx, overrides: Partial<DecideCall> = {}) =>
    adapter.decide(ctx, {
      actor: "approver",
      proposalHash: (await adapter.proposal(ctx)).proposalHash,
      decision: "approve",
      idempotencyKey: "adversarial-key-1",
      ...overrides,
    });

  const refused = async (ctx: Ctx, result: { status: number; body: any }, status: number, code: string) => {
    expect(result.status === status, `status ${result.status}, want ${status}`);
    expect(codeOf(result.body) === code, `error code ${codeOf(result.body)}, want ${code}`);
    expect((await adapter.sideEffects(ctx)) === 0, "a refused decision applied the change");
    const audit = await adapter.auditOutcomes(ctx);
    expect(audit.some(([outcome, c]) => outcome === "refused" && c === code), `no audit row (refused, ${code})`);
  };

  const cases: Array<[string, () => Promise<void>]> = [
    ["approve_applies_once", async () => {
      const ctx = await adapter.setup();
      const result = await approve(ctx);
      expect(result.status === 200, `approve returned ${result.status}`);
      expect((await adapter.sideEffects(ctx)) === 1, "side effects != 1");
      expect((await adapter.auditOutcomes(ctx)).some(([o, c]) => o === "applied" && c === null), "no applied audit row");
    }],
    ["replay_same_key_applies_once", async () => {
      const ctx = await adapter.setup();
      const first = await approve(ctx);
      const second = await approve(ctx);
      expect(first.status === 200 && second.status === 200, `statuses ${first.status}/${second.status}`);
      expect((await adapter.sideEffects(ctx)) === 1, "a replay applied the change twice");
      expect((await adapter.auditOutcomes(ctx)).some(([o]) => o === "replayed"), "replay was not audited");
    }],
    ["reapprove_new_key_applies_once", async () => {
      const ctx = await adapter.setup();
      await approve(ctx);
      const again = await approve(ctx, { idempotencyKey: "adversarial-key-2" });
      expect(again.status === 200, `re-approve returned ${again.status}`);
      expect((await adapter.sideEffects(ctx)) === 1, "re-approve applied the change twice");
    }],
    ["second_approver_is_a_replay", async () => {
      const ctx = await adapter.setup();
      await approve(ctx);
      const second = await approve(ctx, { actor: "second_approver", idempotencyKey: "adversarial-key-2" });
      expect(second.status === 200, `second approver got ${second.status}`);
      expect((await adapter.sideEffects(ctx)) === 1, "second approver applied the change again");
    }],
    ["reject_after_approve_conflicts", async () => {
      const ctx = await adapter.setup();
      await approve(ctx);
      const result = await approve(ctx, { idempotencyKey: "adversarial-key-2", decision: "reject" });
      expect(result.status === 409 && codeOf(result.body) === "already_decided", `got ${result.status} ${codeOf(result.body)}`);
      expect((await adapter.sideEffects(ctx)) === 1, "side effects changed");
    }],
    ["same_key_different_body", async () => {
      const ctx = await adapter.setup();
      await approve(ctx);
      const result = await approve(ctx, { decision: "reject" });
      expect(result.status === 422 && codeOf(result.body) === "idempotency_key_reused", `got ${result.status} ${codeOf(result.body)}`);
    }],
    ["stale_revision_is_refused", async () => {
      const ctx = await adapter.setup();
      const shown = (await adapter.proposal(ctx)).proposalHash;
      await adapter.changeSubject(ctx);
      await refused(ctx, await approve(ctx, { proposalHash: shown }), 409, "stale_proposal");
    }],
    ["tampered_proposal_is_refused", async () => {
      const ctx = await adapter.setup();
      const shown = (await adapter.proposal(ctx)).proposalHash;
      await adapter.tamperStoredProposal(ctx);
      await refused(ctx, await approve(ctx, { proposalHash: shown }), 409, "proposal_tampered");
    }],
    ["wrong_presented_hash_is_refused", async () => {
      const ctx = await adapter.setup();
      await refused(ctx, await approve(ctx, { proposalHash: `sha256:${"0".repeat(64)}` }), 409, "proposal_hash_mismatch");
    }],
    ["forged_actor_is_refused", async () => {
      const ctx = await adapter.setup();
      await refused(ctx, await approve(ctx, { claimedActorId: "someone-else" }), 403, "actor_mismatch");
    }],
    ["other_tenant_is_not_found", async () => {
      const ctx = await adapter.setup();
      const result = await approve(ctx, { actor: "other_tenant" });
      expect(result.status === 404, `other tenant got ${result.status}, want 404`);
      expect((await adapter.sideEffects(ctx)) === 0, "other tenant applied the change");
    }],
  ];

  if (adapter.hasViewer !== false) {
    cases.push(["viewer_is_refused", async () => {
      const ctx = await adapter.setup();
      await refused(ctx, await approve(ctx, { actor: "viewer" }), 403, "actor_not_authorized");
    }]);
  }
  if (adapter.proposerIsUser) {
    cases.push(["self_approval_is_refused", async () => {
      const ctx = await adapter.setup();
      await refused(ctx, await approve(ctx, { actor: "proposer" }), 403, "self_approval_forbidden");
    }]);
  }
  if (adapter.supportsConcurrency) {
    cases.push(["concurrent_approvals_apply_once", async () => {
      const ctx = await adapter.setup();
      const shown = (await adapter.proposal(ctx)).proposalHash;
      // Each call starts from its own macrotask, so four calls interleave even when the adapter is synchronous.
      const results = await Promise.all(
        [0, 1, 2, 3].map(async (i) => {
          await new Promise((resolve) => setImmediate(resolve));
          return adapter.decide(ctx, { actor: "approver", proposalHash: shown, decision: "approve", idempotencyKey: `adversarial-key-c${i}` });
        }),
      );
      expect(results.every((r) => r.status < 500), `concurrent statuses ${results.map((r) => r.status)}`);
      expect((await adapter.sideEffects(ctx)) === 1, "concurrent approvals applied more than once");
    }]);
  }
  return cases;
}

export async function runAdversarialSuite<Ctx>(adapter: CapsuleAdapter<Ctx>): Promise<CaseResult[]> {
  const results: CaseResult[] = [];
  for (const [name, run] of adversarialCases(adapter)) {
    try {
      await run();
      results.push({ name, passed: true });
    } catch (error) {
      if (!(error instanceof Fail)) throw error;
      results.push({ name, passed: false, detail: error.message });
    }
  }
  return results;
}

export async function assertAdversarialSuite<Ctx>(adapter: CapsuleAdapter<Ctx>): Promise<CaseResult[]> {
  const results = await runAdversarialSuite(adapter);
  const failed = results.filter((result) => !result.passed);
  if (failed.length > 0) {
    throw new Error(`approval capsule adversarial suite failed:\n${failed.map((r) => `  ${r.name}: ${r.detail}`).join("\n")}`);
  }
  return results;
}
