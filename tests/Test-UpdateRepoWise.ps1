#Requires -Version 5.1
<#
Behavior tests for scripts/Update-RepoWise.ps1. The live PyPI/uv path is not
the test: injected versions prove behind/current/missing verdicts, and Apply
must call the upgrade command rather than report success while still behind.

Run: pwsh -NoProfile -File tests/Test-UpdateRepoWise.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script = Join-Path $repoRoot 'scripts\Update-RepoWise.ps1'
$hostExe = (Get-Process -Id $PID).Path

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

$stateFile = Join-Path ([IO.Path]::GetTempPath()) ('repowise-cli-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
$settingsFile = [IO.Path]::ChangeExtension($stateFile, '.settings.json')
$augmentExe = [IO.Path]::ChangeExtension($stateFile, '.augment.exe')
function Invoke-Updater {
    param([string[]]$UpdaterArgs, [switch]$BlockProbes, [switch]$FailLatestProbe)
    $all = @('-StateFile', $stateFile) + $UpdaterArgs
    if ($UpdaterArgs -notcontains '-ClaudeSettingsPath') { $all += @('-ClaudeSettingsPath', $settingsFile) }
    if ($UpdaterArgs -notcontains '-AugmentExe') { $all += @('-AugmentExe', $augmentExe) }
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($BlockProbes -or $FailLatestProbe) {
            $arguments = ($all | ForEach-Object {
                if ($_ -match '^-[A-Za-z]+$') { $_ } else { "'" + $_.Replace("'", "''") + "'" }
            }) -join ' '
            $blockedCommands = 'function Invoke-RestMethod { throw "unexpected-pypi-query" }; '
            if ($BlockProbes) { $blockedCommands += 'function Get-Command { throw "unexpected-cli-probe" }; ' }
            $command = $blockedCommands + '& ' + "'" + $script.Replace("'", "''") + "' " + $arguments
            $output = & $hostExe -NoProfile -Command $command 2>&1 | Out-String
        } else {
            $output = & $hostExe -NoProfile -File $script @all 2>&1 | Out-String
        }
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

Report 'updater-script-exists' (Test-Path -LiteralPath $script) $script
$raw = Get-Content -LiteralPath $script -Raw -Encoding UTF8
Report 'sets-stop-eap' ($raw -match '(?m)^\$ErrorActionPreference\s*=\s*''Stop''') 'missing top-level Stop'

$behind = Invoke-Updater -UpdaterArgs @('-Audit', '-InstalledVersion', '0.39.0', '-LatestVersion', '0.44.0')
Report 'audit-behind-exits-1' ($behind.ExitCode -eq 1) "exit=$($behind.ExitCode) output=$($behind.Output)"
Report 'audit-behind-names-versions' (
    $behind.Output -match 'installed=0\.39\.0' -and $behind.Output -match 'latest=0\.44\.0' -and $behind.Output -match 'status=behind'
) $behind.Output

$current = Invoke-Updater -UpdaterArgs @('-Audit', '-InstalledVersion', '0.44.0', '-LatestVersion', '0.44.0')
Report 'audit-current-exits-0' ($current.ExitCode -eq 0) "exit=$($current.ExitCode) output=$($current.Output)"
Report 'audit-current-pass-line' ($current.Output -match 'PASS: RepoWise CLI is the PyPI latest') $current.Output

$missing = Invoke-Updater -UpdaterArgs @('-Audit', '-InstalledVersion', 'none', '-LatestVersion', '0.44.0')
Report 'audit-missing-exits-1' ($missing.ExitCode -eq 1) "exit=$($missing.ExitCode) output=$($missing.Output)"
Report 'audit-missing-status' ($missing.Output -match 'status=missing') $missing.Output

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('repowise-uv-stub-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $scratch | Out-Null
$stub = Join-Path $scratch 'uv.cmd'
$log = Join-Path $scratch 'uv.log'
@(
    '@echo off'
    "echo uv-stub %*>> `"$log`""
    'exit /b 1'
) | Set-Content -LiteralPath $stub -Encoding ASCII

$applyBehind = Invoke-Updater -UpdaterArgs @(
    '-Apply', '-InstalledVersion', '0.39.0', '-LatestVersion', '0.44.0', '-UvExe', $stub
)
Report 'apply-behind-invokes-uv' (Test-Path -LiteralPath $log) 'uv stub was not executed'
$uvLog = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw -Encoding UTF8 } else { '' }
Report 'apply-behind-upgrade-not-install' ($uvLog -match 'tool upgrade repowise') $uvLog
Report 'apply-behind-fails-if-uv-fails' ($applyBehind.ExitCode -ne 0) "exit=$($applyBehind.ExitCode) output=$($applyBehind.Output)"
Report 'apply-behind-does-not-claim-current' ($applyBehind.Output -notmatch 'PASS: RepoWise CLI is now') $applyBehind.Output

Report 'does-not-pin-a-version-in-the-script' ($raw -notmatch '0\.44\.0') 'script hardcodes 0.44.0; latest must come from PyPI'
Report 'uses-uv-tool-upgrade' ($raw -match 'tool'', ''upgrade'', ''repowise') 'missing uv tool upgrade'

# Owner direction 2026-10-13: no scheduled agent jobs. The updater may only
# delete its retired task, never create one.
Report 'never-creates-a-scheduled-task' ($raw -notmatch '/Create|Register-ScheduledTask') 'updater still contains a task-creation path'
$register = Invoke-Updater -UpdaterArgs @('-RegisterSchedule')
Report 'register-schedule-is-refused' ($register.ExitCode -ne 0 -and $register.Output -match 'retired') "exit=$($register.ExitCode) output=$($register.Output)"

$schLog = Join-Path $scratch 'schtasks.log'
$schPresent = Join-Path $scratch 'schtasks-present.cmd'
$presenceFile = Join-Path $scratch 'present.flag'
Set-Content -LiteralPath $presenceFile -Value 'present' -Encoding ASCII
@(
    '@echo off'
    "echo %*>> `"$schLog`""
    "if not exist `"$presenceFile`" goto absent"
    "if /I `"%1`"==`"/Delete`" del `"$presenceFile`""
    'exit /b 0'
    ':absent'
    'echo ERROR: The system cannot find the file specified.'
    'exit /b 1'
) | Set-Content -LiteralPath $schPresent -Encoding ASCII
$removed = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schPresent)
$schText = if (Test-Path -LiteralPath $schLog) { Get-Content -LiteralPath $schLog -Raw -Encoding UTF8 } else { '' }
Report 'remove-schedule-deletes-named-task' ($removed.ExitCode -eq 0 -and $schText -match '/Delete /TN AgentHub-Update-RepoWise /F') "exit=$($removed.ExitCode) log=$schText output=$($removed.Output)"
Report 'remove-schedule-does-not-probe-pypi' ($removed.Output -notmatch 'installed=') $removed.Output

Remove-Item -LiteralPath $schLog -Force -ErrorAction SilentlyContinue
$schAbsent = Join-Path $scratch 'schtasks-absent.cmd'
@(
    '@echo off'
    "echo %*>> `"$schLog`""
    'echo ERROR: The system cannot find the file specified.'
    'exit /b 1'
) | Set-Content -LiteralPath $schAbsent -Encoding ASCII
$absent = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schAbsent)
$schText = if (Test-Path -LiteralPath $schLog) { Get-Content -LiteralPath $schLog -Raw -Encoding UTF8 } else { '' }
Report 'remove-schedule-absent-is-pass' ($absent.ExitCode -eq 0 -and $absent.Output -match 'absent') "exit=$($absent.ExitCode) output=$($absent.Output)"
Report 'remove-schedule-absent-skips-delete' ($schText -notmatch '/Delete') $schText

Remove-Item -LiteralPath $schLog -Force -ErrorAction SilentlyContinue
$schDenied = Join-Path $scratch 'schtasks-denied.cmd'
@('@echo off', "echo %*>> `"$schLog`"", 'echo ERROR: Access is denied.', 'exit /b 1') |
    Set-Content -LiteralPath $schDenied -Encoding ASCII
$denied = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schDenied)
Report 'query-access-denied-fails' ($denied.ExitCode -ne 0) $denied.Output
Report 'query-access-denied-never-claims-absent' ($denied.Output -notmatch 'PASS:.*absent') $denied.Output
$deniedLog = Get-Content -LiteralPath $schLog -Raw -Encoding UTF8
Report 'query-access-denied-skips-delete' ($deniedLog -notmatch '/Delete') $deniedLog

$notRemoved = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $stub)
Report 'query-unclassified-failure-is-not-absence' ($notRemoved.ExitCode -ne 0 -and $notRemoved.Output -notmatch 'PASS:.*absent') $notRemoved.Output

$schUnchanged = Join-Path $scratch 'schtasks-unchanged.cmd'
@('@echo off', 'exit /b 0') | Set-Content -LiteralPath $schUnchanged -Encoding ASCII
$unchanged = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schUnchanged)
Report 'delete-success-with-task-still-present-fails' ($unchanged.ExitCode -ne 0 -and $unchanged.Output -notmatch 'PASS:.*removed') $unchanged.Output

$settingsFile = Join-Path $scratch 'settings.json'
$augmentExe = Join-Path $scratch 'native augment.exe'
[IO.File]::WriteAllBytes($augmentExe, [byte[]]@())
$hookArgs = @('-ClaudeSettingsPath', $settingsFile, '-AugmentExe', $augmentExe)
$postToolUse = 'input=$(cat); case "$input" in *"git commit"*) if command -v repowise-augment >/dev/null 2>&1; then printf "%s" "$input" | repowise-augment; fi;; esac'
$guardedAugment = 'if command -v repowise-augment >/dev/null 2>&1; then exec repowise-augment; fi'
$postJson = ConvertTo-Json -InputObject $postToolUse -Compress
$guardJson = ConvertTo-Json -InputObject $guardedAugment -Compress
$template = @'
{
  "env": { "SYNTHETIC_SECRET": "never-print-this-fixture" },
  "description": __POST__,
  "metadata": "\"command\": __EMBEDDED__",
  "outside": { "command" : __GUARD__ },
  "hooks" : {
    "PostToolUse": [{ "matcher": "Bash", "hooks": [
      { "type": "command", "command" : __POST__, "timeout": 10 },
      { "type": "command", "command": "custom-hook --keep", "note": __GUARD__ },
      { "type": "command", "command": __NEAR__ },
      { "type": "command", "Command": __GUARD__ }
    ] }],
    "SessionStart": [{ "hooks": [{ "type": "command", "command": __GUARD__ }] }]
  },
  "unchanged": [true, 1.00, "caf\u00e9"]
}
'@
$fixture = $template.Replace('__POST__', $postJson).Replace('__GUARD__', $guardJson).
    Replace('__NEAR__', (ConvertTo-Json -InputObject ($guardedAugment + ' ') -Compress)).
    Replace('__EMBEDDED__', $guardJson.Replace('\', '\\').Replace('"', '\"')).Replace("`n", "`r`n") + "`r`n"
$encoding = [Text.UTF8Encoding]::new($true)
[IO.File]::WriteAllText($settingsFile, $fixture, $encoding)
$originalBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile))
Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
$auditHooks = Invoke-Updater -UpdaterArgs (@('-Audit', '-InstalledVersion', '0.59.0', '-LatestVersion', '0.59.0') + $hookArgs)
Report 'audit-preserves-hook-settings' ($auditHooks.ExitCode -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $originalBytes) 'audit changed settings or failed'
Report 'audit-does-not-write-state' (-not (Test-Path -LiteralPath $stateFile)) 'audit wrote its state file'

$repaired = Invoke-Updater -BlockProbes -UpdaterArgs (@('-RepairHooks', '-UvExe', $stub) + $hookArgs)
Report 'standalone-repair-skips-pypi-cli-and-install-probes' ($repaired.ExitCode -eq 0 -and $repaired.Output -notmatch 'installed=|unexpected-.*probe|unexpected-pypi-query') "exit=$($repaired.ExitCode)"
$nativeCommand = '"' + ([IO.Path]::GetFullPath($augmentExe).Replace('\', '/')) + '"'
$nativeJson = ConvertTo-Json -InputObject $nativeCommand -Compress
$expected = $fixture.Replace('"command" : ' + $postJson, '"command" : ' + $nativeJson).
    Replace('"command": ' + $guardJson, '"command": ' + $nativeJson)
$expectedBytes = [byte[]]($encoding.GetPreamble() + $encoding.GetBytes($expected))
$expectedBase64 = [Convert]::ToBase64String($expectedBytes)
$actual = [IO.File]::ReadAllText($settingsFile) | ConvertFrom-Json
Report 'normalizes-posttooluse-wrapper' ($actual.hooks.PostToolUse[0].hooks[0].command -ceq $nativeCommand) 'PostToolUse did not use quoted forward-slash executable'
Report 'normalizes-guarded-augment-wrapper' ($actual.hooks.SessionStart[0].hooks[0].command -ceq $nativeCommand) 'guarded augment was not normalized'
Report 'preserves-all-other-raw-bytes' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $expectedBase64) 'changed unrelated values, formatting, encoding or BOM'
Report 'repair-does-not-log-config-secrets' ($repaired.Output -notmatch 'never-print-this-fixture|custom-hook|input=\$') 'repair logged settings contents'
Report 'standalone-does-not-write-version-state' (-not (Test-Path -LiteralPath $stateFile)) 'repair wrote version state'
$firstWriteTime = [IO.File]::GetLastWriteTimeUtc($settingsFile)
$second = Invoke-Updater -BlockProbes -UpdaterArgs (@('-RepairHooks') + $hookArgs)
Report 'second-repair-is-byte-and-write-noop' ($second.ExitCode -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $expectedBase64 -and [IO.File]::GetLastWriteTimeUtc($settingsFile) -eq $firstWriteTime) 'second repair failed or rewrote settings'

[IO.File]::WriteAllText($settingsFile, $fixture, $encoding)
$applyCurrent = Invoke-Updater -UpdaterArgs (@('-Apply', '-InstalledVersion', '0.59.0', '-LatestVersion', '0.59.0', '-UvExe', $stub) + $hookArgs)
Report 'apply-current-repairs-hooks' ($applyCurrent.ExitCode -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $expectedBase64) "exit=$($applyCurrent.ExitCode)"

$migrationSource = Join-Path $scratch 'migration-settings.json'
$migrationLog = Join-Path $scratch 'migration.log'
[IO.File]::WriteAllText($migrationSource, $fixture, $encoding)
$repowiseStub = Join-Path $scratch 'repowise.cmd'
@(
    '@echo off'
    'if "%1"=="--version" goto version'
    'if "%1"=="agents" if "%2"=="--help" goto migration'
    'exit /b 1'
    ':version'
    'echo repowise, version 0.59.0'
    'exit /b 0'
    ':migration'
    "copy /y `"$migrationSource`" `"$settingsFile`" >nul"
    "echo migrated> `"$migrationLog`""
    'exit /b 0'
) | Set-Content -LiteralPath $repowiseStub -Encoding ASCII
$previousPath = $env:PATH
try {
    $env:PATH = $scratch + [IO.Path]::PathSeparator + $previousPath
    $migratedApply = Invoke-Updater -UpdaterArgs (@('-Apply', '-LatestVersion', '0.59.0', '-UvExe', $stub) + $hookArgs)
} finally {
    $env:PATH = $previousPath
}
Report 'apply-runs-editor-migrations-before-hook-repair' ($migratedApply.ExitCode -eq 0 -and (Test-Path -LiteralPath $migrationLog) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $expectedBase64) "exit=$($migratedApply.ExitCode)"

[IO.File]::WriteAllText($settingsFile, $expected, $encoding)
Remove-Item -LiteralPath $migrationLog -Force
try {
    $env:PATH = $scratch + [IO.Path]::PathSeparator + $previousPath
    $failedLatest = Invoke-Updater -FailLatestProbe -UpdaterArgs (@('-Apply', '-UvExe', $stub) + $hookArgs)
} finally {
    $env:PATH = $previousPath
}
Report 'failed-update-check-preserves-working-hooks' ($failedLatest.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $migrationLog) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $expectedBase64) "exit=$($failedLatest.ExitCode)"

[IO.File]::WriteAllText($settingsFile, $fixture, $encoding)
$missingExe = Join-Path $scratch 'missing.exe'
$noExe = Invoke-Updater -BlockProbes -UpdaterArgs @('-RepairHooks', '-ClaudeSettingsPath', $settingsFile, '-AugmentExe', $missingExe)
Report 'needed-repair-with-missing-executable-fails' ($noExe.ExitCode -ne 0) 'repair reported success without executable'
Report 'missing-executable-preserves-settings' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $originalBytes) 'missing executable mutated settings'
[IO.File]::WriteAllText($settingsFile, '{"command": "custom-hook"}', $encoding)
$noRepairNeeded = Invoke-Updater -BlockProbes -UpdaterArgs @('-RepairHooks', '-ClaudeSettingsPath', $settingsFile, '-AugmentExe', $missingExe)
Report 'unrelated-hooks-do-not-require-executable' ($noRepairNeeded.ExitCode -eq 0) 'unneeded repair required executable'

$invalid = '{"secret":"never-print-invalid-fixture", "command": ' + $guardJson + ', "broken": }'
[IO.File]::WriteAllText($settingsFile, $invalid, $encoding)
$invalidBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile))
$invalidRepair = Invoke-Updater -BlockProbes -UpdaterArgs (@('-RepairHooks') + $hookArgs)
Report 'invalid-json-fails-before-mutation' ($invalidRepair.ExitCode -ne 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsFile)) -ceq $invalidBytes) 'invalid JSON accepted or changed'
Report 'invalid-json-error-does-not-log-contents' ($invalidRepair.Output -notmatch 'never-print-invalid-fixture') 'invalid JSON diagnostic exposed contents'

Remove-Item -LiteralPath $settingsFile -Force
$noSettings = Invoke-Updater -BlockProbes -UpdaterArgs @('-RepairHooks', '-ClaudeSettingsPath', $settingsFile, '-AugmentExe', $missingExe)
Report 'missing-settings-is-noop-without-executable' ($noSettings.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $settingsFile)) 'missing settings failed or created a file'

$plainExe = Join-Path $scratch 'augment.exe'
[IO.File]::WriteAllBytes($plainExe, [byte[]]@())
[IO.File]::WriteAllText($settingsFile, '{"hooks":{"SessionStart":[{"hooks":[{"command":' + $guardJson + '}]}]}}', [Text.UTF8Encoding]::new($false))
$plainRepair = Invoke-Updater -BlockProbes -UpdaterArgs @('-RepairHooks', '-ClaudeSettingsPath', $settingsFile, '-AugmentExe', $plainExe)
$plainActual = [IO.File]::ReadAllText($settingsFile) | ConvertFrom-Json
Report 'path-without-whitespace-is-unquoted' ($plainRepair.ExitCode -eq 0 -and $plainActual.hooks.SessionStart[0].hooks[0].command -ceq ([IO.Path]::GetFullPath($plainExe).Replace('\', '/'))) 'unspaced path was not a direct executable'
Report 'utf8-without-bom-stays-without-bom' ([IO.File]::ReadAllBytes($settingsFile)[0] -eq 123) 'repair added a BOM'

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f ($reported - $failures.Count), $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
