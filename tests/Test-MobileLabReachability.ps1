#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}
function Read-Json([string]$RelativePath) {
    Get-Content -LiteralPath (Join-Path $repoRoot $RelativePath) -Raw -Encoding UTF8 | ConvertFrom-Json
}

$agents = Read-Json 'registry\agents.json'
$capabilities = Read-Json 'registry\capabilities.json'
$mcps = Read-Json 'registry\mcps.json'
$formats = Read-Json 'registry\plugin-formats.json'
$connectors = Read-Json 'registry\native-connectors.json'
$mobile = @($capabilities.capabilities | Where-Object id -eq 'mobile-device-lab')
$appium = @($mcps.mcpServers | Where-Object id -eq 'appium-mobile')
$packageRoot = Join-Path $repoRoot 'packages\mobile-device-lab'
$syncScriptText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') -Raw -Encoding UTF8
$mcpSmokeText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Invoke-AppiumMcpSmoke.mjs') -Raw -Encoding UTF8
$deepGatePath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Test-MobileLab.ps1'
$deepGateText = Get-Content -LiteralPath $deepGatePath -Raw -Encoding UTF8
$idleProbePath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Test-MobileLabIdle.ps1'
$guestStartText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\start-appium-guest.sh') -Raw -Encoding UTF8
$guestSyncPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Sync-MobileLabGuestScripts.ps1'

Report 'one canonical mobile capability exists' ($mobile.Count -eq 1) "count=$($mobile.Count)"
Report 'one pinned Appium MCP exists' ($appium.Count -eq 1 -and $appium[0].command -eq 'npx' -and 'appium-mcp@1.92.0' -in @($appium[0].args)) 'Expected registry/mcps.json#appium-mobile pinned to appium-mcp@1.92.0.'
Report 'Appium is the reviewed persistent on-demand exception' ('appium-mobile' -in @($connectors.lifecyclePolicy.persistedOnDemandLocalMcpIds)) 'Add only appium-mobile to persistedOnDemandLocalMcpIds.'
Report 'persistent on-demand exceptions participate in every sync scope' (
    $syncScriptText -match '\$scopedCandidateServers\s*\+\s*\$persistentExceptionServers'
) 'Merge reviewed persistent exceptions after scope selection so default audits agree with on-demand deployment.'
Report 'Grok partial-scope sync preserves existing section order' (
    $syncScriptText -match '\$canonicalSectionExists' -and
    $syncScriptText -match 'partial scope must not move an existing section'
) 'Replace existing Grok MCP sections in place so cross-scope audits are idempotent.'

$manifestByHost = @{}
foreach ($formatHost in @($formats.hosts)) { $manifestByHost[[string]$formatHost.id] = [string]$formatHost.manifest }
$mappingByHost = @{}
foreach ($mapping in @($mobile[0].hostMappings)) { $mappingByHost[[string]$mapping.hostId] = $mapping }
$inherits = @{
    'cursor-agent' = 'cursor'
    'opencode-desktop' = 'opencode'
    'antigravity-desktop' = 'antigravity'
    'antigravity-ide' = 'antigravity'
}

foreach ($agent in @($agents.activeAgents | Where-Object status -eq 'active')) {
    $hostId = [string]$agent.id
    $effectiveHost = if ($inherits.ContainsKey($hostId)) { $inherits[$hostId] } else { $hostId }
    $mapping = $mappingByHost[$effectiveHost]
    $format = @($formats.hosts | Where-Object id -eq $effectiveHost | Select-Object -First 1)
    $hasInstructionRoute = $mapping -and ($agent.nativePaths.skillsDir -or ($format.Count -eq 1 -and ($format[0].globalSkillsDir -or $format[0].alsoScannedSkillsDirs)))
    Report "$hostId has discoverable mobile instructions" ([bool]$hasInstructionRoute) "effectiveHost=$effectiveHost mapping=$($mapping.deploymentStatus)"

    $status = if ($mapping) { [string]$mapping.deploymentStatus } else { '' }
    $packageBacked = $status -in @('plugin-owned', 'native-plugin-installed', 'native-local-plugin', 'native-extension-junction')
    $directBacked = $status -match 'mcp'
    $packageManifest = if ($manifestByHost.ContainsKey($effectiveHost)) { $manifestByHost[$effectiveHost] } else { $null }
    $packageRoute = $packageBacked -and $packageManifest -and (Test-Path -LiteralPath (Join-Path $packageRoot $packageManifest))
    $directRoute = $directBacked -and $effectiveHost -in @($appium[0].hosts) -and 'appium-mobile' -in @($connectors.lifecyclePolicy.persistedOnDemandLocalMcpIds)
    Report "$hostId has an Appium MCP activation route" ([bool]($packageRoute -or $directRoute)) "status=$status manifest=$packageManifest direct=$directRoute"
}

foreach ($agent in @($agents.activeAgents | Where-Object status -eq 'unverified')) {
    $declared = [string]$agent.executable
    $resolves = $false
    if ($declared) {
        if ([IO.Path]::IsPathRooted($declared)) { $resolves = Test-Path -LiteralPath $declared }
        else { $resolves = [bool](Get-Command $declared -ErrorAction SilentlyContinue) }
    }
    Report "$($agent.id) is not counted functional without an executable" (-not $resolves) "status=$($agent.status) executable=$declared"
}

foreach ($connectorHost in @($connectors.hosts | Where-Object exposures)) {
    $routes = @($connectorHost.exposures.'plugin-owned') + @($connectorHost.exposures.'native-connector') +
        @($connectorHost.exposures.'shared-gateway') + @($connectorHost.exposures.'local-only')
    Report "$($connectorHost.hostId) classifies exactly one Appium route" (@($routes | Where-Object { $_ -eq 'appium-mobile' }).Count -eq 1) 'Classify appium-mobile exactly once as plugin-owned or local-only.'
}

$fixtureRoot = Join-Path $packageRoot 'fixtures\smoke-app'
$fixtureText = (Get-Content -LiteralPath (Join-Path $fixtureRoot 'app.json') -Raw -Encoding UTF8) +
    (Get-Content -LiteralPath (Join-Path $fixtureRoot 'package.json') -Raw -Encoding UTF8)
Report 'synthetic fixture is local-only and has no durable cloud identity' (
    (Test-Path -LiteralPath (Join-Path $fixtureRoot 'App.js')) -and
    (Test-Path -LiteralPath (Join-Path $fixtureRoot '.maestro\smoke.yaml')) -and
    -not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'eas.json')) -and
    $fixtureText -notmatch 'projectId|owner|updates\.url|store'
) 'Fixture must not declare EAS project IDs, owners, store metadata, or cloud update URLs.'
Report 'cross-platform MCP interactions bind to explicit concurrent session IDs' (
    $mcpSmokeText -match 'exerciseSession\("android",\s*report\.android\.sessionId\)' -and
    $mcpSmokeText -match 'exerciseSession\("ios",\s*report\.ios\.sessionId\)' -and
    $mcpSmokeText -match 'appium_get_page_source",\s*\{ sessionId \}'
) 'Do not rely on Appium MCP active-session state after Android and iOS coexist.'
Report 'deep smoke cleans up every MCP-created session' (
    $mcpSmokeText -match 'cleanupCreatedSessions\(\)' -and
    $mcpSmokeText -match 'report\.sessionsCleaned' -and
    $mcpSmokeText -match 'action:\s*"delete",\s*sessionId'
) 'Delete Android and iOS sessions after concurrent evidence so WDA and emulator state do not leak between runs.'
Report 'deep smoke pins both sessions to enumerated virtual-device IDs' (
    $mcpSmokeText -match '"appium:udid":\s*args\["android-udid"\]' -and
    $mcpSmokeText -match '"appium:udid":\s*args\["ios-udid"\]' -and
    $deepGateText -match '--android-udid\s+\$script:Facts\[''androidDeviceId''\]' -and
    $deepGateText -match '--ios-udid\s+\$script:Facts\[''iosDeviceId''\]'
) 'Pass the enumerated emulator and Simulator UDIDs into Appium so a physical device cannot be selected.'

$idleProbeBlocksBusy = $false
$idleProbeAcceptsIdle = $false
$idleProbeIsBeforeBuilder = $false
if (Test-Path -LiteralPath $idleProbePath) {
    $fixtureRootForProbe = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-mobile-idle-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRootForProbe -Force | Out-Null
    try {
        $busySnapshot = Join-Path $fixtureRootForProbe 'busy.json'
        [IO.File]::WriteAllText($busySnapshot, (@{
                    hostProcesses = @('30164 ssh.exe macvm maestro --device 371BE9E8-0ED2-415A-AF85-F2BF9D6F6194 test release.yaml')
                    guestProcesses = @()
                    appiumSessions = @()
                } | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
        $busyOutput = @(& $idleProbePath -SnapshotPath $busySnapshot -Json 2>&1)
        $busyExit = $LASTEXITCODE
        $busyLine = $busyOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
        $busyResult = if ($busyLine) { $busyLine | ConvertFrom-Json } else { $null }
        $idleProbeBlocksBusy = ($busyExit -ne 0 -and $busyResult -and -not $busyResult.idle -and
            (@($busyResult.conflicts | ForEach-Object { $_.Kind }) -join ' ') -match 'Maestro')

        $idleSnapshot = Join-Path $fixtureRootForProbe 'idle.json'
        [IO.File]::WriteAllText($idleSnapshot, (@{
                    hostProcesses = @()
                    guestProcesses = @()
                    appiumSessions = @()
                } | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
        $idleOutput = @(& $idleProbePath -SnapshotPath $idleSnapshot -Json 2>&1)
        $idleExit = $LASTEXITCODE
        $idleLine = $idleOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
        $idleResult = if ($idleLine) { $idleLine | ConvertFrom-Json } else { $null }
        $idleProbeAcceptsIdle = ($idleExit -eq 0 -and $idleResult -and $idleResult.idle)
    }
    finally {
        Remove-Item -LiteralPath $fixtureRootForProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
    $probeIndex = $deepGateText.IndexOf('Test-MobileLabIdle.ps1', [StringComparison]::Ordinal)
    $builderIndex = $deepGateText.IndexOf('Build-MobileLabSmokeFixture.ps1', [StringComparison]::Ordinal)
    $idleProbeIsBeforeBuilder = ($probeIndex -ge 0 -and $builderIndex -gt $probeIndex)
}

$guestSyncStagesLf = $false
$guestSyncPrecedesReadiness = $false
if (Test-Path -LiteralPath $guestSyncPath) {
    $stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-mobile-guest-sync-' + [guid]::NewGuid().ToString('N'))
    try {
        $syncOutput = @(& $guestSyncPath -StageOnly -StagePath $stageRoot -Json 2>&1)
        $syncExit = $LASTEXITCODE
        $syncLine = $syncOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
        $syncResult = if ($syncLine) { $syncLine | ConvertFrom-Json } else { $null }
        $stagedScripts = @(Get-ChildItem -LiteralPath $stageRoot -Filter '*.sh' -File -ErrorAction SilentlyContinue)
        $containsCarriageReturn = @($stagedScripts | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains("`r") }).Count -gt 0
        $guestSyncStagesLf = ($syncExit -eq 0 -and $syncResult -and $syncResult.ok -and
            $stagedScripts.Count -ge 4 -and -not $containsCarriageReturn)
    }
    finally {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $startText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Start-MobileLab.ps1') -Raw -Encoding UTF8
    $syncIndex = $startText.IndexOf('Sync-MobileLabGuestScripts.ps1', [StringComparison]::Ordinal)
    $statusIndex = $startText.IndexOf('/status', [StringComparison]::Ordinal)
    $guestSyncPrecedesReadiness = ($syncIndex -ge 0 -and $statusIndex -gt $syncIndex)
}
Report 'guest helper sync stages every shell script as LF-only UTF-8' $guestSyncStagesLf 'Stage all versioned guest helpers without CR bytes before scp.'
Report 'one-command startup syncs guest helpers before Appium readiness' $guestSyncPrecedesReadiness 'Invoke Sync-MobileLabGuestScripts.ps1 after SSH and before polling Appium.'
Report 'guest Appium launchd restart retries the post-bootout bootstrap race' (
    $guestStartText -match 'for\s+attempt\s+in' -and
    $guestStartText -match 'launchctl\s+bootstrap' -and
    $guestStartText -match 'sleep\s+1'
) 'Retry launchctl bootstrap after bootout; macOS can transiently return error 5 while teardown finishes.'
Report 'startup machine result identifies only virtual devices' (
    $startText -match 'androidDeviceId\s*=\s*\$script:Facts\.androidDeviceId' -and
    $startText -match 'iosDeviceId\s*=\s*\$script:Facts\.iosDeviceId' -and
    $startText -match '\^emulator-\\d\+\\s\+device\$'
) 'Emit both virtual-device IDs and exclude physical adb devices during startup.'
Report 'startup guest-IP polling cannot outlive its declared timeout' (
    $startText -notmatch 'getGuestIPAddress\s+\$Vmx\s+-wait' -and
    $startText -match '\[int\]\$TimeoutMinutes\s*=\s*15'
) 'Use non-blocking vmrun probes inside Wait-Until and allow the measured cold guest recovery window.'
Report 'startup guest SSH overrides retain the stable host-key alias' (
    $startText -match '-o\s+"HostName=\$script:guestIp"\s+-o\s+"HostKeyAlias=macvm"\s+-o\s+"LogLevel=ERROR"' -and
    $startText -notmatch '-o\s+"HostName=\$script:guestIp"\s+-o\s+ConnectTimeout'
) 'Pair every dynamic HostName override with HostKeyAlias=macvm and suppress warning-level SSH diagnostics so PowerShell 5.1 does not promote them to terminating errors.'
Report 'startup handles a null booted-Simulator probe explicitly' (
    $startText -match '\[string\]::IsNullOrWhiteSpace\(\$bootedText\)' -and
    $startText -notmatch "\$bootedText\s*=\s*'iPhone 17 \(Booted\)'"
) 'Do not apply -notmatch or Trim to a null native-command result, and never synthesize a Booted identity.'
Report 'startup retries the idempotent Simulator boot request while shutdown' (
    $startText -match '\$script:lastSimulatorBootEvidence' -and
    $startText -match 'xcrun simctl list devices available -j' -and
    $startText -match 'xcrun simctl boot \$targetSimulatorUdid'
) 'Resolve the exact iPhone 17 Simulator UDID from JSON and retry that quote-free identifier inside the bounded readiness loop.'
Report 'deep smoke busy guard demonstrably rejects an active Maestro run' $idleProbeBlocksBusy 'The idle probe must exit non-zero and report the competing command.'
Report 'deep smoke busy guard accepts a synthetic idle snapshot' $idleProbeAcceptsIdle 'The same probe must exit zero when no conflicting operation or Appium session exists.'
Report 'deep smoke checks exclusivity before building or installing the fixture' $idleProbeIsBeforeBuilder 'Invoke Test-MobileLabIdle.ps1 before Build-MobileLabSmokeFixture.ps1.'
if (Test-Path -LiteralPath $idleProbePath) {
    $idleProbeText = Get-Content -LiteralPath $idleProbePath -Raw -Encoding UTF8
    Report 'Appium 3 session discovery uses the guarded current endpoint' (
        $idleProbeText -match '/appium/sessions' -and
        $guestStartText -match '\*:session_discovery'
    ) 'Use GET /appium/sessions and enable only the Appium 3 session_discovery feature on the private guest service.'
}

if ($failures.Count) {
    Write-Host "`n$($failures.Count) of $reported mobile reachability checks failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll $reported mobile reachability checks passed." -ForegroundColor Green
