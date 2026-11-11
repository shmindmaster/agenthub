#!/usr/bin/env bash
# Invoke-RepoWiseCloudIndex.sh -- incremental, revision-aware RepoWise index
# refresh over the bare mirrors kept by Sync-RepoWiseMirrors.sh. Part of the
# AgentHub RepoWise cloud recipe (SH-4410); see docs/runbooks/repowise-cloud.md.
#
# Per repository:
#   1. read the mirror's fetched default-branch commit (<state-dir>/<alias>.rev)
#   2. skip when the recorded indexed revision already matches (should_index)
#   3. materialize a MACHINE-OWNED checkout under <index-root>/<alias> -- the
#      only working trees this host keeps; no human edits them, and every run
#      hard-resets them to the mirrored commit
#   4. first index : repowise workspace add --no-docs --no-save-key
#      later runs  : repowise update --no-workspace --index-only --concurrency 1
#      (+ --defer-docs when REPOWISE_FACTS_ONLY=1, for an embedder outage)
#   5. write <status-dir>/<alias>.json {repository, revision, startedUtc,
#      finishedUtc, result, detail}
#
# Caps (HARD, per repository): memory via a systemd-run cgroup scope
# (MemoryMax), wall time via `timeout -k`. resolve_cap_mode picks
# systemd-user > systemd-system > rlimit (ulimit -v address-space cap -- a
# weaker bound than cgroup RSS, noted as a fallback only). With no mechanism
# available the run refuses rather than indexing uncapped.
#
# This script installs NO schedule. How an owner would schedule it is a
# runbook topic; until the owner chooses a cadence no timer exists.
#
# Requires: bash 4+, git, jq, flock, timeout, repowise on PATH; systemd-run
# for the preferred memory cap. Functions live above the entry guard so tests
# can source this file without side effects.

CONFIG="${REPOWISE_CLOUD_CONFIG:-$HOME/.config/repowise-cloud/mirrors.json}"
MIRROR_ROOT="${REPOWISE_CLOUD_MIRROR_ROOT:-$HOME/.local/share/repowise-cloud/mirrors}"
INDEX_ROOT="${REPOWISE_CLOUD_INDEX_ROOT:-$HOME/.local/share/repowise-cloud/index}"
STATE_DIR="${REPOWISE_CLOUD_STATE_DIR:-$HOME/.local/share/repowise-cloud/state}"
STATUS_DIR="${REPOWISE_CLOUD_STATUS_DIR:-$HOME/.local/share/repowise-cloud/status}"
MEM_MB="${REPOWISE_INDEX_MEM_MB:-4096}"
TIMEOUT_S="${REPOWISE_INDEX_TIMEOUT_S:-1800}"
FACTS_ONLY="${REPOWISE_FACTS_ONLY:-0}"
ONLY=()

usage() {
    cat >&2 <<'EOF'
Usage: Invoke-RepoWiseCloudIndex.sh [--config PATH] [--only ALIAS ...]
       [--mirror-root DIR] [--index-root DIR] [--state-dir DIR] [--status-dir DIR]

Refreshes the RepoWise index for every mirrored repository whose fetched
revision moved since the last recorded index run. Hard memory/time caps apply
per repository. Installs no schedule.
EOF
}

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- pure decision helpers (unit-tested by tests/Test-RepoWiseCloud.ps1) ---

indexed_revision() {
    # The revision of the last SUCCESSFUL index, or empty. A failed run never
    # advances this, so a failed refresh is retried next run.
    local status_file="$1"
    [ -f "$status_file" ] || return 0
    jq -r 'select(.result == "indexed" or .result == "unchanged") | .revision // empty' \
        "$status_file" 2>/dev/null || true
}

should_index() {
    # should_index <alias> <mirror-rev> <status-file>: 0 = index, 1 = skip.
    local alias="$1" rev="$2" status_file="$3" indexed
    [ -n "$rev" ] || { echo "$alias: empty mirror revision" >&2; return 0; }
    indexed="$(indexed_revision "$status_file")"
    [ "$indexed" = "$rev" ] && return 1
    return 0
}

# resolve_cap_mode: echoes systemd-user | systemd-system | rlimit | none.
resolve_cap_mode() {
    if command -v systemd-run >/dev/null 2>&1; then
        if [ "$(id -u)" -eq 0 ]; then echo systemd-system; return; fi
        if systemctl --user show-environment >/dev/null 2>&1; then echo systemd-user; return; fi
        echo rlimit; return
    fi
    echo none
}

# run_capped <mode> <unit-name> <cmd...>: run cmd inside the hard caps.
run_capped() {
    local mode="$1" unit="$2"; shift 2
    case "$mode" in
        systemd-user)
            systemd-run --user --scope -q --unit "$unit" \
                -p "MemoryMax=${MEM_MB}M" -p MemorySwapMax=0 \
                -- timeout -k 30 "${TIMEOUT_S}s" "$@" ;;
        systemd-system)
            systemd-run --scope -q --unit "$unit" \
                -p "MemoryMax=${MEM_MB}M" -p MemorySwapMax=0 \
                -- timeout -k 30 "${TIMEOUT_S}s" "$@" ;;
        rlimit)
            echo "WARN: no systemd scope; using ulimit -v address-space cap (weaker than cgroup RSS)" >&2
            ( ulimit -v $((MEM_MB * 1024)); exec timeout -k 30 "${TIMEOUT_S}s" "$@" ) ;;
        *)
            echo "no hard memory cap mechanism available; refusing to index uncapped" >&2
            return 2 ;;
    esac
}

materialize_checkout() {
    # The only working trees on this host are machine-owned and disposable:
    # every visit hard-resets them to the mirrored commit. Humans never edit here.
    local mirror="$1" checkout="$2" rev="$3"
    if [ ! -d "$checkout/.git" ]; then
        git clone -q "file://$mirror" "$checkout" || return 1
    fi
    git -C "$checkout" fetch -q --prune origin || return 1
    git -C "$checkout" reset --hard -q "$rev" || return 1
    git -C "$checkout" clean -fdq || return 1
}

last_sync_commit() {
    local state="$1/.repowise/state.json"
    [ -f "$state" ] || return 0
    jq -r '.last_sync_commit // empty' "$state" 2>/dev/null || true
}

write_status() {
    # write_status <file> <alias> <indexed-rev> <started> <result> <detail>
    local file="$1" tmp="${1}.tmp"
    shift
    jq -n --arg repository "$1" --arg revision "$2" --arg startedUtc "$3" \
          --arg finishedUtc "$(utc_now)" --arg result "$4" --arg detail "$5" \
          '{repository:$repository, revision:$revision, startedUtc:$startedUtc,
            finishedUtc:$finishedUtc, result:$result, detail:$detail}' \
          >"$tmp" && mv "$tmp" "$file"
}

index_one() {
    local alias="$1" mirror rev branch status_file checkout started outcome detail prev_rev mode code synced
    mirror="$MIRROR_ROOT/$alias.git"
    status_file="$STATUS_DIR/$alias.json"
    checkout="$INDEX_ROOT/$alias"
    prev_rev="$(indexed_revision "$status_file")"

    if [ ! -d "$mirror" ]; then
        write_status "$status_file" "$alias" "$prev_rev" "$(utc_now)" failed "no mirror at $mirror"
        return 1
    fi
    branch="$(jq -r --arg a "$alias" '.repositories[] | select(.alias == $a) | .defaultBranch' "$CONFIG")"
    rev="$(cat "$STATE_DIR/$alias.rev" 2>/dev/null || true)"
    [ -n "$rev" ] || rev="$(git -C "$mirror" rev-parse --verify "refs/heads/$branch^{commit}" 2>/dev/null || true)"
    if [ -z "$rev" ]; then
        write_status "$status_file" "$alias" "$prev_rev" "$(utc_now)" failed "no fetched revision for $branch"
        return 1
    fi
    if ! should_index "$alias" "$rev" "$status_file"; then
        write_status "$status_file" "$alias" "$rev" "$(utc_now)" unchanged "mirror already indexed"
        echo "unchanged $alias (${rev:0:12})"
        return 0
    fi

    started="$(utc_now)"
    if ! materialize_checkout "$mirror" "$checkout" "$rev"; then
        write_status "$status_file" "$alias" "$prev_rev" "$started" failed "checkout materialization failed"
        return 1
    fi

    mode="$(resolve_cap_mode)"
    if [ -f "$checkout/.repowise/state.json" ]; then
        set -- repowise update --no-workspace --index-only --concurrency 1
        [ "$FACTS_ONLY" = "1" ] && set -- "$@" --defer-docs
    else
        set -- repowise workspace add "$checkout" --alias "$alias" --no-docs --no-save-key
    fi

    code=0
    ( cd "$INDEX_ROOT" && run_capped "$mode" "repowise-index-$alias" "$@" ) || code=$?
    case "$code" in
        0)   outcome=indexed; detail="ok (cap=$mode)" ;;
        124|137) outcome=failed; detail="timeout after ${TIMEOUT_S}s (cap=$mode)" ;;
        *)   outcome=failed; detail="repowise exited $code (cap=$mode)" ;;
    esac
    if [ "$outcome" = indexed ]; then
        synced="$(last_sync_commit "$checkout")"
        if [ "$synced" != "$rev" ]; then
            outcome=failed
            detail="index ran but last_sync_commit=$synced != $rev"
        fi
    fi
    if [ "$outcome" = indexed ]; then
        write_status "$status_file" "$alias" "$rev" "$started" indexed "$detail"
        echo "indexed $alias -> ${rev:0:12} (cap=$mode)"
        return 0
    fi
    write_status "$status_file" "$alias" "$prev_rev" "$started" failed "$detail"
    echo "FAILED $alias: $detail" >&2
    return 1
}

main() {
    local aliases failed=0 total=0
    if [ "${#ONLY[@]}" -gt 0 ]; then
        aliases="$(printf '%s\n' "${ONLY[@]}")"
    else
        aliases="$(jq -r '.repositories[].alias' "$CONFIG")"
    fi
    while IFS= read -r alias; do
        [ -n "$alias" ] || continue
        total=$((total + 1))
        index_one "$alias" || failed=$((failed + 1))
    done <<<"$aliases"
    echo "index: $((total - failed))/$total repositories ok" >&2
    [ "$failed" -eq 0 ] || { echo "index incomplete: $failed failure(s)" >&2; exit 1; }
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    set -euo pipefail
    while [ $# -gt 0 ]; do
        case "$1" in
            --config) CONFIG="$2"; shift 2 ;;
            --mirror-root) MIRROR_ROOT="$2"; shift 2 ;;
            --index-root) INDEX_ROOT="$2"; shift 2 ;;
            --state-dir) STATE_DIR="$2"; shift 2 ;;
            --status-dir) STATUS_DIR="$2"; shift 2 ;;
            --only) shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do ONLY+=("$1"); shift; done ;;
            -h|--help) usage; exit 0 ;;
            *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
        esac
    done
    for tool in git jq flock timeout repowise; do
        command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 2; }
    done
    [ -f "$CONFIG" ] || { echo "mirror list not found: $CONFIG" >&2; exit 2; }
    mkdir -p "$INDEX_ROOT" "$STATE_DIR" "$STATUS_DIR"
    # Serialize concurrent invocations; a second run fails fast instead of racing.
    exec 9>"$STATE_DIR/.index.lock"
    flock -n 9 || { echo "another index run holds $STATE_DIR/.index.lock" >&2; exit 4; }
    main
fi
