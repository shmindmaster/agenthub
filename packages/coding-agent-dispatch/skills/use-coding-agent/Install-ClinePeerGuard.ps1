#Requires -Version 5.1
<# Manual audit/repair of the optional Cline SDK file plugin. No host launch,
   credentials, scheduled work, approval changes, or install-directory patches. #>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ClineHome = $(if ($env:CLINE_DIR) { $env:CLINE_DIR } else { Join-Path $env:USERPROFILE '.cline' }),
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'cline/peer-guard.js'
$destination = Join-Path $ClineHome 'plugins/peer-guard.js'
$expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$current = if (Test-Path -LiteralPath $destination -PathType Leaf) {
    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
} else { $null }
$state = if ($current -eq $expected) { 'current' } elseif ($null -eq $current) { 'missing' } else { 'drift' }
if ($state -ne 'current' -and $Apply -and $PSCmdlet.ShouldProcess($destination, 'Install canonical Cline peer guard plugin')) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    Copy-Item -LiteralPath $source -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
        throw 'Cline plugin readback did not match canonical source.'
    }
    $state = 'repaired'
}
[pscustomobject]@{ State = $state; Path = $destination; HostStarted = $false; CredentialsChanged = $false }
if ($state -in @('missing', 'drift')) { exit 1 }