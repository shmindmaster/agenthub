# Adapter conventions

An adapter is a host-specific exposure of an existing capability owner. It may contain configuration, a manifest, an agent definition, or only deployment instructions. It must not reimplement the underlying capability or introduce a second owner.

All adapters inherit the root `AGENTS.md` policy. Use the host folders for installation guidance and verified support state.

Portfolio context uses the single owner **`shwiki-context`** (remote + local MCP and shared skill under `capabilities/shwiki-context/`). Adapters must not fork ShWiki tools or embed credentials. Remove only Devin/DeepWiki MCP endpoints during host rollout; keep unrelated functional MCPs.

