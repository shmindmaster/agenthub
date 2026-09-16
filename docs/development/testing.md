# Testing

## Layers

1. **Registry validation** — `scripts/Validate-AgentHub.ps1`: structure,
   content hashes, forbidden roots, stale legacy paths.
2. **Behavior tests** — `tests/Test-*.ps1`: one file per contract surface
   (sync idempotency, host surfaces, capability ownership/routing, worktree
   helper, repo standard checker, ...). Each ends with
   `RESULT: N passed, M failed` and a matching exit code.
3. **Package validators** — `packages/*/tests/validate-plugin.ps1`.

## Canonical commands

```powershell
pwsh -NoProfile -File .\tests\Run-AllTests.ps1     # distribution-appropriate suite
pwsh -NoProfile -File .\tests\Test-RepoStandard.ps1  # checker fixtures only
```

`Run-AllTests.ps1` discovers `tests/Test-*.ps1` in the internal distribution.
The public-core distribution uses an explicit portable list so tests that
require private overlays, local fleet state, or export tooling are not
misrepresented as public failures. Both distributions include package
validators and Node tests, aggregate their results, and exit non-zero on any
failure. A discovered-empty run fails loudly by design.

## Conventions

- The full public suite and assurance demo require PowerShell 7.4+. Individual
  core scripts that declare `#Requires -Version 5.1` retain their documented
  Windows PowerShell compatibility and are still exercised independently.
- Result output goes through `Write-Output`, not only `Write-Host`, so
  parent-process capture (Run-AllTests, CI) can parse it.
- Registry JSON is read with `-Encoding UTF8`; hashes normalize line endings
  (`scripts/RegistryContentHash.ps1`).
