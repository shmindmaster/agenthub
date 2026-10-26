Read this when you start work in agenthub, need to orient, or need to know which doc or path owns something.

# AgentHub — Orientation

## Public-first layout

This checkout tracks only public packages under `packages/`. Private capability packages and registry rows live in the gitignored `overlays/personal/` tree on the operator machine. That tree has the same shape strangers get after `init`. There is no second AgentHub control-plane repo.

## Knowledge authority

- Executable code, tests, and scripts describe implemented reality.
- `docs/` holds intentional durable knowledge.
- RepoWise holds derived codebase intelligence.

When they disagree, investigate rather than silently choosing one.

## Start here

1. `AGENTS.md`.
2. `docs/README.md` → `docs/current-state.md`.
3. `global-agent-policy.md`, the public global policy. An overlay host's effective policy is `overlays/personal/global-agent-policy.md`.
4. `docs/development/repo-standard.md` when touching any other fleet repo.
5. `registry/` entries relevant to the capability you are changing.
6. RepoWise workspace context before broad exploration (see [`agent-repowise.md`](./agent-repowise.md)).

## Repository map

| Path | Role |
| --- | --- |
| `packages/<name>/` | **Public** capability content (skill packs, plugins), including RepoWise |
| `overlays/personal.example/` | Template for a local private overlay |
| `overlays/personal/` | **Gitignored** local override: `packages/`, `capabilities.json`, `overlay.json` |
| `registry/` | Public parity contract (no private capability rows) |
| `scripts/` | Lifecycle: sync, validate, hash, checker |
| `tests/` | Behavior tests for registry, sync, and scripts |
| `docs/` | Curated durable knowledge (see `docs/README.md`) |
| `.agents/plugins/marketplace.json` | Public plugin catalog |
| `.claude-plugin/marketplace.json` | Claude-format compatibility projection |

The remote is `github.com/shmindmaster/agenthub` (public). The old `agenthub-internal` mirror is archived. Do not recreate a second control-plane checkout.
