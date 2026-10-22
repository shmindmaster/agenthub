#Requires -Version 5.1
# Synthetic active companion prevents a no-op implementation passing retirement.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('retired-sync-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $scratch 'source'
$profile = Join-Path $scratch 'profile'
$registry = Join-Path $fixture 'registry'
$skill = Join-Path $fixture 'packages\sample\skills\sample'
$null = New-Item -ItemType Directory -Path $registry, $skill -Force
$live = @{ id='fixture-active'; status='active'; name='Synthetic Active'
    nativePaths=@{ instructions="$profile\active\AGENTS.md"; skillsDir="$profile\active\skills" } }
$retired = @{ id='hermes'; status='retired'; name='Synthetic Retired'
    nativePaths=@{ instructions="$profile\retired\SOUL.md"; skillsDir="$profile\retired\skills" } }
@{userProfile=$env:USERPROFILE; activeAgents=@($live,$retired); inactiveAgents=@()} |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$registry\agents.json"
@{capabilities=@(@{id='sample';owner='test';canonicalSource='packages/sample'
    hostMappings=@(@{hostId='fixture-active';deploymentStatus='managed'},@{hostId='hermes';deploymentStatus='managed'})})} |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$registry\capabilities.json"
[IO.File]::WriteAllText("$skill\SKILL.md", "---`nname: sample`ndescription: Synthetic`n---`nSynthetic.")
[IO.File]::WriteAllText("$fixture\global-agent-policy.md", "# Synthetic policy`n")
$previous = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $profile 'AppData\Local'
    & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Capabilities.ps1" `
        -Apply -IncludeInactiveAgents -RepositoryRoot $fixture -UserProfile $profile *> $null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "$profile\active\skills\sample\SKILL.md") -or
        (Test-Path -LiteralPath "$profile\retired")) { throw 'Retired capability deployment guard failed.' }
    & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Instructions.ps1" `
        -Apply -RepositoryRoot $fixture -UserProfile $profile *> $null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "$profile\active\AGENTS.md") -or
        (Test-Path -LiteralPath "$profile\retired")) { throw 'Retired instruction deployment guard failed.' }
    Write-Host 'RESULT: 2 passed, 0 failed'
} finally {
    $env:LOCALAPPDATA = $previous
    [IO.Directory]::Delete($scratch, $true)
}
