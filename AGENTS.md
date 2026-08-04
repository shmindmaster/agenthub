# AgentHub

AgentHub is the personal source of truth for cross-agent skill, plugin, MCP, and policy parity.

## Boundary

- Personal capability work stays in personal systems and uses synthetic fixtures.
- Never copy credentials, authentication state, customer data, private evidence, reports, session state, generated media, or runtime caches into this repository.
- Read a target repository's `AGENTS.md` before touching it. Preserve unrelated work.
- Ask before production changes, external communication, credential changes, or destructive work unless the user explicitly authorized it.

## Canonical layout

- Every capability lives under `packages/<name>`; the registry declares whether it is a plugin or skill pack.
- `.agents/plugins/marketplace.json` is the canonical local catalog; `.claude-plugin/marketplace.json` is the small compatibility projection used by Claude-format consumers.
- `registry/agents.json`, `registry/capabilities.json`, and `registry/mcps.json` are the parity contract.
- Runtime output belongs under `%LOCALAPPDATA%\AgentHub`.
- Finished product videos belong at the OneDrive paths in `registry/product-video-delivery.json`.

Do not reintroduce `adapters`, `capabilities`, `docs`, `generated`, `profiles`, `reports`, `roles`, `standards`, `state`, `templates`, nested plugin roots, or dated audit documents.

## Change contract

Before changing a capability, identify its single registry owner. Update canonical package content and every applicable host manifest, bump package versions, recompute the registry content hash with `scripts/RegistryContentHash.ps1`, and run `scripts/Validate-AgentHub.ps1` plus the package's own validator.

`scripts/AgentHub.ps1` is the single lifecycle entry point: `inventory` (read-only, what the registry declares vs what is on disk), `validate` (delegates to `Validate-AgentHub.ps1`), `sync` (audits by default; `-Apply` is explicit and refuses to run if `validate` fails first), and `drift` (every sync script in audit mode, one verdict). It orchestrates the existing scripts; it does not reimplement them.

Use official host formats. A host without verified packaging support receives supported loose skills/MCP configuration; do not invent a plugin format. Keep implemented, validated, deployed, and production-verified states distinct.

## GitHub

Use `gh`, verify the active account first, and use `shmindmaster` for this repository.
