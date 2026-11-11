#!/usr/bin/env bash
# Wipe everything a previous job left in the workspace (keep the action and tool caches).
set -u
find /home/runner/_work -mindepth 1 -maxdepth 1 ! -name _actions ! -name _tool ! -name _temp -exec rm -rf {} + 2>/dev/null || true
rm -rf /home/runner/_work/_temp/* /tmp/* 2>/dev/null || true
# Fresh BuildKit builder handle each job (the daemon is the repo's private sidecar).
docker buildx rm sh-ci >/dev/null 2>&1 || true
echo "sh-ci: workspace reset for ${GITHUB_REPOSITORY:-?} run ${GITHUB_RUN_ID:-?}"
