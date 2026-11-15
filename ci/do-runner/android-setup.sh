#!/usr/bin/env bash
# Host side of the sh-forge Android build lane (SH-4524): builder image, lane
# script, and the shared Gradle/pnpm caches. Run as root on forge from a folder
# holding this file, android-build.sh and android-builder.Dockerfile:
#   ssh forge 'mkdir -p /tmp/android-lane' && scp android-* forge:/tmp/android-lane/ \
#     && ssh forge 'cd /tmp/android-lane && sed -i "s/\r$//" * && bash android-setup.sh'
# Idempotent. Leaves forge/android-builder:1 untouched; builds :2 beside it.
# Canonical copies: AgentHub ci/do-runner/.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

install -d /opt/forge/android /srv/work/android/artifacts /opt/forge/android/gradle-home /opt/forge/android/pnpm-store
install -m 644 "$here/android-builder.Dockerfile" /opt/forge/android/android-builder.Dockerfile
docker build -q -t forge/android-builder:2 -f /opt/forge/android/android-builder.Dockerfile /opt/forge/android
install -m 755 "$here/android-build.sh" /usr/local/bin/android-build

# GRADLE_USER_HOME properties override the generated project's gradle.properties:
# a cold release build OOMs on the Expo template's 512 MB Metaspace cap
# (measured 2026-11-10 on the mobile-lab worker; see references/remote-android.md).
cat > /opt/forge/android/gradle-home/gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx12g -XX:MaxMetaspaceSize=2g
kotlin.daemon.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
org.gradle.workers.max=12
EOF

docker run --rm forge/android-builder:2 bash -c 'node -v && pnpm -v && ls /opt/android/platforms /opt/android/ndk'
echo "android-setup: ok. Lane: android-build /srv/<repo>.git <branch> --app <dir> [--env K=V]..."
