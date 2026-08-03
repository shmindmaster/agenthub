param(
  [string]$Path = (Get-Location).Path,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$matches = rg -l -i --glob '!**/node_modules/**' --glob '!**/.git/**' 'firecrawl|FIRECRAWL_API_KEY' $Path 2>$null
$result = [ordered]@{
  path = (Resolve-Path -LiteralPath $Path).Path
  firecrawlApiKeyConfigured = [bool]([Environment]::GetEnvironmentVariable('FIRECRAWL_API_KEY','Process') -or [Environment]::GetEnvironmentVariable('FIRECRAWL_API_KEY','User') -or [Environment]::GetEnvironmentVariable('FIRECRAWL_API_KEY','Machine'))
  matchingFiles = @($matches)
  recommendations = @(
    'Keep Firecrawl credentials server-side only.',
    'Use a bounded crawl or map before a broad crawl.',
    'Persist source URL, fetched time, content hash, and authorization state with derived records.'
  )
}
if ($Json) { $result | ConvertTo-Json -Depth 6 } else { $result | Format-List }
