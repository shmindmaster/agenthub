#Requires -Version 5.1
# Synthetic active companion prevents a no-op implementation passing retirement.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\TestPlatform.ps1')
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
@{userProfile=$HOME; activeAgents=@($live,$retired); inactiveAgents=@()} |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$registry\agents.json"
@{capabilities=@(@{id='sample';owner='test';canonicalSource='packages/sample'
    hostMappings=@(@{hostId='fixture-active';deploymentStatus='managed'},@{hostId='hermes';deploymentStatus='managed'})})} |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$registry\capabilities.json"
[IO.File]::WriteAllText((Join-Path $skill "SKILL.md"), "---`nname: sample`ndescription: Synthetic`n---`nSynthetic.")
[IO.File]::WriteAllText((Join-Path $fixture "global-agent-policy.md"), "# Synthetic policy`n")
$previous = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = (Get-TestProfileLocalData $profile)
    & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Capabilities.ps1" `
        -Apply -IncludeInactiveAgents -RepositoryRoot $fixture -UserProfile $profile *> $null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "$profile\active\skills\sample\SKILL.md") -or
        (Test-Path -LiteralPath "$profile\retired")) { throw 'Retired capability deployment guard failed.' }
    & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Instructions.ps1" `
        -Apply -RepositoryRoot $fixture -UserProfile $profile *> $null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "$profile\active\AGENTS.md") -or
        (Test-Path -LiteralPath "$profile\retired")) { throw 'Retired instruction deployment guard failed.' }
    foreach ($schema in @(2,1)) {
        $retired.status = 'active'
        @{userProfile=$HOME; activeAgents=@($live,$retired); inactiveAgents=@()} |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$registry\agents.json"
        [IO.File]::WriteAllText((Join-Path $skill "SKILL.md"), "---`r`nname: sample`r`ndescription: Synthetic`r`n---`r`nSynthetic.")
        & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Capabilities.ps1" `
            -Apply -RepositoryRoot $fixture -UserProfile $profile *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Active retirement fixture setup failed.' }
        $destination = Join-Path $profile 'retired\skills\sample'
        $statePath = Join-Path $env:LOCALAPPDATA 'AgentHub\sync\managed-skills.json'
        $state = Get-Content -LiteralPath $statePath -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($schema -eq 1) {
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                foreach ($entry in $state.managed.PSObject.Properties) {
                    $inventory = 'SKILL.md:' + (Get-FileHash -LiteralPath "$($entry.Name)\SKILL.md").Hash
                    $entry.Value.hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($inventory)))).Replace('-','')
                }
            } finally { $sha.Dispose() }
            $state.schemaVersion = 1
            $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath
        }
        $originalHash = $state.managed.PSObject.Properties[$destination].Value.hash
        $retired.status = 'retired'
        @{userProfile=$HOME; activeAgents=@($live,$retired); inactiveAgents=@()} |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$registry\agents.json"
        & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Capabilities.ps1" `
            -Apply -RepositoryRoot $fixture -UserProfile $profile *> $null
        $state = Get-Content -LiteralPath $statePath -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destination) -or
            $state.managed.PSObject.Properties[$destination].Value.hash -ne $originalHash) {
            throw "Retired ownership lost before prune (schema $schema)."
        }
        $original = [IO.File]::ReadAllText((Join-Path $destination "SKILL.md"))
        Add-Content -LiteralPath "$destination\SKILL.md" -Value 'owner edit'
        & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Capabilities.ps1" `
            -Apply -Prune -RepositoryRoot $fixture -UserProfile $profile *> $null
        $state = Get-Content -LiteralPath $statePath -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($LASTEXITCODE -eq 0 -or -not (Test-Path -LiteralPath $destination) -or
            $state.managed.PSObject.Properties[$destination].Value.hash -ne $originalHash) {
            throw "Modified retired copy lost protection (schema $schema)."
        }
        [IO.File]::WriteAllText((Join-Path $destination "SKILL.md"), $original)
        & (Get-Process -Id $PID).Path -NoProfile -File "$root\scripts\Sync-Capabilities.ps1" `
            -Apply -Prune -RepositoryRoot $fixture -UserProfile $profile *> $null
        $state = Get-Content -LiteralPath $statePath -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $destination) -or
            $state.managed.PSObject.Properties[$destination]) {
            throw "Deferred retirement prune failed (schema $schema)."
        }
    }
    Write-Host 'RESULT: 8 passed, 0 failed'
} finally {
    $env:LOCALAPPDATA = $previous
    [IO.Directory]::Delete($scratch, $true)
}
