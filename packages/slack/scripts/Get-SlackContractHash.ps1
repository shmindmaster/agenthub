#Requires -Version 5.1
<#
Print the canonical Slack contract hash (sha256 of sorted tool names + schemas).
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$printer = Join-Path $here 'mcp\print-hash.mjs'
if (-not (Test-Path -LiteralPath $printer)) {
    throw "missing $printer"
}
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw "node is required to compute slackContractHash"
}
$hash = & $node.Source $printer
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($hash)) {
    throw "print-hash.mjs failed"
}
Write-Output $hash.Trim()
