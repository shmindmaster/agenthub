[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Repositories,
    [string]$RenovateCommand = (Join-Path $env:LOCALAPPDATA 'AgentHub\portfolio-engineering\tools\node_modules\.bin\renovate.cmd')
)
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'portfolio.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$eligible = @($manifest.repos | Where-Object { $_.dependencyAutomation -eq 'renovate-candidate' -and $_.remote } | ForEach-Object remote)
if (@($Repositories | Where-Object { $_ -cnotin $eligible }).Count) { throw 'Every repository must be an exact allowlisted Renovate candidate.' }
if (-not (Test-Path -LiteralPath $RenovateCommand -PathType Leaf)) { throw 'Pinned Renovate runner is missing.' }
if (-not $env:RENOVATE_TOKEN) { throw 'Provide an existing authorized RENOVATE_TOKEN to this child process; no login or credential changes are performed.' }
$fixed = @{
    PORTFOLIO_RENOVATE_REPOS = ($Repositories | Sort-Object -Unique) -join ','
    RENOVATE_CONFIG_FILE = Join-Path $packageRoot 'renovate\config.cjs'
    RENOVATE_DRY_RUN = 'full'
    RENOVATE_AUTODISCOVER = 'false'
    RENOVATE_REPOSITORIES = ($Repositories | Sort-Object -Unique) -join ','
    RENOVATE_BASE_DIR = Join-Path $env:LOCALAPPDATA 'AgentHub\portfolio-engineering\renovate-work'
}
$old = @{}
try {
    # A previous operator's self-hosted settings must not override this runner.
    # ENV_PREFIX can rename arbitrary variables into RENOVATE_* after startup.
    foreach ($item in @(Get-ChildItem Env: | Where-Object { $_.Name -in @('ENV_PREFIX','GITHUB_COM_TOKEN') -or ($_.Name -like 'RENOVATE_*' -and $_.Name -ne 'RENOVATE_TOKEN') })) {
        $old[$item.Name] = $item.Value
        [Environment]::SetEnvironmentVariable($item.Name, $null, 'Process')
    }
    foreach ($key in $fixed.Keys) {
        if (-not $old.ContainsKey($key)) { $old[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
        [Environment]::SetEnvironmentVariable($key, $fixed[$key], 'Process')
    }
    # No positional arguments: in Renovate 44, `--dry-run full` treats `full`
    # as a repository override. The forced environment keeps discovery scoped.
    & $RenovateCommand
    if ($LASTEXITCODE -ne 0) { throw "Renovate dry-run failed (exit $LASTEXITCODE)." }
} finally {
    foreach ($key in $old.Keys) { [Environment]::SetEnvironmentVariable($key, $old[$key], 'Process') }
}
