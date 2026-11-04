"""execution-controls kit: strict UTC timestamps (spec: ../../spec/approval-capsule.md §1).

A timestamp is an ISO 8601 string in UTC ending in ``Z``. Anything else (an
offset, no zone, a date alone, an impossible date) does not parse, and the
callers that gate on time fail closed. Milliseconds are floored, exactly as
``Date.parse`` does in the TypeScript implementation, so both languages order
the same two instants the same way.
"""

from __future__ import annotations

import calendar
import re
from datetime import datetime
from typing import Any

_UTC_TIMESTAMP = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?Z")


def parse_utc_ms(value: Any) -> int | None:
    """Epoch milliseconds (floored) of a ``Z``-suffixed ISO-8601 UTC timestamp, or ``None``."""
    if not isinstance(value, str):
        return None
    match = _UTC_TIMESTAMP.fullmatch(value)
    if match is None:
        return None
    year, month, day, hour, minute, second = (int(part) for part in match.groups()[:6])
    try:
        datetime(year, month, day, hour, minute, second)
    except ValueError:
        return None
    millis = int(((match.group(7) or ".")[1:] + "000")[:3])
    return calendar.timegm((year, month, day, hour, minute, second)) * 1000 + millis
