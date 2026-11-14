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
   `Run-AllTests.ps1` discovers only `packages/**/*.test.mjs`; the other Node suites
   are run directly: `node --test test/doctor/*.test.mjs` and
   `node --test scripts/registry-content-hash.test.mjs` (the Node port of
   `scripts/RegistryContentHash.ps1`, for hosts without `pwsh`).
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

## CI selection

Every change checks registry validation, hashes, public privacy, and the CI
classifier. The classifier compares the PR base or push before-SHA with the
checked-out commit and unions the checks for every changed area. Package
changes run that package's tests and shared plugin checks on Linux; dispatch,
RepoWise, and mobile packages also run on Windows for host-specific checks. Media
Studio tests run only for Media Studio changes, split into four shards.
Doctor changes run its tests on Linux. Shared or unrecognized files run
repository-level contracts and package validators in four Linux and macOS shards
and eight Windows shards;
the media-specific tests are excluded unless that package changed. Manual runs
or unavailable history run shared and all package tests. Main pushes have
separate concurrency groups so later pushes cannot cancel earlier checks.
Run-AllTests.ps1 without a scope still runs the full suite on the local host.
