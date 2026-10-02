<#
.SYNOPSIS
  Runs the single shared RepoWise workspace MCP server (streamable HTTP) that
  every host connects to, instead of each host spawning its own stdio copy.

.DESCRIPTION
  One process serves Claude Code, Claude Desktop, Codex, and Cursor at
  http://127.0.0.1:7339/mcp. Waits for the Local-AI embedder (8790) first,
  because RepoWise resolves its embedder once at startup and falls back to a
  mock embedder for the life of the process if 8790 is down.

  Runs from the per-user logon task "RepoWise-Shared". Safe to run
  repeatedly: exits if the port is already served.
#>
[CmdletBinding()]
param(
    [int]$Port = 7339,
    [string]$Workspace = 'C:/Repos',
    [string]$EmbedderUrl = 'http://127.0.0.1:8790/v1/models',
    [int]$EmbedderWaitSeconds = 180
)

$ErrorActionPreference = 'Stop'
$runtime = Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\repowise-shared'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$log = Join-Path $runtime 'launcher.log'
function Write-Log([string]$m) { "[$(Get-Date -Format s)] $m" | Add-Content -Path $log }

$listening = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listening) { Write-Log "port $Port already served by PID $($listening.OwningProcess); exiting"; return }

$deadline = (Get-Date).AddSeconds($EmbedderWaitSeconds)
while ((Get-Date) -lt $deadline) {
    try { $null = Invoke-WebRequest -Uri $EmbedderUrl -TimeoutSec 5 -UseBasicParsing; Write-Log 'embedder ready'; break }
    catch { Start-Sleep -Seconds 10 }
}

$exe = Join-Path $env:USERPROFILE '.local\bin\repowise.exe'
Write-Log "starting $exe mcp $Workspace on 127.0.0.1:$Port"
$p = Start-Process -FilePath $exe `
    -ArgumentList 'mcp', $Workspace, '--transport', 'streamable-http', '--port', "$Port", '--host', '127.0.0.1' `
    -WorkingDirectory ($Workspace -replace '/', '\') -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $runtime 'stdout.log') `
    -RedirectStandardError (Join-Path $runtime 'stderr.log')
Write-Log "started PID $($p.Id)"
