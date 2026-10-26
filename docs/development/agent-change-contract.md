Read this before changing a capability, registry entry, package, script, test, or host manifest, and before declaring any change done.

# AgentHub — Change contract, testing, definition of done

## Change contract

Before changing a capability, identify its single registry owner. Then:

1. Update the canonical package content and every applicable host manifest.
2. Bump package versions.
3. Recompute the registry content hash with `scripts/RegistryContentHash.ps1`.
4. Run `scripts/Validate-AgentHub.ps1` plus the package's own validator.

## Lifecycle entry point

`scripts/AgentHub.ps1` is the single lifecycle entry point. Its commands are:
- `inventory`
- `validate`
- `sync`: audits by default. `-Apply` refuses to run if validate fails.
- `drift`

It orchestrates the existing scripts and does not reimplement them.

## Host formats

- Use official host formats.
- A host without verified packaging support receives supported loose skills/MCP configuration. Do not invent a plugin format.
- Keep implemented, validated, deployed, and production-verified states distinct.

## Testing and verification

- Every registry or script change requires `Validate-AgentHub.ps1` plus the affected `tests/Test-*.ps1`. Run the full `tests/Run-AllTests.ps1` instead when shared contracts move.
- The fleet checker has fixture tests in `tests/Test-RepoStandard.ps1`.
- Never claim a check passed unless it ran.

## Definition of done

- Registry and package content agree, and content hashes are recomputed.
- `Validate-AgentHub.ps1` and the relevant tests pass.
- Docs are updated when behavior, layout, or contracts changed.
- The RepoWise index is refreshed through the bounded manual entry point (`packages/repowise/scripts/Invoke-RepoWiseBoundedIndex.ps1`).
