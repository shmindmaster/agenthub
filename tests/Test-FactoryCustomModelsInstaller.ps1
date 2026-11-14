#Requires -Version 7
<#
Tests for packages/coding-agent-dispatch/factory/Install-FactoryCustomModels.ps1
(SH-4676 review findings): the audit diff must never print a literal credential
value from an owner-authored entry, and -Apply must install into a settings file
that has no customModels property yet (a PSCustomObject assignment to a missing
property throws; the installer must add the member).

Both cases run against a synthetic -UserProfile; the real user profile is never
read or written. Fixture keys are fake strings that appear nowhere else.

Run: pwsh -NoProfile -File tests/Test-FactoryCustomModelsInstaller.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$installer = Join-Path $repoRoot 'packages\coding-agent-dispatch\factory\Install-FactoryCustomModels.ps1'
$canonicalFile = Join-Path $repoRoot 'packages\coding-agent-dispatch\factory\custom-models.json'
if (-not (Test-Path -LiteralPath $installer)) { throw "installer missing: $installer" }

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

$canonicalIds = @((Get-Content -LiteralPath $canonicalFile -Raw | ConvertFrom-Json).customModels | ForEach-Object { [string]$_.model })
if ($canonicalIds.Count -lt 1) { throw 'canonical file lists no customModels' }

$root = Join-Path ([IO.Path]::GetTempPath()) ("ah-fcm-" + [Guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path (Join-Path $root '.factory') -Force
$settingsFile = Join-Path $root '.factory\settings.json'
try {
    # --- case 1: no customModels property at all ------------------------------
    @{ otherSetting = 'keep-me' } | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding utf8
    $auditOut = & $installer -Audit -UserProfile $root *>&1 | Out-String
    Report 'audit on a settings file without customModels reports every canonical entry missing' `
        (($canonicalIds | Where-Object { $auditOut -notmatch "missing\s+custom:$([regex]::Escape($_))" }).Count -eq 0) $auditOut
    $applyOut = & $installer -Apply -UserProfile $root *>&1 | Out-String
    $after = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
    $afterIds = @($after.customModels | ForEach-Object { [string]$_.model })
    Report '-Apply creates the customModels property on a PSCustomObject that lacks it' `
        (($null -ne $after.PSObject.Properties['customModels']) -and ($canonicalIds | Where-Object { $_ -notin $afterIds }).Count -eq 0) $applyOut
    Report '-Apply preserves unrelated settings' ([string]$after.otherSetting -eq 'keep-me') ($after | ConvertTo-Json -Depth 5)
    Report '-Apply leaves a timestamped backup' ((Get-ChildItem (Join-Path $root '.factory') -Filter 'settings.json.bak-*').Count -eq 1) ''
    $auditOut2 = & $installer -Audit -UserProfile $root *>&1 | Out-String
    Report 'a second audit after -Apply reports every canonical entry current' `
        (($canonicalIds | Where-Object { $auditOut2 -notmatch "current\s+custom:$([regex]::Escape($_))" }).Count -eq 0) $auditOut2

    # --- case 2: owner entry with a literal key and a drifted canonical entry --
    $fakeKey = 'FIXTURE-literal-owner-key-not-a-real-credential'
    $fakeKeyDrifted = 'FIXTURE-literal-drifted-key-not-a-real-credential'
    $drifted = @{
        otherSetting = 'keep-me'
        customModels = @(
            @{ model = 'owner-private'; displayName = 'Owner'; baseUrl = 'https://example.com/v1'; apiKey = $fakeKey; provider = 'generic-chat-completion-api' },
            @{ model = $canonicalIds[0]; displayName = 'Stale Name'; baseUrl = 'https://example.com/stale'; apiKey = $fakeKeyDrifted; provider = 'generic-chat-completion-api' }
        )
    }
    $drifted | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsFile -Encoding utf8
    $auditOut3 = & $installer -Audit -UserProfile $root *>&1 | Out-String
    Report 'audit never prints a literal apiKey value from an existing entry' (($auditOut3 -notmatch [regex]::Escape($fakeKey)) -and ($auditOut3 -notmatch [regex]::Escape($fakeKeyDrifted))) $auditOut3
    Report 'audit masks the credential field but still reports the drift' ($auditOut3 -match '\*\*\*' -and $auditOut3 -match "drift\s+custom:$([regex]::Escape($canonicalIds[0]))") $auditOut3
    Report 'audit reports the owner entry and never claims it' ($auditOut3 -match 'owner-authored\s+custom:owner-private') $auditOut3
    $null = & $installer -Apply -UserProfile $root *>&1
    $after2 = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
    $after2Ids = @($after2.customModels | ForEach-Object { [string]$_.model })
    Report '-Apply merges canonical entries and preserves the owner entry untouched' `
        (('owner-private' -in $after2Ids) -and (($canonicalIds | Where-Object { $_ -notin $after2Ids }).Count -eq 0) -and ((@($after2.customModels | Where-Object { [string]$_.model -eq 'owner-private' } | ForEach-Object { [string]$_.apiKey })[0]) -ceq $fakeKey)) ($after2Ids -join ', ')
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
