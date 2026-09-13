#Requires -Version 5.1
<#
.SYNOPSIS
  Lifecycle for the fleet OpenConnector gateway (one shared local container).

.DESCRIPTION
  Wraps `docker compose` with the runtime env file and data directory under
  %LOCALAPPDATA%\AgentHub\runtime\open-connector so secrets never sit next to
  the compose file in this repository.

  Verbs:
    start             docker compose up -d (pinned image, loopback only)
    stop              docker compose down (keeps the data directory)
    status            container state + authenticated /v1/health
    probe             MCP initialize + tools/list; prints protocolVersion and tool names
    connect           create/replace a provider connection (-Service, optional
                      -ConnectionName, -ApiKeyEnv, or -CredentialsJsonEnv)
    disconnect        remove a provider connection (-Service, optional -ConnectionName)
    list-connections  list configured connections, optionally filtered by -Service
    mint-token        create a persistent runtime token scoped to an action list
                      (-Name, -AllowedActions); prints the token ONCE unless
                      -StoreUserEnv is given, in which case it is written
                      straight to that User-scope environment variable instead
    list-tokens       list runtime API tokens (no secret material returned by
                      the runtime for this call)
    revoke-token      revoke one runtime token by id (-Id)
    smoke             call MCP execute_action for one action id and print a
                      compact result summary (-Action, optional -InputJson)
    exit-test         proves the exit path: mints, uses, and revokes a
                      throwaway runtime token, and connects/disconnects a
                      throwaway no-auth provider connection

  Nothing here reads or prints the encryption key, admin token, or bootstrap
  runtime token. mint-token without -StoreUserEnv prints the new token to the
  console once because the runtime does not return it again; put it in the
  host's environment as OPEN_CONNECTOR_AGENT_TOKEN (see
  packages/open-connector/README.md -- this is deliberately NOT the same name
  as the bootstrap OPEN_CONNECTOR_RUNTIME_TOKEN, so a per-host User env var can
  never shadow the compose file's own interpolation). connect never prints an
  -ApiKeyEnv or -CredentialsJsonEnv value; it reads the named environment
  variable and puts it straight into the request body.

.EXAMPLE
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 start
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 probe
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 connect -Service npm
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 mint-token -Name codex -AllowedActions 'brave_search.*','npm.*' -StoreUserEnv OPEN_CONNECTOR_AGENT_TOKEN
  pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 smoke -Action npm.get_package -InputJson '{"packageName":"react"}'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'probe', 'connect', 'disconnect', 'list-connections', 'mint-token', 'list-tokens', 'revoke-token', 'smoke', 'exit-test')]
    [string]$Verb,

    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\open-connector'),

    # connect / disconnect / list-connections
    [string]$Service,
    [string]$ConnectionName,
    [string]$ApiKeyEnv,
    [string]$CredentialsJsonEnv,

    # mint-token
    [string]$Name,
    [string[]]$AllowedActions = @(),
    [string[]]$AllowedConnections = @(),
    [string]$StoreUserEnv,

    # revoke-token
    [string]$Id,

    # smoke
    [string]$Action,
    [string]$InputJson
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

function ConvertTo-StringMap {
    # ConvertFrom-Json -AsHashtable is PowerShell 6+ only; this script targets
    # 5.1, so a JSON object is walked into a [string]->[string] map by hand.
    param([string]$Json)
    $obj = $Json | ConvertFrom-Json
    $map = @{}
    foreach ($prop in $obj.psobject.Properties) { $map[$prop.Name] = [string]$prop.Value }
    return $map
}

function Get-RequiredEnvValue {
    param([string]$EnvName)
    $value = [Environment]::GetEnvironmentVariable($EnvName)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Environment variable '$EnvName' is not set or empty." }
    return $value
}

# `pwsh -File` passes 'a.*,b.*' as ONE string (bash and cmd strip the quotes and
# -File mode never treats the comma as an array separator), so list parameters
# are split here. 'brave_search.*,npm.*' therefore works from any shell.
function Split-RuleList {
    param([string[]]$Values)
    return @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$AllowedActions = Split-RuleList $AllowedActions
$AllowedConnections = Split-RuleList $AllowedConnections

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
    'connect' {
        # Route confirmed against the LIVE container's own OpenAPI document
        # (GET /openapi.json, 2026-09-13): PUT /api/connections/{service} with
        # ConnectionUpsertRequest { authType, connectionName?, values? }. Gated
        # by the admin token, same as the rest of /api/*.
        if ([string]::IsNullOrWhiteSpace($Service)) { throw 'connect requires -Service.' }
        if ($ApiKeyEnv -and $CredentialsJsonEnv) { throw 'connect accepts either -ApiKeyEnv or -CredentialsJsonEnv, not both.' }
        $connName = if ($ConnectionName) { $ConnectionName } else { 'default' }
        if ($ApiKeyEnv) {
            # 'apiKey' is the values field id for api_key providers. Confirmed
            # live 2026-09-13: connect -Service brave_search -ApiKeyEnv
            # BRAVE_API_KEY returned configured=true and
            # brave_search.web_search then succeeded through /mcp.
            $secret = Get-RequiredEnvValue -EnvName $ApiKeyEnv
            $body = @{ authType = 'api_key'; connectionName = $connName; values = @{ apiKey = $secret } }
        } elseif ($CredentialsJsonEnv) {
            $json = Get-RequiredEnvValue -EnvName $CredentialsJsonEnv
            $body = @{ authType = 'custom_credential'; connectionName = $connName; values = (ConvertTo-StringMap -Json $json) }
        } else {
            # Verified live (2026-09-13): every no-auth provider (npm, hackernews,
            # ...) already appears in GET /api/connections as configured=true,
            # virtual=true BEFORE this call is ever made -- no connect call is
            # required. This PUT is an idempotent confirmation, not a creation:
            # it returns the same virtual connection summary either way.
            $body = @{ authType = 'no_auth'; connectionName = $connName }
        }
        $r = Invoke-Runtime -Path "/api/connections/$Service" -Method 'PUT' -Body $body -Token $adminToken -Port $port
        $result = $r.Content | ConvertFrom-Json
        $status = if ($result.configured) { 'configured' } else { 'not configured' }
        Write-Host "service=$($result.service) connectionName=$($result.connectionName) id=$($result.id) authType=$($result.authType) status=$status"
    }
    'disconnect' {
        if ([string]::IsNullOrWhiteSpace($Service)) { throw 'disconnect requires -Service.' }
        $connName = if ($ConnectionName) { $ConnectionName } else { 'default' }
        $path = "/api/connections/$Service`?connectionName=$([Uri]::EscapeDataString($connName))"
        $r = Invoke-Runtime -Path $path -Method 'DELETE' -Token $adminToken -Port $port
        $result = $r.Content | ConvertFrom-Json
        if ($result.configured) {
            # Verified live (2026-09-13): DELETE on a virtual no-auth connection
            # returns 200 with configured=true unchanged -- it cannot be removed,
            # the provider is always available. Report that rather than a false
            # "disconnected".
            Write-Host "service=$($result.service) connectionName=$connName status=still configured (virtual no-auth connections cannot be removed)"
        } else {
            Write-Host "service=$($result.service) connectionName=$connName status=disconnected"
        }
    }
    'list-connections' {
        $r = Invoke-Runtime -Path '/api/connections' -Token $adminToken -Port $port
        # GET /api/connections does not honor a ?service= filter (verified live,
        # 2026-09-13: it returns the full list regardless), unlike the MCP
        # list_connections tool -- so the -Service filter is applied here.
        $items = @($r.Content | ConvertFrom-Json)
        if ($Service) { $items = @($items | Where-Object { $_.service -eq $Service }) }
        foreach ($c in $items) {
            Write-Host "service=$($c.service) connectionName=$($c.connectionName) id=$($c.id) authType=$($c.authType) configured=$($c.configured)"
        }
        Write-Host "$($items.Count) connection(s)."
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
        if ($StoreUserEnv) {
            [Environment]::SetEnvironmentVariable($StoreUserEnv, $secret, 'User')
            Write-Host "Runtime token '$Name' (id $($created.record.id)) created and written to the User-scope environment variable '$StoreUserEnv'. Restart any host process that reads it so the new value takes effect."
        } else {
            Write-Host "Runtime token '$Name' (id $($created.record.id)) created. Shown once; set it as OPEN_CONNECTOR_AGENT_TOKEN in that host's environment:"
            Write-Host $secret
        }
    }
    'list-tokens' {
        $r = Invoke-Runtime -Path '/api/runtime-tokens' -Token $adminToken -Port $port
        $items = @($r.Content | ConvertFrom-Json)
        foreach ($t in $items) {
            Write-Host "name=$($t.name) id=$($t.id) allowedActions=$($t.allowedActions -join ',') createdAt=$($t.createdAt) lastUsedAt=$($t.lastUsedAt)"
        }
        Write-Host "$($items.Count) token(s)."
    }
    'revoke-token' {
        if ([string]::IsNullOrWhiteSpace($Id)) { throw 'revoke-token requires -Id.' }
        $r = Invoke-Runtime -Path "/api/runtime-tokens/$Id" -Method 'DELETE' -Token $adminToken -Port $port
        $result = $r.Content | ConvertFrom-Json
        Write-Host "id=$($result.id) revoked=$($result.revoked)"
    }
    'smoke' {
        if ([string]::IsNullOrWhiteSpace($Action)) { throw 'smoke requires -Action (for example npm.get_package).' }
        $inputObj = if ($InputJson) { $InputJson | ConvertFrom-Json } else { @{} }
        $call = @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = 'execute_action'; arguments = @{ actionId = $Action; input = $inputObj } } }
        $r = Invoke-Runtime -Path '/mcp' -Method 'POST' -Body $call -Token $runtimeToken -Port $port
        $envelope = Read-McpResult $r.Content
        $payload = $envelope.result.content[0].text | ConvertFrom-Json
        if ($payload.ok) {
            $summary = ($payload.data | ConvertTo-Json -Depth 4 -Compress)
            if ($summary.Length -gt 500) { $summary = $summary.Substring(0, 500) + '...' }
            Write-Host "OK: $Action -> $summary"
        } else {
            Write-Host "REFUSED: $Action -> $($payload.error.code): $($payload.error.message)"
        }
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

        # Second leg: connect/disconnect a no-auth provider. hackernews (not
        # npm, to avoid overlapping the manual VERIFY step) is already a
        # virtual connection before this call, so the round trip proves the
        # request/response shapes rather than proving creation -- disconnect on
        # a virtual connection is a verified no-op (see the 'disconnect' verb).
        $connectBody = @{ authType = 'no_auth'; connectionName = 'default' }
        $connectResult = (Invoke-Runtime -Path '/api/connections/hackernews' -Method 'PUT' -Body $connectBody -Token $adminToken -Port $port).Content | ConvertFrom-Json
        $disconnectResult = (Invoke-Runtime -Path '/api/connections/hackernews?connectionName=default' -Method 'DELETE' -Token $adminToken -Port $port).Content | ConvertFrom-Json
        if ($connectResult.configured -and $disconnectResult.service -eq 'hackernews') {
            Write-Host "PASS: no-auth connect/disconnect round trip for 'hackernews' returned the expected connection summaries."
        } else {
            Write-Host "FAIL: no-auth connect/disconnect round trip returned an unexpected shape (connect.configured=$($connectResult.configured), disconnect.service=$($disconnectResult.service))." -ForegroundColor Red
            exit 1
        }
    }
}
