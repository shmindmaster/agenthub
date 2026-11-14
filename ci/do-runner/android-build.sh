#!/usr/bin/env bash
# android-build: build an Expo/React Native Android app on sh-forge from a branch
# of a bare git repo on this host, inside the pinned forge/android-builder image.
# No EAS cloud, no emulator, nothing runs on the owner PC.
#
#   android-build <bare-repo> <branch> [--app <dir>] [--filter <pnpm-filter>]
#                 [--variant release|debug] [--image <ref>] [--env KEY=VALUE]...
#
#   --app      app directory inside the repo (default: repo root).
#   --filter   pnpm install filter (default: "<package name of --app>..." so the
#              workspace installs only the app and its dependencies).
#   --env      build env passed into the container; repeatable. Values for the
#              ABACare preview lane are recorded in docs/runbooks/do-interim-release.md.
#
# The working tree lives at /srv/work/android/<repo>-<branch>; node_modules and the
# generated android/ persist between runs, and the pnpm store and Gradle home are
# shared under /opt/forge/android. The APK is copied to /srv/work/android/artifacts/
# with its sha256, and the full build log lands beside it. Exit 0 = APK built.
#
# Canonical copy: AgentHub ci/do-runner/android-build.sh, installed at
# /usr/local/bin/android-build by android-setup.sh.
set -euo pipefail

repo=${1:?usage: android-build <bare-repo> <branch> [--app dir] [--filter f] [--variant release|debug] [--env K=V]...}
branch=${2:?usage: android-build <bare-repo> <branch> [--app dir] [--filter f] [--variant release|debug] [--env K=V]...}
shift 2
app="."
filter=""
variant=release
image="${ANDROID_BUILDER_IMAGE:-forge/android-builder:2}"
envs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --app)     app=${2:?--app needs a value}; shift 2;;
    --filter)  filter=${2:?--filter needs a value}; shift 2;;
    --variant) variant=${2:?--variant needs a value}; shift 2;;
    --image)   image=${2:?--image needs a value}; shift 2;;
    --env)     envs+=("${2:?--env needs a value}"); shift 2;;
    *) echo "android-build: unknown option $1" >&2; exit 2;;
  esac
done
case "$variant" in release|debug) ;; *) echo "android-build: --variant must be release or debug" >&2; exit 2;; esac
[ -d "$repo" ] || { echo "android-build: $repo is not a directory" >&2; exit 2; }
docker image inspect "$image" > /dev/null 2>&1 || { echo "android-build: image $image is missing (run android-setup.sh)" >&2; exit 2; }

name=$(basename "$repo"); name=${name%.git}
safe=${branch//[^A-Za-z0-9._-]/-}
work="/srv/work/android/$name-$safe"
artifacts=/srv/work/android/artifacts
cache=/opt/forge/android
mkdir -p "$artifacts" "$cache/gradle-home" "$cache/pnpm-store" /srv/work/android

# Pushed branches only: fetch the exact ref from the bare repo, never a working tree.
[ -d "$work/.git" ] || git clone -q "$repo" "$work"
git -C "$work" fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch"
git -C "$work" checkout -q -B "$safe" "origin/$branch"
git -C "$work" clean -qfd
sha=$(git -C "$work" rev-parse HEAD)
stem="$name-$safe-${sha:0:8}"
log="$artifacts/$stem.log"
app_norm=${app#./}; app_norm=${app_norm%/}

if [ -z "$filter" ]; then
  pkg=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$work/$app_norm/package.json")
  filter="$pkg..."
fi

main() {
  echo "== android-build repo=$repo branch=$branch sha=$sha app=$app_norm filter=$filter variant=$variant image=$image"
  local env_args=()
  for kv in ${envs[@]+"${envs[@]}"}; do env_args+=(-e "$kv"); done
  docker run --rm --init -i \
    -v "$work":/work -w /work \
    -v "$cache/gradle-home":/opt/gradle-home \
    -v "$cache/pnpm-store":/pnpm-store \
    -e APP_DIR="$app_norm" -e PKG_FILTER="$filter" -e VARIANT="$variant" \
    -e EXPO_NO_DOTENV=1 -e SENTRY_DISABLE_AUTO_UPLOAD=true -e CI=1 \
    ${env_args[@]+"${env_args[@]}"} \
    "$image" bash -euo pipefail -s <<'BUILD'
pnpm install --frozen-lockfile --store-dir /pnpm-store --filter "$PKG_FILTER"
cd "$APP_DIR"
# The app's own build-environment gate, when it ships one (ABACare apps/mobile does).
if [ -f scripts/build-environment.cjs ]; then
  node -e 'require("./scripts/build-environment.cjs").assertBuildEnvironment(process.env)'
fi
pnpm exec expo prebuild --platform android
cd android
if [ "$VARIANT" = debug ]; then
  ./gradlew assembleDebug --no-daemon
else
  ./gradlew assembleRelease --no-daemon
fi
BUILD
  local apk
  apk=$(find "$work/$app_norm/android" -type f -path "*/outputs/apk/$variant/*.apk" | sort | head -1)
  [ -n "$apk" ] && [ -s "$apk" ] || { echo "android-build: no $variant APK under $work/$app_norm/android" >&2; return 1; }
  local suffix=""; [ "$variant" = debug ] && suffix="-debug"
  local out="$artifacts/$stem$suffix.apk"
  cp -f "$apk" "$out"
  sha256sum "$out"
  ls -lh "$out"
  echo "== android-build ok: $out (log: $log)"
}

# pipefail keeps main's exit status through tee.
main 2>&1 | tee "$log"
