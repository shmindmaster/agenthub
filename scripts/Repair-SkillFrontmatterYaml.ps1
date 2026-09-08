#Requires -Version 5.1
<#
Quote unmanaged SKILL.md frontmatter that strict YAML parsers (Zed) reject.

Default target is the fleet master library (~/.agents/skills). Does not
rewrite AgentHub-managed skill directories unless you omit -SkipPaths.
Sync-Capabilities -Apply runs the same pass and skips managed destinations.

Run:
  pwsh -NoProfile -File scripts\Repair-SkillFrontmatterYaml.ps1
  pwsh -NoProfile -File scripts\Repair-SkillFrontmatterYaml.ps1 -Apply
#>
[CmdletBinding()]
param(
    [string]$SkillsRoot,
    [switch]$Apply,
    [string[]]$SkipPaths = @()
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SkillsRoot)) {
    $SkillsRoot = Join-Path $env:USERPROFILE '.agents\skills'
}

. (Join-Path $PSScriptRoot 'SkillFrontmatterYaml.ps1')

$result = Repair-SkillFrontmatterYamlDirectory -SkillsRoot $SkillsRoot -Apply:$Apply -SkipPaths $SkipPaths
$label = if ($Apply) { 'repaired' } else { 'needs-repair' }
foreach ($path in @($result.NeedsRepair)) {
    Write-Host "${label}: $path"
}

$remaining = if ($Apply) { 0 } else { @($result.NeedsRepair).Count }
Write-Output "PASS: skill-frontmatter-yaml scanned=$($result.Scanned) repaired=$($result.Repaired) needs-repair=$remaining apply=$Apply."
exit 0
