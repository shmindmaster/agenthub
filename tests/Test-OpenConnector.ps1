#Requires -Version 5.1
<#
Behavior tests for the packages/open-connector fleet SaaS action gateway
package: compose policy defaults, secret hygiene, the honest-scope allowlist,
and the operator wrapper's shape.

Run: pwsh -NoProfile -File tests/Test-OpenConnector.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$pkg = Join-Path $repoRoot 'packages\open-connector'

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

$compose = Read-Utf8 (Join-Path $pkg 'docker-compose.yml')
$wrapper = Read-Utf8 (Join-Path $pkg 'scripts\Invoke-OpenConnector.ps1')
$envExample = Read-Utf8 (Join-Path $pkg '.env.example')
$skill = Read-Utf8 (Join-Path $pkg 'skills\use-open-connector\SKILL.md')
$readme = Read-Utf8 (Join-Path $pkg 'README.md')

foreach ($required in @(
    @{ Name = 'docker-compose.yml'; Value = $compose }
    @{ Name = 'scripts\Invoke-OpenConnector.ps1'; Value = $wrapper }
    @{ Name = '.env.example'; Value = $envExample }
    @{ Name = 'skills\use-open-connector\SKILL.md'; Value = $skill }
    @{ Name = 'README.md'; Value = $readme }
)) {
    Report "package file exists and is readable: $($required.Name)" ($null -ne $required.Value) "missing or empty $($required.Name)"
}

# --- compose: image pin, loopback bind, secret interpolation --------------

Report 'compose image is digest-pinned (@sha256:)' (
    $compose -match 'image:\s*ghcr\.io/oomol-lab/open-connector@sha256:[0-9a-f]{64}'
) 'expected image: ghcr.io/oomol-lab/open-connector@sha256:<64 hex chars>'

Report 'compose port binding starts with 127.0.0.1:' (
    $compose -match '"127\.0\.0\.1:\$\{OPEN_CONNECTOR_PORT:-3400\}:3000"'
) 'expected the ports: mapping to bind 127.0.0.1 on the host side'

foreach ($secretVar in @('OOMOL_CONNECT_ENCRYPTION_KEY', 'OOMOL_CONNECT_ADMIN_TOKEN', 'OOMOL_CONNECT_RUNTIME_TOKEN')) {
    $pattern = [regex]::Escape($secretVar) + ':\s*"\$\{[A-Z_]+:\?[^}]*\}"'
    Report "compose requires $secretVar via `${VAR:?...}" (
        $compose -match $pattern
    ) "expected $secretVar to use the required-with-message interpolation form"
}

# No literal secret-shaped value anywhere in the compose file: a run of 20+
# base64url/hex characters that is NOT part of a ${...} variable expression
# and NOT the pinned image digest (which is itself a public, non-secret
# value). A real leaked token would show up as exactly this shape.
$composeWithoutDigest = $compose -replace '@sha256:[0-9a-f]{64}', '@sha256:REDACTED-DIGEST'
$composeWithoutInterpolation = [regex]::Replace($composeWithoutDigest, '\$\{[^}]*\}', '')
$literalSecretLike = [regex]::Matches($composeWithoutInterpolation, '[A-Za-z0-9_\-]{20,}') |
    Where-Object { $_.Value -notmatch '^(unless-stopped|OOMOL_CONNECT_[A-Z_]+|OPEN_CONNECTOR_[A-Z_]+|agenthub-open-connector|dockerDesktopLinuxEngine|Invoke-OpenConnector\.ps1|Invoke-OpenConnector)$' }
Report 'compose has no literal token-looking value outside ${...} interpolation' (
    $literalSecretLike.Count -eq 0
) "found literal secret-shaped value(s): $((@($literalSecretLike | ForEach-Object { $_.Value })) -join ', ')"

Report 'compose OOMOL_CONNECT_BLOCKED_PROXIES default is *' (
    $compose -match 'OOMOL_CONNECT_BLOCKED_PROXIES:\s*"\$\{OPEN_CONNECTOR_BLOCKED_PROXIES:-\*\}"'
) 'expected the blocked-proxies default to stay *'

$allowedActionsMatch = [regex]::Match($compose, 'OOMOL_CONNECT_ALLOWED_ACTIONS:\s*"\$\{OPEN_CONNECTOR_ALLOWED_ACTIONS:-([^}]*)\}"')
Report 'compose declares OOMOL_CONNECT_ALLOWED_ACTIONS with a default list' $allowedActionsMatch.Success 'could not find the allowlist default in docker-compose.yml'
if ($allowedActionsMatch.Success) {
    $allowDefault = $allowedActionsMatch.Groups[1].Value
    Report 'allowlist default contains brave_search.*' ($allowDefault -match 'brave_search\.\*') "allowlist default: $allowDefault"
    $excludedProviders = @('github', 'linear', 'notion', 'slack', 'railway', 'firecrawl', 'exa', 'descript', 'context7')
    $stillPresent = @($excludedProviders | Where-Object { $allowDefault -match "(^|,)$_\." })
    Report 'allowlist default excludes github/linear/notion/slack/railway/firecrawl/exa/descript/context7' (
        $stillPresent.Count -eq 0
    ) "still present: $($stillPresent -join ', ')"
}

# --- .env.example: names only, no real values ------------------------------

$envLines = @($envExample -split "`r?`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' })
Report '.env.example has at least one active NAME= line' ($envLines.Count -gt 0) 'expected at least OPEN_CONNECTOR_PORT and the secret var names'
$badEnvLines = @($envLines | Where-Object {
    if ($_ -notmatch '^[A-Z_]+=(.*)$') { return $true }
    $value = $Matches[1]
    if ([string]::IsNullOrEmpty($value)) { return $false }
    if ($value -match '^\d+$') { return $false }
    if ($value -match '[<>]') { return $false }
    return $true
})
Report '.env.example lines are NAME= with empty or placeholder values only' (
    $badEnvLines.Count -eq 0
) "line(s) with a non-placeholder value: $($badEnvLines -join ' | ')"

# --- SKILL.md frontmatter --------------------------------------------------

Report 'SKILL.md description starts with Use when, unquoted' (
    $skill -match '(?m)^description:\s*Use when\b'
) 'expected an unquoted description: Use when ...'

# --- README: token model states the agent token, not the bootstrap one ----

Report 'README documents OPEN_CONNECTOR_AGENT_TOKEN' ($readme -match 'OPEN_CONNECTOR_AGENT_TOKEN') 'expected the agent-token env var name to appear'
Report 'README never tells a host to use the bootstrap token as its credential' (
    $readme -notmatch "environment as `[``']?OPEN_CONNECTOR_RUNTIME_TOKEN"
) 'found language directing a host to use OPEN_CONNECTOR_RUNTIME_TOKEN as its own credential'

# --- wrapper: verb coverage and clean parse --------------------------------

$expectedVerbs = @('start', 'stop', 'status', 'probe', 'connect', 'disconnect', 'list-connections', 'mint-token', 'list-tokens', 'revoke-token', 'smoke', 'exit-test')
$validateSetMatch = [regex]::Match($wrapper, '(?s)\[ValidateSet\((.*?)\)\]')
Report 'wrapper declares a ValidateSet for -Verb' $validateSetMatch.Success 'could not find [ValidateSet(...)] in the wrapper'
if ($validateSetMatch.Success) {
    $declaredVerbs = @([regex]::Matches($validateSetMatch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    $missingVerbs = @($expectedVerbs | Where-Object { $declaredVerbs -notcontains $_ })
    Report 'wrapper ValidateSet includes every required verb' (
        $missingVerbs.Count -eq 0
    ) "missing: $($missingVerbs -join ', '); declared: $($declaredVerbs -join ', ')"
}

$wrapperPath = Join-Path $pkg 'scripts\Invoke-OpenConnector.ps1'
$parseTokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($wrapperPath, [ref]$parseTokens, [ref]$parseErrors)
Report 'wrapper parses with zero errors' (
    $null -eq $parseErrors -or $parseErrors.Count -eq 0
) "parse error(s): $((@($parseErrors | ForEach-Object { $_.Message })) -join ' | ')"

# Never print a secret from the connect path: it reads -ApiKeyEnv /
# -CredentialsJsonEnv straight into the request body. (mint-token's
# print-once behavior without -StoreUserEnv is separate and intentional --
# the runtime never returns the token again -- so this check is scoped to the
# 'connect' block only, not the whole file.)
$connectBlockMatch = [regex]::Match($wrapper, "(?s)'connect'\s*\{(.*?)\n\s*'disconnect'\s*\{")
Report "wrapper's connect block extracted for the no-secret-echo check" $connectBlockMatch.Success "could not isolate the 'connect' { ... } block"
if ($connectBlockMatch.Success) {
    $connectBlock = $connectBlockMatch.Groups[1].Value
    Report 'connect block never Write-Hosts the resolved secret value' (
        $connectBlock -notmatch 'Write-Host[^\n]*\$secret\b' -and $connectBlock -notmatch 'Write-Host[^\n]*\$json\b'
    ) 'found a Write-Host referencing the resolved -ApiKeyEnv/-CredentialsJsonEnv value in the connect block'
}

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
