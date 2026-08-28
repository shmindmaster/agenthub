#Requires -Version 5.1
<#
Pins the no-write product-repository boundary for Media Studio and exercises
the retained screencast scaffold's fail-closed path check.

Run: pwsh -NoProfile -File tests/Test-MediaStudioRepositoryBoundary.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$media = Join-Path $repoRoot 'packages\media-studio'
$pds = Join-Path $repoRoot 'packages\product-demo-studio'
$failures = [Collections.Generic.List[string]]::new()
$reported = 0

function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return [IO.File]::ReadAllText($Path)
}

$policy = Read-Text (Join-Path $repoRoot 'global-agent-policy.md')
$producer = Read-Text (Join-Path $media 'skills\media-studio\SKILL.md')
$capture = Read-Text (Join-Path $media 'skills\media-studio-capture\SKILL.md')
$compose = Read-Text (Join-Path $media 'skills\media-studio-compose\SKILL.md')
$generate = Read-Text (Join-Path $media 'skills\media-studio-generate\SKILL.md')
$workflows = Read-Text (Join-Path $media 'skills\media-studio\references\workflows.md')
$command = Read-Text (Join-Path $media 'commands\video.md')
$pdsMain = Read-Text (Join-Path $pds 'pipeline\product-demo-studio\SKILL.md')
$pdsCapture = Read-Text (Join-Path $pds 'pipeline\product-demo-studio-capture\SKILL.md')
$pdsRender = Read-Text (Join-Path $pds 'pipeline\product-demo-studio-render\SKILL.md')

Report 'global policy makes product repositories read-only for media' (
    $policy -match '## Media production repository boundary' -and
    $policy -match 'product repository is read-only input' -and
    $policy -match 'separate, explicitly authorized engineering task'
) 'global-agent-policy.md lacks the fleet-wide repository boundary'

Report 'producer forbids every media write class in the product repo' (
    $producer -match 'Hard repository boundary' -and
    $producer -match 'repositoryWritePolicy: read-only' -and
    $producer -match 'Playwright specs' -and
    $producer -match 'Remotion compositions' -and
    $producer -match 'Git state'
) 'producer does not enumerate and prohibit product-repository writes'

Report 'active product config is external, not created in the repo' (
    $producer -notmatch 'Config in the product repo' -and
    $producer -match 'Config in the external job workspace' -and
    $workflows -notmatch 'Product-repo config filename stays' -and
    $workflows -match 'legacy repo copy is read-only input'
) 'active Media Studio guidance still creates or maintains config in the product repo'

Report 'capture, generate, compose, and command keep code and artifacts external' (
    $capture -match 'Never add a capture test' -and
    $generate -match 'Never copy generated plates' -and
    $compose -match 'Never scaffold or edit a Remotion app' -and
    $command -match 'Treat every product repository as read-only'
) 'one or more public entry points omit the no-write rule'

Report 'retained screencast engine already treats product source as read-only' (
    $pdsMain -match 'Product repositories are read-only inputs' -and
    $pdsCapture -match 'external workspace' -and
    $pdsRender -match 'Do not create `apps/videos`'
) 'the internal engine route does not preserve the external-workspace boundary'

$job = Get-Content -LiteralPath (Join-Path $media 'schemas\job.schema.json') -Raw | ConvertFrom-Json
Report 'job schema requires the read-only repository policy' (
    @($job.required) -contains 'repositoryWritePolicy' -and
    $job.properties.repositoryWritePolicy.const -eq 'read-only' -and
    $job.properties.workspace.description -match 'Never a product repo'
) 'job schema does not make repositoryWritePolicy=read-only mandatory'

$versions = @(
    'plugin.json',
    '.claude-plugin\plugin.json',
    '.codex-plugin\plugin.json',
    '.cursor-plugin\plugin.json'
) | ForEach-Object { (Get-Content -LiteralPath (Join-Path $media $_) -Raw | ConvertFrom-Json).version }
Report 'Media Studio host manifests agree on 1.3.1' (
    @($versions | Select-Object -Unique).Count -eq 1 -and $versions[0] -eq '1.3.1'
) "manifest versions: $($versions -join ', ')"

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('media-boundary-' + [guid]::NewGuid().ToString('N'))
$product = Join-Path $scratch 'product'
$inside = Join-Path $product '.media-workspace'
$outside = Join-Path $scratch 'external-media-workspace'
New-Item -ItemType Directory -Path $product -Force | Out-Null
Set-Content -LiteralPath (Join-Path $product 'sentinel.txt') -Value 'unchanged' -NoNewline
$scaffold = Join-Path $pds 'scripts\scaffold-video-workspace.mjs'
try {
    # Windows PowerShell converts a native process's expected stderr into an
    # ErrorRecord. Temporarily keep that record non-terminating so the test can
    # assert the fail-closed exit and message instead of aborting early.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $insideOutput = & node $scaffold --repo $product --workspace $inside --dry-run 2>&1 | Out-String
        $insideExit = $LASTEXITCODE
        $outsideOutput = & node $scaffold --repo $product --workspace $outside --dry-run 2>&1 | Out-String
        $outsideExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $productFiles = @(Get-ChildItem -LiteralPath $product -Recurse -File | ForEach-Object FullName)
    Report 'scaffold rejects a workspace inside the product repository' (
        $insideExit -eq 2 -and $insideOutput -match 'Refusing to scaffold inside the product repository'
    ) "exit=$insideExit output=$insideOutput"
    Report 'scaffold accepts an external dry-run without modifying product source' (
        $outsideExit -eq 0 -and
        $outsideOutput -match 'Product repo remains untouched' -and
        $productFiles.Count -eq 1 -and
        $productFiles[0] -eq (Join-Path $product 'sentinel.txt') -and
        (Get-Content -LiteralPath (Join-Path $product 'sentinel.txt') -Raw) -eq 'unchanged'
    ) "exit=$outsideExit files=$($productFiles -join ', ')"
} finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $scratchFull = [IO.Path]::GetFullPath($scratch)
    if ($scratchFull.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $scratchFull)) {
        Remove-Item -LiteralPath $scratchFull -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
