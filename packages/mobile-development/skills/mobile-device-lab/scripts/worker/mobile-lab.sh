#!/usr/bin/env bash
# Worker-side command for the remote Android lab. Installed to
# /usr/local/bin/mobile-lab by provision-android-worker.sh and called over SSH
# by Invoke-MobileLabRemote.ps1. It holds no app knowledge: every app arrives
# as a source archive plus a small JSON config on stdin.
set -euo pipefail
# shellcheck disable=SC1091
. /etc/profile.d/mobile-lab.sh
export CI=1 MAESTRO_CLI_NO_ANALYTICS=1 EXPO_NO_TELEMETRY=1

ROOT="$MOBILE_LAB_ROOT"
STATE="$ROOT/state"
SERIAL="emulator-5554"
LEASE="$STATE/lease.lock"
HOLDER="$STATE/lease.holder"

log() { printf '[mobile-lab] %s\n' "$*" >&2; }
die() { printf '[mobile-lab] ERROR: %s\n' "$*" >&2; exit 1; }
valid_app() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || die "invalid app id '$1'"; }

emulator_booted() {
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]
}

emulator_start() {
  if emulator_booted; then log "emulator already booted"; return 0; fi
  if ! pgrep -u "$(id -u)" -f "qemu-system.*${MOBILE_LAB_AVD}" >/dev/null; then
    log "starting ${MOBILE_LAB_AVD} headless"
    # 9>&- on every long-lived child: fd 9 is the run lease, and a child that
    # inherits it keeps the lab locked after the run ends.
    setsid nohup emulator -avd "$MOBILE_LAB_AVD" -no-window -no-audio -no-boot-anim \
      -no-snapshot -gpu swiftshader_indirect -no-metrics \
      > "$STATE/emulator.log" 2>&1 < /dev/null 9>&- &
  fi
  adb start-server >/dev/null 2>&1
  for _ in $(seq 1 120); do
    if emulator_booted; then
      for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
        adb -s "$SERIAL" shell settings put global "$scale" 0 >/dev/null 2>&1 || true
      done
      log "emulator booted"
      return 0
    fi
    sleep 3
  done
  tail -20 "$STATE/emulator.log" >&2 || true
  die "emulator did not boot in 6 minutes"
}

emulator_stop() {
  adb -s "$SERIAL" emu kill >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -u "$(id -u)" -f "qemu-system.*${MOBILE_LAB_AVD}" >/dev/null || break
    sleep 1
  done
  pkill -u "$(id -u)" -f "qemu-system.*${MOBILE_LAB_AVD}" 2>/dev/null || true
  log "emulator stopped"
}

# Metro runs as "node .../expo/bin/cli start --port 8081", so match on the port.
metro_stop() { pkill -u "$(id -u)" -f 'start --port 8081' 2>/dev/null || true; }

status() {
  local booted=false holder="" metro=false
  emulator_booted && booted=true
  if ! flock -n 9 9>>"$LEASE"; then holder="$(cat "$HOLDER" 2>/dev/null || echo unknown)"; fi
  curl -fsS -m 2 http://127.0.0.1:8081/status >/dev/null 2>&1 && metro=true
  jq -n --arg host "$(hostname)" --arg avd "$MOBILE_LAB_AVD" --argjson booted "$booted" \
        --arg holder "$holder" --argjson metro "$metro" \
        --arg kvm "$([ -w /dev/kvm ] && echo usable || echo unavailable)" \
        --arg load "$(cut -d' ' -f1-3 /proc/loadavg)" \
        --arg apps "$(ls "$ROOT/work" 2>/dev/null | tr '\n' ' ')" \
        '{host:$host, kvm:$kvm, avd:$avd, emulatorBooted:$booted, metroRunning:$metro, leaseHeldBy:$holder, load:$load, apps:($apps|split(" ")|map(select(length>0)))}'
}

# receive <app> <appPath>: a tar of the source tree on stdin. Build outputs,
# dependencies and the generated native project are kept between runs.
receive() {
  local app="$1" app_path="${2:-.}"
  valid_app "$app"
  shift; shift || true
  local keep=() extra
  for extra in "$@"; do
    [[ "$extra" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || die "invalid extra path '$extra'"
    keep+=(--exclude "/${extra}/")
  done
  local incoming="$ROOT/incoming/$app" work="$ROOT/work/$app"
  rm -rf "$incoming" && mkdir -p "$incoming" "$work"
  tar -xf - -C "$incoming"
  local prefix=""; [ "$app_path" != "." ] && prefix="/${app_path%/}"
  rsync -a --delete --exclude 'node_modules/' --exclude '.expo/' \
    --exclude "${prefix}/android/" --exclude "${prefix}/ios/" "${keep[@]}" "$incoming/" "$work/"
  rm -rf "$incoming"
  log "source received for $app"
}

# Gitignored inputs a bundle needs (recorded audio, generated data). Sent as a
# separate tar and only when the caller's stamp differs from the stored one.
extra_stamp() { valid_app "$1"; cat "$STATE/$1.extra" 2>/dev/null || true; }
receive_extra() {
  local app="$1" stamp="$2"
  valid_app "$app"
  [[ "$stamp" =~ ^[0-9a-f]{16,64}$ ]] || die "invalid stamp"
  mkdir -p "$ROOT/work/$app"
  tar -xf - -C "$ROOT/work/$app"
  echo "$stamp" > "$STATE/$app.extra"
  log "extra paths received for $app"
}

# run <app>: JSON config on stdin.
run() {
  local app="$1"; valid_app "$app"
  local cfg; cfg="$(cat)"
  local app_path variant package flow install pre screenshot run_id out work
  app_path="$(jq -r '.appPath // "."' <<<"$cfg")"
  variant="$(jq -r '.variant // "release"' <<<"$cfg")"
  package="$(jq -r '.androidPackage' <<<"$cfg")"
  flow="$(jq -r '.flow // ""' <<<"$cfg")"
  install="$(jq -r '.install // "npm ci"' <<<"$cfg")"
  pre="$(jq -r '.preCommand // ""' <<<"$cfg")"
  screenshot="$(jq -r '.screenshot // false' <<<"$cfg")"
  run_id="$(jq -r '.runId' <<<"$cfg")"
  [[ "$variant" =~ ^(release|debug)$ ]] || die "variant must be release or debug"
  [[ "$run_id" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid run id"
  work="$ROOT/work/$app"
  [ -d "$work/$app_path" ] || die "no source for $app; send it first"
  out="$ROOT/artifacts/$app/$run_id"
  mkdir -p "$out"

  exec 9>>"$LEASE"
  if ! flock -w "$(jq -r '.leaseWaitSeconds // 0' <<<"$cfg")" 9; then
    die "the lab is in use by: $(cat "$HOLDER" 2>/dev/null || echo unknown). Wait for that run; never stop another run."
  fi
  echo "$app $run_id $(jq -r '.requestedBy // "unknown"' <<<"$cfg") $(date -u +%FT%TZ)" > "$HOLDER"
  # Not local: the EXIT trap runs after this function's scope is gone.
  PRE_PID=""
  local verdict="error" started; started="$(date +%s)"
  cleanup() {
    if [ -n "${PRE_PID:-}" ]; then pkill -P "$PRE_PID" 2>/dev/null || true; kill "$PRE_PID" 2>/dev/null || true; fi
    rm -f "$HOLDER"
  }
  trap cleanup EXIT

  # App-declared build and runtime variables.
  while IFS=$'\t' read -r key value; do
    [ -n "$key" ] && export "$key=$value"
  done < <(jq -r '.env // {} | to_entries[] | [.key, (.value|tostring)] | @tsv' <<<"$cfg")

  emulator_start

  log "install: $install"
  (cd "$work" && bash -lc "$install") > "$out/install.log" 2>&1 || { tail -30 "$out/install.log" >&2; die "dependency install failed"; }

  cd "$work/$app_path"
  # A stale android/ silently omits native modules added since it was generated,
  # so regenerate it whenever the inputs that decide its contents change.
  local fingerprint
  fingerprint="$( { cat package.json app.json app.config.* 2>/dev/null || true; cat "$work"/pnpm-lock.yaml "$work"/package-lock.json "$work"/yarn.lock 2>/dev/null || true; env | grep -E '^(EXPO_PUBLIC_|PREVIEW_MOCK)' | sort || true; } | sha256sum | cut -d' ' -f1)"
  if [ ! -x android/gradlew ] || [ "$(cat "$STATE/$app.prebuild" 2>/dev/null)" != "$fingerprint" ]; then
    log "expo prebuild (clean)"
    npx expo prebuild --platform android --clean --no-install > "$out/prebuild.log" 2>&1 || { tail -30 "$out/prebuild.log" >&2; die "expo prebuild failed"; }
    echo "$fingerprint" > "$STATE/$app.prebuild"
  fi

  log "gradle assemble ${variant}"
  local task="assemble${variant^}"
  (cd android && ./gradlew ":app:${task}" -PreactNativeArchitectures=x86_64 --console=plain \
      $(jq -r '.gradleArgs // [] | join(" ")' <<<"$cfg")) > "$out/build.log" 2>&1 \
    || { tail -40 "$out/build.log" >&2; die "gradle build failed; see build.log"; }
  local apk; apk="$(find "android/app/build/outputs/apk/$variant" -name '*.apk' | head -1)"
  [ -n "$apk" ] || die "no APK produced"
  cp "$apk" "$out/app-$variant.apk"

  log "install on emulator"
  adb -s "$SERIAL" install -r "$apk" > "$out/adb-install.log" 2>&1 || { cat "$out/adb-install.log" >&2; die "adb install failed"; }

  if [ "$variant" = "debug" ]; then
    metro_stop
    log "starting Metro on 8081"
    # CI must be unset, not empty: with CI=1 Metro does not watch files, and
    # Expo rejects an empty value.
    env -u CI setsid nohup npx expo start --port 8081 > "$STATE/metro-$app.log" 2>&1 < /dev/null 9>&- &
    local metro_up=false
    for _ in $(seq 1 60); do
      if curl -fsS -m 2 http://127.0.0.1:8081/status >/dev/null 2>&1; then metro_up=true; break; fi
      sleep 2
    done
    if [ "$metro_up" != true ]; then tail -15 "$STATE/metro-$app.log" >&2; die "Metro did not start"; fi
    adb -s "$SERIAL" reverse tcp:8081 tcp:8081 >/dev/null
  fi

  if [ -n "$pre" ]; then
    log "pre-command: $pre"
    bash -lc "$pre" > "$out/pre-command.log" 2>&1 9>&- &
    PRE_PID=$!
    sleep 3
  fi

  adb -s "$SERIAL" logcat -c || true
  local flow_exit=0
  if [ -n "$flow" ]; then
    log "maestro: $flow"
    maestro test --device "$SERIAL" --format junit --output "$out/maestro-junit.xml" \
      --debug-output "$out/maestro" --flatten-debug-output "$flow" > "$out/maestro.log" 2>&1 || flow_exit=$?
    tail -25 "$out/maestro.log" >&2
  else
    adb -s "$SERIAL" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 8
  fi
  [ "$flow_exit" -eq 0 ] && verdict="pass" || verdict="fail"

  if [ "$screenshot" = "true" ]; then
    # Bring the app back to the front: a flow may end with stopApp.
    adb -s "$SERIAL" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    sleep 4
    adb -s "$SERIAL" exec-out screencap -p > "$out/screen.png" || true
  else
    # Capture is off for this app: drop anything Maestro saved on failure.
    find "$out/maestro" -name '*.png' -delete 2>/dev/null || true
  fi
  adb -s "$SERIAL" logcat -d -t 4000 > "$out/logcat.txt" 2>/dev/null || true

  jq -n --arg app "$app" --arg runId "$run_id" --arg verdict "$verdict" --arg variant "$variant" \
        --arg package "$package" --arg flow "$flow" --arg device "$SERIAL ($MOBILE_LAB_AVD)" \
        --arg host "$(hostname)" --arg artifacts "$out" --argjson seconds "$(( $(date +%s) - started ))" \
        --argjson screenshot "$([ -s "$out/screen.png" ] && echo true || echo false)" \
        --arg source "$(jq -r '.sourceRef // ""' <<<"$cfg")" \
        '{app:$app, runId:$runId, verdict:$verdict, variant:$variant, androidPackage:$package, flow:$flow, device:$device, worker:$host, sourceRef:$source, seconds:$seconds, screenshot:$screenshot, artifacts:$artifacts, verifiedOn:"emulator"}' \
    | tee "$out/result.json"
  [ "$verdict" = "pass" ]
}

case "${1:-}" in
  status) status ;;
  emulator)
    case "${2:-}" in
      start) emulator_start ;;
      stop) metro_stop; emulator_stop ;;
      *) die "usage: mobile-lab emulator start|stop" ;;
    esac ;;
  receive) shift; receive "$@" ;;
  extra-stamp) extra_stamp "${2:-}" ;;
  receive-extra) shift; receive_extra "$@" ;;
  run) shift; run "$@" ;;
  clean)
    valid_app "${2:-}"
    rm -rf "$ROOT/work/$2" "$ROOT/artifacts/$2" "$STATE/$2.prebuild" "$STATE/$2.extra" "$STATE/metro-$2.log"
    log "removed source, build output and artifacts for $2" ;;
  *) die "usage: mobile-lab status | emulator start|stop | receive <app> <appPath> | run <app> | clean <app>" ;;
esac
