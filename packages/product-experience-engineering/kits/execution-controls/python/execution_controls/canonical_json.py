"""execution-controls kit: canonical JSON and hashing.

The canonical form is the RFC 8785 (JCS) form restricted to values that
serialize identically in every language the fleet uses: objects, arrays,
strings, booleans, null, and integers within +/-(2**53 - 1). Non-integer
numbers are refused, so money, scores and ratios travel as strings. That one
restriction is what lets this module and the TypeScript one agree byte for
byte without porting the ECMAScript number printer.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping

MAX_SAFE = 2**53 - 1


class CanonicalJsonError(ValueError):
    def __init__(self, message: str, path: str) -> None:
        super().__init__(f"{message} at {path or '$'}")
        self.path = path


def _check_text(value: str, path: str, what: str) -> None:
    for char in value:
        if 0xD800 <= ord(char) <= 0xDFFF:
            raise CanonicalJsonError(f"lone surrogate in {what}", path)


def _utf16_order(key: str) -> bytes:
    # JCS orders keys by UTF-16 code units; big-endian UTF-16 bytes sort the same way.
    return key.encode("utf-16-be")


def _encode(value: Any, path: str) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        _check_text(value, path, "string")
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        if abs(value) > MAX_SAFE:
            raise CanonicalJsonError("integer outside the safe range", path)
        return str(value)
    if isinstance(value, float):
        if value.is_integer() and abs(value) <= MAX_SAFE:
            return str(int(value))
        raise CanonicalJsonError("non-integer number; encode it as a string", path)
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(_encode(item, f"{path}[{index}]") for index, item in enumerate(value)) + "]"
    if isinstance(value, Mapping):
        parts = []
        for key in sorted(value.keys(), key=lambda k: _utf16_order(k) if isinstance(k, str) else b""):
            if not isinstance(key, str):
                raise CanonicalJsonError("object keys must be strings", path)
            _check_text(key, path, "key")
            parts.append(json.dumps(key, ensure_ascii=False) + ":" + _encode(value[key], f"{path}.{key}"))
        return "{" + ",".join(parts) + "}"
    raise CanonicalJsonError(f"unsupported type {type(value).__name__}", path)


def canonical_json(value: Any) -> str:
    """Canonical JSON text of ``value``."""
    return _encode(value, "")


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def canonical_hash(value: Any) -> str:
    """``sha256:`` + hex digest of the canonical JSON of ``value``."""
    return "sha256:" + sha256_hex(canonical_json(value))


def drop_none(record: Mapping[str, Any]) -> dict[str, Any]:
    """Optional fields are omitted, never null, so both languages hash the same object."""
    return {key: value for key, value in record.items() if value is not None}
