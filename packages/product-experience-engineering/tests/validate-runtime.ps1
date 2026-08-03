$ErrorActionPreference = 'Stop'

$pluginRoot = Split-Path -Parent $PSScriptRoot
$node = Get-Command node -ErrorAction Stop
$detector = Join-Path $pluginRoot 'scripts\detect-repository-profile.mjs'
$surfaceInventory = Join-Path $pluginRoot 'scripts\inventory-application-surfaces.mjs'
$validator = Join-Path $pluginRoot 'scripts\validate-product-experience-artifact.mjs'
$validAudit = Join-Path $PSScriptRoot 'fixtures\valid-audit.md'
$invalidAudit = Join-Path $PSScriptRoot 'fixtures\invalid-audit.md'
$validDiscovery = Join-Path $PSScriptRoot 'fixtures\valid-discovery.md'
$invalidDiscovery = Join-Path $PSScriptRoot 'fixtures\invalid-discovery-surface.md'
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

& $node.Source $validator --type discovery $validDiscovery
if ($LASTEXITCODE -ne 0) { throw 'A valid discovery artifact was rejected.' }

try {
    $ErrorActionPreference = 'Continue'
    & $node.Source $validator --type discovery $invalidDiscovery 2>$null
    $invalidDiscoveryExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($invalidDiscoveryExitCode -eq 0) { throw 'Discovery without surface and role coverage was accepted.' }

'PASS: helper scripts inventory SaaS surfaces and enforce artifact contracts.'
