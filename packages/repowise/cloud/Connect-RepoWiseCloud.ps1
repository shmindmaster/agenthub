#Requires -Version 5.1
<#
.SYNOPSIS
  Open an on-demand SSH tunnel to the remote RepoWise MCP, verify it answers,
  and report whether the cloud index is behind this repository's HEAD.

.DESCRIPTION
  Part of the AgentHub RepoWise cloud recipe (SH-4410); see
  docs/runbooks/repowise-cloud.md.

  - Starts `ssh -N -L 127.0.0.1:<local>:127.0.0.1:<remote> <SshTarget>` through
    System.Diagnostics.Process with no window and no shell. The remote server
    binds loopback only; the tunnel is the entire access path.
  - Verifies with a real MCP round trip (initialize, notifications/initialized,
    tools/call list_repos).
  - Fetches the indexer's status JSON for this repository's alias over a
    second read-only ssh call and compares `revision` with local HEAD:
    fresh | stale | not-indexed | unknown.
  - Closes the tunnel it opened (by PID) unless -KeepTunnel is given. It never
    kills a listener it did not start.
  - Registers nothing: no scheduled task, no Run key, no service. Run it when
    a session needs the remote index, or let the capped stdio bridge
    (repowise_bridge_capped.py) point at the local port it prints.

.EXAMPLE
  pwsh -NoProfile -File Connect-RepoWiseCloud.ps1 -SshTarget repowise-mirror -Alias agenthub
#>
[CmdletBinding()]
param(
    [string]$SshTarget = 'repowise-mirror',
    [int]$RemotePort = 7339,
    [int]$LocalPort = 0,
    [string]$RemoteStatusDir = '~/.local/share/repowise-cloud/status',
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$Alias,
    [int]$TimeoutSeconds = 60,
    [switch]$KeepTunnel
)

$ErrorActionPreference = 'Stop'
$runtimeDir = Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\repowise-cloud'
$null = New-Item -ItemType Directory -Force -Path $runtimeDir

function Invoke-Hidden {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$ArgumentList,
          [int]$WaitMs = 0)
    $startInfo = [Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($WaitMs -gt 0) { $null = $process.WaitForExit($WaitMs) } else { $process.WaitForExit() }
        [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.Result; StdErr = $stderr.Result; Process = $process }
    } catch {
        $process.Dispose()
        throw
    }
}

function Get-FreeLoopbackPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

function Test-LoopbackListening([int]$Port) {
    try {
        $client = [Net.Sockets.TcpClient]::new()
        $async = $client.BeginConnect([Net.IPAddress]::Loopback, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(1000)) { $client.Close(); return $false }
        $client.EndConnect($async); $client.Close(); return $true
    } catch { return $false }
}

# --- pure validation / argument-building helpers (unit-tested) ---------------
# Everything an attacker-shaped local value could reach (a remote shell string
# or an ssh argv slot) goes through these before any ssh process starts.

function Test-RepoWiseAlias {
    param([string]$Value)
    # -cmatch: aliases are lowercase by contract (same rule the bash side
    # applies); PowerShell's -match is case-insensitive.
    return ($Value -cmatch '\A[a-z0-9][a-z0-9._-]*\z')
}

function Test-SshTarget {
    # [user@]host restricted so it can never be read as an ssh option; the
    # first character deliberately excludes `-`.
    param([string]$Value)
    return ($Value -match '\A[A-Za-z0-9._][A-Za-z0-9._-]*(@[A-Za-z0-9._-]+)?\z')
}

function ConvertTo-RemoteStatusDir {
    # ~/path or /path over [A-Za-z0-9._-] segments only; `~` becomes the literal
    # text $HOME so the remote shell expands it inside double quotes. Rejecting
    # everything else keeps quote-breaking and .. segments out of the remote
    # command. Throws on anything it cannot prove safe.
    param([Parameter(Mandatory)][string]$Dir)
    if ($Dir -notmatch '(^|/)\.\.(/|$)') {
        if ($Dir -match '^~/([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+$') {
            return "`$HOME/" + $Dir.Substring(2)
        }
        if ($Dir -match '^/([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+$') {
            return $Dir
        }
    }
    throw "invalid -RemoteStatusDir '$Dir': expected ~/path or /path over [A-Za-z0-9._-] segments"
}

function New-SshTunnelArguments {
    param([int]$LocalPort, [int]$RemotePort, [string]$SshTarget)
    if (-not (Test-SshTarget $SshTarget)) {
        throw "invalid -SshTarget '$SshTarget': expected [user@]host over [A-Za-z0-9._-]"
    }
    if ($LocalPort -lt 1 -or $LocalPort -gt 65535 -or $RemotePort -lt 1 -or $RemotePort -gt 65535) {
        throw "ports must be integers in 1-65535"
    }
    return @(
        '-N', '-T',
        '-L', "127.0.0.1:$LocalPort`:127.0.0.1:$RemotePort",
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ServerAliveInterval=30',
        '-o', 'ServerAliveCountMax=2',
        '--', $SshTarget
    )
}

function New-StatusProbeArguments {
    # Builds the ssh argv for the read-only status probe. The remote command
    # distinguishes three outcomes through its exit code so the caller can tell
    # "status file absent" (4) from "present but unreadable" (3) and from any
    # other ssh/remote failure: stderr is never redirected away.
    param([string]$SshTarget, [string]$StatusDir, [string]$Alias)
    if (-not (Test-SshTarget $SshTarget)) {
        throw "invalid -SshTarget '$SshTarget': expected [user@]host over [A-Za-z0-9._-]"
    }
    if (-not (Test-RepoWiseAlias $Alias)) {
        throw "invalid -Alias '$Alias': must match ^[a-z0-9][a-z0-9._-]*$"
    }
    $dir = ConvertTo-RemoteStatusDir $StatusDir
    $p = "$dir/$Alias.json"
    $cmd = "if [ -f `"$p`" ]; then cat `"$p`"; elif [ -e `"$p`" ]; then exit 3; else exit 4; fi"
    return @('-T', '-o', 'BatchMode=yes', '--', $SshTarget, $cmd)
}

# Resolve local repository state (tolerates running outside any repo).
$repoRoot = $null; $head = $null
try {
    $probe = Invoke-Hidden 'git' @('-C', $RepositoryRoot, 'rev-parse', '--show-toplevel') -WaitMs 10000
    if ($probe.ExitCode -eq 0) {
        $repoRoot = $probe.StdOut.Trim()
        $headProbe = Invoke-Hidden 'git' @('-C', $repoRoot, 'rev-parse', 'HEAD') -WaitMs 10000
        if ($headProbe.ExitCode -eq 0) { $head = $headProbe.StdOut.Trim() }
    }
} catch { }
if (-not $Alias) {
    $Alias = if ($repoRoot) { Split-Path -Leaf $repoRoot } else { Split-Path -Leaf (Resolve-Path $RepositoryRoot).Path }
}

# Validate every value that reaches a remote shell string or an ssh argv slot
# before any ssh process is started.
if (-not (Test-RepoWiseAlias $Alias)) {
    throw "invalid -Alias '$Alias': must match ^[a-z0-9][a-z0-9._-]*$ (it is interpolated into a remote shell command)"
}
if (-not (Test-SshTarget $SshTarget)) {
    throw "invalid -SshTarget '$SshTarget': expected [user@]host over [A-Za-z0-9._-] (it must never be read as an ssh option)"
}
if ($RemotePort -lt 1 -or $RemotePort -gt 65535) {
    throw "-RemotePort must be an integer in 1-65535"
}
$null = ConvertTo-RemoteStatusDir $RemoteStatusDir

$sshExe = (Get-Command ssh.exe -CommandType Application -ErrorAction Stop).Source
if ($LocalPort -eq 0) { $LocalPort = Get-FreeLoopbackPort }
$url = "http://127.0.0.1:$LocalPort/mcp"
$errLog = Join-Path $runtimeDir 'ssh-tunnel.err.log'

$sshArgs = New-SshTunnelArguments -LocalPort $LocalPort -RemotePort $RemotePort -SshTarget $SshTarget

$tunnel = $null
$result = [ordered]@{
    alias = $Alias; localPort = $LocalPort; remotePort = $RemotePort; sshTarget = $SshTarget
    head = $head; indexed = $null; indexStatus = 'unknown'; serverAnswered = $false; tunnelPid = $null
}
try {
    [IO.File]::WriteAllText($errLog, '')
    $startInfo = [Diagnostics.ProcessStartInfo]::new($sshExe)
    foreach ($argument in $sshArgs) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardError = $true
    $tunnel = [Diagnostics.Process]::new()
    $tunnel.StartInfo = $startInfo
    $null = $tunnel.Start()
    $result.tunnelPid = $tunnel.Id

    $deadline = [DateTime]::Now.AddSeconds($TimeoutSeconds)
    while (-not (Test-LoopbackListening $LocalPort)) {
        if ($tunnel.HasExited) {
            $err = $tunnel.StandardError.ReadToEnd()
            throw "ssh tunnel exited $($tunnel.ExitCode): $($err.Trim())"
        }
        if ([DateTime]::Now -gt $deadline) { throw "tunnel did not open 127.0.0.1:$LocalPort within ${TimeoutSeconds}s" }
        Start-Sleep -Milliseconds 400
    }

    # Real MCP round trip: initialize, notify, then a cheap tools/call.
    $headers = @{ Accept = 'application/json, text/event-stream'; 'Content-Type' = 'application/json' }
    $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"repowise-cloud-connector","version":"1"}}}'
    $r = Invoke-WebRequest -Uri $url -Method Post -Body $init -Headers $headers -TimeoutSec 30 -UseBasicParsing
    $sessionId = [string]$r.Headers['Mcp-Session-Id']
    if (-not $sessionId) { throw 'MCP server answered initialize without a session id' }
    $headers['Mcp-Session-Id'] = $sessionId
    $headers['MCP-Protocol-Version'] = '2025-06-18'
    $null = Invoke-WebRequest -Uri $url -Method Post -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' -Headers $headers -TimeoutSec 15 -UseBasicParsing
    $call = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_repos","arguments":{}}}'
    $r = Invoke-WebRequest -Uri $url -Method Post -Body $call -Headers $headers -TimeoutSec 60 -UseBasicParsing
    $body = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
    if ($body -notmatch '"result"') { throw "MCP tools/call list_repos did not return a result" }
    $result.serverAnswered = $true
    try { $null = Invoke-WebRequest -Uri $url -Method Delete -Headers $headers -TimeoutSec 5 -UseBasicParsing } catch { }

    # Stale-index check: the indexer records the last indexed commit per alias.
    # The probe distinguishes "status file absent" (exit 4 -> not-indexed) from
    # a real read failure (any other non-zero -> unknown); stderr is kept and
    # surfaced instead of being swallowed by `|| true`.
    $statusProbe = Invoke-Hidden $sshExe `
        (New-StatusProbeArguments -SshTarget $SshTarget -StatusDir $RemoteStatusDir -Alias $Alias) `
        -WaitMs 20000
    if ($statusProbe.ExitCode -eq 4) {
        $result.indexStatus = 'not-indexed'
    } elseif ($statusProbe.ExitCode -ne 0) {
        Write-Warning "could not read remote index status (ssh exit $($statusProbe.ExitCode)): $($statusProbe.StdErr.Trim())"
        $result.indexStatus = 'unknown'
    } else {
        try {
            $statusJson = $statusProbe.StdOut | ConvertFrom-Json
            $result.indexed = [string]$statusJson.revision
        } catch { }
        if (-not $result.indexed) {
            Write-Warning 'remote index status file was present but unreadable or empty'
            $result.indexStatus = 'unknown'
        } elseif (-not $head) {
            $result.indexStatus = 'unknown'
        } elseif ($result.indexed -eq $head) {
            $result.indexStatus = 'fresh'
        } else {
            $result.indexStatus = 'stale'
        }
    }
}
finally {
    if ($tunnel -and -not $KeepTunnel) {
        try { if (-not $tunnel.HasExited) { $tunnel.Kill() } } catch { }
        $tunnel.Dispose()
    } elseif ($tunnel) {
        $result.tunnelLeftOpen = $tunnel.Id
    }
}

$result | ConvertTo-Json -Compress
$summary = "repowise-cloud: $($result.indexStatus) (indexed=$($result.indexed) head=$($result.head))"
if ($result.indexStatus -eq 'stale') { Write-Warning $summary } else { Write-Host $summary }
if ($result.indexStatus -eq 'stale') { exit 1 }
exit 0
