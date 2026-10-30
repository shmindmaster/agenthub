<#
.SYNOPSIS
  Runs the single shared RepoWise workspace MCP server (streamable HTTP) that
  every host connects to, instead of each host spawning its own copy.

.DESCRIPTION
  One process serves Claude Code, Claude Desktop, Codex, and Cursor at
  http://127.0.0.1:7339/mcp.

  Fails closed on the embedder. RepoWise resolves its embedder once at startup
  and serves mock vectors for the life of the process if the embedder is
  unreachable, so starting it anyway produces a server that answers every
  semantic query from noise (2026-10-14, after a 180 s wait on the old local
  embedder). The embedder is the MahumTech Azure OpenAI text-embedding-3-small
  deployment, read from FOUNDRY_OPENAI_BASE_URL, FOUNDRY_API_KEY (or
  AZURE_AI_SERVICES_KEY) and FOUNDRY_EMBEDDING_DEPLOYMENT in the environment
  and never persisted. Before starting RepoWise the launcher runs
  `shared_server.py --check-embedder`, one real probe embedding; if the
  environment is missing or the probe fails it exits 2 with a FAIL-CLOSED log
  line and starts nothing. Nothing local is started on its behalf.
  After launch, one MCP tool call confirms the server did not come up degraded
  (`_meta.embedder_degraded`); a degraded server is stopped and the exit is 2.

  Started on demand by the capability that needs it -- the repowise plugin's
  stdio bridge (scripts/repowise_bridge.py) runs this when a host connects and
  the port is down -- or by an operator. Never from a logon or scheduled task
  (owner direction 2026-10-13: a Task Scheduler powershell.exe action opens a
  console window and takes focus). Everything it starts is hidden.

  Safe to run concurrently: a named mutex serialises launchers, and each one
  exits 0 when the port is already served.

  Exit codes: 0 served (already or now); 2 fail-closed (embedder not ready or
  server degraded); 3 server did not start listening; 4 another launcher held
  the lock past the wait.
#>
[CmdletBinding()]
param(
    [int]$Port = 7339,
    [string]$Workspace = 'C:/Repos',
    [int]$EmbedderCheckSeconds = 90,
    [int]$ServerWaitSeconds = 120,
    [switch]$SkipDegradedProbe,
    [string]$RepoWiseExe = (Join-Path $env:USERPROFILE '.local\bin\repowise.exe'),
    [string]$RepoWisePython = (Join-Path $env:APPDATA 'uv\tools\repowise\Scripts\python.exe'),
    [string]$SharedServer = '',
    [string]$RuntimeDir = (Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\repowise-shared')
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 can evaluate parameter defaults before PSScriptRoot
# is populated. Resolve the sibling entry point after parameter binding.
if (-not $SharedServer) { $SharedServer = Join-Path $PSScriptRoot 'shared_server.py' }
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
$log = Join-Path $RuntimeDir 'launcher.log'
function Write-Log([string]$m) { "[$(Get-Date -Format s)] launcher[$PID] $m" | Add-Content -Path $log -Encoding UTF8 }
# Bridges read this to hold real traffic while a freshly started server is
# listening but not yet confirmed off the mock embedder.
$stateFile = Join-Path $RuntimeDir 'launcher.state.json'
$launchStarted = $false
$launchReady = $false
function Set-LaunchState([string]$State) {
    try { @{ pid = $PID; state = $State; at = (Get-Date -Format o) } | ConvertTo-Json -Compress | Set-Content -LiteralPath $stateFile -Encoding UTF8 }
    catch { Write-Log "could not write launcher state: $($_.Exception.Message)" }
}
# A launcher that dies on an unhandled error must still say why; the bridge
# that started it may already be gone, so this log is the only witness.
trap {
    Write-Log "FAIL: unhandled $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    break
}
Write-Log "start (PowerShell $($PSVersionTable.PSVersion), parent $((Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue).ParentProcessId))"

function Test-PortServed {
    [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

# One real probe embedding through shared_server.py --check-embedder. Returns
# $true only on exit 0; a missing environment, a bad key, an unreachable host
# or a timeout is $false. The child never echoes keys or response bodies.
function Test-EmbedderReady {
    $out = Join-Path $RuntimeDir 'embedder-check.log'
    $p = Start-Process -FilePath $RepoWisePython -PassThru -WindowStyle Hidden `
        -ArgumentList "`"$SharedServer`"", "`"$Workspace`"", '--check-embedder' `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    # Windows PowerShell reports no ExitCode unless the handle was opened
    # while the process was still running.
    $null = $p.Handle
    if (-not $p.WaitForExit($EmbedderCheckSeconds * 1000)) {
        try { $p.Kill() } catch { }
        Write-Log "embedder check still running after ${EmbedderCheckSeconds}s; killed PID $($p.Id)"
        return $false
    }
    if ($p.ExitCode -ne 0) { Write-Log "embedder check exited $($p.ExitCode)" }
    return ($p.ExitCode -eq 0)
}

# One MCP round trip: initialize, then a cheap tool call whose `_meta` reports
# whether the embedder fell back to mock. Returns $true (healthy), $false
# (degraded), or $null (could not tell).
function Test-ServerHealthy {
    $url = "http://127.0.0.1:$Port/mcp"
    $headers = @{ Accept = 'application/json, text/event-stream' }
    $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"repowise-launcher","version":"1"}}}'
    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -Body $init -ContentType 'application/json' -Headers $headers -TimeoutSec 60 -UseBasicParsing
        $sid = [string]$r.Headers['Mcp-Session-Id']
        if (-not $sid) { return $null }
        $headers['Mcp-Session-Id'] = $sid
        $headers['MCP-Protocol-Version'] = '2025-06-18'
        $null = Invoke-WebRequest -Uri $url -Method Post -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' -ContentType 'application/json' -Headers $headers -TimeoutSec 30 -UseBasicParsing
        $call = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_repos","arguments":{}}}'
        $r = Invoke-WebRequest -Uri $url -Method Post -Body $call -ContentType 'application/json' -Headers $headers -TimeoutSec 120 -UseBasicParsing
        # Windows PowerShell hands back byte[] for content types it does not
        # treat as text (text/event-stream); decoding it keeps the probe from
        # silently becoming inconclusive.
        $content = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
        try { $null = Invoke-WebRequest -Uri $url -Method Delete -Headers $headers -TimeoutSec 5 -UseBasicParsing } catch { }
        if ($content -match '\\?"embedder_degraded\\?"\s*:\s*true') { return $false }
        if ($content -match '\\?"embedder_degraded\\?"\s*:\s*false') { return $true }
        return $null
    }
    catch {
        Write-Log "health probe failed: $($_.Exception.Message)"
        return $null
    }
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\AgentHub-RepoWiseShared-Launcher')
$owned = $false
try {
    try { $owned = $mutex.WaitOne([TimeSpan]::FromSeconds($EmbedderCheckSeconds + $ServerWaitSeconds + 120)) }
    catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { Write-Log 'another launcher held the lock past the wait; exiting'; exit 4 }

    if (Test-PortServed) {
        $owner = (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
        Write-Log "port $Port already served by PID $owner; exiting"
        exit 0
    }

    if (-not (Test-Path -LiteralPath $RepoWiseExe)) { Write-Log "FAIL: $RepoWiseExe missing"; exit 3 }
    if (-not (Test-Path -LiteralPath $RepoWisePython)) { Write-Log 'FAIL: RepoWise tool Python missing'; exit 3 }
    if (-not (Test-Path -LiteralPath $SharedServer)) { Write-Log 'FAIL: shared server entry point missing'; exit 3 }

    if (-not (Test-EmbedderReady)) {
        Write-Log 'FAIL-CLOSED: Azure embedder environment missing or probe failed; RepoWise NOT started (it would serve mock vectors for its whole life)'
        exit 2
    }
    Write-Log 'embedder ready'
    Write-Log "starting application-owned RepoWise workspace $Workspace on 127.0.0.1:$Port"
    Set-LaunchState 'starting'
    $launchStarted = $true
    $p = Start-Process -FilePath $RepoWisePython `
        -ArgumentList "`"$SharedServer`"", "`"$Workspace`"", '--port', "$Port" `
        -WorkingDirectory ($Workspace -replace '/', '\') -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $RuntimeDir 'stdout.log') `
        -RedirectStandardError (Join-Path $RuntimeDir 'stderr.log')
    Write-Log "started PID $($p.Id)"

    $deadline = (Get-Date).AddSeconds($ServerWaitSeconds)
    while (-not (Test-PortServed)) {
        if ($p.HasExited) { Write-Log "FAIL: repowise exited $($p.ExitCode) before listening; see stderr.log"; exit 3 }
        if ((Get-Date) -gt $deadline) { Write-Log "FAIL: port $Port not listening after ${ServerWaitSeconds}s"; exit 3 }
        Start-Sleep -Milliseconds 500
    }
    Write-Log "listening on $Port"

    if (-not $SkipDegradedProbe) {
        $healthy = Test-ServerHealthy
        if ($healthy -eq $false) {
            Write-Log "FAIL-CLOSED: server reports embedder_degraded=true; stopping PID $($p.Id) and its children"
            # repowise.exe is a launcher over two python.exe levels; stop the tree.
            # Under Windows PowerShell, native stderr with Stop preference is a
            # terminating error, which would turn this exit 2 into an exit 1.
            $ErrorActionPreference = 'Continue'
            & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $p.Id /T /F 2>&1 | Out-Null
            exit 2
        }
        Write-Log "embedder probe: $(if ($healthy) { 'not degraded' } else { 'inconclusive' })"
    }
    Set-LaunchState 'ready'
    $launchReady = $true
    exit 0
}
finally {
    if ($launchStarted -and -not $launchReady) { Set-LaunchState 'failed' }
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
