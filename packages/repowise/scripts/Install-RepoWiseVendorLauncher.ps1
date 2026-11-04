#Requires -Version 7.0
<#
.SYNOPSIS
Point the vendor RepoWise plugins at the Azure-scoped MCP launcher.

.DESCRIPTION
Vendor `repowise mcp` has no Azure provider, so the Claude and Codex plugins start
it through vendor_mcp.py. A plugin update restores the vendor file, so run this
again after updating. Audit is the default; only -Apply writes. Other fields in
each server entry are kept.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$UserProfile = $env:USERPROFILE
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$launcher = (Join-Path $PSScriptRoot 'vendor_mcp.py') -replace '\\', '/'
$hosts = @(
    @{ Name = 'claude'; Glob = '.claude/plugins/cache/repowise/repowise/*/.mcp.json'; Nested = $true }
    @{ Name = 'codex'; Glob = '.codex/plugins/cache/repowise/codex/*/.mcp.json'; Nested = $false }
)

$found = 0
$stale = 0
foreach ($hostEntry in $hosts) {
    foreach ($file in @(Get-ChildItem -Path (Join-Path $UserProfile $hostEntry.Glob) -File -Force -ErrorAction SilentlyContinue)) {
        $found++
        $config = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $servers = if ($hostEntry.Nested) { $config.mcpServers } else { $config }
        $server = $servers.repowise
        if (-not $server) { throw "No repowise server in $($file.FullName)" }
        $current = $server.command -eq 'py' -and @($server.args).Count -eq 2 -and
            $server.args[0] -eq '-3' -and $server.args[1] -eq $launcher
        if ($current) {
            Write-Output "current: $($hostEntry.Name) $($file.FullName)"
            continue
        }
        $stale++
        if (-not $Apply) {
            Write-Output "stale: $($hostEntry.Name) $($file.FullName)"
            continue
        }
        $server.command = 'py'
        $server.args = @('-3', $launcher)
        $json = $config | ConvertTo-Json -Depth 10
        [IO.File]::WriteAllText($file.FullName, $json + "`n", [Text.UTF8Encoding]::new($false))
        Write-Output "updated: $($hostEntry.Name) $($file.FullName)"
    }
}
if ($found -eq 0) { throw 'No vendor RepoWise plugin found.' }
if ($stale -gt 0 -and -not $Apply) { exit 1 }
exit 0
