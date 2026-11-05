#Requires -Version 7
<#
.SYNOPSIS
Links AgentHub skills into ~/.warp/skills.

.DESCRIPTION
Warp cannot load a plugin, so skills are its only route. A skill from a package
is linked as a folder junction, so it follows the repository.

ah-product skills reach ../../scripts, ../../references and ../../kits, which
resolve to ~/.warp/<folder> from a linked skill, so those three are linked too.

ah-aws and RepoWise are left out because each needs a local server Warp does not
run under the plugin-only policy, and their skills would dead-end.

.PARAMETER Audit
Report missing links without changing anything. Exits 1 when any are found.

.EXAMPLE
pwsh -NoProfile -File scripts/Install-WarpSkills.ps1 -Audit
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$WarpHome = (Join-Path $HOME '.warp'),
    [switch]$Audit
)

$ErrorActionPreference = 'Stop'
$packages = @(
    'packages/product', 'packages/media-studio', 'packages/brave-search', 'packages/daytona', 'packages/assemblyai',
    'packages/railway', 'packages/descript', 'packages/exa', 'packages/notion', 'packages/firecrawl',
    'packages/browser', 'overlays/personal/packages/sarosh'
)

$links = [System.Collections.Generic.List[object]]::new()
foreach ($package in $packages) {
    $skills = Join-Path $Root "$package/skills"
    if (-not (Test-Path -LiteralPath $skills)) { continue }
    foreach ($skill in Get-ChildItem -LiteralPath $skills -Directory) {
        if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md'))) { continue }
        $links.Add([pscustomobject]@{ Path = Join-Path $WarpHome "skills/$($skill.Name)"; Target = $skill.FullName })
    }
}
foreach ($folder in 'scripts', 'references', 'kits') {
    $links.Add([pscustomobject]@{ Path = Join-Path $WarpHome $folder; Target = Join-Path $Root "packages/product/$folder" })
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
