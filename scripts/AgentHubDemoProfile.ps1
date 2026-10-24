#Requires -Version 5.1
<#
.SYNOPSIS
    A throwaway AgentHub profile for on-camera audit -> apply -> audit demos.

.DESCRIPTION
    Creates, drives, and destroys a scratch profile that is isolated from the
    real fleet, so Sync-Instructions.ps1 can be filmed reporting drift, fixing
    it, and reporting clean, around a one-line policy edit, without touching
    any real host file.

    Layout under -Root (default %LOCALAPPDATA%\AgentHub\demo\agenthub-profile):
        .agenthub-demo-profile.json   marker that Remove verifies before deleting
        repo\registry\agents.json     snapshot of this checkout's host catalog
        repo\policy-core.md           the PUBLIC portable policy (no owner identity)
        home\                         the throwaway user profile hosts are written into

    Every Sync-Instructions call passes -RepositoryRoot <Root>\repo and
    -UserProfile <Root>\home with AGENTHUB_OVERLAY=off, so the private overlay
    and the compiled personal policy never enter the profile, and staging is
    rerouted under <Root>\home (Get-AgentHubIsolatedLocalData). Output is
    printed with the invoking user's home cropped to '~' unless -NoCrop.

    Actions:
        New         create (or reset) the profile; deterministic for a commit
        Audit       Sync-Instructions -Audit against the profile
        Apply       Sync-Instructions -Apply against the profile
        EditPolicy  append ONE line to the profile's policy-core.md (idempotent)
        Diff        print the profile policy's lines that differ from the checkout
        Remove      delete the profile after verifying its marker

    Refusals: the profile root may not be, contain, or sit above the real user
    profile, may not be a drive root, and an existing directory without this
    script's marker is never reset or removed. Nothing here registers a
    service, task, or auto-start; child processes inherit this hidden console.

.EXAMPLE
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action New
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Apply
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action EditPolicy
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Apply
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
    pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Remove
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('New', 'Audit', 'Apply', 'EditPolicy', 'Diff', 'Remove')]
    [string]$Action,
    [string]$Root,
    [switch]$NoCrop
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\', '/')
. (Join-Path $PSScriptRoot 'lib\DisplayPath.ps1')

$MarkerName = '.agenthub-demo-profile.json'
$MarkerSchema = 'agenthub-demo-profile/1'
# The one-line scratch policy edit (AH2). Fixed text, so every run is the same.
$DemoPolicyLine = '- Demo profile rule: every on-camera sync runs against a throwaway profile, never the real fleet.'

$realHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
if ([string]::IsNullOrWhiteSpace($realHome)) { throw 'Cannot resolve the invoking user profile; refusing to guess what "real" means.' }
$realHome = [IO.Path]::GetFullPath($realHome).TrimEnd('\', '/')

if ([string]::IsNullOrWhiteSpace($Root)) {
    $localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }
    $Root = Join-Path $localData 'AgentHub\demo\agenthub-profile'
}
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$markerPath = Join-Path $Root $MarkerName
$profileRepo = Join-Path $Root 'repo'
$profileHome = Join-Path $Root 'home'
$profilePolicy = Join-Path $profileRepo 'policy-core.md'

function Write-Display([string]$Text) {
    if ($NoCrop) { Write-Host $Text } else { Write-Host (Format-AgentHubDisplayText -Text $Text -HomePath $realHome) }
}

function Stop-Demo([string]$Message) {
    # Refusals are on camera too: crop them like every other line.
    if ($NoCrop) { throw $Message }
    throw (Format-AgentHubDisplayText -Text $Message -HomePath $realHome)
}

function Test-IsSameOrUnder([string]$Child, [string]$Parent) {
    $c = $Child.TrimEnd('\', '/'); $p = $Parent.TrimEnd('\', '/')
    return $c.Equals($p, [StringComparison]::OrdinalIgnoreCase) -or
        $c.StartsWith($p + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-SafeRoot {
    if ([IO.Path]::GetPathRoot($Root).TrimEnd('\', '/') -ieq $Root) {
        Stop-Demo "Refusing a drive root as the demo profile: $Root"
    }
    if (Test-IsSameOrUnder $realHome $Root) {
        Stop-Demo "Refusing '$Root': it is, or contains, the real user profile '$realHome'. The demo profile must be a scratch directory."
    }
    if (Test-IsSameOrUnder $Root $repoRoot) {
        Stop-Demo "Refusing '$Root': it is inside this checkout. The demo profile must never be written into a repository."
    }
    # Host config roots under the real profile are the real fleet.
    foreach ($fleetDir in @('.claude', '.codex', '.agents', '.gemini', '.cursor', '.config', '.copilot', '.grok', '.factory', '.cline', '.codeium', '.warp', 'AppData\Roaming')) {
        if (Test-IsSameOrUnder $Root (Join-Path $realHome $fleetDir)) {
            Stop-Demo "Refusing '$Root': it is inside a real host configuration root ($fleetDir)."
        }
    }
}

function Get-Marker {
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { return $null }
    $m = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$m.schema -ne $MarkerSchema) { return $null }
    if (-not ([IO.Path]::GetFullPath([string]$m.root).TrimEnd('\', '/')).Equals($Root, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $m
}

function Assert-Profile {
    Assert-SafeRoot
    if (-not (Get-Marker)) {
        Stop-Demo "No AgentHub demo profile at '$Root'. Run -Action New first."
    }
}

function Remove-Profile {
    Assert-SafeRoot
    if (-not (Test-Path -LiteralPath $Root)) { return $false }
    if (-not (Get-Marker)) {
        Stop-Demo "Refusing to delete '$Root': it has no $MarkerName written by this script for this exact path."
    }
    Remove-Item -LiteralPath $Root -Recurse -Force
    return $true
}

function Invoke-ProfileSync([string]$Mode) {
    Assert-Profile
    $sync = Join-Path $PSScriptRoot 'Sync-Instructions.ps1'
    $hostExe = (Get-Process -Id $PID).Path
    $previousOverlay = $env:AGENTHUB_OVERLAY
    $previousEap = $ErrorActionPreference
    try {
        $env:AGENTHUB_OVERLAY = 'off'
        $ErrorActionPreference = 'Continue'
        $lines = @(& $hostExe -NoProfile -File $sync "-$Mode" -RepositoryRoot $profileRepo -UserProfile $profileHome 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
        if ($null -eq $previousOverlay) { Remove-Item Env:AGENTHUB_OVERLAY -ErrorAction SilentlyContinue }
        else { $env:AGENTHUB_OVERLAY = $previousOverlay }
    }
    foreach ($line in $lines) { Write-Display $line }
    return $code
}

switch ($Action) {
    'New' {
        Assert-SafeRoot
        if (Test-Path -LiteralPath $Root) {
            if (-not (Get-Marker)) {
                Stop-Demo "Refusing to reset '$Root': it exists and has no $MarkerName for this path."
            }
            Remove-Item -LiteralPath $Root -Recurse -Force
        }
        New-Item -ItemType Directory -Path (Join-Path $profileRepo 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path $profileHome -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Destination (Join-Path $profileRepo 'registry\agents.json')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'policy-core.md') -Destination $profilePolicy
        $marker = [ordered]@{
            schema = $MarkerSchema
            root = $Root
            source = $repoRoot
            note = 'Throwaway AgentHub demo profile. Safe to delete with AgentHubDemoProfile.ps1 -Action Remove.'
        }
        [IO.File]::WriteAllText($markerPath, ($marker | ConvertTo-Json) + "`n", [Text.UTF8Encoding]::new($false))
        Write-Display "Demo profile ready: $Root"
        Write-Display "  registry: $(Join-Path $profileRepo 'registry\agents.json')"
        Write-Display "  policy:   $profilePolicy"
        Write-Display "  home:     $profileHome"
        exit 0
    }
    'Audit' { exit (Invoke-ProfileSync 'Audit') }
    'Apply' { exit (Invoke-ProfileSync 'Apply') }
    'EditPolicy' {
        Assert-Profile
        $text = [IO.File]::ReadAllText($profilePolicy)
        if ($text.Contains($DemoPolicyLine)) {
            Write-Display "Policy edit already present in $profilePolicy"
            exit 0
        }
        if (-not $text.EndsWith("`n")) { $text += "`n" }
        [IO.File]::WriteAllText($profilePolicy, $text + $DemoPolicyLine + "`n", [Text.UTF8Encoding]::new($false))
        Write-Display "Edited $profilePolicy (one line added):"
        Write-Display "+ $DemoPolicyLine"
        exit 0
    }
    'Diff' {
        Assert-Profile
        $base = @(Get-Content -LiteralPath (Join-Path $repoRoot 'policy-core.md') -Encoding UTF8)
        $edited = @(Get-Content -LiteralPath $profilePolicy -Encoding UTF8)
        $delta = @(Compare-Object -ReferenceObject $base -DifferenceObject $edited)
        if ($delta.Count -eq 0) { Write-Display 'Profile policy matches the checkout policy-core.md.' }
        foreach ($d in $delta) {
            $sign = if ($d.SideIndicator -eq '=>') { '+' } else { '-' }
            Write-Display "$sign $($d.InputObject)"
        }
        exit 0
    }
    'Remove' {
        $removed = Remove-Profile
        if ($removed) { Write-Display "Removed demo profile $Root" } else { Write-Display "No demo profile at $Root (nothing to remove)" }
        exit 0
    }
}
