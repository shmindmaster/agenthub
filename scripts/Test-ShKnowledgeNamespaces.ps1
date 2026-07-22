#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Url = "https://shwiki.shtrial.com/api/mcp",
    [string]$TokenEnv = "SHWIKI_MCP_TOKEN",
    [string]$OutputJson = "$env:TEMP\agent-capabilities-shwiki-namespace-check.json",
    [string]$OutputMd = "$env:TEMP\agent-capabilities-shwiki-namespace-check.md"
)

$ErrorActionPreference = 'Stop'

$token = [Environment]::GetEnvironmentVariable($TokenEnv, 'Process')
if ([string]::IsNullOrWhiteSpace($token)) {
    $token = [Environment]::GetEnvironmentVariable($TokenEnv, 'User')
}

$headers = @{
    'Accept' = 'application/json, text/event-stream'
    'Content-Type' = 'application/json'
}
if (-not [string]::IsNullOrWhiteSpace($token)) {
    $headers['Authorization'] = "Bearer $token"
}

$script:McpSessionId = $null

function Get-HeaderValue {
    param(
        $Headers,
        [string]$Name
    )

    if (-not $Headers) { return $null }
    foreach ($k in $Headers.Keys) {
        if ($k -ieq $Name) {
            return [string]$Headers[$k]
        }
    }
    return $null
}

function Invoke-McpJsonRpc {
    param(
        [string]$Method,
        [object]$Params,
        [int]$Id = 1
    )

    $payload = [ordered]@{
        jsonrpc = '2.0'
        id = $Id
        method = $Method
        params = $Params
    }

    $json = $payload | ConvertTo-Json -Depth 8
    $callHeaders = @{}
    foreach ($k in $headers.Keys) { $callHeaders[$k] = $headers[$k] }
    if (-not [string]::IsNullOrWhiteSpace($script:McpSessionId)) {
        $callHeaders['mcp-session-id'] = $script:McpSessionId
    }

    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Post -Headers $callHeaders -Body $json -TimeoutSec 30 -ErrorAction Stop
        $sid = Get-HeaderValue -Headers $resp.Headers -Name 'mcp-session-id'
        if (-not [string]::IsNullOrWhiteSpace($sid)) {
            $script:McpSessionId = $sid
        }

        if ([string]::IsNullOrWhiteSpace($resp.Content)) {
            return [pscustomobject]@{ error = [pscustomobject]@{ code = -2; message = "Empty response while calling $Method" } }
        }

        try {
            return ($resp.Content | ConvertFrom-Json)
        } catch {
            return [pscustomobject]@{ error = [pscustomobject]@{ code = -3; message = "Non-JSON response while calling $Method" } }
        }
    } catch {
        if ($_.Exception.Response) {
            $resp = $_.Exception.Response
            return [pscustomobject]@{
                error = [pscustomobject]@{
                    code = [int]$resp.StatusCode
                    message = "HTTP $([int]$resp.StatusCode) while calling $Method"
                }
            }
        }
        return [pscustomobject]@{
            error = [pscustomobject]@{
                code = -1
                message = $_.Exception.Message
            }
        }
    }
}

$results = @()

$init = Invoke-McpJsonRpc -Method 'initialize' -Params @{
    protocolVersion = '2025-03-26'
    capabilities = @{ }
    clientInfo = @{ name = 'agent-capabilities-test'; version = '1.0.0' }
} -Id 1

$results += [pscustomobject]@{
    check = 'initialize'
    ok = [bool]($init.result)
    detail = if ($init.result) { 'mcp-init-ok' } else { "mcp-init-failed:$($init.error.message)" }
}

$toolNames = @()
if ($init.result) {
    $toolsList = Invoke-McpJsonRpc -Method 'tools/list' -Params @{} -Id 2
    if ($toolsList.result -and $toolsList.result.tools) {
        $toolNames = @($toolsList.result.tools | ForEach-Object { [string]$_.name })
    } else {
        $results += [pscustomobject]@{
            check = 'tools/list'
            ok = $false
            detail = if ($toolsList.error) { "tools-list-failed:$($toolsList.error.message)" } else { 'tools-list-empty' }
            tool = $null
        }
    }
} else {
    $results += [pscustomobject]@{
        check = 'tools/list'
        ok = $false
        detail = 'skipped-due-to-init-failure'
        tool = $null
    }
}

# ShWiki v2 exposes exactly eight job-oriented read-only tools.
$expectedTools = @(
    'wiki.catalog',
    'wiki.search',
    'wiki.get',
    'wiki.analyze',
    'repo.inspect',
    'repo.read',
    'repo.search',
    'repo.compare'
)
$missingTools = @($expectedTools | Where-Object { $_ -notin $toolNames })
$unexpectedTools = @($toolNames | Where-Object { $_ -notin $expectedTools })
$contractOk = $missingTools.Count -eq 0 -and $unexpectedTools.Count -eq 0
$results += [pscustomobject]@{
    check = 'tool-contract'
    ok = $contractOk
    detail = if ($contractOk) { 'exact-eight-tool-contract' } else { "missing=$($missingTools -join ','); unexpected=$($unexpectedTools -join ',')" }
    tool = $null
}

$probes = @(
    @{ namespace = 'wiki'; tool = 'wiki.catalog'; arguments = @{ view = 'repositories' } },
    @{ namespace = 'repo'; tool = 'repo.inspect'; arguments = @{ repository = 'lawli'; operation = 'status' } }
)
foreach ($probe in $probes) {
    if ($probe.tool -notin $toolNames) {
        $results += [pscustomobject]@{
            check = "call:$($probe.namespace)"
            ok = $false
            detail = 'expected-tool-not-discovered'
            tool = $probe.tool
        }
        continue
    }

    $params = @{
        name = $probe.tool
        arguments = $probe.arguments
    }

    try {
        $call = Invoke-McpJsonRpc -Method 'tools/call' -Params $params -Id 100
        $ok = -not $call.error
        $results += [pscustomobject]@{
            check = "call:$($probe.namespace)"
            ok = $ok
            detail = if ($ok) { 'call-ok' } else { "call-error:$($call.error.message)" }
            tool = $probe.tool
        }
    } catch {
        $results += [pscustomobject]@{
            check = "call:$($probe.namespace)"
            ok = $false
            detail = $_.Exception.Message
            tool = $probe.tool
        }
    }
}

$summary = [ordered]@{
    generatedAt = (Get-Date -Format o)
    url = $Url
    usedAuthHeader = -not [string]::IsNullOrWhiteSpace($token)
    discoveredToolCount = $toolNames.Count
    passCount = @($results | Where-Object ok).Count
    failCount = @($results | Where-Object { -not $_.ok }).Count
}

$payload = [ordered]@{
    summary = $summary
    discoveredTools = $toolNames
    checks = $results
}

$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputJson -Encoding UTF8

$md = @()
$md += '# ShWiki Namespace Functional Check'
$md += ''
$md += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ssK')"
$md += ''
$md += "- URL: $Url"
$md += "- Used auth header: $($summary.usedAuthHeader)"
$md += "- Discovered tools: $($summary.discoveredToolCount)"
$md += "- Pass: $($summary.passCount)"
$md += "- Fail: $($summary.failCount)"
$md += ''
$md += '| Check | Tool | OK | Detail |'
$md += '|---|---|---|---|'
foreach ($r in $results) {
    $md += "| $($r.check) | $($r.tool) | $($r.ok) | $($r.detail) |"
}
$md | Set-Content -LiteralPath $OutputMd -Encoding UTF8

Write-Host "Namespace JSON: $OutputJson"
Write-Host "Namespace MD: $OutputMd"
