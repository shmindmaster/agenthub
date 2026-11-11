#Requires -Version 5.1
<#
.SYNOPSIS
  Turn saved RepoWise health, dead-code and risk output into one findings file
  with reproducible evidence. READ-ONLY: it never creates, edits or closes an
  issue anywhere.

.DESCRIPTION
  Part of the AgentHub RepoWise cloud recipe (SH-4410); see
  docs/runbooks/repowise-cloud.md.

  On the index host the operator captures:
      repowise health    --format json > health.json
      repowise dead-code --format json > dead-code.json
      repowise risk      --format json > risk.json
  (exact flag names are recorded in the evidence block; capture whatever the
  installed version emits).

  This script reads those files, hashes each input, normalizes what it can,
  and writes a single findings JSON:

    generatedUtc, repository, revision, repowiseVersion,
    crossCheck: { issueId, evaluation } -- evaluation is always
        "not-performed-read-only"; the field exists so a human can carry an
        existing tracker id next to the findings. This script cannot confirm
        the issue, and it files nothing.
    evidence: per input { source, command, inputFile, sha256, itemCount } so
        every finding can be regenerated from named inputs at a named revision
    findings: normalized items { source, severity, summary, location }

  Anything the parser does not recognize is preserved verbatim (truncated) in
  the finding's summary rather than dropped.

.EXAMPLE
  pwsh -NoProfile -File New-RepoWiseFindings.ps1 -Repository example-repo-a `
      -Revision 0123456789abcdef -HealthPath .\health.json -DeadCodePath .\dead-code.json `
      -RiskPath .\risk.json -OutFile .\findings.json -IssueId SH-4000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Revision,
    [string]$RepoWiseVersion = 'not-captured',
    [Parameter(Mandatory)][string]$HealthPath,
    [Parameter(Mandatory)][string]$DeadCodePath,
    [Parameter(Mandatory)][string]$RiskPath,
    [Parameter(Mandatory)][string]$OutFile,
    [string]$IssueId
)

$ErrorActionPreference = 'Stop'

function Read-SourceJson([string]$Path, [string]$Source) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Source output not found: $Path" }
    # [IO.File] resolves against the process directory, not the PowerShell
    # location, so hand it a full path.
    $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    try { $doc = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json }
    catch { throw "$Source output at $Path is not JSON" }
    return @{ Document = $doc; Sha256 = $sha }
}

function Get-Items($Document) {
    # Best-effort: arrays become findings; objects contribute their first array
    # property (repowise reports usually wrap rows in a named list); anything
    # else becomes one finding carrying the whole document.
    if ($null -eq $Document) { return @() }
    if ($Document -is [array]) { return @($Document) }
    if ($Document -is [pscustomobject]) {
        foreach ($prop in $Document.PSObject.Properties) {
            if ($prop.Value -is [array] -and $prop.Value.Count -gt 0) { return @($prop.Value) }
        }
        return @($Document)
    }
    return @($Document)
}

function Get-Field($Item, [string[]]$Names) {
    if ($Item -isnot [pscustomobject]) { return $null }
    foreach ($name in $Names) {
        $value = $Item.PSObject.Properties[$name]
        if ($value -and $null -ne $value.Value -and "$($value.Value)" -ne '') { return "$($value.Value)" }
    }
    return $null
}

function ConvertTo-Finding($Item, [string]$Source) {
    $summary = Get-Field $Item @('summary', 'title', 'message', 'name', 'symbol', 'rule', 'metric')
    $location = Get-Field $Item @('location', 'file', 'path', 'filePath')
    $line = Get-Field $Item @('line', 'startLine')
    $severity = Get-Field $Item @('severity', 'level', 'score')
    if (-not $summary) {
        $summary = ($Item | ConvertTo-Json -Compress -Depth 6)
        if ($summary.Length -gt 300) { $summary = $summary.Substring(0, 300) + '...' }
    }
    if ($location -and $line) { $location = "$location`:$line" }
    return [ordered]@{ source = $Source; severity = $(if ($severity) { $severity } else { 'info' })
        summary = $summary; location = $location }
}

$sources = @(
    @{ Name = 'health';    Path = $HealthPath;   Command = 'repowise health --format json' }
    @{ Name = 'dead-code'; Path = $DeadCodePath; Command = 'repowise dead-code --format json' }
    @{ Name = 'risk';      Path = $RiskPath;     Command = 'repowise risk --format json' }
)

$evidence = [Collections.Generic.List[object]]::new()
$findings = [Collections.Generic.List[object]]::new()
foreach ($source in $sources) {
    $read = Read-SourceJson $source.Path $source.Name
    $items = @(Get-Items $read.Document)
    $evidence.Add([ordered]@{ source = $source.Name; command = $source.Command
        inputFile = (Resolve-Path -LiteralPath $source.Path).Path; sha256 = $read.Sha256; itemCount = $items.Count })
    foreach ($item in $items) { $findings.Add([pscustomobject](ConvertTo-Finding $item $source.Name)) }
}

$report = [ordered]@{
    generatedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    repository = $Repository
    revision = $Revision
    repowiseVersion = $RepoWiseVersion
    crossCheck = [ordered]@{ issueId = $(if ($IssueId) { $IssueId } else { $null })
        evaluation = 'not-performed-read-only' }
    evidence = @($evidence)
    findings = @($findings)
}
[IO.File]::WriteAllText($OutFile, ($report | ConvertTo-Json -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "findings: $($findings.Count) item(s) -> $OutFile (issue cross-check: $($report.crossCheck.evaluation))"
exit 0
