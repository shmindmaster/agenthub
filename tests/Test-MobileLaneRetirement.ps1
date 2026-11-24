#Requires -Version 5.1
<#
Behavior tests for the 2026-11-24 retirement of the sh-forge lanes in the mobile-development package.

The sh-forge droplet is retired and Daytona is the lane. Daytona has no /dev/kvm, so the remote Android emulator worker
is gone, and iOS work is a paid 24-hour Daytona v2 Mac reservation. These checks are local, read-only and run on
Linux and Windows alike: they never start ssh, adb, an emulator, VMware, a Mac or a Daytona box.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packageRoot = Join-Path $repoRoot 'packages/mobile-development'
$entrypoint = Join-Path $packageRoot 'mobile.ps1'
$labRoot = Join-Path $packageRoot 'skills/mobile-device-lab'
$hostExe = (Get-Process -Id $PID).Path
$failures = [Collections.Generic.List[string]]::new()
$reported = 0

function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

function Read-Text([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 }

# 1. The remote Android command refuses with one message and drives nothing.
$remoteRefusal = @(& $hostExe -NoProfile -File $entrypoint remote status -Json 2>&1)
$remoteExit = $LASTEXITCODE
$remoteText = $remoteRefusal -join "`n"
Report 'mobile.ps1 remote refuses with one message naming Daytona and the missing KVM, and runs nothing over ssh' (
    $remoteExit -eq 1 -and $remoteText -match 'Daytona' -and $remoteText -match 'KVM' -and $remoteText -notmatch 'ssh\s+mobile-lab'
) "exit=$remoteExit output=$remoteText"

# 2. The forge lane and the remote worker are gone from the tree and the registry.
$gone = @(
    'forge', 'references/forge-mac.md', 'references/remote-android.md', 'scripts/worker', 'scripts/Invoke-MobileLabRemote.ps1'
) | Where-Object { Test-Path -LiteralPath (Join-Path $labRoot $_) }
$contract = Get-Content -LiteralPath (Join-Path $repoRoot 'registry/mobile-development.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Report 'the forge lane files and the remote Android worker are removed' (
    @($gone).Count -eq 0 -and $null -eq $contract.remoteAndroid
) "still present: $(@($gone) -join ', '); remoteAndroid=$($null -ne $contract.remoteAndroid)"
$retiredTests = @('Test-MobileLabArchiveChunks.ps1', 'Test-MobileLabLaunchUrl.ps1', 'Test-MobileLabMetroStop.ps1', 'Test-MobileLabPreCommandGate.ps1') |
    Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot "tests/$_") }
Report 'the tests of the removed remote worker are removed with it' (@($retiredTests).Count -eq 0) "still present: $(@($retiredTests) -join ', ')"

# 3. The Daytona Mac reference records the rules the owner set, and the skill points at it.
$macPath = Join-Path $labRoot 'references/daytona-mac.md'
$mac = if (Test-Path -LiteralPath $macPath) { Read-Text $macPath } else { '' }
$skill = Read-Text (Join-Path $labRoot 'SKILL.md')
Report 'daytona-mac.md records the reservation rules and SKILL.md points at it' (
    $mac -match 'base-macos' -and $mac -match 'us-east-bos-1' -and $mac -match 'reservation' -and
    $mac -match '(?i)owner approval' -and $mac -match '(?i)renewal' -and $mac -match '24-hour' -and
    $mac -match '(?i)not an iOS build' -and $mac -match 'daytona_mac\.py status' -and $mac -match 'no /dev/kvm|KVM' -and
    $skill -match 'references/daytona-mac\.md' -and $skill -notmatch 'forge-mac|ssh forge'
) 'The Daytona Mac reference or its SKILL link is missing or incomplete.'

# 4. No file in the package still points an agent at the retired droplet.
$hits = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '[\/](node_modules|fixtures)[\/]' } |
    Where-Object { (Read-Text $_.FullName) -match '(?i)sh-forge|ssh forge|forge-mac|forge\.shtrial|/opt/forge|forge guest' } |
    ForEach-Object { $_.FullName.Substring($packageRoot.Length + 1) })
Report 'no mobile-development file points an agent at the retired forge droplet' ($hits.Count -eq 0) "files=$($hits -join ',')"

$registryHits = @('registry/mobile-development.json', 'registry/mobile-scope.json', 'registry/mcps.json') |
    Where-Object { (Read-Text (Join-Path $repoRoot $_)) -match '(?i)sh-forge|ssh forge|forge-mac|forge\.shtrial|forge guest' }
Report 'the mobile registries do not name the retired forge droplet' (@($registryHits).Count -eq 0) "files=$(@($registryHits) -join ',')"

# 5. The retired local VMware VM refusal names the Daytona route, not forge.
$guestText = Read-Text (Join-Path $labRoot 'scripts/MobileLabGuest.psm1')
Report 'the retired-VM refusal names the Daytona Mac route' (
    $guestText -match 'AGENTHUB_ALLOW_LOCAL_VM' -and $guestText -match 'Daytona' -and $guestText -notmatch '(?i)forge'
) 'MobileLabGuest.psm1 still names forge or omits the Daytona route.'

# 6. The runner kit that served forge is not shipped any more, and the runbook keeps only the short status.
$runbook = Read-Text (Join-Path $repoRoot 'docs/runbooks/do-interim-release.md')
Report 'ci/do-runner is removed and the runbook keeps only the runner status with the Linear pointer' (
    -not (Test-Path -LiteralPath (Join-Path $repoRoot 'ci/do-runner')) -and $runbook -match 'CORE-107' -and
    $runbook -notmatch '(?i)forge|android-build|jobs dashboard'
) 'ci/do-runner still exists or the runbook still carries forge instructions.'

if ($failures.Count) {
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
