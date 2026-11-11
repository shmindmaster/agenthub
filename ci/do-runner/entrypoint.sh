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
  rm -f /state/bootstrap-token
else
  cp /state/.runner /state/.credentials /state/.credentials_rsaparams .
fi
export ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/sh-ci/job-started.sh
exec ./run.sh
