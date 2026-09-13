#Requires -Version 5.1
<#
Behavior tests for the AgentHub-owned Slack capability package.

Slack read/write authority lives in packages/slack, not in a host-native
plugin. These checks keep the package, skill, and plugin manifest from
shipping empty or under a colliding third-party name.

Run: pwsh -NoProfile -File tests/Test-SlackCapability.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$pkg = Join-Path $repoRoot 'packages\slack'

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

$required = @(
    'plugin.json',
    '.claude-plugin\plugin.json',
    '.mcp.json',
    'README.md',
    'schemas\tools.json',
    'schemas\message.json',
    'schemas\identity.json',
    'mcp\slack-mcp.mjs',
    'mcp\contract.mjs',
    'mcp\normalize.mjs',
    'mcp\backend.mjs',
    'fixtures\workspace.json',
    'skills\slack\SKILL.md',
    'skills\slack\references\identity.md',
    'skills\slack\references\messaging.md',
    'skills\slack\references\search.md',
    'skills\slack\references\threads.md',
    'skills\slack\references\rich-content.md',
    'skills\slack\references\writes.md',
    'scripts\Get-SlackContractHash.ps1'
)
foreach ($rel in $required) {
    $p = Join-Path $pkg $rel
    Report "package file exists: $rel" (Test-Path -LiteralPath $p) "missing $p"
}

$skill = Read-Utf8 (Join-Path $pkg 'skills\slack\SKILL.md')
Report 'skill name is slack' ($skill -match '(?m)^name:\s*slack\s*$') 'frontmatter name mismatch'
Report 'skill description starts with Use when' ($skill -match '(?m)^description:\s*"?Use when\b') 'description must start with Use when'
Report 'skill has numbered sections' ($skill -match '(?m)^##\s*1\.') 'expected ## 1.'
Report 'skill says AgentHub owns Slack' ($skill -match 'AgentHub owns Slack') 'ownership sentence missing'
Report 'skill keeps Slack IDs' ($skill -match 'channel_id' -and $skill -match 'thread_ts') 'ID preservation missing'
Report 'skill does not send agents to official Slack MCP as owner' ($skill -notmatch 'mcp\.slack\.com') 'do not make Slack hosted MCP the owner'

$rootPlugin = Get-Content -LiteralPath (Join-Path $pkg 'plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$claudePlugin = Get-Content -LiteralPath (Join-Path $pkg '.claude-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Report 'root plugin name is slack version 1.0.0' ($rootPlugin.name -eq 'slack' -and $rootPlugin.version -eq '1.0.0') 'root plugin.json'
Report 'claude plugin version matches root' ($claudePlugin.version -eq $rootPlugin.version -and $claudePlugin.name -eq 'slack') 'host projection diverged'
Report 'claude plugin declares skills and mcpServers paths' (
    $claudePlugin.skills -eq './skills/' -and $claudePlugin.mcpServers -eq './.mcp.json'
) 'plugin components missing'

$mcpPlugin = Read-Utf8 (Join-Path $pkg '.mcp.json')
Report 'plugin MCP id is slack' ($mcpPlugin -match '"slack"') '.mcp.json'
Report 'plugin MCP uses Claude env dialect' ($mcpPlugin -match '\$\{SLACK_USER_TOKEN\}' -and $mcpPlugin -notmatch '\$\{env:') 'expected ${SLACK_USER_TOKEN}'

$fixture = Read-Utf8 (Join-Path $pkg 'fixtures\workspace.json')
Report 'fixture workspace is synthetic' (
    $fixture -match 'T0FIXTURE' -and $fixture -match 'example\.test' -and $fixture -notmatch 'pendoah' -and $fixture -notmatch 'mahum'
) 'fixture must stay synthetic'

$hashScript = Read-Utf8 (Join-Path $pkg 'scripts\Get-SlackContractHash.ps1')
Report 'hash script fails loudly' ($hashScript -match '\$ErrorActionPreference\s*=\s*''Stop''') 'Get-SlackContractHash.ps1'

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
