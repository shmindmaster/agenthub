$ErrorActionPreference = 'Stop'

$pluginRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $pluginRoot '.codex-plugin\plugin.json'
$claudeManifestPath = Join-Path $pluginRoot '.claude-plugin\plugin.json'
$cursorManifestPath = Join-Path $pluginRoot '.cursor-plugin\plugin.json'
$portableManifestPath = Join-Path $pluginRoot 'plugin.json'
$expectedAgents = @('reviewer.agent.md')
$expectedSkills = @('audit', 'design', 'build', 'verify', 'demo')
$expectedReferences = @('agentic.md', 'demo-handoff.md', 'surfaces.md')
$maxSkillWords = 500
$maxSkillBytes = 5120
$maxDescriptionLength = 300

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Text([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

Assert-True (Test-Path -LiteralPath $manifestPath) 'Missing Codex plugin manifest.'
Assert-True (Test-Path -LiteralPath $claudeManifestPath) 'Missing Claude plugin manifest.'
Assert-True (Test-Path -LiteralPath $cursorManifestPath) 'Missing Cursor plugin manifest.'
Assert-True (Test-Path -LiteralPath $portableManifestPath) 'Missing Copilot/Antigravity plugin manifest.'
$manifest = Read-Text $manifestPath | ConvertFrom-Json
$claudeManifest = Read-Text $claudeManifestPath | ConvertFrom-Json
$cursorManifest = Read-Text $cursorManifestPath | ConvertFrom-Json
$portableManifest = Read-Text $portableManifestPath | ConvertFrom-Json

# The manifests must agree with each other. The version is not pinned here, so a
# bump edits the manifests alone.
Assert-True ($manifest.name -eq 'ah-product') 'Unexpected plugin name.'
Assert-True ($manifest.version -match '^\d+\.\d+\.\d+$') "Codex plugin version must be semver, found '$($manifest.version)'."
foreach ($other in @(
    @{ Label = 'Claude'; Manifest = $claudeManifest },
    @{ Label = 'Cursor'; Manifest = $cursorManifest },
    @{ Label = 'Portable'; Manifest = $portableManifest }
)) {
    Assert-True ($other.Manifest.name -eq $manifest.name) "$($other.Label) plugin name must match Codex."
    Assert-True ($other.Manifest.version -eq $manifest.version) "$($other.Label) plugin version must match Codex."
    Assert-True ($other.Manifest.description -eq $manifest.description) "$($other.Label) plugin description must match Codex."
}
Assert-True ($manifest.author.name -eq 'MahumTech') 'Author must be MahumTech.'
Assert-True ($manifest.interface.displayName -eq 'AH-Product') 'Incorrect display name.'
Assert-True ($manifest.interface.capabilities.Count -ge 3) 'Capabilities metadata is incomplete.'
Assert-True ($manifest.interface.defaultPrompt.Count -eq 3) 'Exactly three starter prompts are required.'
Assert-True (@($portableManifest.PSObject.Properties.Name | Where-Object { $_ -notin @('$schema', 'name', 'version', 'description') }).Count -eq 0) 'Portable manifest must stay compatible with the Agent Plugins floor.'

# A manifest that names `skills` opts out of convention-based discovery, so it
# must also name `agents` or the subagents do not load.
foreach ($manifestPair in @(
    @{ Path = $manifestPath; Manifest = $manifest },
    @{ Path = $claudeManifestPath; Manifest = $claudeManifest },
    @{ Path = $cursorManifestPath; Manifest = $cursorManifest }
)) {
    $declared = $manifestPair.Manifest.PSObject.Properties.Name
    if ($declared -notcontains 'skills') { continue }
    Assert-True ($declared -contains 'agents') "$($manifestPair.Path) declares 'skills' but not 'agents'."
}

foreach ($agentName in $expectedAgents) {
    $agentPath = Join-Path $pluginRoot "agents\$agentName"
    Assert-True (Test-Path -LiteralPath $agentPath) "Missing shared subagent: $agentName"
    $agentText = Read-Text $agentPath
    Assert-True ($agentText -match '(?m)^description: .+$') "Subagent description is missing: $agentName"

    # Host adapters comma-split `tools:`, so a YAML flow sequence produces broken tokens.
    $toolsMatch = [regex]::Match($agentText, '(?m)^tools:\s*([^\r\n]+)\r?$')
    Assert-True $toolsMatch.Success "Subagent is missing a tools: declaration: $agentName"
    $toolsValue = $toolsMatch.Groups[1].Value.Trim()
    Assert-True (-not $toolsValue.StartsWith('[')) "Subagent tools: must use the scalar comma-separated form: $agentName"

    # A missing `readonly` key loses the read-only sandbox downstream.
    Assert-True ($agentText -match '(?m)^readonly:\s*(true|false)\s*$') "Subagent must declare readonly: true or readonly: false explicitly: $agentName"
}
$actualAgents = @(Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'agents') -File | Select-Object -ExpandProperty Name | Sort-Object)
Assert-True (($actualAgents -join '|') -eq (($expectedAgents | Sort-Object) -join '|')) 'Shared subagent set does not match the reviewer-only contract.'
$reviewerText = Read-Text (Join-Path $pluginRoot 'agents\reviewer.agent.md')
Assert-True ($reviewerText -match '(?m)^readonly:\s*true\s*$') 'The reviewer must be read-only.'
Assert-True ($reviewerText -match '(?m)^tools:.*\bBash\b') 'The reviewer needs Bash, because a check it cannot run is Blocked.'

foreach ($assetField in @('composerIcon', 'logo', 'logoDark')) {
    $asset = $manifest.interface.$assetField
    Assert-True (-not [string]::IsNullOrWhiteSpace($asset)) "Manifest field $assetField is missing."
    Assert-True (Test-Path -LiteralPath (Join-Path $pluginRoot ($asset -replace '^\./', ''))) "Missing asset: $asset"
}

$forbiddenVocabulary = '(?i)\b(ledger|receipts?|capsules?|truth table|previously|no longer|retired|legacy)\b'
$linkedReferences = New-Object System.Collections.Generic.HashSet[string]
foreach ($skillName in $expectedSkills) {
    $skillRoot = Join-Path $pluginRoot "skills\$skillName"
    $skillPath = Join-Path $skillRoot 'SKILL.md'
    $openAiPath = Join-Path $skillRoot 'agents\openai.yaml'
    Assert-True (Test-Path -LiteralPath $skillPath) "Missing SKILL.md for $skillName."
    Assert-True (Test-Path -LiteralPath $openAiPath) "Missing agents/openai.yaml for $skillName."
    $skillText = Read-Text $skillPath

    Assert-True ($skillText -match "(?m)^name: $([regex]::Escape($skillName))\r?$") "Skill name mismatch for $skillName."
    $description = [regex]::Match($skillText, '(?m)^description: ([^\r\n]+)\r?$').Groups[1].Value
    Assert-True ($description -match '\. Use when ') "Skill description must state the outcome, then 'Use when': $skillName."
    Assert-True ($description -match 'Not for ') "Skill description must name its look-alike with 'Not for': $skillName."
    Assert-True ($description.Length -le $maxDescriptionLength) "Skill description exceeds $maxDescriptionLength characters: $skillName."
    Assert-True ($description -notmatch ': ') "Skill description must be YAML-safe: $skillName."

    $bytes = [Text.Encoding]::UTF8.GetByteCount($skillText)
    $words = @($skillText -split '\s+' | Where-Object { $_ }).Count
    Assert-True ($words -le $maxSkillWords) "Skill has $words words, over $maxSkillWords`: $skillName."
    Assert-True ($bytes -le $maxSkillBytes) "Skill has $bytes bytes, over $maxSkillBytes`: $skillName."

    Assert-True ($skillText -match 'no earlier files are needed') "Skill must state that it runs standalone: $skillName."
    Assert-True ($skillText -match '(?m)^- \[ \] ') "Skill must carry a copyable checklist: $skillName."
    Assert-True (@([regex]::Matches($skillText, '(?m)^Next: ')).Count -eq 1) "Skill must name the next step in one line: $skillName."
    Assert-True ($skillText -notmatch $forbiddenVocabulary) "Skill uses process vocabulary or history wording: $skillName."

    # Every plugin file a skill names must exist; a renamed script fails only at run time otherwise.
    foreach ($pathMatch in [regex]::Matches($skillText, '\.\./\.\./((?:scripts|kits|references)/[\w./-]*\w)')) {
        $target = [IO.Path]::GetFullPath((Join-Path $skillRoot $pathMatch.Value))
        Assert-True (Test-Path -LiteralPath $target) "Skill names a missing file: $skillName -> $($pathMatch.Value)"
        if ($pathMatch.Groups[1].Value -match '^references/(.+)$') {
            [void]$linkedReferences.Add($Matches[1])
            Assert-True ($skillText -match 'Read when ') "Skill links a reference without a 'Read when' line: $skillName."
        }
    }

    $openAiText = Read-Text $openAiPath
    $skillInvocation = [regex]::Escape('$' + $skillName)
    Assert-True ($openAiText -match "default_prompt: `"[^`"]*$skillInvocation\b") "Default prompt must mention the skill invocation for $skillName."
}

$actualSkills = @(Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'skills') -Directory | Select-Object -ExpandProperty Name | Sort-Object)
Assert-True (($actualSkills -join '|') -eq (($expectedSkills | Sort-Object) -join '|')) 'Skill set does not match the five-skill contract.'

# Rules that must survive any edit to these skills.
$auditText = Read-Text (Join-Path $pluginRoot 'skills\audit\SKILL.md')
foreach ($label in @('Observed', 'Implemented', 'Reported', 'Assumed', 'Unknown')) {
    Assert-True ($auditText -match "(?m)^\| $label \|") "Audit is missing the evidence label: $label."
}
foreach ($skillName in @('verify', 'demo')) {
    Assert-True ((Read-Text (Join-Path $pluginRoot "skills\$skillName\SKILL.md")) -match 'builder never issues the verdict') "Skill must keep the builder-never-verdicts rule: $skillName."
}
$demoText = Read-Text (Join-Path $pluginRoot 'skills\demo\SKILL.md')
Assert-True ($demoText -match 'product-fix-required' -and $demoText -match 'capture-fixable') 'Demo must keep the product-fix and capture-fix split.'

$actualReferences = @(Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'references') -File | Select-Object -ExpandProperty Name | Sort-Object)
Assert-True (($actualReferences -join '|') -eq (($expectedReferences | Sort-Object) -join '|')) 'Reference set does not match the expected three files.'
foreach ($reference in $expectedReferences) {
    Assert-True ($linkedReferences.Contains($reference)) "No skill loads this reference: $reference"
    $referenceLines = @(Get-Content -LiteralPath (Join-Path $pluginRoot "references\$reference") -Encoding UTF8)
    if ($referenceLines.Count -gt 100) {
        Assert-True (($referenceLines -join "`n") -match '(?m)^## Contents$') "A reference over 100 lines must open with a contents list: $reference"
    }
}
$agenticText = Read-Text (Join-Path $pluginRoot 'references\agentic.md')
Assert-True ($agenticText -match '(?m)^\| Consequence and reversibility \|') 'The agentic reference must keep the autonomy table.'
Assert-True ($agenticText -match 'Do not hide deterministic actions behind chat') 'The agentic reference must keep the deterministic-actions rule.'

$allTextFiles = Get-ChildItem -LiteralPath $pluginRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.md', '.json', '.yaml', '.yml', '.mjs', '.ps1', '.svg') }
$forbidden = '(?i)AI[- ]Native[- ]Freight|gentlenext|lawli|lexalign|lienwise|shwiki|subops|verigence|warrantygains|abacare|coledger|documed|empowera'
foreach ($file in $allTextFiles) {
    if ($file.FullName -match '[\\/]tests[\\/]') { continue }
    $content = Read-Text $file.FullName
    Assert-True ($content -notmatch '\[TODO:') "Unresolved scaffold TODO in $($file.FullName)."
    Assert-True ($content -notmatch $forbidden) "Repo-specific content leaked into $($file.FullName)."
}

foreach ($file in (Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter '*.md')) {
    $content = Read-Text $file.FullName
    foreach ($match in [regex]::Matches($content, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value.Trim().Trim('<', '>')
        if ($target -match '^(https?://|mailto:|#)') { continue }
        $relativeTarget = [uri]::UnescapeDataString(($target -split '#')[0])
        if ([string]::IsNullOrWhiteSpace($relativeTarget)) { continue }
        $resolvedTarget = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relativeTarget))
        Assert-True (Test-Path -LiteralPath $resolvedTarget) "Broken local Markdown link in $($file.FullName): $target"
    }
}

Assert-True (-not (Test-Path -LiteralPath (Join-Path $pluginRoot 'hooks'))) 'This plugin must not ship lifecycle hooks.'

$agentHubRoot = Split-Path -Parent (Split-Path -Parent $pluginRoot)
$marketplacePath = Join-Path $agentHubRoot '.agents\plugins\marketplace.json'
$marketplace = Read-Text $marketplacePath | ConvertFrom-Json
$entry = @($marketplace.plugins | Where-Object name -eq 'ah-product')
Assert-True ($marketplace.name -eq 'agenthub') 'Canonical marketplace name must be agenthub.'
Assert-True ($entry.Count -eq 1) 'AgentHub marketplace entry is missing or duplicated.'
Assert-True ($entry[0].source.path -eq './packages/product') 'Marketplace source path is incorrect.'
Assert-True ($entry[0].category -eq 'Developer Tools') 'Marketplace category is incorrect.'

'PASS: plugin structure, metadata, skills, references, assets and hooks are valid.'
