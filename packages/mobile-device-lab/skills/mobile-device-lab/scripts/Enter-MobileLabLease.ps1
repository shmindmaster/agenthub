#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Acquire', 'Release', 'Hold')]
    [string]$Action = 'Acquire',
    [string]$LeaseId,
    [ValidateRange(1, 720)]
    [int]$TimeoutMinutes = 120,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$mutexName = 'Global\AgentHub.MobileDeviceLab.ForegroundMutation'
$leaseRoot = Join-Path $env:LOCALAPPDATA 'AgentHub\mobile-lab\leases'

function Write-LeaseResult {
    param([bool]$Ok, [string]$State, [string]$Id, [Nullable[int]]$HolderPid, [string]$ErrorMessage)
    $result = [ordered]@{
        ok = $Ok
        state = $State
        leaseId = $Id
        holderPid = $HolderPid
        mutex = $mutexName
        error = $ErrorMessage
        remediation = if ($Ok) { $null } else { 'Wait for the reported mobile-lab owner to release its lease. Never terminate it merely to acquire the lab.' }
    }
    if ($Json) { Write-Output ($result | ConvertTo-Json -Depth 4 -Compress) }
    else { $result }
}

function Get-LeasePaths([string]$Id) {
    if ($Id -notmatch '^[0-9a-f]{32}$') { throw 'LeaseId must be the 32-character identifier returned by -Action Acquire.' }
    return @{
        Status = Join-Path $leaseRoot "$Id.status.json"
        Release = Join-Path $leaseRoot "$Id.release"
    }
}

try {
    New-Item -ItemType Directory -Path $leaseRoot -Force | Out-Null

    if ($Action -eq 'Hold') {
        $paths = Get-LeasePaths $LeaseId
        $mutex = [Threading.Mutex]::new($false, $mutexName)
        $acquired = $false
        try {
            try { $acquired = $mutex.WaitOne(0) }
            catch [Threading.AbandonedMutexException] { $acquired = $true }
            if (-not $acquired) {
                [IO.File]::WriteAllText($paths.Status, (@{ ok = $false; active = $false; state = 'busy'; leaseId = $LeaseId; holderPid = $PID } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
                exit 2
            }

            $expiresAt = [DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)
            [IO.File]::WriteAllText($paths.Status, (@{ ok = $true; active = $true; state = 'held'; leaseId = $LeaseId; holderPid = $PID; expiresAt = $expiresAt.ToString('o') } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
            while ([DateTimeOffset]::UtcNow -lt $expiresAt -and -not (Test-Path -LiteralPath $paths.Release)) {
                Start-Sleep -Milliseconds 250
            }
            [IO.File]::WriteAllText($paths.Status, (@{ ok = $true; active = $false; state = 'released'; leaseId = $LeaseId; holderPid = $PID } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
            exit 0
        }
        finally {
            if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
            $mutex.Dispose()
        }
    }

    if ($Action -eq 'Acquire') {
        $LeaseId = [guid]::NewGuid().ToString('N')
        $paths = Get-LeasePaths $LeaseId
        $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Action', 'Hold', '-LeaseId', $LeaseId, '-TimeoutMinutes', [string]$TimeoutMinutes)
        $holder = Start-Process -FilePath $hostExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $paths.Status)) {
            if ($holder.HasExited) { break }
            Start-Sleep -Milliseconds 100
            $holder.Refresh()
        }
        if (-not (Test-Path -LiteralPath $paths.Status)) { throw "Lease holder did not initialize (pid=$($holder.Id))." }
        $status = Get-Content -LiteralPath $paths.Status -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $status.ok -or -not $status.active) {
            Write-LeaseResult -Ok $false -State 'busy' -Id $LeaseId -HolderPid $null -ErrorMessage 'The mobile-lab foreground lease is already held.'
            exit 1
        }
        Write-LeaseResult -Ok $true -State 'held' -Id $LeaseId -HolderPid ([int]$status.holderPid) -ErrorMessage $null
        exit 0
    }

    $paths = Get-LeasePaths $LeaseId
    if (-not (Test-Path -LiteralPath $paths.Status)) { throw "Unknown mobile-lab lease: $LeaseId" }
    $status = Get-Content -LiteralPath $paths.Status -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$status.leaseId -ne $LeaseId) { throw 'Lease metadata does not match LeaseId.' }
    if (-not $status.active) {
        Write-LeaseResult -Ok $true -State 'released' -Id $LeaseId -HolderPid ([int]$status.holderPid) -ErrorMessage $null
        exit 0
    }
    [IO.File]::WriteAllText($paths.Release, $LeaseId, [Text.UTF8Encoding]::new($false))
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 100
        $status = Get-Content -LiteralPath $paths.Status -Raw -Encoding UTF8 | ConvertFrom-Json
    } while ($status.active -and [DateTime]::UtcNow -lt $deadline)
    if ($status.active) { throw "Lease holder did not release within 15 seconds (pid=$($status.holderPid))." }
    Write-LeaseResult -Ok $true -State 'released' -Id $LeaseId -HolderPid ([int]$status.holderPid) -ErrorMessage $null
    exit 0
}
catch {
    Write-LeaseResult -Ok $false -State 'error' -Id $LeaseId -HolderPid $null -ErrorMessage $_.Exception.Message
    exit 1
}
