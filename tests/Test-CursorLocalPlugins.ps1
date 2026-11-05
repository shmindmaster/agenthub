#Requires -Version 7
<#
Behavior test for scripts/Install-CursorLocalPlugins.ps1.

Why: Cursor's loader skips a link whose target is outside ~/.cursor/plugins/local,
and a Windows junction counts as a link, so linked AgentHub plugins never loaded.

Checks, on a fixture:
- the audit fails on a link, a stale copy and a missing plugin, so it can fail;
- install turns a link into a real folder and leaves the link's target intact;
- a folder the script does not manage is left alone;
- the audit passes afterwards.

Then checks the real folder holds no AgentHub links. A machine without Cursor skips this.

Run: pwsh -NoProfile -File tests/Test-CursorLocalPlugins.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'scripts/Install-CursorLocalPlugins.ps1'
$failures = New-Object System.Collections.Generic.List[string]
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

function Invoke-Installer([string[]]$Packages, [string]$Target, [switch]$Audit) {
    $arguments = @('-NoProfile', '-File', $script, '-Target', $Target, '-PackagePaths', ($Packages -join ','))
    if ($Audit) { $arguments += '-Audit' }
    $output = & pwsh @arguments 2>&1 | Out-String
    return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("cursor-local-" + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
try {
    $package = Join-Path $work 'source/alpha'
    [void][IO.Directory]::CreateDirectory((Join-Path $package 'skills/go'))
    [IO.File]::WriteAllText((Join-Path $package 'plugin.json'), '{"name":"ah-alpha"}')
    [IO.File]::WriteAllText((Join-Path $package 'skills/go/SKILL.md'), 'one')
    [void][IO.Directory]::CreateDirectory((Join-Path $package '.git'))
    [IO.File]::WriteAllText((Join-Path $package '.git/config'), 'skip me')

    $target = Join-Path $work 'local'
    [void][IO.Directory]::CreateDirectory($target)
    $other = Join-Path $target 'sentry'
    [void][IO.Directory]::CreateDirectory($other)
    [IO.File]::WriteAllText((Join-Path $other 'keep.txt'), 'keep')

    $missing = Invoke-Installer @($package) $target -Audit
    Assert-True ($missing.ExitCode -eq 1 -and $missing.Output -match 'ah-alpha\s+missing') 'audit should fail on a missing plugin'

    $link = Join-Path $target 'ah-alpha'
    [void](New-Item -ItemType Junction -Path $link -Target $package)
    $linked = Invoke-Installer @($package) $target -Audit
    Assert-True ($linked.ExitCode -eq 1 -and $linked.Output -match 'ah-alpha\s+link') 'audit should fail on a link'

    $install = Invoke-Installer @($package) $target
    Assert-True ($install.ExitCode -eq 0) "install failed: $($install.Output)"
    $item = Get-Item -LiteralPath $link -Force
    Assert-True (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'install should replace the link with a real folder'
    Assert-True (Test-Path -LiteralPath (Join-Path $package 'skills/go/SKILL.md')) 'removing the link must not touch its target'
    Assert-True (Test-Path -LiteralPath (Join-Path $link 'skills/go/SKILL.md')) 'install should copy package files'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $link '.git'))) 'install should skip .git'
    Assert-True (Test-Path -LiteralPath (Join-Path $other 'keep.txt')) 'install must leave unmanaged folders alone'

    $current = Invoke-Installer @($package) $target -Audit
    Assert-True ($current.ExitCode -eq 0) "audit should pass after install: $($current.Output)"

    [IO.File]::WriteAllText((Join-Path $package 'skills/go/SKILL.md'), 'two')
    $stale = Invoke-Installer @($package) $target -Audit
    Assert-True ($stale.ExitCode -eq 1 -and $stale.Output -match 'ah-alpha\s+stale') 'audit should fail on a stale copy'

    $refresh = Invoke-Installer @($package) $target
    Assert-True ($refresh.ExitCode -eq 0) "refresh failed: $($refresh.Output)"
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'skills/go/SKILL.md') -Raw -Encoding utf8) -eq 'two') 'refresh should update the copy'
}
finally {
    [IO.Directory]::Delete($work, $true)
}

$real = Join-Path $HOME '.cursor/plugins/local'
if (Test-Path -LiteralPath $real) {
    foreach ($entry in Get-ChildItem -LiteralPath $real -Directory -Force -Filter 'ah-*') {
        Assert-True (-not ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) "$($entry.Name) is a link, and Cursor will not load it"
    }
}

foreach ($failure in $failures) { Write-Output "FAIL: $failure" }
Write-Output "Test-CursorLocalPlugins: passed=$passed failed=$($failures.Count)"
if ($failures.Count) { exit 1 }
