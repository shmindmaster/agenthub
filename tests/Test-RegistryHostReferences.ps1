#Requires -Version 5.1
<#
Behavior tests for task-6b coverage-gap priority 1: the registry contract.
Every hostId referenced anywhere in registry/capabilities.json,
registry/mcps.json, registry/native-connectors.json,
registry/gateway-profiles.json, and registry/fleet-profile.json's
autonomyProfiles must resolve against registry/agents.json (either a real
agent id or a declared surfaceAliases surfaceId). Every capability's
canonicalSource must exist on disk. Nothing in scripts/ currently enforces
the first four files against each other -- only capabilities.json's
canonicalSource and fleet-profile.json's autonomyProfiles are covered by
scripts/Validate-AgentHub.ps1 today; mcps.json, native-connectors.json, and
gateway-profiles.json host references are unprotected. This file closes
that gap without modifying any production script (out of this task's
scope): the collector and checker below are test-only code.

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this file
follows). Same self-checking idiom: each Test-* function returns a result,
the runner prints one PASS/FAIL line per behavior, accumulates failures,
and exits 1 if any behavior did not hold, 0 otherwise.

This file only ever reads the real registry; it never writes to it and
never invokes any script with -Apply.

Run: pwsh -NoProfile -File tests/Test-RegistryHostReferences.ps1
     powershell.exe -NoProfile -File tests/Test-RegistryHostReferences.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

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

# ---------------------------------------------------------------------------
# Get-HostIdReferences: recursively walks a parsed JSON document (any of the
# five registry files' shapes) and collects every hostId reference. Two
# patterns are observed across the registry: a property literally named
# 'hostId' (capabilities.json hostMappings[], native-connectors.json
# hosts[], gateway-profiles.json hosts[] and profiles[].hostMappings[],
# fleet-profile.json autonomyProfiles.profiles[]/aliases[]), and a property
# named 'hosts' whose value is a bare array of host-id strings
# (mcps.json mcpServers[].hosts). Both are collected generically so this
# does not need to be re-taught every registry file's exact schema.
# ---------------------------------------------------------------------------
function Get-HostIdReferences {
    param($Node, [string]$PathPrefix = '$', [Collections.Generic.List[object]]$Results)
    if ($null -eq $Results) { $Results = [Collections.Generic.List[object]]::new() }
    if ($null -eq $Node) { return $Results }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $Node.PSObject.Properties) {
            $childPath = "$PathPrefix.$($prop.Name)"
            if ($prop.Name -eq 'hostId' -and ($prop.Value -is [string])) {
                $Results.Add([pscustomobject]@{ HostId = $prop.Value; Path = $childPath })
            }
            if ($prop.Name -eq 'hosts' -and ($prop.Value -is [array])) {
                $idx = 0
                foreach ($item in $prop.Value) {
                    $itemPath = "$childPath[$idx]"
                    if ($item -is [string]) {
                        $Results.Add([pscustomobject]@{ HostId = $item; Path = $itemPath })
                    } else {
                        [void](Get-HostIdReferences -Node $item -PathPrefix $itemPath -Results $Results)
                    }
                    $idx++
                }
                continue
            }
            [void](Get-HostIdReferences -Node $prop.Value -PathPrefix $childPath -Results $Results)
        }
    } elseif ($Node -is [array]) {
        $idx = 0
        foreach ($item in $Node) {
            [void](Get-HostIdReferences -Node $item -PathPrefix "$PathPrefix[$idx]" -Results $Results)
            $idx++
        }
    }
    return $Results
}

# Get-ValidHostIds: the resolvable set is every registered agent id PLUS
# every declared surface alias (registry/agents.json's surfaceAliases --
# e.g. 'cursor-agent', 'antigravity-desktop' -- which several registry
# files legitimately reference instead of the underlying hostId).
function Get-ValidHostIds {
    param($AgentsDoc)
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($a in (@($AgentsDoc.activeAgents) + @($AgentsDoc.inactiveAgents))) { [void]$ids.Add([string]$a.id) }
    foreach ($alias in @($AgentsDoc.surfaceAliases)) { [void]$ids.Add([string]$alias.surfaceId) }
    return $ids
}

function Get-HostReferenceViolations {
    param([hashtable]$DocsByLabel, [Collections.Generic.HashSet[string]]$ValidHostIds)
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($label in $DocsByLabel.Keys) {
        $refs = Get-HostIdReferences -Node $DocsByLabel[$label]
        foreach ($ref in $refs) {
            if (-not $ValidHostIds.Contains($ref.HostId)) {
                $violations.Add("$label`: unresolved hostId '$($ref.HostId)' at $($ref.Path)")
            }
        }
    }
    return $violations
}

function Get-CanonicalSourceViolations {
    param($CapabilitiesDoc, [string]$RepoRootPath)
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($capability in @($CapabilitiesDoc.capabilities)) {
        $source = [string]$capability.canonicalSource
        if ([string]::IsNullOrWhiteSpace($source)) {
            $violations.Add("capability '$($capability.id)' has an empty canonicalSource")
            continue
        }
        $resolved = Join-Path $RepoRootPath $source
        if (-not (Test-Path -LiteralPath $resolved)) {
            $violations.Add("capability '$($capability.id)' canonicalSource does not exist on disk: $source")
        }
    }
    return $violations
}

# --- Behavior 1: an unknown hostId embedded in any of the recognized
# shapes (hostId property, or a bare string in a 'hosts' array) is flagged
# by name. Synthetic fixture, never touches the real registry. ---
function Test-CollectorFlagsUnknownHostId {
    $validHostIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$validHostIds.Add('claude')
    [void]$validHostIds.Add('codex')

    $capabilitiesShaped = [pscustomobject]@{
        capabilities = @(
            [pscustomobject]@{
                id = 'fixture-cap'
                hostMappings = @([pscustomobject]@{ hostId = 'totally-bogus-host'; deploymentStatus = 'managed' })
            }
        )
    }
    $mcpsShaped = [pscustomobject]@{
        mcpServers = @([pscustomobject]@{ id = 'sample'; hosts = @('claude', 'another-bogus-host') })
    }
    $docs = @{ 'capabilities.json' = $capabilitiesShaped; 'mcps.json' = $mcpsShaped }
    $violations = Get-HostReferenceViolations -DocsByLabel $docs -ValidHostIds $validHostIds
    if ($violations.Count -ne 2) {
        return @{ Passed = $false; Detail = "expected exactly 2 violations, got $($violations.Count): $($violations -join ' | ')" }
    }
    if (($violations -join '|') -notmatch 'totally-bogus-host' -or ($violations -join '|') -notmatch 'another-bogus-host') {
        return @{ Passed = $false; Detail = "violations did not name both bogus host ids: $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2 (regression guard): a real agent id AND a declared surface
# alias id must both be accepted -- zero violations. Proves the alias
# mechanism (gateway-profiles.json/fleet-profile.json legitimately
# reference surface ids like 'cursor-agent', not just raw agent ids) is not
# a false-positive source. ---
function Test-CollectorAcceptsKnownHostIdsAndSurfaceAliases {
    $agentsDoc = [pscustomobject]@{
        activeAgents = @([pscustomobject]@{ id = 'claude' })
        inactiveAgents = @()
        surfaceAliases = @([pscustomobject]@{ surfaceId = 'cursor-agent'; inheritsHostId = 'cursor' })
    }
    $validHostIds = Get-ValidHostIds -AgentsDoc $agentsDoc
    $doc = [pscustomobject]@{
        profiles = @(
            [pscustomobject]@{ hostId = 'claude' },
            [pscustomobject]@{ hostId = 'cursor-agent' }
        )
    }
    $violations = Get-HostReferenceViolations -DocsByLabel @{ 'fixture.json' = $doc } -ValidHostIds $validHostIds
    if ($violations.Count -ne 0) {
        return @{ Passed = $false; Detail = "expected zero violations for a real host id and a declared surface alias, got: $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: the live registry. Every hostId reference across the real
# capabilities.json, mcps.json, native-connectors.json, gateway-profiles.json,
# and fleet-profile.json resolves against the real agents.json. This is the
# permanent regression guard -- if it ever fails, the registry has drifted. ---
function Test-LiveRegistryHostReferencesAllResolve {
    $registryDir = Join-Path $repoRoot 'registry'
    $agentsDoc = Get-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $validHostIds = Get-ValidHostIds -AgentsDoc $agentsDoc
    $docs = @{
        'capabilities.json'      = (Get-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'mcps.json'               = (Get-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'native-connectors.json'  = (Get-Content -LiteralPath (Join-Path $registryDir 'native-connectors.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'gateway-profiles.json'   = (Get-Content -LiteralPath (Join-Path $registryDir 'gateway-profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'fleet-profile.json.autonomyProfiles' = (Get-Content -LiteralPath (Join-Path $registryDir 'fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json).autonomyProfiles
    }
    $violations = Get-HostReferenceViolations -DocsByLabel $docs -ValidHostIds $validHostIds
    if ($violations.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($violations.Count) unresolved hostId reference(s): $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: a capability whose canonicalSource does not exist on disk
# is flagged by id. Synthetic fixture. ---
function Test-CanonicalSourceMissingOnDiskIsFlagged {
    $doc = [pscustomobject]@{
        capabilities = @([pscustomobject]@{ id = 'ghost-capability'; canonicalSource = 'packages/this-directory-does-not-exist-zz' })
    }
    $violations = Get-CanonicalSourceViolations -CapabilitiesDoc $doc -RepoRootPath $repoRoot
    if ($violations.Count -ne 1) {
        return @{ Passed = $false; Detail = "expected exactly 1 violation, got $($violations.Count): $($violations -join ' | ')" }
    }
    if (($violations -join '|') -notmatch 'ghost-capability') {
        return @{ Passed = $false; Detail = "violation did not name the capability: $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: the live registry. Every real capability's canonicalSource
# exists on disk. Permanent regression guard. ---
function Test-LiveCapabilitiesCanonicalSourcesAllExistOnDisk {
    $capabilitiesDoc = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $violations = Get-CanonicalSourceViolations -CapabilitiesDoc $capabilitiesDoc -RepoRootPath $repoRoot
    if ($violations.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($violations.Count) missing canonicalSource(s): $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 6: every host configuration carries an explicit auth mode and
# owner login command. Unverified account smokes remain gated; Codex dispatch
# is gated on recorded response-capture evidence rather than a fixed state. ---
# A cloud budget authorization is a dated owner record, not a flag: it quotes
# the owner, caps spend per session and concurrency, and names the key by an
# environment variable and a 1Password reference, never by value. The key
# variable must not be one the local CLI adapters strip to protect their account
# logins (DEVIN_API_KEY and its siblings), or a cloud key would override them.
function Get-CloudBudgetAuthorizationViolations($Authorization) {
    $errors = [Collections.Generic.List[string]]::new()
    if ($Authorization -isnot [pscustomobject]) { $errors.Add('not an object'); return $errors }
    if ([string]$Authorization.date -notmatch '^\d{4}-\d{2}-\d{2}$') { $errors.Add('date is not yyyy-mm-dd') }
    if (@($Authorization.ownerQuotes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) { $errors.Add('no ownerQuotes') }
    foreach ($cap in @('defaultMaxAcuLimit', 'maxConcurrentSessions')) {
        $value = $Authorization.$cap
        if (-not ($value -is [int] -or $value -is [long]) -or $value -lt 1) { $errors.Add("$cap is not a positive integer") }
    }
    foreach ($field in @('keyType', 'orgId')) {
        if ([string]::IsNullOrWhiteSpace([string]$Authorization.$field)) { $errors.Add("no $field") }
    }
    $keyEnv = [string]$Authorization.keyEnv
    if ($keyEnv -cnotmatch '^[A-Z][A-Z0-9_]*$') { $errors.Add('keyEnv is not an environment variable name') }
    elseif ($keyEnv -in @('DEVIN_API_KEY', 'DEVIN_API_TOKEN', 'DEVIN_SERVICE_USER_TOKEN', 'DEVIN_ORG_ID')) { $errors.Add("keyEnv $keyEnv is stripped for the local CLI login") }
    # op read rejects '&' in a secret reference ("invalid character in secret
    # reference"), so a reference built from a vault name like "Business & Apps"
    # never resolves; use vault and item ids.
    if ([string]$Authorization.keyOpRef -notmatch '^op://[^/&]+/[^/&]+/[^/&]+$') { $errors.Add('keyOpRef is not an op://vault/item/field reference op read can parse') }
    if ([string]$Authorization.apiBase -notmatch '^https://[^/\s]+(/\S*)?$') { $errors.Add('apiBase is not an https URL') }
    return $errors
}

function Get-OwnerDispatchPolicyViolations($Policy) {
    $violations = [Collections.Generic.List[string]]::new()
    # 2026-10-23 restricted dispatch to Cursor, Grok and Codex; 2026-10-26 the
    # owner re-admitted OpenCode, then Cline, as execution peers (fleet-profile ownerDirection),
    # and the same day admitted Warp for local runs only, then Factory Droid (allowlisted
    # models, medium autonomy, runtime permission rules), then Devin for local runs only.
    # 2026-11-05 the owner directed that a host which works should not stay disabled, so
    # Amp, Antigravity, Copilot and Claude were admitted on their recorded smokes. That
    # direction does not reach a surface whose own reason prohibits hosted cloud execution,
    # an inactive host, or one with an uncaptured response; those stay out and are pinned
    # below, because "nothing should be disabled" is not a budget authorization.
    # 2026-11-19 (SH-4969) the owner authorized Devin Cloud and its API with a recorded
    # budget, so devin-cloud joins the list; the cloud-surface guard below still has
    # to clear on its cloudBudgetAuthorization.
    # Warp was decommissioned 2026-11-19 (docs/fleet/retired-hosts-2026-10-21.md): it was
    # uninstalled and moved to inactiveAgents, so it left the owner-authorized list; its
    # dispatch policy record must stay disabled and is pinned below beside windsurf.
    $authorized = @('cursor', 'cursor-agent', 'grok', 'codex', 'opencode', 'cline', 'factory', 'devin',
        'amp', 'antigravity', 'copilot', 'claude', 'kilo', 'mimo-code', 'qwen', 'devin-cloud')
    foreach ($id in $authorized) {
        if ($Policy.PSObject.Properties.Name -notcontains $id) { $violations.Add("Authorized host $id has no dispatch policy") }
    }
    foreach ($entry in $Policy.PSObject.Properties) {
        if ($entry.Value.enabled -isnot [bool]) {
            $violations.Add("$($entry.Name) must declare an explicit dispatch enabled boolean")
        } elseif ($entry.Name -notin $authorized -and $entry.Value.enabled -ne $false) {
            $violations.Add("$($entry.Name) dispatch is enabled but is not in the owner-authorized host list")
        }
    }
    foreach ($id in @('cursor', 'cursor-agent', 'grok', 'amp', 'antigravity', 'copilot', 'claude')) {
        if ($Policy.PSObject.Properties[$id].Value.enabled -ne $true) { $violations.Add("Authorized verified host $id must remain enabled") }
    }

    # A hosted cloud surface stays disabled until it carries a well-formed budget
    # authorization (Get-CloudBudgetAuthorizationViolations). A surface is a cloud
    # surface when it is one of the four known ones or when its own reason
    # prohibits hosted cloud execution; matching on the reason means a new cloud
    # surface arrives already guarded instead of needing this test edited first,
    # and the name list keeps the guard on a surface whose reason was rewritten
    # when it was enabled (devin-cloud, 2026-11-19).
    $cloudSurfaces = @('devin-cloud', 'jules', 'cursor-cloud', 'copilot-agent')
    foreach ($entry in $Policy.PSObject.Properties) {
        if ($entry.Name -notin $cloudSurfaces -and [string]$entry.Value.reason -notmatch 'Hosted cloud execution is prohibited') { continue }
        if ($entry.Value.enabled -eq $false) { continue }
        $authorization = if ($entry.Value.PSObject.Properties['cloudBudgetAuthorization']) { $entry.Value.cloudBudgetAuthorization } else { $null }
        $authorizationErrors = @(Get-CloudBudgetAuthorizationViolations $authorization)
        if ($authorizationErrors.Count -gt 0) {
            $violations.Add("$($entry.Name) is a hosted cloud surface and records no well-formed cloudBudgetAuthorization, so it must stay disabled ($($authorizationErrors -join ', '))")
        }
    }

    # Windsurf is an inactive agent on the high-cost Lightning tier, which is the
    # tier the Devin guard exists to keep out of an allowlist.
    if (($Policy.PSObject.Properties.Name -contains 'windsurf') -and $Policy.windsurf.enabled -ne $false) {
        $violations.Add('windsurf must stay disabled while registry/agents.json lists it as an inactive agent')
    }
    # Warp was decommissioned 2026-11-19 (docs/fleet/retired-hosts-2026-10-21.md); its
    # policy record is retained as history and must stay disabled while it is inactive.
    if (($Policy.PSObject.Properties.Name -contains 'warp') -and $Policy.warp.enabled -ne $false) {
        $violations.Add('warp must stay disabled while registry/agents.json lists it as an inactive, retired agent')
    }
    return $violations
}

# Codex is the evidence-gated host: an enabled policy must record a successful
# response capture (verifiedOn plus a reason naming it); a disabled one stays
# valid while it carries a reason. Neither state is assumed from a stale rule.
function Get-CodexDispatchEvidenceViolations($CodexPolicy) {
    $violations = [Collections.Generic.List[string]]::new()
    if ($null -eq $CodexPolicy) { $violations.Add('codex has no dispatch policy'); return $violations }
    if ($CodexPolicy.enabled -eq $true) {
        if ([string]::IsNullOrWhiteSpace([string]$CodexPolicy.verifiedOn) -or
            [string]$CodexPolicy.reason -notmatch 'captured a response') {
            $violations.Add('Enabled Codex dispatch must record response-capture evidence: a verifiedOn date plus a reason naming the captured response')
        }
    } elseif ([string]::IsNullOrWhiteSpace([string]$CodexPolicy.reason)) {
        $violations.Add('Disabled Codex dispatch must record its reason')
    }
    return $violations
}

function Test-LiveHostAuthenticationMetadata {
    $profile = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($entry in $profile.hostSettings.PSObject.Properties) {
        if ($entry.Value.authMode -notin @('account', 'apiKey')) {
            $violations.Add("$($entry.Name) has no valid authMode")
        }
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value.loginCommand)) {
            $violations.Add("$($entry.Name) has no loginCommand")
        }
    }
    $dispatchHosts = @('claude', 'codex', 'cursor-agent', 'grok', 'opencode', 'antigravity', 'factory', 'cline', 'copilot', 'amp', 'devin', 'windsurf', 'kilo', 'mimo-code', 'qwen')
    foreach ($id in $dispatchHosts) {
        if ($profile.hostSettings.PSObject.Properties.Name -notcontains $id) {
            $violations.Add("$id has no hostSettings authentication record")
        }
    }
    # Gemini CLI was retired on 2026-11-10 (docs/fleet/retired-hosts-2026-10-21.md).
    if ($profile.hostSettings.PSObject.Properties.Name -contains 'gemini' -or
        $profile.dispatchPolicy.PSObject.Properties.Name -contains 'gemini') {
        $violations.Add('Gemini CLI is retired and must have no hostSettings or dispatchPolicy record')
    }
    foreach ($violation in @(Get-OwnerDispatchPolicyViolations $profile.dispatchPolicy)) { $violations.Add($violation) }
    $openCode = $profile.dispatchPolicy.opencode
    # 2026-11-14 (SH-4674): hostSettings.opencode.model/smallModel are the plan-based host defaults
    # deployed into opencode.json (qwen-token-plan), while the unattended dispatcher default in
    # dispatchPolicy.opencode.model stays the OpenCode Go subscription. The two are deliberately not
    # equal anymore; both must remain smoke-verified allowedModels entries and never opencode/
    # (Zen wallet) pay-as-you-go ids.
    $openCodeHostDefaults = @([string]$profile.hostSettings.opencode.model, [string]$profile.hostSettings.opencode.smallModel)
    if ($openCode.enabled -ne $true -or
        $profile.hostSettings.opencode.authMode -ne 'account' -or
        $openCode.model -ne 'opencode-go/glm-5.3-flash' -or
        @($openCode.allowedModels | Where-Object { [string]$_ -like 'opencode/*' }).Count -gt 0 -or
        @($openCodeHostDefaults | Where-Object { $_ -like 'opencode/*' }).Count -gt 0 -or
        @($openCodeHostDefaults | Where-Object { @($openCode.allowedModels) -notcontains $_ }).Count -gt 0 -or
        $openCode.verifiedOn -ne '2026-10-26' -or
        @($openCode.allowedModels) -notcontains $openCode.model -or
        $openCode.agent -ne 'peer' -or
        $null -ne $openCode.ownerAction) {
        $violations.Add('OpenCode Go dispatch must keep its account login, the opencode-go dispatch default and the subscription-plan host defaults inside allowedModels with no opencode/ (Zen wallet) ids, and the outward-action-denying peer agent')
    }
    $factoryPolicy = $profile.dispatchPolicy.factory
    if ($factoryPolicy.enabled -eq $true -and (
        $profile.hostSettings.factory.authMode -ne 'account' -or
        @($factoryPolicy.allowedModels) -notcontains $factoryPolicy.model -or
        [string]$factoryPolicy.autonomy -notin @('low', 'medium') -or
        -not (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$factoryPolicy.runtimeSettings))))) {
        $violations.Add('Factory dispatch must stay on its account login at low or medium autonomy, with its default model inside allowedModels and a present runtime rules file')
    }
    # Devin: local runs on the account login with a free SWE-2 default; the
    # high-cost Lightning tier stays out of the recorded list. The local lane stays
    # local-only; cloud work is the separate devin-cloud surface, which the
    # cloud-surface guard in Get-OwnerDispatchPolicyViolations gates on its budget.
    $devinPolicy = $profile.dispatchPolicy.devin
    if ($devinPolicy.enabled -eq $true -and (
        $profile.hostSettings.devin.authMode -ne 'account' -or
        @($devinPolicy.allowedModels) -notcontains $devinPolicy.model -or
        $devinPolicy.model -notlike 'swe-2-*' -or
        @($devinPolicy.allowedModels | Where-Object { [string]$_ -like '*lightning*' }).Count -gt 0 -or
        [string]$devinPolicy.scope -notmatch '^local-only' -or
        [string]$devinPolicy.scope -notmatch 'devin-cloud')) {
        $violations.Add('Devin dispatch must stay local-only on its account login, with a free SWE-2 default inside allowedModels, no Lightning tier, and a scope that sends cloud work to devin-cloud')
    }
    if ($profile.hostSettings.cline.authMode -ne 'apiKey' -or
        $profile.hostSettings.cline.provider -ne 'openai-compatible' -or
        $profile.hostSettings.cline.model -ne 'qwen3.8-max-0902') {
        $violations.Add('Cline must retain the owner-authorized Alibaba Coding Plan provider settings')
    }
    # Every model on provider 'cline' except ':free' ids bills usage credit, and
    # the default dispatch model must itself be in the recorded list. The list
    # records verified models; it does not limit what -Model may name.
    $cline = $profile.dispatchPolicy.cline
    if ($cline.enabled -eq $true) {
        $clineModels = @($cline.allowedModels | ForEach-Object { [string]$_ })
        $paid = @($clineModels | Where-Object { $_ -like 'cline:*' -and $_ -notlike '*:free' })
        if ($clineModels.Count -eq 0 -or
            $clineModels -notcontains "$($profile.hostSettings.cline.provider):$($profile.hostSettings.cline.model)" -or
            $paid.Count -gt 0 -or
            @($clineModels | Where-Object { $_ -notmatch '^[a-z0-9-]+:.+' }).Count -gt 0) {
            $violations.Add('Cline dispatch must list provider:model allowedModels including its default, with only :free models on the usage-billed cline provider')
        }
    }
    foreach ($id in @('kilo', 'mimo-code')) {
        $planPolicy = $profile.dispatchPolicy.$id
        if ($planPolicy.enabled -eq $true -and (
            [string]$planPolicy.model -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.:/@+-]*$' -or
            @($planPolicy.allowedModels | ForEach-Object { [string]$_ }) -notcontains $planPolicy.model)) {
            $violations.Add("$id dispatch must keep a provider/model default inside allowedModels")
        }
        if ($planPolicy.enabled -eq $true -and [string]$planPolicy.agent -notmatch '^[A-Za-z0-9_-]+$') {
            $violations.Add("$id dispatch is enabled without a guarded agent; its auto-approve flag approves every action no rule denies")
        }
    }
    foreach ($violation in @(Get-CodexDispatchEvidenceViolations $profile.dispatchPolicy.codex)) { $violations.Add($violation) }
    $catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'registry/agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $activeManagedIds = @($catalog.activeAgents | Where-Object { $_.status -notin @('retired','inventory-only') } | ForEach-Object id)
    foreach ($id in $profile.managedHosts) {
        if ($id -notin $activeManagedIds) {
            $violations.Add("Managed profile host '$id' must be active in the host registry")
        }
    }
    if ($profile.managedHosts -notcontains 'cursor-agent') {
        $violations.Add('Cursor Agent CLI must be present in managedHosts')
    }
    $retiredMatches = foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'registry') -Filter '*.json' -File) {
        $contents = [IO.File]::ReadAllText($file.FullName)
        if ([regex]::IsMatch($contents, '"(?:qwen-code|hermes)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $file.Name
        }
    }
    if ($retiredMatches) {
        $violations.Add("Retired host ids remain in registry JSON: $($retiredMatches -join ', ')")
    }
    foreach ($id in @('cline', 'opencode')) {
        $settings = $profile.hostSettings.PSObject.Properties[$id].Value
        if ($settings.availableProviders.deepseek.apiKeyEnv -ne 'DEEPSEEK_API_KEY') {
            $violations.Add("$id lost its configured DeepSeek secondary provider")
        }
        if ($settings.availableProviders.deepseek.PSObject.Properties.Name -contains 'userScopeSet') {
            $violations.Add("$id exposes local credential state in the public registry")
        }
    }
    if ($violations.Count -gt 0) {
        return @{ Passed = $false; Detail = ($violations -join '; ') }
    }
    return @{ Passed = $true; Detail = $null }
}

function Test-OwnerDispatchPolicyRejectsUnauthorizedChanges {
    $profile = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@(Get-OwnerDispatchPolicyViolations $profile.dispatchPolicy).Count -ne 0) {
        return @{Passed=$false;Detail='Current authorized policy, including gated Codex, was rejected'}
    }
    foreach ($id in @('gemini', 'windsurf', 'new-unapproved-host')) {
        $policy = $profile.dispatchPolicy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $policy | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{enabled=$true}) -Force
        if ((@(Get-OwnerDispatchPolicyViolations $policy) -join ';') -notmatch [regex]::Escape($id)) {
            return @{Passed=$false;Detail="Unauthorized $id dispatch was accepted"}
        }
    }

    # Enabling a surface that prohibits hosted cloud execution must be rejected on
    # the reason it records, and the budget field must clear that specific charge.
    # It deliberately does not clear the authorized-list charge, so enabling cloud
    # execution needs two visible edits: add the host to $authorized and record a
    # cloudBudgetAuthorization. Asserting both halves is what proves the guard is
    # a real gate rather than an unconditional refusal.
    $cloudCharge = 'jules is a hosted cloud surface and records no well-formed cloudBudgetAuthorization'
    $policy = $profile.dispatchPolicy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $policy.jules.enabled = $true
    $seen = @(Get-OwnerDispatchPolicyViolations $policy) -join ';'
    if ($seen -notmatch [regex]::Escape($cloudCharge)) {
        return @{Passed=$false;Detail='Enabling jules raised no cloud-execution charge'}
    }
    # A free-text note is not a budget: it names no cap, key or date.
    $policy.jules | Add-Member -NotePropertyName cloudBudgetAuthorization -NotePropertyValue 'fixture authorization' -Force
    $seen = @(Get-OwnerDispatchPolicyViolations $policy) -join ';'
    if ($seen -notmatch [regex]::Escape($cloudCharge)) {
        return @{Passed=$false;Detail='A free-text cloudBudgetAuthorization cleared the cloud-execution charge'}
    }
    $fixtureAuthorization = [pscustomobject]@{
        date = '2026-01-01'; ownerQuotes = @('fixture owner quote'); defaultMaxAcuLimit = 1; maxConcurrentSessions = 1
        keyType = 'fixture'; keyEnv = 'JULES_FIXTURE_KEY'; keyOpRef = 'op://Fixture/Jules/credential'; orgId = 'fixture-org'; apiBase = 'https://jules.example/v1'
    }
    $policy.jules.cloudBudgetAuthorization = $fixtureAuthorization
    $seen = @(Get-OwnerDispatchPolicyViolations $policy) -join ';'
    if ($seen -match [regex]::Escape($cloudCharge)) {
        return @{Passed=$false;Detail='A well-formed cloudBudgetAuthorization did not clear the cloud-execution charge'}
    }
    if ($seen -notmatch 'jules') {
        return @{Passed=$false;Detail='A cloud budget alone enabled jules; the authorized-list charge must still apply'}
    }

    $policy = $profile.dispatchPolicy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $policy.grok.enabled = $false
    $policy.amp.enabled = $null
    $policy.claude.enabled = $false
    $policy.PSObject.Properties.Remove('codex')
    $violations = @(Get-OwnerDispatchPolicyViolations $policy) -join ';'
    foreach ($id in @('grok','amp','claude','codex')) {
        if ($violations -notmatch $id) { return @{Passed=$false;Detail="Missing/invalid authorized-policy guard for $id"} }
    }
    return @{Passed=$true;Detail=$null}
}

$r1 = Test-CollectorFlagsUnknownHostId
Report 'an unresolved hostId (hostId property or bare hosts[] string) is flagged by name' $r1.Passed $r1.Detail

$r2 = Test-CollectorAcceptsKnownHostIdsAndSurfaceAliases
Report 'a real agent id and a declared surface alias id both resolve with zero false positives' $r2.Passed $r2.Detail

$r3 = Test-LiveRegistryHostReferencesAllResolve
Report 'every hostId reference in the live registry (capabilities/mcps/native-connectors/gateway-profiles/fleet-profile) resolves against agents.json' $r3.Passed $r3.Detail

$r4 = Test-CanonicalSourceMissingOnDiskIsFlagged
Report 'a capability whose canonicalSource is missing on disk is flagged by id' $r4.Passed $r4.Detail

$r5 = Test-LiveCapabilitiesCanonicalSourcesAllExistOnDisk
Report 'every live capability canonicalSource exists on disk' $r5.Passed $r5.Detail

$r6 = Test-LiveHostAuthenticationMetadata
Report 'dispatch hosts have auth records; retired ids are absent and unverified paid routes remain gated' $r6.Passed $r6.Detail

function Test-CodexEvidenceGateRejectsStrippedEvidence {
    $profile = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@(Get-CodexDispatchEvidenceViolations $profile.dispatchPolicy.codex).Count -ne 0) {
        return @{ Passed = $false; Detail = 'the live Codex policy failed its own evidence gate' }
    }
    $stripped = $profile.dispatchPolicy.codex | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $stripped.PSObject.Properties.Remove('verifiedOn')
    $stripped.PSObject.Properties.Remove('reason')
    if (@(Get-CodexDispatchEvidenceViolations $stripped).Count -eq 0) {
        return @{ Passed = $false; Detail = 'an enabled Codex policy with its response-capture evidence removed was accepted' }
    }
    if (@(Get-CodexDispatchEvidenceViolations ([pscustomobject]@{ enabled = $false; reason = 'response capture is not verified' })).Count -ne 0) {
        return @{ Passed = $false; Detail = 'a disabled Codex policy with a recorded reason was rejected' }
    }
    if (@(Get-CodexDispatchEvidenceViolations ([pscustomobject]@{ enabled = $false })).Count -eq 0) {
        return @{ Passed = $false; Detail = 'a disabled Codex policy with no reason was accepted' }
    }
    return @{ Passed = $true; Detail = $null }
}

# SH-4969 (owner direction 2026-11-19): Devin Cloud is enabled under a recorded
# budget. The live record must carry the owner's exact values, and stripping or
# malforming any part of it must re-arm the cloud-execution charge.
function Test-DevinCloudBudgetGate {
    $profile = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cloud = $profile.dispatchPolicy.'devin-cloud'
    if ($cloud.enabled -ne $true) { return @{ Passed = $false; Detail = 'dispatchPolicy.devin-cloud is not enabled' } }
    $auth = $cloud.cloudBudgetAuthorization
    $authErrors = @(Get-CloudBudgetAuthorizationViolations $auth)
    if ($authErrors.Count -ne 0) { return @{ Passed = $false; Detail = "live devin-cloud authorization is malformed: $($authErrors -join '; ')" } }
    $expected = [ordered]@{
        date = '2026-11-19'; defaultMaxAcuLimit = 10; maxConcurrentSessions = 3; keyType = 'org-service-user'
        keyEnv = 'DEVIN_CLOUD_API_KEY'; keyOpRef = 'op://d4yvwfzjsyw4x6mymqjjfcxcoe/ovdhltjbi4cfjnjaf573brqsty/credential'
        orgId = 'org-d986482cea0c49689c6c9a590ecbdf7b'; apiBase = 'https://api.devin.ai/v3'
        serviceUser = 'agenthub-dispatch'; serviceUserRole = 'Member'; keyExpiresOn = '2027-02-17'
    }
    foreach ($name in $expected.Keys) {
        if ([string]$auth.$name -ne [string]$expected[$name]) { return @{ Passed = $false; Detail = "cloudBudgetAuthorization.$name is '$($auth.$name)', expected '$($expected[$name])'" } }
    }
    $quotes = @($auth.ownerQuotes) -join ' | '
    if ($quotes -notmatch 'Devin cloud and api are OK now' -or $quotes -notmatch 'first class agent from now') {
        return @{ Passed = $false; Detail = 'cloudBudgetAuthorization.ownerQuotes does not carry the 2026-11-19 owner direction' }
    }
    $surface = @($profile.hostSurfaces.surfaces | Where-Object { $_.surfaceId -eq 'devin-cloud' })
    if ($surface.Count -ne 1 -or [string]$surface[0].hostId -ne 'devin') {
        return @{ Passed = $false; Detail = 'hostSurfaces has no single devin-cloud surface owned by host devin' }
    }
    if (@(Get-OwnerDispatchPolicyViolations $profile.dispatchPolicy).Count -ne 0) {
        return @{ Passed = $false; Detail = "live policy with devin-cloud enabled was rejected: $(@(Get-OwnerDispatchPolicyViolations $profile.dispatchPolicy) -join '; ')" }
    }
    $cloudCharge = 'records no well-formed cloudBudgetAuthorization'
    $cases = [ordered]@{
        'authorization removed' = { param($p) $p.'devin-cloud'.PSObject.Properties.Remove('cloudBudgetAuthorization') }
        'authorization as a bare string' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization = 'owner said ok' }
        'zero ACU cap' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.defaultMaxAcuLimit = 0 }
        'no concurrency cap' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.PSObject.Properties.Remove('maxConcurrentSessions') }
        'key env shared with the local CLI login' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.keyEnv = 'DEVIN_API_KEY' }
        'key reference outside 1Password' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.keyOpRef = 'C:\keys\devin.txt' }
        'key reference op read cannot parse' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.keyOpRef = 'op://Business & Apps/Devin Cloud API service user/credential' }
        'plain-http API base' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.apiBase = 'http://api.devin.ai/v3' }
        'no owner quote' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.ownerQuotes = @() }
        'undated' = { param($p) $p.'devin-cloud'.cloudBudgetAuthorization.date = 'recently' }
    }
    foreach ($case in $cases.GetEnumerator()) {
        $policy = $profile.dispatchPolicy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        & $case.Value $policy
        $seen = @(Get-OwnerDispatchPolicyViolations $policy) -join ';'
        if ($seen -notmatch [regex]::Escape("devin-cloud is a hosted cloud surface and $cloudCharge")) {
            return @{ Passed = $false; Detail = "devin-cloud stayed accepted with $($case.Key)" }
        }
    }
    return @{ Passed = $true; Detail = $null }
}

$r7 = Test-OwnerDispatchPolicyRejectsUnauthorizedChanges
Report 'owner dispatch whitelist rejects unauthorized hosts and missing or invalid policy entries' $r7.Passed $r7.Detail

$r8 = Test-CodexEvidenceGateRejectsStrippedEvidence
Report 'codex dispatch is gated on recorded response-capture evidence, enabled or disabled' $r8.Passed $r8.Detail

$r9 = Test-DevinCloudBudgetGate
Report 'devin-cloud is enabled exactly while it carries the well-formed 2026-11-19 cloud budget authorization' $r9.Passed $r9.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
