#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys AgentHub's reviewed C:\wt worktree controls to the local agent fleet.

.DESCRIPTION
    Deploys the repository-owned helper to the AgentHub user runtime, verifies
    Codex's user-managed root, installs Claude Code's documented WorktreeCreate
    hook, disables Gemini CLI's incompatible repository-local worktree feature,
    and sets AGENTHUB_WORKTREE_ROOT for future processes.

    Hosts without a documented custom-root control consume the generated global
    policy and invoke the deployed helper manually. This script does not invent
    host settings or modify Qoder's undocumented worktree hook surface.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$RegistryRoot = 'C:\Repos\shmindmaster\agenthub',
    [string]$UserProfile = [Environment]::GetFolderPath('UserProfile'),
    [string]$LocalAppData = [Environment]::GetFolderPath('LocalApplicationData'),
    [string]$RoamingAppData = [Environment]::GetFolderPath('ApplicationData'),
    [ValidateSet('Process', 'User')]
    [string]$EnvironmentScope = 'User'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Read-AgentHubJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowMissing
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) { return [pscustomobject]@{} }
        throw "Required JSON file is missing: $Path"
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Invalid JSON in '$Path': $($_.Exception.Message)"
    }
}

function Get-AgentHubJsonText {
    param([Parameter(Mandatory)]$Value)
    return (($Value | ConvertTo-Json -Depth 100) + "`n")
}

function Set-AgentHubProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function ConvertTo-AgentHubNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path.Replace('/', '\')).TrimEnd('\')
}

function Test-AgentHubTextEqual {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    return [string]::Equals(
        (Get-Content -LiteralPath $Path -Raw -Encoding UTF8),
        $Expected,
        [System.StringComparison]::Ordinal
    )
}

function Set-AgentHubTomlSectionValues {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Values
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($Text -split '\r?\n')) { $lines.Add([string]$line) }
    while ($lines.Count -gt 0 -and [string]::IsNullOrEmpty($lines[$lines.Count - 1])) {
        $lines.RemoveAt($lines.Count - 1)
    }

    $headerPattern = '^\s*\[' + [regex]::Escape($Section) + '\]\s*(?:#.*)?$'
    $headerIndexes = @(
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match $headerPattern) { $index }
        }
    )
    if ($headerIndexes.Count -gt 1) {
        throw "TOML section [$Section] appears more than once."
    }
    if ($headerIndexes.Count -eq 0) {
        if ($lines.Count -gt 0) { $lines.Add('') }
        $lines.Add("[$Section]")
        $sectionStart = $lines.Count - 1
    } else {
        $sectionStart = $headerIndexes[0]
    }

    foreach ($entry in $Values.GetEnumerator()) {
        $sectionEnd = $lines.Count
        for ($index = $sectionStart + 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^\s*\[[^\]]+\]\s*(?:#.*)?$') {
                $sectionEnd = $index
                break
            }
        }
        $keyPattern = '^\s*' + [regex]::Escape([string]$entry.Key) + '\s*='
        $keyIndexes = @(
            for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
                if ($lines[$index] -match $keyPattern) { $index }
            }
        )
        if ($keyIndexes.Count -gt 1) {
            throw "TOML key '$($entry.Key)' appears more than once in [$Section]."
        }
        $desiredLine = '{0} = {1}' -f $entry.Key, $entry.Value
        if ($keyIndexes.Count -eq 1) {
            $lines[$keyIndexes[0]] = $desiredLine
        } else {
            $lines.Insert($sectionEnd, $desiredLine)
        }
    }
    return (($lines -join "`n") + "`n")
}

function Set-AgentHubYamlRootScalar {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($Text -split '\r?\n')) { $lines.Add([string]$line) }
    while ($lines.Count -gt 0 -and [string]::IsNullOrEmpty($lines[$lines.Count - 1])) {
        $lines.RemoveAt($lines.Count - 1)
    }
    $keyPattern = '^' + [regex]::Escape($Key) + '\s*:'
    $indexes = @(
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match $keyPattern) { $index }
        }
    )
    if ($indexes.Count -gt 1) {
        throw "YAML root key '$Key' appears more than once."
    }
    $desiredLine = '{0}: {1}' -f $Key, $Value
    if ($indexes.Count -eq 1) {
        $lines[$indexes[0]] = $desiredLine
    } else {
        if ($lines.Count -gt 0) { $lines.Add('') }
        $lines.Add($desiredLine)
    }
    return (($lines -join "`n") + "`n")
}

$registryPath = Join-Path $RegistryRoot 'registry\worktree-roots.json'
$helperSource = Join-Path $RegistryRoot 'scripts\New-AgentHubWorktree.ps1'
$roots = Read-AgentHubJson -Path $registryPath
if ([string]$roots.canonicalRoot -ne 'C:/wt') {
    throw "The canonical worktree root must be C:/wt in '$registryPath'."
}
if ([string]$roots.environmentContract.name -ne 'AGENTHUB_WORKTREE_ROOT' -or
    [string]$roots.environmentContract.expectedValue -ne 'C:/wt') {
    throw "The environment contract in '$registryPath' is not the reviewed C:/wt contract."
}
if (-not (Test-Path -LiteralPath $helperSource -PathType Leaf)) {
    throw "Worktree helper source is missing: $helperSource"
}
if (-not (Test-Path -LiteralPath 'C:\wt' -PathType Container)) {
    throw 'The approved worktree root C:\wt does not exist.'
}

$runtimeRoot = Join-Path $LocalAppData 'AgentHub'
$runtimeHelper = Join-Path $runtimeRoot 'bin\New-AgentHubWorktree.ps1'
$claudeSettingsPath = Join-Path $UserProfile '.claude\settings.json'
$geminiSettingsPath = Join-Path $UserProfile '.gemini\settings.json'
$copilotSettingsPath = Join-Path $UserProfile '.copilot\settings.json'
$grokConfigPath = Join-Path $UserProfile '.grok\config.toml'
$hermesConfigPath = Join-Path $LocalAppData 'hermes\config.yaml'
$codexConfigPath = Join-Path $UserProfile '.codex\config.toml'
$warpTabConfigPath = Join-Path $RoamingAppData 'warp\Warp\data\tab_configs\agenthub_worktree.toml'

# Preflight every owned surface before making any change.
if (-not (Test-Path -LiteralPath $codexConfigPath -PathType Leaf)) {
    throw "Codex configuration is missing: $codexConfigPath"
}
$codexText = Get-Content -LiteralPath $codexConfigPath -Raw -Encoding UTF8
$codexRootMatch = [regex]::Match(
    $codexText,
    '(?m)^\s*git-worktree-root\s*=\s*(?<quote>[''"])(?<root>.*?)\k<quote>\s*(?:#.*)?$'
)
if (-not $codexRootMatch.Success) {
    throw "Codex git-worktree-root is missing from '$codexConfigPath'."
}
$codexRoot = ConvertTo-AgentHubNormalizedPath -Path $codexRootMatch.Groups['root'].Value
if ($codexRoot -ne 'C:\wt') {
    throw "Codex git-worktree-root must remain C:\wt; found '$codexRoot'."
}

$helperCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runtimeHelper
$claude = Read-AgentHubJson -Path $claudeSettingsPath -AllowMissing
if ($claude.PSObject.Properties['disableAllHooks'] -and [bool]$claude.disableAllHooks) {
    throw "Claude hooks are globally disabled in '$claudeSettingsPath'; WorktreeCreate cannot be enforced."
}
if (-not $claude.PSObject.Properties['hooks'] -or $null -eq $claude.hooks) {
    Set-AgentHubProperty -Object $claude -Name 'hooks' -Value ([pscustomobject]@{})
}
$existingWorktreeGroups = @(
    if ($claude.hooks.PSObject.Properties['WorktreeCreate']) {
        @($claude.hooks.WorktreeCreate)
    }
)
if ($existingWorktreeGroups.Count -gt 0) {
    $existingHandlers = @(
        if ($existingWorktreeGroups.Count -eq 1 -and
            $existingWorktreeGroups[0].PSObject.Properties['hooks']) {
            @($existingWorktreeGroups[0].hooks)
        }
    )
    $isManagedHook = $existingWorktreeGroups.Count -eq 1 -and
        $existingHandlers.Count -eq 1 -and
        [string]$existingHandlers[0].type -eq 'command' -and
        [string]$existingHandlers[0].command -eq $helperCommand
    if (-not $isManagedHook) {
        throw "Claude WorktreeCreate is already owned by another hook in '$claudeSettingsPath'."
    }
} else {
    Set-AgentHubProperty -Object $claude.hooks -Name 'WorktreeCreate' -Value @(
        [pscustomobject]@{
            hooks = @(
                [pscustomobject]@{
                    type = 'command'
                    command = $helperCommand
                }
            )
        }
    )
}
$desiredClaudeText = Get-AgentHubJsonText -Value $claude

$gemini = Read-AgentHubJson -Path $geminiSettingsPath -AllowMissing
if (-not $gemini.PSObject.Properties['experimental'] -or $null -eq $gemini.experimental) {
    Set-AgentHubProperty -Object $gemini -Name 'experimental' -Value ([pscustomobject]@{})
}
Set-AgentHubProperty -Object $gemini.experimental -Name 'worktrees' -Value $false
$desiredGeminiText = Get-AgentHubJsonText -Value $gemini

$copilot = Read-AgentHubJson -Path $copilotSettingsPath -AllowMissing
Set-AgentHubProperty -Object $copilot -Name 'experimental' -Value $false
$desiredCopilotText = Get-AgentHubJsonText -Value $copilot

$grokText = if (Test-Path -LiteralPath $grokConfigPath -PathType Leaf) {
    Get-Content -LiteralPath $grokConfigPath -Raw -Encoding UTF8
} else {
    ''
}
$desiredGrokText = Set-AgentHubTomlSectionValues `
    -Text $grokText `
    -Section 'hints' `
    -Values ([ordered]@{
        new_session_worktree_mode = '"never"'
        fork_worktree_mode = '"never"'
    })

$hermesText = if (Test-Path -LiteralPath $hermesConfigPath -PathType Leaf) {
    Get-Content -LiteralPath $hermesConfigPath -Raw -Encoding UTF8
} else {
    ''
}
$desiredHermesText = Set-AgentHubYamlRootScalar `
    -Text $hermesText `
    -Key 'worktree' `
    -Value 'false'

$desiredWarpText = @"
# agenthub:managed
name = "AgentHub C wt worktree"
title = "{{task}}"

[[panes]]
id = "agent"
type = "agent"
shell = "pwsh"
directory = "{{repository_path}}"
commands = ['& { `$agentHubPath = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$runtimeHelper" -Cwd "{{repository_path}}" -Name "{{task}}"; Set-Location -LiteralPath `$agentHubPath }']
is_focused = true

[params.repository_path]
type = "repo"
description = "Source repository or existing linked worktree"

[params.task]
type = "text"
description = "Lowercase AgentHub task slug"
"@.Replace("`r`n", "`n").TrimEnd() + "`n"
if (Test-Path -LiteralPath $warpTabConfigPath -PathType Leaf) {
    $existingWarpText = Get-Content -LiteralPath $warpTabConfigPath -Raw -Encoding UTF8
    if ($existingWarpText -notmatch 'agenthub:managed') {
        throw "Warp Tab Config is already user-owned and cannot be replaced: $warpTabConfigPath"
    }
}

$helperBytes = [System.IO.File]::ReadAllBytes($helperSource)
$helperInSync = (Test-Path -LiteralPath $runtimeHelper -PathType Leaf) -and
    ((Get-FileHash -LiteralPath $runtimeHelper -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $helperSource -Algorithm SHA256).Hash)
$claudeInSync = Test-AgentHubTextEqual -Path $claudeSettingsPath -Expected $desiredClaudeText
$geminiInSync = Test-AgentHubTextEqual -Path $geminiSettingsPath -Expected $desiredGeminiText
$copilotInSync = Test-AgentHubTextEqual -Path $copilotSettingsPath -Expected $desiredCopilotText
$grokInSync = Test-AgentHubTextEqual -Path $grokConfigPath -Expected $desiredGrokText
$hermesInSync = Test-AgentHubTextEqual -Path $hermesConfigPath -Expected $desiredHermesText
$warpInSync = Test-AgentHubTextEqual -Path $warpTabConfigPath -Expected $desiredWarpText
$environmentTarget = [System.EnvironmentVariableTarget]::$EnvironmentScope
$environmentInSync = [Environment]::GetEnvironmentVariable(
    'AGENTHUB_WORKTREE_ROOT',
    $environmentTarget
) -eq 'C:\wt'

$result = [pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    mode = if ($Apply) { 'apply' } else { 'audit' }
    canonicalRoot = 'C:\wt'
    helper = [pscustomobject]@{
        source = $helperSource
        destination = $runtimeHelper
        inSyncBefore = $helperInSync
        state = if ($helperInSync) { 'unchanged' } elseif ($Apply) { 'deployed' } else { 'drift' }
    }
    codex = [pscustomobject]@{
        path = $codexConfigPath
        state = 'verified-user-managed'
    }
    claude = [pscustomobject]@{
        path = $claudeSettingsPath
        state = if ($claudeInSync) { 'unchanged' } elseif ($Apply) { 'hook-installed' } else { 'drift' }
    }
    gemini = [pscustomobject]@{
        path = $geminiSettingsPath
        state = if ($geminiInSync) { 'unchanged' } elseif ($Apply) { 'native-worktrees-disabled' } else { 'drift' }
    }
    copilot = [pscustomobject]@{
        path = $copilotSettingsPath
        state = if ($copilotInSync) { 'unchanged' } elseif ($Apply) { 'experimental-worktrees-disabled' } else { 'drift' }
    }
    grok = [pscustomobject]@{
        path = $grokConfigPath
        state = if ($grokInSync) { 'unchanged' } elseif ($Apply) { 'native-worktree-prompts-disabled' } else { 'drift' }
    }
    hermes = [pscustomobject]@{
        path = $hermesConfigPath
        state = if ($hermesInSync) { 'unchanged' } elseif ($Apply) { 'native-worktrees-disabled' } else { 'drift' }
    }
    warp = [pscustomobject]@{
        path = $warpTabConfigPath
        state = if ($warpInSync) { 'unchanged' } elseif ($Apply) { 'tab-config-installed' } else { 'drift' }
    }
    environment = [pscustomobject]@{
        name = 'AGENTHUB_WORKTREE_ROOT'
        scope = $EnvironmentScope
        state = if ($environmentInSync) { 'unchanged' } elseif ($Apply) { 'set' } else { 'drift' }
    }
    fallback = [pscustomobject]@{
        state = 'generated-policy-and-manual-helper'
        qoderHook = 'not-installed-undocumented'
    }
}

if ($Apply) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupRoot = Join-Path $runtimeRoot "reports\backups\worktree-policy-$timestamp"
    $changeSet = @(
        [pscustomobject]@{
            path = $runtimeHelper
            changed = -not $helperInSync
            backupName = 'New-AgentHubWorktree.runtime.ps1'
        },
        [pscustomobject]@{
            path = $claudeSettingsPath
            changed = -not $claudeInSync
            backupName = 'settings.claude.json'
        },
        [pscustomobject]@{
            path = $geminiSettingsPath
            changed = -not $geminiInSync
            backupName = 'settings.gemini.json'
        },
        [pscustomobject]@{
            path = $copilotSettingsPath
            changed = -not $copilotInSync
            backupName = 'settings.copilot.json'
        },
        [pscustomobject]@{
            path = $grokConfigPath
            changed = -not $grokInSync
            backupName = 'config.grok.toml'
        },
        [pscustomobject]@{
            path = $hermesConfigPath
            changed = -not $hermesInSync
            backupName = 'config.hermes.yaml'
        },
        [pscustomobject]@{
            path = $warpTabConfigPath
            changed = -not $warpInSync
            backupName = 'agenthub_worktree.warp.toml'
        }
    )
    $backupCandidates = @($changeSet | Where-Object {
        $_.changed -and (Test-Path -LiteralPath $_.path -PathType Leaf)
    })
    if ($backupCandidates.Count -gt 0) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        foreach ($candidate in $backupCandidates) {
            Copy-Item -LiteralPath $candidate.path -Destination (Join-Path $backupRoot $candidate.backupName)
        }
    }

    if (-not $helperInSync) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $runtimeHelper) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($runtimeHelper, $helperBytes)
    }
    if (-not $claudeInSync) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $claudeSettingsPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($claudeSettingsPath, $desiredClaudeText, $utf8NoBom)
    }
    if (-not $geminiInSync) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $geminiSettingsPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($geminiSettingsPath, $desiredGeminiText, $utf8NoBom)
    }
    if (-not $copilotInSync) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $copilotSettingsPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($copilotSettingsPath, $desiredCopilotText, $utf8NoBom)
    }
    if (-not $grokInSync) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $grokConfigPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($grokConfigPath, $desiredGrokText, $utf8NoBom)
    }
    if (-not $hermesInSync) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $hermesConfigPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($hermesConfigPath, $desiredHermesText, $utf8NoBom)
    }
    if (-not $warpInSync) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $warpTabConfigPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($warpTabConfigPath, $desiredWarpText, $utf8NoBom)
    }
    if (-not $environmentInSync) {
        [Environment]::SetEnvironmentVariable(
            'AGENTHUB_WORKTREE_ROOT',
            'C:\wt',
            $environmentTarget
        )
    }

    # Post-apply verification is fail-closed.
    if ((Get-FileHash -LiteralPath $runtimeHelper -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $helperSource -Algorithm SHA256).Hash) {
        throw "Deployed helper hash mismatch: $runtimeHelper"
    }
    if (-not (Test-AgentHubTextEqual -Path $claudeSettingsPath -Expected $desiredClaudeText)) {
        throw "Claude settings did not converge: $claudeSettingsPath"
    }
    if (-not (Test-AgentHubTextEqual -Path $geminiSettingsPath -Expected $desiredGeminiText)) {
        throw "Gemini settings did not converge: $geminiSettingsPath"
    }
    if (-not (Test-AgentHubTextEqual -Path $copilotSettingsPath -Expected $desiredCopilotText)) {
        throw "Copilot settings did not converge: $copilotSettingsPath"
    }
    if (-not (Test-AgentHubTextEqual -Path $grokConfigPath -Expected $desiredGrokText)) {
        throw "Grok settings did not converge: $grokConfigPath"
    }
    if (-not (Test-AgentHubTextEqual -Path $hermesConfigPath -Expected $desiredHermesText)) {
        throw "Hermes settings did not converge: $hermesConfigPath"
    }
    if (-not (Test-AgentHubTextEqual -Path $warpTabConfigPath -Expected $desiredWarpText)) {
        throw "Warp Tab Config did not converge: $warpTabConfigPath"
    }
    if ([Environment]::GetEnvironmentVariable(
        'AGENTHUB_WORKTREE_ROOT',
        $environmentTarget
    ) -ne 'C:\wt') {
        throw "AGENTHUB_WORKTREE_ROOT did not converge at $EnvironmentScope scope."
    }

    $reportRoot = Join-Path $runtimeRoot 'reports\worktree-policy'
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    $reportPath = Join-Path $reportRoot "deployment-$timestamp.json"
    [System.IO.File]::WriteAllText(
        $reportPath,
        (($result | ConvertTo-Json -Depth 20) + "`n"),
        $utf8NoBom
    )
}

Write-Output $result
