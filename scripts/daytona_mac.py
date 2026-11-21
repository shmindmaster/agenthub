#!/usr/bin/env python3
"""Manage the long-lived Daytona v2 macOS build box for ABACare and Rexa.

The v2 SDK reads DAYTONA_API_KEY. This machine keeps the v2/Mac project key in
DAYTONA_API_KEY1, exposed to this helper as DAYTONA_V2_API_KEY. No key value is
ever printed or written to a file.

Usage: python scripts/daytona_mac.py create|status
"""
from __future__ import annotations

import os
import sys

from daytona import Daytona
from daytona.v2 import DISABLED, MacosResources

REGION = "us-east-bos-1"
MODEL = "m4pro-12c-48g"
SHARED_LABELS = {"purpose": "ios-builds", "run": "long-term-mac-20261121", "box": "portfolio-mac-20261121"}
SANDBOXES = {
    "abacare-ios-build": {"owner": "abacare", "purpose": "ios-build"},
    "rexa-ios-build": {"owner": "rexa", "purpose": "ios-build"},
}
# Two sandboxes share the m4pro-12c-48g host: half the cores and RAM each,
# with disk kept under the per-sandbox share left by the first box.
RESOURCES = MacosResources(cpu=6, memory=24, disk=100)
# The default 300-second sandbox timeout would stop these boxes between uses.
# 86400 is the organization plan maximum; idle expiry is cleared.
LIFECYCLE = {"timeout_seconds": 86400, "idle_expiry_seconds": DISABLED}


def client() -> Daytona:
    key = os.environ.get("DAYTONA_V2_API_KEY") or os.environ.get("DAYTONA_API_KEY1")
    if not key:
        raise SystemExit("Set DAYTONA_V2_API_KEY (or DAYTONA_API_KEY1) before running this helper.")
    os.environ["DAYTONA_API_KEY"] = key
    return Daytona()


def sandbox_summary(sandbox) -> dict:
    return {
        "id": getattr(sandbox, "id", None),
        "name": getattr(sandbox, "name", None),
        "state": str(getattr(sandbox, "state", None)),
        "labels": getattr(sandbox, "labels", None),
    }


def main() -> None:
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    d = client()
    key_info = d.v2.current_api_key()
    print("key", {"name": key_info.name, "project": key_info.project_id, "org": key_info.context.org_name})

    existing = {s.name: s for s in d.v2.list().items if getattr(s, "name", None) in SANDBOXES}
    reservations = list(d.v2.reservations.list().items)
    print("reservations", [
        {"id": r.id, "status": str(r.status), "model": str(getattr(r, "model", None)), "region": str(getattr(r, "region", None))}
        for r in reservations
    ])
    print("sandboxes", [sandbox_summary(s) for s in existing.values()])

    if action == "status":
        return
    if action == "wake":
        # Manual, capability-invoked refresh: start stopped boxes and re-arm
        # the 24-hour sandbox timeout. No scheduled job is registered.
        for sandbox in existing.values():
            if str(sandbox.state) != "started":
                d.v2.start(sandbox.id)
            policy = sandbox.update_lifecycle_policy(
                timeout_seconds=86400, idle_expiry_seconds=DISABLED
            )
            print("wake", sandbox.name, "timeout_at", getattr(policy, "timeout_at", None))
        return
    if action == "stop":
        # Stopping every sandbox and clearing auto_renew lets the reservation
        # end with its current 24-hour period; no charge after that.
        for sandbox in existing.values():
            sandbox.stop()
            print("stopped", sandbox.name, sandbox.id)
        if reservations:
            d.v2.reservations.update(reservations[0].id, auto_renew=False)
            print("auto_renew disabled", reservations[0].id)
        return
    if action != "create":
        raise SystemExit(f"Unknown action {action!r}; use create, status or stop")

    reservation = reservations[0] if reservations else d.v2.reservations.create(
        region=REGION, model=MODEL, auto_renew=True
    )
    print("reservation", {"id": reservation.id, "status": str(reservation.status)})

    for name, product_labels in SANDBOXES.items():
        labels = dict(SHARED_LABELS)
        labels.update(product_labels)
        if name in existing:
            existing[name].set_labels(labels)
            print("reuse", name, existing[name].id, "labels", labels)
            continue
        sandbox = d.v2.create_macos(
            "base-macos",
            name=name,
            resources=RESOURCES,
            labels=labels,
            persistent=True,
            reservation=reservation.id,
            lifecycle_policy=LIFECYCLE,
            # The SDK allows auto_renew only when it creates the reservation
            # itself (reservation="new"). Ours was created with auto_renew=True.
            region=REGION,
            wait_seconds=1200,
            create_timeout_seconds=3600,
        )
        print("created", sandbox_summary(sandbox))


if __name__ == "__main__":
    main()
