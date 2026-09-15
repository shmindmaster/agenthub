#Requires -Version 5.1
<#
The Slack agent-facing contract is tools.json. Hosts must expose the same
names and input schemas. This file hashes that contract and refuses an empty
or colliding inventory.

The MCP roundtrip lives in packages/slack/mcp/contract.test.mjs (node --test).
This file is the registry-facing twin so a missing Node test still cannot
claim an empty tools.json is fine.

Run: pwsh -NoProfile -File tests/Test-SlackToolContract.ps1
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

$toolsPath = Join-Path $pkg 'schemas\tools.json'
$doc = Get-Content -LiteralPath $toolsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tools = @($doc.tools)
Report 'tools.json declares a canonical surface' ($tools.Count -ge 20) "found $($tools.Count) tools"

$required = @(
    'slack_search', 'slack_channels', 'slack_users',
    'slack_messages', 'slack_thread',
    'slack_post', 'slack_reply', 'slack_update', 'slack_delete',
    'slack_react', 'slack_unreact',
    'slack_file_get', 'slack_file_upload',
    'slack_permalink', 'slack_channel_info', 'slack_user_info', 'slack_whoami',
    'slack_pin', 'slack_unpin', 'slack_bookmarks',
    'slack_canvas_get', 'slack_list_items',
    'slack_api_read', 'slack_api_write'
)
$names = @($tools | ForEach-Object { [string]$_.name })
$missing = @($required | Where-Object { $names -notcontains $_ })
Report 'required semantic tools are present' ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
Report 'tool names are unique' ($names.Count -eq @($names | Select-Object -Unique).Count) 'duplicate tool name'
$noSchema = @($tools | Where-Object { -not $_.inputSchema })
Report 'every tool has an inputSchema' ($noSchema.Count -eq 0) (($noSchema | ForEach-Object name) -join ', ')

$write = @($tools | Where-Object { $_.name -eq 'slack_api_write' })[0]
Report 'slack_api_write requires approved' (
    $null -ne $write -and @($write.inputSchema.required) -contains 'approved'
) 'escape hatch must require approved'

$node = Get-Command node -ErrorAction SilentlyContinue
Report 'node is on PATH to hash the contract' ($null -ne $node) 'node missing'
if ($node) {
    $printer = Join-Path $pkg 'mcp\print-hash.mjs'
    $hash1 = & $node.Source $printer
    $hash2 = & $node.Source $printer
    $hash1 = ([string]$hash1).Trim()
    $hash2 = ([string]$hash2).Trim()
    Report 'slackContractHash is 64 hex chars' ($hash1 -match '^[A-F0-9]{64}$') "got '$hash1'"
    Report 'slackContractHash is deterministic' ($hash1 -eq $hash2 -and $hash1.Length -eq 64) 'hash changed between runs'
}

$message = Get-Content -LiteralPath (Join-Path $pkg 'schemas\message.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Report 'message schema requires raw and IDs' (
    @($message.required) -contains 'raw' -and
    @($message.required) -contains 'channel_id' -and
    @($message.required) -contains 'ts' -and
    @($message.required) -contains 'author'
) 'lossless message shape drifted'

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
