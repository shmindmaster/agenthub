#Requires -Version 5.1
<#
.SYNOPSIS
  Lifecycle for the fleet OpenConnector gateway (one shared local container).

.DESCRIPTION
  Wraps `docker compose` with the runtime env file and data directory under
  %LOCALAPPDATA%\AgentHub\runtime\open-connector so secrets never sit next to
  the compose file in this repository.

  Verbs:
    start       docker compose up -d (pinned image, loopback only)
    stop        docker compose down (keeps the data directory)
    status      container state + authenticated /v1/health
    probe       MCP initialize + tools/list; prints protocolVersion and tool names
    mint-token  create a persistent runtime token scoped to an action list
                (-Name, -AllowedActions); prints the token ONCE, never stores it
    exit-test   proves the exit path: list connections, revoke a throwaway
                api-key connection, confirm it is gone

  Nothing here reads or prints the encryption key, admin token, or bootstrap
  runtime token. mint-token prints the new token to the console once because
  the runtime does not return it again; put it in the host's environment as
  OPEN_CONNECTOR_RUNTIME_TOKEN.

.EXAMPLE
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 start
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 probe
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 mint-token -Name codex -AllowedActions 'github.*','linear.*'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'probe', 'mint-token', 'exit-test')]
    [string]$Verb,

    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\open-connector'),

    # mint-token
    [string]$Name,
    [string[]]$AllowedActions = @(),
    [string[]]$AllowedConnections = @()
)

$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$composeFile = Join-Path $packageRoot 'docker-compose.yml'
$envFile = Join-Path $RuntimeRoot '.env'

function Read-RuntimeEnv {
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        throw "Runtime env file not found: $envFile. Copy packages/open-connector/.env.example there and fill the values."
    }
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $envFile -Encoding UTF8) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $k, $v = $line -split '=', 2
        $map[$k.Trim()] = $v.Trim()
    }
    foreach ($required in @('OPEN_CONNECTOR_DATA_DIR', 'OPEN_CONNECTOR_ENCRYPTION_KEY', 'OPEN_CONNECTOR_ADMIN_TOKEN', 'OPEN_CONNECTOR_RUNTIME_TOKEN')) {
        if ([string]::IsNullOrWhiteSpace([string]$map[$required])) { throw "Runtime env file is missing $required" }
    }
    if (-not $map.ContainsKey('OPEN_CONNECTOR_PORT')) { $map['OPEN_CONNECTOR_PORT'] = '3400' }
    return $map
}

function Invoke-Compose {
    param([string[]]$Arguments)
    & docker compose --env-file $envFile -f $composeFile @Arguments
    if ($LASTEXITCODE -ne 0) { throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

function Invoke-Runtime {
    param(
        [string]$Path,
        [string]$Method = 'GET',
        [object]$Body = $null,
        [string]$Token,
        [string]$Port
    )
    $headers = @{ 'accept' = 'application/json, text/event-stream'; 'content-type' = 'application/json' }
    if ($Token) { $headers['authorization'] = "Bearer $Token" }
    $uri = "http://127.0.0.1:$Port$Path"
    $params = @{ Uri = $uri; Method = $Method; Headers = $headers; TimeoutSec = 20; UseBasicParsing = $true }
    if ($null -ne $Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress) }
    return Invoke-WebRequest @params
}

function Read-McpResult {
    # The runtime answers MCP over SSE framing: "event: message" / "data: {...}".
    param([string]$Raw)
    $dataLine = ($Raw -split "`n" | Where-Object { $_ -like 'data:*' } | Select-Object -First 1)
    if (-not $dataLine) { throw "No data frame in MCP response: $Raw" }
    return ($dataLine.Substring(5).Trim() | ConvertFrom-Json)
}

$runtime = Read-RuntimeEnv
$port = $runtime['OPEN_CONNECTOR_PORT']
$runtimeToken = $runtime['OPEN_CONNECTOR_RUNTIME_TOKEN']
$adminToken = $runtime['OPEN_CONNECTOR_ADMIN_TOKEN']

switch ($Verb) {
    'start' {
        if (-not (Test-Path -LiteralPath $runtime['OPEN_CONNECTOR_DATA_DIR'])) {
            New-Item -ItemType Directory -Path $runtime['OPEN_CONNECTOR_DATA_DIR'] | Out-Null
        }
        Invoke-Compose @('up', '-d')
        Write-Host "OpenConnector starting on http://127.0.0.1:$port (MCP at /mcp)."
    }
    'stop' {
        Invoke-Compose @('down')
        Write-Host 'OpenConnector stopped. Data directory retained.'
    }
    'status' {
        & docker ps --filter 'name=agenthub-open-connector' --format '{{.Names}}  {{.Status}}  {{.Ports}}'
        try {
            $r = Invoke-Runtime -Path '/v1/health' -Token $runtimeToken -Port $port
            Write-Host "health: HTTP $($r.StatusCode) $($r.Content)"
        } catch {
            Write-Host "health: unreachable ($($_.Exception.Message))"
            exit 1
        }
    }
    'probe' {
        $init = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ protocolVersion = '2025-11-25'; capabilities = @{}; clientInfo = @{ name = 'agenthub-probe'; version = '0' } } }
        $r = Invoke-Runtime -Path '/mcp' -Method 'POST' -Body $init -Token $runtimeToken -Port $port
        $result = Read-McpResult $r.Content
        Write-Host "protocolVersion: $($result.result.protocolVersion)  server: $($result.result.serverInfo.name) $($result.result.serverInfo.version)"
        $list = @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} }
        $r2 = Invoke-Runtime -Path '/mcp' -Method 'POST' -Body $list -Token $runtimeToken -Port $port
        $tools = (Read-McpResult $r2.Content).result.tools
        Write-Host "tools ($($tools.Count)): $(($tools | ForEach-Object { $_.name }) -join ', ')"
        # The gate must be able to fail: an unauthenticated initialize has to be refused.
        try {
            Invoke-Runtime -Path '/mcp' -Method 'POST' -Body $init -Port $port | Out-Null
            Write-Host 'FAIL: unauthenticated /mcp was accepted' -ForegroundColor Red
            exit 1
        } catch {
            Write-Host 'unauthenticated /mcp refused (expected)'
        }
    }
    'mint-token' {
        if ([string]::IsNullOrWhiteSpace($Name)) { throw 'mint-token requires -Name (for example the host id: codex, cursor, opencode, grok).' }
        if ($AllowedActions.Count -eq 0) { throw 'mint-token requires -AllowedActions (for example github.*,linear.*). An empty allowlist is not a safe default.' }
        $body = @{ name = $Name; allowedActions = @($AllowedActions); blockedActions = @(); allowedProxies = @(); allowedConnections = @($AllowedConnections) }
        $r = Invoke-Runtime -Path '/api/runtime-tokens' -Method 'POST' -Body $body -Token $adminToken -Port $port
        # Response shape (verified against v1.5.0): { token, record: { id, name, ... } }.
        $created = $r.Content | ConvertFrom-Json
        $secret = [string]$created.token
        if (-not $secret) { throw 'Token created but the response carried no token field; the response shape changed.' }
        Write-Host "Runtime token '$Name' (id $($created.record.id)) created. Shown once; set it as OPEN_CONNECTOR_RUNTIME_TOKEN in that host's environment:"
        Write-Host $secret
    }
    'exit-test' {
        # Proves the exit path without any provider call. A connection cannot be
        # used for this: PUT /api/connections/{service} verifies the credential
        # against the provider (verified 2026-09-12: a throwaway github api_key
        # was refused with credential_verification_failed), so a throwaway
        # connection would leave the box. A runtime token is created, listed,
        # revoked, and then refused -- all local. Revoking a real connection is
        # the same shape: DELETE /api/connections/{service}?connectionName=<name>.
        $name = "exit-test-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
        $body = @{ name = $name; allowedActions = @('hackernews.*'); blockedActions = @(); allowedProxies = @(); allowedConnections = @() }
        $r = Invoke-Runtime -Path '/api/runtime-tokens' -Method 'POST' -Body $body -Token $adminToken -Port $port
        # Response shape (verified against v1.5.0): { token, record: { id, name, ... } }.
        $created = $r.Content | ConvertFrom-Json
        $throwaway = [string]$created.token
        $id = [string]$created.record.id
        if (-not $throwaway -or -not $id) { throw 'Runtime token creation returned no token/record.id; the response shape changed.' }
        $r = Invoke-Runtime -Path '/v1/health' -Token $throwaway -Port $port
        if ($r.StatusCode -ne 200) { Write-Host 'FAIL: fresh token was not accepted.' -ForegroundColor Red; exit 1 }
        Invoke-Runtime -Path "/api/runtime-tokens/$id" -Method 'DELETE' -Token $adminToken -Port $port | Out-Null
        $r = Invoke-Runtime -Path '/api/runtime-tokens' -Token $adminToken -Port $port
        $stillActive = @(($r.Content | ConvertFrom-Json) | Where-Object { $_.id -eq $id -and -not $_.revokedAt })
        $refused = $false
        try { Invoke-Runtime -Path '/v1/health' -Token $throwaway -Port $port | Out-Null } catch { $refused = $true }
        if ($stillActive.Count -eq 0 -and $refused) { Write-Host "PASS: token '$name' created, accepted, revoked, and refused afterwards." }
        else { Write-Host "FAIL: revoke did not take effect (listedActive=$($stillActive.Count), refused=$refused)." -ForegroundColor Red; exit 1 }
    }
}
