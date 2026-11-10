#!/usr/bin/env bash
# Provision a Linux Android worker for the mobile device lab.
#
# Re-runnable: every step checks before it changes anything. Run as root on an
# x86_64 Ubuntu 22.04 or 24.04 host that exposes /dev/kvm. That is a
# DigitalOcean droplet today and an AWS nested-virtualization instance
# (C8i, M8i, R8i or a .metal size) later; nothing here is provider-specific.
#
# No Docker, no systemd unit and no cron entry: the emulator starts when
# `mobile-lab emulator start` or `mobile-lab run` asks for it and stops with
# `mobile-lab emulator stop`.
set -euo pipefail

LAB_USER="${LAB_USER:-mobilelab}"
LAB_ROOT="${LAB_ROOT:-/srv/mobile-lab}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
ANDROID_API="${ANDROID_API:-36}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"
AVD_NAME="${AVD_NAME:-lab-api${ANDROID_API}}"
AVD_DEVICE="${AVD_DEVICE:-pixel_7}"
CMDLINE_TOOLS_BUILD="${CMDLINE_TOOLS_BUILD:-13114758}"
NODE_MAJOR="${NODE_MAJOR:-24}"
MAESTRO_VERSION="${MAESTRO_VERSION:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis;x86_64"

log() { printf '[provision] %s\n' "$*"; }
die() { printf '[provision] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"
[ "$(uname -m)" = "x86_64" ] || die "x86_64 host required; found $(uname -m)"
[ -e /dev/kvm ] || die "/dev/kvm is missing. Pick a host that exposes KVM (on AWS: a nested-virtualization family or a .metal size)."

log "packages"
export DEBIAN_FRONTEND=noninteractive
need_pkgs=()
for pkg in openjdk-17-jdk-headless unzip curl git jq rsync xz-utils ca-certificates \
           libpulse0 libnss3 libgl1 libxkbcommon0 libxkbfile1 libx11-xcb1 libxcomposite1 \
           libxcursor1 libxi6 libxtst6 libxdamage1 libdbus-1-3 libdrm2 libgbm1; do
  dpkg -s "$pkg" >/dev/null 2>&1 || need_pkgs+=("$pkg")
done
if [ "${#need_pkgs[@]}" -gt 0 ]; then
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "${need_pkgs[@]}" >/dev/null
fi

log "user ${LAB_USER}"
getent group kvm >/dev/null || groupadd --system kvm
id "$LAB_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$LAB_USER"
usermod -aG kvm "$LAB_USER"
lab_home="$(getent passwd "$LAB_USER" | cut -d: -f6)"
install -d -m 700 -o "$LAB_USER" -g "$LAB_USER" "$lab_home/.ssh"
if [ -s /root/.ssh/authorized_keys ] && [ ! -s "$lab_home/.ssh/authorized_keys" ]; then
  install -m 600 -o "$LAB_USER" -g "$LAB_USER" /root/.ssh/authorized_keys "$lab_home/.ssh/authorized_keys"
fi
for dir in "$LAB_ROOT" "$LAB_ROOT/work" "$LAB_ROOT/artifacts" "$LAB_ROOT/cache" "$LAB_ROOT/state" "$LAB_ROOT/incoming"; do
  install -d -o "$LAB_USER" -g "$LAB_USER" "$dir"
done

log "node ${NODE_MAJOR}"
if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'process.versions.node.split(".")[0]')" != "$NODE_MAJOR" ]; then
  node_file="$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt" | awk '/linux-x64.tar.xz$/ {print $2}')"
  [ -n "$node_file" ] || die "could not resolve the latest Node ${NODE_MAJOR} tarball"
  curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/${node_file}" -o "/tmp/${node_file}"
  expected="$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt" | awk -v f="$node_file" '$2 == f {print $1}')"
  echo "${expected}  /tmp/${node_file}" | sha256sum -c - >/dev/null || die "Node tarball checksum mismatch"
  rm -rf /opt/node && mkdir -p /opt/node
  tar -xJf "/tmp/${node_file}" -C /opt/node --strip-components=1
  rm -f "/tmp/${node_file}"
  for bin in node npm npx corepack; do ln -sf "/opt/node/bin/${bin}" "/usr/local/bin/${bin}"; done
fi
# pnpm and yarn resolve from each repository's packageManager field.
corepack enable --install-directory /usr/local/bin >/dev/null 2>&1 || true

log "android sdk at ${ANDROID_SDK_ROOT}"
install -d -o "$LAB_USER" -g "$LAB_USER" "$ANDROID_SDK_ROOT"
if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" -o /tmp/cmdline-tools.zip
  rm -rf /tmp/cmdline-tools-extract && mkdir -p /tmp/cmdline-tools-extract
  unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract
  install -d "$ANDROID_SDK_ROOT/cmdline-tools"
  rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv /tmp/cmdline-tools-extract/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract
  chown -R "$LAB_USER:$LAB_USER" "$ANDROID_SDK_ROOT"
fi

cat > /etc/profile.d/mobile-lab.sh <<EOF
export ANDROID_HOME="${ANDROID_SDK_ROOT}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
export ANDROID_AVD_HOME="${LAB_ROOT}/state/avd"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
export GRADLE_USER_HOME="${LAB_ROOT}/cache/gradle"
export MOBILE_LAB_ROOT="${LAB_ROOT}"
export MOBILE_LAB_AVD="${AVD_NAME}"
export PATH="\$PATH:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/emulator:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${lab_home}/.maestro/bin"
EOF

as_lab() { sudo -H -u "$LAB_USER" bash -lc "cd && $*"; }

log "sdk packages (platform ${ANDROID_API}, emulator, system image)"
as_lab "yes | sdkmanager --licenses >/dev/null 2>&1 || true"
missing=()
[ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ] || missing+=("platform-tools")
[ -x "$ANDROID_SDK_ROOT/emulator/emulator" ] || missing+=("emulator")
[ -d "$ANDROID_SDK_ROOT/platforms/android-${ANDROID_API}" ] || missing+=("platforms;android-${ANDROID_API}")
[ -d "$ANDROID_SDK_ROOT/build-tools/${ANDROID_BUILD_TOOLS}" ] || missing+=("build-tools;${ANDROID_BUILD_TOOLS}")
[ -d "$ANDROID_SDK_ROOT/system-images/android-${ANDROID_API}/google_apis/x86_64" ] || missing+=("$SYSTEM_IMAGE")
if [ "${#missing[@]}" -gt 0 ]; then
  quoted=""; for item in "${missing[@]}"; do quoted+=" '${item}'"; done
  as_lab "sdkmanager --install ${quoted} >/dev/null"
fi

log "avd ${AVD_NAME}"
as_lab "mkdir -p '${LAB_ROOT}/state/avd'"
if [ ! -d "${LAB_ROOT}/state/avd/${AVD_NAME}.avd" ]; then
  as_lab "echo no | avdmanager create avd --name '${AVD_NAME}' --package '${SYSTEM_IMAGE}' --device '${AVD_DEVICE}' >/dev/null"
  cfg="${LAB_ROOT}/state/avd/${AVD_NAME}.avd/config.ini"
  {
    echo "hw.ramSize=4096"
    echo "hw.cpu.ncore=4"
    echo "hw.keyboard=yes"
    echo "disk.dataPartition.size=8G"
  } >> "$cfg"
fi

log "gradle defaults"
# The generated android/gradle.properties caps the JVM at 2 GB heap and 512 MB
# Metaspace, which a full Expo release build exceeds. The user-level file wins.
as_lab "mkdir -p '${LAB_ROOT}/cache/gradle'"
cat > "${LAB_ROOT}/cache/gradle/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx6g -XX:MaxMetaspaceSize=2g
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.daemon.idletimeout=600000
kotlin.daemon.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
EOF
chown "$LAB_USER:$LAB_USER" "${LAB_ROOT}/cache/gradle/gradle.properties"

log "maestro"
if [ ! -x "$lab_home/.maestro/bin/maestro" ]; then
  as_lab "export MAESTRO_VERSION='${MAESTRO_VERSION}'; curl -fsSL https://get.maestro.mobile.dev | bash >/dev/null 2>&1"
fi

log "worker command"
install -m 755 "$SCRIPT_DIR/mobile-lab.sh" /usr/local/bin/mobile-lab

log "verify"
as_lab "node --version && java -version 2>&1 | head -1 && adb version | head -1 && emulator -accel-check 2>&1 | tail -2 && maestro --version 2>/dev/null | tail -1 && emulator -list-avds"
log "done"
