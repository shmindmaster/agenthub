#Requires -Version 5.1
<#
Behavior test: the shared RepoWise server comes back when a host connects, and
never comes back on a mock embedder.

Why: on 2026-10-14 a hard reset took down the (then local) embedder and the
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
     exits 2 and starts nothing when the Azure embedder environment is missing
     or its probe fails, starts and verifies a healthy server, stops a server
     that reports embedder_degraded, and exits 0 untouched when the port is
     already served. No test reaches Azure: the embedder environment is cleared
     and a fake stands in for the probe.
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
# A public entry-point override lets the launcher exercise a synthetic server.
Copy-Item -LiteralPath $fake -Destination (Join-Path $workspace 'mcp')
$marker = Join-Path $scratch 'server-started.txt'
$checkMarker = Join-Path $scratch 'embedder-check-called.txt'
# The launcher reads the embedder from the environment. Clear every name it
# could read so no test ever reaches Azure; the fake stands in for the probe.
$embedderEnvNames = @('FOUNDRY_OPENAI_BASE_URL', 'FOUNDRY_API_KEY', 'AZURE_AI_SERVICES_KEY', 'FOUNDRY_EMBEDDING_DEPLOYMENT')

function Invoke-Launcher {
    param([int]$Port, [switch]$EmbedderDown, [switch]$Degraded, [switch]$DefaultSharedServer)
    $runtime = Join-Path $scratch ("rt-" + [Guid]::NewGuid().ToString('N'))
    $env:FAKE_MCP_MARKER = $marker
    $env:FAKE_MCP_DEGRADED = if ($Degraded) { '1' } else { '0' }
    $env:FAKE_EMBEDDER_OK = if ($EmbedderDown) { '0' } else { '1' }
    $env:FAKE_EMBEDDER_CHECK_MARKER = $checkMarker
    $saved = @{}
    foreach ($n in $embedderEnvNames) { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process'); [Environment]::SetEnvironmentVariable($n, $null, 'Process') }
    try {
        $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
            '-Port', $Port, '-Workspace', $workspace, '-EmbedderCheckSeconds', 30,
            '-ServerWaitSeconds', 30, '-RepoWiseExe', $py, '-RepoWisePython', $py, '-RuntimeDir', $runtime)
        if (-not $DefaultSharedServer) { $argv += @('-SharedServer', $fake) }
        # Files, not a pipe: the server the launcher starts inherits its std
        # handles, so a piped launcher never reaches EOF. The bridge passes
        # DEVNULL for the same reason.
        $quoted = $argv | ForEach-Object { if ("$_" -match '\s') { "`"$_`"" } else { "$_" } }
        $p = Start-Process -FilePath $winPs -ArgumentList $quoted -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $scratch 'launcher.out') -RedirectStandardError (Join-Path $scratch 'launcher.err')
        if (-not $p.WaitForExit(120000)) { $p.Kill(); $code = -1 } else { $code = $p.ExitCode }
    }
    finally {
        foreach ($n in 'FAKE_MCP_MARKER', 'FAKE_MCP_DEGRADED', 'FAKE_EMBEDDER_OK', 'FAKE_EMBEDDER_CHECK_MARKER') { [Environment]::SetEnvironmentVariable($n, $null, 'Process') }
        foreach ($n in $embedderEnvNames) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'Process') }
    }
    $logPath = Join-Path $runtime 'launcher.log'
    $logText = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -Encoding UTF8 } else { '' }
    $statePath = Join-Path $runtime 'launcher.state.json'
    $state = if (Test-Path -LiteralPath $statePath) { [string](Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).state } else { '' }
    [pscustomobject]@{ Code = $code; Log = $logText; State = $state }
}

try {
    # 2a. Embedder missing or failing: fail closed, start nothing. The default
    # entry point runs the real shared_server.py check with the embedder
    # environment cleared, so it must refuse without any network call.
    $port = Get-FreePort
    $r = Invoke-Launcher -Port $port -EmbedderDown -DefaultSharedServer
    Report 'Windows PowerShell binds the default shared server before failing closed' ($r.Code -eq 2 -and $r.Log -match 'FAIL-CLOSED: Azure embedder') "exit=$($r.Code) log=$($r.Log)"
    Report 'default entry point starts nothing on a missing embedder environment' (-not (Test-Path -LiteralPath $marker) -and -not (Test-Listening $port)) 'server marker present or port served'
    $r = Invoke-Launcher -Port $port -EmbedderDown
    Report 'launcher exits 2 when the embedder probe fails' ($r.Code -eq 2) "exit=$($r.Code) log=$($r.Log)"
    Report 'launcher logs FAIL-CLOSED' ($r.Log -match 'FAIL-CLOSED: Azure embedder') $r.Log
    Report 'launcher ran the embedder probe before deciding' (Test-Path -LiteralPath $checkMarker) 'embedder check was not invoked'
    Report 'launcher does not start repowise on a failing embedder' (-not (Test-Path -LiteralPath $marker) -and -not (Test-Listening $port)) 'server marker present or port served'

    # 2b. The launcher never starts a local embedder on its own behalf.
    $launcherSource = Get-Content -LiteralPath $launcher -Raw -Encoding UTF8
    Report 'launcher starts no local embedder' ($launcherSource -notmatch 'ai\.ps1|8790|start retrieval') 'a local embedder dependency remains'

    # 2c. Embedder probe passes: start, wait for the port, confirm not degraded.
    $r = Invoke-Launcher -Port $port
    Report 'launcher starts repowise when the embedder probe passes' ($r.Code -eq 0 -and (Test-Listening $port)) "exit=$($r.Code) log=$($r.Log)"
    Report 'launcher verifies the started server is not degraded' ($r.Log -match 'embedder probe: not degraded') $r.Log
    Report 'launcher marks a verified server ready for bridges' ($r.State -eq 'ready') "state=$($r.State)"

    # 2d. Port already served: exit 0 without touching anything, embedder or not.
    Remove-Item -LiteralPath $marker -Force
    $r = Invoke-Launcher -Port $port -EmbedderDown
    Report 'launcher exits 0 when the port is already served' ($r.Code -eq 0 -and $r.Log -match 'already served') "exit=$($r.Code) log=$($r.Log)"
    Report 'launcher starts no second server' (-not (Test-Path -LiteralPath $marker)) 'a second server was started'
    Stop-PortOwner $port

    # 2e. Server comes up degraded: stop it and fail closed.
    $port2 = Get-FreePort
    $r = Invoke-Launcher -Port $port2 -Degraded
    Report 'launcher exits 2 when the server reports embedder_degraded' ($r.Code -eq 2 -and $r.Log -match 'embedder_degraded=true') "exit=$($r.Code) log=$($r.Log)"
    Start-Sleep -Seconds 1
    Report 'launcher stops a degraded server' (-not (Test-Listening $port2)) "port $port2 still served"
    Report 'launcher marks a degraded launch failed, not starting' ($r.State -eq 'failed') "state=$($r.State)"
    Stop-PortOwner $port2
}
finally {
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
