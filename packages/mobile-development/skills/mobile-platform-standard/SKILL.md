---
name: mobile-platform-standard
description: Use when any fleet product needs native iOS/Android work - Expo, EAS, React Native, app.config, bundle identifiers, TestFlight, Google Play, push notifications, deep links, or mobile store submission. Establishes eligibility first, then the required platform baseline.
---

# Mobile platform standard

One baseline for every fleet product that gets a native app. Read before writing mobile code or touching any Apple, Google, Expo, EAS, or Firebase surface.

Resolve scope and catalog facts through the fleet-managed package:

```powershell
pwsh -NoProfile -File "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1" scope <productId> -Json
pwsh -NoProfile -File "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1" catalog -Json
```

`packages/mobile-development/mobile.ps1` is the canonical source contract; `scripts/Sync-Capabilities.ps1` owns and verifies the deployed whole-package mirror.

## 1. Eligibility gate

`registry/mobile-scope.json` in AgentHub is the sole authority for which products may receive mobile work. Resolve the product against it before anything else.

| Bucket | Action |
| --- | --- |
| `include` | Proceed with baseline. |
| `noNative` | Stop. No intended native mobile surface. |
| `evaluateLater` | Stop. Native value unproven; no identifier may be reserved. |
| `excludedPendingReposition` | Stop. Identity frozen. |
| absent | Stop and ask owner to classify. Absence never means allowed. |

Fail closed: only an exact `include` record authorizes product-targeted mobile work. Do not infer eligibility from a repository, app config, existing build, domain, or remembered decision.

For a frozen product, every class in `scopePolicy.frozenIdentifierClasses` is prohibited: Expo project, EAS project, Apple bundle identifier, App Store Connect app, Google Play package, Firebase mobile application, APNs/FCM credential, deep-link association, store metadata, mobile branding, native application code. A convenient placeholder identifier is a prohibited identifier. Only the owner lifts a freeze via the product's recorded `exitCondition`.

Rationale: an Apple bundle identifier cannot change after the first build reaches App Store Connect; Android treats a changed `applicationId` as a different application.

## 2. Baseline

| Layer | Standard |
| --- | --- |
| Framework | Expo SDK 57 + React Native 0.86 + TypeScript |
| Navigation | Expo Router |
| Native generation | Continuous Native Generation + config plugins |
| Dev runtime | `expo-dev-client` (not Expo Go) |
| Builds | Local by default; EAS Build is fallback |
| Distribution / OTA | EAS Submit, EAS Update |
| CI/CD | EAS Workflows |
| Store metadata | EAS Metadata (`store.config.json` in-repo) |
| Environments | EAS Environment Variables (account-wide + per project) |
| Signing | EAS Credentials + Apple Developer + Play App Signing |
| Beta lanes | TestFlight internal/external; Play internal/closed |
| E2E | Maestro from EAS Workflows |
| Crashes | Sentry, one project per product |
| Performance | EAS Observe |
| Dependency health | `expo-doctor` + `expo install --check` as CI gate |
| Push | `expo-notifications` + APNs + FCM v1 |
| Deep links | Universal Links + Android App Links |
| Local data | SecureStore, SQLite as appropriate |
| Versioning | EAS remote versions + `autoIncrement` |
| Release compatibility | `runtimeVersion: { "policy": "fingerprint" }` |

Release routing follows the fingerprint: unchanged native state ships as EAS Update; changed native state builds and submits. Do not hand-roll this.

### Build locally; cloud runner is fallback

The account exhausted its EAS build quota on 2026-08-11, mostly on iOS (macOS runners burn quota faster).

| Target | Build with | Where |
| --- | --- | --- |
| Android APK | `gradlew` | Windows workstation |
| iOS Simulator `.app` | `xcodebuild` (`ios.simulator: true`) | macOS guest |
| iOS device `.ipa`, signed | `eas build --platform ios --profile <p> --local` | macOS guest |

`--local` contacts Expo only to confirm the project exists and download managed credentials; neither is a build minute. Caching and `secret`-type env vars are unsupported locally; `node`/`yarn`/`fastlane`/`cocoapods`/`ndk`/`image` fields in `eas.json` are ignored.

**An empty signing-identity list does not mean the guest cannot sign.** `security find-identity -v -p codesigning` returning 0 identities is expected after a successful local build: `eas build --local` imports the certificate into a throwaway keychain and tears it down. Check for a signed artifact, never for a permanent keychain identity.

Reach for the cloud runner only when the macOS guest is genuinely unavailable.

**Local builds solve signing, not delivery.** The working route is **`pymobiledevice3` over USB from Windows** (no VMware USB passthrough needed):

```powershell
py -m pip install --user --no-deps pymobiledevice3
py -m pymobiledevice3 usbmux list
py -m pymobiledevice3 apps install <path-to-ipa>
```

`usbmuxd` on Windows comes from Apple in two forms. Either serves the socket; treat `usbmux list` answering as readiness:

| Form | What runs |
| --- | --- |
| Apple Devices app (MSIX, `winget install --id 9NP83LWLPZ9K --source msstore`) | `AppleMobileDeviceProcess` and `AppleMobileDeviceLauncher` after first launch. No Windows service. |
| Apple Mobile Device Support (with iTunes) | Windows service `Apple Mobile Device Service` (AMDS). See [support.apple.com/102347](https://support.apple.com/en-us/102347). |

```powershell
Get-AppxPackage -Name '*AppleDevices*'
Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue
```

Observed 2026-10-13: service form, Running, no MSIX. Neither form is the only correct one.

Two traps:

- **`pip install pymobiledevice3` fails on Windows.** It pulls `pyimg4` → `lzfse`, which has no wheel and needs a C compiler. `pyimg4` is irrelevant to app install. Resolve deps once (`pip install --dry-run --report`), then install flat with `--no-deps`, omitting `pyimg4` and `lzfse`. The CLI imports them lazily; `apps install` works without them.
- **MSIX form requires one launch.** Until the app runs, `usbmux list` fails. No Windows service exists in this form; checks requiring a service or `C:\Program Files\Common Files\Apple` will falsely report it broken, and vice versa.

App install rides `installation_proxy` over lockdown; it should not need `sudo tunneld` (expected, not yet confirmed). Alternatives: VMware USB passthrough to guest (`xcrun devicectl device install app`) or self-hosted `itms-services://` manifest over real HTTPS.

To drop the credential fetch, export the `.p12` via `eas credentials` or mint an App Store Connect API key for `fastlane cert`/`sigh`. The API-key route needs no interactive Apple ID sign-in (relevant because the macOS guest runs synthetic SMBIOS). It handles a private key, so it belongs to the account holder, not an agent.

## 3. One identity per product until it ships

Owner decision 2026-08-08: **single bundle identifier, single EAS `development` profile.**

Every suffix is a separate Apple App ID with its own provisioning profile. A `.dev`/`.preview`/production split across four products is twelve App IDs and twelve profiles for debug builds on two phones.

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

Add profiles when a real need appears and record the reason in the authoritative configuration. Adopt suffixed variants only when genuinely heading to a store and needing side-by-side installs:

```ts
const variant = process.env.APP_VARIANT ?? "production";
const suffix =
  variant === "development" ? ".dev" : variant === "preview" ? ".preview" : "";
```

Applied to both `ios.bundleIdentifier` and `android.package`, with matching display name.

## 4. Resolve identity and account state; do not copy it here

`registry/mobile-scope.json` is the sole product identity authority. After eligibility passes, resolve the product's `mobileIdentity` there for canonical domain, bundle/application identifiers, and project naming. Never derive values from this skill, another product, an old build, or a provider dashboard. `tests/Test-MobileScope.ps1` verifies recorded identities against eligible product configuration.

Stable policy:

- Use the exact authority value; do not normalize, improve, or replace it.
- One EAS project per eligible product unless the authority records a reviewed exception.
- Treat EAS project IDs/slugs, Apple team/certificate state, App IDs, profiles, registered devices, and provider account topology as mutable live facts. Resolve from the eligible product record and provider at execution time; do not persist a second table in a skill.
- Product identity or provider-account mutation is owner-gated. Deletion, recreation, signing, registration, store submission, and credential changes are never implied by development work.
- EAS slugs and store identifiers can carry irreversible history. If authority and provider disagree, stop and report drift rather than repairing either side automatically.
- Ad Hoc profiles embed device membership; credentials/profiles can accumulate. Diagnose live state before proposing cleanup; cleanup remains an explicit owner action.

## 5. Health-sensitive products

`registry/mobile-scope.json` marks products with `healthSensitive: true`. Resolve at execution time. For those products, do not enable screenshot collection, session replay, or broad AI/MCP access against real patient data. Review the connected model provider's retention and training policy before enabling MCP access; prefer synthetic fixtures.

## 6. Dated platform requirement

Google Play requires new apps and updates to target Android 16 / API 36 from **2026-08-31**. Expo SDK 57 already compiles against API 36; verify with `expo-doctor`.

The baseline tracks npm `latest` of `expo`, not prereleases. Checked 2026-10-13: `latest` = 57.0.28, `next` = 58.0.9. Move the baseline only when a new SDK reaches `latest`; re-check the tag. `eas-cli` `latest` = 24.13.0 (`engines.node` `^20.18.3 || >=22.0.0`). Install EAS CLI at a stated version, not `@latest`.

iOS builds run in an x86_64 macOS guest, capping Xcode at 26.6. Xcode 27 requires Apple silicon ([source](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes.md)). Do not plan Xcode 27 work on this guest. The ceiling is recorded in `registry/mobile-development.json` → `expectations.xcode`.

## 7. References

Read only when work reaches them; do not copy into a product repository.

- `references/store-compliance.md` – Apple App Privacy, privacy manifests, Google Data Safety, content rating, account-deletion requirements.
- `references/release-infrastructure.md` – Apple/Google organization setup, App Store Connect API keys, Play App Signing, beta lane structure.
## 8. Final check

- [ ] Product has an exact include record; health-sensitive work uses approved synthetic data.
- [ ] Identifiers match the authority and account drift is reported.
- [ ] Identity, signing, submission and credential changes have owner authority.
- [ ] Baseline and provider facts were checked for the selected target.
