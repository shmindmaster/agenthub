#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/lib/PluginTransaction.ps1')
$script:state = 'old'
$result = Invoke-AgentHubPluginChange -Install { $script:state = 'new' } -Verify { $script:state -eq 'new' } -Rollback { $script:state = 'old' }
if ($result -ne 'verified' -or $script:state -ne 'new') { throw 'Successful update was not verified' }
$script:state = 'old'
$failed = $false
try {
    Invoke-AgentHubPluginChange -Install { $script:state = 'bad' } -Verify { $false } -Rollback { $script:state = 'old' }
} catch { $failed = $true }
if (-not $failed -or $script:state -ne 'old') { throw 'Failed readback did not roll back' }
$failed = $false
try {
    Invoke-AgentHubPluginChange -Install { throw 'provider failure' } -Verify { $true } -Rollback { throw 'restore unavailable' }
} catch { $failed = $_.Exception.Message -match 'restore unavailable' }
if (-not $failed) { throw 'Lost rollback failure evidence' }
Write-Host 'RESULT: 3 passed, 0 failed'
