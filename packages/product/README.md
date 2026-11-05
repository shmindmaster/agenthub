# AH-Product

Audit, design, build, verify and demo product experiences on evidence. Five skills plus one read-only reviewer agent, no MCP server and no hook.

The reviewer agent issues verdicts; the context that wrote a change never does. Each skill is capped at 500 words, so the detail lives in `references/`: `agentic.md`, `authenticated-acceptance.md`, `demo-handoff.md` and `surfaces.md`.

`kits/execution-controls` and `kits/demo-harness` are cross-portfolio contracts. Products vendor the first with `scripts/vendor-execution-controls.mjs` and check drift with `--check`.

Root `plugin.json` is the version authority; bump it with `scripts/Bump-PackageVersion.ps1`, never by hand. Run `tests/run-all.ps1` after any change, then recompute this package's `contentHash`. See `docs/runbooks/plugin-deployment.md`.
