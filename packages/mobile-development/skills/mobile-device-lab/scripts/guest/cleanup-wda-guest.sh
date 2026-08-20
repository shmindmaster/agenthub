#!/usr/bin/env bash
set -euo pipefail

udid="${1:-}"
if [[ ! "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "invalid Simulator UDID" >&2
  exit 2
fi

owned_pids=""
owned_count=0
while read -r pid ppid command; do
  [[ "$pid" =~ ^[0-9]+$ ]] || continue
  [[ "$ppid" =~ ^[0-9]+$ ]] || continue

  [[ "$command" == *xcodebuild* ]] || continue
  [[ "$command" == *WebDriverAgent.xcodeproj* ]] || continue
  [[ "$command" == *"destination id=$udid"* ]] || continue

  parent_command="$(ps -p "$ppid" -o command= 2>/dev/null || true)"
  [[ "$parent_command" == *"appium server"* ]] || continue
  owned_pids="${owned_pids}${owned_pids:+ }${pid}"
  owned_count=$((owned_count + 1))
done < <(ps -axo pid=,ppid=,command=)

for pid in $owned_pids; do
  kill -TERM "$pid" 2>/dev/null || true
done

for _ in {1..20}; do
  remaining=0
  for pid in $owned_pids; do
    if kill -0 "$pid" 2>/dev/null; then
      remaining=$((remaining + 1))
    fi
  done
  (( remaining == 0 )) && break
  sleep 0.5
done

stuck_pids=""
for pid in $owned_pids; do
  if kill -0 "$pid" 2>/dev/null; then
    stuck_pids="${stuck_pids}${stuck_pids:+ }${pid}"
  fi
done

if [[ -n "$stuck_pids" ]]; then
  printf 'WebDriverAgent runner did not stop after SIGTERM: %s\n' "$stuck_pids" >&2
  exit 1
fi

printf '{"ok":true,"terminated":%d,"pids":"%s"}\n' "$owned_count" "$owned_pids"
