// execution-controls kit: approval capsule (spec: ../spec/approval-capsule.md).
//
// A capsule binds one proposed change to the exact payload, subject revision,
// tenant and proposer it was computed from. `decide` is a pure function: the
// adopter loads the stored proposal, the subject's current revision and the
// prior decisions inside one transaction that holds a row lock on the subject,
// calls `decide`, and then either applies the change and stores the decision,
// or stores only the audit row. Every outcome, including every refusal,
// returns exactly one audit row.

import { canonicalHash } from "./canonical-json.ts";

export const CAPSULE_VERSION = "approval-capsule/v1";
export const AUDIT_VERSION = "approval-audit/v1";

export type Revision = number | string;

export interface SubjectRef {
  type: string;
  id: string;
  revision: Revision;
}

export interface Party {
  kind: "agent" | "user" | "rule" | "system";
  id: string;
}

export interface EvidenceRef {
  ref: string;
  hash?: string;
}

export interface ProposalInput {
  capsuleId: string;
  tenantId: string;
  subject: SubjectRef;
  action: string;
  payload: unknown;
  proposedBy: Party;
  createdAt: string;
  expiresAt?: string;
  policyRevision?: string;
  evidence?: EvidenceRef[];
  receiptId?: string;
}

export interface Proposal extends ProposalInput {
  capsuleVersion: typeof CAPSULE_VERSION;
  proposalHash: string;
}

/** The authenticated caller. Never built from request-body fields. */
export interface Principal {
  id: string;
  tenantId: string;
  roles: string[];
}

export type Decision = "approve" | "reject";

export interface DecisionRequest {
  /** The hash the approver was shown. */
  proposalHash: string;
  decision: Decision;
  idempotencyKey: string;
  /** An actor id the client put in the body, if any. Only ever compared, never trusted. */
  claimedActorId?: string;
  reason?: string;
}

export interface ApprovalPolicy {
  approverRoles: string[];
  allowSelfApproval?: boolean;
}

export interface DecisionRecord {
  capsuleId: string;
  proposalHash: string;
  decision: Decision;
  actorId: string;
  idempotencyKey: string;
  requestHash: string;
  subjectRevisionBefore: Revision;
  decidedAt: string;
  reason?: string;
}

export type AuditOutcome = "applied" | "rejected" | "replayed" | "refused";

/** Proposal-derived fields are null only on a `capsule_not_found` refusal. */
export interface AuditRow {
  auditVersion: typeof AUDIT_VERSION;
  tenantId: string;
  capsuleId: string | null;
  action: string | null;
  subjectType: string | null;
  subjectId: string | null;
  subjectRevision: Revision | null;
  presentedHash: string;
  proposalHash: string | null;
  decision: Decision;
  actorId: string;
  idempotencyKey: string;
  outcome: AuditOutcome;
  code: RefusalCode | null;
  status: number;
  at: string;
}

export const REFUSALS = {
  capsule_not_found: 404,
  actor_mismatch: 403,
  proposal_tampered: 409,
  proposal_hash_mismatch: 409,
  actor_not_authorized: 403,
  self_approval_forbidden: 403,
  idempotency_key_reused: 422,
  already_decided: 409,
  proposal_expired: 410,
  stale_proposal: 409,
} as const;

export type RefusalCode = keyof typeof REFUSALS;

const MESSAGES: Record<RefusalCode, string> = {
  capsule_not_found: "No such proposal for this tenant.",
  actor_mismatch: "The actor in the request is not the signed-in user.",
  proposal_tampered: "The stored proposal no longer matches its hash.",
  proposal_hash_mismatch: "The proposal changed after you reviewed it.",
  actor_not_authorized: "You are not allowed to decide this proposal.",
  self_approval_forbidden: "The person who proposed a change cannot approve it.",
  idempotency_key_reused: "This idempotency key was already used for a different request.",
  already_decided: "This proposal already has a different decision.",
  proposal_expired: "This proposal expired before it was approved.",
  stale_proposal: "The record changed after this proposal was made.",
};

export interface DecideInput {
  proposal: Proposal;
  request: DecisionRequest;
  principal: Principal;
  currentRevision: Revision;
  priorDecisions: DecisionRecord[];
  policy: ApprovalPolicy;
  now: string;
}

interface Base {
  audit: AuditRow;
}

export type DecideResult =
  | (Base & { outcome: "apply" | "reject"; status: 200; record: DecisionRecord })
  | (Base & { outcome: "replay"; status: 200; record: DecisionRecord })
  | (Base & { outcome: "refuse"; status: number; code: RefusalCode; message: string });

export function proposalHashOf(proposal: ProposalInput | Proposal): string {
  const { proposalHash: _ignored, ...rest } = proposal as Proposal;
  return canonicalHash({ ...rest, capsuleVersion: CAPSULE_VERSION });
}

export function createProposal(input: ProposalInput): Proposal {
  return { ...input, capsuleVersion: CAPSULE_VERSION, proposalHash: proposalHashOf(input) };
}

export function verifyProposal(proposal: Proposal): boolean {
  return proposalHashOf(proposal) === proposal.proposalHash;
}

export function requestHashOf(request: DecisionRequest, actorId: string): string {
  return canonicalHash({
    proposalHash: request.proposalHash,
    decision: request.decision,
    actorId,
    reason: request.reason,
  });
}

function sameRevision(a: Revision, b: Revision): boolean {
  return String(a) === String(b);
}

export function decide(input: DecideInput): DecideResult {
  const { proposal, request, principal, currentRevision, priorDecisions, policy, now } = input;

  const audit = (outcome: AuditOutcome, status: number, code: RefusalCode | null): AuditRow => ({
    auditVersion: AUDIT_VERSION,
    tenantId: principal.tenantId,
    capsuleId: proposal.capsuleId,
    action: proposal.action,
    subjectType: proposal.subject.type,
    subjectId: proposal.subject.id,
    subjectRevision: currentRevision,
    presentedHash: request.proposalHash,
    proposalHash: proposal.proposalHash,
    decision: request.decision,
    actorId: principal.id,
    idempotencyKey: request.idempotencyKey,
    outcome,
    code,
    status,
    at: now,
  });

  const refuse = (code: RefusalCode): DecideResult => {
    const status = REFUSALS[code];
    const row = audit("refused", status, code);
    if (code === "capsule_not_found") {
      // The row lands in the caller's tenant: it must not describe another tenant's proposal.
      Object.assign(row, { capsuleId: null, action: null, subjectType: null, subjectId: null, subjectRevision: null, proposalHash: null });
    }
    return { outcome: "refuse", status, code, message: MESSAGES[code], audit: row };
  };

  // Tenant first, and as 404: a caller in another tenant learns nothing.
  if (principal.tenantId !== proposal.tenantId) return refuse("capsule_not_found");
  if (request.claimedActorId !== undefined && request.claimedActorId !== principal.id) return refuse("actor_mismatch");
  if (!verifyProposal(proposal)) return refuse("proposal_tampered");
  if (request.proposalHash !== proposal.proposalHash) return refuse("proposal_hash_mismatch");
  if (!principal.roles.some((role) => policy.approverRoles.includes(role))) return refuse("actor_not_authorized");
  if (
    request.decision === "approve" &&
    !policy.allowSelfApproval &&
    proposal.proposedBy.kind === "user" &&
    proposal.proposedBy.id === principal.id
  ) {
    return refuse("self_approval_forbidden");
  }

  const requestHash = requestHashOf(request, principal.id);
  const sameKey = priorDecisions.find((record) => record.idempotencyKey === request.idempotencyKey);
  if (sameKey) {
    if (sameKey.requestHash !== requestHash) return refuse("idempotency_key_reused");
    return { outcome: "replay", status: 200, record: sameKey, audit: audit("replayed", 200, null) };
  }
  const prior = priorDecisions.find((record) => record.proposalHash === proposal.proposalHash);
  if (prior) {
    if (prior.decision !== request.decision) return refuse("already_decided");
    return { outcome: "replay", status: 200, record: prior, audit: audit("replayed", 200, null) };
  }

  if (request.decision === "approve") {
    if (proposal.expiresAt !== undefined && Date.parse(now) >= Date.parse(proposal.expiresAt)) {
      return refuse("proposal_expired");
    }
    if (!sameRevision(currentRevision, proposal.subject.revision)) return refuse("stale_proposal");
  }

  const record: DecisionRecord = {
    capsuleId: proposal.capsuleId,
    proposalHash: proposal.proposalHash,
    decision: request.decision,
    actorId: principal.id,
    idempotencyKey: request.idempotencyKey,
    requestHash,
    subjectRevisionBefore: currentRevision,
    decidedAt: now,
    ...(request.reason !== undefined ? { reason: request.reason } : {}),
  };
  if (request.decision === "approve") {
    return { outcome: "apply", status: 200, record, audit: audit("applied", 200, null) };
  }
  return { outcome: "reject", status: 200, record, audit: audit("rejected", 200, null) };
}

/** The error body every adopter returns for a refusal. */
export function refusalBody(result: Extract<DecideResult, { outcome: "refuse" }>) {
  return { error: { code: result.code, message: result.message } };
}
