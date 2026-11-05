#Requires -Version 7
<#
.SYNOPSIS
Copies AgentHub plugins into ~/.cursor/plugins/local as real folders.

.DESCRIPTION
Cursor IDE and Cursor Agent share one loader. It skips any link in that folder
whose target is outside the folder, and on Windows a junction counts as a link,
so a linked package never loads. Cursor logs each one as
"loadUserLocalPlugin <name> rejected: symlink target ... is outside ...".

Copies do not follow the repository, so rerun this after a package changes.
Only folders named after a managed plugin are touched. Everything else stays.

.PARAMETER Audit
Report links, missing plugins and stale copies without changing anything.
Exits 1 when any are found.

.EXAMPLE
pwsh -NoProfile -File scripts/Install-CursorLocalPlugins.ps1 -Audit
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$Target = (Join-Path $HOME '.cursor/plugins/local'),
    [string[]]$PackagePaths,
    [switch]$Audit
)

$ErrorActionPreference = 'Stop'
$skipNames = @('.git', 'node_modules', '__pycache__', '.venv')

function Get-CursorPackagePaths([string]$RepoRoot) {
    $files = @('registry/capabilities.json', 'overlays/personal/capabilities.json') | ForEach-Object { Join-Path $RepoRoot $_ }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $document = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($capability in @($document.capabilities)) {
            $mapping = @($capability.hostMappings) | Where-Object { $_.hostId -eq 'cursor' -and $_.deploymentStatus -eq 'native-local-plugin' }
            if (-not $mapping) { continue }
            # canonicalSource is relative to the repository root in both registries.
            Join-Path $RepoRoot ([string]$capability.canonicalSource)
        }
    }
}

function Get-PackageFiles([string]$Path) {
    $base = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
    Get-ChildItem -LiteralPath $base -Recurse -File -Force |
        Where-Object {
            $parts = $_.FullName.Substring($base.Length + 1) -split '[\\/]'
            -not ($parts | Where-Object { $_ -in $skipNames })
        } |
        ForEach-Object {
            [pscustomobject]@{
                Relative = $_.FullName.Substring($base.Length + 1).Replace('\', '/')
                FullName = $_.FullName
            }
        }
}

function Test-CopyCurrent([string]$Source, [string]$Copy) {
    $wanted = @(Get-PackageFiles $Source)
    $found = @(Get-PackageFiles $Copy)
    if ($wanted.Count -ne $found.Count) { return $false }
    $foundByPath = @{}
    foreach ($file in $found) { $foundByPath[$file.Relative] = $file.FullName }
    foreach ($file in $wanted) {
        if (-not $foundByPath.ContainsKey($file.Relative)) { return $false }
        $left = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $right = (Get-FileHash -LiteralPath $foundByPath[$file.Relative] -Algorithm SHA256).Hash
        if ($left -ne $right) { return $false }
    }
    return $true
}

function Copy-Package([string]$Source, [string]$Destination) {
    foreach ($file in @(Get-PackageFiles $Source)) {
        $path = Join-Path $Destination ($file.Relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::Copy($file.FullName, $path, $true)
    }
}

$packages = if ($PackagePaths) { $PackagePaths } else { @(Get-CursorPackagePaths $Root) }
if (-not $packages) { throw 'No Cursor packages found in the registry.' }
if (-not $Audit) { [void][IO.Directory]::CreateDirectory($Target) }

$problems = 0
$staging = Join-Path (Split-Path -Parent $Target) '.ah-staging'
foreach ($package in $packages) {
    $manifest = Get-Content -LiteralPath (Join-Path $package 'plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $name = [string]$manifest.name
    if ($name -notmatch '^[a-z0-9][a-z0-9-]*$') { throw "Unsafe plugin name '$name' in $package" }
    $destination = Join-Path $Target $name
    $item = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    $isLink = [bool]($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))

    $state = if (-not $item) { 'missing' }
    elseif ($isLink) { 'link' }
    elseif (Test-CopyCurrent $package $destination) { 'current' }
    else { 'stale' }

    if ($Audit -or $state -eq 'current') {
        Write-Output ('{0,-20} {1}' -f $name, $state)
        if ($state -ne 'current') { $problems++ }
        continue
    }

    $stage = Join-Path $staging $name
    if (Test-Path -LiteralPath $stage) { [IO.Directory]::Delete($stage, $true) }
    Copy-Package $package $stage
    # A link is removed on its own, never recursively, so its target stays intact.
    if ($isLink) { [IO.Directory]::Delete($destination, $false) }
    elseif ($item) { [IO.Directory]::Delete($destination, $true) }
    [IO.Directory]::Move($stage, $destination)
    Write-Output ('{0,-20} installed ({1})' -f $name, $state)
}
if (Test-Path -LiteralPath $staging) { [IO.Directory]::Delete($staging, $true) }

if ($Audit -and $problems) {
    Write-Output "$problems plugin(s) need installing. Rerun without -Audit."
    exit 1
}
