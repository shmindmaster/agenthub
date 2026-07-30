#Requires -Version 5.1

Describe 'agentctl read-only commands' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:agentctl = Join-Path $script:repoRoot 'scripts\agentctl.ps1'
    $script:scriptText = Get-Content -LiteralPath $script:agentctl -Raw
  }

  It 'requires an explicit switch before persisting reports' {
    ($script:scriptText -match '\[switch\]\$WriteReport') | Should -Be $true
    ($script:scriptText -match 'if \(\$WriteReport\)') | Should -Be $true
  }

  It 'does not regenerate instructions from validation or drift' {
    $validateBody = [regex]::Match($script:scriptText, 'function Invoke-Validation \{(?<body>[\s\S]*?)\r?\n\}', 'Singleline').Groups['body'].Value
    $driftBody = [regex]::Match($script:scriptText, 'function Save-DriftReport \{(?<body>[\s\S]*?)\r?\n\}', 'Singleline').Groups['body'].Value
    ($validateBody -match 'New-GeneratedInstructions') | Should -Be $false
    ($driftBody -match 'New-GeneratedInstructions') | Should -Be $false
  }

  It 'keeps cleanup report-only even when Apply is supplied' {
    ($script:scriptText -match 'cleanup remains report-only even with -Apply') | Should -Be $true
  }

  It 'does not infer Cursor billing headroom from undocumented numeric payload fields' {
    ($script:scriptText -match 'Get-CursorSpendCandidates') | Should -Be $false
    ($script:scriptText -match 'does not expose documented spend headroom') | Should -Be $true
    ($script:scriptText -match "Add-Check 'WARN' 'cursor-background-launch'") | Should -Be $true
  }

  It 'enables Cursor only through the compound owner-controlled dispatch gate' {
    $fleetProfile = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry\fleet-profile.json') -Raw | ConvertFrom-Json
    $fleetProfile.dispatchPolicy.cursor.enabled | Should -Be $true
    $fleetProfile.dispatchPolicy.'cursor-agent'.enabled | Should -Be $true
    $fleetProfile.providerHolds.cursor.active | Should -Be $false
    ($script:scriptText -match 'disabled by owner policy; no API request attempted') | Should -Be $true
    ($script:scriptText -match 'cursor-credential-residue') | Should -Be $true
    ($script:scriptText -match 'value was not read') | Should -Be $true
    ($script:scriptText -match 'cursor-hold-wrapper') | Should -Be $true
    ($script:scriptText -match 'launcher can bypass the owner hold') | Should -Be $true
    . (Join-Path $script:repoRoot 'scripts\AgentCtl.CursorReadiness.ps1')
    (Test-CursorDispatchEnabled $fleetProfile) | Should -Be $true
    (Get-CursorLauncherContent -FleetProfile $fleetProfile -Surface agent -Shell cmd) | Should -Match '--yolo'
    (Get-CursorLauncherContent -FleetProfile $fleetProfile -Surface agent -Shell cmd) | Should -Match '--approve-mcps'
    (Get-CursorLauncherContent -FleetProfile $fleetProfile -Surface ide -Shell posix) | Should -Match 'cursor\.cmd'
  }

  It 'generates deterministically and drift does not mutate synthetic output' {
    $fixtureRoot = Join-Path $TestDrive 'control-plane'
    foreach ($directory in @('registry', 'standards', 'templates')) {
      Copy-Item -LiteralPath (Join-Path $script:repoRoot $directory) -Destination (Join-Path $fixtureRoot $directory) -Recurse -Force
    }

    & $script:agentctl generate -RegistryRoot $fixtureRoot | Out-Null
    $first = @(Get-ChildItem (Join-Path $fixtureRoot 'generated') -File -Recurse | Sort-Object FullName | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash })
    & $script:agentctl generate -RegistryRoot $fixtureRoot | Out-Null
    $second = @(Get-ChildItem (Join-Path $fixtureRoot 'generated') -File -Recurse | Sort-Object FullName | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash })
    ($first -join '|') | Should -Be ($second -join '|')

    & $script:agentctl drift -RegistryRoot $fixtureRoot | Out-Null
    $afterDrift = @(Get-ChildItem (Join-Path $fixtureRoot 'generated') -File -Recurse | Sort-Object FullName | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash })
    ($second -join '|') | Should -Be ($afterDrift -join '|')
    (Test-Path (Join-Path $fixtureRoot 'reports')) | Should -Be $false
  }

  It 'refuses to overwrite unmanaged global instructions and accepts managed destinations' {
    $fixtureRoot = Join-Path $TestDrive 'instruction-sync'
    foreach ($directory in @('registry', 'standards', 'templates')) {
      Copy-Item -LiteralPath (Join-Path $script:repoRoot $directory) -Destination (Join-Path $fixtureRoot $directory) -Recurse -Force
    }
    $destination = Join-Path $fixtureRoot 'profile\AGENTS.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    'user-owned instructions' | Set-Content -LiteralPath $destination -Encoding UTF8

    $installationsPath = Join-Path $fixtureRoot 'registry\installations.json'
    $installations = Get-Content -LiteralPath $installationsPath -Raw | ConvertFrom-Json
    $installations.managedInstructionTargets = @(
      [pscustomobject]@{
        id = 'synthetic'
        title = 'Synthetic Global Instructions'
        generatedPath = 'generated/synthetic/AGENTS.md'
        destination = $destination
      }
    )
    $installations | ConvertTo-Json -Depth 40 |
      Set-Content -LiteralPath $installationsPath -Encoding UTF8

    {
      & $script:agentctl sync -Apply -RegistryRoot $fixtureRoot
    } | Should -Throw '*Refusing to overwrite unmanaged instruction file*'
    (Get-Content -LiteralPath $destination -Raw).Trim() | Should -Be 'user-owned instructions'

    "<!-- agenthub:managed -->`nold managed policy" |
      Set-Content -LiteralPath $destination -Encoding UTF8
    & $script:agentctl sync -Apply -RegistryRoot $fixtureRoot | Out-Null
    (Get-Content -LiteralPath $destination -Raw) | Should -Match 'agenthub:managed'
    (Get-Content -LiteralPath $destination -Raw) | Should -Match 'Global Coding-Agent Policy'
  }
}
