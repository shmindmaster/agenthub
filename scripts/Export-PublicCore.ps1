#Requires -Version 5.1
<#
.SYNOPSIS
    Write a public-core tree. Does not push and does not change remote visibility.

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

$overlayPath = Join-Path $repoRoot 'overlays\personal\overlay.json'
if (-not (Test-Path -LiteralPath $overlayPath)) {
    throw "Missing $overlayPath. The export uses it as the private-id list."
}
$overlay = Get-Content -LiteralPath $overlayPath -Raw -Encoding UTF8 | ConvertFrom-Json
$privateIds = @($overlay.enabledCapabilityIds | ForEach-Object { [string]$_ })
$privatePlugins = @($overlay.privateMarketplacePlugins | ForEach-Object { [string]$_ })

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
    'LICENSE', 'CONTRIBUTING.md', 'SECURITY.md', 'README.md',
    'policy-core.md', 'agenthub.profile.example.json',
    'scripts', 'registry', 'tests', 'docs', 'packages'
)) {
    Copy-ExportTree $name
}

foreach ($relative in @(
    '.agents\plugins\marketplace.json',
    '.claude-plugin\marketplace.json'
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
# tree ships none. The extraction plan itself landed and was deleted on
# 2026-09-13, so there is no longer a plan worth carrying across.
$planDir = Join-Path $Destination 'docs\plans\active'
if (Test-Path -LiteralPath $planDir) {
    Get-ChildItem -LiteralPath $planDir -File | Remove-Item -Force
}

$capabilitiesPath = Join-Path $Destination 'registry\capabilities.json'
$capabilities = Get-Content -LiteralPath $capabilitiesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities.capabilities = @(
    $capabilities.capabilities | Where-Object {
        -not ($_.PSObject.Properties['visibility'] -and [string]$_.visibility -eq 'private')
    }
)
[IO.File]::WriteAllText($capabilitiesPath, ($capabilities | ConvertTo-Json -Depth 40), $utf8)

function Remove-PrivateMarketplacePlugins {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $doc.PSObject.Properties['plugins']) { return }
    $doc.plugins = @($doc.plugins | Where-Object { [string]$_.name -notin $privatePlugins })
    [IO.File]::WriteAllText($Path, ($doc | ConvertTo-Json -Depth 20), $utf8)
}
Remove-PrivateMarketplacePlugins (Join-Path $Destination '.agents\plugins\marketplace.json')
Remove-PrivateMarketplacePlugins (Join-Path $Destination '.claude-plugin\marketplace.json')

$publicAgents = @"
# AgentHub

Portable control plane for skills, plugins, MCP servers, and policy across coding agents.

- Read ``policy-core.md`` and ``docs/architecture/control-plane-modules.md``.
- Host destinations are ``{userHome}`` templates. ``scripts/lib/PathBinding.ps1`` materializes them for Windows, macOS, and Linux.
- Personal identity and local roots do not belong in this tree. Use an overlay and a gitignored ``agenthub.profile.json``.
"@
[IO.File]::WriteAllText((Join-Path $Destination 'AGENTS.md'), $publicAgents.Replace('``', '`'), $utf8)

$banned = @('SaroshHussain', 'D:\OneDrive - MahumTech', 'D:\Local-AI', 'D:/Local-AI')
$scanRoots = @(
    (Join-Path $Destination 'scripts'),
    (Join-Path $Destination 'registry'),
    (Join-Path $Destination 'policy-core.md'),
    (Join-Path $Destination 'AGENTS.md'),
    (Join-Path $Destination 'docs\architecture\control-plane-modules.md')
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
