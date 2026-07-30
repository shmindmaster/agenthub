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

function Get-AccountableExternalActionCategory {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action)) { return $null }
    $rules = @(
        @{
            Category = 'payment or financial record'
            Pattern = '\b(?:payments?|money\s+movement|financial\s+(?:attestation|statement(?:\s+of\s+record)?)|paid\s+(?:pilot|commitment)|payer\s+or\s+provider\s+transaction)\b'
        },
        @{
            Category = 'credential, account, or sensitive-access authority'
            Pattern = '\b(?:credentials?(?:\s+provisioning|\s+creation)?|provision(?:ing)?\s+(?:a\s+)?(?:production\s+)?credentials?|oauth(?:\s+or\s+credential)?\s+creation|provider\s+activation|account\s+creation|authority|authorization|permission|approval|consent)\b'
        },
        @{
            Category = 'filing, submission, or formal representation'
            Pattern = '\b(?:regulatory\s+filings?|filings?|submit(?:ting)?|submissions?|representation)\b'
        },
        @{
            Category = 'production or deployment mutation'
            Pattern = '\b(?:(?:mutat(?:e|ion)|chang(?:e|ing)|writ(?:e|ing)|execut(?:e|ion)|publish(?:ing)?|deploy(?:ing|ment)?|rollout)\w*\s+(?:a\s+)?(?:production|live|deployment)|(?:production|live|deployment)\s+(?:mutat(?:e|ion)|chang(?:e|ing)|writ(?:e|ing)|execut(?:e|ion)|publish(?:ing)?|deploy(?:ing|ment)?|rollout))\b'
        },
        @{
            Category = 'binding contract, promise, or external commitment'
            Pattern = '\b(?:binding|commitments?|promises?|agreements?|dealer\s+engagement)\b'
        },
        @{
            Category = 'regulated or professional judgment'
            Pattern = '\b(?:(?:legal|compliance)\s+(?:judgment|strategy|conclusion)|care[- ]delivery\s+action|cross[- ]boundary\s+operational\s+decisions?|security\s+exploit\s+triage)\b'
        }
    )
    foreach ($rule in $rules) {
        if ($Action -match "(?i)$($rule.Pattern)") {
            return [string]$rule.Category
        }
    }
    return $null
}

function Test-IsProcessTheaterGate {
    param([string]$Statement)

    if ([string]::IsNullOrWhiteSpace($Statement)) { return $false }
    if ($Statement -match '(?i)^\s*no\b' -or
        $Statement -match '(?i)\b(?:must|should|need|is|are)\s+not\b' -or
        $Statement -match '(?i)\bnot\s+(?:mandatory|required|a\s+prerequisite)\b') {
        return $false
    }
    $gateSubject = '(?:(?:customer\s+)?interviews?|workshops?|human\s+(?:reviews?|approvals?)|discretionary\s+(?:reviews?|approvals?))'
    $requirement = '(?:await|mandatory|required?|requires?|prerequisites?|quotas?|minimum|at\s+least|two|counts?)'
    return (
        $Statement -match "(?i)\b$requirement\b(?:\s+\w+){0,5}\s+\b$gateSubject\b" -or
        $Statement -match "(?i)\b$gateSubject\b(?:\s+\w+){0,5}\s+\b$requirement\b"
    )
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

    $misclassifiedActions = @(
        foreach ($project in @($policy.portfolio)) {
            foreach ($action in @($project.automate)) {
                $category = Get-AccountableExternalActionCategory -Action ([string]$action)
                if ($category) {
                    "$($project.id): $action [$category]"
                }
            }
        }
    )
    Add-Result -Name 'accountable actions excluded from automate' `
        -Passed ($misclassifiedActions.Count -eq 0) `
        -Detail $(if ($misclassifiedActions.Count -eq 0) {
            'all automate entries are machine-safe or evidence-only'
        } else {
            $misclassifiedActions -join '; '
        })

    $policyStatements = @(
        [string]$policy.policy
        [string]$policy.purpose
        foreach ($className in $expectedClasses) {
            $class = $policy.decisionClasses.$className
            [string]$class.defaultAction
            @($class.requiredEvidence)
            @($class.useFor)
        }
        foreach ($project in @($policy.portfolio)) {
            @($project.automate)
            @($project.retain)
            [string]$project.defaultDecisionClass
        }
        @($policy.guardrails)
    )
    $processTheaterGates = @(
        $policyStatements |
            Where-Object { Test-IsProcessTheaterGate -Statement ([string]$_) }
    )
    Add-Result -Name 'no process-theater gate' -Passed (
        $processTheaterGates.Count -eq 0
    ) -Detail $(if ($processTheaterGates.Count -eq 0) {
        'discretionary interview, workshop, review, and approval requirements are absent'
    } else {
        $processTheaterGates -join '; '
    })
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
