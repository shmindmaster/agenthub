#Requires -Version 5.1
<# Manual native OpenCode 2 plugin audit/repair. Never launches a host,
   changes credentials, or patches the application installation. #>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OpenCodeHome = (Join-Path $env:USERPROFILE '.config\opencode'),
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'opencode\lightweight-chat.js'
$destination = Join-Path $OpenCodeHome 'plugins\lightweight-chat.js'
$expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$current = if (Test-Path -LiteralPath $destination -PathType Leaf) {
    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
} else { $null }
$state = if ($current -eq $expected) { 'current' } elseif ($null -eq $current) { 'missing' } else { 'drift' }
if ($state -ne 'current' -and $Apply -and $PSCmdlet.ShouldProcess($destination, 'Install native OpenCode tool discovery plugin')) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    Copy-Item -LiteralPath $source -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
        throw 'OpenCode plugin readback did not match canonical source.'
    }
    $state = 'repaired'
}
[pscustomobject]@{ State = $state; Path = $destination; HostStarted = $false; CredentialsChanged = $false }
if ($state -in @('missing', 'drift')) { exit 1 }
