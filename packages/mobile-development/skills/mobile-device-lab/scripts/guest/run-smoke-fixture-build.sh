#!/bin/bash
set -u

STATE_DIR="$HOME/mobile-lab/state"
PID_FILE="$STATE_DIR/smoke-fixture.pid"
STATUS_FILE="$STATE_DIR/smoke-fixture.status"
LOG_FILE="$STATE_DIR/smoke-fixture.log"
BUILDER="$HOME/mobile-lab/build-expo-simulator.sh"
mkdir -p "$STATE_DIR"

if [ "${1:-}" = "--worker" ]; then
  REPO="${2:?worker requires repo path}"
  UDID="${3:?worker requires simulator UDID}"
  set +e
  bash "$BUILDER" "$REPO" '' "$UDID" >"$LOG_FILE" 2>&1
  RC=$?
  printf '%s\n' "$RC" >"$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
  exit "$RC"
fi

case "${1:-status}" in
  start)
    REPO="${2:?start requires repo path}"
    UDID="${3:?start requires simulator UDID}"
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo RUNNING
      exit 0
    fi
    rm -f "$STATUS_FILE" "$STATUS_FILE.tmp" "$LOG_FILE"
    printf '%s\n' 'RUNNING' >"$STATUS_FILE"
    nohup "$0" --worker "$REPO" "$UDID" </dev/null >/dev/null 2>&1 &
    printf '%s\n' "$!" >"$PID_FILE"
    echo STARTED
    ;;
  status)
    if [ -f "$STATUS_FILE" ]; then
      STATUS="$(cat "$STATUS_FILE")"
      if [ "$STATUS" = "RUNNING" ]; then
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
          echo RUNNING
        else
          printf '%s\n' '125' >"$STATUS_FILE.tmp"
          mv "$STATUS_FILE.tmp" "$STATUS_FILE"
          printf '%s\n' 'worker exited without publishing a build result' >>"$LOG_FILE"
          echo DONE:125
        fi
      else
        printf 'DONE:%s\n' "$STATUS"
      fi
    elif [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo RUNNING
    else
      echo IDLE
    fi
    ;;
  log)
    tail -40 "$LOG_FILE" 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 start <repo> <simulator-udid>|status|log" >&2
    exit 2
    ;;
esac
