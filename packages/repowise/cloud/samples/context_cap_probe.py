import json
import sys

sys.path.insert(0, sys.argv[1])
from context_cap import MARKER_PREFIX, cap_response, cap_tool_result  # noqa: E402

cases = {
    "huge _meta": {"content": [{"type": "text", "text": "hi"}], "_meta": {"k": "y" * 100000}},
    "huge _meta + content + structured": {"content": [{"type": "text", "text": "z" * 90000}],
                                          "structuredContent": {"a": "b" * 90000}, "_meta": {"k": "y" * 100000}},
    "non-ascii text": {"content": [{"type": "text", "text": "é中" * 40000}]},
    "many items": {"content": [{"type": "text", "text": "q" * 3000} for _ in range(200)]},
    "non-text items": {"content": [{"type": "resource", "resource": {"blob": "A" * 50000}} for _ in range(4)]},
    "small": {"content": [{"type": "text", "text": "fine"}], "_meta": {"k": 1}},
}
ok = True
for name, res in cases.items():
    capped, stats = cap_tool_result(res, 65536, 40)
    wire = len(json.dumps(capped).encode("utf-8"))
    marker = any(str(i.get("text", "")).startswith(MARKER_PREFIX) for i in capped["content"] if isinstance(i, dict))
    good = wire <= 65536 and (name == "small") != marker and (name != "small" or capped == res)
    ok = ok and good
    print(f"{name}: wire={wire} truncated={stats['truncated']} marker={marker} {'OK' if good else 'BAD'}")
capped, _ = cap_tool_result({"content": [{"type": "text", "text": "x" * 5000}], "_meta": {"k": "y" * 5000}}, 100, 40)
w = len(json.dumps(capped).encode("utf-8"))
print("tiny cap 100: wire", w, "OK" if w <= 100 else "over (floor is the bare marker)")
batch = [{"jsonrpc": "2.0", "id": 1, "result": {"content": [{"type": "text", "text": "a"}], "_meta": {"k": "y" * 100000}}}]
out, _ = cap_response(batch, 65536, 40)
bw = len(json.dumps(out[0]["result"]).encode("utf-8"))
print("batch element wire", bw, "OK" if bw <= 65536 else "BAD")
print("ALL OK" if ok and bw <= 65536 else "FAILURES")
