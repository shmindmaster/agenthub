param(
    [string]$RegistryPath = "C:\Repos\shmindmaster\agenthub\registry\mcps.json",
    [string]$Scope = "global-default",
    [int]$TimeoutSec = 20,
    [string]$OutputJson = "",
    [string]$OutputMd = ""
)

$ErrorActionPreference = "Continue"

function Resolve-Placeholders {
    param(
        [string]$Value,
        [ref]$Missing
    )

    if ([string]::IsNullOrEmpty($Value)) { return $Value }

    $resolved = $Value
    $matches = [regex]::Matches($Value, "\$\{(?:env:)?([A-Z0-9_]+)\}")
    foreach ($match in $matches) {
        $name = $match.Groups[1].Value
        $envVal = [Environment]::GetEnvironmentVariable($name, "Process")
        if ([string]::IsNullOrWhiteSpace($envVal)) {
            $envVal = [Environment]::GetEnvironmentVariable($name, "User")
        }
        if ([string]::IsNullOrWhiteSpace($envVal)) {
            $Missing.Value += $name
            continue
        }
        $resolved = $resolved.Replace($match.Value, $envVal)
    }

    return $resolved
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$targets = @($registry.mcpServers | Where-Object { $_.scope -eq $Scope -and $_.transport -eq "http" })

$initBody = @{
    jsonrpc = "2.0"
    id = "liveness"
    method = "initialize"
    params = @{
        protocolVersion = "2025-03-26"
        capabilities = @{}
        clientInfo = @{ name = "mcp-liveness-check"; version = "1.0.0" }
    }
} | ConvertTo-Json -Depth 8 -Compress

$results = @()

foreach ($m in $targets) {
    $missing = @()
    $resolvedUrl = Resolve-Placeholders -Value ([string]$m.url) -Missing ([ref]$missing)

    $headers = @{
        "Accept" = "application/json, text/event-stream"
        "Content-Type" = "application/json"
    }

    if ($m.headers) {
        foreach ($prop in $m.headers.PSObject.Properties) {
            $headers[$prop.Name] = Resolve-Placeholders -Value ([string]$prop.Value) -Missing ([ref]$missing)
        }
    }

    $status = ""
    $ok = $false
    $mode = ""
    $note = ""

    if ($missing.Count -gt 0) {
        $status = "MISSING_ENV"
        $mode = "config"
    } else {
        $uriRef = $null
        if (-not [Uri]::TryCreate($resolvedUrl, [UriKind]::Absolute, [ref]$uriRef)) {
            $status = "INVALID_URL"
            $mode = "config"
            $note = "Resolved URL is not a valid absolute URI"
            $results += [PSCustomObject]@{
                server = [string]$m.id
                url = [string]$m.url
                status = $status
                ok = $ok
                mode = $mode
                missingEnv = (($missing | Sort-Object -Unique) -join ",")
                note = $note
            }
            continue
        }

        try {
            $resp = Invoke-WebRequest -Uri $uriRef -Method Post -Headers $headers -Body $initBody -TimeoutSec $TimeoutSec -ErrorAction Stop
            $status = [string][int]$resp.StatusCode
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
                $ok = $true
                $mode = "mcp-init"
            } else {
                $mode = "http-post"
            }
        }
        catch {
            if ($_.Exception.Response) {
                $code = [int]$_.Exception.Response.StatusCode
                $status = [string]$code
                if ($code -in 401,403) {
                    $ok = $true
                    $mode = "reachable-auth-required"
                } elseif ($code -in 404,405,406,415,422) {
                    try {
                        $g = Invoke-WebRequest -Uri $uriRef -Method Get -TimeoutSec 15 -ErrorAction Stop
                        $status = "POST:$code GET:$([int]$g.StatusCode)"
                        $ok = $true
                        $mode = "reachable-nonstandard"
                    }
                    catch {
                        $mode = "http-error"
                        $note = $_.Exception.Message
                    }
                } else {
                    $mode = "http-error"
                    $note = $_.Exception.Message
                }
            } else {
                $mode = "network-error"
                $note = $_.Exception.Message
            }
        }
    }

    $results += [PSCustomObject]@{
        server = [string]$m.id
        url = [string]$m.url
        status = $status
        ok = $ok
        mode = $mode
        missingEnv = (($missing | Sort-Object -Unique) -join ",")
        note = if ($note.Length -gt 180) { $note.Substring(0, 180) } else { $note }
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = "$env:TEMP\agenthub-mcp-live-check-$stamp.json"
}
if ([string]::IsNullOrWhiteSpace($OutputMd)) {
    $OutputMd = "$env:TEMP\agenthub-mcp-live-check-$stamp.md"
}

$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputJson -Encoding UTF8

$total = $results.Count
$okCount = ($results | Where-Object { $_.ok }).Count
$md = @()
$md += "# MCP Live Check"
$md += ""
$md += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ssK')"
$md += ""
$md += "- Total tested: $total"
$md += "- Reachable/functional: $okCount"
$md += "- Failed: $($total - $okCount)"
$md += ""
$md += "| Server | Result | Status | Mode | Missing Env |"
$md += "|---|---:|---:|---|---|"
foreach ($r in ($results | Sort-Object server)) {
    $res = if ($r.ok) { "PASS" } else { "FAIL" }
    $md += "| $($r.server) | $res | $($r.status) | $($r.mode) | $($r.missingEnv) |"
}
$md | Set-Content -LiteralPath $OutputMd -Encoding UTF8

Write-Host "JSON report: $OutputJson"
Write-Host "Markdown report: $OutputMd"
$results | Sort-Object server | Format-Table -AutoSize
