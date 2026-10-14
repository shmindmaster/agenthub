#Requires -Version 5.1
<#
Behavior tests for macOS-guest bring-up and VMware host-service diagnosis.

Every case is synthetic: guest probes, vmrun, the VMX process check, Windows
service state, elevation, and service mutation are injected script blocks. No
case starts, stops, or reconfigures a service, VM, guest, or emulator. The one
live probe (the read-only runtime check) only compares a Get-Service snapshot
before and after.

Reproduced 2026-10-13: VMAuthdService, VMnetDHCP, and VMware NAT Service were
all Stopped/Manual, no vmware-vmx process ran, and Start-MobileLab.ps1 piped
`vmrun start` to Out-Null and threw only "vmrun start failed with exit -1";
vmrun's own output was "Unknown error". Starting the three services fixed it.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packageRoot = Join-Path $repoRoot 'packages\mobile-development'
$scriptsRoot = Join-Path $packageRoot 'skills\mobile-device-lab\scripts'
$failures = [Collections.Generic.List[string]]::new()
$reported = 0

function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

function New-Svc([string]$Name, [string]$Status, [string]$StartType) {
    [pscustomobject]@{ Name = $Name; Status = $Status; StartType = $StartType }
}

function Invoke-Capture([scriptblock]$Block) {
    try { [pscustomobject]@{ Value = (& $Block); Error = $null } }
    catch { [pscustomobject]@{ Value = $null; Error = $_.Exception.Message } }
}

Import-Module (Join-Path $packageRoot 'MobileDevelopment.psm1') -Force
Import-Module (Join-Path $scriptsRoot 'MobileLabGuest.psm1') -Force

$required = @('VMAuthdService', 'VMnetDHCP', 'VMware NAT Service')
$vmwareResource = Get-MobileDevelopmentResource -Id 'vmware-workstation'
$declared = @($vmwareResource.discovery.hostServices | ForEach-Object { [string]$_.name })
Report 'registry declares the three VMware host services the guest depends on' (
    (@($declared) -join '|') -ceq ($required -join '|') -and
    @($vmwareResource.discovery.hostServices | Where-Object { -not $_.role }).Count -eq 0
) "declared=$($declared -join ',')"

$allStopped = @($required | ForEach-Object { New-Svc $_ 'Stopped' 'Manual' })
$allRunning = @($required | ForEach-Object { New-Svc $_ 'Running' 'Automatic' })

$stoppedState = Invoke-Capture { Get-MobileVmwareServiceState -Services $allStopped }
Report 'stopped VMware services are reported by name, status, and start type with an elevated remediation' (
    -not $stoppedState.Error -and $stoppedState.Value -and -not $stoppedState.Value.ready -and
    (@($stoppedState.Value.notRunning) -join '|') -ceq ($required -join '|') -and
    $stoppedState.Value.summary -match 'VMAuthdService=Stopped/Manual' -and
    $stoppedState.Value.remediation -match 'elevated' -and
    $stoppedState.Value.remediation -match [regex]::Escape("Start-Service -Name 'VMware NAT Service'") -and
    $stoppedState.Value.remediation -match '-RepairVmwareServices'
) "error=$($stoppedState.Error) state=$($stoppedState.Value | ConvertTo-Json -Depth 5 -Compress)"

$runningState = Invoke-Capture { Get-MobileVmwareServiceState -Services $allRunning }
Report 'all VMware services running is ready with no remediation' (
    -not $runningState.Error -and $runningState.Value.ready -and @($runningState.Value.notRunning).Count -eq 0 -and
    [string]::IsNullOrEmpty([string]$runningState.Value.remediation)
) "error=$($runningState.Error) state=$($runningState.Value | ConvertTo-Json -Depth 5 -Compress)"

$missingState = Invoke-Capture { Get-MobileVmwareServiceState -Services @($allRunning[0], $allRunning[1]) }
Report 'an unregistered VMware service is reported missing with an installer-repair remediation' (
    -not $missingState.Error -and -not $missingState.Value.ready -and
    (@($missingState.Value.missing) -join '|') -ceq 'VMware NAT Service' -and
    $missingState.Value.remediation -match 'Repair'
) "error=$($missingState.Error) state=$($missingState.Value | ConvertTo-Json -Depth 5 -Compress)"

# ------------------------------------------------------------ bring-up decision
$vmx = 'D:\Synthetic\macos.vmx'
$calls = [ordered]@{ start = 0; repair = 0; services = 0 }
function Reset-Calls { $script:calls.start = 0; $script:calls.repair = 0; $script:calls.services = 0 }

Reset-Calls
$degraded = Invoke-Capture {
    Invoke-MobileLabGuestBringUp -Vmx $vmx -VmrunPath 'C:\synthetic\vmrun.exe' `
        -ProbeGuest { [pscustomobject]@{ address = '192.0.2.10'; source = 'vmnetdhcp-lease' } } `
        -ListRunning { @('Total running VMs: 0') } `
        -TestVmxProcess { $false } `
        -GetServiceState { $script:calls.services++; Get-MobileVmwareServiceState -Services $allRunning } `
        -StartVm { $script:calls.start++; [pscustomobject]@{ ExitCode = 0; Output = @() } } `
        -RepairServices { param($State) $script:calls.repair++ }
}
Report 'healthy SSH with an empty vmrun list neither starts the VM nor repairs services' (
    -not $degraded.Error -and $degraded.Value.action -eq 'already-reachable' -and -not $degraded.Value.started -and
    $degraded.Value.controlChannel -eq 'degraded' -and $degraded.Value.guestAddress -eq '192.0.2.10' -and
    $calls.start -eq 0 -and $calls.repair -eq 0
) "error=$($degraded.Error) result=$($degraded.Value | ConvertTo-Json -Depth 5 -Compress) calls=$($calls | ConvertTo-Json -Compress)"

Reset-Calls
$booting = Invoke-Capture {
    Invoke-MobileLabGuestBringUp -Vmx $vmx -VmrunPath 'C:\synthetic\vmrun.exe' `
        -ProbeGuest { $null } -ListRunning { @('Total running VMs: 0') } -TestVmxProcess { $true } `
        -GetServiceState { Get-MobileVmwareServiceState -Services $allRunning } `
        -StartVm { $script:calls.start++; [pscustomobject]@{ ExitCode = 0; Output = @() } }
}
Report 'a running canonical vmware-vmx process is not restarted when vmrun list omits it' (
    -not $booting.Error -and $booting.Value.action -eq 'already-running' -and -not $booting.Value.started -and $calls.start -eq 0
) "error=$($booting.Error) result=$($booting.Value | ConvertTo-Json -Depth 5 -Compress)"

Reset-Calls
$listed = Invoke-Capture {
    Invoke-MobileLabGuestBringUp -Vmx $vmx -VmrunPath 'C:\synthetic\vmrun.exe' `
        -ProbeGuest { $null } -ListRunning { @('Total running VMs: 1', 'd:/synthetic/MACOS.vmx') } -TestVmxProcess { $false } `
        -GetServiceState { Get-MobileVmwareServiceState -Services $allRunning } `
        -StartVm { $script:calls.start++; [pscustomobject]@{ ExitCode = 0; Output = @() } }
}
Report 'vmrun list matching is case- and separator-insensitive' (
    -not $listed.Error -and $listed.Value.action -eq 'already-running' -and $listed.Value.vmrunListed -and $calls.start -eq 0
) "error=$($listed.Error) result=$($listed.Value | ConvertTo-Json -Depth 5 -Compress)"

Reset-Calls
$blocked = Invoke-Capture {
    Invoke-MobileLabGuestBringUp -Vmx $vmx -VmrunPath 'C:\synthetic\vmrun.exe' `
        -ProbeGuest { $null } -ListRunning { @('Total running VMs: 0') } -TestVmxProcess { $false } `
        -GetServiceState { Get-MobileVmwareServiceState -Services $allStopped } `
        -StartVm { $script:calls.start++; [pscustomobject]@{ ExitCode = -1; Output = @('Error: Unknown error') } } `
        -RepairServices { param($State) $script:calls.repair++ }
}
Report 'stopped VMware services fail fast with named services and a single-line Remediation tail' (
    $blocked.Error -and $calls.start -eq 0 -and $calls.repair -eq 0 -and
    $blocked.Error -match 'VMAuthdService=Stopped/Manual' -and $blocked.Error -match 'VMnetDHCP' -and
    $blocked.Error -match 'Remediation:\s*\S' -and $blocked.Error -notmatch "`n" -and
    $blocked.Error -notmatch 'exit -1'
) "error=$($blocked.Error) calls=$($calls | ConvertTo-Json -Compress)"

Reset-Calls
$missingBlocked = Invoke-Capture {
    Invoke-MobileLabGuestBringUp -Vmx $vmx -VmrunPath 'C:\synthetic\vmrun.exe' -RepairServicesAllowed `
        -ProbeGuest { $null } -ListRunning { @('Total running VMs: 0') } -TestVmxProcess { $false } `
        -GetServiceState { Get-MobileVmwareServiceState -Services @($allRunning[0], $allRunning[1]) } `
        -StartVm { $script:calls.start++; [pscustomobject]@{ ExitCode = 0; Output = @() } } `
        -RepairServices { param($State) $script:calls.repair++ }
}
Report 'an unregistered required service blocks startup even with repair allowed, naming the installer repair' (
    $missingBlocked.Error -and $calls.start -eq 0 -and
    $missingBlocked.Error -match 'VMware NAT Service=NotInstalled' -and
    $missingBlocked.Error -match "installer's Repair option"
) "error=$($missingBlocked.Error) calls=$($calls | ConvertTo-Json -Compress)"

Reset-Calls
$vmrunFailed = Invoke-Capture {
    Invoke-MobileLabGuestBringUp -Vmx $vmx -VmrunPath 'C:\synthetic\vmrun.exe' `
        -ProbeGuest { $null } -ListRunning { @('Total running VMs: 0') } -TestVmxProcess { $false } `
        -GetServiceState { Get-MobileVmwareServiceState -Services $allRunning } `
        -StartVm { $script:calls.start++; [pscustomobject]@{ ExitCode = -1; Output = @('Error: Unknown error', '') } }
}
Report 'vmrun start failure preserves vmrun output, exit code, and service evidence' (
    $vmrunFailed.Error -and $calls.start -eq 1 -and
    $vmrunFailed.Error -match 'exit -1' -and $vmrunFailed.Error -match 'Error: Unknown error' -and
    $vmrunFailed.Error -match 'VMAuthdService=Running/Automatic' -and
    $vmrunFailed.Error -match 'Remediation:\s*\S' -and $vmrunFailed.Error -notmatch "`n"
) "error=$($vmrunFailed.Error)"

Reset-Calls
$script:repairedState = $false
$repaired = Invoke-Capture {
    Invoke-MobileLabGuestBringUp -Vmx $vmx -VmrunPath 'C:\synthetic\vmrun.exe' -RepairServicesAllowed `
        -ProbeGuest { $null } -ListRunning { @('Total running VMs: 0') } -TestVmxProcess { $false } `
        -GetServiceState { if ($script:repairedState) { Get-MobileVmwareServiceState -Services $allRunning } else { Get-MobileVmwareServiceState -Services $allStopped } } `
        -StartVm { $script:calls.start++; [pscustomobject]@{ ExitCode = 0; Output = @() } } `
        -RepairServices { param($State) $script:calls.repair++; $script:repairedState = $true }
}
Report 'explicit repair runs once, re-reads service state, then starts the VM' (
    -not $repaired.Error -and $repaired.Value.action -eq 'started' -and $repaired.Value.started -and
    $repaired.Value.servicesRepaired -and $calls.repair -eq 1 -and $calls.start -eq 1
) "error=$($repaired.Error) result=$($repaired.Value | ConvertTo-Json -Depth 5 -Compress) calls=$($calls | ConvertTo-Json -Compress)"

# ------------------------------------------------------------- bounded repair
$mutations = [Collections.Generic.List[string]]::new()
$setAuto = { param($Name) $mutations.Add("auto:$Name") }
$startSvc = { param($Name) $mutations.Add("start:$Name") }

$mutations.Clear()
$notElevated = Invoke-Capture {
    Repair-MobileVmwareServices -State (Get-MobileVmwareServiceState -Services $allStopped) -IsElevated { $false } -SetAutomatic $setAuto -StartByName $startSvc
}
Report 'repair refuses without elevation, mutates nothing, and never self-elevates' (
    $notElevated.Error -match 'elevated' -and $mutations.Count -eq 0 -and
    (Get-Content -LiteralPath (Join-Path $packageRoot 'MobileDevelopment.psm1') -Raw -Encoding UTF8) -notmatch '-Verb\s+RunAs'
) "error=$($notElevated.Error) mutations=$($mutations -join ',')"

$mutations.Clear()
$disabled = Invoke-Capture {
    Repair-MobileVmwareServices -State (Get-MobileVmwareServiceState -Services @((New-Svc 'VMAuthdService' 'Stopped' 'Disabled'), $allStopped[1], $allStopped[2])) -IsElevated { $true } -SetAutomatic $setAuto -StartByName $startSvc
}
Report 'repair refuses to override a Disabled service and mutates nothing' (
    $disabled.Error -match 'Disabled' -and $disabled.Error -match 'VMAuthdService' -and $mutations.Count -eq 0
) "error=$($disabled.Error) mutations=$($mutations -join ',')"

$mutations.Clear()
$partial = Invoke-Capture {
    Repair-MobileVmwareServices -State (Get-MobileVmwareServiceState -Services @($allRunning[0], (New-Svc 'VMnetDHCP' 'Stopped' 'Manual'), (New-Svc 'VMware NAT Service' 'Stopped' 'Automatic'), (New-Svc 'Unrelated' 'Stopped' 'Manual'))) -IsElevated { $true } -SetAutomatic $setAuto -StartByName $startSvc
}
Report 'repair touches only stopped registry-declared services, Manual becoming Automatic' (
    -not $partial.Error -and
    ($mutations -join ',') -ceq 'auto:VMnetDHCP,start:VMnetDHCP,start:VMware NAT Service'
) "error=$($partial.Error) mutations=$($mutations -join ',')"

# ----------------------------------------------------------- read-only paths
$startText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Start-MobileLab.ps1') -Raw -Encoding UTF8
$gateText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Test-MobileLab.ps1') -Raw -Encoding UTF8
# Inspect invoked commands through the AST, not text: remediation strings
# legitimately quote 'Start-Service ...' for the operator to run.
$mutatingCommands = @('Start-Service', 'Set-Service', 'Restart-Service', 'Stop-Service', 'Repair-MobileVmwareServices', 'sc', 'sc.exe', 'net', 'net.exe', 'Start-Process')
function Get-InvokedCommandNames([Management.Automation.Language.Ast]$Ast) {
    @($Ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
}
function Get-FileAst([string]$Path) {
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
}
$moduleAst = Get-FileAst (Join-Path $packageRoot 'MobileDevelopment.psm1')
$stateAst = @($moduleAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MobileVmwareServiceState' }, $true))
$processAst = @($moduleAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MobileRuntimeProcessMatch' }, $true))
$readOnlyInvocations = @(
    if ($stateAst.Count -eq 1) { Get-InvokedCommandNames $stateAst[0] }
    if ($processAst.Count -eq 1) { Get-InvokedCommandNames $processAst[0] }
    Get-InvokedCommandNames (Get-FileAst (Join-Path $scriptsRoot 'Test-MobileLab.ps1'))
)
$mutatingFound = @($readOnlyInvocations | Where-Object { $_ -in $mutatingCommands } | Sort-Object -Unique)
Report 'read-only gate, runtime process match, and service-state reader invoke no service mutation' (
    $stateAst.Count -eq 1 -and $processAst.Count -eq 1 -and $mutatingFound.Count -eq 0 -and
    $gateText -match 'Get-MobileVmwareServiceState'
) "stateFunction=$($stateAst.Count) processFunction=$($processAst.Count) mutating=$($mutatingFound -join ',')"
Report 'startup captures vmrun output, delegates the decision, and gates repair behind an explicit switch' (
    $startText -match '\[switch\]\$RepairVmwareServices' -and
    $startText -match 'Invoke-MobileLabGuestBringUp' -and
    $startText -match '-RepairServicesAllowed:\$RepairVmwareServices' -and
    $startText -notmatch 'start \$Vmx nogui \| Out-Null' -and
    $startText -notmatch '\$running -contains \$Vmx'
) 'Start-MobileLab.ps1 still hides vmrun output or decides from vmrun list alone.'

function Get-VmwareServiceSnapshot {
    @($required | ForEach-Object {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        if ($svc) { '{0}={1}/{2}' -f $svc.Name, $svc.Status, $svc.StartType } else { "$_=absent" }
    }) -join ','
}
$before = Get-VmwareServiceSnapshot
$liveState = Invoke-Capture { Get-MobileVmwareServiceState }
$hostExe = (Get-Process -Id $PID).Path
$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { $runtimeOutput = @(& $hostExe -NoProfile -File (Join-Path $packageRoot 'mobile.ps1') check runtime ios -Json 2>&1) }
finally { $ErrorActionPreference = $old }
$after = Get-VmwareServiceSnapshot
$runtimeLine = $runtimeOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
$runtimeResult = if ($runtimeLine) { try { $runtimeLine | ConvertFrom-Json } catch { $null } } else { $null }
Report 'live read-only service reader and runtime check leave every VMware service unchanged' (
    -not $liveState.Error -and $before -ceq $after -and $runtimeResult -and
    -not $runtimeResult.startedResources -and $null -ne $runtimeResult.ios.vmwareHostServices
) "before=$before after=$after error=$($liveState.Error) output=$($runtimeOutput -join ' ')"

# ---------------------------------------------------------------- docs truth
$platformSkill = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-platform-standard\SKILL.md') -Raw -Encoding UTF8
$labSkill = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\SKILL.md') -Raw -Encoding UTF8
Report 'Windows usbmuxd guidance accepts both the Apple Devices MSIX and the Apple Mobile Device Service' (
    $platformSkill -match 'Apple Mobile Device Service' -and $platformSkill -match 'AppleDevices' -and
    $platformSkill -notmatch 'There is no Windows \*service\*' -and $platformSkill -match 'usbmux list'
) 'The skill still asserts a single installed form.'
Report 'lab skill documents service diagnosis and the bounded repair switch' (
    $labSkill -match 'VMAuthdService' -and $labSkill -match '-RepairVmwareServices' -and $labSkill -match 'vmrun list'
) 'mobile-device-lab SKILL.md lacks the VMware service runbook.'

if ($failures.Count) {
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
