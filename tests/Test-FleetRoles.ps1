#Requires -Version 5.1
<#
Behavior tests for the six-host authority contract (SH-4669): the real registry
satisfies it, and synthetic registries that add an unknown role, a seventh
retained host, a mis-owned companion, a demoted family or a missing role are rejected.
A retired-labelled host may be moved back to active (owner direction 2026-11-13: roles are labels, not blocks).
Run: pwsh -NoProfile -File tests/Test-FleetRoles.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\lib\FleetRoles.ps1')
$failures = 0
function Report([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green } else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures++ }
}
function New-Registry { Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
function Find-Host($r, $id) { @($r.activeAgents + $r.inactiveAgents) | Where-Object { $_.id -eq $id } | Select-Object -First 1 }

$real = @(Test-AgentFleetRoles -Agents (New-Registry))
Report 'real registry satisfies the contract' ($real.Count -eq 0) ($real -join '; ')

$r = New-Registry; (Find-Host $r 'cline').fleetRole = 'friend'
$e = @(Test-AgentFleetRoles -Agents $r)
Report 'unknown role is rejected' (($e -join ';') -match "unknown fleetRole 'friend': cline")

$r = New-Registry; (Find-Host $r 'cline').fleetRole = 'retained'
$e = @(Test-AgentFleetRoles -Agents $r)
Report 'seventh retained host is rejected' (($e -join ';') -match 'not one of the six families: cline')

$r = New-Registry; (Find-Host $r 'kilo').fleetRole = 'pending-retirement'
$e = @(Test-AgentFleetRoles -Agents $r)
Report 'demoting a retained family is rejected' (($e -join ';') -match 'not marked retained: kilo')

# SH-4969 (owner direction 2026-11-19): Devin is a first-class retained agent.
$r = New-Registry
Report 'devin is recorded as retained' ([string](Find-Host $r 'devin').fleetRole -eq 'retained') ([string](Find-Host $r 'devin').fleetRole)
(Find-Host $r 'devin').fleetRole = 'pending-retirement'
$e = @(Test-AgentFleetRoles -Agents $r)
Report 'demoting devin is rejected' (($e -join ';') -match 'not marked retained: devin')

$r = New-Registry; (Find-Host $r 'opencode-desktop').fleetOwner = 'cline'
$e = @(Test-AgentFleetRoles -Agents $r)
Report 'companion owned by a non-retained host is rejected' (($e -join ';') -match 'companion surface must name a retained fleetOwner')


$r = New-Registry; $h = Find-Host $r 'windsurf'; $r.inactiveAgents = @($r.inactiveAgents | Where-Object { $_.id -ne 'windsurf' }); $r.activeAgents = @($r.activeAgents) + $h
$e = @(Test-AgentFleetRoles -Agents $r)
Report 'a retired-labelled host may be reactivated' ($e.Count -eq 0) ($e -join '; ')

$r = New-Registry; (Find-Host $r 'amp').PSObject.Properties.Remove('fleetRole')
$e = @(Test-AgentFleetRoles -Agents $r)
Report 'host with no role is rejected' (($e -join ';') -match 'no fleetRole: amp')

Write-Host "RESULT: $($script:failures -eq 0) failures=$script:failures"
if ($failures -gt 0) { exit 1 } else { exit 0 }

