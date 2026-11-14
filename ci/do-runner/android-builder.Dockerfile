# forge/android-builder:2 - sh-forge Android build lane image (SH-4524).
#
# Same base as forge/android-builder:1 (reactnativecommunity/react-native-android:
# JDK 17, SDK 37, NDK 28.2) plus what the Expo SDK 57 / React Native 0.86
# monorepos measure as required:
#   - Node 24 and pnpm 11 (ABACare engines: node >=24.20.0, pnpm >=11.15.0;
#     packageManager pins pnpm@11.15.0)
#   - compileSdk 36, build-tools 36.0.0, NDK 27.1.12297006
#     (react-native@0.86.3 gradle/libs.versions.toml). Without them every
#     ephemeral container re-downloads the NDK on each build.
#
# Build on forge (android-setup.sh does this):
#   docker build -t forge/android-builder:2 -f android-builder.Dockerfile .
# The :1 image is left untouched; nothing depends on this layering over it.
FROM reactnativecommunity/react-native-android:latest
RUN apt-get update && apt-get install -y --no-install-recommends rsync jq xz-utils && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://nodejs.org/dist/v24.22.3/node-v24.22.3-linux-x64.tar.xz -o /tmp/node.tar.xz \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /usr/local/lib/node_modules/corepack /usr/local/bin/corepack \
 && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components 1 \
 && rm /tmp/node.tar.xz \
 && npm install -g pnpm@11.15.0 \
 && node -v && npm -v && pnpm -v
# The rm -rf matters: extracting over the image's npm 10 leaves a merged tree that
# makes npm 11 exit 1 with no error message (measured 2026-11-14).
RUN yes | /opt/android/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null 2>&1 || true \
 && /opt/android/cmdline-tools/latest/bin/sdkmanager "platforms;android-36" "build-tools;36.0.0" "ndk;27.1.12297006"
WORKDIR /work
# Daemon off keeps a --rm container from leaking JVMs; heap sizing lives in the
# persistent GRADLE_USER_HOME gradle.properties that android-setup.sh writes,
# which overrides the generated project's 512 MB Metaspace cap.
ENV GRADLE_OPTS="-Dorg.gradle.daemon=false"
