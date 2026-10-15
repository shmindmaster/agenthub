#Requires -Version 5.1
<#
Behavior test: the shared RepoWise server comes back when a host connects, and
never comes back on a mock embedder.

Why: on 2026-10-14 a hard reset took down the Local-AI embedder (8790) and the
shared RepoWise server (7339). Hosts carried a bare HTTP entry, so every host
got ECONNREFUSED and nothing on the RepoWise path could restart the server (the
no-autostart policy forbids logon/scheduled jobs). When an operator did restart
it, Start-RepoWiseShared.ps1 waited 180 s for the embedder and then started
RepoWise anyway, leaving it on mock vectors for its whole life.

Covers:
  1. The bridge (scripts/repowise_bridge.py) unit suite: proxies a live server,
     runs the launcher when the port is down, recovers from a mid-session
     restart and from an expired session, answers the handshake from cache and
     errors fast when the launcher fails closed, spawns windowless.
  2. The launcher, run under Windows PowerShell exactly as the bridge runs it:
     exits 2 and starts nothing when the embedder is down (with and without an
     embedder-start attempt), starts and verifies a healthy server, stops a
     server that reports embedder_degraded, and exits 0 untouched when the port
     is already served.
  3. Every host manifest launches the bridge, and no HTTP-only entry remains.

Run: pwsh -NoProfile -File tests/Test-RepoWiseBridge.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$pkg = Join-Path $repoRoot 'packages\repowise'
$launcher = Join-Path $pkg 'scripts\Start-RepoWiseShared.ps1'
$fake = Join-Path $pkg 'tests\fake_mcp_server.py'

$script:passed = 0
$failures = [Collections.Generic.List[string]]::new()
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$py = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $py) { Report 'py launcher is available' $false 'py.exe not on PATH; the plugin launches the bridge through pyw/py'; exit 1 }
$py = $py.Source
$winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ------------------------------------------------------------ 1. bridge unit
$priorEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$unit = & $py -3 -I (Join-Path $pkg 'tests\test_repowise_bridge.py') 2>&1
$ErrorActionPreference = $priorEap
$unitText = ($unit | ForEach-Object { [string]$_ }) -join "`n"
Report 'bridge unit suite passes' ($LASTEXITCODE -eq 0 -and $unitText -match '(?m)^OK') ($unitText -split "`n" | Select-Object -Last 15 | Out-String)

# --------------------------------------------------------------- 2. launcher
function Get-FreePort {
    $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $l.Start()
    $p = $l.LocalEndpoint.Port; $l.Stop(); return $p
}
function Test-Listening([int]$Port) { [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) }
function Stop-PortOwner([int]$Port) {
    Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $_.OwningProcess /T /F *> $null }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("rwlauncher-" + [Guid]::NewGuid().ToString('N'))
$workspace = Join-Path $scratch 'ws'
New-Item -ItemType Directory -Force -Path $workspace | Out-Null
# The launcher runs `<RepoWiseExe> mcp <workspace> ...` from the workspace, so
# with py.exe as the exe a file named `mcp` there stands in for repowise.
Copy-Item -LiteralPath $fake -Destination (Join-Path $workspace 'mcp')
$marker = Join-Path $scratch 'server-started.txt'
$embedderStub = Join-Path $scratch 'ai.ps1'
$embedderMarker = Join-Path $scratch 'embedder-start-called.txt'
"param([string]`$Action, [string]`$Target) ""`$Action `$Target"" | Set-Content -LiteralPath '$embedderMarker'; exit 0" |
    Set-Content -LiteralPath $embedderStub -Encoding UTF8

function Invoke-Launcher {
    param([int]$Port, [string]$EmbedderUrl, [string[]]$Extra = @(), [switch]$Degraded)
    $runtime = Join-Path $scratch ("rt-" + [Guid]::NewGuid().ToString('N'))
    $env:FAKE_MCP_MARKER = $marker
    $env:FAKE_MCP_DEGRADED = if ($Degraded) { '1' } else { '0' }
    try {
        $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
            '-Port', $Port, '-Workspace', $workspace, '-EmbedderUrl', $EmbedderUrl, '-EmbedderWaitSeconds', 3,
            '-ServerWaitSeconds', 30, '-RepoWiseExe', $py, '-RuntimeDir', $runtime, '-LocalAiCli', $embedderStub) + $Extra
        # Files, not a pipe: the server the launcher starts inherits its std
        # handles, so a piped launcher never reaches EOF. The bridge passes
        # DEVNULL for the same reason.
        $quoted = $argv | ForEach-Object { if ("$_" -match '\s') { "`"$_`"" } else { "$_" } }
        $p = Start-Process -FilePath $winPs -ArgumentList $quoted -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $scratch 'launcher.out') -RedirectStandardError (Join-Path $scratch 'launcher.err')
        if (-not $p.WaitForExit(120000)) { $p.Kill(); $code = -1 } else { $code = $p.ExitCode }
    }
    finally { Remove-Item Env:\FAKE_MCP_MARKER, Env:\FAKE_MCP_DEGRADED -ErrorAction SilentlyContinue }
    $logPath = Join-Path $runtime 'launcher.log'
    $logText = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -Encoding UTF8 } else { '' }
    $statePath = Join-Path $runtime 'launcher.state.json'
    $state = if (Test-Path -LiteralPath $statePath) { [string](Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).state } else { '' }
    [pscustomobject]@{ Code = $code; Log = $logText; State = $state }
}

$embedderPort = Get-FreePort
$deadEmbedder = "http://127.0.0.1:$(Get-FreePort)/v1/models"
$liveEmbedder = "http://127.0.0.1:$embedderPort/v1/models"
$embedderProc = $null
try {
    # 2a. Embedder down, no start allowed: fail closed, start nothing.
    $port = Get-FreePort
    $r = Invoke-Launcher -Port $port -EmbedderUrl $deadEmbedder -Extra @('-NoEmbedderStart')
    Report 'launcher exits 2 when the embedder is down' ($r.Code -eq 2) "exit=$($r.Code) log=$($r.Log)"
    Report 'launcher logs FAIL-CLOSED' ($r.Log -match 'FAIL-CLOSED: embedder') $r.Log
    Report 'launcher does not start repowise on a down embedder' (-not (Test-Path -LiteralPath $marker) -and -not (Test-Listening $port)) 'server marker present or port served'

    # 2b. Embedder down, start attempted through ai.ps1, still down: fail closed.
    $r = Invoke-Launcher -Port $port -EmbedderUrl $deadEmbedder
    Report 'launcher asks ai.ps1 to start retrieval when the embedder is down' ((Test-Path -LiteralPath $embedderMarker) -and ((Get-Content -LiteralPath $embedderMarker -Raw -Encoding UTF8) -match 'start retrieval')) "log=$($r.Log)"
    Report 'launcher still fails closed when the embedder start does not help' ($r.Code -eq 2 -and -not (Test-Path -LiteralPath $marker)) "exit=$($r.Code)"

    # 2c. Embedder up: start, wait for the port, confirm not degraded.
    $embedderProc = Start-Process -FilePath $py -ArgumentList '-3', '-I', "`"$fake`"", '--port', $embedderPort -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Listening $embedderPort) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    $r = Invoke-Launcher -Port $port -EmbedderUrl $liveEmbedder
    Report 'launcher starts repowise when the embedder is ready' ($r.Code -eq 0 -and (Test-Listening $port)) "exit=$($r.Code) log=$($r.Log)"
    Report 'launcher verifies the started server is not degraded' ($r.Log -match 'embedder probe: not degraded') $r.Log
    Report 'launcher marks a verified server ready for bridges' ($r.State -eq 'ready') "state=$($r.State)"

    # 2d. Port already served: exit 0 without touching anything, embedder or not.
    Remove-Item -LiteralPath $marker -Force
    $r = Invoke-Launcher -Port $port -EmbedderUrl $deadEmbedder -Extra @('-NoEmbedderStart')
    Report 'launcher exits 0 when the port is already served' ($r.Code -eq 0 -and $r.Log -match 'already served') "exit=$($r.Code) log=$($r.Log)"
    Report 'launcher starts no second server' (-not (Test-Path -LiteralPath $marker)) 'a second server was started'
    Stop-PortOwner $port

    # 2e. Server comes up degraded: stop it and fail closed.
    $port2 = Get-FreePort
    $r = Invoke-Launcher -Port $port2 -EmbedderUrl $liveEmbedder -Degraded
    Report 'launcher exits 2 when the server reports embedder_degraded' ($r.Code -eq 2 -and $r.Log -match 'embedder_degraded=true') "exit=$($r.Code) log=$($r.Log)"
    Start-Sleep -Seconds 1
    Report 'launcher stops a degraded server' (-not (Test-Listening $port2)) "port $port2 still served"
    Report 'launcher marks a degraded launch failed, not starting' ($r.State -eq 'failed') "state=$($r.State)"
    Stop-PortOwner $port2
}
finally {
    if ($embedderProc) { & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $embedderProc.Id /T /F *> $null }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# -------------------------------------------------------------- 3. manifests
$shared = Get-Content -LiteralPath (Join-Path $pkg '.mcp.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$entry = $shared.mcpServers.'repowise-workspace'
Report 'Claude/Cursor manifest launches the bridge through windowless pyw' ($entry.command -eq 'pyw' -and @($entry.args)[-1] -eq '${CLAUDE_PLUGIN_ROOT}/scripts/repowise_bridge.py') ($entry | ConvertTo-Json -Compress)
Report 'Claude/Cursor manifest carries no HTTP-only entry' (-not $entry.url -and $entry.type -ne 'http') ($entry | ConvertTo-Json -Compress)

$codexPlugin = Get-Content -LiteralPath (Join-Path $pkg '.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Report 'Codex plugin points at its own stdio manifest' ($codexPlugin.mcpServers -eq './mcp.codex.json') "mcpServers=$($codexPlugin.mcpServers)"
$codex = (Get-Content -LiteralPath (Join-Path $pkg 'mcp.codex.json') -Raw -Encoding UTF8 | ConvertFrom-Json).mcpServers.'repowise-workspace'
Report 'Codex manifest launches the bridge relative to the plugin root' ($codex.type -eq 'stdio' -and $codex.command -eq 'pyw' -and @($codex.args)[-1] -eq './scripts/repowise_bridge.py') ($codex | ConvertTo-Json -Compress)

$launcherText = Get-Content -LiteralPath $launcher -Raw -Encoding UTF8
Report 'launcher holds no scheduled-task or logon registration' ($launcherText -notmatch 'Register-ScheduledTask|schtasks|CurrentVersion\\Run') 'scheduled start found'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $script:passed passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $script:passed passed, 0 failed" -ForegroundColor Green
exit 0
