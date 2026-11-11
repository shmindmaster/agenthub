#!/usr/bin/env bash
# Reset what a previous job left behind, before this job's steps run.
# The runner has already created this job's workspace and event payload
# (_work/_temp/_github_workflow), so keep the current workspace directory itself,
# the runner's own _temp/_actions/_tool, and empty everything else.
set -u
ws=${GITHUB_WORKSPACE:?}
parent=$(basename "$(dirname "$ws")")
find /home/runner/_work -mindepth 1 -maxdepth 1 ! -name _actions ! -name _tool ! -name _temp ! -name "$parent" -exec rm -rf {} + 2>/dev/null || true
find "$(dirname "$ws")" -mindepth 1 -maxdepth 1 ! -path "$ws" -exec rm -rf {} + 2>/dev/null || true
find "$ws" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$ws"
find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
docker buildx rm sh-ci >/dev/null 2>&1 || true
echo "sh-ci: workspace reset for ${GITHUB_REPOSITORY:-?} run ${GITHUB_RUN_ID:-?}"
