#Requires -Version 5.1
<#
.SYNOPSIS
    Build the thin agent index for the documents knowledge tree.

.DESCRIPTION
    Agents time out walking 02-06. This writes four small, always-read
    artifacts so they never glob the corpus:

      _INDEX.md           router (read this first)
      _maps/<root>.md     depth-3 tree for one folder
      _CATALOG.md         high-signal filenames only
      _ENGAGEMENTS.md     02 path taxonomy (sector/industry/client/year)

    _MAP.md is rewritten as a pointer to those files, not a 6k-line dump.
#>
[CmdletBinding()]
param(
    [string]$DocumentsRoot = 'D:\OneDrive - MahumTech\Documents',
    [switch]$CatalogOnly
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)

$roots = @(
    '02_Client_Work',
    '03_Products_and_Startups',
    '04_Career_and_Public_Profile',
    '05_Methodologies_Templates_and_Accelerators',
    '06_Research_and_Knowledge_Base'
)

$mapDir = Join-Path $DocumentsRoot '_maps'
if (-not (Test-Path -LiteralPath $mapDir)) {
    New-Item -ItemType Directory -Path $mapDir | Out-Null
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

# --- per-root maps (same tree as before, one file each) ---
if (-not $CatalogOnly) {
foreach ($name in $roots) {
    $r = Join-Path $DocumentsRoot $name
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# $name")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Generated $stamp. Do not hand-edit.")
    [void]$sb.AppendLine('')
    if (-not (Test-Path -LiteralPath $r)) {
        [void]$sb.AppendLine('_missing on this machine_')
        Write-Utf8 (Join-Path $mapDir "$name.md") $sb.ToString()
        continue
    }
    Get-ChildItem -LiteralPath $r -Directory -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object {
            $rel = $_.FullName.Substring($r.Length).TrimStart('\')
            $depth = @($rel -split '\\').Count - 1
            $files = @(Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction SilentlyContinue)
            $note = ''
            if ($files.Count -gt 0) {
                $mb = [math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 1)
                $note = " — $($files.Count) files, $mb MB"
            }
            [void]$sb.AppendLine(('  ' * $depth) + "- $($_.Name)$note")
        }
    $out = Join-Path $mapDir "$name.md"
    Write-Utf8 $out $sb.ToString()
    Write-Output "Wrote $out"
}
}

# --- catalog: high-signal filenames via rg --files (no content scan) ---
$globs = @(
    '*proposal*', '*architecture*', '*sow*', '*statement*of*work*',
    '*case*stud*', '*integration*', '*kickoff*', '*operating*model*',
    '*itsm*', '*rfp*', '*solution*design*', '*agent*platform*',
    '*claim*matrix*', '*resume*', '*walkthrough*', '*design*doc*'
)
$rg = Get-Command rg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$catalogLines = [System.Collections.Generic.List[string]]::new()
[void]$catalogLines.Add('# High-signal catalog')
[void]$catalogLines.Add('')
[void]$catalogLines.Add("Generated $stamp. Filenames only. Do not hand-edit.")
[void]$catalogLines.Add('')
[void]$catalogLines.Add('Use this to pick a file, then read that file. Do not recurse.')
[void]$catalogLines.Add('')

if ($rg) {
    foreach ($name in $roots) {
        $r = Join-Path $DocumentsRoot $name
        if (-not (Test-Path -LiteralPath $r)) { continue }
        [void]$catalogLines.Add("## $name")
        [void]$catalogLines.Add('')
        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($g in $globs) {
            $found = & $rg.Source --files --hidden --no-ignore --glob-case-insensitive -g $g $r 2>$null
            foreach ($f in @($found)) {
                if (-not $f) { continue }
                if ($f -match '\\(\.codex_work|_archive|node_modules|\.git)\\') { continue }
                [void]$hits.Add($f)
            }
        }
        $uniq = $hits | Sort-Object -Unique
        foreach ($f in $uniq) {
            $rel = $f.Substring($DocumentsRoot.Length).TrimStart('\')
            [void]$catalogLines.Add("- $rel")
        }
        [void]$catalogLines.Add('')
        Write-Output ("catalog {0}: {1} files" -f $name, @($uniq).Count)
    }
} else {
    [void]$catalogLines.Add('_rg not on PATH; catalog not generated_')
}
Write-Utf8 (Join-Path $DocumentsRoot '_CATALOG.md') (($catalogLines -join "`n") + "`n")
Write-Output "Wrote $(Join-Path $DocumentsRoot '_CATALOG.md')"

# --- engagement index from 02 path taxonomy ---
$engRoot = Join-Path $DocumentsRoot '02_Client_Work'
$engSb = [System.Text.StringBuilder]::new()
[void]$engSb.AppendLine('# Engagement index (path taxonomy)')
[void]$engSb.AppendLine('')
[void]$engSb.AppendLine("Generated $stamp. Derived from folder names only.")
[void]$engSb.AppendLine('')
[void]$engSb.AppendLine('| Sector | Industry | Client | Engagement | Files | MB |')
[void]$engSb.AppendLine('| --- | --- | --- | --- | --- | --- |')
if (Test-Path -LiteralPath $engRoot) {
    Get-ChildItem -LiteralPath $engRoot -Directory -Force |
        Where-Object { $_.Name -match '^\d{2}_' } |
        Sort-Object Name |
        ForEach-Object {
            $sector = $_.Name
            Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue |
                Sort-Object Name |
                ForEach-Object {
                    $industry = $_.Name
                    Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue |
                        Sort-Object Name |
                        ForEach-Object {
                            $client = $_.Name
                            Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue |
                                Sort-Object Name |
                                ForEach-Object {
                                    $eng = $_.Name
                                    $files = @(Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)
                                    $mb = 0
                                    if ($files.Count -gt 0) {
                                        $mb = [math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 1)
                                    }
                                    [void]$engSb.AppendLine("| $sector | $industry | $client | $eng | $($files.Count) | $mb |")
                                }
                        }
                }
        }
}
Write-Utf8 (Join-Path $DocumentsRoot '_ENGAGEMENTS.md') $engSb.ToString()
Write-Output "Wrote $(Join-Path $DocumentsRoot '_ENGAGEMENTS.md')"

# --- router ---
$index = @"
# Knowledge index

Generated $stamp. **Read this file first.** Do not open `_MAP.md` as a
full tree (it is a pointer). Do not ``Get-ChildItem -Recurse`` the
Documents root. Do not use the Portfolio Audit skill here — that skill
is for git repos under ``C:\Repos``.

## Authority

1. The file on disk.
2. ``AGENTS.md`` in this folder (output rules, including no client names).
3. This index, then one of the files below.

## Where to look

| Need | File |
| --- | --- |
| Which top-level folder? | this file |
| Folder tree for one root | ``_maps/<root>.md`` |
| Proposal / architecture / SOW / case-study filenames | ``_CATALOG.md`` |
| Client-work engagements by sector/industry/year | ``_ENGAGEMENTS.md`` |
| Career claims that may be published | ``04_Career_and_Public_Profile/FINAL_CAREER_BRAND_PACKAGE/18_Claim_Matrix_Public_Safe.md`` |
| Literal string inside PDF/Office | ``Search-Knowledge.ps1 -Query ... -Root 02`` (or 03–06), never unscoped |

## Roots

- ``02_Client_Work`` — GICS Sector / Industry / Client / YYYY_Engagement
- ``03_Products_and_Startups`` — Pendoah services vs MahumTech private ventures (not the same)
- ``04_Career_and_Public_Profile`` — resumes, claim matrix, brand package
- ``05_Methodologies_Templates_and_Accelerators`` — Domain / NNNN_Topic
- ``06_Research_and_Knowledge_Base`` — research notes

## Search contract

1. Read this index.
2. Open at most one ``_maps/*.md`` or a section of ``_CATALOG.md`` / ``_ENGAGEMENTS.md``.
3. ``Search-Knowledge.ps1`` scoped to that branch (``-Root 05`` or a deeper path).
4. Read only the files returned.
5. For a resume or application, reconcile every claim against
   ``18_Claim_Matrix_Public_Safe.md`` before it leaves this tree.
   Client names stay anonymized unless that matrix (or the owner this
   turn) cleared them.

Generated artifacts live next to this file. Regenerated by
``packages/knowledge-access/scripts/New-KnowledgeIndex.ps1``.
"@
Write-Utf8 (Join-Path $DocumentsRoot '_INDEX.md') $index
Write-Utf8 (Join-Path $DocumentsRoot '_MAP.md') @"
# Knowledge Map

Generated $stamp. Do not hand-edit.

This file is a **pointer**, not the tree. Agents that read the whole
former 6k-line map stall. Start at ``_INDEX.md``.

- Router: ``_INDEX.md``
- Per-root trees: ``_maps/``
- High-signal filenames: ``_CATALOG.md``
- Engagement taxonomy: ``_ENGAGEMENTS.md``
"@
Write-Output "Wrote _INDEX.md and pointer _MAP.md"
