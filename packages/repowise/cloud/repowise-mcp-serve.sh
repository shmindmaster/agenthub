#!/usr/bin/env bash
# repowise-mcp-serve.sh -- start the RepoWise workspace MCP server on the
# remote index host, loopback only. Run by repowise-mcp.service; also safe to
# run by hand. See docs/runbooks/repowise-cloud.md.
#
# It execs the package's shared_server.py, the same entry point the Windows
# fleet uses: a streamable-HTTP MCP surface bound to 127.0.0.1 that fails
# closed when the Azure embedding probe fails (FOUNDRY_OPENAI_BASE_URL,
# FOUNDRY_API_KEY or AZURE_AI_SERVICES_KEY, FOUNDRY_EMBEDDING_DEPLOYMENT --
# names only; values live in the unit's EnvironmentFile, never here).
# --idle-minutes 0 keeps it resident under the service manager.
#
# There is no public listener anywhere in this recipe. Workstations reach the
# server through an SSH tunnel to 127.0.0.1 on this host only.

set -euo pipefail

WORKSPACE="${REPOWISE_CLOUD_INDEX_ROOT:-$HOME/.local/share/repowise-cloud/index}"
PORT="${REPOWISE_CLOUD_PORT:-7339}"
PYTHON="${REPOWISE_CLOUD_PYTHON:-python3}"

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --python) PYTHON="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SERVER="$SCRIPT_DIR/../scripts/shared_server.py"

[ -f "$SHARED_SERVER" ] || { echo "shared_server.py not found at $SHARED_SERVER (deploy the repowise package layout intact)" >&2; exit 2; }
[ -f "$WORKSPACE/.repowise-workspace.yaml" ] || { echo "no RepoWise workspace at $WORKSPACE; run Invoke-RepoWiseCloudIndex.sh first" >&2; exit 2; }
command -v "$PYTHON" >/dev/null 2>&1 || { echo "missing interpreter: $PYTHON" >&2; exit 2; }

exec "$PYTHON" "$SHARED_SERVER" "$WORKSPACE" --port "$PORT" --idle-minutes 0
