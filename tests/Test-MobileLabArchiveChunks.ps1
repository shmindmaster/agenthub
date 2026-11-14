#Requires -Version 5.1
<#
Behavior tests for Split-MobileLabArchive (SH-4390): the remote lab driver
sends source archives to the worker in chunks because Windows OpenSSH resets
a single large stream on some hosts. The split must be lossless, ordered and
bounded. Local and non-mutating beyond a temp folder it removes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
Import-Module (Join-Path $repoRoot 'packages\mobile-development\MobileDevelopment.psm1') -Force

$passed = 0
$failed = 0
function Report([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Output "PASS: $Name" }
    else { $script:failed++; Write-Output "FAIL: $Name -- $Detail" }
}
function Throws([scriptblock]$Block) {
    try { & $Block | Out-Null; return $false } catch { return $true }
}
function New-TestFile([string]$Path, [int]$Size) {
    $bytes = New-Object byte[] $Size
    for ($i = 0; $i -lt $Size; $i++) { $bytes[$i] = [byte]($i % 251) }
    [IO.File]::WriteAllBytes($Path, $bytes)
}
function Get-Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "mobile-lab-chunk-test-$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # 3.5 MB in 1 MB chunks: four chunks, the last one partial.
    $src = Join-Path $tmp 'source.tar'
    New-TestFile $src (3.5MB)
    $chunks = @(Split-MobileLabArchive -Path $src -Destination (Join-Path $tmp 'split') -ChunkSize 1MB)
    Report 'a 3.5 MB archive splits into four 1 MB chunks' `
        ($chunks.Count -eq 4) "count=$($chunks.Count)"
    Report 'chunk names are zero-padded and ordered' `
        ((@($chunks | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ',') -eq 'chunk-000,chunk-001,chunk-002,chunk-003')
    $sizesOk = ((Get-Item -LiteralPath $chunks[0]).Length -eq 1MB) -and ((Get-Item -LiteralPath $chunks[3]).Length -eq 0.5MB)
    Report 'the last chunk carries the remainder' $sizesOk

    # Reassembly in name order must reproduce the original byte for byte.
    $joined = Join-Path $tmp 'joined.tar'
    $out = [IO.File]::Create($joined)
    try {
        foreach ($chunk in ($chunks | Sort-Object { [IO.Path]::GetFileName($_) })) {
            $bytes = [IO.File]::ReadAllBytes($chunk)
            $out.Write($bytes, 0, $bytes.Length)
        }
    } finally { $out.Dispose() }
    Report 'reassembled chunks match the original hash' `
        ((Get-Sha $joined) -eq (Get-Sha $src))

    # An exact multiple produces no empty trailing chunk.
    $exact = Join-Path $tmp 'exact.tar'
    New-TestFile $exact 2MB
    $exactChunks = @(Split-MobileLabArchive -Path $exact -Destination (Join-Path $tmp 'exact-split') -ChunkSize 1MB)
    Report 'an exact multiple produces no empty trailing chunk' `
        ($exactChunks.Count -eq 2) "count=$($exactChunks.Count)"

    Report 'an empty archive is refused' `
        (Throws { $empty = Join-Path $tmp 'empty.tar'; [IO.File]::WriteAllBytes($empty, @()); Split-MobileLabArchive -Path $empty -Destination (Join-Path $tmp 'empty-split') -ChunkSize 1MB })
    Report 'a missing archive is refused' `
        (Throws { Split-MobileLabArchive -Path (Join-Path $tmp 'absent.tar') -Destination (Join-Path $tmp 'absent-split') })
    Report 'a chunk size under 1 MB is refused' `
        (Throws { Split-MobileLabArchive -Path $src -Destination (Join-Path $tmp 'small-split') -ChunkSize 512KB })
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
