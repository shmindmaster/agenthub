[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $toolkitRoot '..\..'))
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputRoot = Join-Path $repoRoot "reports\browser-toolkit\concurrency-$runId"
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

& (Join-Path $PSScriptRoot 'launch-agent-chrome.ps1') -Agent claude -Mode Persistent
& (Join-Path $PSScriptRoot 'launch-agent-chrome.ps1') -Agent qwen -Mode Persistent
Start-Sleep -Seconds 2

$claudeVersion = Invoke-RestMethod -Uri 'http://127.0.0.1:9341/json/version' -TimeoutSec 5
$qwenVersion = Invoke-RestMethod -Uri 'http://127.0.0.1:9342/json/version' -TimeoutSec 5

$node = (Get-Command node).Source
$site = Start-Process -FilePath $node `
    -ArgumentList 'scripts/start-smoke-site.mjs' `
    -WorkingDirectory $toolkitRoot `
    -WindowStyle Hidden `
    -PassThru
try {
    Start-Sleep -Seconds 1
    $common = @{ BROWSER_TOOLKIT_BASE_URL = 'http://127.0.0.1:41731' }
    $claudeSmoke = Start-Process -FilePath $node `
        -ArgumentList 'scripts/mcp-smoke.mjs' `
        -WorkingDirectory $toolkitRoot `
        -Environment ($common + @{
            BROWSER_TOOLKIT_CDP_URL = 'http://127.0.0.1:9341'
            BROWSER_TOOLKIT_OUTPUT_DIR = (Join-Path $outputRoot 'claude')
        }) `
        -WindowStyle Hidden `
        -PassThru
    $qwenSmoke = Start-Process -FilePath $node `
        -ArgumentList 'scripts/mcp-smoke.mjs' `
        -WorkingDirectory $toolkitRoot `
        -Environment ($common + @{
            BROWSER_TOOLKIT_CDP_URL = 'http://127.0.0.1:9342'
            BROWSER_TOOLKIT_OUTPUT_DIR = (Join-Path $outputRoot 'qwen')
        }) `
        -WindowStyle Hidden `
        -PassThru

    $claudeSmoke.WaitForExit()
    $qwenSmoke.WaitForExit()
    if ($claudeSmoke.ExitCode -ne 0 -or $qwenSmoke.ExitCode -ne 0) {
        throw "Concurrent smoke failed. Claude exit=$($claudeSmoke.ExitCode), Qwen exit=$($qwenSmoke.ExitCode)"
    }
} finally {
    if ($site -and -not $site.HasExited) { Stop-Process -Id $site.Id }
}

$claudeReport = Get-Content -LiteralPath (Join-Path $outputRoot 'claude\smoke-report.json') -Raw | ConvertFrom-Json
$qwenReport = Get-Content -LiteralPath (Join-Path $outputRoot 'qwen\smoke-report.json') -Raw | ConvertFrom-Json
$result = [pscustomobject]@{
    status = if ($claudeReport.status -eq 'passed' -and $qwenReport.status -eq 'passed') { 'passed' } else { 'failed' }
    claude = @{ port = 9341; browser = $claudeVersion.Browser; smoke = $claudeReport.status }
    qwen = @{ port = 9342; browser = $qwenVersion.Browser; smoke = $qwenReport.status }
    evidence = $outputRoot
}
$result | ConvertTo-Json -Depth 10
if ($result.status -ne 'passed') { exit 1 }
