#Requires -Version 7.0
<#
Exercises Install-RepoWiseVendorLauncher.ps1 against a throwaway profile holding
the real Claude and Codex plugin file shapes.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '../packages/repowise/scripts/Install-RepoWiseVendorLauncher.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) "repowise-launcher-$([guid]::NewGuid().ToString('N'))"
$passed = 0
$failed = 0
function Report([string]$Name, [bool]$Condition) {
    if ($Condition) { $script:passed++; Write-Output "PASS: $Name" }
    else { $script:failed++; Write-Output "FAIL: $Name" }
}
function Invoke-Installer([string[]]$Arguments) {
    $output = & pwsh -NoProfile -File $script -UserProfile $root @Arguments 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

try {
    $claudeDir = Join-Path $root '.claude/plugins/cache/repowise/repowise/0.60.1'
    $codexDir = Join-Path $root '.codex/plugins/cache/repowise/codex/0.9.0'
    $null = New-Item -ItemType Directory -Path $claudeDir, $codexDir -Force
    $claudeFile = Join-Path $claudeDir '.mcp.json'
    $codexFile = Join-Path $codexDir '.mcp.json'
    '{"mcpServers":{"repowise":{"command":"repowise","args":["mcp"]}}}' | Set-Content -LiteralPath $claudeFile
    '{"repowise":{"command":"repowise","args":["mcp"],"startup_timeout_sec":20}}' | Set-Content -LiteralPath $codexFile
    $null = New-Item -ItemType Directory -Path "$claudeDir/.claude-plugin", "$codexDir/.codex-plugin" -Force
    '{"name":"repowise","displayName":"Repowise","author":{"name":"Repowise"}}' | Set-Content "$claudeDir/.claude-plugin/plugin.json"
    '{"name":"codex","interface":{"displayName":"Repowise","brandColor":"#2563EB"}}' | Set-Content "$codexDir/.codex-plugin/plugin.json"
    $vendorBytes = (Get-FileHash -LiteralPath $claudeFile).Hash

    $audit = Invoke-Installer @()
    Report 'audit fails on a vendor file that still starts repowise directly' ($audit.ExitCode -eq 1)
    Report 'audit names both hosts' (($audit.Output -match '^stale: claude').Count -eq 1 -and ($audit.Output -match '^stale: codex').Count -eq 1)
    Report 'audit writes nothing' ((Get-FileHash -LiteralPath $claudeFile).Hash -eq $vendorBytes)

    $apply = Invoke-Installer @('-Apply')
    $claude = Get-Content -LiteralPath $claudeFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $codex = Get-Content -LiteralPath $codexFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Report 'apply succeeds' ($apply.ExitCode -eq 0)
    Report 'Claude shape starts the launcher through py' ($claude.mcpServers.repowise.command -eq 'py' -and $claude.mcpServers.repowise.args[1] -like '*/packages/repowise/scripts/vendor_mcp.py')
    Report 'Codex shape starts the launcher through py' ($codex.repowise.command -eq 'py' -and $codex.repowise.args[1] -like '*/packages/repowise/scripts/vendor_mcp.py')
    Report 'other server fields are kept' ($codex.repowise.startup_timeout_sec -eq 20)
    $claudeManifest = Get-Content "$claudeDir/.claude-plugin/plugin.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $codexManifest = Get-Content "$codexDir/.codex-plugin/plugin.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Report 'Claude display alias keeps vendor identity' ($claudeManifest.displayName -eq 'AH-RepoWise' -and $claudeManifest.name -eq 'repowise' -and $claudeManifest.author.name -eq 'Repowise')
    Report 'Codex display alias keeps vendor identity and artwork' ($codexManifest.interface.displayName -eq 'AH-RepoWise' -and $codexManifest.name -eq 'codex' -and $codexManifest.interface.brandColor -eq '#2563EB')

    $second = Invoke-Installer @('-Apply')
    Report 'a second apply changes nothing' ($second.ExitCode -eq 0 -and ($second.Output -match '^updated:').Count -eq 0)
    $after = Invoke-Installer @()
    Report 'audit passes after apply' ($after.ExitCode -eq 0)

    $emptyRoot = Join-Path $root 'empty'
    $null = New-Item -ItemType Directory -Path $emptyRoot
    $null = & pwsh -NoProfile -File $script -UserProfile $emptyRoot 2>&1
    Report 'a machine with no vendor plugin is an error, not a pass' ($LASTEXITCODE -ne 0)
}
finally {
    if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}

Write-Output "RESULT: $passed passed, $failed failed"
exit ([int]($failed -gt 0))
