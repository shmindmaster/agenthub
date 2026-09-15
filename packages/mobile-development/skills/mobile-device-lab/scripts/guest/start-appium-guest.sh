#!/bin/bash
# Start Appium in the macOS guest so it survives the ssh session that started
# it, and comes back after a guest reboot.
#
# A plain `ssh macvm 'appium &'` does NOT survive -- the process dies with the
# channel. This installs a launchd LaunchAgent instead, which is what makes the
# lab available without a human starting anything.
#
# Run from Windows:  ssh macvm 'bash ~/mobile-lab/start-appium-guest.sh'

set -euo pipefail

LABEL="dev.shmindmaster.appium"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/mobile-lab"
FACTS="$HOME/mobile-lab/mobile-development.env"
[ -f "$FACTS" ] || { echo "FATAL: canonical mobile-development.env is missing; rerun mobile.ps1 start ios" >&2; exit 1; }
# shellcheck source=/dev/null
. "$FACTS"
PORT="${APPIUM_PORT:?APPIUM_PORT missing from mobile-development.env}"
BIND_ADDRESS="${APPIUM_BIND_ADDRESS:?APPIUM_BIND_ADDRESS missing from mobile-development.env}"

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

APPIUM_BIN="$(command -v appium)" || { echo "FATAL: appium not on PATH; run setup-appium-guest.sh first"; exit 1; }
NODE_BIN="$(command -v node)"
NODE_DIR="$(dirname "$NODE_BIN")"

# launchd does NOT source .zshenv, so the agent gets none of the interactive
# PATH. Resolve node's directory now and bake it in; nvm's path is version-
# specific, so regenerating the plist on every run is what keeps it correct
# across a node upgrade rather than silently pointing at a removed version.
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${APPIUM_BIN}</string>
    <string>server</string>
    <string>--address</string><string>${BIND_ADDRESS}</string>
    <string>--port</string><string>${PORT}</string>
    <string>--use-drivers</string><string>xcuitest</string>
    <string>--allow-insecure</string><string>*:session_discovery</string>
    <string>--log-level</string><string>info</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${NODE_DIR}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key><string>${HOME}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG_DIR}/appium.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/appium.err.log</string>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST_EOF

echo "wrote $PLIST"

UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
bootstrapped=0
# bootout can return before launchd has fully removed the old job. An immediate
# bootstrap then intermittently fails with error 5 even though the plist is
# valid; retry the documented operation instead of leaving Appium down.
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  if launchctl bootstrap "gui/${UID_NUM}" "$PLIST"; then
    bootstrapped=1
    break
  fi
  sleep 1
done
if [ "$bootstrapped" -ne 1 ]; then
  echo "FATAL: launchctl bootstrap did not succeed after 30 attempts." >&2
  exit 1
fi
launchctl enable "gui/${UID_NUM}/${LABEL}"

echo "launchd agent bootstrapped: ${LABEL}"
echo "logs: ${LOG_DIR}/appium.log"
echo
echo "Cold start takes minutes on this guest. Poll rather than assume:"
echo "  curl -s http://127.0.0.1:${PORT}/status"
