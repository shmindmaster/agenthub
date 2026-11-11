"""Bounded context for RepoWise cloud answers (SH-4410).

Caps what a RepoWise MCP tools/call result hands back to an agent: a total
byte budget covering the WHOLE serialized result (so ``structuredContent`` and
every other field count, not just ``content``) and an item-count budget for
the ``content`` array. A JSON-RPC batch is capped element by element. An
oversized response is never passed through -- it is cut and carries an
explicit marker so the agent can see the answer was capped and ask for the
rest deliberately (or accept the bounded summary).

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


def _result_bytes(result) -> int:
    """UTF-8 size of the whole serialized result, every field included."""
    return len(json.dumps(result, ensure_ascii=False).encode("utf-8"))


# Room kept back for the truncation marker itself so the serialized result
# stays under the byte cap after the marker is appended.
_MARKER_RESERVE = 256


def _marker(kept_bytes: int, total_bytes: int, kept_items: int, total_items: int,
            dropped_structured: bool = False) -> dict:
    note = (" structuredContent was dropped entirely."
            if dropped_structured else "")
    return {
        "type": "text",
        "text": (
            f"{MARKER_PREFIX} response truncated: kept {kept_bytes} of {total_bytes} bytes, "
            f"{kept_items} of {total_items} items.{note} The rest was cut by the context cap; "
            "ask for a narrower target instead of re-reading everything."
        ),
    }


def _cap_tool_result_inner(result: dict, max_bytes: int = DEFAULT_MAX_BYTES,
                           max_items: int = DEFAULT_MAX_ITEMS) -> tuple[dict, dict]:
    """Cap one CallToolResult-shaped dict. Returns (result, stats).

    The byte budget covers the whole serialized result, so a result whose
    ``structuredContent`` (or any other field) is oversized cannot slip past
    the cap: structuredContent is dropped first with a marker note, then the
    content list is trimmed to whatever budget remains. Stats:
    {truncated, kept_bytes, total_bytes, kept_items, total_items}.
    """
    stats = {"truncated": False, "kept_bytes": 0, "total_bytes": 0,
             "kept_items": 0, "total_items": 0}
    if not isinstance(result, dict):
        return result, stats
    capped = dict(result)

    dropped_structured = False
    if "structuredContent" in capped and _result_bytes(capped) > max_bytes:
        del capped["structuredContent"]
        dropped_structured = True

    content = capped.get("content")
    if not isinstance(content, list):
        stats["truncated"] = dropped_structured
        return capped, stats

    sizes = [_item_bytes(item) for item in content]
    stats["total_items"] = len(content)
    stats["total_bytes"] = sum(sizes)

    # The content array gets the budget left after every other result field
    # (structuredContent, isError, annotations, ...) and the marker reserve.
    skeleton = dict(capped)
    skeleton["content"] = []
    budget = max(0, max_bytes - _result_bytes(skeleton) - _MARKER_RESERVE)

    kept: list[dict] = []
    for item, size in zip(content, sizes):
        if len(kept) >= max_items:
            break
        if size <= budget:
            kept.append(item)
            budget -= size
            continue
        # A single oversized text item is cut mid-text rather than dropped, so
        # the agent keeps the head of the answer plus the marker. Slicing the
        # UTF-8 encoding and decoding with "ignore" drops a partial trailing
        # multi-byte character instead of emitting mojibake.
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
    stats["truncated"] = (dropped_structured
                          or stats["kept_items"] < stats["total_items"]
                          or stats["kept_bytes"] < stats["total_bytes"])
    if stats["truncated"]:
        kept.append(_marker(stats["kept_bytes"], stats["total_bytes"],
                            stats["kept_items"], stats["total_items"],
                            dropped_structured))
    capped["content"] = kept
    return capped, stats


# Fields of a CallToolResult that are kept when the result has to be cut down
# to its essentials. Everything else (_meta, annotations, vendor extensions)
# is dropped rather than allowed to carry an uncapped payload.
_ESSENTIAL_FIELDS = ("content", "isError")


def _wire_bytes(result) -> int:
    """Size of the result exactly as the bridge writes it (json.dumps default
    escaping, so non-ASCII text counts at its escaped length)."""
    return len(json.dumps(result).encode("utf-8"))


def cap_tool_result(result: dict, max_bytes: int = DEFAULT_MAX_BYTES,
                    max_items: int = DEFAULT_MAX_ITEMS) -> tuple[dict, dict]:
    """Cap one CallToolResult-shaped dict so its serialized size on the wire
    never exceeds ``max_bytes``. Returns (result, stats).

    Order of cuts: structuredContent, then the content list, then every
    non-essential field (``_meta`` and the like), then the remaining text.
    The last resort is a result holding only the truncation marker.
    """
    pre_dropped: list[str] = []
    if isinstance(result, dict):
        # Oversized side fields go first, so they cannot use up the budget
        # that the actual answer (content) should get.
        side = {k: v for k, v in result.items() if k not in _ESSENTIAL_FIELDS and k != "structuredContent"}
        if side and _wire_bytes(side) > max_bytes // 4:
            pre_dropped = sorted(side)
            result = {k: v for k, v in result.items() if k not in side}
    capped, stats = _cap_tool_result_inner(result, max_bytes, max_items)
    if pre_dropped and isinstance(capped, dict):
        stats["truncated"] = True
        content = capped.get("content")
        capped["content"] = (list(content) if isinstance(content, list) else []) + [{
            "type": "text",
            "text": f"{MARKER_PREFIX} dropped oversized result fields: {', '.join(pre_dropped)[:200]}."}]
    if not isinstance(capped, dict) or _wire_bytes(capped) <= max_bytes:
        return capped, stats

    stats["truncated"] = True
    extras = [k for k in capped if k not in _ESSENTIAL_FIELDS]
    if extras:
        capped = {k: v for k, v in capped.items() if k in _ESSENTIAL_FIELDS}
        note = {"type": "text",
                "text": f"{MARKER_PREFIX} dropped oversized result fields: {', '.join(sorted(extras))[:200]}."}
        content = capped.get("content")
        capped["content"] = (list(content) if isinstance(content, list) else []) + [note]

    content = capped.get("content")
    if not isinstance(content, list):
        content = []
    content = list(content)
    # Shrink from the front of the payload items (markers sit at the end) until
    # the wire size fits: cut text items in halves, then drop items.
    guard = 0
    while _wire_bytes({**capped, "content": content}) > max_bytes and guard < 10000:
        guard += 1
        payload = [i for i, item in enumerate(content)
                   if not (isinstance(item, dict) and str(item.get("text", "")).startswith(MARKER_PREFIX))]
        if not payload:
            break
        idx = payload[-1]
        item = content[idx]
        text = str(item.get("text", "")) if isinstance(item, dict) and item.get("type") == "text" else ""
        if len(text) > 64:
            trimmed = dict(item)
            trimmed["text"] = text[: len(text) // 2]
            content[idx] = trimmed
        else:
            del content[idx]
    capped["content"] = content
    if _wire_bytes(capped) > max_bytes:
        capped = {"content": [{"type": "text", "text": f"{MARKER_PREFIX} response truncated."}]}
        if result.get("isError") is not None:
            capped["isError"] = result.get("isError")
    stats["kept_items"] = sum(1 for item in capped["content"]
                              if not (isinstance(item, dict) and str(item.get("text", "")).startswith(MARKER_PREFIX)))
    return capped, stats


def cap_response(message, max_bytes: int = DEFAULT_MAX_BYTES,
                 max_items: int = DEFAULT_MAX_ITEMS):
    """Cap a JSON-RPC response message if it carries a CallToolResult.

    A JSON-RPC batch (a list of messages) is capped element by element.
    Anything else (errors, notifications, non-content results) passes through.
    Returns (message, stats) with the same stats shape as cap_tool_result,
    aggregated across elements for a batch.
    """
    empty = {"truncated": False, "kept_bytes": 0, "total_bytes": 0,
             "kept_items": 0, "total_items": 0}
    if isinstance(message, list):
        stats = dict(empty)
        out = []
        for element in message:
            capped_el, el_stats = cap_response(element, max_bytes, max_items)
            out.append(capped_el)
            stats["truncated"] = stats["truncated"] or el_stats["truncated"]
            for key in ("kept_bytes", "total_bytes", "kept_items", "total_items"):
                stats[key] += el_stats[key]
        return out, stats
    result = message.get("result") if isinstance(message, dict) else None
    if not isinstance(result, dict):
        return message, empty
    capped, stats = cap_tool_result(result, max_bytes, max_items)
    out = dict(message)
    out["result"] = capped
    return out, stats
