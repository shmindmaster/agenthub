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
function Resolve-LivePath([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    $registryProfile = [string]$agents.userProfile
    if ($PathValue -eq '~') { return $env:USERPROFILE }
    if ($PathValue.StartsWith('~/') -or $PathValue.StartsWith('~\')) {
        return Join-Path $env:USERPROFILE $PathValue.Substring(2)
    }
    if ($registryProfile -and $PathValue.StartsWith($registryProfile, [StringComparison]::OrdinalIgnoreCase)) {
        return $env:USERPROFILE + $PathValue.Substring($registryProfile.Length)
    }
    return $PathValue
}

$agents = Read-Json 'registry\agents.json'
$capabilities = Read-Json 'registry\capabilities.json'
$mcps = Read-Json 'registry\mcps.json'
$formats = Read-Json 'registry\plugin-formats.json'
$connectors = Read-Json 'registry\native-connectors.json'
$mobile = @($capabilities.capabilities | Where-Object id -eq 'mobile-device-lab')
$marketplace = Read-Json '.agents\plugins\marketplace.json'
$appium = @($mcps.mcpServers | Where-Object id -eq 'appium-mobile')
$packageRoot = Join-Path $repoRoot 'packages\mobile-device-lab'
$syncScriptText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') -Raw -Encoding UTF8
$mcpSmokeText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Invoke-AppiumMcpSmoke.mjs') -Raw -Encoding UTF8
$deepGatePath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Test-MobileLab.ps1'
$deepGateText = Get-Content -LiteralPath $deepGatePath -Raw -Encoding UTF8
$idleProbePath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Test-MobileLabIdle.ps1'
$idleProbeText = Get-Content -LiteralPath $idleProbePath -Raw -Encoding UTF8
$leaseToolPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Enter-MobileLabLease.ps1'
$leaseToolText = Get-Content -LiteralPath $leaseToolPath -Raw -Encoding UTF8
$mobileSkillText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\SKILL.md') -Raw -Encoding UTF8
$guestStartText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\start-appium-guest.sh') -Raw -Encoding UTF8
$guestWdaCleanupPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\cleanup-wda-guest.sh'
$guestWdaCleanupText = Get-Content -LiteralPath $guestWdaCleanupPath -Raw -Encoding UTF8
$guestSyncPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Sync-MobileLabGuestScripts.ps1'
$expectedPluginVersion = [string](Read-Json 'packages\mobile-device-lab\plugin.json').version
$liveDriftPath = Join-Path $env:LOCALAPPDATA 'AgentHub\sync\latest-drift.json'
$liveDrift = if (Test-Path -LiteralPath $liveDriftPath) { Get-Content -LiteralPath $liveDriftPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

Report 'one canonical mobile capability exists' ($mobile.Count -eq 1) "count=$($mobile.Count)"
# The pin comes from the registry, not a literal. Hardcoding the version
# made this fail on a correct bump that had been protocol-verified, which
# trains people to edit the assertion rather than read it.
$pinnedAppiumArg = @($appium[0].args | Where-Object { $_ -like 'appium-mcp@*' })
Report 'one pinned Appium MCP exists' ($appium.Count -eq 1 -and $appium[0].command -eq 'npx' -and $pinnedAppiumArg.Count -eq 1) `
    "Expected exactly one npx-invoked appium-mcp@<version> arg in registry/mcps.json#appium-mobile; found $($pinnedAppiumArg.Count)."
Report 'Windows stdio MCP wrap exists' ($syncScriptText -match 'function Resolve-WindowsHiddenStdioEntry' -and $syncScriptText -match 'Hide-Stdio.exe') 'Emit stdio MCP through Hide-Stdio.exe on Windows so npx/cmd wrappers do not steal focus.'
# appium-mobile must NOT be persisted. A stdio MCP server named in a host
# config is started BY THE HOST at session start -- there is no lazy path --
# so persisting it means a node process per session whether or not any mobile
# work happens. Measured after a clean reboot on 2026-08-20: 15 processes,
# 2,024 MB, still climbing as sessions opened, with no mobile work running.
Report 'Appium is not persisted into host configs' ('appium-mobile' -notin @($connectors.lifecyclePolicy.persistedOnDemandLocalMcpIds)) `
    'appium-mobile is back in persistedOnDemandLocalMcpIds; that re-creates the per-session process cost measured at 2,024 MB.'

# The capability must still be REACHABLE, or the saving above is just a
# removal. An explicit, documented enable route is what makes it on-demand
# rather than gone.
$appiumRoute = [string]$connectors.lifecyclePolicy.appiumActivationRoute
Report 'Appium has a documented enable-on-demand route' ($appiumRoute -match 'plugin (enable|add)' -and $appiumRoute -match 'mobile-device-lab') `
    'lifecyclePolicy.appiumActivationRoute must name the concrete command that turns the capability on, or removing it from the default set just loses the capability.'
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
    # The mobile-device-lab SKILL states both platforms are reached through the
    # appium-mcp server, so on a host with no such route it is instructions for
    # tooling that host cannot invoke. Its hostMappings were narrowed to claude
    # and codex on 2026-08-19 to match registry/mcps.json. Note this covers only
    # mobile-device-lab; mobile-platform-standard is owned by portfolio-engineering
    # and stays fleet-wide, because writing Expo/EAS code needs no MCP.
    $inMobileScope = $effectiveHost -in @($appium[0].hosts)
    if ($inMobileScope) {
        Report "$hostId has discoverable mobile instructions" ([bool]$hasInstructionRoute) "effectiveHost=$effectiveHost mapping=$($mapping.deploymentStatus)"
    } else {
        Report "$hostId is outside mobile scope and carries no lab instructions" (-not $hasInstructionRoute) "effectiveHost=$effectiveHost mapping=$($mapping.deploymentStatus)"
    }

    $status = if ($mapping) { [string]$mapping.deploymentStatus } else { '' }
    $packageBacked = $status -in @('plugin-owned', 'native-plugin-installed', 'native-local-plugin', 'native-extension-junction')
    $directBacked = $status -match 'mcp'
    $packageManifest = if ($manifestByHost.ContainsKey($effectiveHost)) { $manifestByHost[$effectiveHost] } else { $null }
    $packageRoute = $packageBacked -and $packageManifest -and (Test-Path -LiteralPath (Join-Path $packageRoot $packageManifest))
    $directRoute = $directBacked -and $effectiveHost -in @($appium[0].hosts) -and 'appium-mobile' -in @($connectors.lifecyclePolicy.persistedOnDemandLocalMcpIds)
    # Appium's host list was narrowed to claude and codex on 2026-08-19 (the
    # reason is recorded in registry/mcps.json -> appium-mobile
    # localProcessPolicy.note). Fleet-wide registration cost ~93 MB of node per
    # host at session start for a lab most hosts never drive. Assert both
    # directions: in scope the route must exist, out of scope the direct MCP
    # route must be absent, so the narrowing is enforced and not merely tolerated.
    if ($inMobileScope) {
        # The route must EXIST (the capability can be turned on) while being absent
        # from the running default. Asserting only presence would fail the new design;
        # asserting only absence would let the capability quietly disappear.
        # A route is a way to TURN IT ON, not evidence it is on. After gating, the
        # route is the marketplace entry the enable command resolves against -- that
        # is what makes the capability recoverable rather than deleted.
        $marketplaceRoute = (@($marketplace.plugins | Where-Object { $_.name -eq 'mobile-device-lab' }).Count -eq 1)
        Report "$hostId can activate Appium on demand" ([bool]($packageRoute -or $directRoute -or $marketplaceRoute)) `
            "status=$status manifest=$packageManifest direct=$directRoute marketplace=$marketplaceRoute -- an in-scope host must retain a way to enable the capability."
    } else {
        Report "$hostId is outside Appium scope and carries no direct MCP route" (-not $directRoute) "status=$status direct=$directRoute"
    }

    $effectiveAgent = @($agents.activeAgents | Where-Object id -eq $effectiveHost | Select-Object -First 1)
    $liveInstruction = $false
    $liveMcp = $false
    if ($effectiveHost -eq 'claude' -and $packageBacked) {
        $installedPath = Join-Path $env:USERPROFILE '.claude\plugins\installed_plugins.json'
        $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
        if ((Test-Path -LiteralPath $installedPath) -and (Test-Path -LiteralPath $settingsPath)) {
            $installed = Get-Content -LiteralPath $installedPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $pluginEntry = @($installed.plugins.'mobile-device-lab@agenthub' | Select-Object -Last 1)
            $enabledProperty = $settings.enabledPlugins.PSObject.Properties['mobile-device-lab@agenthub']
            if ($pluginEntry.Count -eq 1 -and $pluginEntry[0].version -eq $expectedPluginVersion -and $enabledProperty -and [bool]$enabledProperty.Value) {
                $installPath = [string]$pluginEntry[0].installPath
                $liveInstruction = Test-Path -LiteralPath (Join-Path $installPath 'skills\mobile-device-lab\SKILL.md')
                $liveMcp = Test-Path -LiteralPath (Join-Path $installPath '.mcp.json')
            }
        }
    }
    else {
        $skillRoots = [Collections.Generic.List[string]]::new()
        if ($effectiveAgent.Count -eq 1) {
            $declaredSkillRoot = if ($effectiveAgent[0].nativePaths.sharedSkillsDir) { [string]$effectiveAgent[0].nativePaths.sharedSkillsDir } else { [string]$effectiveAgent[0].nativePaths.skillsDir }
            if ($declaredSkillRoot) { $skillRoots.Add((Resolve-LivePath $declaredSkillRoot)) }
        }
        if ($format.Count -eq 1) {
            foreach ($formatRoot in @([string]$format[0].globalSkillsDir) + @($format[0].alsoScannedSkillsDirs | ForEach-Object { [string]$_ })) {
                $resolvedRoot = Resolve-LivePath $formatRoot
                if ($resolvedRoot -and $resolvedRoot -notin $skillRoots) { $skillRoots.Add($resolvedRoot) }
            }
        }
        # Track WHICH root matched, not just whether one did. The shared-dir
        # exception below has to know the difference between a private copy that
        # survived prune and the shared ~/.agents/skills directory that several
        # hosts read by design.
        $matchedRoots = @($skillRoots | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'mobile-device-lab\SKILL.md') })
        $liveInstruction = $matchedRoots.Count -gt 0
        # What prune can actually control is a host's OWN skills directory. Every
        # other root in $skillRoots belongs to some other host and is merely also
        # scanned -- ~/.agents/skills by codex/gemini/warp, ~/.claude/skills by
        # vscode-insiders/copilot/warp. Withdrawing the skill from those would
        # withdraw it from the in-scope host that owns them, which the directory
        # layout makes impossible. Keying this on one hardcoded shared path missed
        # the ~/.claude/skills readers and reported them as retaining a private copy.
        $ownSkillsRoot = if ($effectiveAgent.Count -eq 1 -and $effectiveAgent[0].nativePaths.skillsDir) {
            Resolve-LivePath ([string]$effectiveAgent[0].nativePaths.skillsDir)
        } else { $null }
        $privateCopy = [bool]($ownSkillsRoot -and @($matchedRoots | Where-Object { $_ -eq $ownSkillsRoot }).Count -gt 0)
        $onlyViaSharedDir = $liveInstruction -and -not $privateCopy

        $driftHost = @(if ($liveDrift) { $liveDrift.hosts | Where-Object host -eq $effectiveHost | Select-Object -First 1 })
        if ($driftHost.Count -eq 1) {
            foreach ($mcpEntry in @($driftHost[0].mcp)) {
                $mcpPath = [string]$mcpEntry.path
                if ($mcpEntry.status -eq 'unchanged' -and $mcpPath -and (Test-Path -LiteralPath $mcpPath) -and
                    (Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8) -match 'appium-mobile') {
                    $liveMcp = $true
                    break
                }
            }
        }
    }
    # Out of scope, the private copy must be gone. A host that reads the shared
    # ~/.agents/skills directory is the documented exception: codex, gemini and
    # warp all read it, so the skill cannot be withdrawn from gemini or warp
    # without also withdrawing it from codex, which is in scope. Record that
    # rather than asserting something the directory layout makes impossible.
    # A host reaches the shared dir either by declaring sharedSkillsDir in
    # agents.json OR by listing ~/.agents/skills in alsoScannedSkillsDirs in
    # plugin-formats.json. Checking only the first field reported factory as
    # retaining a private copy when its own directory was correctly pruned
    # and the skill was resolving from the shared dir like codex and gemini.
    $usesSharedSkills = [bool]($effectiveAgent.Count -eq 1 -and $effectiveAgent[0].nativePaths.sharedSkillsDir) -or $onlyViaSharedDir
    if ($inMobileScope) {
        Report "$hostId live profile carries mobile instructions" $liveInstruction `
            'Instructions are cheap and stay deployed; only the MCP server is gated, so the skill must remain readable.'
    } elseif ($usesSharedSkills) {
        Report "$hostId sees mobile instructions only via the shared skills dir" $liveInstruction 'Known limitation: the shared ~/.agents/skills directory is read by in-scope and out-of-scope hosts alike.'
    } else {
        Report "$hostId live profile carries no private mobile lab copy" (-not $privateCopy) `
            "An out-of-scope host must not keep a copy in its OWN skills directory ($ownSkillsRoot) after prune; roots owned by other hosts are the documented shared-directory limitation."
    }
    if ($inMobileScope) {
        # Gated by default. The skill tells the agent how to enable it when mobile
        # work actually starts.
        Report "$hostId live profile does not eagerly expose Appium MCP" (-not $liveMcp) `
            'An in-scope host is carrying the Appium server in its live config again, which spawns a node process every session.'
    } else {
        Report "$hostId live profile has no Appium MCP" (-not $liveMcp) 'A host outside the narrowed Appium scope must not carry the server in its live config; prune should have removed it.'
    }
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

$appiumScopeHosts = @(($mcps.mcpServers | Where-Object { $_.id -eq 'appium-mobile' }).hosts)
Report 'the registry declares an Appium host scope to test against' ($appiumScopeHosts.Count -gt 0) `
    'appium-mobile has no hosts in registry/mcps.json, so every check below would be vacuous.'

foreach ($connectorHost in @($connectors.hosts | Where-Object exposures)) {
    $routes = @($connectorHost.exposures.'plugin-owned') + @($connectorHost.exposures.'native-connector') +
        @($connectorHost.exposures.'shared-gateway') + @($connectorHost.exposures.'local-only')
    # Scope-aware, matching the narrowing recorded in registry/mcps.json.
    # This assertion originally required EVERY host to classify an Appium
    # route, which was right while appium-mobile named all 18 hosts. After
    # the narrowing to claude+codex, demanding a route everywhere would
    # force the fleet-wide exposure back into native-connectors.json and
    # re-create the per-host process cost the narrowing removed. Assert the
    # invariant in BOTH directions instead: present in scope, absent out of
    # scope -- an assertion that only checks presence cannot detect a
    # silent re-fan-out.
    $appiumRoutes = @($routes | Where-Object { $_ -eq 'appium-mobile' }).Count
    if ($connectorHost.hostId -in $appiumScopeHosts) {
        Report "$($connectorHost.hostId) classifies exactly one Appium route" ($appiumRoutes -eq 1) `
            "in-scope host classified appium-mobile $appiumRoutes time(s); expected exactly one."
    } else {
        Report "$($connectorHost.hostId) classifies no Appium route (out of scope)" ($appiumRoutes -eq 0) `
            "host is outside appium-mobile hosts in registry/mcps.json but still carries $appiumRoutes exposure row(s); this is the fleet-wide fan-out returning."
    }
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
$idleProbeBlocksLease = $false
$idleProbeAcceptsOwnedLease = $false
$leaseRejectsContender = $false
$leaseReleasesCleanly = $false
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
                    labLease = $false
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
                    labLease = $false
                } | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
        $idleOutput = @(& $idleProbePath -SnapshotPath $idleSnapshot -Json 2>&1)
        $idleExit = $LASTEXITCODE
        $idleLine = $idleOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
        $idleResult = if ($idleLine) { $idleLine | ConvertFrom-Json } else { $null }
        $idleProbeAcceptsIdle = ($idleExit -eq 0 -and $idleResult -and $idleResult.idle)

        $leaseOutput = @(& $leaseToolPath -Action Acquire -TimeoutMinutes 2 -Json 2>&1)
        $leaseExit = $LASTEXITCODE
        $leaseLine = $leaseOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
        $leaseResult = if ($leaseLine) { $leaseLine | ConvertFrom-Json } else { $null }
        if ($leaseExit -eq 0 -and $leaseResult -and $leaseResult.ok) {
            try {
                $blockedOutput = @(& $idleProbePath -LeaseOnly -Json 2>&1)
                $blockedExit = $LASTEXITCODE
                $blockedLine = $blockedOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
                $blockedResult = if ($blockedLine) { $blockedLine | ConvertFrom-Json } else { $null }
                $idleProbeBlocksLease = ($blockedExit -ne 0 -and $blockedResult -and -not $blockedResult.idle -and
                    (@($blockedResult.conflicts | ForEach-Object { $_.Kind }) -contains 'mobile-lab foreground lease'))

                $ownedOutput = @(& $idleProbePath -LeaseOnly -LeaseId ([string]$leaseResult.leaseId) -Json 2>&1)
                $ownedExit = $LASTEXITCODE
                $ownedLine = $ownedOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
                $ownedResult = if ($ownedLine) { $ownedLine | ConvertFrom-Json } else { $null }
                $idleProbeAcceptsOwnedLease = ($ownedExit -eq 0 -and $ownedResult -and $ownedResult.idle)

                $contenderOutput = @(& $leaseToolPath -Action Acquire -TimeoutMinutes 2 -Json 2>&1)
                $contenderExit = $LASTEXITCODE
                $contenderLine = $contenderOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
                $contenderResult = if ($contenderLine) { $contenderLine | ConvertFrom-Json } else { $null }
                $leaseRejectsContender = ($contenderExit -ne 0 -and $contenderResult -and -not $contenderResult.ok -and $contenderResult.state -eq 'busy')
            }
            finally {
                $releaseOutput = @(& $leaseToolPath -Action Release -LeaseId ([string]$leaseResult.leaseId) -Json 2>&1)
                $releaseExit = $LASTEXITCODE
                $releaseLine = $releaseOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
                $releaseResult = if ($releaseLine) { $releaseLine | ConvertFrom-Json } else { $null }
                if ($releaseExit -eq 0 -and $releaseResult -and $releaseResult.ok) {
                    $afterOutput = @(& $idleProbePath -LeaseOnly -Json 2>&1)
                    $afterExit = $LASTEXITCODE
                    $afterLine = $afterOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
                    $afterResult = if ($afterLine) { $afterLine | ConvertFrom-Json } else { $null }
                    $leaseReleasesCleanly = ($afterExit -eq 0 -and $afterResult -and $afterResult.idle)
                }
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $fixtureRootForProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
    $probeIndex = $deepGateText.IndexOf('Test-MobileLabIdle.ps1', [StringComparison]::Ordinal)
    $builderIndex = $deepGateText.IndexOf('Build-MobileLabSmokeFixture.ps1', [StringComparison]::Ordinal)
    $idleProbeIsBeforeBuilder = ($probeIndex -ge 0 -and $builderIndex -gt $probeIndex)
}

$guestSyncStagesLf = $false
$guestSyncStagesInstaller = $false
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
        $installerPath = Join-Path $stageRoot 'agenthub-install.sh'
        $guestSyncStagesInstaller = ((Test-Path -LiteralPath $installerPath) -and
            -not [IO.File]::ReadAllText($installerPath).Contains("`r") -and
            [IO.File]::ReadAllText($installerPath).Contains('AGENTHUB_GUEST_SYNC'))
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
Report 'guest helper sync stages its installer instead of passing multiline shell through ssh arguments' $guestSyncStagesInstaller 'Generate agenthub-install.sh as LF-only UTF-8 and execute that uploaded file.'
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
Report 'startup and deep validation enforce Android API 36' (
    $startText -match 'Get-Api36EmulatorIds' -and
    $startText -match 'ro\.build\.version\.sdk' -and
    $startText -match "Trim\(\) -eq '36'" -and
    $deepGateText -match "Where-Object Sdk -eq '36'"
) 'A different emulator API level must not satisfy readiness merely because adb reports it attached.'
Report 'startup guest-IP polling cannot outlive its declared timeout' (
    $startText -notmatch 'getGuestIPAddress\s+\$Vmx\s+-wait' -and
    $startText -match '\[int\]\$TimeoutMinutes\s*=\s*15'
) 'Use non-blocking vmrun probes inside Wait-Until and allow the measured cold guest recovery window.'
Report 'startup guest SSH overrides retain the stable host-key alias' (
    $startText -match '-o\s+"HostName=\$script:guestIp"\s+-o\s+"HostKeyAlias=macvm"\s+-o\s+"LogLevel=ERROR"' -and
    $startText -notmatch '-o\s+"HostName=\$script:guestIp"\s+-o\s+ConnectTimeout'
) 'Pair every dynamic HostName override with HostKeyAlias=macvm and suppress warning-level SSH diagnostics so PowerShell 5.1 does not promote them to terminating errors.'
Report 'startup resolves the exact configured Simulator and runtime' (
    $startText -match 'xcrun simctl list devices available -j' -and
    $startText -match 'iOS-26-5\$' -and
    $startText -match "Where-Object name -eq 'iPhone 17'" -and
    $startText -match '\$targetSimulatorUdid'
) 'Resolve iPhone 17 only from the iOS 26.5 inventory bucket and verify its explicit UDID is booted.'
Report 'startup retries the idempotent Simulator boot request while shutdown' (
    $startText -match '\$script:lastSimulatorBootEvidence' -and
    $startText -match 'xcrun simctl list devices available -j' -and
    $startText -match 'xcrun simctl boot \$targetSimulatorUdid'
) 'Resolve the exact iPhone 17 Simulator UDID from JSON and retry that quote-free identifier inside the bounded readiness loop.'
Report 'deep smoke busy guard demonstrably rejects an active Maestro run' $idleProbeBlocksBusy 'The idle probe must exit non-zero and report the competing command.'
Report 'deep smoke busy guard accepts a synthetic idle snapshot' $idleProbeAcceptsIdle 'The same probe must exit zero when no conflicting operation or Appium session exists.'
Report 'deep smoke busy guard demonstrably rejects an active foreground lease' $idleProbeBlocksLease 'The idle probe must fail closed while another AgentHub mobile run owns the named lease.'
Report 'deep smoke checks exclusivity before building or installing the fixture' $idleProbeIsBeforeBuilder 'Invoke Test-MobileLabIdle.ps1 before Build-MobileLabSmokeFixture.ps1.'
Report 'cross-process foreground lease blocks an independent idle probe' $idleProbeBlocksLease 'Hold the named mutex in another process and require Test-MobileLabIdle.ps1 -LeaseOnly to reject it.'
Report 'lease owner can preflight without ignoring another owner' $idleProbeAcceptsOwnedLease 'Accept only the random live LeaseId returned by Enter-MobileLabLease.ps1.'
Report 'cross-process foreground lease rejects a competing acquisition' $leaseRejectsContender 'A second product or Deep task must not acquire the machine-wide mutex.'
Report 'cross-process foreground lease releases cleanly' $leaseReleasesCleanly 'Release the holder in finally and prove a fresh probe can acquire the mutex.'
Report 'product mutation guidance requires holding the shared lease' (
    $leaseToolText -match 'Global\\AgentHub\.MobileDeviceLab\.ForegroundMutation' -and
    $mobileSkillText -match '-Action Acquire' -and
    $mobileSkillText -match '-Action Release' -and
    $mobileSkillText -match 'finally'
) 'Product tasks must hold the same lease for their full mutation window, not merely run a point-in-time probe.'
Report 'deep smoke holds a cross-process foreground lease and rechecks immediately before launch' (
    $deepGateText -match 'Global\\AgentHub\.MobileDeviceLab\.ForegroundMutation' -and
    $deepGateText -match 'final pre-launch exclusivity check' -and
    $deepGateText -match '-IgnoreLabLease' -and
    $idleProbeText -match 'mobile-lab foreground lease'
) 'Hold one named lease across build/install/interaction and re-enumerate external activity immediately before Appium can foreground the fixture.'
Report 'deep validation guest-IP discovery cannot block indefinitely' (
    $deepGateText -notmatch 'getGuestIPAddress\s+\$vmx\s+-wait'
) 'Use a non-waiting vmrun probe after the running-VM gate.'
Report 'deep smoke retires only its Appium-owned WDA runner after MCP cleanup' (
    $deepGateText -match 'cleanup-wda-guest\.sh' -and
    $deepGateText.IndexOf('cleanup-wda-guest.sh', [StringComparison]::Ordinal) -gt $deepGateText.IndexOf('mcpSessionsCleaned', [StringComparison]::Ordinal) -and
    $guestWdaCleanupText -match 'WebDriverAgent\.xcodeproj' -and
    $guestWdaCleanupText -match 'destination id=\$udid' -and
    $guestWdaCleanupText -match 'appium server' -and
    $guestWdaCleanupText -notmatch 'pkill|killall'
) 'After Appium session deletion, stop only WDA xcodebuild children of the lab Appium server for the explicit Simulator UDID.'
Report 'deep smoke cannot pass when any MCP-created session cleanup fails' (
    $mcpSmokeText -match 'if \(!report\.sessionsCleaned\)' -and
    $deepGateText -match '\$mcpResult\.sessionsCleaned' -and
    $deepGateText -match '/appium/sessions' -and
    $deepGateText -match 'skipped because one or more Appium sessions remain active or session discovery failed'
) 'Treat cleanup errors as a failed smoke and never terminate WDA while an Appium session remains active.'
Report 'product-neutral guest sync requires the caller to select its repository and destination' (
    (Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Sync-RepoToGuest.ps1') -Raw -Encoding UTF8) -notmatch 'shmindmaster\\rexa|shmindmaster/rexa' -and
    (Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Sync-RepoToGuest.ps1') -Raw -Encoding UTF8) -match '\[Parameter\(Mandatory\)\]\[string\]\s+\$RepoPath'
) 'Never default a shared infrastructure helper to a product repository or guest path.'
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
