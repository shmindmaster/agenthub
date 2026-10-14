#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\lib\CapabilityGraph.ps1')
. (Join-Path $repoRoot 'scripts\lib\SyncOrchestrator.ps1')

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

function New-FakeLinkedCheckout {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [switch]$WithPrimaryOverlay
    )
    $primary = Join-Path $BasePath 'primary'
    $worktree = Join-Path $BasePath 'worktree'
    $primaryGitDir = Join-Path $primary '.git'
    $worktreeGitDir = Join-Path $primaryGitDir 'worktrees\x'
    New-Item -ItemType Directory -Path $worktreeGitDir -Force | Out-Null
    New-Item -ItemType Directory -Path $worktree -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree '.git') -Value "gitdir: $worktreeGitDir" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $worktreeGitDir 'commondir') -Value '../..' -Encoding UTF8
    if ($WithPrimaryOverlay) {
        $overlay = Join-Path $primary 'overlays\personal'
        New-Item -ItemType Directory -Path $overlay -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $overlay 'overlay.json') -Value '{"enabledCapabilityIds":[]}' -Encoding UTF8
    }
    return [pscustomobject]@{ Primary = $primary; Worktree = $worktree }
}

function Test-ResolvedPath {
    param([string]$Actual, [string]$Expected)
    return $Actual -and ([IO.Path]::GetFullPath($Actual).TrimEnd('\', '/') -ieq [IO.Path]::GetFullPath($Expected).TrimEnd('\', '/'))
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-overlay-worktree-" + [guid]::NewGuid().ToString('N'))
$previousOverlay = $env:AGENTHUB_OVERLAY
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null

    $linked = New-FakeLinkedCheckout -BasePath (Join-Path $scratch 'linked') -WithPrimaryOverlay
    Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue
    $root = Get-AgentHubOverlayRoot -RepositoryRoot $linked.Worktree
    Report 'linked worktree resolves overlay from primary checkout' `
        (Test-ResolvedPath $root (Join-Path $linked.Primary 'overlays\personal')) `
        "resolved '$root'"

    $messages = @(& {
        $null = Get-AgentHubOverlayRoot -RepositoryRoot $linked.Worktree -ReportPrimaryCheckout
    } 6>&1 | ForEach-Object { [string]$_ })
    Report 'primary overlay resolution reports one path line' `
        ($messages.Count -eq 1 -and $messages[0] -like "OVERLAY: * (primary checkout)") `
        "reported $($messages.Count) line(s): $($messages -join '; ')"

    $syncSteps = @(Get-AgentHubSyncStepDefinitions -RepositoryRoot $linked.Worktree -UserProfile $scratch)
    $reportingSteps = @($syncSteps | Where-Object { $_.Args -notcontains '-QuietOverlayResolution' })
    Report 'orchestrated sync reports its primary overlay only once' `
        ($syncSteps.Count -eq 4 -and $reportingSteps.Count -eq 1) `
        "sync steps=$($syncSteps.Count); reporting steps=$($reportingSteps.Count)"

    $applySteps = @(Get-AgentHubSyncStepDefinitions -RepositoryRoot $linked.Worktree -UserProfile $scratch -ApplyMode)
    $applyReportingSteps = @($applySteps | Where-Object { $_.Args -notcontains '-QuietOverlayResolution' })
    Report 'apply sync leaves the single overlay report to validation' `
        ($applySteps.Count -eq 4 -and $applyReportingSteps.Count -eq 0) `
        "apply steps=$($applySteps.Count); reporting steps=$($applyReportingSteps.Count)"

    $privatePackage = Join-Path $root 'packages\fixture-private'
    New-Item -ItemType Directory -Path $privatePackage -Force | Out-Null
    $capability = [pscustomobject]@{
        id = 'fixture-private'
        visibility = 'private'
        canonicalSource = 'overlays/personal/packages/fixture-private'
    }
    $packageRoot = Resolve-AgentHubPackageRoot -RepositoryRoot $linked.Worktree `
        -Capability $capability -OverlayRoot $root
    Report 'private package path is rebased onto the resolved overlay' `
        (Test-ResolvedPath $packageRoot $privatePackage) "resolved '$packageRoot'"

    $explicit = Join-Path $scratch 'explicit-overlay'
    New-Item -ItemType Directory -Path $explicit -Force | Out-Null
    $env:AGENTHUB_OVERLAY = $explicit
    $root = Get-AgentHubOverlayRoot -RepositoryRoot $linked.Worktree
    Report 'explicit AGENTHUB_OVERLAY directory takes precedence' `
        (Test-ResolvedPath $root $explicit) "resolved '$root'"

    $env:AGENTHUB_OVERLAY = 'off'
    $root = Get-AgentHubOverlayRoot -RepositoryRoot $linked.Worktree
    Report 'AGENTHUB_OVERLAY=off disables the overlay' `
        ($null -eq $root) "resolved '$root'"

    Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue
    $root = Get-AgentHubOverlayRoot -RepositoryRoot $linked.Primary
    Report 'primary checkout resolves its local overlay' `
        (Test-ResolvedPath $root (Join-Path $linked.Primary 'overlays\personal')) `
        "resolved '$root'"

    $absent = New-FakeLinkedCheckout -BasePath (Join-Path $scratch 'absent')
    $root = $null
    $threw = $false
    try { $root = Get-AgentHubOverlayRoot -RepositoryRoot $absent.Worktree }
    catch { $threw = $true }
    Report 'missing overlays anywhere return null without throwing' `
        (-not $threw -and $null -eq $root) "threw=$threw; resolved '$root'"

    $malformed = Join-Path $scratch 'malformed'
    New-Item -ItemType Directory -Path $malformed -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $malformed 'worktree') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $malformed 'worktree\.git') -Value 'not a gitdir file' -Encoding UTF8
    $root = $null
    $threw = $false
    try { $root = Get-AgentHubOverlayRoot -RepositoryRoot (Join-Path $malformed 'worktree') }
    catch { $threw = $true }
    Report 'malformed .git metadata returns null without throwing' `
        (-not $threw -and $null -eq $root) "threw=$threw; resolved '$root'"

    $missingCommon = New-FakeLinkedCheckout -BasePath (Join-Path $scratch 'missing-commondir')
    Remove-Item -LiteralPath (Join-Path $missingCommon.Primary '.git\worktrees\x\commondir')
    $root = $null
    $threw = $false
    try { $root = Get-AgentHubOverlayRoot -RepositoryRoot $missingCommon.Worktree }
    catch { $threw = $true }
    Report 'missing commondir returns null without throwing' `
        (-not $threw -and $null -eq $root) "threw=$threw; resolved '$root'"
} finally {
    if ($null -eq $previousOverlay) { Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue }
    else { $env:AGENTHUB_OVERLAY = $previousOverlay }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
