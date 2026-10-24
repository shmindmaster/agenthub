#Requires -Version 5.1
<# Manual audit/repair of the optional Cline SDK file plugin. No host launch,
   credentials, scheduled work, approval changes, or install-directory patches. #>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ClineHome = $(if ($env:CLINE_DIR) { $env:CLINE_DIR } else { Join-Path $env:USERPROFILE '.cline' }),
    [string]$GlobalSettingsPath,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
# These are Cline 3.0.73's native storage overrides. An explicit fixture/home
# remains isolated unless the caller also explicitly supplies a settings path.
if (-not $GlobalSettingsPath) {
    if (-not $PSBoundParameters.ContainsKey('ClineHome') -and $env:CLINE_GLOBAL_SETTINGS_PATH) {
        $GlobalSettingsPath = $env:CLINE_GLOBAL_SETTINGS_PATH
    } else {
        $dataRoot = if (-not $PSBoundParameters.ContainsKey('ClineHome') -and $env:CLINE_DATA_DIR) { $env:CLINE_DATA_DIR } else { Join-Path $ClineHome 'data' }
        $GlobalSettingsPath = Join-Path $dataRoot 'settings\global-settings.json'
    }
}
$settings = if (Test-Path -LiteralPath $GlobalSettingsPath -PathType Leaf) {
    Get-Content -LiteralPath $GlobalSettingsPath -Raw | ConvertFrom-Json
} else { [pscustomobject]@{} }
if ($null -eq $settings -or $settings -isnot [pscustomobject]) {
    throw 'Cline global settings must be a JSON object; no settings were changed.'
}
$compactionState = if ($settings.compactionStrategy -eq 'basic' -and $settings.compactionEnabled -eq $true) { 'current' } else { 'drift' }
$source = Join-Path $PSScriptRoot 'cline\lightweight-chat.js'
$destination = Join-Path $ClineHome 'plugins\lightweight-chat.js'
$expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$current = if (Test-Path -LiteralPath $destination -PathType Leaf) {
    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
} else { $null }
$state = if ($current -eq $expected) { 'current' } elseif ($null -eq $current) { 'missing' } else { 'drift' }
if ($state -ne 'current' -and $Apply -and $PSCmdlet.ShouldProcess($destination, 'Install canonical Cline tool discovery plugin')) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    Copy-Item -LiteralPath $source -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
        throw 'Cline plugin readback did not match canonical source.'
    }
    $state = 'repaired'
}
if ($compactionState -ne 'current' -and $Apply -and $PSCmdlet.ShouldProcess($GlobalSettingsPath, 'Enable native basic compaction (global Cline default)')) {
    # Native basic compaction preserves typed user prompts without an LLM
    # summary. Preserve every other setting, including unknown future keys.
    $settings | Add-Member -NotePropertyName compactionStrategy -NotePropertyValue 'basic' -Force
    $settings | Add-Member -NotePropertyName compactionEnabled -NotePropertyValue $true -Force
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $GlobalSettingsPath) -Force
    $temporary = $GlobalSettingsPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, (($settings | ConvertTo-Json -Depth 100) + [Environment]::NewLine), (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $temporary -Destination $GlobalSettingsPath -Force
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    $readback = Get-Content -LiteralPath $GlobalSettingsPath -Raw | ConvertFrom-Json
    if ($readback.compactionStrategy -ne 'basic' -or $readback.compactionEnabled -ne $true) {
        throw 'Cline native compaction settings readback failed.'
    }
    $compactionState = 'repaired'
}
[pscustomobject]@{ State = $state; Path = $destination; CompactionState = $compactionState; CompactionScope = 'global-default'; SettingsPath = $GlobalSettingsPath; HostStarted = $false; CredentialsChanged = $false }
if ($state -in @('missing', 'drift') -or $compactionState -eq 'drift') { exit 1 }
