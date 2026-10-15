// execution-controls kit: receipts (spec: ../spec/receipt.md).
//
// A receipt records one consequential step (a model call, a rule check, a
// retrieval, a tool call, a human decision) well enough to replay it: what
// went in (by hash), which engine and revisions ran, what evidence it used,
// and what came out (by hash). Receipts never carry prompt text, document
// text or personal data; they carry hashes and ids.

import { canonicalHash } from "./canonical-json.ts";
import type { Decision, SubjectRef } from "./approval-capsule.ts";

export const RECEIPT_VERSION = "receipt/v1";

export type ReceiptKind = "model_call" | "rule_check" | "retrieval" | "tool_call" | "decision";
export type Engine = "model" | "rules" | "model+rules" | "human";
export type OutcomeStatus = "succeeded" | "failed" | "refused" | "fallback";

export interface ReceiptInputRef {
  /** Hash of the exact input the step consumed. */
  hash: string;
  promptName?: string;
  promptRevision?: string;
  policyRevision?: string;
  rulePackRevision?: string;
}

export interface RetrievedDocument {
  id: string;
  hash: string;
  revision?: string;
  /** Scores are strings so they hash identically in every language. */
  score?: string;
}

export interface RetrievalRef {
  dataSourceId?: string;
  queryHash: string;
  topK?: number;
  documents: RetrievedDocument[];
}

export interface ModelRef {
  /** OTel `gen_ai.provider.name` value, e.g. "anthropic". */
  provider: string;
  requestModel: string;
  responseModel?: string;
  /** OTel `gen_ai.operation.name`; defaults to "chat". */
  operation?: string;
  responseId?: string;
  finishReasons?: string[];
  usage?: {
    inputTokens?: number;
    outputTokens?: number;
    cacheReadInputTokens?: number;
    cacheWriteInputTokens?: number;
  };
}

export interface EvidenceItem {
  ref: string;
  hash: string;
  span?: { start: number; end: number };
}

export interface ReceiptOutcome {
  status: OutcomeStatus;
  code?: string;
  outputHash?: string;
  /** For `fallback`: which engine produced the answer instead. */
  fallbackEngine?: Engine;
}

export interface ReceiptInput {
  receiptId: string;
  tenantId: string;
  occurredAt: string;
  durationMs?: number;
  kind: ReceiptKind;
  engine: Engine;
  subject?: SubjectRef;
  input: ReceiptInputRef;
  retrieval?: RetrievalRef;
  model?: ModelRef;
  tool?: { name: string; callId?: string };
  evidence?: EvidenceItem[];
  outcome: ReceiptOutcome;
  approval?: { capsuleId: string; proposalHash: string; decision: Decision; actorId: string };
  trace?: { traceId: string; spanId: string };
}

export interface Receipt extends ReceiptInput {
  receiptVersion: typeof RECEIPT_VERSION;
  retrievalHash?: string;
  replayKey: string;
  prevReceiptHash: string | null;
  receiptHash: string;
}

/** `null` means absent, at every depth of a receipt input. Only plain objects and arrays are walked. */
function prune<T>(value: T): T {
  if (Array.isArray(value)) return value.map((item) => prune(item)) as T;
  if (value !== null && typeof value === "object") {
    const proto = Object.getPrototypeOf(value);
    if (proto === Object.prototype || proto === null) {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .filter(([, item]) => item != null)
          .map(([key, item]) => [key, prune(item)]),
      ) as T;
    }
  }
  return value;
}

/** A retrieval object without a `documents` key is absent: it has no retrievalHash and no part in the replay key. */
function hasRetrieval(retrieval: unknown): retrieval is RetrievalRef {
  return retrieval != null && typeof retrieval === "object" && (retrieval as { documents?: unknown }).documents != null;
}

export function retrievalHashOf(retrieval: RetrievalRef): string {
  return canonicalHash(retrieval);
}

/** Two receipts with the same replay key ran the same step on the same inputs. */
export function replayKeyOf(input: ReceiptInput): string {
  return canonicalHash({
    kind: input.kind,
    engine: input.engine,
    input: input.input,
    retrievalHash: hasRetrieval(input.retrieval) ? retrievalHashOf(input.retrieval) : undefined,
    requestModel: input.model?.requestModel ?? undefined,
    tool: input.tool?.name ?? undefined,
  });
}

export function receiptHashOf(receipt: Omit<Receipt, "receiptHash"> | Receipt): string {
  const { receiptHash: _ignored, ...rest } = receipt as Receipt;
  return canonicalHash(rest);
}

export function createReceipt(input: ReceiptInput, prev: Receipt | null = null): Receipt {
  const clean = prune(input);
  const body: Omit<Receipt, "receiptHash"> = {
    ...clean,
    receiptVersion: RECEIPT_VERSION,
    ...(hasRetrieval(clean.retrieval) ? { retrievalHash: retrievalHashOf(clean.retrieval) } : {}),
    replayKey: replayKeyOf(clean),
    prevReceiptHash: prev ? prev.receiptHash : null,
  };
  return { ...body, receiptHash: receiptHashOf(body) };
}

export function verifyReceipt(receipt: Receipt): boolean {
  if (receipt.receiptVersion !== RECEIPT_VERSION) return false;
  if (receiptHashOf(receipt) !== receipt.receiptHash) return false;
  if (receipt.replayKey !== replayKeyOf(receipt)) return false;
  if (hasRetrieval(receipt.retrieval) && receipt.retrievalHash !== retrievalHashOf(receipt.retrieval)) return false;
  return true;
}

export interface ChainVerdict {
  ok: boolean;
  /** Index of the first receipt that fails, or -1. */
  brokenAt: number;
  reason?: "receipt_hash" | "chain_link";
}

/**
 * Verify a chain from a known head: the first receipt's `prevReceiptHash` must
 * equal `expectedPrev` (null for a chain that starts at its beginning). Dropping
 * receipts from the tail is only detectable against an externally held anchor.
 */
export function verifyChain(receipts: Receipt[], expectedPrev: string | null = null): ChainVerdict {
  for (let index = 0; index < receipts.length; index += 1) {
    const receipt = receipts[index];
    if (!verifyReceipt(receipt)) return { ok: false, brokenAt: index, reason: "receipt_hash" };
    const wantPrev = index === 0 ? expectedPrev : receipts[index - 1].receiptHash;
    if (receipt.prevReceiptHash !== wantPrev) return { ok: false, brokenAt: index, reason: "chain_link" };
  }
  return { ok: true, brokenAt: -1 };
}

export interface ReplayComparison {
  sameStep: boolean;
  sameOutput: boolean;
}

/** Compare a replayed receipt to the original. */
export function compareReplay(original: Receipt, replay: Receipt): ReplayComparison {
  return {
    sameStep: original.replayKey === replay.replayKey,
    sameOutput:
      original.outcome.outputHash !== undefined && original.outcome.outputHash === replay.outcome.outputHash,
  };
}
