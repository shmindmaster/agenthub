# macOS on Daytona

Read before any iOS build, Simulator or Xcode work. Since 2026-11-24 the DigitalOcean build droplet is retired and Daytona is the lane. The local VMware macOS VM is also retired (`Invoke-MobileLabVmrunStart` refuses). A connected iPhone or Android phone on this PC stays available for device testing (`physical-iphone.md`).

**Status: not yet run by us.** Everything below about the Mac comes from Daytona's documentation and the account's price list on 2026-11-24. No Mac has been reserved, no sandbox created, and USB devices and code signing are undocumented. Record each of those the first time a run proves it.

## What Daytona gives

| Fact | Value (2026-11-24) |
| --- | --- |
| Platform | Daytona v2 only (`api.daytona.com`, `@daytona/sdk` 2.x, `daytona.v2`). The older platform (`app.daytona.io`) has no Macs. |
| Region | `us-east-bos-1`, the only region with free Macs on 2026-11-24 |
| Image | `base-macos` (documented: macOS 26.6.2, Xcode 26.6 with the iPhone Simulator, Homebrew, Python) |
| Purchase | A **24-hour reservation**: m4pro-12c-24g $60.08, m4pro-12c-48g $69.41, m5pro-15c-24g $96.89. m4-10c-16g ($32.43) had none free |
| Create | `daytona.v2.createMacos('base-macos', { region: 'us-east-bos-1', reservation: <id> })` |
| Key | `DAYTONA_API_KEY`; never print it |

The Xcode ceiling in `registry/mobile-development.json` (`expectations.xcode`) describes the retired x86_64 VMware guest. The reservable Macs are Apple silicon, so it does not bind them; check the Xcode version the image actually ships before relying on it.

## Rules (owner direction 2026-11-24)

Auto-reserve is **on** by default for the organization and renews automatically. Creating a macOS sandbox without a reservation therefore buys one, and a reservation left alone buys the next day.

1. Get owner approval of the price for each reservation before buying it. A reservation is real money; "the task needs a Mac" is not approval.
2. Create an explicit reservation, then create the sandbox with `reservation: <id>`. Never let a bare `createMacos` buy one.
3. Turn renewal off on that reservation straight after buying it, and read the setting back.
4. Batch all iOS work (builds, Simulator runs, log capture, signing checks) into one 24-hour window. Plan the whole list before buying.
5. Capture every artifact before the window ends, compare hash and size with the Mac's own record, then delete the sandbox. Cancel what can be cancelled; if the reservation cannot be released early, say so in the report.
6. Label the sandbox with `owner` and `run`, and clean up only sandboxes that carry your own `run` label.

`scripts/daytona-run.mjs` creates Linux boxes only and never buys a Mac. Do not extend it to Macs without the owner's approval of this rule set.

## Use it

1. State what the 24-hour window will do and the reservation size and price; wait for the owner's approval.
2. Reserve, create the sandbox, turn renewal off, and record the reservation id and its end time in the task notes.
3. Send the source (`git archive` of the commit, in chunks that are hashed and reassembled if it is large), build and run, and write artifacts off the Mac as each finishes.
4. Report "verified on simulator" for Simulator runs, never "on device".
5. Delete the sandbox and confirm the reservation will not renew.

Things Daytona's documentation does not cover, so treat them as unknown until a run shows otherwise: attaching a USB iPhone, installing a signing identity or provisioning profile, and Apple Account or Expo sessions. An agent never holds an Apple or Expo login; those stay with the owner (`mobile-mcp.md` explains the one signing step that needs a Mac).

## No Android emulator on Daytona

Daytona has no `/dev/kvm`: the older platform answered "KVM sandboxes are not enabled for this organization", and v2 sandboxes have no `/dev/kvm` (documented as an Enterprise-plan feature). There is no remote Android emulator lane. Android Gradle and APK builds are expected to work on a v2 Linux box (`node scripts/daytona-run.mjs --owner <project> -- <command>`) but have not been run. Emulator and Maestro runs use the Windows emulator (`mobile.ps1 start android`) or a USB device.
