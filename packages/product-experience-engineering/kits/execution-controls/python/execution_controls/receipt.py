"""execution-controls kit: receipts (spec: ../../spec/receipt.md).

A receipt records one consequential step (a model call, a rule check, a
retrieval, a tool call, a human decision) well enough to replay it: what went
in (by hash), which engine and revisions ran, what evidence it used, and what
came out (by hash). Receipts never carry prompt text, document text or personal
data; they carry hashes and ids.
"""

from __future__ import annotations

from typing import Any, Mapping, Sequence

from .canonical_json import canonical_hash

RECEIPT_VERSION = "receipt/v1"


def _prune(value: Any) -> Any:
    """``None`` means absent everywhere in a receipt input."""
    if isinstance(value, Mapping):
        return {key: _prune(item) for key, item in value.items() if item is not None}
    if isinstance(value, (list, tuple)):
        return [_prune(item) for item in value]
    return value


def retrieval_hash_of(retrieval: Mapping[str, Any]) -> str:
    return canonical_hash(retrieval)


def replay_key_of(receipt: Mapping[str, Any]) -> str:
    """Two receipts with the same replay key ran the same step on the same inputs."""
    retrieval = receipt.get("retrieval")
    model = receipt.get("model") or {}
    tool = receipt.get("tool") or {}
    body = {
        "kind": receipt["kind"],
        "engine": receipt["engine"],
        "input": receipt["input"],
        "retrievalHash": retrieval_hash_of(retrieval) if retrieval else None,
        "requestModel": model.get("requestModel"),
        "tool": tool.get("name"),
    }
    return canonical_hash({key: value for key, value in body.items() if value is not None})


def receipt_hash_of(receipt: Mapping[str, Any]) -> str:
    return canonical_hash({key: value for key, value in receipt.items() if key != "receiptHash"})


def create_receipt(receipt_input: Mapping[str, Any], prev: Mapping[str, Any] | None = None) -> dict[str, Any]:
    body: dict[str, Any] = _prune(dict(receipt_input))
    body["receiptVersion"] = RECEIPT_VERSION
    if body.get("retrieval"):
        body["retrievalHash"] = retrieval_hash_of(body["retrieval"])
    body["replayKey"] = replay_key_of(body)
    body["prevReceiptHash"] = prev["receiptHash"] if prev else None
    body["receiptHash"] = receipt_hash_of(body)
    return body


def verify_receipt(receipt: Mapping[str, Any]) -> bool:
    if receipt.get("receiptVersion") != RECEIPT_VERSION:
        return False
    if receipt_hash_of(receipt) != receipt.get("receiptHash"):
        return False
    if replay_key_of(receipt) != receipt.get("replayKey"):
        return False
    retrieval = receipt.get("retrieval")
    if retrieval and receipt.get("retrievalHash") != retrieval_hash_of(retrieval):
        return False
    return True


def verify_chain(receipts: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    for index, receipt in enumerate(receipts):
        if not verify_receipt(receipt):
            return {"ok": False, "brokenAt": index, "reason": "receipt_hash"}
        expected_prev = receipt.get("prevReceiptHash") if index == 0 else receipts[index - 1]["receiptHash"]
        if receipt.get("prevReceiptHash") != expected_prev:
            return {"ok": False, "brokenAt": index, "reason": "chain_link"}
    return {"ok": True, "brokenAt": -1}


def compare_replay(original: Mapping[str, Any], replay: Mapping[str, Any]) -> dict[str, bool]:
    output = original.get("outcome", {}).get("outputHash")
    return {
        "sameStep": original["replayKey"] == replay["replayKey"],
        "sameOutput": output is not None and output == replay.get("outcome", {}).get("outputHash"),
    }
