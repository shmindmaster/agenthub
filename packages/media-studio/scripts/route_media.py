#!/usr/bin/env python3
"""Pick the lane for a media need from policy/provider-routing.json.

    route_media.py <need> [<need> ...] [--identity mahumtech|abacare|any] [--all] [--json]
    route_media.py --catalog          # every lane, with its mode (script, api, connector, browser), cost, how and notes

Free and offline. Prints the lanes that can serve the need, best first: ready before conditional, free before
paid. Frozen, skipped and disabled lanes are hidden unless --all, and are never returned as the pick. A lane
tied to one identity is not returned for a different --identity; lanes marked "any" serve every film, and the
owner picks the entity per film, so ownership is named in the quote and is never a blocker.

Exit 0 when at least one usable lane exists, 1 when none does (say so, do not improvise a provider).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

POLICY = Path(__file__).resolve().parent.parent / "policy" / "provider-routing.json"
USABLE = ("ready", "conditional")
ORDER = {"ready": 0, "conditional": 1, "frozen": 2, "skipped": 3, "disabled": 4}


def load(path=POLICY):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def identity_ok(lane, want):
    have = lane.get("identity", "any")
    if want in (None, "any") or have in ("any", "n/a"):
        return True
    return have == want


def is_free(lane):
    return str(lane.get("cost", "")).lower().startswith("none")


def route(policy, needs, identity=None, include_blocked=False):
    wanted = {n.lower() for n in needs}
    lanes = []
    for lane in policy["lanes"]:
        if not wanted & {n.lower() for n in lane.get("needs", [])}:
            continue
        if lane["status"] not in USABLE and not include_blocked:
            continue
        if not identity_ok(lane, identity):
            continue
        lanes.append(lane)
    lanes.sort(key=lambda l: (ORDER.get(l["status"], 9), 0 if is_free(l) else 1, l["id"]))
    return lanes


MODES = {"script": "a script or CLI in this plugin", "api": "a provider API called directly",
         "connector": "a connector tool in the host", "browser": "an interactive browser session (Claude in Chrome)"}


def mode_of(lane):
    return lane.get("mode") or "script"


def catalog(policy):
    """Every lane in the policy as markdown, usable lanes first, so an agent sees the whole capability set."""
    out = [f"# media-studio capability catalog (policy {policy['revision']}, as of {policy['asOf']})", "", policy["basis"], ""]
    for title, wanted in (("Usable now", USABLE), ("Frozen, skipped or disabled (listed so nothing is hidden)", ("frozen", "skipped", "disabled"))):
        out += [f"## {title}", ""]
        for lane in sorted((l for l in policy["lanes"] if l["status"] in wanted), key=lambda l: (ORDER.get(l["status"], 9), l["id"])):
            out.append(f"### {lane['id']}  [{lane['status']}, {mode_of(lane)}, identity {lane.get('identity', 'any')}]")
            out.append(f"- Serves: {', '.join(lane.get('needs', [])) or 'nothing'}")
            out.append(f"- Cost: {lane.get('cost')}")
            out.append(f"- How: {lane.get('how')}")
            if lane.get("notes"):
                out.append(f"- Notes: {lane['notes']}")
            out.append("")
    out += ["## Modes", ""] + [f"- {k}: {v}" for k, v in MODES.items()] + [""]
    out += ["## Rules", ""] + [f"- {r}" for r in policy["rules"]]
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("needs", nargs="*")
    ap.add_argument("--identity", default="any")
    ap.add_argument("--all", action="store_true", help="also show frozen, skipped and disabled lanes")
    ap.add_argument("--catalog", action="store_true", help="print every lane with its mode, cost, how and notes")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    policy = load()
    if args.catalog:
        print(catalog(policy), end="")
        return 0
    if not args.needs:
        ap.error("name a need, or use --catalog")
    lanes = route(policy, args.needs, args.identity, args.all)
    usable = [l for l in lanes if l["status"] in USABLE]
    if args.json:
        print(json.dumps({"needs": args.needs, "identity": args.identity, "asOf": policy["asOf"], "basis": policy["basis"],
                          "pick": usable[0]["id"] if usable else None, "lanes": lanes}, indent=2))
    else:
        for l in lanes:
            print(f"{l['status'].upper():11} {l['id']}  [{l.get('cost')}]  {l.get('how')}")
        if not usable:
            print("NO USABLE LANE: tell the owner what is blocked and what would unblock it.")
    return 0 if usable else 1


if __name__ == "__main__":
    sys.exit(main())
