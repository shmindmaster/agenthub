function Get-RegisteredSharedSkillPaths {
    param(
        [Parameter(Mandatory)][string]$UserProfile,
        [AllowNull()][object]$NativeConnectors
    )

    $agentDirectory = Join-Path $UserProfile '.agents'
    $skillsDirectory = Join-Path $agentDirectory 'skills'
    $lockPath = Join-Path $agentDirectory '.skill-lock.json'
    $lock = $null
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        try { $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Verbose "Cannot read the shared skill installer receipt: $_" }
    }

    if (-not $lock.skills) { return }
    foreach ($extension in $NativeConnectors.thirdPartyExtensions.extensions) {
        $source = [string]$extension.upstream -replace '^https://github\.com/', ''
        foreach ($name in $extension.sharedSkillNames) {
            $entry = $lock.skills.PSObject.Properties[$name].Value
            if ($entry.source -eq $source -and $entry.sourceType -eq 'github' -and
                $entry.skillPath -ceq "skills/$name/SKILL.md") {
                $skillPath = Join-Path $skillsDirectory $name
                if (Test-Path -LiteralPath (Join-Path $skillPath 'SKILL.md') -PathType Leaf) {
                    [IO.Path]::GetFullPath($skillPath)
                }
            }
        }
    }
}

function Get-UnmanagedSharedSkills {
    param(
        [Parameter(Mandatory)][string]$UserProfile,
        [AllowNull()][object]$NativeConnectors
    )

    $registeredPaths = @(Get-RegisteredSharedSkillPaths -UserProfile $UserProfile -NativeConnectors $NativeConnectors)
    Get-ChildItem -LiteralPath (Join-Path $UserProfile '.agents/skills') -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'synced' -and $_.FullName -notin $registeredPaths }
}
