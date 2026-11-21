# Shared by deployment, pruning and the live policy test.
. (Join-Path $PSScriptRoot 'PathBinding.ps1')

function Test-AutoClawBrowserSkillMirror {
    param([string]$Source, [string]$Shared)

    $files = @('SKILL.md', 'dist/autoglm-browser-service.exe')
    foreach ($relativePath in $files) {
        $sourceFile = Join-Path $Source $relativePath
        $sharedFile = Join-Path $Shared $relativePath
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf) -or
            -not (Test-Path -LiteralPath $sharedFile -PathType Leaf) -or
            (Get-FileHash -LiteralPath $sourceFile).Hash -ne (Get-FileHash -LiteralPath $sharedFile).Hash) {
            return $false
        }
    }
    # The exported skill contains the document and executable. Additional files
    # can change what another host discovers, so flag the directory in that case.
    $sharedFiles = @(Get-ChildItem -LiteralPath $Shared -Recurse -File -Force)
    if ($sharedFiles.Count -ne $files.Count) { return $false }
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Shared $files[1])
    return ($signature.Status -eq 'Valid' -and
        $signature.SignerCertificate.Subject -match '(?:^|, )O=JINGSHENG HENGXING TECHNOLOGY PTE\. LTD\.(?:,|$)')
}

function Get-RegisteredSharedSkillPaths {
    param(
        [Parameter(Mandatory)][string]$UserProfile,
        [AllowNull()][object]$NativeConnectors
    )

    $agentDirectory = Join-Path $UserProfile '.agents'
    $skillsDirectory = Join-Path $agentDirectory 'skills'
    # AutoClaw deploys this mirror from its account-native skill store. Unlike
    # shared installs from GitHub, it does not produce a skills CLI receipt.
    if ((Get-AgentHubHostPlatformId) -eq 'windows') {
        $shared = Join-Path $skillsDirectory 'autoglm-browser-agent'
        if (Test-Path -LiteralPath $shared -PathType Container) {
            $context = New-AgentHubPathBindingContext -TargetUserProfile $UserProfile
            $accounts = Join-Path $context.EffectiveRoamingConfig 'AutoClaw-oversea-official/accounts'
            foreach ($account in @(Get-ChildItem -LiteralPath $accounts -Directory -ErrorAction SilentlyContinue)) {
                $source = Join-Path $account.FullName 'runtime/zwork-agent/skills/autoglm-browser-agent'
                try {
                    if (Test-AutoClawBrowserSkillMirror -Source $source -Shared $shared) {
                        [IO.Path]::GetFullPath($shared)
                        break
                    }
                } catch {
                    Write-Verbose 'Could not verify the AutoClaw browser skill mirror.'
                }
            }
        }
    }
    $lockPath = Join-Path $agentDirectory '.skill-lock.json'
    # The installer uses XDG state for the invoking account only. A profile
    # override must not use that account's receipt to authorize another tree.
    $invokingProfile = Get-AgentHubDefaultHome
    $pathComparison = if ((Get-AgentHubHostPlatformId) -eq 'windows') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($env:XDG_STATE_HOME -and $invokingProfile -and
        [string]::Equals([IO.Path]::GetFullPath($UserProfile).TrimEnd('\', '/'),
            [IO.Path]::GetFullPath($invokingProfile).TrimEnd('\', '/'), $pathComparison)) {
        $lockPath = Join-Path $env:XDG_STATE_HOME 'skills/.skill-lock.json'
    }
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
