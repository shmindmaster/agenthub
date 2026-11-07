#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = [IO.Directory]::CreateTempSubdirectory('agenthub-plugin-audit-')
try {
    $cli = Join-Path $root 'scripts/AgentHub.ps1'
    $output = & pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $testRoot.FullName -HostId cursor -PluginId ah-browser -Json
    if ($LASTEXITCODE) { throw "Plugin audit failed: $output" }
    $report = $output | ConvertFrom-Json
    if ($report.mode -ne 'audit' -or @($report.mappings).Count -ne 1) { throw 'Expected one audit row' }
    $row = $report.mappings[0]
    if ($row.host -ne 'cursor' -or $row.plugin -ne 'ah-browser' -or $row.status -ne 'missing' -or -not $row.expected) { throw 'Incorrect filtered row' }
    if (@(Get-ChildItem $testRoot.FullName -Force).Count) { throw 'Read-only audit created files' }
    & pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $testRoot.FullName -HostId cursor -PluginId ah-browser -Apply *> $null
    if ($LASTEXITCODE -eq 0 -or @(Get-ChildItem $testRoot.FullName -Force).Count) { throw 'Apply accepted an unpublished checkout or alternate profile' }
    & pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $testRoot.FullName -HostId invalid-host -Json *> $null
    if ($LASTEXITCODE -eq 0) { throw 'Unknown host filter reported success' }
    Write-Host 'RESULT: 4 passed, 0 failed'
} finally {
    $resolved = (Get-Item -LiteralPath $testRoot.FullName).FullName
    if ($resolved -eq $testRoot.FullName -and (Split-Path -Parent $resolved) -eq $testRoot.Parent.FullName) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
