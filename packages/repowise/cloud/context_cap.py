"""Bounded context for RepoWise cloud answers (SH-4410).

Caps what a RepoWise MCP tools/call result hands back to an agent: a total
byte budget and an item-count budget, applied to the ``content`` array of the
CallToolResult. An oversized response is never passed through -- it is cut and
carries an explicit marker so the agent can see the answer was capped and ask
for the rest deliberately (or accept the bounded summary).

Stdlib only. Imported by repowise_bridge_capped.py and by the unit test.
"""

from __future__ import annotations

import json

MARKER_PREFIX = "[repowise-context-cap]"

# Defaults a workstation session gets when the env vars are unset. Pre-task
# triage (get_context) and post-diff summaries both land in the same budget.
DEFAULT_MAX_BYTES = 65536
DEFAULT_MAX_ITEMS = 40


def _item_bytes(item: dict) -> int:
    """UTF-8 size of one content item's payload."""
    if isinstance(item, dict) and item.get("type") == "text":
        return len(str(item.get("text", "")).encode("utf-8"))
    return len(json.dumps(item, ensure_ascii=False).encode("utf-8"))


def _marker(kept_bytes: int, total_bytes: int, kept_items: int, total_items: int) -> dict:
    return {
        "type": "text",
        "text": (
            f"{MARKER_PREFIX} response truncated: kept {kept_bytes} of {total_bytes} bytes, "
            f"{kept_items} of {total_items} items. The rest was cut by the context cap; "
            "ask for a narrower target instead of re-reading everything."
        ),
    }


def cap_tool_result(result: dict, max_bytes: int = DEFAULT_MAX_BYTES,
                    max_items: int = DEFAULT_MAX_ITEMS) -> tuple[dict, dict]:
    """Cap one CallToolResult-shaped dict. Returns (result, stats).

    Stats: {truncated, kept_bytes, total_bytes, kept_items, total_items}.
    A result without a content list is returned unchanged.
    """
    stats = {"truncated": False, "kept_bytes": 0, "total_bytes": 0,
             "kept_items": 0, "total_items": 0}
    if not isinstance(result, dict):
        return result, stats
    content = result.get("content")
    if not isinstance(content, list):
        return result, stats

    sizes = [_item_bytes(item) for item in content]
    stats["total_items"] = len(content)
    stats["total_bytes"] = sum(sizes)

    kept: list[dict] = []
    budget = max_bytes
    for item, size in zip(content, sizes):
        if len(kept) >= max_items:
            break
        if size <= budget:
            kept.append(item)
            budget -= size
            continue
        # A single oversized text item is cut mid-text rather than dropped, so
        # the agent keeps the head of the answer plus the marker.
        if isinstance(item, dict) and item.get("type") == "text" and budget > 0:
            trimmed = dict(item)
            text = str(item.get("text", ""))
            encoded = text.encode("utf-8")
            trimmed["text"] = encoded[:budget].decode("utf-8", "ignore")
            kept.append(trimmed)
            budget = 0
        break

    stats["kept_items"] = len(kept)
    stats["kept_bytes"] = sum(_item_bytes(i) for i in kept)
    stats["truncated"] = (stats["kept_items"] < stats["total_items"]
                          or stats["kept_bytes"] < stats["total_bytes"])
    if stats["truncated"]:
        kept.append(_marker(stats["kept_bytes"], stats["total_bytes"],
                            stats["kept_items"], stats["total_items"]))
    capped = dict(result)
    capped["content"] = kept
    return capped, stats


def cap_response(message: dict, max_bytes: int = DEFAULT_MAX_BYTES,
                 max_items: int = DEFAULT_MAX_ITEMS) -> tuple[dict, dict]:
    """Cap a JSON-RPC response message if it carries a CallToolResult.

    Anything else (errors, notifications, non-content results) passes through.
    Returns (message, stats) with the same stats shape as cap_tool_result.
    """
    result = message.get("result") if isinstance(message, dict) else None
    if not isinstance(result, dict) or not isinstance(result.get("content"), list):
        return message, {"truncated": False, "kept_bytes": 0, "total_bytes": 0,
                         "kept_items": 0, "total_items": 0}
    capped, stats = cap_tool_result(result, max_bytes, max_items)
    out = dict(message)
    out["result"] = capped
    return out, stats
