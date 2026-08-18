#!/bin/bash
# Build an Expo app as an iOS *Simulator* .app inside the macOS guest, and
# install it on the booted simulator.
#
# Why this exists: the lab drives an app, it does not produce one, and a device
# build (.ipa / Debug-iphoneos) cannot run on a simulator -- different
# architecture, different SDK. This is the local equivalent of an EAS profile
# with ios.simulator: true, with no cloud queue and no credentials, because
# simulator builds are not code-signed.
#
# Release, not Debug, on purpose: a Debug build expects a Metro server and shows
# a red screen without one. Release runs the embedded JS bundle standalone,
# which is what an automated test needs.
#
# Usage:
#   bash build-expo-simulator.sh <repo-path> [scheme]
#
# Example:
#   bash ~/mobile-lab/build-expo-simulator.sh ~/Repos/shmindmaster/rexa Rexa

set -euo pipefail

REPO="${1:?usage: build-expo-simulator.sh <repo-path> [scheme]}"
SCHEME="${2:-}"

cd "$REPO"

say() { printf '\n=== %s ===\n' "$1"; }

say "preflight"
[ -f package.json ] || { echo "FATAL: no package.json in $REPO"; exit 1; }
if [ ! -d node_modules ]; then
  echo "node_modules missing -- installing (slow on this guest)"
  npm ci --no-audit --no-fund
fi

# Continuous Native Generation: ios/ is generated, not committed. Regenerate it
# when absent rather than failing, so a fresh checkout works.
if [ ! -d ios ]; then
  say "expo prebuild (ios/ absent)"
  npx expo prebuild --platform ios --no-install
fi

WORKSPACE="$(ls -d ios/*.xcworkspace 2>/dev/null | head -1 || true)"
if [ -z "$WORKSPACE" ]; then
  echo "FATAL: no .xcworkspace under ios/. Run: npx expo prebuild --platform ios"
  exit 1
fi
echo "workspace: $WORKSPACE"

if [ -z "$SCHEME" ]; then
  # Derive the app scheme from the workspace name; the pods scheme is
  # Pods-<name>, so match the bare name.
  SCHEME="$(basename "$WORKSPACE" .xcworkspace)"
fi
echo "scheme: $SCHEME"

say "xcodebuild (Release, iphonesimulator)"
# No `| tail` and no `| xcpretty`: a pipeline returns the LAST command's exit
# status, which has already reported a passing build for a failing one in this
# lab. The full log goes to a file and only the tail is printed afterwards.
#
# Ad-hoc signing rather than `CODE_SIGNING_ALLOWED=NO`. Disabling signing
# produced a binary with *no entitlements at all*, which silently broke every
# app in the lab that uses the keychain -- i.e. every app with authentication:
#
#   codesign -dv          -> flags=0x2(adhoc)     # signed anyway...
#   codesign -d --entitlements -   -> (nothing)   # ...but nothing declared
#
# Clerk stores its device token in the keychain, so its calls returned
# errSecMissingEntitlement (-34018), the SDK never initialized, and the app
# rendered a blank screen *without crashing*. That reads as a UI bug and cost a
# day in ABACare before anyone looked at the device log (2026-08-17).
#
# `-` needs no Apple account, no provisioning profile and no network, and an
# app that declares no entitlements builds exactly as it did before -- so this
# is strictly additive: it only starts embedding entitlements for the products
# that actually declare them.
#
# Do NOT "fix" a missing entitlement afterwards with `codesign --entitlements`.
# Measured both directions: a bundle re-signed that way verifies clean ("valid
# on disk", "satisfies its Designated Requirement") and is then refused by the
# simulator with "denied by service delegate (SBMainWorkspace)", while the same
# bundle re-signed ad-hoc with no entitlements launches normally. They have to
# be embedded here, at build time.
BUILD_DIR="$REPO/build/simulator"
set +e
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="-" \
  build >/tmp/expo-sim-build.log 2>&1
BUILD_RC=$?
set -e
tail -25 /tmp/expo-sim-build.log
if [ "$BUILD_RC" -ne 0 ]; then
  echo
  echo "FATAL: xcodebuild exited $BUILD_RC. Full log: /tmp/expo-sim-build.log"
  exit 1
fi

APP="$(ls -d "$BUILD_DIR"/Build/Products/Release-iphonesimulator/*.app 2>/dev/null | head -1 || true)"
if [ -z "$APP" ]; then
  echo "FATAL: build reported success but produced no .app under"
  echo "       $BUILD_DIR/Build/Products/Release-iphonesimulator/"
  echo "       Treat a 'successful' build with no artifact as a failure."
  exit 1
fi
say "built"
echo "$APP"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)"
echo "bundleId: ${BUNDLE_ID:-<unreadable>}"

say "install on booted simulator"
if ! xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
  echo "no simulator booted; skipping install."
  echo "Boot one and re-run, or install by hand:"
  echo "  xcrun simctl install booted '$APP'"
  exit 0
fi
xcrun simctl install booted "$APP"
echo "installed."
echo
echo "Drive it with appium:bundleId = ${BUNDLE_ID:-<unknown>}"
