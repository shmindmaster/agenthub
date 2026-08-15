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
  set +e
  bash "$BUILDER" "$REPO" >"$LOG_FILE" 2>&1
  RC=$?
  printf '%s\n' "$RC" >"$STATUS_FILE"
  exit "$RC"
fi

case "${1:-status}" in
  start)
    REPO="${2:?start requires repo path}"
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo RUNNING
      exit 0
    fi
    rm -f "$STATUS_FILE" "$LOG_FILE"
    nohup "$0" --worker "$REPO" </dev/null >/dev/null 2>&1 &
    printf '%s\n' "$!" >"$PID_FILE"
    echo STARTED
    ;;
  status)
    if [ -f "$STATUS_FILE" ]; then
      printf 'DONE:%s\n' "$(cat "$STATUS_FILE")"
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
    echo "usage: $0 start <repo>|status|log" >&2
    exit 2
    ;;
esac
