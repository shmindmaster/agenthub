$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-PortfolioRenovate.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('portfolio-runner-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$stub = Join-Path $fixtureRoot 'stub.ps1'
$output = Join-Path $fixtureRoot 'observed.json'
@'
@{dryRun=$env:RENOVATE_DRY_RUN; repositories=$env:RENOVATE_REPOSITORIES; autodiscover=$env:RENOVATE_AUTODISCOVER; config=$env:RENOVATE_CONFIG_FILE; argsCount=$args.Count; prefix=$env:ENV_PREFIX; endpoint=$env:RENOVATE_ENDPOINT; alternateConfig=$env:RENOVATE_ADDITIONAL_CONFIG_FILE; githubToken=$env:GITHUB_COM_TOKEN} | ConvertTo-Json | Set-Content -LiteralPath $env:PORTFOLIO_RUNNER_FIXTURE_OUTPUT
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $stub
$keys = @('RENOVATE_TOKEN','RENOVATE_DRY_RUN','RENOVATE_REPOSITORIES','RENOVATE_AUTODISCOVER','PORTFOLIO_RUNNER_FIXTURE_OUTPUT','ENV_PREFIX','RENOVATE_ENDPOINT','RENOVATE_ADDITIONAL_CONFIG_FILE','GITHUB_COM_TOKEN')
$old = @{}
foreach($key in $keys) { $old[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
function Must-Fail([scriptblock]$Action, [string]$Pattern) {
    try { & $Action; throw 'Expected rejection did not occur' }
    catch { if ($_.Exception.Message -notmatch $Pattern) { throw } }
}
try {
    $env:RENOVATE_TOKEN='synthetic-fixture-token'
    $env:RENOVATE_DRY_RUN='disabled'
    $env:RENOVATE_REPOSITORIES='unapproved/client'
    $env:RENOVATE_AUTODISCOVER='true'
    $env:PORTFOLIO_RUNNER_FIXTURE_OUTPUT=$output
    $env:ENV_PREFIX='TEST_'
    $env:RENOVATE_ENDPOINT='https://outside.invalid'
    $env:RENOVATE_ADDITIONAL_CONFIG_FILE='unapproved.cjs'
    $env:GITHUB_COM_TOKEN='unapproved-synthetic-token'
    & $runner -Repositories shmindmaster/mahumtech -RenovateCommand $stub
    $observed=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if ($observed.dryRun -ne 'full' -or $observed.repositories -ne 'shmindmaster/mahumtech' -or $observed.autodiscover -ne 'false' -or $observed.argsCount -ne 0) {throw 'Forced scope/dry-run contract failed'}
    if ($observed.prefix -or $observed.endpoint -or $observed.alternateConfig -or $observed.githubToken) {throw 'Inherited self-hosted overrides leaked into the child'}
    if ($env:ENV_PREFIX -ne 'TEST_' -or $env:RENOVATE_ENDPOINT -ne 'https://outside.invalid' -or $env:RENOVATE_ADDITIONAL_CONFIG_FILE -ne 'unapproved.cjs') {throw 'Inherited self-hosted settings were not restored'}
    if ($env:RENOVATE_DRY_RUN -ne 'disabled' -or $env:RENOVATE_REPOSITORIES -ne 'unapproved/client' -or $env:RENOVATE_AUTODISCOVER -ne 'true') {throw 'Parent environment was not restored'}
    Must-Fail { & $runner -Repositories shmindmaster/gitpin -RenovateCommand $stub } 'allowlisted'
    Must-Fail { & $runner -Repositories shmindmaster/portfolio-records -RenovateCommand $stub } 'allowlisted'
    Must-Fail { & $runner -Repositories shmindmaster/mahumtech -RenovateCommand (Join-Path $fixtureRoot 'missing.cmd') } 'missing'
    $env:RENOVATE_TOKEN=''
    Must-Fail { & $runner -Repositories shmindmaster/mahumtech -RenovateCommand $stub } 'RENOVATE_TOKEN'
    $env:RENOVATE_TOKEN='synthetic-fixture-token'
    '$global:LASTEXITCODE = 17' | Set-Content -LiteralPath $stub
    Must-Fail { & $runner -Repositories shmindmaster/mahumtech -RenovateCommand $stub } 'exit 17'
    if ($env:RENOVATE_DRY_RUN -ne 'disabled') {throw 'Failure did not restore parent environment'}
    Write-Output 'PASS: forced scope/dry-run, no positional overrides, parent restoration, Dependabot/private exclusions, missing tool/token, and failed child'
} finally {
    foreach($key in $old.Keys) {[Environment]::SetEnvironmentVariable($key,$old[$key],'Process')}
    $resolved=[IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {throw 'Fixture cleanup path escaped temp root'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
