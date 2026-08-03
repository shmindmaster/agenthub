#Requires -Version 5.1
<#
.SYNOPSIS
    Translates every capability's canonical agents/*.agent.md files into each
    target host's native subagent format, and syncs them into that host's
    documented destination. Capability-generic: no capability id or name
    appears anywhere in this script.

.DESCRIPTION
    Replaces the deleted scripts/Sync-ProductDemoStudioHostAdapters.ps1
    (git show fc1bda6f6fb8a1476603c263c03107f70024738f), which was hardcoded
    to exactly one capability (product-demo-studio) and had zero overwrite
    protection, zero dry-run, and a naive comma-split tools: parser that
    silently mis-translated a YAML flow-sequence. See
    .superpowers/sdd/control-plane-restore-plan/research/defect-audit.md
    (defects C3/C4/C5) and task-5-brief.md for the full defect list.

    Iterates every capability in registry/capabilities.json whose
    <canonicalSource>/agents directory exists and contains at least one
    *.agent.md file -- a capability without one is skipped cleanly, never
    treated as an error. For each such capability's agents, generates
    per-host subagent files for exactly the 4 hosts documented in
    registry/subagent-formats.json (codex, opencode, gemini, antigravity --
    the same 4 the deleted generator served; see that file's header note for
    why no other host is in scope). Destination roots are built entirely
    from the resolved -UserProfile parameter plus registry-declared
    templates -- this script never reads an absolute destination path baked
    into a registry file, which is the exact hazard class documented in
    task-2-report.md's "Safety incident" (Sync-Instructions.ps1 has to
    rebase registry-baked absolute paths under -UserProfile; this script has
    no such baked path to rebase in the first place).

    A destination that exists but does not structurally resemble this
    generator's own output format ("shape check" -- e.g. a Codex agent file
    must contain both `name = "` and `developer_instructions = """`) is
    reported 'unmanaged' and is never written. This deliberately does NOT
    reuse Sync-Instructions.ps1's literal `<!-- agenthub:managed -->` HTML
    comment marker: TOML/YAML have no HTML comment syntax, and more
    importantly, embedding ANY marker string into the rendered content would
    make it impossible for the 13 real, pre-existing Codex/OpenCode files
    (generated 2026-07-31 by the deleted script, with no marker of any kind)
    to ever audit as 'current' -- which is the explicit, required fidelity
    check for this task. The structural shape check is the format-agnostic
    equivalent: it still refuses to overwrite content this generator does
    not recognize as its own, while allowing byte-identical legacy output,
    and legitimate drift caused by an upstream canonical-source edit, to be
    correctly classified as 'current'/'drift' rather than falsely refused.
    See task-5-report.md for the full design rationale.

    A host whose root config directory does not exist (e.g. no ~/.codex at
    all) is reported 'skipped (host not installed)' and never has a
    directory tree created for it -- this script only ever fills in the
    deeper agents/extension subdirectory for a host that is already present.

.PARAMETER Audit
    Report per-(capability, host, agent) drift without writing any
    destination. Default mode.

.PARAMETER Apply
    Write destinations that are 'missing' or 'drift'. Never writes an
    'unmanaged' destination or a host reported 'skipped (host not
    installed)'.

.PARAMETER RepositoryRoot
    Repository root to read registry/capabilities.json,
    registry/subagent-formats.json, and every capability's agents/ directory
    from. Self-derived from this script's own path when omitted.

.PARAMETER UserProfile
    User-profile root whose native destinations are audited/written.
    Defaults to $env:USERPROFILE.
#>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [string]$RepositoryRoot,
    [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

if ($Apply -and $Audit) {
    throw "Specify only one of -Audit or -Apply, not both."
}
if (-not $Apply) { $Audit = $true }

# ---------------------------------------------------------------------------
# Path resolution -- self-derived, never hardcoded to one checkout.
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')

if ([string]::IsNullOrWhiteSpace($UserProfile)) {
    throw "Could not resolve a user profile directory. Pass -UserProfile explicitly."
}
$UserProfile = [System.IO.Path]::GetFullPath($UserProfile).TrimEnd('\')

$RegistryDir           = Join-Path $RepositoryRoot 'registry'
$CapabilitiesFile      = Join-Path $RegistryDir 'capabilities.json'
$SubagentFormatsFile   = Join-Path $RegistryDir 'subagent-formats.json'

foreach ($required in @($CapabilitiesFile, $SubagentFormatsFile)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required registry file: $required"
    }
}

$capabilitiesReg = Get-Content -LiteralPath $CapabilitiesFile -Raw -Encoding UTF8 | ConvertFrom-Json
$formatsReg      = Get-Content -LiteralPath $SubagentFormatsFile -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $capabilitiesReg.PSObject.Properties['capabilities'] -or @($capabilitiesReg.capabilities).Count -eq 0) {
    throw "Registry '$CapabilitiesFile' declares zero capabilities. Refusing to report success against what looks like an empty or wrong registry tree."
}
if (-not $formatsReg.PSObject.Properties['hosts'] -or @($formatsReg.hosts).Count -eq 0) {
    throw "Registry '$SubagentFormatsFile' declares zero target hosts."
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Expand-DestinationTemplate {
    param([string]$Template, [string]$CapabilityId)
    if ([string]::IsNullOrWhiteSpace($Template)) { return $null }
    return $Template.Replace('{userProfile}', $UserProfile).Replace('{capabilityId}', $CapabilityId)
}

function ConvertTo-DisplayName {
    param([string]$Id)
    $words = @($Id -split '-' | Where-Object { $_ })
    $titled = @($words | ForEach-Object {
        if ($_.Length -le 1) { $_.ToUpperInvariant() }
        else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    })
    return ($titled -join ' ')
}

function ConvertTo-TomlString {
    param([string]$Value)
    return ($Value | ConvertTo-Json -Compress)
}

# ---------------------------------------------------------------------------
# Capability discovery -- capability-generic. No capability id appears as a
# literal anywhere in this script; every capability in registry/
# capabilities.json whose <canonicalSource>/agents directory exists and
# contains at least one *.agent.md file is picked up automatically. A
# capability without one (the majority -- clerk, framer, campaign-production,
# etc.) is skipped cleanly, not treated as an error.
# ---------------------------------------------------------------------------
function Get-EligibleCapabilities {
    param($CapabilitiesReg, [string]$RepoRoot)
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($cap in $CapabilitiesReg.capabilities) {
        $capId = [string]$cap.id
        $canonicalSource = [string]$cap.canonicalSource
        if ([string]::IsNullOrWhiteSpace($canonicalSource)) { continue }
        $packageRoot = Join-Path $RepoRoot ($canonicalSource -replace '/', '\')
        $agentsDir = Join-Path $packageRoot 'agents'
        if (-not (Test-Path -LiteralPath $agentsDir -PathType Container)) { continue }
        $agentFiles = @(Get-ChildItem -LiteralPath $agentsDir -Filter '*.agent.md' -File | Sort-Object Name)
        if ($agentFiles.Count -eq 0) { continue }

        $manifestPath = Join-Path $packageRoot '.codex-plugin\plugin.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Capability '$capId' has an agents/ directory ($agentsDir) but no .codex-plugin\plugin.json manifest to read a version from ($manifestPath). Refusing to guess a version."
        }
        $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $version = [string]$manifestJson.version
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "Capability '$capId' manifest has no version: $manifestPath"
        }

        $result.Add([pscustomobject]@{
            Id          = $capId
            DisplayName = ConvertTo-DisplayName $capId
            AgentsDir   = $agentsDir
            Version     = $version
            AgentFiles  = $agentFiles
        })
    }
    return $result
}

# ---------------------------------------------------------------------------
# Canonical agent frontmatter parser. Deliberately NOT a naive comma-split
# on the raw regex-captured value (the confirmed defect, C4): a tools: value
# that starts with '[' (a YAML flow-sequence, e.g. "tools: [Read, Grep]")
# is refused with a clear, actionable error rather than silently split into
# stray-bracket tokens ("[Read", "Grep]") that would match nothing in any
# host's tool-name map. Today's 17 canonical files all use the scalar
# comma-list dialect (commit 6e1876f normalized product-experience-
# engineering's 4), but nothing in the registry enforces that for a future
# capability, so this check must stay live.
# ---------------------------------------------------------------------------
function Read-CanonicalAgent {
    param([string]$Path)
    $content = [System.IO.File]::ReadAllText($Path)
    $match = [regex]::Match(
        $content,
        '\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n(?<body>[\s\S]*)\z',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $match.Success) {
        throw "Invalid canonical agent frontmatter (expected a leading --- ... --- block): $Path"
    }
    $frontmatter = $match.Groups['frontmatter'].Value

    $name = [regex]::Match($frontmatter, '(?m)^name:\s*(?<value>.+?)\s*$').Groups['value'].Value
    $description = [regex]::Match($frontmatter, '(?m)^description:\s*(?<value>.+?)\s*$').Groups['value'].Value
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($description)) {
        throw "Canonical agent lacks name or description: $Path"
    }

    $tools = @()
    $toolsMatch = [regex]::Match($frontmatter, '(?m)^tools:\s*(?<value>.+?)\s*$')
    if ($toolsMatch.Success) {
        $rawToolsValue = $toolsMatch.Groups['value'].Value.Trim()
        if ($rawToolsValue.StartsWith('[')) {
            throw "Canonical agent '$name' ($Path) declares tools: as a YAML flow-sequence ('$rawToolsValue'). This parser only supports the scalar comma-list dialect (tools: A, B, C) that all 17 canonical agents use today. Normalize the source file before generating subagents -- refusing to guess and silently mis-split the brackets into stray tokens, which is the exact defect (C4) this generator exists to eliminate."
        }
        if (-not [string]::IsNullOrWhiteSpace($rawToolsValue)) {
            $tools = @($rawToolsValue -split '\s*,\s*' | Where-Object { $_ })
        }
    }

    $readOnly = [regex]::IsMatch($frontmatter, '(?m)^readonly:\s*true\s*$')

    return [pscustomobject]@{
        Name        = $name
        Description = $description
        Tools       = $tools
        ReadOnly    = $readOnly
        Body        = $match.Groups['body'].Value.Trim()
        SourcePath  = $Path
    }
}

# ---------------------------------------------------------------------------
# Tool-name translation. A tool with no entry in a host's toolMap is dropped
# from that host's list (matching the deleted generator's own behavior --
# neither Gemini nor Antigravity has a documented, verified tool name for
# every possible canonical tool, e.g. WebSearch/WebFetch; AGENTS.md forbids
# inventing an unverified host-native tool name), but -- unlike the deleted
# generator (defect #7, silent drop) -- every drop is surfaced as a visible
# Unmapped entry, printed as a NOTE line and included in the audit table.
# ---------------------------------------------------------------------------
function Get-MappedTools {
    param([string[]]$Tools, $ToolMapObj)
    if (-not $ToolMapObj) { return [pscustomobject]@{ Mapped = @(); Unmapped = @() } }
    $mapped = New-Object System.Collections.Generic.List[string]
    $unmapped = New-Object System.Collections.Generic.List[string]
    foreach ($t in $Tools) {
        $prop = $ToolMapObj.PSObject.Properties[$t]
        if ($prop) { $mapped.Add([string]$prop.Value) } else { $unmapped.Add($t) }
    }
    return [pscustomobject]@{
        Mapped   = @($mapped | Sort-Object -Unique)
        Unmapped = @($unmapped)
    }
}

# ---------------------------------------------------------------------------
# Per-host renderers. Four genuinely different serialization dialects (TOML,
# three mutually-incompatible YAML-frontmatter shapes) -- this is inherent
# to the target formats, not capability-specific branching. Which renderer
# applies to which host is selected generically via $formatsReg.hosts[].format
# (registry data), never by comparing a host id against a capability name.
# ---------------------------------------------------------------------------
function Get-CodexTomlContent {
    param($RuntimeName, $Agent)
    $lines = @(
        "name = $(ConvertTo-TomlString $RuntimeName)",
        "description = $(ConvertTo-TomlString $Agent.Description)"
    )
    if ($Agent.ReadOnly) { $lines += 'sandbox_mode = "read-only"' }
    $lines += @('developer_instructions = """', $Agent.Body, '"""')
    return [pscustomobject]@{ Content = (($lines -join "`n") + "`n"); Unmapped = @() }
}

function Get-OpenCodeMdContent {
    param($RuntimeName, $Agent)
    $fm = @('---', "description: $($Agent.Description)", 'mode: subagent')
    if ($Agent.ReadOnly) {
        $fm += @('permission:', '  edit: deny', '  bash: deny', '  task: deny')
    }
    $fm += '---'
    return [pscustomobject]@{ Content = (($fm + '', $Agent.Body) -join "`n"); Unmapped = @() }
}

function Get-GeminiMdContent {
    param($RuntimeName, $Agent, $ToolMap)
    $mapped = Get-MappedTools -Tools $Agent.Tools -ToolMapObj $ToolMap
    $fm = @('---', "name: $RuntimeName", "description: $($Agent.Description)", 'kind: local', 'tools:') +
        @($mapped.Mapped | ForEach-Object { "  - $_" }) +
        @('model: inherit', 'max_turns: 30', '---')
    return [pscustomobject]@{ Content = (($fm + '', $Agent.Body) -join "`n"); Unmapped = $mapped.Unmapped }
}

function Get-AntigravityMdContent {
    param($RuntimeName, $Agent, $ToolMap)
    $mapped = Get-MappedTools -Tools $Agent.Tools -ToolMapObj $ToolMap
    $policy = if ($Agent.ReadOnly) { 'off' } else { 'sandbox' }
    $fm = @('---', "name: $RuntimeName", "description: $($Agent.Description)", 'tools:') +
        @($mapped.Mapped | ForEach-Object { "  - $_" }) +
        @('subagent: true', 'mainAgent: false', 'model: inherit', "commandExecutionPolicy: $policy", '---')
    return [pscustomobject]@{ Content = (($fm + '', $Agent.Body) -join "`n"); Unmapped = $mapped.Unmapped }
}

function Get-RenderedSubagent {
    param([string]$Format, [string]$RuntimeName, $Agent, $ToolMap)
    switch ($Format) {
        'codex-toml'     { return Get-CodexTomlContent -RuntimeName $RuntimeName -Agent $Agent }
        'opencode-md'    { return Get-OpenCodeMdContent -RuntimeName $RuntimeName -Agent $Agent }
        'gemini-md'      { return Get-GeminiMdContent -RuntimeName $RuntimeName -Agent $Agent -ToolMap $ToolMap }
        'antigravity-md' { return Get-AntigravityMdContent -RuntimeName $RuntimeName -Agent $Agent -ToolMap $ToolMap }
        default { throw "Unknown subagent format '$Format' declared in $SubagentFormatsFile." }
    }
}

# ---------------------------------------------------------------------------
# Structural "managed" shape checks -- see the .DESCRIPTION comment above for
# why this replaces a literal embedded marker string for this generator.
# ---------------------------------------------------------------------------
function Test-CodexTomlShape { param([string]$Content) return ($Content -match '(?m)^name\s*=\s*"' -and $Content -match '(?m)^developer_instructions\s*=\s*"""') }
function Test-OpenCodeMdShape { param([string]$Content) return ($Content.TrimStart().StartsWith('---') -and $Content -match '(?m)^description:\s') }
function Test-GeminiMdShape { param([string]$Content) return ($Content.TrimStart().StartsWith('---') -and $Content -match '(?m)^kind:\s*local\s*$') }
function Test-AntigravityMdShape { param([string]$Content) return ($Content.TrimStart().StartsWith('---') -and $Content -match '(?m)^commandExecutionPolicy:\s') }
function Test-ManifestShape {
    param([string]$Content)
    try {
        $obj = $Content | ConvertFrom-Json
        return [bool]($obj.PSObject.Properties['name'])
    } catch { return $false }
}

function Test-SubagentShape {
    param([string]$Format, [string]$Content)
    switch ($Format) {
        'codex-toml'     { return Test-CodexTomlShape -Content $Content }
        'opencode-md'    { return Test-OpenCodeMdShape -Content $Content }
        'gemini-md'      { return Test-GeminiMdShape -Content $Content }
        'antigravity-md' { return Test-AntigravityMdShape -Content $Content }
        default { return $false }
    }
}

# ---------------------------------------------------------------------------
# Manifest content (Gemini extension / Antigravity plugin wrapper). Built by
# hand rather than ConvertTo-Json: PowerShell 5.1's ConvertTo-Json emits a
# different indent/spacing style ("  \"name\":  \"x\"", 4-space, double
# space after colon) than PowerShell 7's ("  \"name\": \"x\"", 2-space,
# single space -- confirmed by comparing both against the real deployed
# gemini-extension.json, which matches pwsh's style, proving the original
# generator ran under pwsh). Relying on ConvertTo-Json here would make this
# script's manifest output depend on which shell ran it, violating "both
# shells produce the same result."
# ---------------------------------------------------------------------------
function Get-GeminiManifestContent {
    param($Capability)
    $desc = "AgentHub-managed $($Capability.DisplayName) subagents; skills and MCP remain centrally distributed."
    return "{`n" +
        "  ""name"": $(ConvertTo-TomlString "agenthub-$($Capability.Id)"),`n" +
        "  ""version"": $(ConvertTo-TomlString $Capability.Version),`n" +
        "  ""description"": $(ConvertTo-TomlString $desc)`n" +
        "}`n"
}

function Get-AntigravityManifestContent {
    param($Capability)
    $desc = "AgentHub-managed $($Capability.DisplayName) subagents; skills and MCP remain centrally distributed."
    return "{`n" +
        "  ""`$schema"": ""https://antigravity.google/schemas/v1/plugin.json"",`n" +
        "  ""name"": $(ConvertTo-TomlString $Capability.Id),`n" +
        "  ""description"": $(ConvertTo-TomlString $desc)`n" +
        "}`n"
}

function Get-RenderedManifest {
    param([string]$ManifestKind, $Capability)
    switch ($ManifestKind) {
        'gemini-extension'   { return Get-GeminiManifestContent -Capability $Capability }
        'antigravity-plugin' { return Get-AntigravityManifestContent -Capability $Capability }
        default { return $null }
    }
}

# ---------------------------------------------------------------------------
# State classification, shared by subagent files and manifest files.
# ---------------------------------------------------------------------------
function Get-DestinationState {
    param([string]$DestinationPath, [string]$ExpectedContent, [string]$Format, [bool]$IsManifest)
    if (-not (Test-Path -LiteralPath $DestinationPath)) { return 'missing' }
    $existing = [System.IO.File]::ReadAllText($DestinationPath)
    if ($existing -ceq $ExpectedContent) { return 'current' }
    $shapeOk = if ($IsManifest) { Test-ManifestShape -Content $existing } else { Test-SubagentShape -Format $Format -Content $existing }
    if ($shapeOk) { return 'drift' }
    return 'unmanaged'
}

# ---------------------------------------------------------------------------
# Capability + agent discovery
# ---------------------------------------------------------------------------
$capabilities = Get-EligibleCapabilities -CapabilitiesReg $capabilitiesReg -RepoRoot $RepositoryRoot
if (@($capabilities).Count -eq 0) {
    throw "Zero capabilities in $CapabilitiesFile have a populated agents/ directory. Refusing to report success against an empty work set."
}

$parsedByCapability = @{}
foreach ($cap in $capabilities) {
    $parsedByCapability[$cap.Id] = @($cap.AgentFiles | ForEach-Object { Read-CanonicalAgent -Path $_.FullName })
}

# ---------------------------------------------------------------------------
# Main loop -- capability x host x agent, plus one manifest row per
# capability x host for hosts that declare a manifestKind.
# ---------------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$notes = New-Object System.Collections.Generic.List[string]
$workSetCount = 0
$hasUnmanaged = $false

foreach ($cap in $capabilities) {
    $agents = $parsedByCapability[$cap.Id]

    foreach ($hostFormat in $formatsReg.hosts) {
        $hostRootMarker = Expand-DestinationTemplate -Template $hostFormat.hostRootMarkerTemplate -CapabilityId $cap.Id
        $hostInstalled = [string]::IsNullOrWhiteSpace($hostRootMarker) -or (Test-Path -LiteralPath $hostRootMarker -PathType Container)

        if (-not $hostInstalled) {
            foreach ($agent in $agents) {
                $results.Add([pscustomobject]@{
                    Capability = $cap.Id; HostId = $hostFormat.id; Agent = $agent.Name
                    State = 'skipped (host not installed)'; Action = 'none'; Path = $null; Notes = $null
                })
            }
            if ($hostFormat.manifestKind -and $hostFormat.manifestKind -ne 'none') {
                $results.Add([pscustomobject]@{
                    Capability = $cap.Id; HostId = $hostFormat.id; Agent = "($($hostFormat.manifestFileName))"
                    State = 'skipped (host not installed)'; Action = 'none'; Path = $null; Notes = $null
                })
            }
            continue
        }

        $destDir = Expand-DestinationTemplate -Template $hostFormat.destinationTemplate -CapabilityId $cap.Id
        $toolMap = $hostFormat.toolMap

        # Manifest (Gemini extension / Antigravity plugin wrapper), one per
        # capability x host, only for hosts that declare a manifestKind.
        if ($hostFormat.manifestKind -and $hostFormat.manifestKind -ne 'none') {
            $manifestDir = Expand-DestinationTemplate -Template $hostFormat.manifestDestinationTemplate -CapabilityId $cap.Id
            $manifestPath = Join-Path $manifestDir $hostFormat.manifestFileName
            $manifestContent = Get-RenderedManifest -ManifestKind $hostFormat.manifestKind -Capability $cap
            $manifestState = Get-DestinationState -DestinationPath $manifestPath -ExpectedContent $manifestContent -Format $hostFormat.format -IsManifest $true

            $manifestAction = 'none'
            if ($Apply) {
                if ($manifestState -eq 'missing' -or $manifestState -eq 'drift') {
                    if (-not (Test-Path -LiteralPath $manifestDir)) { New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null }
                    Write-Utf8NoBom -Path $manifestPath -Content $manifestContent
                    $manifestAction = 'updated'
                } elseif ($manifestState -eq 'unmanaged') {
                    $manifestAction = 'refused'
                    $hasUnmanaged = $true
                }
            } elseif ($manifestState -eq 'unmanaged') {
                $hasUnmanaged = $true
            }
            $results.Add([pscustomobject]@{
                Capability = $cap.Id; HostId = $hostFormat.id; Agent = "($($hostFormat.manifestFileName))"
                State = $manifestState; Action = $manifestAction; Path = $manifestPath; Notes = $null
            })
        }

        foreach ($agent in $agents) {
            $runtimeName = "$($cap.Id)-$($agent.Name)"
            $destPath = Join-Path $destDir "$runtimeName.$($hostFormat.extension)"
            $rendered = Get-RenderedSubagent -Format $hostFormat.format -RuntimeName $runtimeName -Agent $agent -ToolMap $toolMap
            $workSetCount++

            $state = Get-DestinationState -DestinationPath $destPath -ExpectedContent $rendered.Content -Format $hostFormat.format -IsManifest $false

            $rowNotes = $null
            if (@($rendered.Unmapped).Count -gt 0) {
                $rowNotes = "unmapped tool(s) dropped (no verified $($hostFormat.id) mapping): $($rendered.Unmapped -join ', ')"
                $notes.Add("NOTE: $($cap.Id)/$($agent.Name) -> $($hostFormat.id): $rowNotes")
            }

            $action = 'none'
            if ($Apply) {
                if ($state -eq 'missing' -or $state -eq 'drift') {
                    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    Write-Utf8NoBom -Path $destPath -Content $rendered.Content
                    $action = 'updated'
                } elseif ($state -eq 'unmanaged') {
                    $action = 'refused'
                    $hasUnmanaged = $true
                }
            } elseif ($state -eq 'unmanaged') {
                $hasUnmanaged = $true
            }

            $results.Add([pscustomobject]@{
                Capability = $cap.Id; HostId = $hostFormat.id; Agent = $agent.Name
                State = $state; Action = $action; Path = $destPath; Notes = $rowNotes
            })
        }
    }
}

if ($results.Count -eq 0) {
    # Defense-in-depth only: the pre-loop guards above (zero eligible
    # capabilities, zero declared hosts) already make this unreachable in
    # practice. Deliberately NOT gated on $workSetCount, which legitimately
    # reaches 0 when every declared host is 'skipped (host not installed)'
    # on this machine/profile -- that is a real, successful outcome (every
    # candidate was evaluated and correctly skipped), not an empty work set.
    throw "Zero (capability, host, agent) rows were evaluated at all. Refusing to report success against an empty work set."
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$mode = if ($Apply) { 'Apply' } else { 'Audit' }
Write-Host "Sync-Subagents ($mode) -- RepositoryRoot=$RepositoryRoot UserProfile=$UserProfile"
Write-Host ("{0,-32} {1,-12} {2,-42} {3,-25} {4,-8} {5}" -f 'CAPABILITY', 'HOSTID', 'AGENT', 'STATE', 'ACTION', 'PATH')
foreach ($r in $results) {
    Write-Host ("{0,-32} {1,-12} {2,-42} {3,-25} {4,-8} {5}" -f $r.Capability, $r.HostId, $r.Agent, $r.State, $r.Action, $r.Path)
}
foreach ($n in $notes) { Write-Host $n -ForegroundColor Yellow }

$counts = @{
    current = @($results | Where-Object State -eq 'current').Count
    drift   = @($results | Where-Object State -eq 'drift').Count
    missing = @($results | Where-Object State -eq 'missing').Count
    unmanaged = @($results | Where-Object State -eq 'unmanaged').Count
    skipped = @($results | Where-Object State -eq 'skipped (host not installed)').Count
    updated = @($results | Where-Object Action -eq 'updated').Count
}
Write-Host ("SUMMARY: current={0} drift={1} missing={2} unmanaged={3} skipped={4} updated={5} total={6} workSet={7}" -f `
    $counts.current, $counts.drift, $counts.missing, $counts.unmanaged, $counts.skipped, $counts.updated, $results.Count, $workSetCount)

if ($hasUnmanaged) {
    Write-Host "REFUSED: one or more destinations are unmanaged (existing content does not structurally match this generator's own output format). Refusing to overwrite content this generator did not write. This run is a failure, not a partial success." -ForegroundColor Red
    exit 1
}

Write-Host "Sync-Subagents complete: $($results.Count) rows evaluated, $workSetCount subagent destinations." -ForegroundColor Green
exit 0
