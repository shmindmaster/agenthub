#Requires -Version 5.1
<#
Behavior tests for scripts/lib/PathBinding.ps1.

The four sync scripts used to rebase absolute destinations independently.
This file pins the one contract they now share: templates expand against
the target profile, recorded absolute prefixes rebase onto it, and an
unrebaseable absolute shape is refused before any write.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\lib\PathBinding.ps1')

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

function Test-TemplateExpandsToTarget {
    $context = New-AgentHubPathBindingContext -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared '{userProfile}\.claude\CLAUDE.md' -Context $context
    if ($bound -ne 'C:\synth\user\.claude\CLAUDE.md') {
        return @{ Passed = $false; Detail = "template expanded to '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-RecordedAbsoluteRebasesFromRegistryProfile {
    $context = New-AgentHubPathBindingContext -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared 'C:\real\user\.codex\config.toml' -Context $context
    if ($bound -ne 'C:\synth\user\.codex\config.toml') {
        return @{ Passed = $false; Detail = "absolute rebase produced '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-MissingRegistryProfileFallsBackToInvokingProfile {
    $context = New-AgentHubPathBindingContext -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared 'C:\real\user\.agents\skills' -Context $context
    if ($bound -ne 'C:\synth\user\.agents\skills') {
        return @{ Passed = $false; Detail = "invoking-profile fallback produced '$bound'. Sync-Capabilities fixtures omit registry userProfile and still must isolate." }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-UnrebasableShapeIsRefused {
    $context = New-AgentHubPathBindingContext -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    try {
        Resolve-AgentHubBoundPath -Declared '\\fileserver\agents\codex\config.toml' -Context $context | Out-Null
        return @{ Passed = $false; Detail = 'UNC path was accepted' }
    } catch {
        if ($_.Exception.Message -notmatch 'refuses') {
            return @{ Passed = $false; Detail = $_.Exception.Message }
        }
    }
    try {
        Resolve-AgentHubBoundPath -Declared 'C:/real/user/.codex/config.toml' -Context $context | Out-Null
        return @{ Passed = $false; Detail = 'forward-slash absolute path was accepted' }
    } catch {
        if ($_.Exception.Message -notmatch 'refuses') {
            return @{ Passed = $false; Detail = $_.Exception.Message }
        }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-GlobalPolicyTokenIsNotAPath {
    if (Test-AgentHubBindablePathValue '{{globalPolicy}}') {
        return @{ Passed = $false; Detail = '{{globalPolicy}} was classified as a bindable path' }
    }
    $context = New-AgentHubPathBindingContext -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user'
    $node = [pscustomobject]@{ instructionBodyTemplate = "# Hermes`n{{globalPolicy}}`n" }
    Convert-AgentHubBoundNode -Node $node -Context $context
    if ($node.instructionBodyTemplate -notmatch '\{\{globalPolicy\}\}') {
        return @{ Passed = $false; Detail = 'binding rewrote the Hermes policy token' }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-ForwardSlashHomeTemplateMatchesBackslashOnWindows {
    $context = New-AgentHubPathBindingContext -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared '{userHome}/.claude/CLAUDE.md' -Context $context
    if ($bound -ne 'C:\synth\user\.claude\CLAUDE.md') {
        return @{ Passed = $false; Detail = "portable template expanded to '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-OsConfigRootsExpandPerPlatform {
    $windows = New-AgentHubPathBindingContext -Platform windows -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -LocalAppData 'C:\real\user\AppData\Local' -RoamingConfig 'C:\real\user\AppData\Roaming'
    $cursorWin = Resolve-AgentHubBoundPath -Declared '{roamingConfig}/Cursor/User/settings.json' -Context $windows
    $runtimeWin = Resolve-AgentHubBoundPath -Declared '{localData}/AgentHub' -Context $windows
    if ($cursorWin -ne 'C:\synth\user\AppData\Roaming\Cursor\User\settings.json') {
        return @{ Passed = $false; Detail = "windows roaming expanded to '$cursorWin'" }
    }
    if ($runtimeWin -ne 'C:\synth\user\AppData\Local\AgentHub') {
        return @{ Passed = $false; Detail = "windows local data expanded to '$runtimeWin'" }
    }

    $darwin = New-AgentHubPathBindingContext -Platform darwin -TargetUserProfile '/Users/synth' -InvokingUserProfile '/Users/real'
    $cursorMac = Resolve-AgentHubBoundPath -Declared '{roamingConfig}/Cursor/User/settings.json' -Context $darwin
    $expectedMac = '/Users/synth/Library/Application Support/Cursor/User/settings.json'
    if ($cursorMac -ne $expectedMac) {
        return @{ Passed = $false; Detail = "darwin roaming expanded to '$cursorMac'" }
    }

    $linux = New-AgentHubPathBindingContext -Platform linux -TargetUserProfile '/home/synth' -InvokingUserProfile '/home/real'
    $cursorLinux = Resolve-AgentHubBoundPath -Declared '{roamingConfig}/Cursor/User/settings.json' -Context $linux
    $runtimeLinux = Resolve-AgentHubBoundPath -Declared '{localData}/AgentHub' -Context $linux
    if ($cursorLinux -ne '/home/synth/.config/Cursor/User/settings.json') {
        return @{ Passed = $false; Detail = "linux roaming expanded to '$cursorLinux'" }
    }
    if ($runtimeLinux -ne '/home/synth/.local/share/AgentHub') {
        return @{ Passed = $false; Detail = "linux local data expanded to '$runtimeLinux'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-PosixAbsoluteRebasesWithoutGetFullPath {
    $context = New-AgentHubPathBindingContext -Platform linux -TargetUserProfile '/home/synth' -InvokingUserProfile '/home/real' -RegistryUserProfile '/home/real'
    $bound = Resolve-AgentHubBoundPath -Declared '/home/real/.codex/config.toml' -Context $context
    if ($bound -ne '/home/synth/.codex/config.toml') {
        return @{ Passed = $false; Detail = "posix rebase produced '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-WindowsOnlyLayoutIsNotWrittenOnUnix {
    $context = New-AgentHubPathBindingContext -Platform darwin -TargetUserProfile '/Users/synth' -InvokingUserProfile '/Users/real'
    try {
        Resolve-AgentHubBoundPath -Declared '{userHome}/AppData/Local/Programs/cursor/cursor.cmd' -Context $context | Out-Null
        return @{ Passed = $false; Detail = 'windows-only AppData template was accepted on darwin' }
    } catch {
        if ($_.Exception.Message -notmatch 'windows-only layout') {
            return @{ Passed = $false; Detail = $_.Exception.Message }
        }
    }
    $catalog = [pscustomobject]@{
        activeAgents = @(
            [pscustomobject]@{
                id = 'cursor'
                executable = '{userHome}/AppData/Local/Programs/cursor/cursor.cmd'
                nativePaths = [pscustomobject]@{
                    settings = '{roamingConfig}/Cursor/User/settings.json'
                    vendorExecutable = '{userHome}/AppData/Local/Programs/cursor/cursor.cmd'
                }
            }
        )
    }
    . (Join-Path $repoRoot 'scripts\lib\HostCatalog.ps1')
    Import-AgentHubBoundHostCatalog -AgentsDocument $catalog -Context $context | Out-Null
    $agent = $catalog.activeAgents[0]
    if ($null -ne $agent.executable) {
        return @{ Passed = $false; Detail = "darwin catalog kept windows executable '$($agent.executable)'" }
    }
    if ($null -ne $agent.nativePaths.vendorExecutable) {
        return @{ Passed = $false; Detail = 'darwin catalog kept a windows-only vendor executable' }
    }
    $expected = '/Users/synth/Library/Application Support/Cursor/User/settings.json'
    if ($agent.nativePaths.settings -ne $expected) {
        return @{ Passed = $false; Detail = "darwin catalog settings became '$($agent.nativePaths.settings)'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-UnsupportedPlatformIsRefused {
    try {
        Get-AgentHubPlatformId -Platform ios | Out-Null
        return @{ Passed = $false; Detail = 'ios was accepted as a coding-agent platform' }
    } catch {
        if ($_.Exception.Message -notmatch 'windows, darwin, and linux') {
            return @{ Passed = $false; Detail = $_.Exception.Message }
        }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-AlreadyTargetPathIsNotNested {
    $context = New-AgentHubPathBindingContext -TargetUserProfile 'C:\real\user\AppData\Local\Temp\scratch' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared 'C:\real\user\AppData\Local\Temp\scratch\.claude\CLAUDE.md' -Context $context
    if ($bound -ne 'C:\real\user\AppData\Local\Temp\scratch\.claude\CLAUDE.md') {
        return @{ Passed = $false; Detail = "already-isolated path was nested: '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

$behaviors = @(
    @{ Name = 'template expands to the target profile'; Run = { Test-TemplateExpandsToTarget } }
    @{ Name = 'recorded absolute path rebases from the registry profile'; Run = { Test-RecordedAbsoluteRebasesFromRegistryProfile } }
    @{ Name = 'missing registry profile still rebases from the invoking profile'; Run = { Test-MissingRegistryProfileFallsBackToInvokingProfile } }
    @{ Name = 'UNC and forward-slash absolutes are refused'; Run = { Test-UnrebasableShapeIsRefused } }
    @{ Name = 'globalPolicy token is not treated as a path'; Run = { Test-GlobalPolicyTokenIsNotAPath } }
    @{ Name = 'a path already under the target profile is not nested'; Run = { Test-AlreadyTargetPathIsNotNested } }
    @{ Name = 'forward-slash home templates expand with the Windows separator'; Run = { Test-ForwardSlashHomeTemplateMatchesBackslashOnWindows } }
    @{ Name = 'OS config roots expand for windows, darwin, and linux'; Run = { Test-OsConfigRootsExpandPerPlatform } }
    @{ Name = 'a POSIX absolute path rebases onto the target home'; Run = { Test-PosixAbsoluteRebasesWithoutGetFullPath } }
    @{ Name = 'a Windows install pin is not written on darwin'; Run = { Test-WindowsOnlyLayoutIsNotWrittenOnUnix } }
    @{ Name = 'platforms other than windows, darwin, and linux are refused'; Run = { Test-UnsupportedPlatformIsRefused } }
)
foreach ($behavior in $behaviors) {
    $result = & $behavior.Run
    Report $behavior.Name ([bool]$result.Passed) ([string]$result.Detail)
}

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
