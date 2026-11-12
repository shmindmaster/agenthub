#Requires -Version 7
<#
.SYNOPSIS
  Write Kiro Web cloud projections of the Kiro-mapped AgentHub Powers.
.DESCRIPTION
  Kiro Web Configuration Sync (https://kiro.dev/docs/web/cloud-configuration/,
  checked 2026-11-11) accepts a custom Power of at most 50 text files, each at most
  4,000,000 bytes, uploaded by dragging the powers/ folder into Agent Config >
  Cloud Config. A cloud sandbox cannot reach this machine, so a projection keeps
  only what works there: plugin.json, the skills' SKILL.md files and their text
  references, and mcp.json when every server in it is remote (http). Scripts,
  kits, tests, assets and local stdio servers stay local, and CLOUD.md in each
  projection lists what was left out so the cloud agent does not assume it.

  Private overlay capabilities are never projected: they carry personal material
  and local-only runtimes. Pass -IncludePrivate only after reviewing the output.

  Writes under -OutputRoot (default %LOCALAPPDATA%\AgentHub\kiro-cloud\powers) and
  nothing else. Uploading is a manual step in Kiro Web; this script never uploads.
.EXAMPLE
  pwsh -NoProfile -File scripts/New-KiroCloudPowers.ps1 -RepositoryRoot . -Json
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$OutputRoot,
    [switch]$IncludePrivate,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
if (-not $RepositoryRoot) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
$root = [IO.Path]::GetFullPath($RepositoryRoot)
. (Join-Path $PSScriptRoot 'lib/CapabilityGraph.ps1')
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')
. (Join-Path $PSScriptRoot 'lib/PathBinding.ps1')
if (-not $OutputRoot) { $OutputRoot = Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub/kiro-cloud/powers' }

$MaxFiles = 50
$MaxBytes = 4000000
$TextExtensions = @('.md', '.markdown', '.txt', '.json', '.yaml', '.yml', '.csv')

$capabilities = Get-Content (Join-Path $root 'registry/capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$overlay = Get-AgentHubOverlayRoot -RepositoryRoot $root

function Test-RemoteOnlyMcp([string]$Path) {
    $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $servers = @($doc.mcpServers.PSObject.Properties)
    if (-not $servers.Count) { return $false }
    foreach ($server in $servers) {
        if (-not $server.Value.url -or $server.Value.command) { return $false }
    }
    return $true
}

$report = foreach ($cap in Get-AgentHubEffectiveCapabilities -CapabilitiesDocument $capabilities -OverlayRoot $overlay) {
    $mapping = @($cap.hostMappings | Where-Object { $_.hostId -eq 'kiro' -and $_.deploymentStatus -eq 'native-local-plugin' }) | Select-Object -First 1
    if (-not $mapping) { continue }
    $private = Test-AgentHubCapabilityPrivate $cap
    $source = Resolve-AgentHubPackageRoot -RepositoryRoot $root -Capability $cap -OverlayRoot $overlay
    $manifest = Get-Content (Join-Path $source 'plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $row = [ordered]@{ capability = $cap.id; power = $manifest.name; version = $manifest.version; status = $null; files = 0; omitted = @(); path = $null }
    if ($private -and -not $IncludePrivate) { $row.status = 'local-only-private'; $row; continue }

    $files = if ($private) { @(Get-AgentHubFilesystemRelativeFiles -Path $source) } else { @(Get-AgentHubGitTrackedRelativeFiles -Path $source) }
    $keep = [Collections.Generic.List[string]]::new()
    $omitted = [Collections.Generic.List[string]]::new()
    $keep.Add('plugin.json')
    if ('mcp.json' -in $files) {
        if (Test-RemoteOnlyMcp (Join-Path $source 'mcp.json')) { $keep.Add('mcp.json') } else { $omitted.Add('mcp.json (local server)') }
    }
    $skillFiles = @($files | Where-Object { $_ -match '^skills/[^/]+/SKILL\.md$' } | Sort-Object)
    $references = @($files | Where-Object {
        $_ -match '^skills/[^/]+/references/' -and [IO.Path]::GetExtension($_).ToLowerInvariant() -in $TextExtensions
    } | Sort-Object)
    foreach ($file in $skillFiles) { $keep.Add($file) }
    foreach ($file in $references) { $keep.Add($file) }
    # Over the limit (one slot stays free for CLOUD.md): fold the references of the skill
    # with the most of them into one bundle.md, largest skill first, until it fits. No
    # reference text is dropped; the projected SKILL.md links point at the bundle.
    $bundles = @{}
    while ($keep.Count -gt $MaxFiles - 1) {
        $skill = @($keep | Where-Object { $_ -match '^skills/[^/]+/references/' -and $_ -notmatch '/bundle\.md$' } |
            Group-Object { ($_ -split '/')[1] } | Where-Object Count -GT 1 | Sort-Object Count -Descending) | Select-Object -First 1
        if (-not $skill) { break }
        $bundles[$skill.Name] = @($skill.Group)
        foreach ($file in $skill.Group) { [void]$keep.Remove($file) }
        $keep.Add("skills/$($skill.Name)/references/bundle.md")
    }
    # A reference folded into a bundle.md is carried, not omitted.
    $bundled = @($bundles.Values | ForEach-Object { $_ })
    foreach ($file in $files) {
        if ($file -notin $keep -and $file -notin $bundled -and $file -ne '.mcp.json' -and $file -notmatch '^\.[a-z-]+-plugin/' -and -not ($omitted | Where-Object { $_ -like "$file *" })) {
            $top = ($file -split '/')[0]
            $label = if ($file -match '^skills/[^/]+/scripts/') { 'skill scripts' }
                elseif ($file -match '^skills/[^/]+/references/') { 'skill reference files that are not text' }
                elseif ($file -match '^skills/') { 'other skill files' }
                else { $top }
            if ($label -notin $omitted) { $omitted.Add($label) }
        }
    }
    if ($keep.Count -gt $MaxFiles - 1) { $row.status = 'blocked-too-many-skills'; $row.omitted = @($omitted); $row; continue }

    $destination = Join-Path $OutputRoot $manifest.name
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    foreach ($file in $keep) {
        $bundleSkill = if ($file -match '^skills/([^/]+)/references/bundle\.md$') { $Matches[1] }
        if ($bundleSkill) {
            $parts = foreach ($part in $bundles[$bundleSkill]) {
                "<!-- $part -->`n# $([IO.Path]::GetFileName($part))`n`n" + [IO.File]::ReadAllText((Join-Path $source $part))
            }
            $to = Join-Path $destination $file
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to))
            [IO.File]::WriteAllText($to, ($parts -join "`n`n"), [Text.UTF8Encoding]::new($false))
            continue
        }
        $from = Join-Path $source $file
        if ((Get-Item -LiteralPath $from).Length -gt $MaxBytes) { throw "$($cap.id): $file exceeds the $MaxBytes-byte cloud limit." }
        $to = Join-Path $destination $file
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to))
        Copy-Item -LiteralPath $from -Destination $to
        $skillName = if ($file -match '^skills/([^/]+)/SKILL\.md$') { $Matches[1] }
        if ($skillName -and $bundles.ContainsKey($skillName)) {
            $text = [IO.File]::ReadAllText($to)
            foreach ($part in $bundles[$skillName]) { $text = $text.Replace(($part -replace "^skills/$skillName/", ''), 'references/bundle.md') }
            [IO.File]::WriteAllText($to, $text, [Text.UTF8Encoding]::new($false))
        }
    }
    if ($bundles.Count) { $omitted.Insert(0, "nothing from references: the references of $(@($bundles.Keys | Sort-Object) -join ', ') are folded into references/bundle.md") }
    $note = @(
        "# $($manifest.name) $($manifest.version) - cloud projection",
        '',
        "Generated from AgentHub ``$($cap.canonicalSource)`` (content hash $($cap.contentHash.Substring(0, 12))) by scripts/New-KiroCloudPowers.ps1.",
        'A Kiro cloud sandbox cannot reach the owner''s machine. These parts of the package exist only in local sessions:',
        ''
    ) + @($omitted | ForEach-Object { "- $_" }) + @(
        '',
        'When a skill step needs one of them, say that the step needs a local Kiro session and stop that step. Do not recreate the missing script or server.'
    )
    [IO.File]::WriteAllText((Join-Path $destination 'CLOUD.md'), ($note -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    $row.files = $keep.Count + 1
    $row.omitted = @($omitted)
    $row.path = $destination
    $row.status = 'cloud-projection-written'
    $row
}
$report = @($report)
if ($Json) { $report | ConvertTo-Json -Depth 4 }
else {
    $report | ForEach-Object { [pscustomobject]$_ } | Format-Table capability, power, version, status, files -AutoSize
    Write-Output "Upload: drag $OutputRoot into Kiro Web > Agent Config > Cloud Config (powers/)."
}
