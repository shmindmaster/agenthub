# Testing

## Layers

1. **Registry validation** — `scripts/Validate-AgentHub.ps1`: structure,
   content hashes, forbidden roots, stale legacy paths.
2. **Behavior tests** — `tests/Test-*.ps1`: one file per contract surface
   (sync idempotency, host surfaces, capability ownership/routing, worktree
   helper, repo standard checker, ...). Each ends with
   `RESULT: N passed, M failed` and a matching exit code.
3. **Package validators** — `packages/*/tests/validate-*.ps1`.
4. **Node tests** — `packages/**/*.test.mjs`, run with `node --test`.
5. **Python tests** — `test_*.py` files, run with `python -m unittest` from a
   `tests/Test-*.ps1` wrapper through `tests/lib/PythonUnitTests.ps1`, which
   removes credential variables and points `LOCALAPPDATA` and `HOME` at a
   throwaway directory. The runner does not discover `.py` files itself, so a
   new Python test needs a wrapper.

## Canonical commands

```powershell
pwsh -NoProfile -File .\tests\Run-AllTests.ps1     # everything
pwsh -NoProfile -File .\tests\Test-RepoStandard.ps1  # checker fixtures only
```

`Run-AllTests.ps1` discovers `tests/Test-*.ps1` plus package validators,
aggregates, and exits non-zero on any failure. A discovered-empty run fails
loudly by design.

## Conventions

- Tests are PowerShell 5.1-compatible and use the accumulate-and-report
  idiom (`Report` function + `RESULT` line).
- Result output goes through `Write-Output`, not only `Write-Host`, so
  parent-process capture (Run-AllTests, CI) can parse it.
- Registry JSON is read with `-Encoding UTF8`; hashes normalize line endings
  (`scripts/RegistryContentHash.ps1`).
