#!/bin/bash
# Idempotent Appium setup for the macOS guest. Safe to re-run.
#
# Deliberate choices, each with a reason recorded in
# references/architecture-decisions.md:
#   * no sudo -- node is nvm-managed and user-owned; sudo would either miss
#     nvm's node or leave root-owned files in the user's tree
#   * pinned versions -- so a re-run does not silently move the lab
#   * fail closed -- every install, uninstall, and doctor result is checked and
#     the installed version is re-read afterwards; nothing is `|| true`'d. The
#     old `install || update --unsafe || true` reported success after a failed
#     install, and `update --unsafe` would have moved the driver off its pin.
#   * no `| tail`, `| head`, or `| grep -q` on anything whose exit code matters;
#     a pipeline returns the LAST command's status, which has already reported
#     PASS on a failed build in this lab once, and an early-exiting reader can
#     SIGPIPE the producer and fail a healthy check under pipefail
#   * never kill or shut down what this script did not start -- another agent
#     holding the mobile-lab lease may own a WebDriverAgent runner or a booted
#     Simulator, so remedies name owners instead of `pkill`/`shutdown all`
#
# Run from Windows:  ssh macvm 'bash ~/mobile-lab/setup-appium-guest.sh'
# bash 3.2 (macOS /bin/bash) compatible: no mapfile, no associative arrays.

set -euo pipefail

FACTS="$HOME/mobile-lab/mobile-development.env"
[ -f "$FACTS" ] || { echo "FATAL: canonical mobile-development.env is missing; rerun mobile.ps1 start ios" >&2; exit 1; }
# shellcheck source=/dev/null
. "$FACTS"
: "${APPIUM_VERSION:?APPIUM_VERSION missing from mobile-development.env}"
: "${XCUITEST_VERSION:?XCUITEST_VERSION missing from mobile-development.env}"

STATE_DIR="$HOME/mobile-lab/state"
LOG_DIR="$HOME/mobile-lab/logs"
WDA_STAMP="$STATE_DIR/wda-build.key"
mkdir -p "$STATE_DIR" "$LOG_DIR"

say() { printf '\n=== %s ===\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; shift; for line in "$@"; do printf '       %s\n' "$line" >&2; done; exit 1; }

# Installed driver facts come from Appium's own JSON listing, never from a
# substring grep: "xcuitest@12.18.1" also matches 12.18.10, and a listing that
# failed to run must not read as "not installed".
installed_driver_field() { # <field>; prints the value, empty when the driver is absent
  local json rc=0
  json="$(appium driver list --installed --json 2>"$LOG_DIR/driver-list.err")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fatal "appium driver list --installed --json failed (exit $rc); cannot tell which driver is installed." \
          "$(cat "$LOG_DIR/driver-list.err" 2>/dev/null || true)"
  fi
  DRIVERS_JSON="$json" node -e '
    const raw = process.env.DRIVERS_JSON || "";
    let data;
    try { data = JSON.parse(raw); }
    catch (e) {
      const start = raw.indexOf("{"), end = raw.lastIndexOf("}");
      try { data = JSON.parse(raw.slice(start, end + 1)); }
      catch (e2) { console.error("unparseable driver list: " + raw.slice(0, 200)); process.exit(2); }
    }
    const d = data && data.xcuitest;
    if (!d || d.installed === false) process.exit(0);
    const v = d[process.argv[1]];
    if (v !== undefined && v !== null) process.stdout.write(String(v));
  ' "$1" || fatal "could not parse 'appium driver list --installed --json' output."
}

# WebDriverAgent is built from the driver's appium-webdriveragent dependency,
# which npm may nest or hoist.
wda_source_version() { # <driver installPath>
  [ -n "$1" ] || return 0
  node -e '
    const path = require("path"), fs = require("fs");
    const root = process.argv[1];
    for (const candidate of [
      path.join(root, "node_modules", "appium-webdriveragent", "package.json"),
      path.join(root, "..", "appium-webdriveragent", "package.json"),
    ]) {
      try { process.stdout.write(JSON.parse(fs.readFileSync(candidate, "utf8")).version); process.exit(0); } catch (e) {}
    }
  ' "$1" || true
}

say "preflight"
command -v node >/dev/null || fatal "node not on PATH"
# appium engines.node = ^20.19.0 || ^22.12.0 || >=24.0.0 -- minor matters too.
if ! node -e '
  const [maj, min] = process.versions.node.split(".").map(Number);
  process.exit(maj >= 24 || (maj === 22 && min >= 12) || (maj === 20 && min >= 19) ? 0 : 1);
'; then
  fatal "node $(node --version) does not satisfy appium@${APPIUM_VERSION}" \
        "engines.node = ^20.19.0 || ^22.12.0 || >=24.0.0"
fi
echo "node $(node --version)"

# Ask the toolchain, never a path. xcodes installs /Applications/Xcode-<ver>.app,
# so a literal /Applications/Xcode.app test is false on a perfectly good install
# -- that exact mistake silently skipped a compile step in this lab before.
# Captured, NOT piped to `head`: under pipefail an early-closing reader can
# SIGPIPE the producer and exit the script silently, once in a while.
xcodebuild_version="$(xcodebuild -version 2>/dev/null)" || fatal "xcodebuild not usable. Try: sudo xcodebuild -runFirstLaunch"
xcode_line="${xcodebuild_version%%$'\n'*}"
xcode_build="$(printf '%s\n' "$xcodebuild_version" | sed -n 's/^Build version //p')"
printf '%s (build %s)\n' "$xcode_line" "${xcode_build:-unknown}"
guest_arch="$(uname -m)"
echo "guest architecture: $guest_arch"
if [ -n "${XCODE_MAX_COMPATIBLE:-}" ]; then
  installed_xcode="${xcode_line#Xcode }"
  if [ "$installed_xcode" != "$XCODE_MAX_COMPATIBLE" ]; then
    # Reported, not fatal: the parent owns the Xcode install. The registry
    # records the newest Xcode this guest's architecture can run.
    echo "NOTE: guest runs Xcode ${installed_xcode}; the newest Xcode this ${guest_arch} guest can run is ${XCODE_MAX_COMPATIBLE} (${XCODE_CEILING_REASON:-see registry expectations.xcode})."
  fi
fi

runtimes="$(xcrun simctl list runtimes 2>/dev/null)" || fatal "xcrun simctl list runtimes failed."
case "$runtimes" in
  *iOS*) ;;
  *) fatal "no iOS simulator runtime installed." \
           "Installing Xcode does NOT install a runtime; it is a separate" \
           "~10.6 GB download:" \
           "  sudo xcodebuild -downloadPlatform iOS -architectureVariant universal" ;;
esac

say "appium ${APPIUM_VERSION}"
current_appium="$(appium --version 2>/dev/null || true)"
if [ "$current_appium" = "$APPIUM_VERSION" ]; then
  echo "already installed"
else
  echo "installed: ${current_appium:-none}; installing pin ${APPIUM_VERSION}"
  # First run of a fresh install is slow here (cold cache, software rendering,
  # ~250 modules). Minutes is normal; it is not a hang.
  npm install -g "appium@${APPIUM_VERSION}" || fatal "npm install -g appium@${APPIUM_VERSION} failed; the lab is not on its pin."
  current_appium="$(appium --version 2>/dev/null || true)"
  [ "$current_appium" = "$APPIUM_VERSION" ] || fatal "after install, appium --version reports '${current_appium:-nothing}', not ${APPIUM_VERSION}." \
    "Another appium earlier on PATH ($(command -v appium || echo none)) may be shadowing the npm global install."
fi
echo "appium $current_appium"

say "xcuitest driver ${XCUITEST_VERSION}"
current_driver="$(installed_driver_field version)"
if [ "$current_driver" = "$XCUITEST_VERSION" ]; then
  echo "already installed"
else
  if [ -n "$current_driver" ]; then
    # `appium driver install` refuses an installed name, and `update` resolves
    # to the newest release rather than the pin. Uninstall, then install the pin.
    echo "installed: ${current_driver}; replacing with pin ${XCUITEST_VERSION}"
    appium driver uninstall xcuitest || fatal "appium driver uninstall xcuitest failed; xcuitest ${current_driver} is still installed and is not the pin."
  fi
  appium driver install "xcuitest@${XCUITEST_VERSION}" || \
    fatal "appium driver install xcuitest@${XCUITEST_VERSION} failed; no pinned xcuitest driver is installed." \
          "Fix the reported npm/network error and re-run this script."
  current_driver="$(installed_driver_field version)"
  [ "$current_driver" = "$XCUITEST_VERSION" ] || fatal "after install, Appium reports xcuitest '${current_driver:-absent}', not ${XCUITEST_VERSION}."
fi
driver_path="$(installed_driver_field installPath)"
wda_version="$(wda_source_version "$driver_path")"
echo "xcuitest ${current_driver} (WebDriverAgent ${wda_version:-unknown}) at ${driver_path:-unknown path}"

say "driver doctor"
# Appium's doctor exits non-zero with "Treatment required" when a required fix
# is outstanding and prints "N required fixes needed"; a driver that exports
# no checks exits 0 having checked nothing. Each case is reported as itself.
# The matched strings are Appium 3.8.0's own (build/lib/doctor/doctor.js and
# build/lib/cli/extension-command.js, read 2026-10-13); re-check them when the
# Appium pin moves.
#
# Bounded, because the doctor can block indefinitely: observed hanging for
# 11+ minutes at 4.7s CPU (blocked in its event loop, no children) while a
# leftover WebDriverAgent xcodebuild from an earlier session was still alive.
# macOS ships no coreutils `timeout`, hence the hand-rolled watchdog.
DOCTOR_TIMEOUT="${DOCTOR_TIMEOUT:-300}"
DOCTOR_POLL="${DOCTOR_POLL:-5}"
doctor_out="$(mktemp "$LOG_DIR/wda-doctor.XXXXXX")"
appium driver doctor xcuitest </dev/null >"$doctor_out" 2>&1 &
doctor_pid=$!
waited=0
while [ "$waited" -lt "$DOCTOR_TIMEOUT" ]; do
  kill -0 "$doctor_pid" 2>/dev/null || break
  sleep "$DOCTOR_POLL"
  waited=$((waited + DOCTOR_POLL))
done
if kill -0 "$doctor_pid" 2>/dev/null; then
  # Our own doctor child and its direct children (e.g. an xcodebuild it
  # spawned) are the only processes this script ever terminates; anything
  # else is listed below for its owner to retire.
  doctor_children="$(ps -axo pid=,ppid= 2>/dev/null | awk -v p="$doctor_pid" '$2 == p { print $1 }')" || doctor_children=""
  for doctor_child in $doctor_children; do kill -9 "$doctor_child" 2>/dev/null || true; done
  kill -9 "$doctor_pid" 2>/dev/null || true
  wait "$doctor_pid" 2>/dev/null || true
  echo "--- doctor output so far ($doctor_out) ---"
  cat "$doctor_out" || true
  echo "--- WebDriverAgent runners currently alive (read-only listing) ---"
  # Diagnostic only: a failed listing must not abort before the FATAL reason.
  listing="$(ps -axo pid=,ppid=,command= 2>/dev/null)" || listing=""
  if [ -z "$listing" ]; then
    echo "(process listing unavailable)"
  else
    printf '%s\n' "$listing" | while read -r pid ppid command; do
      case "$command" in
        *xcodebuild*WebDriverAgent*)
          parent="$(ps -p "$ppid" -o command= 2>/dev/null || true)"
          printf 'pid=%s ppid=%s parent=%s\n  %s\n' "$pid" "$ppid" "${parent:-<gone>}" "$command" ;;
      esac
    done
  fi
  fatal "driver doctor did not finish within ${DOCTOR_TIMEOUT}s (timed out; this is not a required-fix report)." \
        "A leftover WebDriverAgent xcodebuild or Simulator can hold the toolchain. The runners above" \
        "are listed with their parent. Retire only one you own: end its Appium session, or run" \
        "  bash ~/mobile-lab/cleanup-wda-guest.sh <simulator-udid>" \
        "which stops only Appium-owned runners for that Simulator. Do not pkill WebDriverAgent or" \
        "'simctl shutdown all': another agent holding the mobile-lab lease may own them."
fi
doctor_rc=0
wait "$doctor_pid" || doctor_rc=$?
cat "$doctor_out"
# awk, not a greedy sed capture (which reads "12 required" as 2), and it exits
# 0 on no match, so a clean report cannot trip set -e here.
required="$(awk 'match($0, /[0-9]+ required fix/) { s = substr($0, RSTART, RLENGTH); sub(/ .*/, "", s); n = s } END { print n }' "$doctor_out")"
if [ "$doctor_rc" -ne 0 ]; then
  if [ -n "$required" ] && [ "$required" -gt 0 ]; then
    fatal "driver doctor reported ${required} required fix(es) above (exit $doctor_rc)."
  fi
  fatal "driver doctor failed to run (exit $doctor_rc) and reported no required-fix count; this is a doctor/driver error, not a clean bill of health. See $doctor_out."
fi
if [ -n "$required" ] && [ "$required" -gt 0 ]; then
  fatal "driver doctor exited 0 but reported ${required} required fix(es); refusing to treat that as healthy."
fi
if grep -Eq 'does not export any doctor checks|exports no valid doctor checks|Unable to load doctor checks' "$doctor_out"; then
  fatal "driver doctor did not run its checks (see output above); '0 required fixes' cannot be claimed."
fi
echo "doctor: 0 required fixes"
rm -f "$doctor_out" # failures keep theirs for inspection

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
# Version-aware: `build-wda` costs ~3.5 min on this guest, so it is skipped
# when the last successful build was made from the same xcuitest driver, the
# same WebDriverAgent source, and the same Xcode build. Any of those moving
# (a pin change, a driver reinstall, an Xcode update) makes an existing
# product stale, and the old "any WebDriverAgent-* product exists" test kept
# it. An unknown WDA version never matches. Pass --force-wda to rebuild anyway.
wda_key="xcuitest=${current_driver};wda=${wda_version:-unknown};xcode=${xcode_build:-unknown}"
recorded_key="$(cat "$WDA_STAMP" 2>/dev/null || true)"
wda_product=""
for candidate in "$HOME"/Library/Developer/Xcode/DerivedData/WebDriverAgent-*/Build/Products/Debug-iphonesimulator/WebDriverAgentRunner-Runner.app; do
  if [ -d "$candidate" ]; then wda_product="$candidate"; break; fi
done
if [ "${1:-}" = "--force-wda" ]; then
  wda_reason="--force-wda"
elif [ -z "$wda_product" ]; then
  wda_reason="no built WebDriverAgentRunner product"
elif [ -z "$wda_version" ] || [ -z "$xcode_build" ]; then
  wda_reason="WebDriverAgent source or Xcode build version is unknown, so the existing product cannot be matched"
elif [ "$recorded_key" != "$wda_key" ]; then
  wda_reason="built for '${recorded_key:-unrecorded}', current is '${wda_key}'"
else
  wda_reason=""
fi
if [ -z "$wda_reason" ]; then
  echo "already built for ${wda_key}: $wda_product"
  echo "(re-run with --force-wda to rebuild)"
else
  echo "building WebDriverAgent: ${wda_reason}"
  rm -f "$WDA_STAMP"
  appium driver run xcuitest build-wda || fatal "appium driver run xcuitest build-wda failed for ${wda_key}."
  printf '%s\n' "$wda_key" >"$WDA_STAMP"
  echo "built for ${wda_key}"
fi

say "done"
echo "Start the server with: bash ~/mobile-lab/start-appium-guest.sh"
