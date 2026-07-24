[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('claude', 'qwen', 'opencode', 'hermes')]
    [string]$Agent,

    [ValidateSet('Persistent', 'Clean')]
    [string]$Mode = 'Persistent',

    [string]$StartUrl = 'about:blank'
)

$ports = @{
    claude = 9341
    qwen = 9342
    opencode = 9343
    hermes = 9344
}

& (Join-Path $PSScriptRoot 'launch-qa-chrome.ps1') `
    -Mode $Mode `
    -Port $ports[$Agent] `
    -Instance $Agent `
    -StartUrl $StartUrl
