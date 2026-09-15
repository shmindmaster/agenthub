param(
  [string[]]$RepoPaths = @(
    "C:\Repos\shmindmaster\verigence",
    "C:\Repos\shmindmaster\abacare",
    "C:\Repos\shmindmaster\coledger",
    "C:\Repos\shmindmaster\gentlenext",
    "C:\Repos\shmindmaster\lawli",
    "C:\Repos\shmindmaster\lexalign",
    "C:\Repos\shmindmaster\lienwise",
    "C:\Repos\shmindmaster\subops"
  )
)

$ErrorActionPreference = "Stop"

function Invoke-DoctlJson {
  param([string[]]$Arguments)
  $output = & doctl @Arguments -o json 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
    return @()
  }
  return $output | ConvertFrom-Json
}

$apps = Invoke-DoctlJson @("apps", "list")
$databases = Invoke-DoctlJson @("databases", "list")
$domains = Invoke-DoctlJson @("compute", "domain", "list")
$projects = Invoke-DoctlJson @("projects", "list")

$repoSummaries = foreach ($repo in $RepoPaths) {
  $exists = Test-Path -LiteralPath $repo
  $doSpec = Join-Path $repo ".do\app.yaml"
  [pscustomobject]@{
    repo = Split-Path $repo -Leaf
    path = $repo
    exists = $exists
    has_do_spec = $exists -and (Test-Path -LiteralPath $doSpec)
    has_platform_runbook = $exists -and (Test-Path -LiteralPath (Join-Path $repo "docs\runbooks\platform-operations.md"))
    has_do_sync_script = $exists -and (Test-Path -LiteralPath (Join-Path $repo "scripts\sync-do-spec.sh"))
  }
}

[pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  account = (& doctl account get 2>$null | Out-String).Trim()
  apps = $apps | ForEach-Object {
    [pscustomobject]@{
      id = $_.id
      name = $_.spec.name
      repo = (($_.spec.services | Where-Object { $_.github.repo } | Select-Object -First 1).github.repo)
      domains = @($_.spec.domains | ForEach-Object { $_.domain })
      services = @($_.spec.services | ForEach-Object { $_.name })
      databases = @($_.spec.databases | ForEach-Object { "$($_.name):$($_.engine)" })
      updated_at = $_.updated_at
      active_at = $_.last_deployment_active_at
      default_ingress = $_.default_ingress
    }
  }
  databases = $databases | ForEach-Object {
    [pscustomobject]@{
      name = $_.name
      engine = $_.engine
      version = $_.version
      status = $_.status
      region = $_.region
      size = $_.size
      num_nodes = $_.num_nodes
      db_names = $_.db_names
    }
  }
  domains = $domains | ForEach-Object { [pscustomobject]@{ name = $_.name; ttl = $_.ttl } }
  projects = $projects | ForEach-Object { [pscustomobject]@{ name = $_.name; id = $_.id; environment = $_.environment; is_default = $_.is_default } }
  repos = $repoSummaries
} | ConvertTo-Json -Depth 8
