#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot = 'C:\Repos\shmindmaster\agenthub',
    [string]$UserProfilePath = $env:USERPROFILE,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$rows = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]
$agentsPath = Join-Path $RegistryRoot 'registry\agents.json'
$policyPath = Join-Path $RegistryRoot 'docs\worktree-management-policy.md'

if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
    Write-Error "Missing agent registry: $agentsPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    Write-Error "Missing worktree policy: $policyPath"
    exit 1
}

try {
    $registry = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error 'Agent registry is invalid JSON.'
    exit 1
}

foreach ($agent in @($registry.activeAgents)) {
    $installed = $false
    if ($agent.executable) {
        $installed = Test-Path -LiteralPath ([string]$agent.executable) -PathType Leaf
        if (-not $installed) {
            $commandName = [System.IO.Path]::GetFileNameWithoutExtension([string]$agent.executable)
            $installed = $null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)
        }
    }

    $instructions = $null
    if ($agent.nativePaths -and $agent.nativePaths.PSObject.Properties.Match('instructions').Count -gt 0) {
        $instructions = [string]$agent.nativePaths.instructions
    }

    $policyPointer = 'not-required'
    if ($instructions) {
        if (-not $instructions -or -not (Test-Path -LiteralPath $instructions -PathType Leaf)) {
            $policyPointer = 'missing-instruction-file'
            $failures.Add("$($agent.id): instruction file missing")
        } else {
            $instructionRaw = Get-Content -LiteralPath $instructions -Raw -Encoding UTF8
            if ($instructionRaw.Contains($policyPath)) {
                $policyPointer = 'present'
            } else {
                $policyPointer = 'missing-policy-pointer'
                $failures.Add("$($agent.id): worktree policy pointer missing")
            }
        }
    }

    $rows.Add([pscustomobject]@{
        id = [string]$agent.id
        name = [string]$agent.name
        installed = $installed
        instructionFile = if ($instructions) { Test-Path -LiteralPath $instructions -PathType Leaf } else { $null }
        worktreePolicy = $policyPointer
    })
}

$summary = [ordered]@{
    registered = $rows.Count
    installed = @($rows | Where-Object installed).Count
    optionalMissing = @($rows | Where-Object { -not $_.installed }).Count
    policyFailures = $failures.Count
}

if ($Json) {
    [ordered]@{ summary = $summary; hosts = @($rows); failures = @($failures) } | ConvertTo-Json -Depth 5
} else {
    $rows | Format-Table id, name, installed, instructionFile, worktreePolicy -AutoSize
    Write-Output "Summary: registered=$($summary.registered) installed=$($summary.installed) optionalMissing=$($summary.optionalMissing) policyFailures=$($summary.policyFailures)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0

