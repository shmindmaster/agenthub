# Agent ecosystem classification — 2026-07-24

This is a read-only classification of package and host surfaces that are present in the repository but are not current entries in `registry/capabilities.json`. No package was deleted or promoted as part of this review.

## Noncanonical packages

| Package | Evidence | Classification | Action |
| --- | --- | --- | --- |
| `packages/portfolio-plugins/ediscovery-processing` | Four host manifests, a local `courtlistener` executable path under `D:\LocalAI\KnowledgeSystem`, a Trellis OAuth endpoint, and descriptions tied to immutable evidence on `G:\` | Retained inactive; local/private-data and provider-specific dependencies require a separate capability owner and authorization review | Preserve unchanged; do not distribute or register as a general fleet capability |
| `packages/portfolio-plugins/knowledge-system` | Four host manifests, a local ShWiki/RAG MCP reference, and descriptions for a private local corpus | Retained inactive; local/private-data coupling and no current registry mapping | Preserve unchanged; use `shwiki-context` as the current canonical read-only portfolio-context capability |
| `packages/portfolio-plugins/notebooklm-ops` | One Codex manifest, zero skills, zero MCP servers, and no active registry mapping | Retained inactive scaffold; not implementation-ready | Preserve unchanged; do not advertise or distribute |

All three packages were last touched by commit `28485ff` (`chore: bootstrap agent capability control plane`) and have no current working-tree edits. Their absence from the registry is therefore a deliberate classification gap, not proof that they are safe to delete.

## Host surfaces

- Cursor and Cursor Agent remain retained-disabled. No launch, availability probe, configuration activation, or dispatch was performed.
- Amp, Devin, Factory, VS Code Insiders, and Windsurf remain retained/inactive according to the registry. Their configuration paths are preserved, but inactive status is not treated as proof of runtime readiness.
- Hosts with discovery-required plugin, subagent, hook, LSP, ACP, or memory contracts remain explicitly marked rather than receiving speculative files.

## MCP state

- Canonical MCP endpoints and environment/OAuth references remain in `registry/mcps.json`.
- ShWiki is configured as the canonical remote read-only context server; local/private package MCP definitions are not promoted into the global registry.
- OAuth-pending connectors remain pending until the user completes host-managed authentication. No credentials were written.
