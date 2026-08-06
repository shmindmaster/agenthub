#Requires -Version 5.1
<#
.SYNOPSIS
  Optional helper: run chrome-devtools-mcp with --autoConnect (same as registry).

.DESCRIPTION
  Prefer configuring hosts via registry/mcps.json (npx ... --autoConnect).
  This script exists for manual smoke tests from a terminal.
#>
$ErrorActionPreference = 'Stop'
$env:CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS = "true"
Write-Host "Starting chrome-devtools-mcp@1.6.0 --autoConnect (requires Chrome remote-debugging enabled)"
& npx -y chrome-devtools-mcp@1.6.0 --autoConnect --no-usage-statistics --no-performance-crux
exit $LASTEXITCODE
