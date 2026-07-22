#Requires -Version 5.1

Describe 'agentctl read-only commands' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:agentctl = Join-Path $script:repoRoot 'scripts\agentctl.ps1'
    $script:scriptText = Get-Content -LiteralPath $script:agentctl -Raw
  }

  It 'requires an explicit switch before persisting reports' {
    ($script:scriptText -match '\[switch\]\$WriteReport') | Should Be $true
    ($script:scriptText -match 'if \(\$WriteReport\)') | Should Be $true
  }

  It 'does not regenerate instructions from validation or drift' {
    $validateBody = [regex]::Match($script:scriptText, 'function Invoke-Validation \{(?<body>[\s\S]*?)\r?\n\}', 'Singleline').Groups['body'].Value
    $driftBody = [regex]::Match($script:scriptText, 'function Save-DriftReport \{(?<body>[\s\S]*?)\r?\n\}', 'Singleline').Groups['body'].Value
    ($validateBody -match 'New-GeneratedInstructions') | Should Be $false
    ($driftBody -match 'New-GeneratedInstructions') | Should Be $false
  }

  It 'keeps cleanup report-only even when Apply is supplied' {
    ($script:scriptText -match 'cleanup remains report-only even with -Apply') | Should Be $true
  }

  It 'does not infer Cursor billing headroom from undocumented numeric payload fields' {
    ($script:scriptText -match 'Get-CursorSpendCandidates') | Should Be $false
    ($script:scriptText -match 'does not expose documented spend headroom') | Should Be $true
    ($script:scriptText -match "Add-Check 'WARN' 'cursor-background-launch'") | Should Be $true
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
    ($first -join '|') | Should Be ($second -join '|')

    & $script:agentctl drift -RegistryRoot $fixtureRoot | Out-Null
    $afterDrift = @(Get-ChildItem (Join-Path $fixtureRoot 'generated') -File -Recurse | Sort-Object FullName | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash })
    ($second -join '|') | Should Be ($afterDrift -join '|')
    (Test-Path (Join-Path $fixtureRoot 'reports')) | Should Be $false
  }
}
