#!/bin/bash
# Idempotent Appium setup for the macOS guest. Safe to re-run.
#
# Deliberate choices, each with a reason recorded in
# references/architecture-decisions.md:
#   * no sudo -- node is nvm-managed and user-owned; sudo would either miss
#     nvm's node or leave root-owned files in the user's tree
#   * pinned versions -- so a re-run does not silently move the lab
#   * no `| tail` on anything whose exit code matters; a pipeline returns the
#     LAST command's status, which has already reported PASS on a failed build
#     in this lab once
#
# Run from Windows:  ssh macvm 'bash ~/mobile-lab/setup-appium-guest.sh'

set -euo pipefail

APPIUM_VERSION="3.6.0"
XCUITEST_VERSION="12.3.1"

say() { printf '\n=== %s ===\n' "$1"; }

say "preflight"
command -v node >/dev/null || { echo "FATAL: node not on PATH"; exit 1; }
node_major="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$node_major" -lt 24 ] && [ "$node_major" -ne 22 ] && [ "$node_major" -ne 20 ]; then
  echo "FATAL: node $(node --version) does not satisfy appium@${APPIUM_VERSION}"
  echo "       engines.node = ^20.19.0 || ^22.12.0 || >=24.0.0"
  exit 1
fi
echo "node $(node --version)"

# Ask the toolchain, never a path. xcodes installs /Applications/Xcode-<ver>.app,
# so a literal /Applications/Xcode.app test is false on a perfectly good install
# -- that exact mistake silently skipped a compile step in this lab before.
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "FATAL: xcodebuild not usable. Try: sudo xcodebuild -runFirstLaunch"
  exit 1
fi
# Captured, NOT piped to `head`. Under `set -euo pipefail`, `head` closes the
# pipe after one line, the producer takes SIGPIPE, pipefail propagates the
# non-zero status and `set -e` exits the script -- silently, right here, with
# everything after it skipped. It is a race, so it passes most runs and then
# fails once. Same reason ffmpeg below is captured rather than piped.
xcodebuild_version="$(xcodebuild -version 2>/dev/null)"
printf '%s\n' "${xcodebuild_version%%$'\n'*}"

if ! xcrun simctl list runtimes 2>/dev/null | grep -q "iOS"; then
  echo "FATAL: no iOS simulator runtime installed."
  echo "       Installing Xcode does NOT install a runtime; it is a separate"
  echo "       ~10.6 GB download:"
  echo "         sudo xcodebuild -downloadPlatform iOS -architectureVariant universal"
  exit 1
fi

say "appium ${APPIUM_VERSION}"
if appium --version 2>/dev/null | grep -q "^${APPIUM_VERSION}$"; then
  echo "already installed"
else
  # First run of a fresh install is slow here (cold cache, software rendering,
  # ~250 modules). Minutes is normal; it is not a hang.
  npm install -g "appium@${APPIUM_VERSION}"
fi
appium --version

say "xcuitest driver ${XCUITEST_VERSION}"
if appium driver list --installed 2>&1 | grep -q "xcuitest@${XCUITEST_VERSION}"; then
  echo "already installed"
else
  appium driver install "xcuitest@${XCUITEST_VERSION}" || \
    appium driver update xcuitest --unsafe || true
fi
# `|| true`: grep exits 1 when it matches nothing, and under `set -e` that
# would abort the script on an informational line.
appium driver list --installed 2>&1 | grep xcuitest || true

say "driver doctor"
# Exit code is what matters; the driver reports optional gaps as warnings.
#
# Bounded, because the doctor can block indefinitely: observed hanging for
# 11+ minutes at 4.7s CPU (blocked in its event loop, no children) while a
# leftover WebDriverAgent xcodebuild from an earlier session was still alive.
# macOS ships no coreutils `timeout`, hence the hand-rolled watchdog. A
# timeout is reported as a failure, not swallowed -- a diagnostic that
# silently gave up is worse than one that never ran.
DOCTOR_TIMEOUT="${DOCTOR_TIMEOUT:-300}"
appium driver doctor xcuitest </dev/null >/tmp/wda-doctor.out 2>&1 &
doctor_pid=$!
waited=0
while [ "$waited" -lt "$DOCTOR_TIMEOUT" ]; do
  kill -0 "$doctor_pid" 2>/dev/null || break
  sleep 5
  waited=$((waited + 5))
done
if kill -0 "$doctor_pid" 2>/dev/null; then
  kill -9 "$doctor_pid" 2>/dev/null || true
  echo "FATAL: driver doctor did not finish within ${DOCTOR_TIMEOUT}s."
  echo "       This usually means a stale WebDriverAgent xcodebuild or"
  echo "       simulator process is still holding the toolchain. Clear them"
  echo "       and re-run:"
  echo "         pkill -f 'xcodebuild.*WebDriverAgent'; xcrun simctl shutdown all"
  tail -20 /tmp/wda-doctor.out || true
  exit 1
fi
wait "$doctor_pid"; doctor_rc=$?
tail -20 /tmp/wda-doctor.out
if [ "$doctor_rc" -eq 0 ]; then
  echo "doctor: 0 required fixes"
else
  echo "FATAL: driver doctor reported required fixes above (exit $doctor_rc)"
  exit 1
fi

say "ffmpeg (screen recording evidence)"
if command -v ffmpeg >/dev/null; then
  ffmpeg_version="$(ffmpeg -version 2>/dev/null)"
  echo "present: ${ffmpeg_version%%$'\n'*}"
else
  HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg
fi

# applesimutils is deliberately NOT installed -- brew refuses it as an
# untrusted third-party tap, and trusting a tap is an owner decision. It is
# only needed for `mobile: setPermission`. Opt in with:
#   brew trust wix/brew && brew install applesimutils

say "prebuild WebDriverAgent"
# Warms Xcode's DerivedData so the first real session is not also a cold build.
# NOTE: this builds WDA; it does NOT install it onto a simulator. Do not set
# appium:usePrebuiltWDA until `simctl listapps booted` actually shows it.
#
# Guarded: `build-wda` always rebuilds, which costs ~3.5 min on this guest
# every run. An unconditional call makes re-running this script expensive
# enough that people stop re-running it, which defeats the point of it being
# idempotent. Pass --force-wda to rebuild deliberately.
WDA_PRODUCT="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/WebDriverAgent-*/Build/Products/Debug-iphonesimulator/WebDriverAgentRunner-Runner.app 2>/dev/null | head -1 || true)"
if [ -n "$WDA_PRODUCT" ] && [ "${1:-}" != "--force-wda" ]; then
  echo "already built: $WDA_PRODUCT"
  echo "(re-run with --force-wda to rebuild)"
else
  appium driver run xcuitest build-wda
fi

say "done"
echo "Start the server with: bash ~/mobile-lab/start-appium-guest.sh"
