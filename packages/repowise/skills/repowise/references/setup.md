# Setup

Read when: configuring embeddings, the CLI, the dashboard, or hosted mode.

## Embeddings

RepoWise's `openai` embedder points at MahumTech Azure OpenAI `mt-foundary-resource`, deployment `text-embedding-3-small` (1536 dimensions). Read these from the environment at start and never persist them:

- `FOUNDRY_OPENAI_BASE_URL` (`https://mt-foundary-resource.openai.azure.com/openai/v1/`)
- `FOUNDRY_API_KEY` or `AZURE_AI_SERVICES_KEY`
- `FOUNDRY_EMBEDDING_DEPLOYMENT`

Accept https and `*.openai.azure.com` only. The probe must return a finite, nonzero embedding before the server serves. A models response or `embedder_degraded: false` is not enough: run real searches and check the vector source and relevance. CLI indexing needs the same base URL, key, deployment and width; keep the existing vector config. Change providers only through an explicit, compatible reindex. Embedding models are not covered by Azure Batch and the deployment allows 700K TPM, so full re-embeds are slow.

## CLI and dashboard

The CLI is uv-managed (`uv tool install repowise`). Update manually with `pwsh -NoProfile -File <agenthub>/scripts/Update-RepoWise.ps1 -Apply` (the script lives in the repository's `scripts/` folder, not this package); it installs `repowise@latest` only when a newer version exists and does not touch editors or hooks. Run `repowise search "<q>"`, `repowise status -w` and `repowise doctor -w` from `C:/Repos`.

Dashboard: `repowise serve --host 127.0.0.1 --ui-port 7338` from `C:/Repos`; API on `http://127.0.0.1:7337`.

Workspace instructions are in `C:/Repos/.claude/CLAUDE.md` and `C:/Repos/AGENTS.md`; never hand-edit inside `REPOWISE:START` blocks.

## Hosted mode (bridge)

The bridge can forward to a self-hosted RepoWise endpoint. It is off by default; the private overlay sets these outside the repository:

| Variable | Meaning |
| --- | --- |
| `AGENTHUB_REPOWISE_MODE` | `local` (default) or `remote` |
| `AGENTHUB_REPOWISE_REMOTE_URL` | hosted MCP URL, https only |
| `AGENTHUB_REPOWISE_REMOTE_TOKEN_ENV` | name of the env var holding the bearer token (default `REPOWISE_REMOTE_TOKEN`) |

In remote mode the bridge never starts the local launcher and never falls back to local: an unreachable remote, missing token or refused token returns a JSON-RPC error naming the cause. Return to local with `AGENTHUB_REPOWISE_MODE=local` and restart the host session. A repo missing from `list_repos` in remote mode was not cleared for hosting; use local mode or `rg`. Never log or echo the token, and never persist a remote URL or token in a tracked file or host config. Never send repository queries or credentials to a hosted endpoint outside this mode.
