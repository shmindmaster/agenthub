#Requires -Version 5.1
<#
Behavior tests for Test-MarkdownFrontmatter in scripts/Sync-AgentHub.ps1.

Why this file exists: Test-MarkdownFrontmatter piped candidate YAML through
`ConvertFrom-Yaml -ErrorAction SilentlyContinue`. SilentlyContinue suppresses
a cmdlet's own non-terminating errors before they can ever reach the
surrounding try/catch, so a genuinely malformed frontmatter block was never
reported -- the function always returned $true regardless of whether the
YAML actually parsed. A check whose failure path can never fire is
decoration, not validation.

This machine has no powershell-yaml module installed (ConvertFrom-Yaml does
not exist here), so a real malformed-YAML repro is not directly available.
A locally-defined `ConvertFrom-Yaml` function in this test's own scope
takes precedence over any module cmdlet of the same name for unqualified
calls -- exactly the PowerShell command-resolution rule that lets this test
simulate "the real cmdlet reported a non-terminating parse error" without
requiring the module to be present, while exercising the identical
-ErrorAction SilentlyContinue code path Test-MarkdownFrontmatter actually
uses.

Not a Pester suite, for the reasons recorded in Test-RegistryContentHash.ps1:
same accumulate-and-report idiom, one PASS/FAIL line per behavior, exit 1 if
any behavior did not hold.

Run: pwsh -NoProfile -File tests/Test-MarkdownFrontmatterValidation.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncPath = Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

# Pull Test-MarkdownFrontmatter out of the sync script without running the
# whole script (it has a param block and top-level work; dot-sourcing it
# directly would execute a sync).
$ast = [System.Management.Automation.Language.Parser]::ParseFile($syncPath, [ref]$null, [ref]$null)
$fnAst = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'Test-MarkdownFrontmatter'
    }, $true) | Select-Object -First 1

Report 'the sync script defines Test-MarkdownFrontmatter' ($null -ne $fnAst) `
    'Expected function Test-MarkdownFrontmatter in scripts/Sync-AgentHub.ps1.'
if (-not $fnAst) { Write-Host 'RESULT: 0 passed, 1 failed'; exit 1 }

# Simulate a real YAML parser: reports a non-terminating parse error only
# for input carrying a sentinel marker, and otherwise succeeds -- so this
# test can prove both directions (malformed frontmatter fails, well-formed
# frontmatter still passes) without depending on real YAML grammar. This
# function definition takes precedence over any real ConvertFrom-Yaml
# cmdlet for unqualified calls in this scope, regardless of whether the
# powershell-yaml module is installed on this machine.
function ConvertFrom-Yaml {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)] $InputObject)
    process {
        if ($InputObject -match 'SIMULATED_MALFORMED_YAML') {
            Write-Error 'simulated malformed YAML: mapping values are not allowed in this context'
        } else {
            return @{ parsed = $true }
        }
    }
}

. ([scriptblock]::Create($fnAst.Extent.Text))

function New-FrontmatterFixture([string]$Body) {
    $p = Join-Path ([IO.Path]::GetTempPath()) ("frontmatter-fixture-" + [guid]::NewGuid().ToString('N') + '.md')
    [IO.File]::WriteAllText($p, $Body, [Text.UTF8Encoding]::new($false))
    return $p
}

# 1. Malformed frontmatter must be reported as invalid, not silently passed.
$script:validationErrors = @()
$badPath = New-FrontmatterFixture "---`nkey: SIMULATED_MALFORMED_YAML`n---`nbody text`n"
try {
    $ok = Test-MarkdownFrontmatter -Path $badPath
    Report 'malformed frontmatter is reported invalid, not silently passed' (-not $ok) `
        "Test-MarkdownFrontmatter returned `$true for malformed YAML frontmatter (the -ErrorAction SilentlyContinue defect: a real parse error can never reach the try/catch)."
    Report 'malformed frontmatter records a validation error' ($script:validationErrors.Count -gt 0) `
        'Expected at least one entry in $script:validationErrors for malformed frontmatter.'
} finally {
    Remove-Item -LiteralPath $badPath -Force -ErrorAction SilentlyContinue
}

# 2. A file with no frontmatter delimiter at all is untouched by the YAML
#    parser and must still pass -- this guards against an overcorrection
#    that starts flagging every ordinary markdown file.
$script:validationErrors = @()
$plainPath = New-FrontmatterFixture "# Just a heading`n`nNo frontmatter here.`n"
try {
    $okPlain = Test-MarkdownFrontmatter -Path $plainPath
    Report 'a file with no frontmatter block still passes' $okPlain `
        "Test-MarkdownFrontmatter returned `$false for a file with no frontmatter delimiter at all."
} finally {
    Remove-Item -LiteralPath $plainPath -Force -ErrorAction SilentlyContinue
}

# 3. Well-formed frontmatter (no sentinel marker) still passes -- proves the
#    fix is not a blanket "always fail" overcorrection, and that the
#    delimiter-block regex actually extracts and submits the YAML body.
$script:validationErrors = @()
$goodPath = New-FrontmatterFixture "---`ntitle: Fixture`ntags: [a, b]`n---`nbody text`n"
try {
    $okGood = Test-MarkdownFrontmatter -Path $goodPath
    Report 'well-formed frontmatter still passes' $okGood `
        "Test-MarkdownFrontmatter returned `$false for well-formed frontmatter with no simulated parse error."
    Report 'well-formed frontmatter records no validation error' ($script:validationErrors.Count -eq 0) `
        "Expected zero entries in `$script:validationErrors; got: $($script:validationErrors -join '; ')"
} finally {
    Remove-Item -LiteralPath $goodPath -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
