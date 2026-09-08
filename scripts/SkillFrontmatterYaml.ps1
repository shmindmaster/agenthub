#Requires -Version 5.1
<#
YAML-safe skill frontmatter for hosts that parse SKILL.md strictly.

Zed (and any libyaml consumer) rejects an unquoted scalar that contains
": " as "mapping values are not allowed in this context". Claude and
Cursor are looser, so a skill can sit in ~/.agents/skills for weeks and
only fail when Zed loads it. The live case was Railway's use-railway
description, which is third-party and not an AgentHub package.

This module quotes those scalars in place. It does not re-vendor upstream
skills and must not rewrite AgentHub-managed copies (those are fixed at
source via the skill authoring standard). Callers pass -SkipPaths for
managed skill directories.

Dot-source only. No top-level work.
#>

function ConvertTo-YamlDoubleQuotedScalar {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Test-YamlScalarNeedsQuoting {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $false }
    $trimmed = $Value.TrimStart()
    if ($trimmed.StartsWith('"') -or $trimmed.StartsWith("'") -or
        $trimmed.StartsWith('|') -or $trimmed.StartsWith('>') -or
        $trimmed.StartsWith('[') -or $trimmed.StartsWith('{')) {
        return $false
    }
    return $Value -match ': '
}

function Repair-SkillFrontmatterYamlText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $match = [regex]::Match($Content, '(?s)\A(?<open>---\r?\n)(?<yaml>.*?)(?<close>\r?\n---)(?<rest>[\s\S]*)\z')
    if (-not $match.Success) {
        return @{ Changed = $false; Content = $Content; Reason = 'no-frontmatter' }
    }

    $yaml = $match.Groups['yaml'].Value
    $newline = if ($match.Groups['open'].Value -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [regex]::Split($yaml, '\r?\n')
    $changed = $false
    $newLines = foreach ($line in $lines) {
        if ($line -match '^(?<k>[A-Za-z0-9][A-Za-z0-9_-]*):\s+(?<v>.*)$' -and
            (Test-YamlScalarNeedsQuoting -Value $Matches['v'])) {
            $changed = $true
            '{0}: {1}' -f $Matches['k'], (ConvertTo-YamlDoubleQuotedScalar -Value $Matches['v'])
        } else {
            $line
        }
    }

    if (-not $changed) {
        return @{ Changed = $false; Content = $Content; Reason = 'already-safe' }
    }

    $newYaml = [string]::Join($newline, $newLines)
    $newContent = $match.Groups['open'].Value + $newYaml + $match.Groups['close'].Value + $match.Groups['rest'].Value
    return @{ Changed = $true; Content = $newContent; Reason = 'quoted' }
}

function Repair-SkillFrontmatterYamlFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Apply
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @{ Changed = $false; Path = $Path; Reason = 'missing' }
    }

    $content = [IO.File]::ReadAllText($Path)
    $result = Repair-SkillFrontmatterYamlText -Content $content
    if ($result.Changed -and $Apply) {
        [IO.File]::WriteAllText($Path, $result.Content, [Text.UTF8Encoding]::new($false))
    }
    return @{
        Changed = [bool]$result.Changed
        Path    = $Path
        Reason  = $result.Reason
        Written = [bool]($result.Changed -and $Apply)
    }
}

function Repair-SkillFrontmatterYamlDirectory {
    param(
        [Parameter(Mandatory)][string]$SkillsRoot,
        [switch]$Apply,
        [string[]]$SkipPaths = @()
    )

    $scanned = 0
    $needsRepair = [Collections.Generic.List[string]]::new()
    $repaired = [Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $SkillsRoot -PathType Container)) {
        return @{
            Scanned     = 0
            Repaired    = 0
            NeedsRepair = @()
            SkillsRoot  = $SkillsRoot
        }
    }

    $skipSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($skip in @($SkipPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($skip)) {
            [void]$skipSet.Add([IO.Path]::GetFullPath($skip).TrimEnd('\', '/'))
        }
    }

    foreach ($dir in @(Get-ChildItem -LiteralPath $SkillsRoot -Directory -Force)) {
        $skillMd = Join-Path $dir.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) { continue }
        $scanned++
        $fullDir = [IO.Path]::GetFullPath($dir.FullName).TrimEnd('\', '/')
        if ($skipSet.Contains($fullDir)) { continue }

        $fileResult = Repair-SkillFrontmatterYamlFile -Path $skillMd -Apply:$Apply
        if ($fileResult.Changed) {
            $needsRepair.Add($skillMd)
            if ($fileResult.Written) { $repaired.Add($skillMd) }
        }
    }

    return @{
        Scanned     = $scanned
        Repaired    = $repaired.Count
        NeedsRepair = @($needsRepair)
        SkillsRoot  = $SkillsRoot
    }
}
