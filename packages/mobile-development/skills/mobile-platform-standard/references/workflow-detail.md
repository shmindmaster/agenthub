# Workflow detail


## 2. Baseline

| Layer | Standard |
| --- | --- |
| Framework | Expo SDK 57, React Native 0.86, TypeScript, Expo Router |
| Native | Continuous Native Generation, config plugins, `expo-dev-client` (not Expo Go) |
| Builds | Local; EAS cloud only when the macOS guest is unavailable |
| Release | EAS Submit, Update, Workflows, Metadata (`store.config.json`), Environment Variables, Credentials |
| Quality | Maestro E2E, Sentry per product, EAS Observe, `expo-doctor` and `expo install --check` in CI |
| Push, links | `expo-notifications` (APNs, FCM v1); Universal Links, Android App Links |
| Versioning | EAS remote versions, `autoIncrement`, `runtimeVersion: { "policy": "fingerprint" }` |

Unchanged native state ships as EAS Update; changed native state builds and submits. Track npm `latest` of `expo`, never prereleases, and pin the EAS CLI version. Target Android 16 / API 36. The macOS guest is x86_64, so Xcode stops at 26.x (`registry/mobile-development.json` `expectations.xcode`).

## 3. Local builds

Android builds with `gradlew` on Windows. iOS builds in the macOS guest: `xcodebuild` for a Simulator `.app`, `eas build --platform ios --profile <p> --local` for a signed `.ipa`. Commands, signing checks and installing an `.ipa` on a phone: `references/release-infrastructure.md`.
