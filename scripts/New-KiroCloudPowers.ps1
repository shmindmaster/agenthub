#Requires -Version 7
<#
.SYNOPSIS
  Write Kiro Web cloud projections of the Kiro-mapped AgentHub Powers.
.DESCRIPTION
  Kiro Web Configuration Sync (https://kiro.dev/docs/web/cloud-configuration/,
  checked 2026-11-11) accepts a custom Power of at most 50 text files, each at most
  4,000,000 bytes, uploaded by dragging the powers/ folder into Agent Config >
  Cloud Config. A cloud sandbox cannot reach this machine, so a projection keeps
  only what works there: plugin.json, the skills' SKILL.md files, the text files in
  their references/ folders and the package's shared references/, and mcp.json when every server in it is remote (http). Scripts,
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

# A reference folder is skills/<skill>/references or the package's shared references.
function Get-ReferenceFolder([string]$Path) {
    if ($Path -match '^((skills/[^/]+/)?references)/') { return $Matches[1] }
}

# Point every link at a folded reference to its bundle.md, in every projected text file:
# <skill>/references/<name> from anywhere, references/<name> inside the owning skill (or
# the package root for shared references), ../../references/<name> from a skill, and a
# bare sibling name, linked or in backticks, inside the bundle itself.
function Update-ProjectedLinks([string]$Text, [string]$File, [hashtable]$Bundles) {
    $fileSkill = if ($File -match '^skills/([^/]+)/') { $Matches[1] }
    foreach ($folder in $Bundles.Keys) {
        $folderSkill = if ($folder -match '^skills/([^/]+)/references$') { $Matches[1] }
        foreach ($part in $Bundles[$folder]) {
            $name = [regex]::Escape($part.Substring($folder.Length + 1))
            $end = '(?![\w.-])'
            if ($folderSkill) {
                $skill = [regex]::Escape($folderSkill)
                $Text = [regex]::Replace($Text, "(?<![\w.-])$skill/references/$name$end", "$folderSkill/references/bundle.md")
                if ($fileSkill -eq $folderSkill) { $Text = [regex]::Replace($Text, "(?<![\w./-])references/$name$end", 'references/bundle.md') }
            } else {
                $Text = [regex]::Replace($Text, "(?<![\w.-])\.\./\.\./references/$name$end", '../../references/bundle.md')
                if (-not $fileSkill) { $Text = [regex]::Replace($Text, "(?<![\w./-])references/$name$end", 'references/bundle.md') }
            }
            if ($File -eq "$folder/bundle.md") {
                $Text = [regex]::Replace($Text, "(?<=\]\()(\./)?$name(?=[)#])", 'bundle.md')
                $Text = [regex]::Replace($Text, "(?<=``)(\./)?$name(?=``)", 'bundle.md')
            }
        }
    }
    return $Text
}

# Each run rewrites the whole upload folder: projections an earlier run wrote (an
# -IncludePrivate run included) go first, so the folder holds only this run's Powers.
$foreign = [Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $OutputRoot) {
    foreach ($entry in Get-ChildItem -LiteralPath $OutputRoot -Force) {
        $previousNote = Join-Path $entry.FullName 'CLOUD.md'
        $generated = $entry.PSIsContainer -and -not ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            (Test-Path -LiteralPath $previousNote -PathType Leaf) -and
            (Select-String -LiteralPath $previousNote -SimpleMatch 'by scripts/New-KiroCloudPowers.ps1' -Quiet)
        if ($generated) { Remove-Item -LiteralPath $entry.FullName -Recurse -Force } else { $foreign.Add($entry.Name) }
    }
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
        (Get-ReferenceFolder $_) -and [IO.Path]::GetExtension($_).ToLowerInvariant() -in $TextExtensions
    } | Sort-Object)
    foreach ($file in $skillFiles) { $keep.Add($file) }
    foreach ($file in $references) { $keep.Add($file) }
    # Over the limit (one slot stays free for CLOUD.md): fold the reference folder with
    # the most files into one bundle.md, largest first, until it fits. No reference text
    # is dropped; every projected link to a folded file points at its bundle.
    $bundles = @{}
    while ($keep.Count -gt $MaxFiles - 1) {
        $group = @($keep | Where-Object { (Get-ReferenceFolder $_) -and $_ -notmatch '/bundle\.md$' } |
            Group-Object { Get-ReferenceFolder $_ } | Where-Object Count -GT 1 | Sort-Object Count -Descending) | Select-Object -First 1
        if (-not $group) { break }
        $bundles[$group.Name] = @($group.Group)
        foreach ($file in $group.Group) { [void]$keep.Remove($file) }
        $keep.Add("$($group.Name)/bundle.md")
    }
    # A reference folded into a bundle.md is carried, not omitted.
    $bundled = @($bundles.Values | ForEach-Object { $_ })
    foreach ($file in $files) {
        if ($file -notin $keep -and $file -notin $bundled -and $file -ne '.mcp.json' -and $file -notmatch '^\.[a-z-]+-plugin/' -and -not ($omitted | Where-Object { $_ -like "$file *" })) {
            $top = ($file -split '/')[0]
            $label = if ($file -match '^skills/[^/]+/scripts/') { 'skill scripts' }
                elseif (Get-ReferenceFolder $file) { 'reference files that are not text' }
                elseif ($file -match '^skills/') { 'other skill files' }
                else { $top }
            if ($label -notin $omitted) { $omitted.Add($label) }
        }
    }
    if ($keep.Count -gt $MaxFiles - 1) { $row.status = 'blocked-too-many-skills'; $row.omitted = @($omitted); $row; continue }

    $destination = Join-Path $OutputRoot $manifest.name
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    foreach ($file in $keep) {
        $to = Join-Path $destination $file
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to))
        $folder = if ($file -match '^(.+)/bundle\.md$') { $Matches[1] }
        if ($folder -and $bundles.ContainsKey($folder)) {
            $parts = foreach ($part in $bundles[$folder]) {
                "<!-- $part -->`n# $([IO.Path]::GetFileName($part))`n`n" + [IO.File]::ReadAllText((Join-Path $source $part))
            }
            $text = Update-ProjectedLinks ($parts -join "`n`n") $file $bundles
            $encoded = [Text.UTF8Encoding]::new($false).GetBytes($text)
            if ($encoded.Length -gt $MaxBytes) { throw "$($cap.id): $file exceeds the $MaxBytes-byte cloud limit." }
            [IO.File]::WriteAllBytes($to, $encoded)
            continue
        }
        $from = Join-Path $source $file
        if ((Get-Item -LiteralPath $from).Length -gt $MaxBytes) { throw "$($cap.id): $file exceeds the $MaxBytes-byte cloud limit." }
        if (-not $bundles.Count) { Copy-Item -LiteralPath $from -Destination $to; continue }
        $text = [IO.File]::ReadAllText($from)
        [IO.File]::WriteAllText($to, (Update-ProjectedLinks $text $file $bundles), [Text.UTF8Encoding]::new($false))
    }
    if ($bundles.Count) { $omitted.Insert(0, "nothing from references: the files in $(@($bundles.Keys | Sort-Object) -join ', ') are folded into bundle.md in the same folder") }
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
if ($foreign.Count) { Write-Warning "$OutputRoot also holds entries this script did not write; remove them before uploading: $($foreign -join ', ')" }
if ($Json) { $report | ConvertTo-Json -Depth 4 }
else {
    $report | ForEach-Object { [pscustomobject]$_ } | Format-Table capability, power, version, status, files -AutoSize
    Write-Output "Upload: drag $OutputRoot into Kiro Web > Agent Config > Cloud Config (powers/)."
}
