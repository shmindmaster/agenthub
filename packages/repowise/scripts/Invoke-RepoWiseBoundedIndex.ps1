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
    [Parameter(Mandatory)][DateTimeOffset]$Deadline,
    [string]$Python = 'python.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows Job Objects are required.' }
foreach ($path in @($Workspace, $RepositoryRoot, $LeasePath, $OutputDirectory)) {
    if (-not [IO.Path]::IsPathFullyQualified($path)) { throw 'All paths must be absolute.' }
}
if ([DateTimeOffset]::Now -ge $Deadline) { throw 'Admission deadline has passed.' }
$free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
if ($free -le $MinimumFreeGiB * 1GB) { throw 'Insufficient free physical RAM; no lease acquired.' }
$pythonCommand = (Get-Command $Python -CommandType Application -ErrorAction Stop).Source
if ($pythonCommand -like '*\WindowsApps\*') { throw 'Use an installed Python, not the Store stub.' }
# uv/py launchers may insert a shim process. Call the actual interpreter so the
# reader can bind the lease to its immediate PowerShell parent without guessing
# ancestry or weakening the PID check.
$runtime = (& $pythonCommand -c 'import sys; print(sys.executable)' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not [IO.Path]::IsPathFullyQualified($runtime) -or
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
        token = $token; acquiredUtc = [DateTimeOffset]::UtcNow.ToString('o') }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress))
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
    if ([DateTimeOffset]::Now -ge $Deadline) { throw 'Admission deadline has passed.' }
    & $pythonCommand "$PSScriptRoot\bounded_index.py" `
        --workspace $Workspace --repo-root $RepositoryRoot `
        --lease $LeasePath --lease-token $token --output $OutputDirectory `
        --memory-gib $MemoryGiB --timeout-seconds $TimeoutSeconds `
        --minimum-free-gib $MinimumFreeGiB --deadline $Deadline.ToUniversalTime().ToString('o')
    $code = $LASTEXITCODE
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
