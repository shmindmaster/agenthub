$ErrorActionPreference = 'Stop'

$pluginRoot = Split-Path -Parent $PSScriptRoot
$node = Get-Command node -ErrorAction Stop
$validator = Join-Path $pluginRoot 'scripts\validate-demo-readiness-handoff.mjs'
$validFixture = Join-Path $PSScriptRoot 'fixtures\valid-demo-readiness.json'
$temporaryFiles = New-Object System.Collections.Generic.List[string]
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-ExitCode {
    param(
        [string]$Name,
        [int]$Expected,
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $node.Source $validator @Arguments 2>&1 | Out-String
        $actual = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($actual -ne $Expected) {
        throw "$Name expected exit code $Expected but received $actual.`n$output"
    }
}

function Copy-Fixture {
    $path = [IO.Path]::GetTempFileName()
    $temporaryFiles.Add($path)
    $document = Get-Content -LiteralPath $validFixture -Raw | ConvertFrom-Json
    return [pscustomobject]@{
        Path = $path
        Document = $document
    }
}

function Save-Fixture($Fixture) {
    $json = $Fixture.Document | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Fixture.Path, $json, $utf8NoBom)
}

try {
    Assert-ExitCode 'Valid demo-ready handoff' 0 @(
        $validFixture,
        '--current-revision', 'abc123',
        '--expected-handoff-path', '_product-experience/07-demo-readiness-handoff.md'
    )

    Assert-ExitCode 'Revision mismatch' 1 @($validFixture, '--current-revision', 'different-revision')
    Assert-ExitCode 'Handoff path mismatch' 1 @($validFixture, '--expected-handoff-path', '_product-experience/wrong.md')

    $demoReadyWithFailure = Copy-Fixture
    $demoReadyWithFailure.Document.criteria[0].passed = $false
    $demoReadyWithFailure.Document.criteria[0] | Add-Member -NotePropertyName classification -NotePropertyValue 'capture-fixable'
    $demoReadyWithFailure.Document.verdict = 'CONDITIONAL'
    $demoReadyWithFailure.Document.handoffDecision = 'PROCEED-WITH-CAPTURE-TREATMENT'
    $demoReadyWithFailure.Document.captureFixes = @('Crop the unstable edge.')
    Save-Fixture $demoReadyWithFailure
    Assert-ExitCode 'Demo-ready with a failed criterion' 1 @($demoReadyWithFailure.Path)

    $remediableProceed = Copy-Fixture
    $remediableProceed.Document.afterVerdict = 'REMEDIABLE'
    Save-Fixture $remediableProceed
    Assert-ExitCode 'Remediable mapped to video proceed' 1 @($remediableProceed.Path)

    $remediableConditional = Copy-Fixture
    $remediableConditional.Document.afterVerdict = 'REMEDIABLE'
    $remediableConditional.Document.criteria[0].passed = $false
    $remediableConditional.Document.criteria[0] | Add-Member -NotePropertyName classification -NotePropertyValue 'capture-fixable'
    $remediableConditional.Document.verdict = 'CONDITIONAL'
    $remediableConditional.Document.handoffDecision = 'PROCEED-WITH-CAPTURE-TREATMENT'
    $remediableConditional.Document.captureFixes = @('Crop the unstable edge.')
    Save-Fixture $remediableConditional
    Assert-ExitCode 'Remediable mapped to conditional capture' 1 @($remediableConditional.Path)

    $remediableFailClosed = Copy-Fixture
    $remediableFailClosed.Document.afterVerdict = 'REMEDIABLE'
    $remediableFailClosed.Document.criteria[0].passed = $false
    $remediableFailClosed.Document.criteria[0] | Add-Member -NotePropertyName classification -NotePropertyValue 'capture-fixable'
    $remediableFailClosed.Document.verdict = 'FAIL'
    $remediableFailClosed.Document.handoffDecision = 'DO-NOT-RECORD'
    $remediableFailClosed.Document.captureFixes = @('Stabilize the layout before reassessment.')
    $remediableFailClosed.Document | Add-Member -NotePropertyName shortestPathToReady -NotePropertyValue 'Apply the layout fix and rerun all eleven criteria.'
    Save-Fixture $remediableFailClosed
    Assert-ExitCode 'Remediable fail-closed handoff' 0 @($remediableFailClosed.Path)
}
finally {
    foreach ($path in $temporaryFiles) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}

'PASS: demo-readiness handoff semantics fail closed and optional context checks are enforced.'
