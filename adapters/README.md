# Adapter conventions

An adapter is a host-specific exposure of an existing capability owner. It may contain configuration, a manifest, an agent definition, or only deployment instructions. It must not reimplement the underlying capability or introduce a second owner.

All adapters inherit the root `AGENTS.md` policy. Use the host folders for installation guidance and verified support state.

Portfolio context uses the single owner **`repocontext`** (remote + local MCP and shared skill under `capabilities/repocontext/`). Adapters must not fork RepoContext tools or embed credentials. Retired ShWiki aliases migrate to `repocontext`; keep unrelated functional MCPs.
