#Requires -Version 7
param([switch]$PublicOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/lib/CapabilityGraph.ps1')
$packages = @(Get-ChildItem (Join-Path $root 'packages') -Directory)
$overlay = Get-AgentHubOverlayRoot -RepositoryRoot $root
if ($overlay -and -not $PublicOnly) { $packages += @(Get-ChildItem (Join-Path $overlay 'packages') -Directory) }
$failures = 0
$passed = 0
foreach ($package in $packages) {
    if (-not (Test-Path (Join-Path $package.FullName 'plugin.json'))) { continue }
    $private = $package.Parent.Name -eq 'packages' -and $package.Parent.FullName -ne (Join-Path $root 'packages')
    $label = if ($private) { 'personal overlay plugin' } else { $package.Name }
    try {
        $fixture = Get-Content (Join-Path $package.FullName 'tests/workflows.json') -Raw | ConvertFrom-Json
        $skills = @(Get-ChildItem (Join-Path $package.FullName 'skills') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') })
        $seen = @{}
        foreach ($scenario in $fixture.scenarios) {
            if ($scenario.kind -notin 'workflow', 'recovery' -or -not $scenario.input -or -not $scenario.expected) { throw 'Incomplete scenario' }
            if ($scenario.skill -notin $skills.Name) { throw 'Unknown fixture skill' }
            $key = "$($scenario.skill)/$($scenario.kind)"
            if ($seen[$key]) { throw 'Duplicate scenario' }
            $seen[$key] = $true
            $skill = Get-Content (Join-Path $package.FullName "skills/$($scenario.skill)/SKILL.md") -Raw
            foreach ($marker in @($scenario.evidence)) {
                if (-not $marker -or -not $skill.Contains($marker)) { throw "Missing documented evidence for $key" }
            }
            if (@($scenario.evidence).Count -lt 2) { throw 'Scenario needs at least two evidence markers' }
        }
        foreach ($skill in $skills) {
            foreach ($kind in 'workflow', 'recovery') {
                if (-not $seen["$($skill.Name)/$kind"]) { throw "Missing $kind for $($skill.Name)" }
            }
        }
        Write-Host "PASS: $label workflow contracts ($($skills.Count) skills)"
        $passed++
    } catch {
        $reason = if ($private) { 'private fixture contract failed' } else { $_.Exception.Message }
        Write-Host "FAIL: $label - $reason"
        $failures++
    }
}
Write-Host "RESULT: $passed passed, $failures failed"
if ($failures) { exit 1 }
