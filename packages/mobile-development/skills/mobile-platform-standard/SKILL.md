---
name: mobile-platform-standard
description: Use when any fleet product needs native iOS/Android work - Expo, EAS, React Native, app.config, bundle identifiers, TestFlight, Google Play, push notifications, deep links, or mobile store submission. Establishes eligibility first, then the required platform baseline.
---

# Mobile platform standard

One baseline for every fleet product that gets a native app. Read this before
writing mobile code, and before touching any Apple, Google, Expo, EAS, or
Firebase surface.

## 1. Eligibility gate - do this first

`registry/mobile-scope.json` in AgentHub is the sole authority for which
products may receive mobile work. Resolve the product against it before
anything else.

| Bucket | What to do |
| --- | --- |
| `include` | Proceed with the baseline below. |
| `evaluateLater` | Stop. Report that native value is unproven for this product and no identifier may be reserved ahead of that decision. |
| `excludedPendingReposition` | Stop. Identity is frozen; see below. |
| absent from the file | Stop and ask the owner to classify it. Absence never means allowed. |

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

Verified on Rexa 2026-08-11 in the VMware macOS guest, ~10 minutes wall clock:
a 16.1 MB `arm64` `.ipa`, authority `iPhone Distribution: Sarosh Hussain
(9V6CGU625U)`, `codesign --verify` clean, Ad Hoc profile carrying the test
device's UDID.

**An empty signing-identity list does not mean the guest cannot sign.**

```
security find-identity -v -p codesigning   ->  0 valid identities found
```

That is the expected state *after a successful local build*: `eas build
--local` imports the certificate into a throwaway keychain for the build and
tears it down afterwards. Rexa's runbook read that output as "the guest cannot
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

Add profiles when a real need appears and say what it is - Rexa carries a
`study` profile because it needs a build that runs without a dev server. That
is a reason; "we might release someday" is not.

Adopt suffixed variants only when a product is genuinely heading to a store
and needs side-by-side installs. Then, and only then:

```ts
const variant = process.env.APP_VARIANT ?? "production";
const suffix =
  variant === "development" ? ".dev" : variant === "preview" ? ".preview" : "";
```

Applied to both `ios.bundleIdentifier` and `android.package`, with a matching
display name.

## 4. Identifier conventions

- Reverse-DNS from the product's own domain (`ai.abacare.app`), not a shared
  vendor prefix - so an identifier never binds a product to whoever owns it
  today. Recorded per product under `mobileIdentity` in
  `registry/mobile-scope.json`, and `tests/Test-MobileScope.ps1` fails if a
  recorded identifier drifts from the app config.
- Exception on record: `rexa` uses `app.shmindmaster.rexa` because `rexa.ai`
  is not owned. It predates the rule and cannot be changed.
- One EAS project per product. The EAS slug equals the product's `productId`
  in `registry/mobile-scope.json`.
- Anything compiled into client JavaScript is public. EAS secrets do not make
  an embedded `EXPO_PUBLIC_*` value private.

**The EAS slug cannot be renamed.** Verified 2026-08-08 against eas-cli 21.7.0
and the Expo dashboard: `eas project` exposes only
`icon`/`delete`/`info`/`init`/`new`, and project settings edits a separate
"Display name" while the Danger zone offers only transfer and delete. The only
route to a different slug is delete and re-create - a new project ID, lost
build history, and regenerated credentials.

Cautionary case, and how it ended: Rexa's EAS project shipped as
`@shmindmaster/recallforge`, the pre-rename product name. The owner deleted
the project on 2026-08-08 and the slug is being re-created as `rexa`. That was
only affordable because nothing had been store-submitted and no EAS Update
channel existed - the sole cost was build history. **Delete-and-re-create stops
being an option the moment a build reaches App Store Connect.** Set the slug
from the final name, or freeze the product until there is one.

When a project is deleted, clear `extra.eas.projectId` from `app.json`. A
project ID pointing at a deleted project fails every `eas` command with
"project not found"; `eas init` writes a fresh one.

Account-level Apple state (team, distribution certificate, App IDs, devices)
survives an EAS project deletion - it belongs to the account, not the project.

## 5. Account topology - one of everything

Verified against the live Expo and Apple accounts on 2026-08-08. A solo
developer needs exactly this, and every extra row is something to keep
consistent forever:

| Layer | Correct count | Detail |
| --- | --- | --- |
| Expo account | **1** | `shmindmaster`, the personal account. Not an organization. |
| Apple team | **1** | `9V6CGU625U`, Individual. |
| iOS Distribution certificate | **1** | Shared by every app. Apple caps you at 2 - do not burn them. |
| Apple App IDs | **1 per product** | EAS creates each on that product's first build. |
| Provisioning profiles | **1 per App ID** | The target, not the default - see below. |
| Registered devices | **1 per physical phone** | Shared across all profiles. |
| APNs / App Store Connect API keys | **0** | Only needed for push and store submission. |

**Never hand-create anything in the Apple Developer portal.** Let EAS create
App IDs and profiles; hand-made ones drift from what EAS expects and produce
provisioning failures that are slow to unpick. Four apps do not mean four
certificates - EAS reuses the one.

Ad Hoc profiles embed the device list, so adding a phone invalidates every
existing profile until the next build regenerates them. A build that suddenly
will not install on a new device is that, not a bug.

**Profiles accumulate; EAS creates, it does not replace.** Regenerating
credentials mints `[expo] <bundleId> AdHoc <ts>` and leaves the previous
profile active against the same App ID - observed on 2026-08-08, two live
profiles for `app.shmindmaster.rexa` after one rebuild. Only the newest is
bound to the project. The stale ones are inert but they are what makes an
account drift, so delete them in the portal when the count exceeds one.

Three traps found on this account, all worth checking elsewhere:

- Expo historically auto-created a `<username>s-team` organization at signup.
  It is a legacy artifact, not something to build on. A solo developer should
  delete it and work under the personal account.
- EAS names an Apple App ID from the EAS project's full name at creation time,
  so a stale EAS slug leaks into the Apple portal - here the App ID for
  `app.shmindmaster.rexa` is described `shmindmasterrecallforge...`. The
  description is editable and EAS will not overwrite it; the bundle
  identifier underneath is not editable at all.
- **A rebuild will not repair that name.** EAS names an App ID only when it
  creates one, and it will not create one that already exists - `Bundle
  identifier registered` in the build log means matched, not minted. Deleting
  the App ID in the portal *before* the build is the only way to get a
  correctly-named replacement, and it forces deleting every profile that
  references it first. Renaming the description in the portal reaches the same
  end state without spending a build; prefer it.

Deleting an Expo project or account requires an interactive password
re-confirmation ("sudo mode") and is not exposed as a GraphQL mutation, so it
cannot be automated - hand those steps to the owner.

## 6. Health-sensitive products

`registry/mobile-scope.json` marks products with `healthSensitive: true`
(currently `abacare` and `gentlenext`). For those, do not enable screenshot
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
