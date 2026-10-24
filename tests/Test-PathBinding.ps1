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
    $context = New-AgentHubPathBindingContext -Platform windows -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared '{userProfile}\.claude\CLAUDE.md' -Context $context
    if ($bound -ne 'C:\synth\user\.claude\CLAUDE.md') {
        return @{ Passed = $false; Detail = "template expanded to '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-RecordedAbsoluteRebasesFromRegistryProfile {
    $context = New-AgentHubPathBindingContext -Platform windows -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared 'C:\real\user\.codex\config.toml' -Context $context
    if ($bound -ne 'C:\synth\user\.codex\config.toml') {
        return @{ Passed = $false; Detail = "absolute rebase produced '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-MissingRegistryProfileFallsBackToInvokingProfile {
    $context = New-AgentHubPathBindingContext -Platform windows -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared 'C:\real\user\.agents\skills' -Context $context
    if ($bound -ne 'C:\synth\user\.agents\skills') {
        return @{ Passed = $false; Detail = "invoking-profile fallback produced '$bound'. Sync-Capabilities fixtures omit registry userProfile and still must isolate." }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-UnrebasableShapeIsRefused {
    $context = New-AgentHubPathBindingContext -Platform windows -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
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

function Test-ForwardSlashHomeTemplateMatchesBackslashOnWindows {
    $context = New-AgentHubPathBindingContext -Platform windows -TargetUserProfile 'C:\synth\user' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
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
    # The Windows launcher path is meaningless on macOS, but its command name
    # is what the same CLI installs onto PATH there.
    if ($agent.executable -ne 'cursor') {
        return @{ Passed = $false; Detail = "darwin catalog executable became '$($agent.executable)', expected the PATH command 'cursor'" }
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
    $context = New-AgentHubPathBindingContext -Platform windows -TargetUserProfile 'C:\real\user\AppData\Local\Temp\scratch' -InvokingUserProfile 'C:\real\user' -RegistryUserProfile 'C:\real\user'
    $bound = Resolve-AgentHubBoundPath -Declared 'C:\real\user\AppData\Local\Temp\scratch\.claude\CLAUDE.md' -Context $context
    if ($bound -ne 'C:\real\user\AppData\Local\Temp\scratch\.claude\CLAUDE.md') {
        return @{ Passed = $false; Detail = "already-isolated path was nested: '$bound'" }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-RegistryPlatformPathsResolvePerOs {
    . (Join-Path $repoRoot 'scripts\lib\HostCatalog.ps1')
    $expectations = @(
        @{ Platform = 'darwin'; Home = '/Users/synth'; Host = 'devin'; Field = 'config'; Expected = '/Users/synth/.config/devin/config.json' }
        @{ Platform = 'linux'; Home = '/home/synth'; Host = 'devin'; Field = 'config'; Expected = '/home/synth/.config/devin/config.json' }
        @{ Platform = 'windows'; Home = 'C:\synth'; Host = 'devin'; Field = 'config'; Expected = 'C:\synth\AppData\Roaming\devin\config.json' }
        @{ Platform = 'darwin'; Home = '/Users/synth'; Host = 'warp'; Field = 'configHome'; Expected = '/Users/synth/.warp' }
        @{ Platform = 'linux'; Home = '/home/synth'; Host = 'warp'; Field = 'configHome'; Expected = '/home/synth/.config/warp-terminal' }
        @{ Platform = 'darwin'; Home = '/Users/synth'; Host = 'antigravity-desktop'; Field = 'configHome'; Expected = '/Users/synth/Library/Application Support/Antigravity' }
        @{ Platform = 'linux'; Home = '/home/synth'; Host = 'vscode-insiders'; Field = 'settings'; Expected = '/home/synth/.config/Code - Insiders/User/settings.json' }
        @{ Platform = 'darwin'; Home = '/Users/synth'; Host = 'claude'; Field = 'executable'; Expected = '/Users/synth/.local/bin/claude' }
        @{ Platform = 'linux'; Home = '/home/synth'; Host = 'codex'; Field = 'executable'; Expected = 'codex' }
    )
    foreach ($case in $expectations) {
        $doc = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $context = New-AgentHubPathBindingContext -Platform $case.Platform -TargetUserProfile $case.Home -InvokingUserProfile '/nonexistent/invoker' -LocalAppData '' -RoamingConfig ''
        Import-AgentHubBoundHostCatalog -AgentsDocument $doc -Context $context | Out-Null
        $agent = @(@($doc.activeAgents) + @($doc.inactiveAgents) | Where-Object id -eq $case.Host)[0]
        $actual = if ($case.Field -eq 'executable') { $agent.executable } else { $agent.nativePaths.($case.Field) }
        if ($actual -ne $case.Expected) {
            return @{ Passed = $false; Detail = "$($case.Host).$($case.Field) on $($case.Platform) resolved to '$actual', expected '$($case.Expected)'" }
        }
    }
    return @{ Passed = $true; Detail = $null }
}

$behaviors = @(
    @{ Name = 'template expands to the target profile'; Run = { Test-TemplateExpandsToTarget } }
    @{ Name = 'registry platformPaths resolve each host to its documented macOS, Linux and Windows location'; Run = { Test-RegistryPlatformPathsResolvePerOs } }
    @{ Name = 'recorded absolute path rebases from the registry profile'; Run = { Test-RecordedAbsoluteRebasesFromRegistryProfile } }
    @{ Name = 'missing registry profile still rebases from the invoking profile'; Run = { Test-MissingRegistryProfileFallsBackToInvokingProfile } }
    @{ Name = 'UNC and forward-slash absolutes are refused'; Run = { Test-UnrebasableShapeIsRefused } }
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
