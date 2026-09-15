param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Redact-Line {
  param([string]$Line)
  if ($null -eq $Line) { return "" }
  return ($Line -replace "fc-[A-Za-z0-9_-]+", "fc-REDACTED")
}

$apiKey = [Environment]::GetEnvironmentVariable("FIRECRAWL_API_KEY")
$firecrawl = Get-Command firecrawl -ErrorAction SilentlyContinue
$node = Get-Command node -ErrorAction SilentlyContinue
$npx = Get-Command npx -ErrorAction SilentlyContinue

$status = [ordered]@{
  firecrawlApiKeyPresent = [bool]$apiKey
  firecrawlCliPresent = [bool]$firecrawl
  nodePresent = [bool]$node
  npxPresent = [bool]$npx
  mcpCommandReady = ([bool]$npx -and [bool]$apiKey)
  cliStatusOk = $false
  cliStatusSummary = @()
  warnings = @()
}

if (-not $apiKey) { $status.warnings += "FIRECRAWL_API_KEY is not set." }
if (-not $npx) { $status.warnings += "npx is not on PATH; the Firecrawl MCP command cannot start." }
if (-not $firecrawl) { $status.warnings += "firecrawl CLI is not on PATH; CLI fallback is unavailable." }

if ($firecrawl) {
  try {
    $raw = & $firecrawl.Source --status 2>&1
    $status.cliStatusSummary = @($raw | ForEach-Object { Redact-Line ([string]$_) } | Select-Object -First 8)
    $status.cliStatusOk = (($LASTEXITCODE -eq 0) -or ($null -eq $LASTEXITCODE))
  } catch {
    $status.cliStatusSummary = @("firecrawl --status failed: $($_.Exception.Message)")
  }
}

if ($Json) { $status | ConvertTo-Json -Depth 6 } else { $status.GetEnumerator() | ForEach-Object { "{0}: {1}" -f $_.Key, (($_.Value -join " | ")) } }
