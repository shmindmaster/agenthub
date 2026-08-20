#!/bin/bash
# Build an Expo app as an iOS *Simulator* .app inside the macOS guest. Installation
# is deliberately left to the Appium session after the final exclusivity check.
#
# Why this exists: the lab drives an app, it does not produce one, and a device
# build (.ipa / Debug-iphoneos) cannot run on a simulator -- different
# architecture, different SDK. This is the local equivalent of an EAS profile
# with ios.simulator: true, with no cloud queue and no credentials, because
# simulator builds are not code-signed.
#
# Usage:
#   bash build-expo-simulator.sh <repo-path> [scheme] [simulator-udid] [flags]
#
# Flags:
#   --config Debug|Release   default Release. See "Which configuration" below.
#   --dev                    alias for --config Debug
#   --profile                add -showBuildTimingSummary (per-phase attribution)
#   --no-ccache              disable the compiler cache even if ccache is present
#   --all-archs              build every simulator arch, not just this host's
#
# Example:
#   bash ~/mobile-lab/build-expo-simulator.sh ~/Repos/shmindmaster/rexa Rexa
#
# ---------------------------------------------------------------- Which configuration
#
# Release is still the default, because an automated regression run needs the
# app to stand alone: Release embeds the JS bundle, so the binary behaves
# identically with nothing else running.
#
# Debug is the right choice for the *development* loop, and is structurally
# less work rather than merely less optimized. React Native's own
# scripts/react-native-xcode.sh short-circuits for Debug + simulator, printing
# "Skipping bundling in Debug for the Simulator (since the packager bundles for
# you)" -- so a Debug build skips Metro bundling and the hermesc bytecode pass
# entirely, on top of -O0 and no dSYM.
#
# The consequence that matters more than the speed: a Debug build has no
# embedded bundle, so its JavaScript comes from Metro at runtime. Change JS,
# reload, see it -- no rebuild. And because Metro is what inlines EXPO_PUBLIC_*
# values, the .env that supplies them has to exist on whichever machine runs
# Metro, which can simply be the Windows host. See Start-MobileLabMetro.ps1.
#
# The trap to know about: Debug is not a substitute for Release when the thing
# under test is startup time, Hermes bytecode behaviour, or anything gated on
# __DEV__. Release-only faults are real and current in this RN line.

set -euo pipefail

REPO="${1:?usage: build-expo-simulator.sh <repo-path> [scheme] [simulator-udid] [flags]}"
SCHEME="${2:-}"
SIMULATOR_UDID="${3:-booted}"
shift $(( $# < 3 ? $# : 3 ))

CONFIGURATION="Release"
PROFILE=0
USE_CCACHE_FLAG=1
ALL_ARCHS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --config)     CONFIGURATION="${2:?--config needs Debug or Release}"; shift 2 ;;
    --dev)        CONFIGURATION="Debug"; shift ;;
    --profile)    PROFILE=1; shift ;;
    --no-ccache)  USE_CCACHE_FLAG=0; shift ;;
    --all-archs)  ALL_ARCHS=1; shift ;;
    *) echo "FATAL: unknown flag '$1'"; exit 2 ;;
  esac
done

case "$CONFIGURATION" in
  Debug|Release) ;;
  *) echo "FATAL: --config must be Debug or Release, got '$CONFIGURATION'"; exit 2 ;;
esac

cd "$REPO"

say() { printf '\n=== %s ===\n' "$1"; }

say "preflight ($CONFIGURATION)"
[ -f package.json ] || { echo "FATAL: no package.json in $REPO"; exit 1; }
if [ ! -x node_modules/.bin/expo ]; then
  echo "node_modules missing -- installing (slow on this guest)"
  npm ci --no-audit --no-fund
fi

# Continuous Native Generation: ios/ is generated, not committed. Regenerate it
# when absent rather than failing, so a fresh checkout works.
#
# Deliberately NOT --clean. Expo SDK 57 made `prebuild` clean by default, which
# regenerates the whole project and throws away target-level incrementality.
# Adding an existing-directory prebuild here would silently convert every warm
# build into a cold one.
if [ ! -d ios ]; then
  say "expo prebuild (ios/ absent)"
  npx expo prebuild --platform ios --no-install
fi

WORKSPACE="$(ls -d ios/*.xcworkspace 2>/dev/null | head -1 || true)"
if [ -z "$WORKSPACE" ] && [ -f ios/Podfile ]; then
  say "pod install (workspace absent)"
  npx pod-install
  WORKSPACE="$(ls -d ios/*.xcworkspace 2>/dev/null | head -1 || true)"
fi
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

# ------------------------------------------------------------------ build settings
BUILD_SETTINGS=()

# Only this host's architecture.
#
# React Native ships precompiled xcframeworks for iOS by default since 0.84,
# and their simulator slices really do carry x86_64 as well as arm64 -- so an
# Intel guest is not forced to compile RN core from source. What it *was* doing
# is compiling everything else twice: the Expo bare template sets
# ONLY_ACTIVE_ARCH=YES in the Debug configuration only, so a Release simulator
# build defaults it to NO and builds arm64 *and* x86_64 for every app target
# and every pod. On an x86-only host the arm64 half cannot be run by anything.
#
# Prebuilts cover React core, its C++ dependencies and Hermes -- and nothing
# else. Every expo-* and community pod still compiles from source, which is why
# halving that work is the largest single lever on this machine rather than a
# rounding error.
if [ "$ALL_ARCHS" -eq 0 ]; then
  HOST_ARCH="$(uname -m)"
  BUILD_SETTINGS+=( "ONLY_ACTIVE_ARCH=YES" "ARCHS=$HOST_ARCH" )
  echo "arch: $HOST_ARCH only (pass --all-archs to build every simulator slice)"
else
  echo "arch: all simulator slices"
fi

# ccache is first-party in this React Native line: react_native_pods.rb reads
# USE_CCACHE, and RN ships its own compiler shims and a ccache.conf whose
# sloppiness settings exist specifically to survive Xcode's index store, module
# maps and VFS overlays. Enabled when the binary is actually installed --
# exporting USE_CCACHE=1 without ccache present only produces a warning at pod
# time, which is a confusing way to learn it did nothing.
if [ "$USE_CCACHE_FLAG" -eq 1 ] && command -v ccache >/dev/null 2>&1; then
  export USE_CCACHE=1
  echo "ccache: enabled ($(ccache --version 2>/dev/null | head -1))"
else
  if [ "$USE_CCACHE_FLAG" -eq 1 ]; then
    echo "ccache: not installed (brew install ccache) -- continuing without it"
  else
    echo "ccache: disabled by --no-ccache"
  fi
fi

XCODE_EXTRA=()
if [ "$PROFILE" -eq 1 ]; then
  # The only honest way to argue about where the time goes. Attributes build
  # time per phase, which distinguishes compilation from codegen script phases
  # from artifact downloads -- three causes that all present as "the build is
  # slow" and have completely different fixes.
  XCODE_EXTRA+=( "-showBuildTimingSummary" )
  export EXPO_PROFILE=1
fi

say "xcodebuild ($CONFIGURATION, iphonesimulator)"
# No `| tail` and no `| xcpretty`: a pipeline returns the LAST command's exit
# status, which has already reported a passing build for a failing one in this
# lab. The full log goes to a file and only the tail is printed afterwards.
#
# Ad-hoc signing rather than `CODE_SIGNING_ALLOWED=NO`. `-` needs no Apple
# account, no provisioning profile and no network, so this costs nothing and is
# closer to how a real build is produced.
#
# CORRECTION 2026-08-17, same day this was introduced. It was added on the
# theory that `CODE_SIGNING_ALLOWED=NO` broke keychain access -- the binary
# carries no entitlements, Clerk's keychain calls return
# errSecMissingEntitlement (-34018), and the app renders a blank screen without
# crashing. Two parts of that turned out to be wrong, both measured on ABACare:
#
#  1. The entitlement was never the blocker. The blank screen was Clerk's
#     Native API being disabled on the instance (every `_is_native=1` request
#     returned 400 `native_api_disabled`). With that toggled on, the app
#     reaches its sign-in screen and passes its Maestro flow. `-34018` still
#     appears in the log and is not fatal -- Clerk's bridge sets no
#     accessGroup, so its items use the app's default keychain access group,
#     which needs no entitlement.
#
#  2. These flags do not embed entitlements anyway. On a simulator build with
#     no provisioning profile, `codesign -d --entitlements` on the product of
#     *this* command still reports an empty `<dict/>`, even with
#     CODE_SIGN_ENTITLEMENTS set in the project.
#
# So: keep it, because it is harmless and verified to build and launch, but do
# not reach for it to solve a keychain or entitlement problem. It will not.
#
# Do NOT "fix" a missing entitlement afterwards with `codesign --entitlements`.
# Measured both directions: a bundle re-signed that way verifies clean ("valid
# on disk", "satisfies its Designated Requirement") and is then refused by the
# simulator with "denied by service delegate (SBMainWorkspace)", while the same
# bundle re-signed ad-hoc with no entitlements launches normally.
BUILD_DIR="$REPO/build/simulator"
BUILD_LOG="/tmp/expo-sim-build.log"
BUILD_STARTED=$(date +%s)
set +e
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$BUILD_DIR" \
  "${XCODE_EXTRA[@]}" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="-" \
  "${BUILD_SETTINGS[@]}" \
  build >"$BUILD_LOG" 2>&1
BUILD_RC=$?
set -e
BUILD_SECONDS=$(( $(date +%s) - BUILD_STARTED ))
tail -25 "$BUILD_LOG"
if [ "$BUILD_RC" -ne 0 ]; then
  echo
  echo "FATAL: xcodebuild exited $BUILD_RC after ${BUILD_SECONDS}s. Full log: $BUILD_LOG"
  exit 1
fi

# A prebuilt artifact that fails to download does not fail the build -- RN logs
# "No prebuilt artifacts found, reverting to building from source" and compiles
# React core itself, which is most of the difference between a slow build and a
# very slow one. Silent by design, so surface it.
if grep -q 'reverting to building from source' "$BUILD_LOG" 2>/dev/null; then
  echo
  echo "NOTE: React Native prebuilt artifacts were unavailable and core was compiled"
  echo "      from source. That is usually a network or mirror problem, not a code"
  echo "      one, and it accounts for a large part of this build's duration."
  echo "      The shared cache lives at ~/Library/Caches/ReactNative."
fi

APP="$(ls -d "$BUILD_DIR/Build/Products/$CONFIGURATION-iphonesimulator"/*.app 2>/dev/null | head -1 || true)"
if [ -z "$APP" ]; then
  echo "FATAL: build reported success but produced no .app under"
  echo "       $BUILD_DIR/Build/Products/$CONFIGURATION-iphonesimulator/"
  echo "       Treat a 'successful' build with no artifact as a failure."
  exit 1
fi
say "built in ${BUILD_SECONDS}s"
echo "$APP"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)"
echo "bundleId: ${BUNDLE_ID:-<unreadable>}"

echo
echo "built for simulator $SIMULATOR_UDID; Appium will install after the final idle check."
echo "Drive it with appium:bundleId = ${BUNDLE_ID:-<unknown>}"

if [ "$CONFIGURATION" = "Debug" ]; then
  cat <<EOF

This is a Debug build: it carries no JavaScript bundle and will show a red
screen until it is pointed at a Metro server. That is the intended state -- it
is what makes every later JS change a reload instead of another build.

From the Windows host:
  .\\Start-MobileLabMetro.ps1 -ProjectPath <windows-path-to-app>
which starts Metro bound to an address the guest can reach, and prints the
exact deep link to hand this build.
EOF
fi
