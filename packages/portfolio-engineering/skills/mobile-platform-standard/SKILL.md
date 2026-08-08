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
| Builds / distribution / OTA | EAS Build, EAS Submit, EAS Update |
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

## 3. Three installable variants, not three profiles

Development, preview, and production must install side by side on one device,
which requires distinct application identifiers - not just distinct EAS build
profiles. Drive them from `APP_VARIANT` in `app.config.ts`:

```ts
const variant = process.env.APP_VARIANT ?? "production";
const suffix =
  variant === "development" ? ".dev" : variant === "preview" ? ".preview" : "";
```

Apply `suffix` to both `ios.bundleIdentifier` and `android.package`, and vary
the display name to match.

## 4. Identifier conventions

- Reverse-DNS from the product's own domain (`ai.abacare.mobile`), not a
  shared vendor prefix.
- One EAS project per product. The EAS slug equals the product's `productId`
  in `registry/mobile-scope.json`.
- Anything compiled into client JavaScript is public. EAS secrets do not make
  an embedded `EXPO_PUBLIC_*` value private.

**The EAS slug cannot be renamed.** Verified 2026-08-08 against eas-cli 21.7.0
and the Expo dashboard: `eas project` exposes only
`icon`/`delete`/`info`/`init`/`new`, and project settings edits a separate
"Display name" while the Danger zone offers only transfer and delete. The only
route to a different slug is a new project, which means a new project ID, lost
build history, and regenerated credentials.

Cautionary case: Rexa's EAS project shipped as `@shmindmaster/recallforge` -
the pre-rename product name, now permanent for that project ID. Set the slug
from the final name, or freeze the product until there is one.

## 5. Health-sensitive products

`registry/mobile-scope.json` marks products with `healthSensitive: true`
(currently `abacare` and `gentlenext`). For those, do not enable screenshot
collection, session replay, or broad AI/MCP access against real patient data.
Review the connected model provider's retention and training policy before
enabling MCP access at all, and prefer synthetic fixtures.

## 6. Dated platform requirement

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
