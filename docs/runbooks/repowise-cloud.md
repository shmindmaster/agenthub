# Runbook: RepoWise on a remote read-only mirror host (SH-4410)

Run RepoWise indexing and MCP serving on a remote Linux host over read-only
git mirrors, so coding agents get graph/context over MCP without indexing on
the Windows workstation. **This runbook ships as a recipe plus tooling — nothing
has been deployed.** See [What was NOT done](#what-was-not-done).

Everything lives under `packages/repowise/cloud/`:

| File | Runs where | Purpose |
| --- | --- | --- |
| `mirrors.example.json`, `mirrors.schema.json` | index host (operator) | which repositories to mirror; placeholders only |
| `Sync-RepoWiseMirrors.sh` | index host | create/update bare mirrors, record fetched revisions |
| `Invoke-RepoWiseCloudIndex.sh` | index host | incremental, capped index refresh + per-repo status JSON |
| `repowise-mcp-serve.sh`, `repowise-mcp.service.example` | index host | shared MCP server on loopback only |
| `Connect-RepoWiseCloud.ps1` | Windows workstation | on-demand windowless SSH tunnel + verify + stale-index check |
| `context_cap.py`, `repowise_bridge_capped.py` | Windows workstation | bounded pre-task/post-diff context over the tunnel |
| `Measure-RepoWiseBenefit.ps1`, `samples/benchmark/` | anywhere | turn recorded run logs into a comparison table |
| `New-RepoWiseFindings.ps1`, `samples/findings/` | anywhere | turn repowise health/dead-code/risk output into a findings file |

## Audit: what exists today

Established by reading `packages/repowise/` and running the installed CLI
(`repowise --version` → **0.60.1**; `repowise --help`, `repowise update --help`,
`repowise mcp --help`, `repowise workspace add --help` are read-only and were
run for this audit):

- **Version targeted: repowise 0.60.1** (installed and what this repository
  audits against).
- **Windows launch path today:** the vendor plugins `repowise@repowise`
  (Claude) and `codex@repowise` (Codex) own MCP, hooks and skills. Their cached
  MCP configurations were rewritten to point at
  `packages/repowise/scripts/vendor_mcp.py`, which delegates to
  `repowise_bridge.py`. The bridge ensures one shared server
  (`scripts/shared_server.py`) is up on `http://127.0.0.1:7339/mcp`
  (streamable HTTP), then forwards the session's stdio JSON-RPC to it. The
  server validates the Azure embedding environment before serving
  (`FOUNDRY_OPENAI_BASE_URL`, `FOUNDRY_API_KEY`/`AZURE_AI_SERVICES_KEY`,
  `FOUNDRY_EMBEDDING_DEPLOYMENT` — env names, not values).
- **Measured serving footprint** (from `vendor_mcp.py`): a `repowise mcp`
  process per session is ~330 MB each (3.3 GB across 10 sessions measured);
  the shared server is ~760 MB for all sessions — that is why the shared
  server exists.
- **Local indexing today:** `scripts/Invoke-RepoWiseBoundedIndex.ps1` wraps
  `scripts/bounded_index.py`, which runs `repowise update --index-only` inside
  a Windows Job Object with a hard memory cap. Measured peaks: a normal
  repository stays under 1.1 GB; the largest observed (first run after a
  RepoWise upgrade) hit 3.3 GiB — hence the 4 GiB default cap and the
  minimum-4-GiB-free precheck.
- **Remote mode already exists in the bridge:** `AGENTHUB_REPOWISE_MODE=remote`,
  `AGENTHUB_REPOWISE_REMOTE_URL`, and `AGENTHUB_REPOWISE_REMOTE_TOKEN_ENV`
  (default name `REPOWISE_REMOTE_TOKEN`) point the bridge at a remote server
  instead of spawning a local one.
- **Index state:** `repowise workspace add` / `repowise update` keep a
  workspace file (`.repowise-workspace.yaml`) plus per-repo `.repowise/`
  directories; `state.json` records `last_sync_commit`, which the index script
  checks against the mirror revision before reporting success.
  - **Established** (from `packages/repowise/scripts/bounded_index.py`, which
    reads `repo/.repowise/state.json`, and from a real AgentHub checkout):
    on repowise 0.60.1, `.repowise/` lives **inside the indexed repository
    directory** and `.repowise-workspace.yaml` at the workspace root.
  - **Consequence:** an unfiltered `git clean -fd` inside the checkout would
    delete `.repowise/` every run, so the incremental `repowise update
    --index-only` path would never fire. `materialize_checkout` therefore
    cleans with `-e .repowise -e .repowise-workspace.yaml`.
  - **NOT ESTABLISHED:** whether repowise on Linux keeps state in exactly the
    same locations (the vendor supports Linux but the layout was verified on
    Windows only), and exactly where `workspace add` writes the workspace
    file when the checkout is added to an existing workspace. If a deployed
    run shows `.repowise/` absent from the checkout after indexing, inspect
    `repowise workspace list` output and adjust the `-e` excludes to match.
- **What differs on Linux:**
  - The Windows Job Object memory cap has no direct equivalent; this recipe
    uses a `systemd-run --scope` cgroup (`MemoryMax`) with an `ulimit -v`
    address-space fallback, and refuses to run uncapped.
  - The service manager is systemd (a *user* unit is enough — no root needed
    beyond installing repowise itself).
  - `repowise mcp` / `shared_server.py` loopback binding and the streamable-HTTP
    surface are Python and carry over unchanged.
  - The tunnel replaces the on-demand local spawn: availability comes from
    SSH + a resident unit instead of the bridge starting a process.
- **NOT ESTABLISHED (not guessed at):**
  - repowise 0.60.1 behaviour/flags on Linux (the vendor supports Linux, but
    this recipe was not executed there).
  - `--format json` output shapes of `repowise health|dead-code|risk` —
    `New-RepoWiseFindings.ps1` normalizes best-effort and preserves
    unrecognized fields verbatim.
  - Exact `--defer-docs` semantics on this version (help lists it; wired as
    an opt-in only).
  - Whether the vendor plugins can point their MCP entry at a stdio bridge
    on Windows without re-pinning plugin cache entries (out of scope here).

## Host requirements

All numbers are sized for **one concurrent indexing run** (the indexer
serializes itself; run it sequentially).

**RAM** — `RAM >= OS (~1 GiB) + MCP server (~1 GiB) + index cap (default 4 GiB) + headroom (~1 GiB)`.

| Component | Figure | Basis |
| --- | --- | --- |
| shared MCP server | ~760 MB | measured (`vendor_mcp.py`), Windows; Linux assumed similar — NOT ESTABLISHED |
| one index run | <= 4 GiB hard cap | cap default `REPOWISE_INDEX_MEM_MB=4096`; worst measured local peak 3.3 GiB |
| **recommended host** | **8 GiB** | derived, comfortable for unit + sync + one indexer |

**Disk per repository** — `disk(repo) ~= mirror + checkout + index-db`:

| Piece | What it is | Figure |
| --- | --- | --- |
| `~/.local/share/repowise-cloud/mirrors/<alias>.git` | bare mirror (`clone --mirror`), full history | ~= size of the remote's packed `.git` |
| `~/.local/share/repowise-cloud/index/<alias>` | machine-owned checkout + `.repowise/` index | measured on AgentHub: `.git` 27 MiB packed, `.repowise` 98 MiB (one data point — **not a guaranteed ratio**) |
| `state/`, `status/` | `.rev` and `.json` files | negligible |

Rule of thumb until you measure your own fleet: `disk(repo) ~= 2x the size of
a fresh clone of that repo`, plus the mirror again. The 2x is **not measured**;
the AgentHub numbers above are.

**Other requirements:** bash 4+, git, jq, flock, timeout (coreutils), a Python
that runs `shared_server.py`, `repowise` on PATH, outbound HTTPS to the Azure
embedder, inbound SSH. systemd with user sessions for the preferred memory
cap and the service unit; without systemd the indexer falls back to
`ulimit -v` and the server needs another supervisor — no supervisor fallback
is shipped.

## Deployment steps (recipe — not executed)

1. Provision a Linux host reachable by SSH from the workstations only. Give it
   a hostname you control; the examples use the SSH config alias
   `repowise-mirror` — add it to `~/.ssh/config` on each workstation.
2. Install repowise per vendor docs (`repowise --version` must print the
   audited version or newer); install git, jq, and Python with the
   `shared_server.py` dependencies.
3. Copy the mirror list into place and edit it for your fleet:
   `cp packages/repowise/cloud/mirrors.example.json ~/.config/repowise-cloud/mirrors.json`,
   then replace every `<...>` placeholder. **Do not commit a real list** —
   the shipped example keeps placeholders on purpose.
4. Create a **read-only deploy key** per remote (or one shared one) at each git
   host; put the private key file(s) on the index host and export the *path*
   in the variable named by `defaultCredentialEnv`/`credentialEnv` (e.g.
   `REPOWISE_MIRROR_DEPLOY_KEY=/home/<user>/.ssh/repowise-mirror-ro`). The
   scripts read the variable's value, never embed a credential.
5. Lay down the package: copy `packages/repowise/` (including `cloud/` and
   `scripts/shared_server.py`) to a deploy root on the host, e.g.
   `~/repowise-cloud/`.
6. First sync: `bash cloud/Sync-RepoWiseMirrors.sh` — creates
   `mirrors/<alias>.git` bare mirrors and `state/<alias>.rev`.
7. First index: `bash cloud/Invoke-RepoWiseCloudIndex.sh` — materializes
   `index/<alias>` checkouts and runs `repowise workspace add --no-docs
   --no-save-key` under the caps; status lands in `status/<alias>.json`.
8. Create the embedder environment file `~/.config/repowise-cloud/embedder.env`
   (chmod 600) with `FOUNDRY_OPENAI_BASE_URL`, `FOUNDRY_API_KEY`,
   `FOUNDRY_EMBEDDING_DEPLOYMENT`. Names only — values stay on the host.
9. Install the service: copy `repowise-mcp.service.example` to
   `~/.config/systemd/user/repowise-mcp.service`, replace `<deploy-root>`,
   then `systemctl --user daemon-reload && systemctl --user enable --now
   repowise-mcp.service` (enable linger for boot persistence if wanted:
   `loginctl enable-linger <user>`).
10. From a Windows workstation:
    `pwsh -NoProfile -File Connect-RepoWiseCloud.ps1 -SshTarget repowise-mirror -Alias <alias>` —
    it opens the tunnel windowless, does a real MCP round trip, reports the
    index status versus local `HEAD`, and closes the tunnel it opened.
11. Point agents at the bridge: set `REPOWISE_CLOUD_MCP_URL` to the printed
    loopback URL (or keep the default `http://127.0.0.1:7339/mcp` with
    `-LocalPort 7339 -KeepTunnel`) and configure the host's MCP entry to run
    `repowise_bridge_capped.py`. Alternatively use the existing remote mode:
    `AGENTHUB_REPOWISE_MODE=remote` + `AGENTHUB_REPOWISE_REMOTE_URL` — that
    path does not apply the context cap; the capped bridge does.

## Security boundary

- The MCP server binds **127.0.0.1 only** — the binding is inside
  `shared_server.py`; the unit and launcher never override it. There is no
  public listener and no unauthenticated port anywhere in this recipe.
- The only path in is **SSH**, workstation -> host, forwarding
  `127.0.0.1:<local>` to `127.0.0.1:7339`. Firewall the host to SSH only.
- Mirrors are **read-only by construction**: bare repos, fetched with a
  read-only deploy key, and every mirror's push URL is pinned to `DISABLED`
  (`git remote set-url --push origin DISABLED`) after each sync — even a
  writable credential cannot turn the host into a write path.
- Repository URLs are **validated before they reach git**: `valid_repo_url`
  accepts only scp-style ssh, `ssh://`, or `https://` clone URLs to
  github.com of the form `owner/name[.git]`, and `git clone`/`remote set-url`
  place `--` before the URL. A URL can therefore never be parsed as a git
  option (e.g. `-oProxyCommand=...`). Mirroring a different git host means
  deliberately widening that function — it is not a config option.
- Aliases are **path segments**, and validated as such (`^[a-z0-9][a-z0-9._-]*$`)
  in both scripts: `--only ../x` and a config alias like it are refused before
  `git clean`/`reset --hard` can run outside the mirror, index, state or
  status roots (`path_under` re-verifies containment).
- Credentials appear **by name only**: the deploy key is an env-var name in
  the mirror list; embedder secrets live in `embedder.env` (0600) referenced
  by `EnvironmentFile`; nothing secret is in the repo. Both bash scripts run
  `umask 077`, and the sync refuses a key file that is group- or
  world-readable (the same rule ssh itself applies).
- `Connect-RepoWiseCloud.ps1` registers **nothing persistent** — no scheduled
  task, no Run key, no service — and kills only the tunnel PID it started.
  Its `-Alias`, `-SshTarget`, `-RemoteStatusDir` and ports are all validated
  (and `--` terminates ssh option parsing) before any ssh process starts, so
  none of them can be turned into a remote shell command or an ssh option.
- The stale-index probe **distinguishes "missing" from "unreadable"**: the
  remote command prints the status file when present, exits 4 when absent
  (`not-indexed`), and surfaces stderr on any other failure (`unknown`). It
  builds the path with `$HOME` inside double quotes — never a single-quoted
  `~` that silently fails.
- Indexer exit-code semantics: `124` is the `timeout` deadline; `137` is a
  SIGKILL — under `MemoryMax` that is the cgroup OOM kill (or the `-k` grace
  firing) and is reported as a **memory kill**, not a timeout.

## Scheduling

The scripts install **no schedule** — there is no timer, cron entry, or
Windows task until the owner chooses a cadence. When they do, the natural
choices on the host are a user systemd timer or a cron line that runs
`Sync-RepoWiseMirrors.sh && Invoke-RepoWiseCloudIndex.sh` — the scripts take
flock locks so overlapping runs fail fast instead of racing. A reasonable
starting point is hourly sync + index; the stale-index check on the connector
is what tells you the cadence is too slow.

## Rollback

- **Workstation side:** stop pointing agents at `REPOWISE_CLOUD_MCP_URL` /
  remote-mode env vars. The local shared server and the existing bounded
  indexer are untouched — the fleet's current behaviour returns immediately.
- **Host side:** `systemctl --user disable --now repowise-mcp.service`, remove
  the unit and any timer the owner added, then delete
  `~/.local/share/repowise-cloud/` (mirrors, checkouts, state, status) and
  `~/.config/repowise-cloud/`. Nothing on the host writes outside those two
  roots.
- Any host-side failure mode is fail-closed for the workstation: unreachable
  endpoint -> JSON-RPC error replies from the capped bridge, or a non-zero
  connector exit — never a silent fallback to indexing locally.

## Benchmark and findings usage

- Record one benchmark log per mode in the JSONL format documented in
  `Measure-RepoWiseBenefit.ps1` (fields: repo, task, tokensTotal incl. cached,
  tokensCached, toolCalls, secondsToCorrectFile, indexStale), then run it with
  the task list (three tasks per repository) to get the comparison table.
  Sample: `samples/benchmark/`.
- On the host, capture `repowise health|dead-code|risk` JSON output, then run
  `New-RepoWiseFindings.ps1` with `-IssueId <existing tracker id>` to produce
  a findings file with sha256 evidence per input. The script is read-only —
  it cannot create, edit, or close an issue.

## What was NOT done

- **Nothing deployed** — no host was provisioned and no script ran against a
  remote; there is no SSH or cloud access from this worktree.
- **No remote index built** — the mirror list, sync, indexer, service and
  connector were written and statically/unit-tested, never executed on Linux.
- **No benchmark with real agents** — the harness parses the format, the
  shipped logs are synthetic samples.
- **Upstream Linux compatibility not verified** — repowise 0.60.1 on Linux,
  `workspace add`/`update` flag parity, and the shared server under the
  systemd unit are all unverified there; the audit's "NOT ESTABLISHED" items
  stand.
- **No real deployment credential exercised** — `git_ssh_command` was
  reviewed statically; no deploy key was created or used.
