#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RegistryRoot)) {
    $RegistryRoot = Split-Path -Parent $PSScriptRoot
}
$policyPath = Join-Path $RegistryRoot 'registry\automation-gates.json'
$expectedProjects = @(
    'abacare', 'agenthub', 'coledger', 'crewscore', 'gentlenext', 'lawli',
    'lexalign', 'repocontext', 'sabhi', 'subops', 'verigence', 'warrantygains'
)
$expectedClasses = @(
    'machine', 'automated_evidence', 'accountable_external_action', 'fail_closed_exception'
)
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $results.Add([pscustomobject]@{ name = $Name; passed = $Passed; detail = $Detail })
}

try {
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Result -Name 'valid JSON policy' -Passed $true -Detail $policyPath
} catch {
    Add-Result -Name 'valid JSON policy' -Passed $false -Detail $_.Exception.Message
    $policy = $null
}

if ($null -ne $policy) {
    Add-Result -Name 'schema version' -Passed ($policy.schemaVersion -eq 1) -Detail "actual=$($policy.schemaVersion)"
    $actualClasses = @($policy.decisionClasses.PSObject.Properties.Name | Sort-Object)
    Add-Result -Name 'decision classes' -Passed (($actualClasses -join '|') -eq (($expectedClasses | Sort-Object) -join '|')) -Detail ($actualClasses -join ', ')

    foreach ($className in $expectedClasses) {
        $class = $policy.decisionClasses.$className
        Add-Result -Name "decision class: $className" -Passed (
            $null -ne $class -and
            -not [string]::IsNullOrWhiteSpace([string]$class.defaultAction) -and
            @($class.requiredEvidence).Count -gt 0 -and
            @($class.useFor).Count -gt 0
        ) -Detail ([string]$class.defaultAction)
    }

    $actualProjects = @($policy.portfolio.id | Sort-Object)
    Add-Result -Name 'portfolio coverage' -Passed (($actualProjects -join '|') -eq ($expectedProjects -join '|')) -Detail ($actualProjects -join ', ')

    foreach ($project in @($policy.portfolio)) {
        Add-Result -Name "project policy: $($project.id)" -Passed (
            @($project.automate).Count -gt 0 -and
            @($project.retain).Count -gt 0 -and
            [string]$project.defaultDecisionClass -in $expectedClasses
        ) -Detail ([string]$project.defaultDecisionClass)
    }

    $policyText = $policy | ConvertTo-Json -Depth 20
    Add-Result -Name 'no process-theater gate' -Passed (
        $policyText -notmatch '(?i)await human review|mandatory interview|mandatory workshop|discretionary approval count'
    ) -Detail 'legacy discretionary gate phrases are absent'
    Add-Result -Name 'guardrails' -Passed (@($policy.guardrails).Count -ge 5) -Detail "count=$(@($policy.guardrails).Count)"
}

$failed = @($results | Where-Object { -not $_.passed })
$summary = [pscustomobject]@{ pass = @($results).Count - $failed.Count; fail = $failed.Count }
if ($Json) {
    [pscustomobject]@{ summary = $summary; results = @($results) } | ConvertTo-Json -Depth 6
} else {
    foreach ($result in $results) {
        $label = if ($result.passed) { 'PASS' } else { 'FAIL' }
        Write-Host "$label  $($result.name): $($result.detail)"
    }
    Write-Host "Summary: $($summary.pass) pass, $($summary.fail) fail"
}

if ($failed.Count -gt 0) { exit 1 }
