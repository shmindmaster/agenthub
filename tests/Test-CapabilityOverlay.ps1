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
. (Join-Path $PSScriptRoot 'lib\PrivateOverlay.ps1')

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
    param([Parameter(Mandatory)][string]$OverlayRoot)
    $previous = $env:AGENTHUB_OVERLAY
    try {
        # In the checkout that owns the overlay the default resolution must find
        # it with no override; from a linked worktree the overlay is reached
        # through the documented AGENTHUB_OVERLAY=<dir> override instead.
        $local = Join-Path $repoRoot 'overlays\personal'
        if ($OverlayRoot -ieq $local) {
            Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue
        } else {
            $env:AGENTHUB_OVERLAY = $OverlayRoot
        }
        $root = Get-AgentHubOverlayRoot -RepositoryRoot $repoRoot
        if (-not $root -or -not ([IO.Path]::GetFullPath($root).TrimEnd('') -ieq [IO.Path]::GetFullPath($OverlayRoot).TrimEnd(''))) {
            return @{ Passed = $false; Detail = "Get-AgentHubOverlayRoot resolved '$root', expected '$OverlayRoot'" }
        }
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
    param([Parameter(Mandatory)][string]$OverlayRoot)
    $core = Get-Content -LiteralPath (Join-Path $repoRoot 'policy-core.md') -Raw -Encoding UTF8
    if ($core -match 'Sarosh') {
        return @{ Passed = $false; Detail = 'policy-core.md contains owner identity' }
    }
    $fragment = Get-Content -LiteralPath (Join-Path $OverlayRoot 'policy-fragment.md') -Raw -Encoding UTF8
    if ($fragment -notmatch 'sarosh-communication') {
        return @{ Passed = $false; Detail = 'personal fragment does not route sarosh-communication' }
    }
    $compiled = Get-Content -LiteralPath (Join-Path $OverlayRoot 'global-agent-policy.md') -Raw -Encoding UTF8
    if ($compiled -notmatch 'sarosh-communication') {
        return @{ Passed = $false; Detail = 'compiled personal policy no longer routes sarosh-communication; this machine would deploy a weaker policy' }
    }
    return @{ Passed = $true; Detail = $null }
}

$overlay = Resolve-AgentHubTestOverlay -RepositoryRoot $repoRoot
if ($overlay.Root) {
    Write-Host "OVERLAY: $($overlay.Root) (resolved from $($overlay.Source))"
} else {
    Write-Host "SKIP: overlay-on and policy-fragment checks -- $($overlay.Reason)"
}

$behaviors = @(
    @{ Name = 'AGENTHUB_OVERLAY=off drops private capabilities'; NeedsOverlay = $false; Run = { Test-OverlayOffDropsPrivate } }
    @{ Name = 'overlay on keeps private capabilities in the effective graph'; NeedsOverlay = $true; Run = { Test-OverlayOnIncludesPrivate -OverlayRoot $overlay.Root } }
    @{ Name = 'policy-core has no owner identity and the compiled personal policy still does'; NeedsOverlay = $true; Run = { Test-PolicyCoreHasNoOwnerIdentity -OverlayRoot $overlay.Root } }
)
foreach ($behavior in $behaviors) {
    if ($behavior.NeedsOverlay -and -not $overlay.Root) { continue }
    $result = & $behavior.Run
    Report $behavior.Name ([bool]$result.Passed) ([string]$result.Detail)
}

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
