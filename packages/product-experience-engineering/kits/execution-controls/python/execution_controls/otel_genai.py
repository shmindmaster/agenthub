"""execution-controls kit: receipt -> OpenTelemetry span.

Attribute names follow the OpenTelemetry GenAI semantic conventions
(github.com/open-telemetry/semantic-conventions-genai, checked 2026-10-14):
``gen_ai.provider.name`` (not the retired ``gen_ai.system``), ``gen_ai.usage.*``,
``gen_ai.prompt.name``/``gen_ai.prompt.version``, ``gen_ai.data_source.id``,
``gen_ai.tool.name``. Rule checks and human decisions are not GenAI operations,
so their spans carry only ``app.receipt.*`` attributes.

Content attributes (input/output messages, system instructions, retrieval query
text, tool arguments and results) are never emitted.

``receipt_span`` has no dependencies. ``emit_receipt_span`` needs
``opentelemetry-api`` and takes any tracer from it.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Mapping


def _put(attributes: dict[str, Any], key: str, value: Any) -> None:
    if value is None:
        return
    if isinstance(value, (list, tuple)):
        if not value:
            return
        value = list(value)
    attributes[key] = value


def _epoch_ms(timestamp: str) -> int:
    return round(datetime.fromisoformat(timestamp.replace("Z", "+00:00")).timestamp() * 1000)


def receipt_span(receipt: Mapping[str, Any]) -> dict[str, Any]:
    attributes: dict[str, Any] = {}
    kind = "internal"
    model = receipt.get("model") or {}
    usage = model.get("usage") or {}
    receipt_input = receipt.get("input") or {}
    outcome = receipt.get("outcome") or {}
    retrieval = receipt.get("retrieval") or {}
    tool = receipt.get("tool")

    if receipt["kind"] == "model_call" and model:
        operation = model.get("operation") or "chat"
        name = f"{operation} {model['requestModel']}"
        kind = "client"
        _put(attributes, "gen_ai.operation.name", operation)
        _put(attributes, "gen_ai.provider.name", model.get("provider"))
        _put(attributes, "gen_ai.request.model", model.get("requestModel"))
        _put(attributes, "gen_ai.response.model", model.get("responseModel"))
        _put(attributes, "gen_ai.response.id", model.get("responseId"))
        _put(attributes, "gen_ai.response.finish_reasons", model.get("finishReasons"))
        _put(attributes, "gen_ai.usage.input_tokens", usage.get("inputTokens"))
        _put(attributes, "gen_ai.usage.output_tokens", usage.get("outputTokens"))
        _put(attributes, "gen_ai.usage.cache_read.input_tokens", usage.get("cacheReadInputTokens"))
        _put(attributes, "gen_ai.usage.cache_write.input_tokens", usage.get("cacheWriteInputTokens"))
        _put(attributes, "gen_ai.prompt.name", receipt_input.get("promptName"))
        _put(attributes, "gen_ai.prompt.version", receipt_input.get("promptRevision"))
    elif receipt["kind"] == "retrieval":
        source = retrieval.get("dataSourceId")
        name = f"retrieval {source}" if source else "retrieval"
        kind = "client"
        _put(attributes, "gen_ai.operation.name", "retrieval")
        _put(attributes, "gen_ai.data_source.id", source)
        _put(attributes, "gen_ai.retrieval.top_k", retrieval.get("topK"))
        _put(attributes, "gen_ai.provider.name", model.get("provider"))
        _put(attributes, "gen_ai.request.model", model.get("requestModel"))
    elif receipt["kind"] == "tool_call" and tool:
        name = f"execute_tool {tool['name']}"
        _put(attributes, "gen_ai.operation.name", "execute_tool")
        _put(attributes, "gen_ai.tool.name", tool.get("name"))
        _put(attributes, "gen_ai.tool.call.id", tool.get("callId"))
    else:
        name = "decision" if receipt["kind"] == "decision" else "rule_check"

    _put(attributes, "app.receipt.id", receipt.get("receiptId"))
    _put(attributes, "app.receipt.hash", receipt.get("receiptHash"))
    _put(attributes, "app.receipt.kind", receipt.get("kind"))
    _put(attributes, "app.receipt.engine", receipt.get("engine"))
    _put(attributes, "app.receipt.replay_key", receipt.get("replayKey"))
    _put(attributes, "app.receipt.outcome", outcome.get("status"))
    _put(attributes, "app.receipt.input_hash", receipt_input.get("hash"))
    _put(attributes, "app.receipt.output_hash", outcome.get("outputHash"))
    _put(attributes, "app.receipt.policy_revision", receipt_input.get("policyRevision"))
    _put(attributes, "app.receipt.rule_pack_revision", receipt_input.get("rulePackRevision"))
    _put(attributes, "app.receipt.retrieval_hash", receipt.get("retrievalHash"))
    _put(attributes, "app.receipt.fallback_engine", outcome.get("fallbackEngine"))
    _put(attributes, "app.tenant.id", receipt.get("tenantId"))
    approval = receipt.get("approval")
    if approval:
        _put(attributes, "app.approval.capsule_id", approval.get("capsuleId"))
        _put(attributes, "app.approval.proposal_hash", approval.get("proposalHash"))
        _put(attributes, "app.approval.decision", approval.get("decision"))

    error = outcome.get("status") == "failed"
    if error:
        _put(attributes, "error.type", outcome.get("code") or "_OTHER")

    end_ms = _epoch_ms(receipt["occurredAt"])
    start_ms = end_ms - int(receipt.get("durationMs") or 0)
    return {"name": name, "kind": kind, "attributes": attributes, "startTimeMs": start_ms, "endTimeMs": end_ms, "error": error}


def emit_receipt_span(tracer: Any, receipt: Mapping[str, Any]) -> dict[str, Any]:
    """Emit one finished span for ``receipt`` through an opentelemetry-api tracer."""
    from opentelemetry.trace import SpanKind, Status, StatusCode

    shape = receipt_span(receipt)
    span = tracer.start_span(
        shape["name"],
        kind=SpanKind.CLIENT if shape["kind"] == "client" else SpanKind.INTERNAL,
        attributes=shape["attributes"],
        start_time=shape["startTimeMs"] * 1_000_000,
    )
    if shape["error"]:
        span.set_status(Status(StatusCode.ERROR, (receipt.get("outcome") or {}).get("code")))
    span.end(end_time=shape["endTimeMs"] * 1_000_000)
    return shape
