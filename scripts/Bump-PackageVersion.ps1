#Requires -Version 5.1
<#
.SYNOPSIS
  Bump a package version with root plugin.json as the single authority.

.DESCRIPTION
  AgentHub treats packages/<id>/plugin.json as the portable Agent Plugins floor
  and the version authority. Host projections (.claude-plugin, .codex-plugin,
  .cursor-plugin, .qoder-plugin) must carry the same version string.

  This script updates those manifests together. It does not recompute
  contentHash or edit registry/capabilities.json — run RegistryContentHash.ps1
  and update the capability entry after content changes, as today.

.EXAMPLE
  pwsh -NoProfile -File scripts/Bump-PackageVersion.ps1 -Package media-studio -Version 1.5.7
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Version,
    [string]$RepositoryRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
$packageRoot = Join-Path $root "packages/$Package"
if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    throw "Package directory not found: $packageRoot"
}
if ($Version -notmatch '^\d+\.\d+\.\d+([.-][0-9A-Za-z.-]+)?$') {
    throw "Version '$Version' is not a simple semver-like string (expected N.N.N)."
}

$hostDirs = @('.claude-plugin', '.codex-plugin', '.cursor-plugin', '.qoder-plugin')
$schema = 'https://agentplugins.org/schemas/1.0.0/plugin.schema.json'
$rootManifestPath = Join-Path $packageRoot 'plugin.json'

function Read-JsonFile([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 20
    # PowerShell's ConvertTo-Json is lossy for property order; acceptable for bumps.
    [IO.File]::WriteAllText($Path, ($json.TrimEnd() + "`n"))
}

# Build / update portable root first — it is the authority.
if (Test-Path -LiteralPath $rootManifestPath) {
    $rootManifest = Read-JsonFile -Path $rootManifestPath
} else {
    $rootManifest = [pscustomobject]@{ name = $Package }
}
$previousVersion = [string]$rootManifest.version
$rootHash = @{}
foreach ($p in $rootManifest.PSObject.Properties) { $rootHash[$p.Name] = $p.Value }
$rootHash['$schema'] = $schema
if (-not $rootHash.ContainsKey('name') -or [string]::IsNullOrWhiteSpace([string]$rootHash['name'])) {
    $rootHash['name'] = $Package
}
$rootHash['version'] = $Version
if (-not $rootHash.ContainsKey('description')) {
    foreach ($hostDir in $hostDirs) {
        $hostPath = Join-Path $packageRoot "$hostDir/plugin.json"
        if (Test-Path -LiteralPath $hostPath) {
            $hostObj = Read-JsonFile -Path $hostPath
            if ($hostObj.description) { $rootHash['description'] = [string]$hostObj.description; break }
        }
    }
}
# Ordered portable fields first.
$portable = [ordered]@{
    '$schema'   = $schema
    name        = [string]$rootHash['name']
    version     = $Version
    description = [string]$rootHash['description']
}
foreach ($extra in @('author', 'license', 'keywords', 'homepage', 'repository')) {
    if ($rootHash.ContainsKey($extra) -and $null -ne $rootHash[$extra]) {
        $portable[$extra] = $rootHash[$extra]
    }
}
Write-JsonFile -Path $rootManifestPath -Object ([pscustomobject]$portable)
Write-Host "updated $Package/plugin.json -> $Version"

$updated = @('plugin.json')
foreach ($hostDir in $hostDirs) {
    $hostPath = Join-Path $packageRoot "$hostDir/plugin.json"
    if (-not (Test-Path -LiteralPath $hostPath)) { continue }
    $hostObj = Read-JsonFile -Path $hostPath
    $hostObj | Add-Member -NotePropertyName version -NotePropertyValue $Version -Force
    Write-JsonFile -Path $hostPath -Object $hostObj
    $updated += "$hostDir/plugin.json"
    Write-Host "updated $Package/$hostDir/plugin.json -> $Version"
}

# A deployable kit (media-studio) carries the release version in more files than the plugin manifests, and the package
# tests require every one to equal plugin.json: kit/package.json, kit/package-lock.json (root and packages[""]) and
# kit/scene-archetypes.json. Only those version lines are rewritten, so each file keeps its layout; each is re-read and
# checked afterwards, and a file whose layout does not match fails the bump instead of being left stale.
function Set-ReleaseVersionLines([string]$RelativePath, [int]$Count, [scriptblock]$Check) {
    $path = Join-Path $packageRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return }
    $raw = [IO.File]::ReadAllText($path)
    $pattern = [regex]'(?m)^(\s*"version"\s*:\s*")[^"]*(")'
    if ($pattern.Matches($raw).Count -lt $Count) { throw "$RelativePath has fewer than $Count version fields: $path" }
    $next = $pattern.Replace($raw, "`${1}$Version`${2}", $Count)
    # Checked on the text: Windows PowerShell's ConvertFrom-Json rejects the lockfile's empty-string key (packages[""]).
    if (-not (& $Check $next)) { throw "$RelativePath would not carry release $Version after the bump: $path" }
    [IO.File]::WriteAllText($path, $next, [Text.UTF8Encoding]::new($false))
    $script:updated += $RelativePath
    Write-Host "updated $Package/$RelativePath -> $Version"
}
$v = [regex]::Escape($Version)
Set-ReleaseVersionLines 'kit/package.json' 1 { param($t) $t -match "(?m)^\{\s*(""[^""]+""\s*:\s*""[^""]*"",\s*)*""version""\s*:\s*""$v""" }
# npm lockfile v3: the first two version lines are the root and packages[""] (the package itself), before any dependency.
Set-ReleaseVersionLines 'kit/package-lock.json' 2 { param($t) $t -match "^\{\s*""name""\s*:\s*""[^""]*"",\s*""version""\s*:\s*""$v""" -and $t -match """packages""\s*:\s*\{\s*""""\s*:\s*\{[^{}]*?""version""\s*:\s*""$v""" }
Set-ReleaseVersionLines 'kit/scene-archetypes.json' 1 { param($t) $t -match "^\{\s*""version""\s*:\s*""$v""" }

# Skills that pin the release they verify against (media-studio-compose checks the runtime kit with -ne '<version>').
# Only the previous release's own pins are rewritten: quoted '<old>', "<old> release", "verified <old>", "Studio <old>".
if ($previousVersion -and $previousVersion -ne $Version) {
    $old = [regex]::Escape($previousVersion)
    $pins = [regex]"('$old')|($old(?= release))|((?<=verified )$old)|((?<=Studio )$old)"
    foreach ($skill in @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'skills') -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue)) {
        $raw = [IO.File]::ReadAllText($skill.FullName)
        if (-not $pins.IsMatch($raw)) { continue }
        $next = $pins.Replace($raw, { param($m) $m.Value.Replace($previousVersion, $Version) })
        [IO.File]::WriteAllText($skill.FullName, $next, [Text.UTF8Encoding]::new($false))
        $rel = $skill.FullName.Substring($packageRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $updated += $rel
        Write-Host "updated release pins in $Package/$rel -> $Version"
    }
}

Write-Host ""
Write-Host "Version authority is packages/$Package/plugin.json ($Version)."
Write-Host "Updated: $($updated -join ', ')"
Write-Host "Next: recompute contentHash if package content changed, then Validate-AgentHub.ps1."
