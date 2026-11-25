$ErrorActionPreference = 'Stop'

$pluginRoot = Split-Path -Parent $PSScriptRoot
$node = Get-Command node -ErrorAction Stop
$detector = Join-Path $pluginRoot 'scripts\detect-repository-profile.mjs'
$surfaceInventory = Join-Path $pluginRoot 'scripts\inventory-application-surfaces.mjs'
$validator = Join-Path $pluginRoot 'scripts\validate-artifact.mjs'
$validAudit = Join-Path $PSScriptRoot 'fixtures\valid-audit.md'
$invalidAudit = Join-Path $PSScriptRoot 'fixtures\invalid-audit.md'
$auditWithoutSurfaces = Join-Path $PSScriptRoot 'fixtures\invalid-audit-no-surfaces.md'
$validDesign = Join-Path $PSScriptRoot 'fixtures\valid-design.md'
$validVerify = Join-Path $PSScriptRoot 'fixtures\valid-verify.md'
$surfaceFixture = Join-Path $PSScriptRoot 'fixtures\surface-app'

if (-not (Test-Path -LiteralPath $detector)) { throw 'Missing repository detector.' }
if (-not (Test-Path -LiteralPath $surfaceInventory)) { throw 'Missing application surface inventory.' }
if (-not (Test-Path -LiteralPath $validator)) { throw 'Missing artifact validator.' }

$profileText = & $node.Source $detector $pluginRoot
if ($LASTEXITCODE -ne 0) { throw 'Repository detector failed.' }
$profile = $profileText | ConvertFrom-Json
if ($profile.root -ne $pluginRoot) { throw 'Repository detector returned the wrong root.' }

$surfaceText = & $node.Source $surfaceInventory $surfaceFixture
if ($LASTEXITCODE -ne 0) { throw 'Application surface inventory failed.' }
$surfaces = $surfaceText | ConvertFrom-Json
$expectedSurfaceTypes = @(
    'public-marketing',
    'authentication-onboarding',
    'core-application',
    'customer-administration',
    'internal-operations',
    'billing-commerce',
    'help-support',
    'developer-platform'
)
foreach ($surfaceType in $expectedSurfaceTypes) {
    if ($surfaceType -notin @($surfaces.routes.classification)) { throw "Surface inventory missed classification: $surfaceType" }
}

& $node.Source $validator --type audit $validAudit
if ($LASTEXITCODE -ne 0) { throw 'A valid audit artifact was rejected.' }

$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & $node.Source $validator --type audit $invalidAudit 2>$null
    $invalidAuditExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($invalidAuditExitCode -eq 0) { throw 'An invalid audit artifact was accepted.' }

& $node.Source $validator --type design $validDesign
if ($LASTEXITCODE -ne 0) { throw 'A valid design artifact was rejected.' }

& $node.Source $validator --type verify $validVerify
if ($LASTEXITCODE -ne 0) { throw 'A valid verify artifact was rejected.' }

try {
    $ErrorActionPreference = 'Continue'
    & $node.Source $validator --type audit $auditWithoutSurfaces 2>$null
    $noSurfacesExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($noSurfacesExitCode -eq 0) { throw 'An audit without surface coverage was accepted.' }

# The static UI check passes a clean fixture and fails a bad one on every rule it owns.
$uiChecker = Join-Path $pluginRoot 'scripts\check-ui-rules.mjs'
$uiGood = Join-Path $PSScriptRoot 'fixtures\ui-good'
$uiBad = Join-Path $PSScriptRoot 'fixtures\ui-bad'
try {
    $ErrorActionPreference = 'Continue'
    & $node.Source $uiChecker $uiGood | Out-Null
    $uiGoodExitCode = $LASTEXITCODE
    $uiBadOutput = & $node.Source $uiChecker $uiBad 2>&1 | Out-String
    $uiBadExitCode = $LASTEXITCODE
    & $node.Source $uiChecker --skip viewport-font,letter-spacing,card-radius $uiBad 2>&1 | Out-Null
    $uiSkippedExitCode = $LASTEXITCODE
    & $node.Source $uiChecker --skip not-a-rule $uiBad 2>&1 | Out-Null
    $uiUnknownRuleExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($uiGoodExitCode -ne 0) { throw 'A clean UI fixture was rejected.' }
if ($uiBadExitCode -ne 1) { throw 'A UI fixture that breaks every rule was accepted.' }
foreach ($uiRule in @('viewport-font', 'letter-spacing', 'card-radius')) {
    if ($uiBadOutput -notmatch "(?m) $uiRule`:") { throw "The UI check missed the rule: $uiRule" }
}
if ($uiSkippedExitCode -ne 0) { throw 'Skipping every rule did not clear the findings.' }
if ($uiUnknownRuleExitCode -ne 2) { throw 'An unknown --skip rule was accepted.' }

'PASS: helper scripts inventory SaaS surfaces, enforce artifact contracts and check UI rules.'
