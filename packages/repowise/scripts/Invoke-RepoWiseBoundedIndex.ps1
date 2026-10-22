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
$token = [Guid]::NewGuid().ToString('N')
$stream = $null
try {
    # CreateNew is the admission decision. DeleteOnClose releases this exact
    # handle only; never remove a path owned by another task.
    $stream = [IO.FileStream]::new(
        $LeasePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose)
    $record = @{ owner = 'AgentHub bounded RepoWise index'; pid = $PID
        token = $token; acquiredUtc = [DateTimeOffset]::UtcNow.ToString('o') }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress))
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
    & $pythonCommand "$PSScriptRoot\bounded_index.py" `
        --workspace $Workspace --repo-root $RepositoryRoot `
        --lease $LeasePath --lease-token $token --output $OutputDirectory `
        --memory-gib $MemoryGiB --timeout-seconds $TimeoutSeconds `
        --minimum-free-gib $MinimumFreeGiB --deadline $Deadline.ToUniversalTime().ToString('o')
    if ($LASTEXITCODE -ne 0) { throw 'Bounded indexing was not accepted.' }
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
}
