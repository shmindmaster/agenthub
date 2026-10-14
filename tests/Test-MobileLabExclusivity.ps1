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

# A per-run Local mutex, never the canonical Global one: a live lab owner that
# legitimately holds the real lease (observed 2026-10-13 while this suite ran)
# must neither fail these behavior checks nor be contended by them.
$testMutex = 'Local\AgentHub.MobileDeviceLab.Test.' + [guid]::NewGuid().ToString('N')
$canonicalMutex = 'Global\AgentHub.MobileDeviceLab.ForegroundMutation'
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

    $lease = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Acquire'; TimeoutMinutes = 2; MutexName = $testMutex }
    if ($lease.ExitCode -eq 0 -and $lease.Result -and $lease.Result.ok) {
        $leaseId = [string]$lease.Result.leaseId
        $blocked = Invoke-JsonScript -Path $idleProbePath -Parameters @{ LeaseOnly = $true; MutexName = $testMutex }
        Report 'independent idle probe rejects an active foreground lease' (
            $blocked.ExitCode -ne 0 -and $blocked.Result -and -not $blocked.Result.idle -and
            'mobile-lab foreground lease' -in @($blocked.Result.conflicts | ForEach-Object Kind)
        ) "exit=$($blocked.ExitCode) output=$($blocked.Output -join ' ')"

        $owned = Invoke-JsonScript -Path $idleProbePath -Parameters @{ LeaseOnly = $true; LeaseId = $leaseId; MutexName = $testMutex }
        Report 'lease owner can run its own preflight' ($owned.ExitCode -eq 0 -and $owned.Result -and $owned.Result.idle) "exit=$($owned.ExitCode) output=$($owned.Output -join ' ')"

        $contender = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Acquire'; TimeoutMinutes = 2; MutexName = $testMutex }
        Report 'competing foreground lease acquisition is rejected' (
            $contender.ExitCode -ne 0 -and $contender.Result -and -not $contender.Result.ok -and $contender.Result.state -eq 'busy'
        ) "exit=$($contender.ExitCode) output=$($contender.Output -join ' ')"

        $release = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Release'; LeaseId = $leaseId; MutexName = $testMutex }
        if ($release.ExitCode -eq 0 -and $release.Result -and $release.Result.ok) { $leaseId = $null }
        $after = Invoke-JsonScript -Path $idleProbePath -Parameters @{ LeaseOnly = $true; MutexName = $testMutex }
        Report 'foreground lease releases cleanly' ($release.ExitCode -eq 0 -and $after.ExitCode -eq 0 -and $after.Result.idle) "release=$($release.Output -join ' ') after=$($after.Output -join ' ')"

        $staleLeaseId = [guid]::NewGuid().ToString('N')
        $stale = Invoke-JsonScript -Path $idleProbePath -Parameters @{ LeaseOnly = $true; LeaseId = $staleLeaseId; MutexName = $testMutex }
        Report 'stale lease id cannot bypass a free canonical mutex' (
            $stale.ExitCode -ne 0 -and $stale.Result -and -not $stale.Result.idle -and
            (@($stale.Result.probeErrors | ForEach-Object Error) -join ' ') -match 'does not own'
        ) "exit=$($stale.ExitCode) output=$($stale.Output -join ' ')"
    }
    else {
        foreach ($name in @('independent idle probe rejects an active foreground lease','lease owner can run its own preflight','competing foreground lease acquisition is rejected','foreground lease releases cleanly','stale lease id cannot bypass a free canonical mutex')) {
            Report $name $false "initial lease acquisition failed: $($lease.Output -join ' ')"
        }
    }

    # The override is test isolation, not a bypass: it admits only the
    # canonical name or a Local test name, and nothing outside the lease tool
    # itself (which forwards it to its own holder) ever passes it.
    # Case and trailing-newline variants matter most: Win32 mutex names are
    # case-sensitive, so either would open a different, uncontended object
    # while the caller believed it held the lab.
    $badNames = @(
        'Global\AgentHub.MobileDeviceLab.Other',
        'Local\AgentHub.MobileDeviceLab.Test.notahexid',
        ('Global\AgentHub.MobileDeviceLab.Test.' + [guid]::NewGuid().ToString('N')),
        $canonicalMutex.ToLowerInvariant(),
        ($canonicalMutex + "`n"),
        ('LOCAL\AgentHub.MobileDeviceLab.Test.' + [guid]::NewGuid().ToString('N')),
        ('Local\AgentHub.MobileDeviceLab.Test.' + [guid]::NewGuid().ToString('N').ToUpperInvariant())
    )
    $aliasRejected = foreach ($bad in $badNames) {
        # Parameter validation throws before the script body runs, which is
        # the rejection being tested; anything that returns ran with the name.
        $outcomes = foreach ($try in @(
                @{ Path = $leaseToolPath; Parameters = @{ Action = 'Acquire'; TimeoutMinutes = 1; MutexName = $bad } },
                @{ Path = $idleProbePath; Parameters = @{ LeaseOnly = $true; MutexName = $bad } })) {
            try {
                $ran = Invoke-JsonScript -Path $try.Path -Parameters $try.Parameters
                "ran: exit=$($ran.ExitCode) $($ran.Output -join ' ')"
            }
            catch [Management.Automation.ParameterBindingException] { 'rejected' }
        }
        [pscustomobject]@{ Name = $bad; Rejected = (@($outcomes | Where-Object { $_ -ne 'rejected' }).Count -eq 0); Output = ($outcomes -join ' / ') }
    }
    $accepted = @($aliasRejected | Where-Object { -not $_.Rejected })
    Report 'mutex override rejects every name outside the canonical and Local test namespaces' ($accepted.Count -eq 0) (($accepted | ForEach-Object { "$($_.Name.Trim()): $($_.Output)" }) -join ' | ')

    $defaults = foreach ($path in @($leaseToolPath, $idleProbePath)) {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        $param = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'MutexName' })
        if ($param.Count -eq 1 -and $param[0].DefaultValue) { $param[0].DefaultValue.SafeGetValue() } else { '<none>' }
    }
    Report 'lease tool and idle probe default to the canonical Global mutex' (
        @($defaults | Where-Object { $_ -ceq $canonicalMutex }).Count -eq 2
    ) "defaults=$($defaults -join ',')"

    $packageScripts = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'packages\mobile-development') -Recurse -File -Include '*.ps1', '*.psm1', '*.mjs', '*.sh'
    $passers = @($packageScripts | Where-Object {
        $_.FullName -ne $leaseToolPath -and $_.FullName -ne $idleProbePath -and
        (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) -match '(?i)-MutexName|MutexName\s*='
    } | ForEach-Object Name)
    Report 'no production caller passes the test-only mutex override' ($passers.Count -eq 0) "callers=$($passers -join ',')"
}
finally {
    if ($leaseId) { $null = Invoke-JsonScript -Path $leaseToolPath -Parameters @{ Action = 'Release'; LeaseId = $leaseId; MutexName = $testMutex } }
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) {
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: $reported passed, 0 failed" -ForegroundColor Green
