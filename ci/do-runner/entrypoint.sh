#!/usr/bin/env bash
# sh-ci runner entrypoint. Persistent (non-ephemeral) registration: the runner's own
# credential lives in /state (root-owned volume, 0700, uid 1001). The one-hour bootstrap
# token is read once from /state/bootstrap-token and deleted. No other secret exists here.
set -euo pipefail
cd /home/runner
if [ ! -f /state/.runner ]; then
  test -s /state/bootstrap-token || { echo "sh-ci: no registration and no bootstrap token"; sleep 300; exit 1; }
  ./config.sh --unattended --replace --disableupdate \
    --url "https://github.com/${SH_CI_REPO}" --token "$(cat /state/bootstrap-token)" \
    --name "${SH_CI_RUNNER_NAME}" --labels "${SH_CI_LABELS}" --work /home/runner/_work
  cp .runner .credentials .credentials_rsaparams /state/
else
  cp /state/.runner /state/.credentials /state/.credentials_rsaparams .
fi
# A token passed to an already registered runner is unused; never leave one behind.
rm -f /state/bootstrap-token

# Docker can restart these containers in any order. Wait for each configured sidecar
# before the listener connects and starts accepting jobs.
wait_for_sidecar() {
  local host=$1 port=$2
  if ! timeout 45 bash -c 'until (: > "/dev/tcp/$1/$2") 2>/dev/null; do sleep 1; done' _ "$host" "$port"; then
    echo "sh-ci: $host did not listen on port $port within 45 seconds" >&2
    return 1
  fi
}
if [ -n "${TEST_POSTGRES_URL:-}" ]; then wait_for_sidecar postgres 5432; fi
if [ -n "${TEST_REDIS_URL:-}" ]; then wait_for_sidecar valkey 6379; fi
if [ -n "${TEST_REDIS_URL_B:-}" ]; then wait_for_sidecar valkey-b 6379; fi
if [ -n "${BUILDKIT_HOST:-}" ]; then wait_for_sidecar buildkitd 1234; fi

export ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/sh-ci/job-started.sh
exec ./run.sh
