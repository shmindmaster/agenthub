#Requires -Version 5.1
<#
.SYNOPSIS
  Header helper for hosts that start the Devin MCP command with a cleaned environment.

.DESCRIPTION
  Grok's headers_helper and Codex's http_headers_helper on Windows do not pass
  OP_SERVICE_ACCOUNT_TOKEN into the child (Codex: openai/codex issue 46244).
  When this process has no token, copy the User-scope value into the process
  and then run Get-DevinMcpHeaders.ps1. Nothing is printed except that script's
  stdout. Nothing is written to User or Machine scope. A missing token still
  refuses inside the helper.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:OP_SERVICE_ACCOUNT_TOKEN)) {
    $fromUser = [Environment]::GetEnvironmentVariable('OP_SERVICE_ACCOUNT_TOKEN', 'User')
    if (-not [string]::IsNullOrWhiteSpace($fromUser)) {
        [Environment]::SetEnvironmentVariable('OP_SERVICE_ACCOUNT_TOKEN', $fromUser, 'Process')
    }
}
& (Join-Path $PSScriptRoot 'Get-DevinMcpHeaders.ps1')
exit $LASTEXITCODE
