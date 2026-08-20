#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$scriptsRoot = Join-Path $repoRoot 'packages\mobile-development\skills\mobile-device-lab\scripts'
$idleProbePath = Join-Path $scriptsRoot 'Test-MobileLabIdle.ps1'
$leaseToolPath = Join-Path $scriptsRoot 'Enter-MobileLabLease.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-mobile-exclusivity-' + [guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA
$failures = [Collections.Generic.List[string]]::new()
$reported = 0

function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

function Invoke-JsonScript([string]$Path, [hashtable]$Parameters) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $Parameters.Json = $true
    try { $output = @(& $Path @Parameters 2>&1); $exitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    $line = $output | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
    $result = if ($line) { $line | ConvertFrom-Json } else { $null }
    [pscustomobject]@{ ExitCode = $exitCode; Result = $result; Output = @($output) }
}

$leaseId = $null
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$env:LOCALAPPDATA = Join-Path $fixtureRoot 'LocalAppData'
try {
    $busySnapshot = Join-Path $fixtureRoot 'busy.json'
    [IO.File]::WriteAllText($busySnapshot, (@{
        hostProcesses = @('30164 ssh.exe macvm maestro --device synthetic-simulator test release.yaml')
        guestProcesses = @()
        appiumSessions = @()
        labLease = $false
    } | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    $busy = Invoke-JsonScript -Path $idleProbePath -Parameters @{ SnapshotPath = $busySnapshot }
    Report 'busy probe rejects an active Maestro run' (
        $busy.ExitCode -ne 0 -and $busy.Result -and -not $busy.Result.idle -and
        (@($busy.Result.conflicts | ForEach-Object Kind) -join ' ') -match 'Maestro'
    ) "exit=$($busy.ExitCode) output=$($busy.Output -join ' ')"

    $idleSnapshot = Join-Path $fixtureRoot 'idle.json'
    [IO.File]::WriteAllText($idleSnapshot, (@{
        hostProcesses = @(); guestProcesses = @(); appiumSessions = @(); labLease = $false
    } | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    $idle = Invoke-JsonScript -Path $idleProbePath -Parameters @{ SnapshotPath = $idleSnapshot }
    Report 'busy probe accepts an idle synthetic snapshot' ($idle.ExitCode -eq 0 -and $idle.Result -and $idle.Result.idle) "exit=$($idle.ExitCode) output=$($idle.Output -join ' ')"

    $lease = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Acquire'; TimeoutMinutes = 2 }
    if ($lease.ExitCode -eq 0 -and $lease.Result -and $lease.Result.ok) {
        $leaseId = [string]$lease.Result.leaseId
        $blocked = Invoke-JsonScript -Path $idleProbePath -Parameters @{ LeaseOnly = $true }
        Report 'independent idle probe rejects an active foreground lease' (
            $blocked.ExitCode -ne 0 -and $blocked.Result -and -not $blocked.Result.idle -and
            'mobile-lab foreground lease' -in @($blocked.Result.conflicts | ForEach-Object Kind)
        ) "exit=$($blocked.ExitCode) output=$($blocked.Output -join ' ')"

        $owned = Invoke-JsonScript -Path $idleProbePath -Parameters @{ LeaseOnly = $true; LeaseId = $leaseId }
        Report 'lease owner can run its own preflight' ($owned.ExitCode -eq 0 -and $owned.Result -and $owned.Result.idle) "exit=$($owned.ExitCode) output=$($owned.Output -join ' ')"

        $contender = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Acquire'; TimeoutMinutes = 2 }
        Report 'competing foreground lease acquisition is rejected' (
            $contender.ExitCode -ne 0 -and $contender.Result -and -not $contender.Result.ok -and $contender.Result.state -eq 'busy'
        ) "exit=$($contender.ExitCode) output=$($contender.Output -join ' ')"

        $release = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Release'; LeaseId = $leaseId }
        if ($release.ExitCode -eq 0 -and $release.Result -and $release.Result.ok) { $leaseId = $null }
        $after = Invoke-JsonScript -Path $idleProbePath -Parameters @{ LeaseOnly = $true }
        Report 'foreground lease releases cleanly' ($release.ExitCode -eq 0 -and $after.ExitCode -eq 0 -and $after.Result.idle) "release=$($release.Output -join ' ') after=$($after.Output -join ' ')"
    }
    else {
        foreach ($name in @('independent idle probe rejects an active foreground lease','lease owner can run its own preflight','competing foreground lease acquisition is rejected','foreground lease releases cleanly')) {
            Report $name $false "initial lease acquisition failed: $($lease.Output -join ' ')"
        }
    }
}
finally {
    if ($leaseId) { $null = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Release'; LeaseId = $leaseId } }
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) {
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: $reported passed, 0 failed" -ForegroundColor Green
