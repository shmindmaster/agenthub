function Get-UnmanagedSharedSkills {
    param(
        [Parameter(Mandatory)][string]$UserProfile,
        [AllowNull()][object]$NativeConnectors
    )

    $agentDirectory = Join-Path $UserProfile '.agents'
    $lockPath = Join-Path $agentDirectory '.skill-lock.json'
    $lock = $null
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        try { $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Verbose "Cannot read the shared skill installer receipt: $_" }
    }

    $managed = @{}
    foreach ($extension in $NativeConnectors.thirdPartyExtensions.extensions) {
        if (-not $lock.skills) { break }
        $source = [string]$extension.upstream -replace '^https://github\.com/', ''
        foreach ($name in $extension.sharedSkillNames) {
            $entry = $lock.skills.PSObject.Properties[$name].Value
            if ($entry.source -eq $source -and $entry.sourceType -eq 'github' -and
                $entry.skillPath -ceq "skills/$name/SKILL.md") {
                $managed[$name] = $true
            }
        }
    }

    Get-ChildItem -LiteralPath (Join-Path $agentDirectory 'skills') -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ne 'synced' -and
            (-not $managed.ContainsKey($_.Name) -or
                -not (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf))
        }
}
