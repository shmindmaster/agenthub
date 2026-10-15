// execution-controls kit: receipt -> OpenTelemetry span.
//
// Attribute names follow the OpenTelemetry GenAI semantic conventions
// (github.com/open-telemetry/semantic-conventions-genai, checked 2026-10-14):
// `gen_ai.provider.name` (not the retired `gen_ai.system`), `gen_ai.usage.*`,
// `gen_ai.prompt.name`/`gen_ai.prompt.version`, `gen_ai.data_source.id`,
// `gen_ai.tool.name`. Rule checks and human decisions are not GenAI
// operations, so their spans carry only `app.receipt.*` attributes and the
// engine label says "rules" or "human" in plain view.
//
// Content attributes (`gen_ai.input.messages`, `gen_ai.output.messages`,
// `gen_ai.system_instructions`, retrieval query text) are never emitted: the
// receipt only holds hashes, and prompts are trade-secret.
//
// No dependency on @opentelemetry/api: pass any tracer with the API's
// `startSpan(name, options)` shape.

import type { Receipt } from "./receipt.ts";

export type AttributeValue = string | number | boolean | string[];

export interface ReceiptSpan {
  name: string;
  kind: "client" | "internal";
  attributes: Record<string, AttributeValue>;
  startTimeMs: number;
  endTimeMs: number;
  error: boolean;
}

function put(attributes: Record<string, AttributeValue>, key: string, value: AttributeValue | undefined) {
  if (value === undefined) return;
  if (Array.isArray(value) && value.length === 0) return;
  attributes[key] = value;
}

export function receiptSpan(receipt: Receipt): ReceiptSpan {
  const attributes: Record<string, AttributeValue> = {};
  let name: string;
  let kind: ReceiptSpan["kind"] = "internal";

  if (receipt.kind === "model_call" && receipt.model) {
    const operation = receipt.model.operation ?? "chat";
    name = `${operation} ${receipt.model.requestModel}`;
    kind = "client";
    put(attributes, "gen_ai.operation.name", operation);
    put(attributes, "gen_ai.provider.name", receipt.model.provider);
    put(attributes, "gen_ai.request.model", receipt.model.requestModel);
    put(attributes, "gen_ai.response.model", receipt.model.responseModel);
    put(attributes, "gen_ai.response.id", receipt.model.responseId);
    put(attributes, "gen_ai.response.finish_reasons", receipt.model.finishReasons);
    put(attributes, "gen_ai.usage.input_tokens", receipt.model.usage?.inputTokens);
    put(attributes, "gen_ai.usage.output_tokens", receipt.model.usage?.outputTokens);
    put(attributes, "gen_ai.usage.cache_read.input_tokens", receipt.model.usage?.cacheReadInputTokens);
    put(attributes, "gen_ai.usage.cache_write.input_tokens", receipt.model.usage?.cacheWriteInputTokens);
    put(attributes, "gen_ai.prompt.name", receipt.input.promptName);
    put(attributes, "gen_ai.prompt.version", receipt.input.promptRevision);
  } else if (receipt.kind === "retrieval") {
    const source = receipt.retrieval?.dataSourceId;
    name = source ? `retrieval ${source}` : "retrieval";
    kind = "client";
    put(attributes, "gen_ai.operation.name", "retrieval");
    put(attributes, "gen_ai.data_source.id", source);
    put(attributes, "gen_ai.retrieval.top_k", receipt.retrieval?.topK);
    put(attributes, "gen_ai.provider.name", receipt.model?.provider);
    put(attributes, "gen_ai.request.model", receipt.model?.requestModel);
  } else if (receipt.kind === "tool_call" && receipt.tool) {
    name = `execute_tool ${receipt.tool.name}`;
    put(attributes, "gen_ai.operation.name", "execute_tool");
    put(attributes, "gen_ai.tool.name", receipt.tool.name);
    put(attributes, "gen_ai.tool.call.id", receipt.tool.callId);
  } else {
    name = receipt.kind === "decision" ? "decision" : "rule_check";
  }

  put(attributes, "app.receipt.id", receipt.receiptId);
  put(attributes, "app.receipt.hash", receipt.receiptHash);
  put(attributes, "app.receipt.kind", receipt.kind);
  put(attributes, "app.receipt.engine", receipt.engine);
  put(attributes, "app.receipt.replay_key", receipt.replayKey);
  put(attributes, "app.receipt.outcome", receipt.outcome.status);
  put(attributes, "app.receipt.input_hash", receipt.input.hash);
  put(attributes, "app.receipt.output_hash", receipt.outcome.outputHash);
  put(attributes, "app.receipt.policy_revision", receipt.input.policyRevision);
  put(attributes, "app.receipt.rule_pack_revision", receipt.input.rulePackRevision);
  put(attributes, "app.receipt.retrieval_hash", receipt.retrievalHash);
  put(attributes, "app.receipt.fallback_engine", receipt.outcome.fallbackEngine);
  put(attributes, "app.tenant.id", receipt.tenantId);
  if (receipt.approval) {
    put(attributes, "app.approval.capsule_id", receipt.approval.capsuleId);
    put(attributes, "app.approval.proposal_hash", receipt.approval.proposalHash);
    put(attributes, "app.approval.decision", receipt.approval.decision);
  }

  const error = receipt.outcome.status === "failed";
  if (error) put(attributes, "error.type", receipt.outcome.code ?? "_OTHER");

  const endTimeMs = Date.parse(receipt.occurredAt);
  const startTimeMs = endTimeMs - (receipt.durationMs ?? 0);
  return { name, kind, attributes, startTimeMs, endTimeMs, error };
}

/** Minimal structural view of the @opentelemetry/api Tracer. */
export interface TracerLike {
  startSpan(
    name: string,
    options?: { kind?: number; attributes?: Record<string, AttributeValue>; startTime?: number },
  ): { setStatus(status: { code: number; message?: string }): unknown; end(endTime?: number): void };
}

// @opentelemetry/api enum values, inlined to keep the kit dependency-free.
const SPAN_KIND = { internal: 0, client: 2 } as const;
const STATUS_ERROR = 2;

export function emitReceiptSpan(tracer: TracerLike, receipt: Receipt): ReceiptSpan {
  const shape = receiptSpan(receipt);
  const span = tracer.startSpan(shape.name, {
    kind: SPAN_KIND[shape.kind],
    attributes: shape.attributes,
    startTime: shape.startTimeMs,
  });
  if (shape.error) span.setStatus({ code: STATUS_ERROR, message: receipt.outcome.code });
  span.end(shape.endTimeMs);
  return shape;
}
