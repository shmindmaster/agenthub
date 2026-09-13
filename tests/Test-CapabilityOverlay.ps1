#Requires -Version 5.1
<#
The personal overlay is opt-in. With overlays/personal present, private
capabilities stay in the effective graph. AGENTHUB_OVERLAY=off drops them.
policy-core.md must not carry owner identity.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\lib\CapabilityGraph.ps1')

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

$capabilities = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function Test-OverlayOnIncludesPrivate {
    $previous = $env:AGENTHUB_OVERLAY
    try {
        Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue
        $root = Get-AgentHubOverlayRoot -RepositoryRoot $repoRoot
        $effective = @(Get-AgentHubEffectiveCapabilities -CapabilitiesDocument $capabilities -OverlayRoot $root)
        $ids = @($effective | ForEach-Object { [string]$_.id })
        if ($ids -notcontains 'sarosh-communication') {
            return @{ Passed = $false; Detail = 'overlay on dropped sarosh-communication' }
        }
        if ($ids -notcontains 'slack') {
            return @{ Passed = $false; Detail = 'overlay on dropped public capability slack' }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        if ($null -eq $previous) { Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue }
        else { $env:AGENTHUB_OVERLAY = $previous }
    }
}

function Test-OverlayOffDropsPrivate {
    $previous = $env:AGENTHUB_OVERLAY
    try {
        $env:AGENTHUB_OVERLAY = 'off'
        $root = Get-AgentHubOverlayRoot -RepositoryRoot $repoRoot
        if ($root) {
            return @{ Passed = $false; Detail = "AGENTHUB_OVERLAY=off still resolved '$root'" }
        }
        $effective = @(Get-AgentHubEffectiveCapabilities -CapabilitiesDocument $capabilities -OverlayRoot $root)
        $ids = @($effective | ForEach-Object { [string]$_.id })
        $leaked = @($ids | Where-Object { $_ -in @('sarosh-communication', 'sarosh-writing', 'sarosh-audio-voice', 'knowledge-access', 'local-ai', 'portfolio-engineering') })
        if ($leaked.Count -gt 0) {
            return @{ Passed = $false; Detail = "public graph still contains: $($leaked -join ', ')" }
        }
        if ($ids -notcontains 'slack') {
            return @{ Passed = $false; Detail = 'public graph dropped slack' }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        if ($null -eq $previous) { Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue }
        else { $env:AGENTHUB_OVERLAY = $previous }
    }
}

function Test-PolicyCoreHasNoOwnerIdentity {
    $core = Get-Content -LiteralPath (Join-Path $repoRoot 'policy-core.md') -Raw -Encoding UTF8
    if ($core -match 'Sarosh') {
        return @{ Passed = $false; Detail = 'policy-core.md contains owner identity' }
    }
    $fragment = Get-Content -LiteralPath (Join-Path $repoRoot 'overlays\personal\policy-fragment.md') -Raw -Encoding UTF8
    if ($fragment -notmatch 'sarosh-communication') {
        return @{ Passed = $false; Detail = 'personal fragment does not route sarosh-communication' }
    }
    $compiled = Get-Content -LiteralPath (Join-Path $repoRoot 'global-agent-policy.md') -Raw -Encoding UTF8
    if ($compiled -notmatch 'sarosh-communication') {
        return @{ Passed = $false; Detail = 'compiled personal policy no longer routes sarosh-communication; this machine would deploy a weaker policy' }
    }
    return @{ Passed = $true; Detail = $null }
}

$behaviors = @(
    @{ Name = 'overlay on keeps private capabilities in the effective graph'; Run = { Test-OverlayOnIncludesPrivate } }
    @{ Name = 'AGENTHUB_OVERLAY=off drops private capabilities'; Run = { Test-OverlayOffDropsPrivate } }
    @{ Name = 'policy-core has no owner identity and the compiled personal policy still does'; Run = { Test-PolicyCoreHasNoOwnerIdentity } }
)
foreach ($behavior in $behaviors) {
    $result = & $behavior.Run
    Report $behavior.Name ([bool]$result.Passed) ([string]$result.Detail)
}

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
