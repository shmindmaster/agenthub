#Requires -Version 7.0
<#
.SYNOPSIS
Manually run one local index-only update under an atomic coordination lease.
.DESCRIPTION
No install, service restart, schedule, agent generation, docs or paid provider.
The caller supplies the shared heavy-work lease path, never a foreign lease.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$LeasePath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(1, 8)][int]$MemoryGiB = 8,
    [ValidateRange(1, 900)][int]$TimeoutSeconds = 900,
    [ValidateRange(4, 64)][double]$MinimumFreeGiB = 8,
    [ValidateLength(1, 512)]
    [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
    [string]$RamFloorWaiverReason,
    [Parameter(Mandatory)][DateTimeOffset]$Deadline,
    [string]$Python = 'python.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows Job Objects are required.' }
function Invoke-HiddenProcess {
    # Never the call operator: launch through System.Diagnostics.Process with no
    # shell and no console window. ArgumentList keeps every argument intact
    # (no joined command-line string to re-split or quote).
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$ArgumentList)
    $startInfo = [Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        # Drain both pipes concurrently so a chatty child cannot deadlock.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.Result; StdErr = $stderr.Result }
    } finally { $process.Dispose() }
}
foreach ($path in @($Workspace, $RepositoryRoot, $LeasePath, $OutputDirectory)) {
    if (-not [IO.Path]::IsPathFullyQualified($path)) { throw 'All paths must be absolute.' }
}
if ([DateTimeOffset]::Now -ge $Deadline) { throw 'Admission deadline has passed.' }
$free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
if (-not $RamFloorWaiverReason -and $free -le $MinimumFreeGiB * 1GB) { throw 'Insufficient free physical RAM; no lease acquired.' }
$pythonCommand = (Get-Command $Python -CommandType Application -ErrorAction Stop).Source
if ($pythonCommand -like '*\WindowsApps\*') { throw 'Use an installed Python, not the Store stub.' }
# uv/py launchers may insert a shim process. Call the actual interpreter so the
# reader can bind the lease to its immediate PowerShell parent without guessing
# ancestry or weakening the PID check.
$resolved = Invoke-HiddenProcess -FilePath $pythonCommand -ArgumentList @('-c', 'import sys; print(sys.executable)')
$runtime = $resolved.StdOut.Trim()
if ($resolved.ExitCode -ne 0 -or -not [IO.Path]::IsPathFullyQualified($runtime) -or
    -not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw 'Could not resolve the actual Python interpreter.' }
$pythonCommand = $runtime
$token = [Guid]::NewGuid().ToString('N')
$stream = $null
$retainLease = $false
try {
    # CreateNew is the admission decision. The handle is NOT DeleteOnClose: a
    # lease must survive a run that cannot prove its owned processes are gone.
    # FileShare.Read keeps other tasks from deleting or rewriting it meanwhile.
    $stream = [IO.FileStream]::new(
        $LeasePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::Read, 4096, [IO.FileOptions]::None)
    $record = @{ owner = 'AgentHub bounded RepoWise index'; pid = $PID
        token = $token; acquiredUtc = [DateTimeOffset]::UtcNow.ToString('o')
        ramFloorWaiverReason = $RamFloorWaiverReason }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress))
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
    if ([DateTimeOffset]::Now -ge $Deadline) { throw 'Admission deadline has passed.' }
    $childArguments = @(
        (Join-Path $PSScriptRoot 'bounded_index.py'),
        '--workspace', $Workspace, '--repo-root', $RepositoryRoot,
        '--lease', $LeasePath, '--lease-token', $token, '--output', $OutputDirectory,
        '--memory-gib', [string]$MemoryGiB, '--timeout-seconds', [string]$TimeoutSeconds,
        '--minimum-free-gib', [string]$MinimumFreeGiB,
        '--deadline', $Deadline.ToUniversalTime().ToString('o'))
    if ($RamFloorWaiverReason) { $childArguments += @('--ram-floor-waiver-reason', $RamFloorWaiverReason) }
    $run = Invoke-HiddenProcess -FilePath $pythonCommand -ArgumentList $childArguments
    if ($run.StdOut) { Write-Output $run.StdOut.TrimEnd() }
    if ($run.StdErr) { Write-Host $run.StdErr.TrimEnd() }
    $code = $run.ExitCode
    if ($code -eq 3) {
        # Exit 3: owned processes may still be alive. Keep the lease.
        $retainLease = $true
        throw "Bounded indexing could not prove its owned processes are gone. The admission lease REMAINS at '$LeasePath'. An operator must verify the processes are gone before removing it."
    }
    if ($code -ne 0) { throw 'Bounded indexing was not accepted.' }
} finally {
    if ($null -ne $stream) {
        $stream.Dispose()
        if (-not $retainLease) {
            # Remove only the lease this run created: its token must match. A
            # file that is not ours (or unreadable) is left for its owner.
            try {
                $mine = ([IO.File]::ReadAllText($LeasePath) | ConvertFrom-Json).token -eq $token
            } catch { $mine = $false }
            if ($mine) { [IO.File]::Delete($LeasePath) }
            else { Write-Warning "Lease at '$LeasePath' was not removed: its token is not this run's." }
        }
    }
}
