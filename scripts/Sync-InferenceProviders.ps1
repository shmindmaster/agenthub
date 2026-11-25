#Requires -Version 7
<#
.SYNOPSIS
  Audit or apply additive AgentHub Daytona inference provider entries across supported coding agents.
#>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [string[]]$HostId,
    [string]$UserProfile,
    [string]$RoamingConfig,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ($Audit -and $Apply) { throw 'Use either -Audit or -Apply, not both.' }

$repoRoot = Split-Path -Parent $PSScriptRoot
$pyScript = Join-Path $PSScriptRoot 'sync_inference_providers.py'
if (-not (Test-Path -LiteralPath $pyScript -PathType Leaf)) {
    throw "Missing sync script: $pyScript"
}

$pyArgs = @($pyScript, '--repo-root', $repoRoot)
if ($UserProfile) { $pyArgs += @('--user-profile', $UserProfile) }
if ($RoamingConfig) { $pyArgs += @('--roaming-config', $RoamingConfig) }
if ($Apply) { $pyArgs += '--apply' }
foreach ($h in @($HostId)) {
    if (-not [string]::IsNullOrWhiteSpace($h)) { $pyArgs += @('--host', $h) }
}
if ($Json) { $pyArgs += '--json' }

$pythonExe = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonExe) { throw 'python is required on PATH' }

& $pythonExe.Source @pyArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
