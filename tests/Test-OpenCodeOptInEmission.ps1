#Requires -Version 5.1
<#
Behavior test: an opt-in-disabled stdio MCP written into OpenCode must be
launchable the moment someone flips enabled=true.

Found 2026-09-13 on the live opencode.json. The slack entry Sync-AgentHub.ps1
had written read:

    "command": ["node", "mcp/slack-mcp.mjs"],
    "environment": { "SLACK_BOT_TOKEN": "${env:SLACK_BOT_TOKEN}", ... }

Two defects, both silent because enabled=false means nothing ever ran it:

  1. The script path was package-relative. OpenCode's `local` shape has no
     cwd, so the path resolves against whatever directory the session was
     opened in -- never this repository. Bundled servers now reference their
     file through a {registryRoot} token that Get-CanonicalMcpEntry expands to
     an absolute path, so the registry stays portable and the host gets
     something it can spawn.
  2. `environment` kept the registry's host-neutral ${env:NAME} spelling.
     OpenCode expands {env:NAME}; the headers path already translated this,
     the environment path did not.

The fixture seeds the exact bad shape that was live, so the convergence
assertion is not vacuous: an existing entry with the old dialect must be
corrected, not merely a fresh one written correctly.

Every -Apply targets a synthetic -RegistryRoot/-UserProfile pair under
$env:AGENTHUB_TEST_SCRATCH. Never the real registry root or user profile.

Run: pwsh -NoProfile -File tests/Test-OpenCodeOptInEmission.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncScript = Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1'
$hostExe = (Get-Process -Id $PID).Path

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

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

function Invoke-SyncAgentHub {
    param([string[]]$ExtraArgs = @())
    $allArgs = @('-NoProfile', '-File', $syncScript) + $ExtraArgs
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

# One fixture: an OpenCode host, one opt-in-disabled stdio server whose script
# is bundled under the fixture registry root, and an opencode.json that already
# carries the defective shape the live machine had.
function New-Fixture {
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-opencode-optin-repo-" + [guid]::NewGuid())
    $profileDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-opencode-optin-profile-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    $bundleDir = Join-Path $root 'packages\fixture-bridge\mcp'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    $serverScript = Join-Path $bundleDir 'bridge.mjs'
    [IO.File]::WriteAllText($serverScript, "process.exit(0)`n", [Text.UTF8Encoding]::new($false))

    $openCodeConfig = Join-Path $profileDir 'opencode.json'

    @{
        activeAgents = @(
            @{ id = 'opencode'; name = 'Fixture OpenCode'; status = 'active'; nativePaths = @{ config = $openCodeConfig } }
        )
        inactiveAgents = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

    @{
        mcpServers = @(
            @{
                id = 'fixture-bridge'
                transport = 'stdio'
                activationMode = 'on-demand-local'
                startupEnabled = $false
                command = 'node'
                args = @('{registryRoot}/packages/fixture-bridge/mcp/bridge.mjs')
                env = @{ FIXTURE_TOKEN = '${env:FIXTURE_TOKEN}'; FIXTURE_MODE = 'fixture' }
                hosts = @('opencode')
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Encoding UTF8 -NoNewline

    @{
        schemaVersion = 2
        capabilities = @(
            @{ id = 'fixture-cap'; owner = 'test'; capabilityType = 'skills'; canonicalSource = 'packages/does-not-exist' }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

    @{
        lifecyclePolicy = @{
            onDemandLocalMcpIds = @('fixture-bridge')
            persistedOnDemandLocalMcpIds = @()
            optInDisabledLocalMcpIds = @('fixture-bridge')
            optInDisabledHosts = @('opencode')
            hostConfiguredLocalMcpIds = @()
        }
        hosts = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryDir 'native-connectors.json') -Encoding UTF8 -NoNewline

    # The defective shape, verbatim from the live machine on 2026-09-13.
    @{
        '$schema' = 'https://opencode.ai/config.json'
        mcp = @{
            'fixture-bridge' = @{
                type = 'local'
                command = @('node', 'mcp/bridge.mjs')
                environment = @{ FIXTURE_TOKEN = '${env:FIXTURE_TOKEN}'; FIXTURE_MODE = 'fixture' }
                enabled = $false
            }
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $openCodeConfig -Encoding UTF8 -NoNewline

    return [pscustomobject]@{
        Root         = $root
        Profile      = $profileDir
        ServerScript = $serverScript
        ConfigPath   = $openCodeConfig
        Args         = @('-Apply', '-RegistryRoot', $root, '-UserProfile', $profileDir)
    }
}

function Remove-Fixture {
    param($Fixture)
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.Profile -Recurse -Force -ErrorAction SilentlyContinue
}

$fixture = New-Fixture
try {
    $run = Invoke-SyncAgentHub -ExtraArgs $fixture.Args
    Report '-Apply against the OpenCode fixture exits 0' ($run.ExitCode -eq 0) "exit $($run.ExitCode). Output: $($run.Output)"

    $config = Get-Content -LiteralPath $fixture.ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = $config.mcp.'fixture-bridge'
    Report 'the opt-in entry is still written' ($null -ne $entry) 'entry missing after -Apply'

    if ($entry) {
        Report 'the opt-in entry stays enabled=false' ($entry.enabled -eq $false) "enabled=$($entry.enabled)"
        Report 'the opt-in entry is type local' ($entry.type -eq 'local') "type=$($entry.type)"

        $command = @($entry.command)
        $scriptArg = if ($command.Count -ge 2) { [string]$command[1] } else { '' }
        $expected = [IO.Path]::GetFullPath($fixture.ServerScript)
        $actual = if ($scriptArg) { [IO.Path]::GetFullPath($scriptArg) } else { '' }
        Report 'the bundled script path is absolute and points at the registry-root copy' (
            [IO.Path]::IsPathRooted($scriptArg) -and $actual -eq $expected
        ) "command=$($command -join ' ')"
        Report 'the bundled script path exists on disk' ($scriptArg -and (Test-Path -LiteralPath $scriptArg)) "command=$($command -join ' ')"
        Report 'no {registryRoot} token leaks into the host config' (($command -join ' ') -notmatch '\{registryRoot\}') "command=$($command -join ' ')"

        $environment = $entry.environment
        $tokenRef = if ($environment) { [string]$environment.FIXTURE_TOKEN } else { '' }
        Report 'environment uses the OpenCode {env:NAME} dialect' ($tokenRef -eq '{env:FIXTURE_TOKEN}') "FIXTURE_TOKEN=$tokenRef"
        Report 'environment does not keep the registry ${env:NAME} spelling' ($tokenRef -notmatch '\$\{env:') "FIXTURE_TOKEN=$tokenRef"
        $literal = if ($environment) { [string]$environment.FIXTURE_MODE } else { '' }
        Report 'literal environment values pass through untouched' ($literal -eq 'fixture') "FIXTURE_MODE=$literal"
    }

    # Idempotency: the corrected file must not churn on a second no-op apply.
    $before = [IO.File]::ReadAllBytes($fixture.ConfigPath)
    $second = Invoke-SyncAgentHub -ExtraArgs $fixture.Args
    $after = [IO.File]::ReadAllBytes($fixture.ConfigPath)
    Report 'a second -Apply is byte-identical' (
        $second.ExitCode -eq 0 -and [Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]]$after)
    ) "exit $($second.ExitCode); bytes changed=$(-not [Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]]$after))"
} finally {
    Remove-Fixture -Fixture $fixture
}

# The real registry must use the token for its one bundled stdio server, and
# the token must resolve to a file that exists in this checkout.
$mcps = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$slack = @($mcps.mcpServers | Where-Object { $_.id -eq 'slack' })[0]
if ($slack) {
    $slackArg = [string](@($slack.args)[0])
    Report 'registry slack args reference the bridge through {registryRoot}' ($slackArg -match '^\{registryRoot\}/packages/slack/mcp/slack-mcp\.mjs$') "args[0]=$slackArg"
    $resolved = $slackArg.Replace('{registryRoot}', $repoRoot)
    Report 'registry slack bridge path resolves to a file in this checkout' (Test-Path -LiteralPath $resolved) "resolved=$resolved"
} else {
    Report 'registry has a slack MCP entry' $false 'missing from registry/mcps.json'
}

# The plugin manifest is loaded by Claude (and Codex, which sets the same
# variable for compatibility) with no guaranteed cwd, so it must anchor the
# bundled script the documented way rather than rely on a relative path.
$pluginManifest = Get-Content -LiteralPath (Join-Path $repoRoot 'packages\slack\.mcp.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginArg = [string](@($pluginManifest.mcpServers.slack.args)[0])
Report 'slack plugin .mcp.json anchors the bridge on ${CLAUDE_PLUGIN_ROOT}' ($pluginArg -eq '${CLAUDE_PLUGIN_ROOT}/mcp/slack-mcp.mjs') "args[0]=$pluginArg"

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
