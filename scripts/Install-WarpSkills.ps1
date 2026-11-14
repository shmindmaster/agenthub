#Requires -Version 7
<#
.SYNOPSIS
Links AgentHub skills into ~/.warp/skills.

.DESCRIPTION
Warp cannot load a plugin, so skills are its only route. A skill from a package
is linked as a folder junction, so it follows the repository.

ah-product skills reach ../../scripts, ../../references and ../../kits, which
resolve to ~/.warp/<folder> from a linked skill, so those three are linked too.

LinkedIn is mapped to Warp in the registry but deliberately not
linked: each needs a local server Warp does not run under the plugin-only policy,
so their skills would dead-end.
tests/Test-InstallerPackageLists.ps1 holds the authoritative exclusion list with
a reason per entry, and fails if this array stops covering a mapped capability or
if an exclusion outlives its registry row.

.PARAMETER Audit
Report missing links without changing anything. Exits 1 when any are found.

.EXAMPLE
pwsh -NoProfile -File scripts/Install-WarpSkills.ps1 -Audit
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$WarpHome = (Join-Path $HOME '.warp'),
    [string]$PluginId,
    [switch]$Audit
)

$ErrorActionPreference = 'Stop'
function Get-AgentHubOverlayRootForWarp([string]$RepoRoot) {
    if ($env:AGENTHUB_OVERLAY -eq 'off') { return $null }
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTHUB_OVERLAY)) {
        $explicit = [System.IO.Path]::GetFullPath($env:AGENTHUB_OVERLAY).TrimEnd('\', '/')
        if (Test-Path -LiteralPath $explicit) { return $explicit }
        return $null
    }
    $default = Join-Path $RepoRoot 'overlays\personal'
    if (Test-Path -LiteralPath $default) { return $default }
    $sibling = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/'))) 'agenthub-private'
    if (Test-Path -LiteralPath (Join-Path $sibling 'overlay.json')) { return $sibling }
    return $null
}

$packages = @(
    'packages/product', 'packages/media-studio', 'packages/assemblyai',
    
    'packages/browser', 'packages/coding-agent-dispatch', 'packages/funding'
)
# Private packages: prefer checkout overlays/personal, else sibling agenthub-private clone.
$overlayRoot = Get-AgentHubOverlayRootForWarp $Root
foreach ($privatePkg in @('sarosh', 'docwise')) {
    $candidates = @()
    if ($overlayRoot) { $candidates += (Join-Path $overlayRoot "packages\$privatePkg") }
    $candidates += (Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($Root).TrimEnd('\', '/'))) "agenthub-private\packages\$privatePkg")
    $resolved = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($resolved) {
        $packages += ([IO.Path]::GetRelativePath($Root, $resolved)).Replace('\', '/')
    }
}

if ($PluginId) {
    $packages = @($packages | Where-Object { (Split-Path -Leaf $_) -eq $PluginId })
    if (-not $packages.Count) { throw "No supported skill links for '$PluginId'." }
}
$links = [System.Collections.Generic.List[object]]::new()
foreach ($package in $packages) {
    $skills = Join-Path $Root "$package/skills"
    if (-not (Test-Path -LiteralPath $skills)) { continue }
    foreach ($skill in Get-ChildItem -LiteralPath $skills -Directory) {
        if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md'))) { continue }
        $links.Add([pscustomobject]@{ Path = Join-Path $WarpHome "skills/$($skill.Name)"; Target = $skill.FullName })
    }
}
if (-not $PluginId -or $PluginId -eq 'product') {
    foreach ($folder in 'scripts', 'references', 'kits') {
        $links.Add([pscustomobject]@{ Path = Join-Path $WarpHome $folder; Target = Join-Path $Root "packages/product/$folder" })
    }
}

$problems = 0
foreach ($link in $links) {
    $item = Get-Item -LiteralPath $link.Path -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        if ([IO.Path]::GetFullPath($item.Target) -eq [IO.Path]::GetFullPath($link.Target)) { continue }
        Write-Output "wrong target: $($link.Path)"
        $problems++
        continue
    }
    if ($item) {
        Write-Output "not a link, left alone: $($link.Path)"
        $problems++
        continue
    }
    if ($Audit) {
        Write-Output "missing: $($link.Path)"
        $problems++
        continue
    }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $link.Path))
    [void](New-Item -ItemType Junction -Path $link.Path -Target $link.Target)
    Write-Output "linked: $($link.Path)"
}

Write-Output "$($links.Count) links checked, $problems problem(s)."
if ($problems) { exit 1 }
