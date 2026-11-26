"""LiteLLM CustomLogger hook for per-alias reasoning and system-message normalization.

1. Normalizes omitted or unsupported reasoning_effort / reasoning.effort values
   (mapping 'high' -> 'medium' for Qwen/Flash-Next backends that accept
   low/medium/xhigh) without silently switching checkpoints, falling back to
   paid providers, or overriding valid explicit reasoning requests such as 'xhigh'.
2. Coalesces multiple or mid-conversation system/developer messages into a single
   leading system instruction so llama.cpp Qwen Jinja templates (and vLLM) never
   fail with 'System message must be at the beginning' on Codex /v1/responses.
"""

from __future__ import annotations

from typing import Any, Literal

try:
    from litellm.integrations.custom_logger import CustomLogger
except Exception:  # pragma: no cover - allows standalone unit testing without litellm installed
    class CustomLogger:  # type: ignore[no-redef]
        pass


REASONING_POLICY: dict[str, dict[str, Any]] = {
    "qwen3.8-27b-unc-q8": {
        "default": "medium",
        "supported": {"low", "medium", "xhigh"},
        "aliases": {"high": "medium"},
        "vllm_chat_template": True,
    },
    "inkling2-min-26b-unc-q8-128k": {
        "default": "medium",
        "supported": {"low", "medium", "xhigh"},
        "aliases": {"high": "medium"},
        "vllm_chat_template": False,
    },
}


def _extract_text(content: Any) -> str:
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str) and item.strip():
                parts.append(item.strip())
            elif isinstance(item, dict):
                itype = str(item.get("type") or "")
                if itype in ("", "text", "input_text", "output_text"):
                    txt = item.get("text")
                    if isinstance(txt, str) and txt.strip():
                        parts.append(txt.strip())
        return "\n".join(parts)
    return ""


def _coalesce_system_messages(data: dict[str, Any]) -> None:
    # 1. Responses API: extract system/developer items from input[] into instructions.
    if isinstance(data.get("input"), list):
        sys_chunks: list[str] = []
        existing_inst = _extract_text(data.get("instructions"))
        if existing_inst:
            sys_chunks.append(existing_inst)
        kept: list[Any] = []
        for item in data["input"]:
            if isinstance(item, dict) and str(item.get("role") or "").lower() in ("system", "developer"):
                txt = _extract_text(item.get("content"))
                if txt:
                    sys_chunks.append(txt)
            else:
                kept.append(item)
        if sys_chunks:
            data["instructions"] = "\n\n".join(sys_chunks)
        data["input"] = kept

    # 2. Chat Completions: coalesce all system/developer messages to index 0.
    if isinstance(data.get("messages"), list):
        sys_chunks = []
        other_msgs: list[Any] = []
        for msg in data["messages"]:
            if isinstance(msg, dict) and str(msg.get("role") or "").lower() in ("system", "developer"):
                txt = _extract_text(msg.get("content"))
                if txt:
                    sys_chunks.append(txt)
            else:
                other_msgs.append(msg)
        if sys_chunks:
            data["messages"] = [{"role": "system", "content": "\n\n".join(sys_chunks)}, *other_msgs]
        else:
            data["messages"] = other_msgs


def _resolve_effort(raw_effort: Any, policy: dict[str, Any]) -> str:
    supported: set[str] = policy["supported"]
    aliases: dict[str, str] = policy["aliases"]
    default_effort: str = policy["default"]
    if raw_effort is None or str(raw_effort).strip() == "":
        return default_effort
    effort_str = str(raw_effort).strip().lower()
    effort = aliases.get(effort_str, effort_str)
    if effort not in supported:
        return default_effort
    return effort


def normalize_reasoning_payload(data: dict[str, Any], call_type: str | None = None) -> dict[str, Any]:
    """Normalize reasoning_effort, Responses reasoning.effort, and leading system messages."""
    model = str(data.get("model") or "").strip()
    model_key = model.split("/", 1)[-1] if "/" in model else model

    policy = REASONING_POLICY.get(model_key)
    if policy is None:
        return data

    _coalesce_system_messages(data)

    is_responses = call_type == "responses" or "input" in data or isinstance(data.get("reasoning"), dict)
    raw_effort = data.get("reasoning_effort")
    if is_responses and isinstance(data.get("reasoning"), dict):
        raw_effort = data["reasoning"].get("effort") or raw_effort

    effort = _resolve_effort(raw_effort, policy)

    if is_responses:
        reasoning_obj = data.get("reasoning")
        if not isinstance(reasoning_obj, dict):
            reasoning_obj = {}
            data["reasoning"] = reasoning_obj
        reasoning_obj["effort"] = effort
        if "messages" in data:
            data["reasoning_effort"] = effort
    else:
        data["reasoning_effort"] = effort

    if policy.get("vllm_chat_template") and "messages" in data:
        extra_body = data.get("extra_body")
        if not isinstance(extra_body, dict):
            extra_body = {}
            data["extra_body"] = extra_body
        if "chat_template_kwargs" not in extra_body:
            extra_body["chat_template_kwargs"] = {
                "enable_thinking": True,
                "reasoning_effort": effort,
            }

    return data


class ReasoningNormalizer(CustomLogger):
    """Pre-call hook that applies REASONING_POLICY and system coalescing to incoming requests."""

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict[str, Any],
        call_type: Literal[
            "completion",
            "text_completion",
            "embeddings",
            "image_generation",
            "moderation",
            "audio_transcription",
            "pass_through_endpoint",
            "rerank",
            "responses",
        ],
    ) -> dict[str, Any]:
        return normalize_reasoning_payload(data, call_type=call_type)


proxy_handler_instance = ReasoningNormalizer()
