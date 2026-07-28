#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Url = 'https://repocontext.shtrial.com/api/mcp',
    [string]$TokenEnv = 'REPOCONTEXT_MCP_TOKEN',
    [string]$RepoContextRoot = 'C:\Repos\shmindmaster\repocontext'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$token = [Environment]::GetEnvironmentVariable($TokenEnv, 'Process')
if ([string]::IsNullOrWhiteSpace($token)) {
    $token = [Environment]::GetEnvironmentVariable($TokenEnv, 'User')
}
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Set $TokenEnv in the process or user environment before testing the remote RepoContext MCP."
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoContextRoot 'scripts\verify-remote.mjs') -PathType Leaf)) {
    throw "RepoContext remote verifier not found at $RepoContextRoot"
}

$priorUrl = [Environment]::GetEnvironmentVariable('REPOCONTEXT_MCP_URL', 'Process')
$priorToken = [Environment]::GetEnvironmentVariable('REPOCONTEXT_MCP_TOKEN', 'Process')
try {
    [Environment]::SetEnvironmentVariable('REPOCONTEXT_MCP_URL', $Url, 'Process')
    [Environment]::SetEnvironmentVariable('REPOCONTEXT_MCP_TOKEN', $token, 'Process')
    & pnpm --dir $RepoContextRoot verify:remote
    if ($LASTEXITCODE -ne 0) {
        throw "RepoContext remote contract check failed with exit code $LASTEXITCODE."
    }
}
finally {
    [Environment]::SetEnvironmentVariable('REPOCONTEXT_MCP_URL', $priorUrl, 'Process')
    [Environment]::SetEnvironmentVariable('REPOCONTEXT_MCP_TOKEN', $priorToken, 'Process')
}
