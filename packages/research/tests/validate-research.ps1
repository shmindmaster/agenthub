#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$package = Split-Path -Parent $PSScriptRoot
$expected = @('research-code', 'research-deep', 'research-docs', 'research-entities', 'research-monitor')
$skills = @(Get-ChildItem -LiteralPath (Join-Path $package 'skills') -Directory)
if (Compare-Object $expected @($skills.Name | Sort-Object)) {
    throw 'AH-Research must contain the five registered workflows.'
}
foreach ($skill in $skills) {
    $doc = Get-Content -LiteralPath (Join-Path $skill.FullName 'SKILL.md') -Raw -Encoding UTF8
    $name = [regex]::Escape($skill.Name)
    if ($doc -cnotmatch "(?m)^name: $name\r?$" -or $doc -notmatch '(?m)^description: \S' -or
        $doc -notmatch '(?m)^## Workflow' -or $doc -notmatch '(?m)^## Evidence and access') {
        throw "Invalid AH-Research workflow: $($skill.Name)"
    }
}
foreach ($file in @('.mcp.json', 'mcp.json')) {
    if (Test-Path -LiteralPath (Join-Path $package $file)) {
        throw 'Provider connections belong to the vendor or native host.'
    }
}
Write-Host 'PASS: AH-Research has five task-scoped workflows and no bundled MCP.'
