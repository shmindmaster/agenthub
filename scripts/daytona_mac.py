#!/usr/bin/env python3
"""Manage the long-lived Daytona v2 macOS build boxes.

The v2 SDK reads DAYTONA_API_KEY, and so does this helper: all Daytona work uses
one organization. No key value is ever printed or written to a file.

Provisioning identifiers are supplied by environment variables so this public
script carries no private infrastructure details. See the private guidance file
`guidance/daytona-mac.md` for the current values.

Required env: DAYTONA_MAC_REGION, DAYTONA_MAC_MODEL, DAYTONA_MAC_SANDBOXES
(comma-separated names), DAYTONA_MAC_RESERVATION_ID.
Optional env: DAYTONA_MAC_RESOURCES ("cpu,memory_gib,disk_gib"),
DAYTONA_MAC_LABELS (JSON object of shared labels), DAYTONA_MAC_ORG (refuse a key
from any other organization), DAYTONA_MAC_AUTO_RENEW=1 (create turns renewal on;
otherwise create turns it off, so a reservation ends instead of buying another day).

Usage: python scripts/daytona_mac.py create|status|wake|stop
"""
from __future__ import annotations

import json
import os
import sys

from daytona import Daytona
from daytona.v2 import DISABLED, MacosResources

LIFECYCLE = {"timeout_seconds": 86400, "idle_expiry_seconds": DISABLED}
BOX_LABEL = {"purpose": "ios-build"}


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Set {name} before running this helper.")
    return value


def client() -> Daytona:
    required("DAYTONA_API_KEY")
    return Daytona()


def settings():
    region = required("DAYTONA_MAC_REGION")
    model = required("DAYTONA_MAC_MODEL")
    reservation_id = required("DAYTONA_MAC_RESERVATION_ID")
    names = [n.strip() for n in required("DAYTONA_MAC_SANDBOXES").split(",") if n.strip()]
    raw_resources = os.environ.get("DAYTONA_MAC_RESOURCES", "6,24,100")
    cpu, memory, disk = (float(part) for part in raw_resources.split(","))
    resources = MacosResources(cpu=int(cpu), memory=memory, disk=disk)
    try:
        shared_labels = json.loads(os.environ.get("DAYTONA_MAC_LABELS", "{}"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"DAYTONA_MAC_LABELS must be JSON: {exc}")
    return region, model, reservation_id, names, resources, dict(shared_labels)


def sandbox_summary(sandbox) -> dict:
    return {
        "id": sandbox.id,
        "name": sandbox.name,
        "state": str(sandbox.state),
        "reservation_id": getattr(sandbox, "reservation_id", None),
        "labels": sandbox.labels,
    }


def find_boxes(d, names):
    # iter() walks every page; list() only returns the first one.
    wanted = set(names)
    return {s.name: s for s in d.v2.iter() if s.name in wanted}


def confirm_reservation(d, reservation_id, boxes):
    reservation = d.v2.reservations.get(reservation_id)
    details = [d.v2.get(s.id) for s in boxes.values()]
    attached = {getattr(x, "reservation_id", None) for x in details}
    if attached and attached != {reservation_id}:
        raise SystemExit(f"Build boxes are not on reservation {reservation_id}; refusing to mutate it.")
    return reservation


def main() -> None:
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    region, model, reservation_id, names, resources, shared_labels = settings()
    d = client()
    key_info = d.v2.current_api_key()
    print("key", {"name": key_info.name, "project": key_info.project_id, "org": key_info.context.org_name})

    expected_org = os.environ.get("DAYTONA_MAC_ORG", "").strip()
    if expected_org and key_info.context.org_name != expected_org:
        raise SystemExit(f"DAYTONA_API_KEY belongs to {key_info.context.org_name!r}, not {expected_org!r}.")

    boxes = find_boxes(d, names)
    print("sandboxes", [sandbox_summary(s) for s in boxes.values()])

    if action == "status":
        return

    reservation = confirm_reservation(d, reservation_id, boxes)
    print("reservation", {"id": reservation.id, "status": str(reservation.status), "auto_renew": reservation.auto_renew})

    if action == "stop" or action == "wake":
        if action == "stop":
            # Disable renewal first, independently of sandbox stop outcomes.
            try:
                d.v2.reservations.update(reservation.id, auto_renew=False)
                print("auto_renew disabled", reservation.id)
            except Exception as exc:
                print("auto_renew disable FAILED", type(exc).__name__, str(exc)[:200], file=sys.stderr)
            failures = []
            for sandbox in boxes.values():
                try:
                    if str(sandbox.state) != "stopped":
                        sandbox.stop()
                    print("stopped", sandbox.name)
                except Exception as exc:
                    failures.append((sandbox.name, type(exc).__name__, str(exc)[:200]))
            for failure in failures:
                print("stop FAILED", *failure, file=sys.stderr)
            if failures:
                raise SystemExit(1)
            return

        # wake: start stopped boxes and re-arm the 24-hour sandbox timeout.
        for sandbox in boxes.values():
            if str(sandbox.state) != "started":
                d.v2.start(sandbox.id)
            policy = sandbox.update_lifecycle_policy(
                timeout_seconds=86400, idle_expiry_seconds=DISABLED
            )
            print("wake", sandbox.name, "timeout_at", getattr(policy, "timeout_at", None))
        return

    if action != "create":
        raise SystemExit(f"Unknown action {action!r}; use create, status, wake or stop")

    renew = os.environ.get("DAYTONA_MAC_AUTO_RENEW", "").strip() == "1"
    d.v2.reservations.update(reservation.id, auto_renew=renew)
    print("auto_renew", renew)
    for name in names:
        labels = dict(shared_labels)
        labels.update(BOX_LABEL)
        labels["owner"] = name.removesuffix("-ios-build")
        sandbox = boxes.get(name)
        if sandbox is None:
            sandbox = d.v2.create_macos(
                "base-macos",
                name=name,
                resources=resources,
                labels=labels,
                persistent=True,
                reservation=reservation.id,
                lifecycle_policy=LIFECYCLE,
                region=region,
                wait_seconds=1200,
                create_timeout_seconds=3600,
            )
            print("created", sandbox_summary(sandbox))
        else:
            merged = dict(sandbox.labels or {})
            merged.update(labels)
            sandbox.set_labels(merged)
            if str(sandbox.state) != "started":
                d.v2.start(sandbox.id)
            sandbox.update_lifecycle_policy(timeout_seconds=86400, idle_expiry_seconds=DISABLED)
            print("reused", sandbox_summary(sandbox))
        if str(sandbox.state) != "started":
            raise SystemExit(f"{name} is {sandbox.state}, not started; investigate before use")


if __name__ == "__main__":
    main()
