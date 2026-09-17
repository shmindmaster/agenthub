#Requires -Version 5.1
<#
.SYNOPSIS
    Residue audit: write a stripped public-core tree from this checkout.

.DESCRIPTION
    Day-to-day AgentHub is already public-first (2026-09-17): private packages
    live under gitignored overlays/personal/, not under packages/. This script
    remains as a safety export/audit for publishing a clean tree; it is not a
    dual-repo sync workflow. Prefer pushing this repository's main to
    github.com/shmindmaster/agenthub.

.PARAMETER Destination
    Empty or new directory that will receive the export.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Destination = [IO.Path]::GetFullPath($Destination)

if ((Test-Path -LiteralPath $Destination) -and @(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0) {
    throw "Export destination '$Destination' is not empty. Refusing to merge into an existing tree."
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

. (Join-Path $repoRoot 'scripts\lib\CapabilityGraph.ps1')

# Private ids come from the registry visibility field — not from the personal
# overlay — so a checkout without overlays/personal can still export, and a
# published public tree never needs the private list as a side channel.
$capabilitiesSource = Join-Path $repoRoot 'registry\capabilities.json'
$capabilitiesDoc = Get-Content -LiteralPath $capabilitiesSource -Raw -Encoding UTF8 | ConvertFrom-Json
$privateIds = @(
    $capabilitiesDoc.capabilities |
        Where-Object { Test-AgentHubCapabilityPrivate $_ } |
        ForEach-Object { [string]$_.id } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

function Copy-ExportTree {
    param([string]$Relative)
    $source = Join-Path $repoRoot $Relative
    if (-not (Test-Path -LiteralPath $source)) { return }
    $target = Join-Path $Destination $Relative
    $parent = Split-Path -Parent $target
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
}

foreach ($name in @(
    'LICENSE', 'CONTRIBUTING.md', 'SECURITY.md', 'package.json',
    'policy-core.md', 'agenthub.profile.example.json',
    'scripts', 'registry', 'tests', 'docs', 'packages'
)) {
    Copy-ExportTree $name
}

foreach ($relative in @(
    '.agents\plugins\marketplace.json',
    '.claude-plugin\marketplace.json',
    'overlays\personal.example'
)) {
    Copy-ExportTree $relative
}

foreach ($id in $privateIds) {
    $packageDir = Join-Path $Destination ("packages\" + $id)
    if (Test-Path -LiteralPath $packageDir) {
        Remove-Item -LiteralPath $packageDir -Recurse -Force
    }
}

foreach ($relative in @(
    'docs\current-state.md',
    'docs\architecture\overview.md',
    'docs\architecture\portfolio-policy.md',
    'registry\repo-standard.json',
    'registry\mobile-scope.json',
    'registry\product-video-delivery.json',
    'scripts\Export-PublicCore.ps1'
)) {
    $path = Join-Path $Destination $relative
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

$utf8 = [Text.UTF8Encoding]::new($false)
Get-ChildItem -LiteralPath (Join-Path $Destination 'registry') -Filter *.json -File | ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName)
    $text = $text.Replace('C:/Users/SaroshHussain', '{userProfile}').Replace('C:\Users\SaroshHussain', '{userProfile}').Replace('C:\\Users\\SaroshHussain', '{userProfile}')
    $text = $text.Replace('D:/OneDrive - MahumTech', '{documentsRoot}').Replace('D:\OneDrive - MahumTech', '{documentsRoot}').Replace('D:\\OneDrive - MahumTech', '{documentsRoot}')
    $text = $text.Replace('D:/Local-AI', '{localRuntimeRoot}').Replace('D:\Local-AI', '{localRuntimeRoot}').Replace('D:\\Local-AI', '{localRuntimeRoot}')
    [IO.File]::WriteAllText($_.FullName, $text, $utf8)
}

# Execution plans are private working state (docs/plans/PLANS.md); the public
# tree ships none.
$planDir = Join-Path $Destination 'docs\plans\active'
if (Test-Path -LiteralPath $planDir) {
    Get-ChildItem -LiteralPath $planDir -File | Remove-Item -Force
}

$capabilitiesPath = Join-Path $Destination 'registry\capabilities.json'
$capabilities = Get-Content -LiteralPath $capabilitiesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities.capabilities = @(
    $capabilities.capabilities | Where-Object {
        -not (Test-AgentHubCapabilityPrivate $_)
    }
)
# Explicit export provenance distinguishes the portable distribution from a
# canonical fleet checkout with an accidentally missing private registry.
$capabilities | Add-Member -NotePropertyName distribution -NotePropertyValue 'public-core' -Force
[IO.File]::WriteAllText($capabilitiesPath, ($capabilities | ConvertTo-Json -Depth 40), $utf8)

function Remove-PrivateMarketplacePlugins {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $doc.PSObject.Properties['plugins']) { return }
    $privateSet = @{}
    foreach ($id in $privateIds) { $privateSet[$id] = $true }
    $doc.plugins = @(
        $doc.plugins | Where-Object {
            $name = [string]$_.name
            -not $privateSet.ContainsKey($name)
        }
    )
    [IO.File]::WriteAllText($Path, ($doc | ConvertTo-Json -Depth 20), $utf8)
}
Remove-PrivateMarketplacePlugins (Join-Path $Destination '.agents\plugins\marketplace.json')
Remove-PrivateMarketplacePlugins (Join-Path $Destination '.claude-plugin\marketplace.json')

$publicReadme = @'
# AgentHub

Portable control plane for skills, plugins, MCP servers, and policy across
coding agents — with drift detection and an optional **personal overlay** for
what should stay private on your machine.

## First five minutes

Requires [PowerShell 7+](https://aka.ms/powershell) (`pwsh`) on Windows, macOS, or Linux. Node 18+ is optional for the CLI wrapper.

```bash
# optional wrapper
npm install -g .

npx agenthub init          # local overlay + profile from examples
npx agenthub validate      # registry checks
npx agenthub sync          # read-only drift audit
# npx agenthub sync --apply  # deploy after validate passes
```

Or call PowerShell directly:

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

Full walkthrough: [docs/development/quickstart.md](./docs/development/quickstart.md).

## What this is

- One **desired-state registry** (`registry/`) for capabilities, hosts, and MCPs.
- **Validate → audit → apply** lifecycle (`scripts/AgentHub.ps1`).
- Host destinations as `{userHome}` / `{localData}` / `{roamingConfig}` templates — see [docs/architecture/control-plane-modules.md](./docs/architecture/control-plane-modules.md).
- **Personal overlay** (`overlays/personal.example/` → copy to `overlays/personal/`) for private capability ids and policy fragments. Core never imports those packages by default.
- Portable policy in `policy-core.md`. Machine roots in gitignored `agenthub.profile.json`.

This is not “symlink skills into every tool.” It is a host-neutral parity and policy plane: honest host formats, content-hash validation, and explicit degradation when a host cannot honor a surface.

## Layout

| Path | Role |
| --- | --- |
| `packages/` | Canonical capability content |
| `registry/` | Parity contract |
| `scripts/` | Validate, sync, path binding |
| `overlays/personal.example/` | Template for a local private overlay |
| `policy-core.md` | Portable policy |

Runtime output belongs under the OS local-data root (Windows: `%LOCALAPPDATA%\AgentHub`). Do not commit credentials, customer data, or generated media.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [SECURITY.md](./SECURITY.md).
'@
[IO.File]::WriteAllText((Join-Path $Destination 'README.md'), $publicReadme.TrimStart() + "`n", $utf8)

$publicDocsReadme = @'
# Documentation

Start with [development/quickstart.md](./development/quickstart.md).

## Architecture

- [architecture/control-plane-modules.md](./architecture/control-plane-modules.md) — path binding, host catalog, capability overlay.

## Development

- [development/setup.md](./development/setup.md) — environment requirements.
- [development/testing.md](./development/testing.md) — test layers.
- [development/skill-authoring-standard.md](./development/skill-authoring-standard.md) — skill shape.

## Operations

- [runbooks/sync-and-validate.md](./runbooks/sync-and-validate.md) — audit and deploy.

## Product

- [product/vision.md](./product/vision.md) — purpose and boundaries.
'@
[IO.File]::WriteAllText((Join-Path $Destination 'docs\README.md'), $publicDocsReadme.TrimStart() + "`n", $utf8)

$publicSetup = @'
# Setup

## Requirements

- Windows, macOS, or Linux.
- PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 works for many scripts on Windows only.
- Git.
- Node 18+ optional, for `npx agenthub` / `npm install -g .`.

No package install step is required for the PowerShell lifecycle: this repo is
scripts, registry JSON, and markdown.

## First run

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

See [quickstart.md](./quickstart.md).

## Local-only files (never commit)

- `agenthub.profile.json` — optional path pins (copy from `agenthub.profile.example.json`).
- `overlays/personal/` — private capability list and policy fragment (copy from `overlays/personal.example/`).
- OS local-data AgentHub runtime directory — drift JSON and generated workspaces.
'@
[IO.File]::WriteAllText((Join-Path $Destination 'docs\development\setup.md'), $publicSetup.TrimStart() + "`n", $utf8)

$publicAgents = @"
# AgentHub

Portable control plane for skills, plugins, MCP servers, and policy across coding agents.

- Read ``policy-core.md`` and ``docs/architecture/control-plane-modules.md``.
- Start with ``docs/development/quickstart.md``.
- Host destinations are ``{userHome}`` templates. ``scripts/lib/PathBinding.ps1`` materializes them for Windows, macOS, and Linux.
- Personal identity and local roots do not belong in this tree. Use ``overlays/personal/`` (from ``overlays/personal.example/``) and a gitignored ``agenthub.profile.json``.
"@
[IO.File]::WriteAllText((Join-Path $Destination 'AGENTS.md'), $publicAgents.Replace('``', '`'), $utf8)

# Public checkouts should not track a filled personal overlay.
$gitignorePath = Join-Path $Destination '.gitignore'
$gitignoreExtra = @"

# Personal overlay (copy from overlays/personal.example/). Never commit private capability lists.
overlays/personal/
"@
if (Test-Path -LiteralPath (Join-Path $repoRoot '.gitignore')) {
    $gi = [IO.File]::ReadAllText((Join-Path $repoRoot '.gitignore'))
    if ($gi -notmatch 'overlays/personal/') {
        $gi = $gi.TrimEnd() + "`n" + $gitignoreExtra.TrimStart() + "`n"
    }
    [IO.File]::WriteAllText($gitignorePath, $gi, $utf8)
} else {
    [IO.File]::WriteAllText($gitignorePath, $gitignoreExtra.TrimStart() + "`n", $utf8)
}

$banned = @('SaroshHussain', 'D:\OneDrive - MahumTech', 'D:\Local-AI', 'D:/Local-AI', 'MahumTech')
$scanRoots = @(
    (Join-Path $Destination 'scripts'),
    (Join-Path $Destination 'registry'),
    (Join-Path $Destination 'policy-core.md'),
    (Join-Path $Destination 'AGENTS.md'),
    (Join-Path $Destination 'README.md'),
    (Join-Path $Destination 'docs\architecture\control-plane-modules.md'),
    (Join-Path $Destination 'docs\development\quickstart.md'),
    (Join-Path $Destination 'docs\development\setup.md'),
    (Join-Path $Destination 'docs\README.md'),
    (Join-Path $Destination 'package.json')
)
$hits = [Collections.Generic.List[string]]::new()
foreach ($root in $scanRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $files = if ((Get-Item -LiteralPath $root).PSIsContainer) {
        Get-ChildItem -LiteralPath $root -Recurse -File
    } else {
        ,@(Get-Item -LiteralPath $root)
    }
    foreach ($file in $files) {
        if ($file.Length -gt 2MB) { continue }
        $text = [IO.File]::ReadAllText($file.FullName)
        foreach ($needle in $banned) {
            if ($text.Contains($needle)) {
                $relative = $file.FullName.Substring($Destination.Length).TrimStart('\')
                $hits.Add("$relative contains $needle")
            }
        }
    }
}
if ($hits.Count -gt 0) {
    throw ("Public core export contains personal residue:`n" + ($hits -join "`n"))
}

Write-Output "Exported public core to $Destination ($($privateIds.Count) private packages excluded)."
exit 0
