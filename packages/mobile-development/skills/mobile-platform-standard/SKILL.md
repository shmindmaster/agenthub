---
name: mobile-platform-standard
description: Use when any fleet product needs native iOS/Android work - Expo, EAS, React Native, app.config, bundle identifiers, TestFlight, Google Play, push notifications, deep links, or mobile store submission. Establishes eligibility first, then the required platform baseline.
---

# Mobile platform standard

One baseline for every fleet product that gets a native app. Read this before
writing mobile code, and before touching any Apple, Google, Expo, EAS, or
Firebase surface.

Resolve scope and catalog facts through the fleet-managed package, not an
AgentHub checkout that may be absent or not yet integrated:

```powershell
pwsh -NoProfile -File "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1" scope <productId> -Json
pwsh -NoProfile -File "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1" catalog -Json
```

`packages/mobile-development/mobile.ps1` remains the canonical source
contract; `scripts/Sync-Capabilities.ps1` owns and verifies this deployed
whole-package mirror.

## 1. Eligibility gate - do this first

`registry/mobile-scope.json` in AgentHub is the sole authority for which
products may receive mobile work. Resolve the product against it before
anything else.

| Bucket | What to do |
| --- | --- |
| `include` | Proceed with the baseline below. |
| `noNative` | Stop. This product has no intended native mobile surface. |
| `evaluateLater` | Stop. Report that native value is unproven for this product and no identifier may be reserved ahead of that decision. |
| `excludedPendingReposition` | Stop. Identity is frozen; see below. |
| absent from the file | Stop and ask the owner to classify it. Absence never means allowed. |

Fail closed: only an exact `include` record authorizes product-targeted mobile
work. Do not infer eligibility from a repository, app config, existing build,
domain, or remembered owner decision.

For a frozen product, every class in `scopePolicy.frozenIdentifierClasses` is
prohibited: Expo project, EAS project, Apple bundle identifier, App Store
Connect app, Google Play package, Firebase mobile application, APNs/FCM
credential, deep-link association, store metadata, mobile branding, native
application code. **A convenient placeholder identifier is a prohibited
identifier** - reserving one is the specific harm the freeze prevents. Only the
owner lifts a freeze, and only by the product's recorded `exitCondition`.

Why the gate is absolute: an Apple bundle identifier cannot be changed after
the first build reaches App Store Connect, and Android treats a changed
`applicationId` as a different application. An identifier minted under a name
that is already known to be wrong is permanent infrastructure carrying a
permanent mistake.

## 2. Baseline

| Layer | Standard |
| --- | --- |
| Framework | Expo SDK 57 + React Native 0.86 + TypeScript |
| Navigation | Expo Router |
| Native generation | Continuous Native Generation + config plugins |
| Dev runtime | `expo-dev-client` - not Expo Go |
| Builds | **Local by default** - see below. EAS Build is the fallback |
| Distribution / OTA | EAS Submit, EAS Update |
| CI/CD | EAS Workflows |
| Store metadata | EAS Metadata (`store.config.json` in-repo) |
| Environments | EAS Environment Variables (account-wide + per project) |
| Signing | EAS Credentials + Apple Developer + Play App Signing |
| Beta lanes | TestFlight internal/external; Play internal/closed |
| E2E | Maestro, run from EAS Workflows |
| Crashes | Sentry, one project per product |
| Performance | EAS Observe |
| Dependency health | `expo-doctor` + `expo install --check` as a CI gate |
| Push | `expo-notifications` + APNs + FCM v1 |
| Deep links | Universal Links + Android App Links |
| Local data | SecureStore, SQLite as appropriate |
| Versioning | EAS remote versions + `autoIncrement` |
| Release compatibility | `runtimeVersion: { "policy": "fingerprint" }` |

Release routing follows the fingerprint: unchanged native state ships as an
EAS Update; changed native state builds and submits. Do not hand-roll this
decision.

### Build locally. The cloud runner is the fallback

Every target compiles on this hardware. Sending a routine build to EAS's
runners spends money for nothing, and the fleet has already paid that bill -
the account exhausted its build quota on 2026-08-11, mostly on iOS builds,
which run on macOS runners and burn quota far faster than the Linux runners
Android uses.

| Target | Build it with | Where |
| --- | --- | --- |
| Android APK | `gradlew` | the Windows workstation |
| iOS Simulator `.app` | `xcodebuild` (`ios.simulator: true`) | the macOS guest |
| iOS device `.ipa`, signed | `eas build --platform ios --profile <p> --local` | the macOS guest |

`--local` runs the same build EAS runs, on your machine. It contacts Expo for
exactly two things - confirming the project exists and downloading the managed
credentials - and **neither is a build minute**. Caching and `secret`-type
environment variables are not supported locally, and the `node`/`yarn`/
`fastlane`/`cocoapods`/`ndk`/`image` version fields in `eas.json` are ignored.

A measured local guest build completed in roughly ten minutes and produced a
verified signed `arm64` `.ipa`. Treat that as route evidence, not as current
product, account, certificate, team, or device state; resolve those facts from
their authorities at execution time.

**An empty signing-identity list does not mean the guest cannot sign.**

```
security find-identity -v -p codesigning   ->  0 valid identities found
```

That is the expected state *after a successful local build*: `eas build
--local` imports the certificate into a throwaway keychain for the build and
tears it down afterwards. A prior runbook read that output as "the guest cannot
sign", recorded "iOS device builds require EAS" as fact, and kept spending
quota on the one build it did not need to. Check for a signed artifact, never
for a permanent keychain identity.

Reach for the cloud runner only when the macOS guest is genuinely unavailable.

**Local builds solve signing, not delivery.** A cloud build comes with an
install page the phone can open in Safari; a local `.ipa` does not, so each
product still needs a route onto hardware.

The working route on this workstation is **`pymobiledevice3` over USB from
Windows** - it needs no VMware USB passthrough, which is the fiddly part of the
alternatives. Set up and verified 2026-08-11:

```powershell
winget install --id 9NP83LWLPZ9K --source msstore   # Apple Devices - supplies usbmuxd
py -m pip install --user --no-deps pymobiledevice3  # plus its pinned deps, see below
py -m pymobiledevice3 usbmux list                   # [] == socket live, no device attached
py -m pymobiledevice3 apps install <path-to-ipa>    # with the phone plugged in and trusted
```

Two traps, both already paid for:

- **`pip install pymobiledevice3` fails on Windows.** It pulls `pyimg4`, which
  requires `lzfse` on non-darwin, and `lzfse` publishes no wheel at all - it
  needs a C compiler. `pyimg4` parses Apple Image4 firmware and is irrelevant
  to installing an app, so resolve the dependency set once
  (`pip install --dry-run --report`), then install it flat with `--no-deps`,
  omitting `pyimg4` and `lzfse`. The CLI imports them lazily; `apps install`
  works without them. This does not arise in the macOS guest, where `pyimg4`
  does not require `lzfse`.
- **Installing Apple Devices is not enough - it must be launched once.** The
  MSIX package registers no service at install time. Until the app runs,
  `usbmux list` fails with `Failed to connect to usbmuxd socket`. After launch,
  `AppleMobileDeviceProcess` and `AppleMobileDeviceLauncher` are running and
  the socket answers. There is no Windows *service* and nothing under
  `C:\Program Files\Common Files\Apple` - checking for either reports a
  correctly working setup as broken.

App install rides `installation_proxy` over lockdown, so it should not need the
`sudo tunneld` RemoteXPC tunnel that iOS 17+ *developer* services require -
expected, not yet confirmed against a device. The remaining alternatives are
VMware USB passthrough to the guest (`xcrun devicectl device install app`) and
a self-hosted `itms-services://` manifest, which Apple requires over real
HTTPS.

To drop the credential fetch as well, export the `.p12` once with `eas
credentials`, or mint an App Store Connect API key and let `fastlane
cert`/`sigh` manage the certificate and profile headlessly. The API-key route
needs no interactive Apple ID sign-in, which matters because the macOS guest
runs a synthetic SMBIOS and cannot complete one. Weigh it as independence, not
savings - the fetch is free and read-only. It handles a private key, so it
belongs to the account holder, not an agent.

## 3. One identity per product until a product actually ships

**Default: a single bundle identifier, a single EAS `development` profile.**
Owner decision 2026-08-08, after this file briefly said otherwise.

Every identifier suffix is a separate Apple App ID with its own provisioning
profile. A `.dev` / `.preview` / production split across four products is
twelve App IDs and twelve profiles - to run debug builds on two phones. The
side-by-side install that split buys is worth nothing until something is
actually being released.

```json
{
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "android": { "buildType": "apk" }
    }
  }
}
```

Add profiles when a real need appears and record that reason in the product's
authoritative configuration. "We might release someday" is not a reason.

Adopt suffixed variants only when a product is genuinely heading to a store
and needs side-by-side installs. Then, and only then:

```ts
const variant = process.env.APP_VARIANT ?? "production";
const suffix =
  variant === "development" ? ".dev" : variant === "preview" ? ".preview" : "";
```

Applied to both `ios.bundleIdentifier` and `android.package`, with a matching
display name.

## 4. Resolve identity and account state; do not copy it here

`registry/mobile-scope.json` is the sole product identity authority. After the
eligibility gate passes, resolve the selected product's `mobileIdentity` there
for its canonical domain, bundle/application identifiers, and project naming.
Never derive or copy those values from this skill, another product, an old
build, or a provider dashboard. `tests/Test-MobileScope.ps1` verifies recorded
identities against eligible product configuration.

Stable policy:

- Use the exact authority value; do not normalize, improve, or replace it.
- One EAS project per eligible product unless the authority records a reviewed
  exception. Anything compiled into client JavaScript is public.
- Treat EAS project IDs/slugs, Apple team and certificate state, App IDs,
  profiles, registered devices, and provider account topology as mutable live
  facts. Resolve them from the eligible product record and provider at the
  authorized execution gate; do not persist a second table in a skill.
- Product identity or provider-account mutation is owner-gated. Deletion,
  recreation, signing, registration, store submission, and credential changes
  are never implied by development work.
- EAS slugs and store identifiers can carry irreversible history. If the
  authority and provider disagree, stop and report the drift rather than
  repairing either side automatically.
- Ad Hoc profiles embed device membership and provider credentials/profiles
  can accumulate. Diagnose current live state before proposing cleanup; any
  cleanup remains an explicit owner action.

## 6. Health-sensitive products

`registry/mobile-scope.json` marks products with `healthSensitive: true`.
Resolve that flag for the selected product at execution time. For those
products, do not enable screenshot
collection, session replay, or broad AI/MCP access against real patient data.
Review the connected model provider's retention and training policy before
enabling MCP access at all, and prefer synthetic fixtures.

## 7. Dated platform requirement

Google Play requires new apps and updates to target Android 16 / API 36 from
**2026-08-31**. Expo SDK 57 already compiles against API 36, so a
standard-conformant project needs no action - but verify with `expo-doctor`
rather than assuming.

## References

Read these only when the work reaches them; do not copy them into a product
repository.

- `references/store-compliance.md` - Apple App Privacy, privacy manifests,
  Google Data Safety, content rating, account-deletion requirements.
- `references/release-infrastructure.md` - Apple/Google organization setup,
  App Store Connect API keys, Play App Signing, beta lane structure.
