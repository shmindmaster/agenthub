Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
Set-ContextLimits.py is what keeps every coding host's context settings in line.

Covers:
- the registry: every plugin-only host has a setting or a stated reason, so no host is skipped;
- the script, on a fixture: audit writes nothing, apply sets each format and keeps other keys,
  a second run changes nothing, a '*' key reaches every server, and it backs up before writing;
- secrecy: a string value beside a managed key never reaches the output.
#>

$repoRoot = Split-Path -Parent $PSScriptRoot
$script:passed = 0
$script:failed = @()
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passed++ } else { $script:failed += $Message }
}

$registryPath = Join-Path $repoRoot 'registry/context-limits.json'
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding utf8 | ConvertFrom-Json
$policy = (Get-Content -LiteralPath (Join-Path $repoRoot 'registry/mcps.json') -Raw -Encoding utf8 | ConvertFrom-Json).activationPolicy.pluginOnly
$covered = @($registry.settings.host) + @($registry.noDocumentedSetting.PSObject.Properties.Name)
foreach ($hostName in $policy.hosts.PSObject.Properties.Name) {
    Assert-True ($hostName -in $covered) "host '$hostName' has no context setting and no stated reason"
}
foreach ($row in $registry.settings) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.why)) "$($row.host) $($row.key -join '.') has no reason"
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.source)) "$($row.host) $($row.key -join '.') has no source"
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) "context-limits-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    $secret = 'fixture-secret-value-do-not-print'
    New-Item -ItemType Directory -Path (Join-Path $fixture 'a') | Out-Null
    $json = Join-Path $fixture 'a/settings.json'
    $toml = Join-Path $fixture 'a/config.toml'
    $jsonc = Join-Path $fixture 'a/editor.json'
    $mcp = Join-Path $fixture 'a/mcp.json'
    [IO.File]::WriteAllText($json, "{`n  `"apiKey`": `"$secret`",`n  `"models`": { `"m`": { `"window`": 1 } }`n}`n")
    [IO.File]::WriteAllText($toml, "# keep me`nmodel = `"x`"`nlimit = 120000`n`n[table]`ntoken = `"$secret`"`nflag = true`n")
    [IO.File]::WriteAllText($jsonc, "{`n    // keep me`n    `"edit.size`": 12`n}`n")
    [IO.File]::WriteAllText($mcp, "{`n  `"mcpServers`": { `"one`": { `"token`": `"$secret`" }, `"two`": { `"disabled`": false } }`n}`n")

    $rows = @(
        @{ host = 'a'; file = '~/a/settings.json'; format = 'json'; key = @('models', 'm', 'window'); value = 5 }
        @{ host = 'a'; file = '~/a/settings.json'; format = 'json'; key = @('fresh', 'on'); value = $true }
        @{ host = 'b'; file = '~/a/config.toml'; format = 'toml'; key = @('limit'); value = 240000 }
        @{ host = 'b'; file = '~/a/config.toml'; format = 'toml'; key = @('added'); value = 12000 }
        @{ host = 'b'; file = '~/a/config.toml'; format = 'toml'; key = @('table', 'flag'); value = $false }
        @{ host = 'b'; file = '~/a/config.toml'; format = 'toml'; key = @('table', 'other'); value = $false }
        @{ host = 'c'; file = '~/a/editor.json'; format = 'jsonc'; key = @('edit.size'); value = 14 }
        @{ host = 'c'; file = '~/a/editor.json'; format = 'jsonc'; key = @('edit.on'); value = $false }
        @{ host = 'd'; file = '~/a/mcp.json'; format = 'json'; key = @('mcpServers', '*', 'disabled'); value = $true }
        @{ host = 'e'; format = 'user-env'; key = @('FIXTURE_ONLY'); value = '1' }
        @{ host = 'f'; file = '~/a/absent.json'; format = 'json'; key = @('x'); value = 1 }
    )
    $plugins = Join-Path $fixture 'a/plugins.json'
    [IO.File]::WriteAllText($plugins, '{ "enabledPlugins": { "gone@market": true, "kept@market": true, "off@market": false } }')
    $removedPlugins = @{ names = @('gone', 'off'); configs = @(@{ host = 'p'; file = '~/a/plugins.json'; format = 'json'; key = 'enabledPlugins' }) }
    $fixtureRegistry = Join-Path $fixture 'registry.json'
    [IO.File]::WriteAllText($fixtureRegistry, (@{ settings = $rows; removedPlugins = $removedPlugins } | ConvertTo-Json -Depth 6))
    $script = Join-Path $repoRoot 'scripts/Set-ContextLimits.py'
    function Invoke-Limits([string[]]$Extra) {
        return @(& python $script --home $fixture --registry $fixtureRegistry @Extra 2>&1 | ForEach-Object { "$_" })
    }

    $original = Get-Content -LiteralPath $toml -Raw -Encoding utf8
    $audit = Invoke-Limits @()
    Assert-True ($LASTEXITCODE -eq 0) "audit failed: $($audit -join ' ')"
    Assert-True ((Get-Content -LiteralPath $toml -Raw -Encoding utf8) -eq $original) 'audit changed a file'
    Assert-True (($audit -join ' ') -match 'drift') 'audit did not report drift'
    Assert-True (($audit -join ' ') -match 'gone@market: removed plugin is back') 'a removed plugin that returned was not reported'
    Assert-True (($audit -join ' ') -notmatch 'kept@market|off@market') 'only enabled plugins on the removed list are reported'

    $apply = Invoke-Limits @('--apply')
    Assert-True ($LASTEXITCODE -eq 0) "apply failed: $($apply -join ' ')"
    Assert-True ((($audit + $apply) -join ' ') -notmatch $secret) 'a secret beside a managed key reached the output'

    $data = Get-Content -LiteralPath $json -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($data.models.m.window -eq 5 -and $data.fresh.on -eq $true) 'JSON keys not set'
    Assert-True ($data.apiKey -eq $secret) 'JSON lost a neighbouring key'
    $text = Get-Content -LiteralPath $toml -Raw -Encoding utf8
    Assert-True ($text -match '(?m)^limit = 240000') 'TOML key not replaced'
    Assert-True ($text.IndexOf('added = 12000') -lt $text.IndexOf('[table]')) 'TOML key must go before the first table'
    Assert-True ($text -match '# keep me' -and $text.Contains($secret)) 'TOML lost a comment or table'
    Assert-True ($text -match '(?m)^flag = false' -and $text -match '(?m)^other = false') 'TOML table keys not set'
    Assert-True ($text.IndexOf('other = false') -gt $text.IndexOf('[table]')) 'a table key must stay inside its table'
    $editor = Get-Content -LiteralPath $jsonc -Raw -Encoding utf8
    Assert-True ($editor -match '// keep me' -and $editor -match '"edit\.size": 14' -and $editor -match '"edit\.on": false') 'JSONC edit wrong'
    $servers = (Get-Content -LiteralPath $mcp -Raw -Encoding utf8 | ConvertFrom-Json).mcpServers
    Assert-True ($servers.one.disabled -eq $true -and $servers.two.disabled -eq $true) "'*' did not reach every server"
    Assert-True ($servers.one.token -eq $secret) 'a server lost its token'
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'backups')).Count -eq 4) 'each changed file needs one backup'
    Assert-True (($apply -join ' ') -match 'file missing') 'a missing file should be reported'
    Assert-True (($apply -join ' ') -match '\[e\] FIXTURE_ONLY: skipped') 'a fixture run must not touch the user environment'

    $again = Invoke-Limits @('--apply')
    Assert-True (($again -join ' ') -match 'files written=0') 'a second run should change nothing'
    [IO.File]::WriteAllText($plugins, '{ "enabledPlugins": { "kept@market": true } }')
    $again = Invoke-Limits @('--apply')
    Assert-True (($again -join ' ') -notmatch 'drift') 'a second run should report no drift'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -Confirm:$false
}

Write-Host "Test-ContextLimits: passed=$script:passed failed=$($script:failed.Count)"
foreach ($failure in $script:failed) { Write-Host "  FAIL: $failure" }
if ($script:failed.Count -gt 0) { exit 1 }
