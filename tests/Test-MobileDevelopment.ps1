#Requires -Version 5.1
<#
Behavior tests for the canonical mobile-development contract.

These checks are deliberately local and non-mutating. They do not start adb,
an emulator, VMware, the guest, Appium, Metro, or an external service. The
live cross-platform synthetic smoke remains a separate Task 4 gate.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packageRoot = Join-Path $repoRoot 'packages\mobile-development'
$entrypoint = Join-Path $packageRoot 'mobile.ps1'
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

function Test-Sequence([object[]]$Actual, [object[]]$Expected) {
    (@($Actual) -join "`n") -ceq (@($Expected) -join "`n")
}

function Test-ReadableSkillTree([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container) -or
        -not (Test-Path -LiteralPath $Destination -PathType Container)) { return $false }
    try {
        $sourceFiles = @(
            Get-ChildItem -LiteralPath $Source -Recurse -File -Force |
                ForEach-Object { $_.FullName.Substring($Source.TrimEnd('\').Length + 1).Replace('\','/') } |
                Sort-Object
        )
        $destinationFiles = @(
            Get-ChildItem -LiteralPath $Destination -Recurse -File -Force |
                ForEach-Object { $_.FullName.Substring($Destination.TrimEnd('\').Length + 1).Replace('\','/') } |
                Sort-Object
        )
        if (-not (Test-Sequence $sourceFiles $destinationFiles)) { return $false }
        foreach ($relative in $sourceFiles) {
            $sourcePath = Join-Path $Source ($relative -replace '/', '\')
            $destinationPath = Join-Path $Destination ($relative -replace '/', '\')
            if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash) { return $false }
        }
        return $true
    } catch { return $false }
}

function Invoke-MobileJson([string[]]$Arguments) {
    $hostExe = (Get-Process -Id $PID).Path
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $hostExe -NoProfile -File $entrypoint @Arguments -Json 2>&1); $exit = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    $line = $output | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
    $parsed = $null
    if ($line) { try { $parsed = $line | ConvertFrom-Json } catch { } }
    [pscustomobject]@{ ExitCode = $exit; Output = $output; Result = $parsed }
}

function Get-MobileProcessSnapshot {
    @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.Name -match '^(adb|emulator|emulator64-[A-Za-z]+|qemu-system-.+|vmware-vmx)\.exe$' } |
            ForEach-Object { '{0}:{1}' -f $_.Name, $_.ProcessId } |
            Sort-Object
    )
}

$contract = Read-Json 'registry\mobile-development.json'
$scope = Read-Json 'registry\mobile-scope.json'
$mcps = Read-Json 'registry\mcps.json'
$capabilities = Read-Json 'registry\capabilities.json'
$agents = Read-Json 'registry\agents.json'
$connectors = Read-Json 'registry\native-connectors.json'
$agentMarketplace = Read-Json '.agents\plugins\marketplace.json'
$claudeMarketplace = Read-Json '.claude-plugin\marketplace.json'
$manifest = Read-Json 'packages\mobile-development\plugin.json'
$mcpManifest = Read-Json 'packages\mobile-development\.mcp.json'
$entrypointText = Get-Content -LiteralPath $entrypoint -Raw -Encoding UTF8
$moduleText = Get-Content -LiteralPath (Join-Path $packageRoot 'MobileDevelopment.psm1') -Raw -Encoding UTF8
$startPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Start-MobileLab.ps1'
$gatePath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Test-MobileLab.ps1'
$idlePath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Test-MobileLabIdle.ps1'
$syncGuestPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Sync-MobileLabGuestScripts.ps1'
$mcpSmokePath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Invoke-AppiumMcpSmoke.mjs'
$guestBuildSupervisorPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\run-smoke-fixture-build.sh'
$guestSimulatorBuilderPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\build-expo-simulator.sh'
$guestWdaCleanupPath = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\cleanup-wda-guest.sh'
$labSkillText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\SKILL.md') -Raw -Encoding UTF8
$platformSkillText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-platform-standard\SKILL.md') -Raw -Encoding UTF8
$startText = Get-Content -LiteralPath $startPath -Raw -Encoding UTF8
$gateText = Get-Content -LiteralPath $gatePath -Raw -Encoding UTF8
$idleText = Get-Content -LiteralPath $idlePath -Raw -Encoding UTF8
$syncGuestText = Get-Content -LiteralPath $syncGuestPath -Raw -Encoding UTF8
$mcpSmokeText = Get-Content -LiteralPath $mcpSmokePath -Raw -Encoding UTF8
$guestBuildSupervisorText = Get-Content -LiteralPath $guestBuildSupervisorPath -Raw -Encoding UTF8
$guestSimulatorBuilderText = Get-Content -LiteralPath $guestSimulatorBuilderPath -Raw -Encoding UTF8
$guestWdaCleanupText = Get-Content -LiteralPath $guestWdaCleanupPath -Raw -Encoding UTF8
Import-Module (Join-Path $packageRoot 'MobileDevelopment.psm1') -Force

$powerShellParseErrors = @(
    Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter '*.ps1' |
        ForEach-Object {
            $parseTokens = $null
            $parseErrors = $null
            [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$parseTokens, [ref]$parseErrors) | Out-Null
            foreach ($parseError in @($parseErrors)) {
                '{0}: {1}' -f $_.FullName, $parseError.Message
            }
        }
)
Report 'every canonical mobile PowerShell script parses' (
    $powerShellParseErrors.Count -eq 0
) ($powerShellParseErrors -join '; ')

Report 'canonical contract has stable top-level ownership and authorities' (
    $contract.schemaVersion -eq 1 -and $contract.recordedOn -eq '2026-08-20' -and `
    $contract.owner -eq 'mobile-quality' -and $contract.contract -eq 'mobile-development' -and `
    $contract.status -eq 'active-canonical' -and $contract.entrypoint -eq 'packages/mobile-development/mobile.ps1' -and `
    $contract.authorities.productScope -eq 'registry/mobile-scope.json' -and `
    $contract.authorities.appiumMcp -eq 'registry/mcps.json#appium-mobile' -and `
    $contract.authorities.vmx -eq 'D:/VMs/macOS-Tahoe-AMD/macos.vmx'
) 'Top-level identity or sole-authority references drifted.'

$expectedPrimary = @('scope.resolve','platform.expo-baseline','development.metro','build.android-apk','build.ios-simulator','device.android-emulator','device.ios-simulator','inspect.appium','test.unit-component','test.maestro','test.mobile-web','evidence.capture','guest.sync','health.check')
$expectedSpecialty = @('build.ios-signed','device.physical','delivery.eas-store','integration.push','integration.deep-links','observability.mobile')
$expectedResources = @('mobile-scope-registry','windows-mobile-toolchain','windows-hypervisor-platform','vmware-workstation','macos-guest-vm','macos-guest-known-good-backup','android-avd','ios-simulator')
$expectedServices = @('adb','metro','ssh','guest-appium','appium-mcp')
$expectedOutOfScope = @('detox','maestro-mcp','wsl-android-e2e','android-studio','nested-virtualization','second-vm-nic','routine-cloud-builds','cloud-device-farms')

Report 'primary agent surface exactly matches the approved 14 jobs' (Test-Sequence @($contract.agentSurface.primary.id) $expectedPrimary) "actual=$(@($contract.agentSurface.primary.id) -join ',')"
Report 'specialty agent surface exactly matches the approved 6 gated jobs' (Test-Sequence @($contract.agentSurface.specialty.id) $expectedSpecialty) "actual=$(@($contract.agentSurface.specialty.id) -join ',')"
Report 'resource catalog exactly covers the approved providers' (Test-Sequence @($contract.resources.id) $expectedResources) "actual=$(@($contract.resources.id) -join ',')"
Report 'service catalog exactly covers five lifecycle services' (Test-Sequence @($contract.services.id) $expectedServices) "actual=$(@($contract.services.id) -join ',')"
Report 'closed task map mirrors the approved capability lists' (
    $contract.taskMap.closedDecision -eq $true -and @($contract.taskMap.deferred).Count -eq 0 -and `
    (Test-Sequence @($contract.taskMap.enabled) $expectedPrimary) -and `
    (Test-Sequence @($contract.taskMap.specialty) $expectedSpecialty) -and `
    (Test-Sequence @($contract.taskMap.outOfScope.id) $expectedOutOfScope) -and `
    [string]$contract.taskMap.rationale -match 'not a backlog|new approved contract'
) 'The closed decision map gained, lost, reordered, or deferred work.'

$resourceIds = @($contract.resources.id)
$serviceIds = @($contract.services.id)
$badProviderRefs = @()
$badServiceRefs = @()
$badFileRefs = @()
$badCommands = @()
$badServiceInvocationRefs = @()
foreach ($surface in @($contract.agentSurface.primary) + @($contract.agentSurface.specialty)) {
    foreach ($id in @($surface.providerIds | Where-Object { $_ })) { if ($id -notin $resourceIds) { $badProviderRefs += "$($surface.id):$id" } }
    foreach ($id in @($surface.serviceIds | Where-Object { $_ })) { if ($id -notin $serviceIds) { $badServiceRefs += "$($surface.id):$id" } }
    foreach ($ref in @($surface.fileRefs | Where-Object { $_ })) {
        $filePart = ([string]$ref -split '#')[0]
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ($filePart -replace '/', '\')) -PathType Leaf)) { $badFileRefs += "$($surface.id):$ref" }
    }
    if ($surface.command -and [string]$surface.command -notmatch '^mobile\.ps1\s+(catalog|scope|check|mcp|start|test|sync|metro|web)\b') { $badCommands += "$($surface.id):$($surface.command)" }
}
foreach ($resource in @($contract.resources)) {
    if ($resource.providerId -and [string]$resource.providerId -notin $resourceIds) { $badProviderRefs += "$($resource.id):$($resource.providerId)" }
}
foreach ($service in @($contract.services)) {
    $invocation = [string]$service.invocation
    if ($invocation -match '^(packages/[^ ]+)') {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ($Matches[1] -replace '/', '\')) -PathType Leaf)) { $badServiceInvocationRefs += "$($service.id):$invocation" }
    }
    elseif ($invocation -match '^mobile\.ps1\b') {
        if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) { $badServiceInvocationRefs += "$($service.id):$invocation" }
    }
    elseif ($invocation -match '^<android-sdk>/(.+)$') {
        $toolchain = @($contract.resources | Where-Object id -eq 'windows-mobile-toolchain')[0]
        $sdkRoot = @($toolchain.discovery.androidSdkEnvironment | ForEach-Object { [Environment]::GetEnvironmentVariable([string]$_) } | Where-Object { $_ } | Select-Object -First 1)
        if ($sdkRoot.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $sdkRoot[0] ($Matches[1] -replace '/', '\')) -PathType Leaf)) { $badServiceInvocationRefs += "$($service.id):$invocation" }
    }
    elseif ($invocation -match '^ssh\b') {
        if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { $badServiceInvocationRefs += "$($service.id):$invocation" }
    }
    else { $badServiceInvocationRefs += "$($service.id):$invocation" }
}
$delegateMap = [ordered]@{
    start = 'skills\mobile-device-lab\scripts\Start-MobileLab.ps1'
    test = 'skills\mobile-device-lab\scripts\Test-MobileLab.ps1'
    sync = 'skills\mobile-device-lab\scripts\Sync-RepoToGuest.ps1'
    metro = 'skills\mobile-device-lab\scripts\Start-MobileLabMetro.ps1'
    web = 'skills\mobile-device-lab\scripts\Open-MobileLabWebTarget.ps1'
}
$badDelegates = @($delegateMap.GetEnumerator() | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $packageRoot $_.Value) -PathType Leaf) -or
    $entrypointText -notmatch [regex]::Escape($_.Value)
} | ForEach-Object Key)
Report 'every provider, service, command, file, service invocation, and wrapper delegate resolves' (
    $badProviderRefs.Count -eq 0 -and $badServiceRefs.Count -eq 0 -and $badFileRefs.Count -eq 0 -and
    $badCommands.Count -eq 0 -and $badServiceInvocationRefs.Count -eq 0 -and $badDelegates.Count -eq 0
) "providers=$($badProviderRefs -join ',') services=$($badServiceRefs -join ',') files=$($badFileRefs -join ',') commands=$($badCommands -join ',') serviceInvocations=$($badServiceInvocationRefs -join ',') delegates=$($badDelegates -join ',')"
$delegateInvocationCount = ([regex]::Matches($entrypointText, 'Invoke-MobileDelegate\s+-Script\s+\$script\s+-Arguments\s+\$forward')).Count
Report 'public wrapper preserves named options for every delegated PowerShell route' (
    $entrypointText -match 'function\s+Invoke-MobileDelegate' -and `
    $entrypointText -match '&\s+\$hostExe\s+-NoProfile\s+-File\s+\$Script\s+@Arguments' -and `
    $entrypointText -notmatch '&\s+\$script\s+@forward' -and `
    $delegateInvocationCount -eq 6
) "delegateInvocationCount=$delegateInvocationCount"
Report 'every service declares activation, invocation, and readiness metadata' (@($contract.services | Where-Object { -not $_.activationMode -or -not $_.invocation -or -not $_.readiness }).Count -eq 0) 'A lifecycle field is missing.'

$appium = @($mcps.mcpServers | Where-Object id -eq 'appium-mobile')
$pinArgs = if ($appium.Count) { @($appium[0].args | Where-Object { [string]$_ -match '^appium-mcp@[0-9]+\.[0-9]+\.[0-9]+' }) } else { @() }
$manifestPin = @($mcpManifest.mcpServers.'appium-mobile'.args | Where-Object { [string]$_ -match '^appium-mcp@' })
$pinRegistryShape = ($appium.Count -eq 1 -and $pinArgs.Count -eq 1 -and $appium[0].command -eq 'npx')
$pinManifestParity = ($manifestPin.Count -eq 1 -and (($manifestPin -join '') -ceq ($pinArgs -join '')))
$pinResolverPresent = $moduleText -match "Read-AgentHubJson -RelativePath 'registry/mcps\.json'"
$pinAbsentFromClient = $mcpSmokeText -notmatch 'appium-mcp@[0-9]'
$pinOk = [bool]($pinRegistryShape -and $pinManifestParity -and $pinResolverPresent -and $pinAbsentFromClient)
Report 'registry/mcps.json is the sole Appium MCP pin authority' $pinOk "shape=$pinRegistryShape parity=$pinManifestParity resolver=$pinResolverPresent clientDynamic=$pinAbsentFromClient registry=$($pinArgs -join ',') manifest=$($manifestPin -join ',')"
Report 'deep smoke receives the resolved pin and emits the resolved version' (
    $gateText -match '--appium-package\s+\$appiumMcp\.Package' -and `
    $gateText -match '\[''appiumMcpVersion''\]\s*=\s*\$appiumMcp\.Version' -and `
    $mcpSmokeText -match 'args\["appium-package"\]'
) 'The smoke client or emitted facts can drift from registry/mcps.json.'

$claudeManifest = Read-Json 'packages\mobile-development\.claude-plugin\plugin.json'
$codexManifest = Read-Json 'packages\mobile-development\.codex-plugin\plugin.json'
Report 'generic, Claude, and Codex manifests share one mobile-development identity and version' (
    $manifest.name -eq 'mobile-development' -and $claudeManifest.name -eq $manifest.name -and $codexManifest.name -eq $manifest.name -and `
    $manifest.version -eq '2.0.0' -and $claudeManifest.version -eq $manifest.version -and $codexManifest.version -eq $manifest.version
) "generic=$($manifest.name)@$($manifest.version) claude=$($claudeManifest.name)@$($claudeManifest.version) codex=$($codexManifest.name)@$($codexManifest.version)"
$retainedHostManifestDirs = @(Get-ChildItem -LiteralPath $packageRoot -Force -Directory | Where-Object Name -match '^\..+-plugin$' | Select-Object -ExpandProperty Name | Sort-Object)
Report 'unsupported legacy host manifests are absent' (
    Test-Sequence $retainedHostManifestDirs @('.claude-plugin','.codex-plugin')
) "retained=$($retainedHostManifestDirs -join ',')"
Report 'both marketplaces expose only the canonical mobile-development package identity' (
    @($agentMarketplace.plugins | Where-Object name -eq 'mobile-development').Count -eq 1 -and `
    @($claudeMarketplace.plugins | Where-Object name -eq 'mobile-development').Count -eq 1 -and `
    @($agentMarketplace.plugins | Where-Object name -eq 'mobile-development')[0].source.path -eq './packages/mobile-development' -and `
    @($claudeMarketplace.plugins | Where-Object name -eq 'mobile-development')[0].source -eq './packages/mobile-development' -and `
    'mobile-device-lab' -notin @($agentMarketplace.plugins.name) -and 'mobile-device-lab' -notin @($claudeMarketplace.plugins.name)
) 'A marketplace still exposes the retired package/plugin identity or path.'

$mobileCapability = @($capabilities.capabilities | Where-Object id -eq 'mobile-development')
$oldCapability = @($capabilities.capabilities | Where-Object id -eq 'mobile-device-lab')
$owners = @($capabilities.capabilities | Where-Object { 'mobile-device-lab' -in @($_.managedSkillNames) -or 'mobile-platform-standard' -in @($_.managedSkillNames) })
$portfolio = @($capabilities.capabilities | Where-Object id -eq 'portfolio-engineering')
Report 'mobile-development is the one owner of both recognizable skills' (
    $mobileCapability.Count -eq 1 -and $oldCapability.Count -eq 0 -and $owners.Count -eq 1 -and `
    (Test-Sequence @($mobileCapability[0].managedSkillNames) @('mobile-device-lab','mobile-platform-standard')) -and `
    'mobile-platform-standard' -notin @($portfolio[0].managedSkillNames)
) "owners=$(@($owners.id) -join ',')"
Report 'old package and split skill residues are absent' (
    @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'packages\mobile-device-lab') -Recurse -File -Force -ErrorAction SilentlyContinue).Count -eq 0 -and `
    @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'packages\portfolio-engineering\skills\mobile-platform-standard') -Recurse -File -Force -ErrorAction SilentlyContinue).Count -eq 0
) 'A duplicate canonical package or split skill tree remains.'

$alias = @{}; foreach ($row in @($capabilities.surfaceAliases)) { $alias[[string]$row.surfaceId] = [string]$row.inheritsHostId }
$activeAgents = @($agents.activeAgents | Where-Object status -eq 'active')
$activeHosts = @($activeAgents | ForEach-Object { if ($alias.ContainsKey([string]$_.id)) { $alias[[string]$_.id] } else { [string]$_.id } } | Sort-Object -Unique)
$mappedHosts = @($mobileCapability[0].hostMappings.hostId | Sort-Object -Unique)
$mobileDeploymentFailures = @(
    foreach ($activeAgent in $activeAgents) {
        $resolvedHost = if ($alias.ContainsKey([string]$activeAgent.id)) { $alias[[string]$activeAgent.id] } else { [string]$activeAgent.id }
        $resolvedAgent = @($agents.activeAgents | Where-Object id -eq $resolvedHost | Select-Object -First 1)
        $mapping = @($mobileCapability[0].hostMappings | Where-Object hostId -eq $resolvedHost)
        $skillsDir = if ($resolvedAgent.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$resolvedAgent[0].nativePaths.sharedSkillsDir)) {
            [string]$resolvedAgent[0].nativePaths.sharedSkillsDir
        } elseif ($resolvedAgent.Count -eq 1) {
            [string]$resolvedAgent[0].nativePaths.skillsDir
        } else { $null }
        $skillsReadable = $true
        foreach ($skillName in @($mobileCapability[0].managedSkillNames)) {
            $source = Join-Path $packageRoot "skills\$skillName"
            $destination = if ($skillsDir) { Join-Path $skillsDir $skillName } else { $null }
            if (-not $destination -or -not (Test-ReadableSkillTree -Source $source -Destination $destination)) {
                $skillsReadable = $false
            }
        }
        $catalogPath = Join-Path $repoRoot (([string]$mobileCapability[0].catalogEntrypoint -split '\s+')[0] -replace '/', '\')
        $catalogReadable = Test-Path -LiteralPath $catalogPath -PathType Leaf
        if ($mapping.Count -ne 1 -or 'skills' -notin @($mapping[0].components) -or
            'catalog' -notin @($mapping[0].components) -or -not $skillsReadable -or -not $catalogReadable) {
            "$($activeAgent.id)->$resolvedHost skillsDir=$skillsDir mappingCount=$($mapping.Count) skillsReadable=$skillsReadable catalogReadable=$catalogReadable"
        }
    }
)
Report 'all active coding hosts receive the loose mobile skills and catalog' (
    (Test-Sequence $mappedHosts $activeHosts) -and `
    $mobileCapability[0].catalogEntrypoint -eq 'packages/mobile-development/mobile.ps1 catalog' -and `
    @($mobileCapability[0].hostMappings | Where-Object { [string]$_.deploymentStatus -notmatch 'loose-skills' -or 'skills' -notin @($_.components) -or 'catalog' -notin @($_.components) }).Count -eq 0 -and `
    $mobileDeploymentFailures.Count -eq 0
) "active=$($activeHosts -join ',') mapped=$($mappedHosts -join ',') deploymentFailures=$($mobileDeploymentFailures -join '; ')"
Report 'Appium MCP is scoped to Claude and Codex only' (Test-Sequence @($appium[0].hosts) @('claude','codex')) "hosts=$(@($appium[0].hosts) -join ',')"
Report 'Appium never persists in default host MCP configuration' ('appium-mobile' -notin @($connectors.lifecyclePolicy.persistedOnDemandLocalMcpIds)) 'Persisting stdio Appium starts an idle process per task.'
Report 'native MCP management is enable/disable and explains new-task loading' (
    ($entrypointText -match "'claude'.*plugin" -or $entrypointText -match "\$hostName -eq 'claude'") -and `
    $entrypointText -match "'add'" -and $entrypointText -match "'remove'" -and `
    $entrypointText -match 'open a new.*task' -and $entrypointText -match 'Existing tasks may retain'
) 'The public entrypoint must use claude plugin enable/disable and codex plugin add/remove, then explain task-scoped loading.'
Report 'native activation registry names the canonical explicit add/remove routes' (
    $connectors.lifecyclePolicy.appiumActivationRoute -match 'claude plugin enable mobile-development@agenthub' -and `
    $connectors.lifecyclePolicy.appiumActivationRoute -match 'claude plugin disable mobile-development@agenthub' -and `
    $connectors.lifecyclePolicy.appiumActivationRoute -match 'codex plugin add mobile-development@agenthub' -and `
    $connectors.lifecyclePolicy.appiumActivationRoute -match 'codex plugin remove mobile-development@agenthub' -and `
    $connectors.lifecyclePolicy.appiumActivationRoute -match 'new task'
) 'The registry does not match the public entrypoint activation contract.'

$catalog = Invoke-MobileJson @('catalog','inspect.appium')
$catalogMatch = 'inspect.appium' -in @($catalog.Result.matches.id)
$catalogOk = [bool]($catalog.ExitCode -eq 0 -and $catalogMatch -and ([string]$catalog.Result.resolved.appiumMcpPackage -ceq ($pinArgs -join '')) -and $catalog.Result.resolved.vmxHardware.exists)
Report 'catalog query resolves canonical records plus authoritative live facts' $catalogOk "match=$catalogMatch exit=$($catalog.ExitCode) output=$($catalog.Output -join ' ')"
$includeScope = Invoke-MobileJson @('scope','rexa')
$noNativeScope = Invoke-MobileJson @('scope','agenthub')
Report 'scope resolves include products' ($includeScope.ExitCode -eq 0 -and $includeScope.Result.bucket -eq 'include' -and $includeScope.Result.eligible) "output=$($includeScope.Output -join ' ')"
Report 'scope resolves noNative explicitly instead of treating it as absent' ($noNativeScope.ExitCode -eq 0 -and $noNativeScope.Result.bucket -eq 'noNative' -and -not $noNativeScope.Result.eligible -and $noNativeScope.Result.decision -match 'no native') "output=$($noNativeScope.Output -join ' ')"
Report 'both loose skills enumerate noNative and fail closed to exact include eligibility' (
    $platformSkillText -match '\| `noNative` \|' -and $labSkillText -match '\| `noNative` \|' -and
    $platformSkillText -match 'only an exact `include` record authorizes' -and
    $labSkillText -match 'only an exact `include` record authorizes'
) 'A loose skill can infer product eligibility outside registry/mobile-scope.json#include.'
Report 'platform skill resolves mutable product identity and account facts instead of copying them' (
    $platformSkillText -match 'sole product identity authority' -and
    $platformSkillText -match 'do not persist a second table in a skill' -and
    $platformSkillText -notmatch '9V6CGU625U|app\.shmindmaster\.rexa|ai\.abacare\.app|@shmindmaster/recallforge'
) 'The skill still carries a copied bundle ID, Apple team ID, provider identity, or product exception.'
$gatedNoNative = Invoke-MobileJson @('sync','agenthub')
$gatedEvaluate = Invoke-MobileJson @('metro','lawli')
$gatedFrozen = Invoke-MobileJson @('web','empowera')
$gatedAbsent = Invoke-MobileJson @('sync','definitely-unclassified')
Report 'every product-targeting command requires an include product' (
    $gatedNoNative.ExitCode -ne 0 -and $gatedNoNative.Result.error -match "classified 'noNative'" -and `
    $gatedEvaluate.ExitCode -ne 0 -and $gatedEvaluate.Result.error -match "classified 'evaluateLater'" -and `
    $gatedFrozen.ExitCode -ne 0 -and $gatedFrozen.Result.error -match "classified 'excludedPendingReposition'" -and `
    $gatedAbsent.ExitCode -ne 0 -and $gatedAbsent.Result.error -match 'absent.*Absence never means eligible'
) 'sync, metro, or web reached its underlying script before the sole scope authority allowed it.'
Report 'deep smoke is the sole fixed synthetic product-scope exception' (
    $contract.syntheticFixture.path -eq 'packages/mobile-development/fixtures/smoke-app' -and `
    $contract.syntheticFixture.scopeException -match 'test deep' -and `
    $entrypointText -match "'test'.*" -and $entrypointText -match "\$mode -ne 'deep'"
) 'The synthetic exception is absent, broad, or product-selectable.'

$fixtureRoot = Join-Path $packageRoot 'fixtures\smoke-app'
$fixtureText = @('app.json','package.json') | ForEach-Object { Get-Content -LiteralPath (Join-Path $fixtureRoot $_) -Raw -Encoding UTF8 } | Out-String
Report 'synthetic evidence fixture carries no cloud or store identity' (
    (Test-Path -LiteralPath (Join-Path $fixtureRoot 'App.js')) -and `
    (Test-Path -LiteralPath (Join-Path $fixtureRoot '.maestro\smoke.yaml')) -and `
    -not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'eas.json')) -and `
    $fixtureText -notmatch 'projectId|updates\.url|store\.config|owner'
) 'The infrastructure fixture must remain local-only and identity-free.'
Report 'health-sensitive evidence guidance is synthetic-only' (
    $labSkillText -match 'healthSensitive' -and $labSkillText -match 'synthetic fixtures' -and `
    $labSkillText -match 'Never capture[\s\S]*real patient data'
) 'Capture guidance could expose PHI or private patient evidence.'

$vmx = ([string]$contract.authorities.vmx) -replace '/', '\'
$backupResource = @($contract.resources | Where-Object id -eq 'macos-guest-known-good-backup')
$vmxText = if (Test-Path -LiteralPath $vmx) { Get-Content -LiteralPath $vmx -Raw -Encoding UTF8 } else { '' }
$vmxCpu = if ($vmxText -match '(?m)^numvcpus\s*=\s*"([0-9]+)"') { [int]$Matches[1] } else { $null }
$vmxMemory = if ($vmxText -match '(?m)^memsize\s*=\s*"([0-9]+)"') { [int]$Matches[1] } else { $null }
Report 'VMX and known-good backup paths resolve without touching either tree' (
    (Test-Path -LiteralPath $vmx -PathType Leaf) -and $backupResource.Count -eq 1 -and `
    $backupResource[0].path -eq 'D:/VMs/macOS-Tahoe-AMD-Backup-2026-08-10' -and `
    (Test-Path -LiteralPath (([string]$backupResource[0].path -replace '/', '\')) -PathType Container)
) "vmx=$vmx backup=$($backupResource[0].path)"
$vmReadmePath = 'D:\VMs\macOS-Tahoe-AMD\README.md'
$vmReadmeText = if (Test-Path -LiteralPath $vmReadmePath) { Get-Content -LiteralPath $vmReadmePath -Raw -Encoding UTF8 } else { '' }
Report 'VM README is a thin canonical pointer with no copied runtime contract' (
    $vmReadmeText -match [regex]::Escape('C:\Repos\shmindmaster\agenthub\packages\mobile-development\mobile.ps1') -and `
    $vmReadmeText -match [regex]::Escape('D:\VMs\macOS-Tahoe-AMD-Backup-2026-08-10') -and `
    $vmReadmeText -match 'must not modify VM disks' -and `
    $vmReadmeText -notmatch 'D:\\Downloads|boot entry|vCPU|GB RAM|fixed IP|192\.168\.'
) 'The external VM document copied mutable hardware/network facts or dead operational guidance.'
Report 'catalog parses VM hardware live and registry records no copied values' (
    $catalog.Result.resolved.vmxHardware.vcpu -eq $vmxCpu -and `
    $catalog.Result.resolved.vmxHardware.memoryMb -eq $vmxMemory -and `
    $contract.resources[4].hardwareDiscovery.recordValuesHere -eq $false -and `
    -not $contract.resources[4].PSObject.Properties['vcpu'] -and `
    -not $contract.resources[4].PSObject.Properties['memoryMb']
) "catalog=$($catalog.Result.resolved.vmxHardware | ConvertTo-Json -Compress) liveCpu=$vmxCpu liveMemory=$vmxMemory"

$activeScriptText = @($startText,$gateText,$idleText,$syncGuestText,$mcpSmokeText) -join "`n"
$copiedExpectationLiterals = @(
    [string]$contract.expectations.guestAppium.version,
    [string]$contract.expectations.xcuitest.version,
    [string]$contract.expectations.ios.deviceName,
    [string]$contract.expectations.ios.platformVersion,
    [string]$contract.expectations.android.avdName
) | Where-Object { $activeScriptText -match [regex]::Escape($_) }
Report 'active scripts resolve guest and virtual-device expectations from registry' (
    $copiedExpectationLiterals.Count -eq 0 -and `
    $startText -match 'Get-MobileDevelopmentContract' -and $gateText -match 'Get-MobileDevelopmentContract' -and `
    $syncGuestText -match 'mobile-development\.env' -and `
    (Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\setup-appium-guest.sh') -Raw -Encoding UTF8) -match 'mobile-development\.env'
) "copied literals=$($copiedExpectationLiterals -join ',')"
Report 'startup resolves only the canonical VMX and fails closed on nested virtualization' (
    $startText -match '\$Vmx\s*=\s*\(Get-MobileVmxFacts\)\.path' -and `
    $startText -notmatch 'inventory\.vmls' -and `
    $startText -notmatch 'WriteAllText\(\$Vmx' -and `
    $startText -match 'Nested virtualization is out of scope'
) 'Startup may select or rewrite a different VMX.'

$before = Get-MobileProcessSnapshot
$filesCheck = Invoke-MobileJson @('check','files','both')
$afterFiles = Get-MobileProcessSnapshot
$runtimeCheck = Invoke-MobileJson @('check','runtime','both')
$afterRuntime = Get-MobileProcessSnapshot
Report 'read-only file check demonstrably starts no mobile resource' (
    $filesCheck.Result -and -not $filesCheck.Result.startedResources -and (Test-Sequence $afterFiles $before)
) "before=$($before -join ',') after=$($afterFiles -join ',') output=$($filesCheck.Output -join ' ')"
Report 'read-only runtime check demonstrably starts no adb, emulator, or VMware guest process' (
    $runtimeCheck.Result -and -not $runtimeCheck.Result.startedResources -and (Test-Sequence $afterRuntime $afterFiles)
) "before=$($afterFiles -join ',') after=$($afterRuntime -join ',') output=$($runtimeCheck.Output -join ' ')"
Report 'runtime check is process-table-only and never invokes lifecycle commands' (
    $entrypointText -match 'process-table-only' -and `
    $entrypointText -notmatch 'Get-MobileRuntimeCheck[\s\S]{0,3500}Start-Process' -and `
    $entrypointText -notmatch 'Get-MobileRuntimeCheck[\s\S]{0,3500}&\s*\$adb'
) 'The read-only runtime path can start or drive a mobile resource.'

$runtimeHealthFunction = [regex]::Match($entrypointText, 'function Invoke-MobileRuntimeHealthCheck[\s\S]+?(?=\r?\ntry \{)').Value
$healthProcessPreflight = $runtimeHealthFunction.IndexOf('Get-MobileRuntimeCheck -Platform $Platform')
$healthDelegate = $runtimeHealthFunction.IndexOf('Invoke-MobileDelegate -Script $script -Arguments $forward')
$gateProcessPreflight = $gateText.IndexOf('Get-MobileRuntimeProcessMatch -Platform $runtimePlatform')
$gateNodeProbe = $gateText.IndexOf('Get-Command node')
$gateAdbProbe = $gateText.IndexOf('& $adb @existingServerArgs devices')
$gateVmProbe = $gateText.IndexOf('& $vmrun list')
$invokeGuestFunction = [regex]::Match($gateText, 'function Invoke-Guest[\s\S]+?(?=\r?\nWrite-Host)').Value
$guestAsyncDrain = $invokeGuestFunction.IndexOf('ReadToEndAsync()')
$guestWaitForExit = $invokeGuestFunction.IndexOf('$p.WaitForExit($TimeoutSec * 1000)')
Report 'check runtime -Deep fails closed on canonical processes before full health delegation' (
    $entrypointText -match "-Deep is valid only with check runtime" -and `
    $healthProcessPreflight -ge 0 -and $healthProcessPreflight -lt $healthDelegate -and `
    $runtimeHealthFunction -match 'if \(-not \$invocation\.delegate\)' -and `
    $runtimeHealthFunction -match 'startedResources = \$false'
) 'The public deep-health route can probe or delegate before exact process identity is established.'
Report 'deep health delegates to the retained gate without enabling synthetic smoke' (
    $runtimeHealthFunction -match 'Get-MobileRuntimeHealthInvocation' -and `
    $runtimeHealthFunction -match 'Invoke-MobileDelegate -Script \$script -Arguments \$forward' -and `
    $runtimeHealthFunction -notmatch "@\('-Deep'\)" -and `
    $gateText -match '\[switch\]\$RequireRunningProcesses'
) 'The public health route bypasses the retained gate or can trigger its mutating -Deep mode.'
Report 'retained health gate repeats process preflight before node adb and VMware probes' (
    $gateProcessPreflight -ge 0 -and $gateProcessPreflight -lt $gateNodeProbe -and `
    $gateProcessPreflight -lt $gateAdbProbe -and $gateProcessPreflight -lt $gateVmProbe -and `
    $gateText -match "@\('-H', '127\.0\.0\.1', '-P', '5037'\)" -and `
    $gateText -match '& \$adb @existingServerArgs -s \$id emu avd name'
) 'The retained gate can auto-discover/start adb or probe before canonical runtime processes are proven.'
Report 'guest command runner drains redirected output before waiting for exit' (
    $guestAsyncDrain -ge 0 -and $guestAsyncDrain -lt $guestWaitForExit -and `
    $invokeGuestFunction -notmatch '\.Standard(Output|Error)\.ReadToEnd\(\)'
) 'Large simctl JSON can fill the redirected pipe and deadlock the gate before its timeout.'
Report 'guest synthetic build lifecycle is race-free under macOS Bash' (
    $guestBuildSupervisorText.Contains('printf ''%s\n'' ''RUNNING'' >"$STATUS_FILE"') -and `
    $guestBuildSupervisorText -match 'mv "\$STATUS_FILE\.tmp" "\$STATUS_FILE"' -and `
    $guestSimulatorBuilderText.Contains('${XCODE_EXTRA[@]+"${XCODE_EXTRA[@]}"}') -and `
    $guestSimulatorBuilderText -notmatch '(?m)^\s*"\$\{XCODE_EXTRA\[@\]\}"\s*\\\s*$'
) 'The supervisor can report transient IDLE or the optional Xcode argument array is unsafe with set -u.'
Report 'guest WDA cleanup is bounded and safe with an empty match set' (
    $guestWdaCleanupText -match 'while read -r pid ppid command; do' -and `
    $guestWdaCleanupText -notmatch '\bawk\b' -and `
    $guestWdaCleanupText.Contains('for pid in $owned_pids; do') -and `
    $guestWdaCleanupText.Contains('"$owned_count" "$owned_pids"')
) 'The cleanup can exceed its 30-second caller timeout or fail under macOS Bash when no Appium-owned runner remains.'
$requiredHealthEvidence = @(
    'windows: node >= 22',
    'android: canonical',
    'vmware: the macOS guest is running',
    'ssh: guest executes commands',
    'guest: Xcode usable',
    'simulator runtime is installed',
    'Simulator is booted',
    'guest: Appium',
    'guest: XCUITest',
    'appium: server reachable from Windows'
)
$missingHealthEvidence = @($requiredHealthEvidence | Where-Object { $gateText -notmatch [regex]::Escape($_) })
Report 'deep health retains SSH Xcode runtime Simulator Appium and XCUITest coverage' (
    $missingHealthEvidence.Count -eq 0
) "missing=$($missingHealthEvidence -join ',')"

$syntheticSdk = 'C:\synthetic\Android\Sdk'
$canonicalAvd = [string]$contract.expectations.android.avdName
$canonicalApi = [string]$contract.expectations.android.apiLevel
$androidProcesses = @(
    [pscustomobject]@{ Name='adb.exe'; ProcessId=101; ExecutablePath="$syntheticSdk\platform-tools\adb.exe"; CommandLine='adb -L tcp:5037 fork-server server' },
    [pscustomobject]@{ Name='qemu-system-x86_64.exe'; ProcessId=102; ExecutablePath="$syntheticSdk\emulator\qemu\windows-x86_64\qemu-system-x86_64.exe"; CommandLine="qemu-system-x86_64.exe -avd $canonicalAvd" }
)
$androidMatch = Get-MobileRuntimeProcessMatch -Platform android -Processes $androidProcesses -AndroidSdkRoot $syntheticSdk -AvdConfigText "image.sysdir.1=system-images\android-$canonicalApi\google_apis\x86_64\"
$wrongAvdProcesses = @($androidProcesses[0], [pscustomobject]@{ Name='qemu-system-x86_64.exe'; ProcessId=103; ExecutablePath="$syntheticSdk\emulator\qemu\windows-x86_64\qemu-system-x86_64.exe"; CommandLine='qemu-system-x86_64.exe -avd unrelated-api36' })
$wrongAvd = Get-MobileRuntimeProcessMatch -Platform android -Processes $wrongAvdProcesses -AndroidSdkRoot $syntheticSdk -AvdConfigText "image.sysdir.1=system-images\android-$canonicalApi\google_apis\x86_64\"
$wrongApi = Get-MobileRuntimeProcessMatch -Platform android -Processes $androidProcesses -AndroidSdkRoot $syntheticSdk -AvdConfigText 'image.sysdir.1=system-images\android-35\google_apis\x86_64\'
$canonicalVmx = (([string]$contract.authorities.vmx) -replace '/', '\')
$iosMatch = Get-MobileRuntimeProcessMatch -Platform ios -Processes @([pscustomobject]@{ Name='vmware-vmx.exe'; ProcessId=201; ExecutablePath='C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe'; CommandLine="vmware-vmx.exe `"$canonicalVmx`"" })
$wrongIos = Get-MobileRuntimeProcessMatch -Platform ios -Processes @([pscustomobject]@{ Name='vmware-vmx.exe'; ProcessId=202; ExecutablePath='C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe'; CommandLine='vmware-vmx.exe "C:\unrelated\macos.vmx"' })
$iosTrailingCollision = Get-MobileRuntimeProcessMatch -Platform ios -Processes @([pscustomobject]@{ Name='vmware-vmx.exe'; ProcessId=203; ExecutablePath='C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe'; CommandLine="vmware-vmx.exe `"$canonicalVmx.backup`"" })
$iosLeadingCollision = Get-MobileRuntimeProcessMatch -Platform ios -Processes @([pscustomobject]@{ Name='vmware-vmx.exe'; ProcessId=204; ExecutablePath='C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe'; CommandLine="vmware-vmx.exe `"prefix-$canonicalVmx`"" })
Report 'runtime matching requires canonical Android SDK, AVD, and API evidence' (
    $androidMatch.ready -and $androidMatch.android.avdConfigMatchesApi -and -not $wrongAvd.ready -and -not $wrongApi.ready
) "canonical=$($androidMatch | ConvertTo-Json -Depth 5 -Compress) wrongAvdReady=$($wrongAvd.ready) wrongApiReady=$($wrongApi.ready)"
Report 'runtime matching requires the authoritative iOS VMX as an exact command-line token' (
    $iosMatch.ready -and -not $wrongIos.ready -and -not $iosTrailingCollision.ready -and -not $iosLeadingCollision.ready
) "canonicalReady=$($iosMatch.ready) unrelatedReady=$($wrongIos.ready) trailingCollisionReady=$($iosTrailingCollision.ready) leadingCollisionReady=$($iosLeadingCollision.ready) path=$canonicalVmx"
$readyHealthInvocation = Get-MobileRuntimeHealthInvocation -Platform android -ProcessCheck $androidMatch
$blockedHealthInvocation = Get-MobileRuntimeHealthInvocation -Platform android -ProcessCheck $wrongAvd
Report 'deep health invocation delegates only after a successful process match' (
    $readyHealthInvocation.delegate -and -not $blockedHealthInvocation.delegate -and `
    -not $readyHealthInvocation.startedResources -and `
    (Test-Sequence @($readyHealthInvocation.arguments) @('-RequireRunningProcesses','-SkipIos')) -and `
    $readyHealthInvocation.scriptRelativePath -eq 'skills\mobile-device-lab\scripts\Test-MobileLab.ps1'
) "ready=$($readyHealthInvocation | ConvertTo-Json -Compress) blocked=$($blockedHealthInvocation | ConvertTo-Json -Compress)"

Report 'deep smoke pins both sessions to enumerated virtual-device IDs' (
    $mcpSmokeText -match '"appium:udid":\s*args\["android-udid"\]' -and `
    $mcpSmokeText -match '"appium:udid":\s*args\["ios-udid"\]' -and `
    $gateText -match '--android-udid\s+\$script:Facts\[''androidDeviceId''\]' -and `
    $gateText -match '--ios-udid\s+\$script:Facts\[''iosDeviceId''\]'
) 'A physical or ambiguous device could be selected.'
Report 'deep smoke retains exclusivity and complete session cleanup' (
    $gateText -match 'Global\\AgentHub\.MobileDeviceLab\.ForegroundMutation' -and `
    $gateText -match 'final pre-launch exclusivity check' -and `
    $mcpSmokeText -match 'cleanupAllCreatedSessions\(\)' -and `
    $mcpSmokeText -match 'if \(!report\.sessionsCleaned\)'
) 'Foreground mutation or Appium session cleanup wiring became unsafe.'
$hostExe = (Get-Process -Id $PID).Path
$exclusivityOutput = @(& $hostExe -NoProfile -File (Join-Path $repoRoot 'tests\Test-MobileLabExclusivity.ps1') 2>&1)
$exclusivityExit = $LASTEXITCODE
$cleanupOutput = @(& node (Join-Path $repoRoot 'tests\Test-AppiumSessionCleanup.mjs') 2>&1)
$cleanupExit = $LASTEXITCODE
Report 'lease busy/idle/contender behavior is executable' ($exclusivityExit -eq 0) "exit=$exclusivityExit output=$($exclusivityOutput -join ' ')"
Report 'Appium session cleanup behavior is executable' ($cleanupExit -eq 0) "exit=$cleanupExit output=$($cleanupOutput -join ' ')"
Report 'guest helper sync stages LF-only scripts plus generated registry facts' (
    $syncGuestText -match 'Replace\("`r`n", "`n"\)' -and `
    $syncGuestText -match "guestEnvironmentName = 'mobile-development\.env'" -and `
    $syncGuestText -match 'APPIUM_VERSION' -and $syncGuestText -match 'ANDROID_AVD_NAME'
) 'Guest expectations or line endings can drift from canonical source.'

if ($failures.Count) {
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
