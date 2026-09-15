# Runbook: Sync, Validate, and Fleet Sweeps

## Validate the registry

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
```

Fails on: missing canonical packages, content-hash drift, forbidden roots,
stale legacy paths, malformed registry references.

## Audit deployment drift (read-only)

```powershell
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Audit -Validate
pwsh -NoProfile -File .\scripts\Sync-Capabilities.ps1            # audit default
```

## Deploy managed state to hosts

```powershell
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Apply -Validate
pwsh -NoProfile -File .\scripts\Sync-Capabilities.ps1 -Apply
```

`-Apply` refuses to run if validation fails. Deployments write only to
documented host user-level config locations; they never carry credentials.

`Sync-Capabilities.ps1 -Apply` also quotes unmanaged `SKILL.md` frontmatter
in `~/.agents/skills` that strict YAML parsers (Zed) reject. Standalone:

```powershell
pwsh -NoProfile -File .\scripts\Repair-SkillFrontmatterYaml.ps1          # audit
pwsh -NoProfile -File .\scripts\Repair-SkillFrontmatterYaml.ps1 -Apply   # quote
```

## Fleet repository-standard sweep

```powershell
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All            # report
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All -Fix       # repair deterministic drift
pwsh -NoProfile -File .\scripts\Update-RepoWise.ps1 -Audit             # CLI vs PyPI latest
repowise status -w                                                    # index freshness (from C:\Repos)
repowise doctor -w                                                    # RepoWise health
```

Run after: adding a repo to the fleet, changing the standard, or any large
documentation/agent-instruction change in a member repo.

## After changing package content

1. `pwsh -NoProfile -File .\scripts\RegistryContentHash.ps1` usage:
   dot-source it and call `Get-AgentHubRegistryHashBasisValue -Path packages\<name>`;
   write the value into `registry/capabilities.json` `contentHash`.
2. Validate + affected tests.
3. Sync audit to see deployment drift.
