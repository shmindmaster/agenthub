#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieve layered evidence to augment a document you are writing.

.DESCRIPTION
    Queries the Local-AI Qdrant `knowledge` collection once per layer
    (method, precedent, recent product work, market context, voice) and
    returns material for each, with a rendering mode attached to every item.

    This is an augmentation step, not a gate. It returns material to use.
    It does not score an opportunity or advise whether to pursue it.

    Describe the STRUCTURE of the problem in -Shape, not the job title.
    Role vocabulary retrieves your own resumes back; problem shape
    retrieves your actual work. Reusable shape sets for recurring role
    archetypes live in references/opportunity-shape-library.md.

    Layers, rendering modes and descriptors are data, not code:
    config/evidence-layers.json.

.PARAMETER Shape
    Problem-shape primitive. Repeatable.

.PARAMETER ShapesFile
    File of shapes, one per line. Lines beginning '#' are ignored.
    Combine with -Shape to extend a library set for one opportunity.

.EXAMPLE
    .\Get-EvidenceAugmentation.ps1 -Label 'Netflix - Sr EM, Agent Platform' `
        -Shape 'shared internal platform many teams build on, with standards and onboarding governance' `
        -Shape 'driving migration of business units onto one standard and measuring adoption'

.EXAMPLE
    .\Get-EvidenceAugmentation.ps1 -Label 'Upwork - Azure AI Search consultant' `
        -ShapesFile ..\references\shapes\hands-on-retrieval-delivery.txt -PerLayer 3
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Label,

    [string[]]$Shape,

    [string]$ShapesFile,

    [int]$PerLayer = 5,

    [int]$Pool,

    [string]$Out = 'evidence-augmentation',

    [string]$LocalAiRoot = $(if ($env:LOCAL_AI_ROOT) { $env:LOCAL_AI_ROOT } else { 'D:\Local-AI' })
)

$ErrorActionPreference = 'Stop'

if (-not $Shape -and -not $ShapesFile) {
    throw 'Supply at least one -Shape or a -ShapesFile.'
}

$scriptDir = $PSScriptRoot
$entry = Join-Path $scriptDir 'evidence_augmentation.py'
if (-not (Test-Path -LiteralPath $entry)) {
    throw "evidence_augmentation.py not found beside this script ($entry)"
}

# Reuse the Python runtime Local-AI already resolves for retrieval.
$registryPath = Join-Path $LocalAiRoot 'registry.json'
if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "registry.json not found under $LocalAiRoot"
}
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
$runtime = ($registry.services | Where-Object { $_.id -eq 'retrieval' }).runtime
if (-not $runtime -or -not (Test-Path -LiteralPath $runtime)) {
    throw "retrieval runtime not found in registry: $runtime"
}

$argList = @($entry, '--label', $Label, '--per-layer', "$PerLayer", '--out', $Out)
foreach ($s in $Shape) { $argList += @('--shape', $s) }
if ($ShapesFile) {
    $resolved = (Resolve-Path -LiteralPath $ShapesFile).Path
    $argList += @('--shapes-file', $resolved)
}
if ($PSBoundParameters.ContainsKey('Pool')) { $argList += @('--pool', "$Pool") }

& $runtime @argList
exit $LASTEXITCODE
