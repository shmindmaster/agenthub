#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $repoRoot 'examples/assurance-loop/Invoke-AssuranceDemo.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-assurance-test/{0}" -f [guid]::NewGuid().ToString('n'))
$passed = 0
$failed = 0

function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "PASS: $Name"; $script:passed++ }
    else { Write-Host "FAIL: $Name"; $script:failed++ }
}

try {
    & $scriptPath -Scenario all -OutputRoot $tempRoot | Out-Host
    $invalid = Get-Content -LiteralPath (Join-Path $tempRoot 'invalid.receipt.json') -Raw | ConvertFrom-Json
    $traversal = Get-Content -LiteralPath (Join-Path $tempRoot 'traversal.receipt.json') -Raw | ConvertFrom-Json
    $unapproved = Get-Content -LiteralPath (Join-Path $tempRoot 'unapproved.receipt.json') -Raw | ConvertFrom-Json
    $approved = Get-Content -LiteralPath (Join-Path $tempRoot 'approved.receipt.json') -Raw | ConvertFrom-Json
    $target = Join-Path $tempRoot 'workspace/result.txt'

    Assert-True ($invalid.result -eq 'rejected' -and -not $invalid.execution.attempted) 'invalid structured output is rejected before execution'
    Assert-True ($traversal.result -eq 'denied' -and $traversal.reasonCodes -contains 'path-dot-segment' -and -not $traversal.execution.attempted) 'dot-segment traversal is denied before execution'
    Assert-True ($unapproved.result -eq 'denied' -and $unapproved.reasonCodes -contains 'approval-required' -and -not $unapproved.execution.attempted) 'missing approval deterministically blocks the write'
    Assert-True ($approved.result -eq 'executed' -and $approved.execution.finalState -eq 'expected-state-observed') 'approved action records the observed final state'
    Assert-True ($approved.approval.inputSha256 -eq $approved.inputSha256 -and $approved.approval.decisionId -eq $approved.decisionId) 'trusted approval is bound to the decision ID and proposal digest'
    Assert-True ((Test-Path -LiteralPath $target) -and ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $approved.execution.observedSha256)) 'receipt hash matches the written artifact'
    Assert-True ($approved.inputSha256 -match '^[a-f0-9]{64}$' -and $approved.policySha256 -match '^[a-f0-9]{64}$') 'receipt binds the input and policy by digest'
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
