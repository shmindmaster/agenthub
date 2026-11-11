#!/usr/bin/env bash
# Sync-RepoWiseMirrors.sh -- create or update bare, read-only git mirrors on the
# remote index host. Part of the AgentHub RepoWise cloud recipe (SH-4410);
# see docs/runbooks/repowise-cloud.md before deploying.
#
# What this does, per repository in the mirror list:
#   * first run  : git clone --mirror into <mirror-root>/<alias>.git
#   * later runs : git remote update --prune inside that bare mirror
#   * records the fetched default-branch commit in <state-dir>/<alias>.rev
#
# Guarantees:
#   * never fetches into a working tree a human edits (bare mirrors only)
#   * no credentials in this script: the deploy credential is named by an
#     environment variable (defaultCredentialEnv / credentialEnv), whose value
#     is a path to a read-only SSH deploy-key file
#   * never prompts: GIT_TERMINAL_PROMPT=0, ssh BatchMode
#   * idempotent: safe to re-run; a concurrency lock serializes invocations
#   * exits non-zero when any repository failed, and says which
#
# Requires: bash 4+, git, jq, flock. Nothing is scheduled by this script.
# Functions live above the entry guard so tests can source this file without
# side effects.

CONFIG="${REPOWISE_CLOUD_CONFIG:-$HOME/.config/repowise-cloud/mirrors.json}"
MIRROR_ROOT="${REPOWISE_CLOUD_MIRROR_ROOT:-$HOME/.local/share/repowise-cloud/mirrors}"
STATE_DIR="${REPOWISE_CLOUD_STATE_DIR:-$HOME/.local/share/repowise-cloud/state}"
DEFAULT_CRED_ENV=""

usage() {
    cat >&2 <<'EOF'
Usage: Sync-RepoWiseMirrors.sh [--config PATH] [--mirror-root DIR] [--state-dir DIR]

Synchronizes bare read-only mirrors for every repository in the mirror list.
Each repository's SSH deploy credential is referenced by the NAME of an
environment variable (credentialEnv, else defaultCredentialEnv) whose value is
the path to the private-key file. The credential itself never appears here.
EOF
}

# git_ssh_command <repo-json> : echo the GIT_SSH_COMMAND for one repository.
# The credential is referenced by NAME only: the environment variable it names
# must hold the path to a readable SSH private-key file (a read-only deploy
# key). An unset variable or unreadable file is a hard error for that repo.
git_ssh_command() {
    local repo="$1" cred_env key_path
    cred_env="$(jq -r '.credentialEnv // empty' <<<"$repo")"
    [ -n "$cred_env" ] || cred_env="$DEFAULT_CRED_ENV"
    [ -n "$cred_env" ] || { echo "no credentialEnv and no defaultCredentialEnv" >&2; return 1; }
    key_path="${!cred_env:-}"
    [ -n "$key_path" ] || { echo "credential env $cred_env is not set" >&2; return 1; }
    [ -r "$key_path" ] || { echo "credential file from $cred_env is not readable: $key_path" >&2; return 1; }
    printf 'ssh -i %q -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new' "$key_path"
}

sync_one() {
    local repo="$1" alias url branch dir ssh_cmd rev tmp
    alias="$(jq -r '.alias' <<<"$repo")"
    url="$(jq -r '.url' <<<"$repo")"
    branch="$(jq -r '.defaultBranch' <<<"$repo")"
    [[ "$alias" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "$alias: invalid alias" >&2; return 1; }
    dir="$MIRROR_ROOT/$alias.git"
    ssh_cmd="$(git_ssh_command "$repo")" || return 1

    if [ ! -d "$dir" ]; then
        GIT_SSH_COMMAND="$ssh_cmd" git clone --mirror "$url" "$dir" || return 1
    else
        [ -d "$dir/objects" ] || { echo "$dir exists but is not a bare mirror" >&2; return 1; }
        # The mirror's stored URL is refreshed each run so a list change takes
        # effect without a reclone; the fetch itself is read-only.
        git -C "$dir" remote set-url origin "$url" || return 1
        GIT_SSH_COMMAND="$ssh_cmd" git -C "$dir" remote update --prune || return 1
    fi

    rev="$(git -C "$dir" rev-parse --verify "refs/heads/$branch^{commit}")" \
        || { echo "$alias: default branch $branch not found after fetch" >&2; return 1; }
    tmp="$STATE_DIR/.$alias.rev.tmp"
    printf '%s\n' "$rev" >"$tmp" && mv "$tmp" "$STATE_DIR/$alias.rev"
    echo "synced $alias -> ${rev:0:12}"
}

main() {
    local failed=0 total=0
    while IFS= read -r repo; do
        total=$((total + 1))
        if ! sync_one "$repo"; then
            failed=$((failed + 1))
            echo "FAILED: $(jq -r '.alias' <<<"$repo")" >&2
        fi
    done < <(jq -c '.repositories[]' "$CONFIG")
    echo "mirrors: $((total - failed))/$total synced" >&2
    [ "$failed" -eq 0 ] || { echo "sync incomplete: $failed repository failure(s)" >&2; exit 1; }
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    set -euo pipefail
    while [ $# -gt 0 ]; do
        case "$1" in
            --config) CONFIG="$2"; shift 2 ;;
            --mirror-root) MIRROR_ROOT="$2"; shift 2 ;;
            --state-dir) STATE_DIR="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
        esac
    done
    for tool in git jq flock; do
        command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 2; }
    done
    [ -f "$CONFIG" ] || { echo "mirror list not found: $CONFIG" >&2; exit 2; }
    jq -e '.repositories | type == "array" and length > 0' "$CONFIG" >/dev/null \
        || { echo "mirror list has no repositories: $CONFIG" >&2; exit 2; }
    mkdir -p "$MIRROR_ROOT" "$STATE_DIR"
    export GIT_TERMINAL_PROMPT=0
    # Serialize concurrent invocations; a second run fails fast instead of racing.
    exec 9>"$STATE_DIR/.sync.lock"
    flock -n 9 || { echo "another sync holds $STATE_DIR/.sync.lock" >&2; exit 4; }
    DEFAULT_CRED_ENV="$(jq -r '.defaultCredentialEnv // empty' "$CONFIG")"
    main
fi
