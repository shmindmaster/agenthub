#Requires -Version 5.1
<#
.SYNOPSIS
    Generate _MAP.md for the documents knowledge tree.

.DESCRIPTION
    Writes a depth-3 directory listing with file counts and sizes for
    folders 02 through 06. Do not hand-edit the output file.
#>
[CmdletBinding()]
param(
    [string]$DocumentsRoot = 'D:\OneDrive - MahumTech\Documents',
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = Join-Path $DocumentsRoot '_MAP.md'
}

$roots = @(
    '02_Client_Work',
    '03_Products_and_Startups',
    '04_Career_and_Public_Profile',
    '05_Methodologies_Templates_and_Accelerators',
    '06_Research_and_Knowledge_Base'
)

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Knowledge Map')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(("Generated {0}. Do not hand-edit." -f (Get-Date -Format 'yyyy-MM-dd HH:mm')))
[void]$sb.AppendLine('')

foreach ($name in $roots) {
    $r = Join-Path $DocumentsRoot $name
    [void]$sb.AppendLine("## $name")
    [void]$sb.AppendLine('')
    if (-not (Test-Path -LiteralPath $r)) {
        [void]$sb.AppendLine("_missing on this machine_")
        [void]$sb.AppendLine('')
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
    [void]$sb.AppendLine('')
}

$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($OutFile, $sb.ToString(), $utf8)
Write-Output "Wrote $OutFile"
