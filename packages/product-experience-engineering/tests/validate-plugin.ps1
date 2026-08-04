$ErrorActionPreference = 'Stop'

$pluginRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $pluginRoot '.codex-plugin\plugin.json'
$claudeManifestPath = Join-Path $pluginRoot '.claude-plugin\plugin.json'
$cursorManifestPath = Join-Path $pluginRoot '.cursor-plugin\plugin.json'
$portableManifestPath = Join-Path $pluginRoot 'plugin.json'
$expectedAgents = @(
    'experience-auditor.agent.md',
    'experience-designer.agent.md',
    'experience-implementer.agent.md',
    'experience-validator.agent.md'
)
$expectedSkills = @(
    'engineer-product-experience',
    'discover-application',
    'audit-product-experience',
    'design-workflows-and-features',
    'specify-experience-improvements',
    'implement-experience-improvements',
    'validate-product-experience',
    'design-new-application-experience',
    'measure-experience-outcomes',
    'design-agentic-experiences',
    'prepare-product-for-demo'
)
$expectedPluginReferences = @(
    'artifact-contracts.md',
    'routing-map.md',
    'application-surface-coverage.md',
    'product-experience-audit-remediation-guide.md'
)
$expectedReferences = @(
    '00_Overview-and-How-to-Use.md',
    '01_Product-Experience-Principles.md',
    '02_Agentic-Interaction-Patterns.md',
    '03_Core-Application-UX-Patterns.md',
    '04_Feature-and-Workflow-Design-Method.md',
    '05_Visual-Design-and-Interaction-System.md',
    '06_Product-Experience-Audit-Method.md',
    '07_Implementation-Specification-Template.md',
    '08_Research-Synthesis-and-References.md',
    '09_Repository-Audit-Template.md'
)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $manifestPath) 'Missing plugin manifest.'
Assert-True (Test-Path -LiteralPath $claudeManifestPath) 'Missing Claude plugin manifest.'
Assert-True (Test-Path -LiteralPath $cursorManifestPath) 'Missing Cursor plugin manifest.'
Assert-True (Test-Path -LiteralPath $portableManifestPath) 'Missing Copilot/Antigravity plugin manifest.'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$claudeManifest = Get-Content -LiteralPath $claudeManifestPath -Raw | ConvertFrom-Json
$cursorManifest = Get-Content -LiteralPath $cursorManifestPath -Raw | ConvertFrom-Json
Assert-True ($manifest.name -eq 'product-experience-engineering') 'Unexpected plugin name.'
Assert-True ($manifest.version -eq '1.4.0') 'Codex plugin version must be 1.4.0.'
Assert-True ($claudeManifest.name -eq $manifest.name) 'Claude plugin name must match Codex.'
Assert-True ($claudeManifest.version -eq $manifest.version) 'Claude plugin version must match Codex.'
Assert-True ($cursorManifest.name -eq $manifest.name) 'Cursor plugin name must match Codex.'
Assert-True ($cursorManifest.version -eq $manifest.version) 'Cursor plugin version must match Codex.'
Assert-True ($manifest.version -match '^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$') 'Version is not semantic.'
Assert-True ($manifest.author.name -eq 'MahumTech') 'Author must be MahumTech.'
Assert-True ($manifest.interface.displayName -eq 'Product Experience Engineering') 'Incorrect display name.'
Assert-True ($manifest.interface.capabilities.Count -ge 3) 'Capabilities metadata is incomplete.'
Assert-True ($manifest.interface.defaultPrompt.Count -eq 3) 'Exactly three starter prompts are required.'

# A manifest that names `skills` opts out of convention-based discovery, so every
# other content directory it ships must be named too. Codex silently loaded the
# skills and none of the subagents while `agents` was missing here.
foreach ($manifestPair in @(
    @{ Path = $manifestPath;       Manifest = $manifest },
    @{ Path = $claudeManifestPath; Manifest = $claudeManifest },
    @{ Path = $cursorManifestPath; Manifest = $cursorManifest }
)) {
    $declared = $manifestPair.Manifest.PSObject.Properties.Name
    if ($declared -notcontains 'skills') { continue }
    Assert-True ($declared -contains 'agents') (
        "$($manifestPair.Path) declares 'skills' but not 'agents'; " +
        'the shipped subagents will not be discovered.'
    )
}

$portableManifest = Get-Content -LiteralPath $portableManifestPath -Raw | ConvertFrom-Json
Assert-True ($portableManifest.name -eq $manifest.name) 'Portable plugin name must match Codex.'
Assert-True (@($portableManifest.PSObject.Properties.Name | Where-Object { $_ -notin @('name','description') }).Count -eq 0) 'Portable manifest must stay compatible with Antigravity schema.'
foreach ($agentName in $expectedAgents) {
    $agentPath = Join-Path $pluginRoot "agents\$agentName"
    Assert-True (Test-Path -LiteralPath $agentPath) "Missing shared subagent: $agentName"
    $agentText = Get-Content -LiteralPath $agentPath -Raw
    Assert-True ($agentText -match '(?m)^description: .+$') "Subagent description is missing: $agentName"

    # The deleted host-adapter generator comma-split `tools:` naively, so a YAML
    # flow sequence (`tools: [Read, Grep]`) silently produced broken tokens.
    # Reject that dialect here so it cannot re-enter this package.
    $toolsMatch = [regex]::Match($agentText, '(?m)^tools:\s*([^\r\n]+)\r?$')
    Assert-True $toolsMatch.Success "Subagent is missing a tools: declaration: $agentName"
    $toolsValue = $toolsMatch.Groups[1].Value.Trim()
    Assert-True (-not $toolsValue.StartsWith('[')) "Subagent tools: must use the scalar comma-separated form, not a YAML flow sequence: $agentName"

    # A missing `readonly` key is how a read-only agent loses its sandbox
    # restriction downstream (Codex `sandbox_mode = "read-only"`). Require it
    # declared explicitly rather than inferred.
    Assert-True ($agentText -match '(?m)^readonly:\s*(true|false)\s*$') "Subagent must declare readonly: true or readonly: false explicitly: $agentName"
}
$actualAgents = @(Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'agents') -File | Select-Object -ExpandProperty Name | Sort-Object)
Assert-True (($actualAgents -join '|') -eq (($expectedAgents | Sort-Object) -join '|')) 'Shared subagent set does not match the four-role contract.'

foreach ($assetField in @('composerIcon', 'logo', 'logoDark')) {
    $asset = $manifest.interface.$assetField
    Assert-True (-not [string]::IsNullOrWhiteSpace($asset)) "Manifest field $assetField is missing."
    $assetPath = Join-Path $pluginRoot ($asset -replace '^\./', '')
    Assert-True (Test-Path -LiteralPath $assetPath) "Missing asset: $assetPath"
}

foreach ($skillName in $expectedSkills) {
    $skillRoot = Join-Path $pluginRoot "skills\$skillName"
    Assert-True (Test-Path -LiteralPath (Join-Path $skillRoot 'SKILL.md')) "Missing SKILL.md for $skillName."
    Assert-True (Test-Path -LiteralPath (Join-Path $skillRoot 'agents\openai.yaml')) "Missing agents/openai.yaml for $skillName."
    $skillText = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw
    Assert-True ($skillText -match "(?m)^name: $([regex]::Escape($skillName))\r?$") "Skill name mismatch for $skillName."
    Assert-True ($skillText -match '(?m)^description: Use when ') "Skill description must start with 'Use when' for $skillName."
    Assert-True ($skillText -match '(?m)^## Standalone execution\r?$') "Skill must define standalone execution behavior: $skillName."
    Assert-True ($skillText -match '\.\./\.\./references/artifact-contracts\.md') "Skill must link to the generated-artifact contract: $skillName."
    $agentText = Get-Content -LiteralPath (Join-Path $skillRoot 'agents\openai.yaml') -Raw
    $skillInvocation = [regex]::Escape('$' + $skillName)
    Assert-True ($agentText -match "default_prompt: `"[^`"]*$skillInvocation\b") "Default prompt must mention the skill invocation for $skillName."
}

$actualSkills = @(Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'skills') -Directory | Select-Object -ExpandProperty Name | Sort-Object)
Assert-True (($actualSkills -join '|') -eq (($expectedSkills | Sort-Object) -join '|')) 'Canonical skill siblings do not exactly match the expected eleven-skill contract.'

foreach ($reference in $expectedPluginReferences) {
    Assert-True (Test-Path -LiteralPath (Join-Path $pluginRoot "references\$reference")) "Missing plugin reference: $reference"
}

$guidePath = Join-Path $pluginRoot 'references\product-experience-audit-remediation-guide.md'
# Hash the newline-normalized bytes, not the raw file. Get-FileHash here made
# the verdict depend on git's core.autocrlf: identical content passed in an LF
# checkout and failed in a CRLF worktree. The constant below is unchanged --
# the normalized digest already equals the LF-file digest.
$guideSha = [Security.Cryptography.SHA256]::Create()
try {
    $guideText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($guidePath)).Replace("`r`n", "`n")
    $guideHash = ([BitConverter]::ToString($guideSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($guideText)))).Replace('-', '')
} finally { $guideSha.Dispose() }
Assert-True ($guideHash -eq 'D4B11030FED14700F0F8921F447481892F91ACDE4070E03967A0F743AC527C34') 'Canonical pre-video guide is incomplete or differs from the reviewed source.'

$artifactContractPath = Join-Path $pluginRoot 'references\artifact-contracts.md'
$artifactContract = Get-Content -LiteralPath $artifactContractPath -Raw
Assert-True ($artifactContract -match 'Default: do not create or update `_product-experience/`') 'Artifact contract must default to no repository working-memory folder.'
Assert-True ($artifactContract -match 'does not by itself authorize a plugin working-memory folder') 'Artifact contract must separate task authorization from artifact persistence.'

$referenceRoot = Join-Path $pluginRoot 'references\product-experience-system'
foreach ($reference in $expectedReferences) {
    Assert-True (Test-Path -LiteralPath (Join-Path $referenceRoot $reference)) "Missing canonical reference: $reference"
}

$allTextFiles = Get-ChildItem -LiteralPath $pluginRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.md', '.json', '.yaml', '.yml', '.mjs', '.ps1', '.svg') }
$forbidden = '(?i)AI[- ]Native[- ]Freight|gentlenext|lawli|lexalign|sabhi|shwiki|subops|verigence|warrantygains|abacare|coledger|documed|empowera'
foreach ($file in $allTextFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($file.FullName -notlike '*\tests\*') {
        Assert-True ($content -notmatch '\[TODO:') "Unresolved scaffold TODO in $($file.FullName)."
        Assert-True ($content -notmatch $forbidden) "Repo-specific or freight content leaked into $($file.FullName)."
    }
}

$markdownFiles = Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter '*.md'
foreach ($file in $markdownFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($content, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value.Trim().Trim('<', '>')
        if ($target -match '^(https?://|mailto:|#)') { continue }
        $relativeTarget = [uri]::UnescapeDataString(($target -split '#')[0])
        if ([string]::IsNullOrWhiteSpace($relativeTarget)) { continue }
        $resolvedTarget = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relativeTarget))
        Assert-True (Test-Path -LiteralPath $resolvedTarget) "Broken local Markdown link in $($file.FullName): $target"
    }
}

foreach ($skillName in $expectedSkills) {
    $skillPath = Join-Path $pluginRoot "skills\$skillName\SKILL.md"
    $skillText = Get-Content -LiteralPath $skillPath -Raw
    Assert-True ($skillText -notmatch '(?m)^\d+\. Write `_product-experience/') "Skill still unconditionally writes product-experience artifacts: $skillName"
}

$hooksPath = Join-Path $pluginRoot 'hooks\hooks.json'
Assert-True (Test-Path -LiteralPath $hooksPath) 'Missing hooks declaration.'
$hooks = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
Assert-True (@($hooks.hooks.PSObject.Properties).Count -eq 0) 'Product Experience Engineering must not activate lifecycle hooks.'

$agentHubRoot = Split-Path -Parent (Split-Path -Parent $pluginRoot)
$marketplacePath = Join-Path $agentHubRoot '.agents\plugins\marketplace.json'
$marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
$entry = @($marketplace.plugins | Where-Object name -eq 'product-experience-engineering')
Assert-True ($marketplace.name -eq 'agenthub') 'Canonical marketplace name must be agenthub.'
Assert-True ($entry.Count -eq 1) 'AgentHub marketplace entry is missing or duplicated.'
Assert-True ($entry[0].source.path -eq './packages/product-experience-engineering') 'Marketplace source path is incorrect.'
Assert-True ($entry[0].category -eq 'Developer Tools') 'Marketplace category is incorrect.'

'PASS: plugin structure, metadata, references, assets, and inactive hooks are valid.'
