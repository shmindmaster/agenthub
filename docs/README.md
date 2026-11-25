# Documentation Map

See the [browser setup and acceptance runbook](runbooks/browser-fleet.md) for native browser tools, user collaboration, recording and remote MCP setup.

Start with [development/quickstart.md](./development/quickstart.md) for a
stranger-safe first run. For this private fleet checkout, also use
[current-state.md](./current-state.md) for verified repository reality.

## Product

- [product/vision.md](./product/vision.md) — what AgentHub is for, its
  boundaries, and what must never enter this repository. Read before adding a
  capability or a registry surface.

## Architecture

- [Portfolio intelligence direction](architecture/portfolio-intelligence.md) — proposed commercial pilots, product opportunities and evidence requirements.

- [architecture/control-plane-modules.md](./architecture/control-plane-modules.md) —
  PathBinding, host catalog, capability overlay, and the public/personal split.
- [architecture/overview.md](./architecture/overview.md) — registry model and
  validation layers (fleet checkout).
- [architecture/portfolio-policy.md](./architecture/portfolio-policy.md) —
  proposed portfolio sharing policy (private).

## Development

- [development/quickstart.md](./development/quickstart.md) — init → validate → sync.
- [development/setup.md](./development/setup.md) — environment requirements.
- [development/testing.md](./development/testing.md) — test layers.
- [development/skill-authoring-standard.md](./development/skill-authoring-standard.md).
- [development/repo-standard.md](./development/repo-standard.md) — fleet repository standard.
- [development/pr-review-guideline.md](./development/pr-review-guideline.md) —
  shared fleet PR review guideline (SH-4416): ready-only Seer/Codex review,
  exact-head-SHA verdicts, reviewer independence, bounded iteration, no
  auto-merge; carries the `## Code Review Rules` block copied into each
  repo's `AGENTS.md`.
- [Portfolio product and architecture standard](../packages/product/references/portfolio-standard.md) — production-grade apps, storage, workers, caching, static marketing sites and email provider choice; ships with `ah-product`.
- [development/agent-orientation.md](./development/agent-orientation.md), [agent-change-contract.md](./development/agent-change-contract.md) — agent reference loaded on demand from the triggers in `AGENTS.md`.
- [development/chrome-cdp.md](./development/chrome-cdp.md) — browser MCP notes.

## Operations

- [Research workflows and verification](runbooks/research.md) — Exa, Parallel and Tavily routing, native acceptance and scope.

- [runbooks/desktop-integrations.md](./runbooks/desktop-integrations.md) — Windows inventory and app-owned connector verification for AutoClaw, Grok Bot, and Manus Studio.
- [runbooks/zcode.md](./runbooks/zcode.md) — Standalone ZCode inventory, native marketplace deployment, MCP, and browser setup.
- [runbooks/clerk-auth.md](./runbooks/clerk-auth.md) — official Clerk fleet rollout,
  host OAuth lifecycle, genuine user and tenant/resource authorization acceptance.

- [runbooks/sync-and-validate.md](./runbooks/sync-and-validate.md) — drift
  audit, deploy, validate, and fleet standard sweep procedures.
- [runbooks/plugin-deployment.md](./runbooks/plugin-deployment.md) — `ah-` plugin
  naming and the install, refresh and remove command for each host.
- [runbooks/demo-profile.md](./runbooks/demo-profile.md) — throwaway profile
  for an on-camera audit -> apply -> audit, with home paths cropped to `~`.
- [runbooks/stale-agent-sessions.md](./runbooks/stale-agent-sessions.md) —
  on-demand recycle of coding-agent sessions older than seven days, and where
  each agent keeps them.
- [runbooks/hosting-routing.md](./runbooks/hosting-routing.md) — deployment
  provider selection and retained-integration rules.
- [runbooks/codebuild-pr-ci.md](./runbooks/codebuild-pr-ci.md) — reusable
  CodeBuild pull-request CI template, read-only preflight, and IAM boundary.
- [runbooks/do-interim-release.md](./runbooks/do-interim-release.md) — DigitalOcean
  SHA-tag image releases, rollback, and AWS target.
- [runbooks/pr-review.md](./runbooks/pr-review.md) — the host-enforced
  read-only PR reviewer run through the dispatcher.
- [../ci/daytona-factory/README.md](../ci/daytona-factory/README.md) — Daytona
  build and demo factory workflow: Daytona v2 by default, `platform=v0`
  fallback, pilot budget and cleanup controls.

## Execution

- [plans/PLANS.md](./plans/PLANS.md) — when and how to write resumable plans.
- [plans/active/](./plans/active/) — active complex work.
- [plans/completed/](./plans/completed/) — required directory; finished plans are deleted, not retained.
