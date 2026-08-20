#!/usr/bin/env bash
set -euo pipefail

udid="${1:-}"
if [[ ! "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "invalid Simulator UDID" >&2
  exit 2
fi

declare -a owned_pids=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  pid="$(awk '{print $1}' <<<"$line")"
  ppid="$(awk '{print $2}' <<<"$line")"
  command="${line#*"$ppid"}"

  [[ "$command" == *xcodebuild* ]] || continue
  [[ "$command" == *WebDriverAgent.xcodeproj* ]] || continue
  [[ "$command" == *"destination id=$udid"* ]] || continue

  parent_command="$(ps -p "$ppid" -o command= 2>/dev/null || true)"
  [[ "$parent_command" == *"appium server"* ]] || continue
  owned_pids+=("$pid")
done < <(ps -axo pid=,ppid=,command=)

for pid in "${owned_pids[@]}"; do
  kill -TERM "$pid" 2>/dev/null || true
done

for _ in {1..20}; do
  remaining=0
  for pid in "${owned_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      remaining=$((remaining + 1))
    fi
  done
  (( remaining == 0 )) && break
  sleep 0.5
done

declare -a stuck_pids=()
for pid in "${owned_pids[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then
    stuck_pids+=("$pid")
  fi
done

if (( ${#stuck_pids[@]} > 0 )); then
  printf 'WebDriverAgent runner did not stop after SIGTERM: %s\n' "${stuck_pids[*]}" >&2
  exit 1
fi

printf '{"ok":true,"terminated":%d,"pids":"%s"}\n' "${#owned_pids[@]}" "${owned_pids[*]:-}"
