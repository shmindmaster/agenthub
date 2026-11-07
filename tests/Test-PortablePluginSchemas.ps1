#Requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$publicPackages = Join-Path $repoRoot 'packages'
$schemaRoot = Join-Path $PSScriptRoot 'schemas/agent-plugins/1.0.0'
$passed = 0
$failed = 0
$publicPluginCount = 0
$privateFileCount = 0

. (Join-Path $repoRoot 'scripts/lib/CapabilityGraph.ps1')
$packageTrees = @($publicPackages)
$overlayRoot = Get-AgentHubOverlayRoot -RepositoryRoot $repoRoot
if ($overlayRoot) {
    $overlayPackages = Join-Path $overlayRoot 'packages'
    if (Test-Path -LiteralPath $overlayPackages -PathType Container) { $packageTrees += $overlayPackages }
}

foreach ($package in Get-ChildItem -LiteralPath $packageTrees -Directory) {
    $privatePackage = $package.Parent.FullName -ne $publicPackages
    $packageLabel = $package.Name
    if ($privatePackage) { $packageLabel = 'personal overlay package' }
    $pluginPath = Join-Path $package.FullName 'plugin.json'
    $mcpPath = Join-Path $package.FullName 'mcp.json'
    if (-not (Test-Path -LiteralPath $pluginPath) -and (Test-Path -LiteralPath $mcpPath)) {
        Write-Host "FAIL: $packageLabel/mcp.json requires a sibling plugin.json"
        $failed++
    }

    foreach ($name in @('plugin', 'mcp')) {
        $path = Join-Path $package.FullName "$name.json"
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if ($privatePackage) { $privateFileCount++ }
        elseif ($name -eq 'plugin') { $publicPluginCount++ }
        $label = "$packageLabel/$name.json"
        $schema = Join-Path $schemaRoot "$name.schema.json"
        try {
            if (-not (Test-Json -LiteralPath $path -SchemaFile $schema)) {
                throw 'The document did not match the schema.'
            }
            if (-not $privatePackage) { Write-Host "PASS: $label conforms to the Agent Plugins 1.0.0 schema" }
            $passed++
        } catch {
            Write-Host "FAIL: $label failed Agent Plugins 1.0.0 schema validation"
            $failed++
        }
    }
}

if ($publicPluginCount -eq 0) {
    Write-Host 'FAIL: no public portable plugin manifests were checked'
    $failed++
}

Write-Host "Personal overlay files checked: $privateFileCount"
Write-Host "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
