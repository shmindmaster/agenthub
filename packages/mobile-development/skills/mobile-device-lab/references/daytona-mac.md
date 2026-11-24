# macOS on Daytona

Read before any iOS build, Simulator or Xcode work. Since 2026-11-24 the DigitalOcean build droplet is retired and Daytona is the lane. The local VMware macOS VM is also retired (`Invoke-MobileLabVmrunStart` refuses). A connected iPhone or Android phone on this PC stays available for device testing (`physical-iphone.md`).

**Status.** The owner directed one long-lived Mac for iOS work on 2026-11-21. Two macOS boxes were created on it and checked by command: macOS 26.6.2, Xcode 26.6, Node 24, pnpm, CocoaPods, fastlane. That proves the toolchain, not an iOS build, a signed install or a USB device. The state of those boxes was not visible from this repository's keys on 2026-11-24, so check it before planning work. Identifiers, key name and cost are in the private `guidance/daytona-mac.md`.

## What Daytona gives

| Fact | Value (2026-11-24) |
| --- | --- |
| Platform | Daytona v2 only (`api.daytona.com`, `@daytona/sdk` 2.x, `daytona.v2`). The older platform (`app.daytona.io`) has no Macs. |
| Region | `us-east-bos-1`, the only region with free Macs on 2026-11-24 |
| Image | `base-macos` (macOS 26.6.2, Xcode 26.6 with the iPhone Simulator, Homebrew, Python) |
| Purchase | A **24-hour reservation**: m4pro-12c-24g $60.08, m4pro-12c-48g $69.41, m5pro-15c-24g $96.89. m4-10c-16g ($32.43) had none free |
| Create | `daytona.v2.createMacos('base-macos', { region: 'us-east-bos-1', reservation: <id> })` |
| Key | `DAYTONA_API_KEY`; never print it |

The Xcode ceiling in `registry/mobile-development.json` (`expectations.xcode`) describes the retired x86_64 VMware guest. The reservable Macs are Apple silicon, so it does not bind them; check the Xcode version the image actually ships before relying on it.

## Rules

A Mac is a paid 24-hour reservation. Auto-reserve is **on** by default for the organization, so creating a macOS sandbox without naming a reservation buys one, and a reservation with renewal on buys the next day.

1. Use the owner's existing boxes. `python scripts/daytona_mac.py status` reports them; `wake` starts them before a session.
2. Get owner approval of the price before buying any other reservation: a new one, a different model, or a replacement for one that ended. "The task needs a Mac" is not approval. Always pass `reservation: <id>`; never let a bare create buy one.
3. Renewal on the owner's standing reservation is the owner's choice: leave it as found. Turn renewal off on any reservation bought for one task, and read the setting back.
4. When the owner no longer wants the standing box, `python scripts/daytona_mac.py stop` turns renewal off first, then stops the boxes.
5. Capture every artifact, compare hash and size with the Mac's own record, and label new sandboxes with `owner` and `run`. Clean up only sandboxes that carry your own `run` label.

`scripts/daytona-run.mjs` creates Linux boxes only and never buys a Mac.

## Use it

1. Check `status`. If the boxes or the reservation are gone, stop and ask the owner; do not recreate them.
2. Send the source (`git archive` of the commit), build and run, and copy artifacts off the Mac as each finishes.
3. Report "verified on simulator" for Simulator runs, never "on device".

Things Daytona's documentation does not cover, so treat them as unknown until a run shows otherwise: attaching a USB iPhone, installing a signing identity or provisioning profile, and Apple Account or Expo sessions. An agent never holds an Apple or Expo login; those stay with the owner (`mobile-mcp.md` explains the one signing step that needs a Mac).

## No Android emulator on Daytona

Daytona has no `/dev/kvm`: the older platform answered "KVM sandboxes are not enabled for this organization", and v2 sandboxes have no `/dev/kvm` (documented as an Enterprise-plan feature). There is no remote Android emulator lane. Android Gradle and APK builds are expected to work on a v2 Linux box (`node scripts/daytona-run.mjs --owner <project> -- <command>`) but have not been run. Emulator and Maestro runs use the Windows emulator (`mobile.ps1 start android`) or a USB device.
