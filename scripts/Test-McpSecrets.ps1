#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot = "C:\Repos\agent-capabilities",
    [string]$UserProfile = "C:\Users\SaroshHussain",
    [string]$OutputJson = "$env:TEMP\agent-capabilities-mcp-secret-audit.json",
    [string]$OutputMd = "$env:TEMP\agent-capabilities-mcp-secret-audit.md"
)

$ErrorActionPreference = 'Stop'

function Read-JsonSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

$stateFile = Join-Path (Join-Path $env:LOCALAPPDATA 'AgentCapabilities\sync') 'sync-state.json'
$state = Read-JsonSafe $stateFile
if (-not $state) { throw "Missing sync state at $stateFile" }

$targets = @($state.managedFiles.PSObject.Properties.Name)
$findings = @()

$inlinePatterns = @(
    'Bearer\s+[A-Za-z0-9_\-\.]{20,}',
    'tvly-[A-Za-z0-9_\-]{20,}',
    'ctx7sk-[A-Za-z0-9_\-]{20,}',
    'BSA[A-Za-z0-9_\-]{16,}',
    '"(Authorization|api[-_]?key|token)"\s*:\s*"(?!\$\{)[^"]{16,}"'
)

foreach ($path in $targets) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach ($pattern in $inlinePatterns) {
        $matches = [regex]::Matches($raw, $pattern, 'IgnoreCase')
        foreach ($m in $matches) {
            $value = $m.Value
            $redacted = if ($value.Length -le 10) { '***' } else { $value.Substring(0, 6) + '***' + $value.Substring($value.Length - 4) }
            $findings += [pscustomobject]@{
                path = $path
                pattern = $pattern
                redactedMatch = $redacted
                severity = 'rotation-required'
            }
        }
    }
}

$report = [ordered]@{
    generatedAt = (Get-Date -Format o)
    managedFileCount = $targets.Count
    findingCount = $findings.Count
    findings = $findings
}

$outDir = Split-Path $OutputJson -Parent
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputJson -Encoding UTF8 -NoNewline

$md = @()
$md += '# MCP Migration Log'
$md += ''
$md += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ssK')"
$md += ''
$md += "- Managed files scanned: $($report.managedFileCount)"
$md += "- Potential inline secret findings: $($report.findingCount)"
$md += ''
$md += '## Rotation-Required Findings (Redacted)'
if ($findings.Count -eq 0) {
    $md += '- None found in managed files.'
} else {
    foreach ($f in $findings) {
        $md += "- $($f.path): $($f.redactedMatch)"
    }
}

$docDir = Split-Path $OutputMd -Parent
if (-not (Test-Path -LiteralPath $docDir)) { New-Item -ItemType Directory -Path $docDir -Force | Out-Null }
$md -join "`r`n" | Set-Content -LiteralPath $OutputMd -Encoding UTF8

Write-Host "Secret audit JSON: $OutputJson"
Write-Host "Migration log markdown: $OutputMd"
