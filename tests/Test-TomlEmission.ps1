#Requires -Version 5.1
<#
Behavior tests for the TOML emission in scripts/Sync-AgentHub.ps1.

Why this file exists: on 2026-08-19 a sync wrote every Windows path into a TOML
*basic* string, so `command = "C:\Users\..."` made `\U` an invalid unicode
escape and both TOML hosts (codex, grok) stopped parsing their whole config.
A second defect emitted `[mcp_servers.<name>.env]` once per environment
variable, redefining a table TOML only allows once. Neither is visible to a
text assertion that merely greps for a function name -- the emitted string has
to be handed to a real TOML parser, and the pre-fix form has to be shown to
fail, or the test proves nothing.

Not a Pester suite, for the reasons recorded in Test-RegistryContentHash.ps1:
same accumulate-and-report idiom, one PASS/FAIL line per behavior, exit 1 if
any behavior did not hold.

Run: pwsh -NoProfile -File tests/Test-TomlEmission.ps1
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

# Pull the emitter out of the sync script without running the script: it has a
# param block and top-level work, so dot-sourcing it would execute a sync.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($syncPath, [ref]$null, [ref]$null)
$fnAst = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'ConvertTo-TomlString'
    }, $true) | Select-Object -First 1

Report 'the sync script defines a dedicated TOML string emitter' ($null -ne $fnAst) `
    'Expected function ConvertTo-TomlString in scripts/Sync-AgentHub.ps1.'
if (-not $fnAst) { Write-Host 'RESULT: 0 passed, 1 failed'; exit 1 }
. ([scriptblock]::Create($fnAst.Extent.Text))

# A real parser is the only honest oracle here.
$python = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $python) {
    Report 'a TOML parser is available to verify emission' $false 'python (tomllib) not found on PATH.'
    Write-Host 'RESULT: aborted'; exit 1
}

function Test-TomlRoundTrip {
    <# Returns the parsed value of key `k`, or $null when the document is invalid. #>
    param([string]$DocumentText)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("toml-emit-" + [guid]::NewGuid().ToString('N') + ".toml")
    $reader = Join-Path ([IO.Path]::GetTempPath()) ("toml-read-" + [guid]::NewGuid().ToString('N') + ".py")
    try {
        [IO.File]::WriteAllText($tmp, $DocumentText, [Text.UTF8Encoding]::new($false))
        $py = @(
            'import sys, tomllib'
            'try:'
            '    d = tomllib.load(open(sys.argv[1], "rb"))'
            'except Exception:'
            '    print("__INVALID__"); raise SystemExit(0)'
            'print(d.get("k", "__MISSING__"))'
        ) -join "`n"
        [IO.File]::WriteAllText($reader, $py, [Text.UTF8Encoding]::new($false))
        $out = (& python $reader $tmp 2>&1 | Out-String).Trim()
        if ($out -eq '__INVALID__') { return $null }
        return $out
    } finally {
        Remove-Item -LiteralPath $tmp, $reader -Force -ErrorAction SilentlyContinue
    }
}

$winPath = 'C:\Users\SaroshHussain\AppData\Local\AgentHub\bin\Hide-Stdio.exe'

# 1. The fix: a Windows path survives emission and parses back identically.
$emitted = ConvertTo-TomlString $winPath
$parsed = Test-TomlRoundTrip ("k = " + $emitted)
Report 'a Windows path round-trips through a real TOML parser' ($parsed -eq $winPath) `
    "Emitted [$emitted] parsed back as [$parsed], expected [$winPath]."

# 2. The guard can fail: the pre-fix basic-string form must be rejected. A check
#    that cannot fail is decoration, and this is the exact form that shipped.
$preFix = '"' + $winPath + '"'
$preFixParsed = Test-TomlRoundTrip ("k = " + $preFix)
Report 'the pre-fix basic-string form is demonstrably rejected' ($null -eq $preFixParsed) `
    "Basic string [$preFix] parsed as [$preFixParsed]; it must be invalid, or this suite proves nothing."

# 3. Values a literal string cannot hold fall back to an escaped basic string.
$quoted = "C:\it's\path"
$emittedQuoted = ConvertTo-TomlString $quoted
$parsedQuoted = Test-TomlRoundTrip ("k = " + $emittedQuoted)
Report 'a value containing a single quote still round-trips' ($parsedQuoted -eq $quoted) `
    "Emitted [$emittedQuoted] parsed back as [$parsedQuoted], expected [$quoted]."

# 4. The grok writer must emit the env table header once, not once per variable.
$syncText = Get-Content -LiteralPath $syncPath -Raw -Encoding UTF8
$grokEnvBlock = [regex]::Match($syncText, 'if \(\$mcp\.env\) \{(?<body>.*?)\r?\n            \}', 'Singleline')
$headerOutsideLoop = $false
if ($grokEnvBlock.Success) {
    $body = $grokEnvBlock.Groups['body'].Value
    $headerIdx = $body.IndexOf('.env]')
    $loopIdx = $body.IndexOf('foreach')
    $headerOutsideLoop = ($headerIdx -ge 0 -and $loopIdx -ge 0 -and $headerIdx -lt $loopIdx)
}
Report 'the env table header is emitted once, not once per variable' $headerOutsideLoop `
    'TOML rejects a redefined table; [mcp_servers.<name>.env] must precede the foreach, not sit inside it.'

# 5. End state: every deployed TOML host config actually parses.
$tomlHosts = @(
    @{ Host = 'codex'; Path = (Join-Path $env:USERPROFILE '.codex\config.toml') }
    @{ Host = 'grok';  Path = (Join-Path $env:USERPROFILE '.grok\config.toml') }
)
foreach ($h in $tomlHosts) {
    if (-not (Test-Path -LiteralPath $h.Path)) {
        Report "deployed $($h.Host) config parses" $true "absent, skipped: $($h.Path)"
        continue
    }
    # Parse the file directly rather than through the k= helper: we want the
    # document's validity, not the value of any particular key.
    $tmpReader = Join-Path ([IO.Path]::GetTempPath()) ("toml-host-" + [guid]::NewGuid().ToString('N') + ".py")
    [IO.File]::WriteAllText($tmpReader, "import sys, tomllib`ntry:`n    tomllib.load(open(sys.argv[1], 'rb'))`n    print('OK')`nexcept Exception as e:`n    print('INVALID: ' + str(e))", [Text.UTF8Encoding]::new($false))
    $res = (& python $tmpReader $h.Path 2>&1 | Out-String).Trim()
    Remove-Item -LiteralPath $tmpReader -Force -ErrorAction SilentlyContinue
    Report "deployed $($h.Host) config parses" ($res -eq 'OK') $res
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
