#Requires -Version 5.1
# The guard must fail when routing or the required document is removed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\PrivateOverlay.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-policy-' + [guid]::NewGuid().ToString('N'))
$policyFile = Join-Path $scratch 'global-agent-policy.md'
$guidance = Join-Path $scratch 'guidance'
New-Item -ItemType Directory -Path $guidance -Force | Out-Null
$mandatory = "## Load detailed policy when the task needs it`nThe following are mandatory parts. Read the indicated canonical file before acting.`n"
$routing = '- Before any mobile work: Read `' + (Join-Path $guidance 'mobile.md') + '`.'
function Expect-Rejection([string]$Label) {
    $rejected = $false
    try { $null = Read-AgentHubTestPolicy -PolicyPath $policyFile -Domains mobile } catch { $rejected = $true }
    if (-not $rejected) { throw "Expected rejection: $Label" }
    Write-Host "PASS: $Label"
}
try {
    Set-Content -LiteralPath (Join-Path $guidance 'mobile.md') -Encoding UTF8 -Value 'REQUIRED_GUARD'
    Set-Content -LiteralPath $policyFile -Encoding UTF8 -Value ($mandatory + $routing)
    if ((Read-AgentHubTestPolicy -PolicyPath $policyFile -Domains mobile) -notmatch 'REQUIRED_GUARD') { throw 'Guidance was not loaded' }
    Write-Host 'PASS: mandatory referenced guidance is included'
    Set-Content -LiteralPath $policyFile -Encoding UTF8 -Value $mandatory
    Expect-Rejection 'unreferenced adjacent guidance is rejected'
    Set-Content -LiteralPath $policyFile -Encoding UTF8 -Value ($mandatory + '- Before any mobile work: Read `C:\wrong\guidance\mobile.md`.')
    Expect-Rejection 'a different absolute guidance path is rejected'
    Set-Content -LiteralPath $policyFile -Encoding UTF8 -Value ($mandatory + '- Before any mobile work: Read `guidance\mobile.md`.')
    Expect-Rejection 'a relative guidance path is rejected'
    Set-Content -LiteralPath $policyFile -Encoding UTF8 -Value ("## Load detailed policy when the task needs it`nOptional reading.`n" + $routing)
    Expect-Rejection 'optional routing is rejected'
    Set-Content -LiteralPath $policyFile -Encoding UTF8 -Value ($mandatory + $routing)
    Remove-Item -LiteralPath (Join-Path $guidance 'mobile.md')
    Expect-Rejection 'missing referenced guidance is rejected'
    Set-Content -LiteralPath $policyFile -Encoding UTF8 -Value 'INLINE_GUARD'
    if ((Read-AgentHubTestPolicy -PolicyPath $policyFile -Domains mobile) -ne "INLINE_GUARD`r`n" -and (Read-AgentHubTestPolicy -PolicyPath $policyFile -Domains mobile).Trim() -ne 'INLINE_GUARD') { throw 'Inline policy changed' }
    Write-Host 'PASS: public inline policy remains supported'
} finally {
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not ([IO.Path]::GetFullPath($scratch)).StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture path' }
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
