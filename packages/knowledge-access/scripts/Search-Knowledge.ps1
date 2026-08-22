#Requires -Version 5.1
<#
.SYNOPSIS
    Literal search over the documents knowledge tree.

.DESCRIPTION
    Prefers ripgrep-all (rga) so PDF/docx/xlsx/pptx are searchable.
    Falls back to rg, which only sees text files. Never walks the whole
    tree: pass -Root as a top-level folder name or a deeper path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Query,

    [string]$Root = '05',

    [string]$DocumentsRoot = 'D:\OneDrive - MahumTech\Documents',

    [int]$MaxCount = 50,

    [switch]$NamesOnly
)

$ErrorActionPreference = 'Stop'

$aliases = @{
    '02' = '02_Client_Work'
    '03' = '03_Products_and_Startups'
    '04' = '04_Career_and_Public_Profile'
    '05' = '05_Methodologies_Templates_and_Accelerators'
    '06' = '06_Research_and_Knowledge_Base'
}

$target = $Root
if ($aliases.ContainsKey($Root)) {
    $target = Join-Path $DocumentsRoot $aliases[$Root]
} elseif (-not [IO.Path]::IsPathRooted($Root)) {
    $target = Join-Path $DocumentsRoot $Root
}

if (-not (Test-Path -LiteralPath $target)) {
    throw "search root does not exist: $target"
}

if ($NamesOnly) {
    if (-not $rg) {
        $rg = Get-Command rg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $rg) { throw 'rg is required for -NamesOnly' }
    Write-Output "engine=rg-files root=$target"
    & $rg.Source --files --hidden --no-ignore --glob-case-insensitive -g "*${Query}*" $target
    exit $LASTEXITCODE
}

$rga = Get-Command rga -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$rg = Get-Command rg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

if ($rga) {
    Write-Output "engine=rga root=$target"
    & $rga.Source --files-with-matches --max-count $MaxCount $Query $target
    exit $LASTEXITCODE
}

# Upstream ships no Windows build (GitHub assets checked: darwin/linux only).
# WSL can run the musl binary against /mnt/<drive>/... paths.
$wslRga = $null
try {
    $wslRga = (wsl -e bash -lc 'command -v rga' 2>$null | Select-Object -First 1)
} catch {
    $wslRga = $null
}
if (-not [string]::IsNullOrWhiteSpace($wslRga)) {
    $drive = $target.Substring(0, 1).ToLowerInvariant()
    $rest = $target.Substring(2).Replace('\', '/')
    $wslPath = "/mnt/$drive$rest"
    Write-Output "engine=wsl-rga root=$wslPath"
    $inner = 'rga --files-with-matches --no-messages --max-count ' + [int]$MaxCount + ' -- ' +
        "'" + ($Query.Replace("'", "'\''")) + "' '" + ($wslPath.Replace("'", "'\''")) + "'"
    wsl -e bash -lc $inner
    exit $LASTEXITCODE
}

if ($rg) {
    Write-Output "engine=rg (text only; PDF/Office not searched) root=$target"
    & $rg.Source --files-with-matches -m $MaxCount -- $Query $target
    exit $LASTEXITCODE
}

throw 'neither rga, wsl rga, nor rg is available. Native Windows rga is not published; install the musl binary in WSL or BurntSushi.ripgrep.MSVC.'
