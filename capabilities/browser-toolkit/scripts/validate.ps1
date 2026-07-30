[CmdletBinding()]
param(
    [switch]$RunBrowserSmoke,
    [ValidateRange(1024, 65535)]
    [int]$Port = 9333
)

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $toolkitRoot '..\..'))
$results = [Collections.Generic.List[object]]::new()

function Add-Result([string]$Component, [string]$Status, [string]$Evidence) {
    $results.Add([pscustomobject]@{ component = $Component; status = $Status; evidence = $Evidence })
    Write-Host "[$Status] $Component — $Evidence"
}

function Command-Version([string]$Command, [string[]]$Arguments) {
    $found = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $found) { return $null }
    $output = & $Command @Arguments 2>&1 | Select-Object -First 1
    return [string]$output
}

Push-Location $toolkitRoot
try {
    & node scripts/static-check.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Toolkit static checks failed.' }
    Add-Result 'Toolkit files and schemas' 'Verified' 'npm run check'

    $chromeCommand = Get-Command chrome -ErrorAction SilentlyContinue
    $chromeVersion = if ($chromeCommand) { (Get-Item -LiteralPath $chromeCommand.Source).VersionInfo.FileVersion } else { $null }
    if (-not $chromeVersion) {
        $chromePath = Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'
        if (Test-Path -LiteralPath $chromePath) { $chromeVersion = (Get-Item $chromePath).VersionInfo.FileVersion }
    }
    Add-Result 'Chrome' $(if ($chromeVersion) { 'Verified' } else { 'Not verified' }) $(if ($chromeVersion) { $chromeVersion } else { 'not found' })

    foreach ($agent in @(
        @{ Name = 'Hermes'; Command = 'hermes'; Args = @('--version') },
        @{ Name = 'Claude Code'; Command = 'claude'; Args = @('--version') },
        @{ Name = 'OpenCode'; Command = 'opencode'; Args = @('--version') },
        @{ Name = 'Qwen Code'; Command = 'qwen'; Args = @('--version') }
    )) {
        $version = Command-Version $agent.Command $agent.Args
        Add-Result $agent.Name $(if ($version) { 'Verified' } else { 'Not verified' }) $(if ($version) { $version } else { 'command not found' })
    }
    $cursorVendor = Join-Path $env:LOCALAPPDATA 'cursor-agent\cursor-agent.cmd'
    $cursorVersion = if (Test-Path -LiteralPath $cursorVendor) {
        [string](& $cursorVendor --version 2>&1 | Select-Object -First 1)
    } else {
        Command-Version 'cursor-agent' @('--version')
    }
    Add-Result 'Cursor' $(if ($cursorVersion) { 'Verified' } else { 'Not verified' }) $(if ($cursorVersion) { "$cursorVersion; non-paid version check" } else { 'command not found' })

    foreach ($variable in @('QWEN_API_KEY', 'ANTHROPIC_AUTH_TOKEN')) {
        $present = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variable, 'User'))
        Add-Result "$variable presence" $(if ($present) { 'Verified' } else { 'Not verified' }) $(if ($present) { 'present; value not read or printed' } else { 'absent' })
    }

    $configChecks = @(
        @{ Name = 'Claude MCP'; Path = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude.json'); Pattern = 'chrome-devtools-mcp@1.6.0' },
        @{ Name = 'Qwen settings'; Path = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.qwen\settings.json'); Pattern = 'chrome-devtools-mcp@1.6.0' },
        @{ Name = 'OpenCode settings'; Path = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\opencode\opencode.json'); Pattern = 'chrome-devtools-mcp@1.6.0' }
    )
    foreach ($check in $configChecks) {
        $ok = (Test-Path -LiteralPath $check.Path) -and (Select-String -LiteralPath $check.Path -SimpleMatch $check.Pattern -Quiet)
        Add-Result $check.Name $(if ($ok) { 'Verified' } else { 'Not verified' }) $check.Path
    }

    $hermesMcp = & hermes mcp list 2>&1 | Out-String
    Add-Result 'Hermes MCP discovery' $(if ($hermesMcp -match 'chrome-devtools') { 'Verified' } else { 'Not verified' }) 'hermes mcp list'

    if ($RunBrowserSmoke) {
        try {
            Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 | Out-Null
            Add-Result 'Dedicated Chrome CDP' 'Verified' "http://127.0.0.1:$Port/json/version"
        } catch {
            throw "Dedicated QA Chrome is not reachable on port $Port. Run scripts\launch-qa-chrome.ps1 first."
        }

        $reportRoot = Join-Path $repoRoot ('reports\browser-toolkit\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
        $siteOut = Join-Path $reportRoot 'smoke-site.out.log'
        $siteErr = Join-Path $reportRoot 'smoke-site.err.log'
        $site = Start-Process -FilePath (Get-Command node).Source -ArgumentList @('scripts/start-smoke-site.mjs') -WorkingDirectory $toolkitRoot -RedirectStandardOutput $siteOut -RedirectStandardError $siteErr -WindowStyle Hidden -PassThru
        try {
            $ready = $false
            foreach ($attempt in 1..30) {
                try {
                    Invoke-WebRequest -Uri 'http://127.0.0.1:41731/' -UseBasicParsing -TimeoutSec 1 | Out-Null
                    $ready = $true
                    break
                } catch {
                    Start-Sleep -Milliseconds 200
                }
            }
            if (-not $ready) { throw 'Synthetic smoke site did not become ready.' }
            $env:BROWSER_TOOLKIT_OUTPUT_DIR = $reportRoot
            $env:BROWSER_TOOLKIT_CDP_URL = "http://127.0.0.1:$Port"
            $env:BROWSER_TOOLKIT_BASE_URL = 'http://127.0.0.1:41731'
            & node scripts/mcp-smoke.mjs
            if ($LASTEXITCODE -ne 0) { throw "Browser MCP smoke failed. See $reportRoot" }
            Add-Result 'Chrome DevTools MCP browser smoke' 'Verified' $reportRoot
        } finally {
            Remove-Item Env:BROWSER_TOOLKIT_OUTPUT_DIR -ErrorAction SilentlyContinue
            Remove-Item Env:BROWSER_TOOLKIT_CDP_URL -ErrorAction SilentlyContinue
            Remove-Item Env:BROWSER_TOOLKIT_BASE_URL -ErrorAction SilentlyContinue
            if ($site -and -not $site.HasExited) { Stop-Process -Id $site.Id }
        }
    } else {
        Add-Result 'Chrome DevTools MCP browser smoke' 'Not verified' 'Run validate.ps1 -RunBrowserSmoke with dedicated QA Chrome.'
    }

    Add-Result 'Agent model responses' 'Not verified' 'Network model prompts are not used as automated health probes; validate during authorized real work.'
    Add-Result 'Playwright regression' 'Partially verified' 'Existing installations preserved; not installed or owned by this toolkit.'
    Add-Result 'Product demo' 'Not verified' 'No real product was placed in scope; fail-closed readiness workflow only.'

    $report = [pscustomobject]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('o')
        host = $env:COMPUTERNAME
        results = $results
    }
    $reportPath = Join-Path $repoRoot 'reports\browser-toolkit\verification-report.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Write-Host "Verification report: $reportPath"
} finally {
    Pop-Location
}
