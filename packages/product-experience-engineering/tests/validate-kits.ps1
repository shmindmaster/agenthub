$ErrorActionPreference = 'Stop'

# Behavior tests for kits/execution-controls and kits/demo-harness. Every child
# process runs windowless; the demo-stack check starts and stops a fixture
# service on 127.0.0.1 and leaves nothing running.

$pluginRoot = Split-Path -Parent $PSScriptRoot
$kits = Join-Path $pluginRoot 'kits'
$node = (Get-Command node -ErrorAction Stop).Source
$pythonNames = if ($env:OS -eq 'Windows_NT') { @('python', 'python3') } else { @('python3', 'python') }
$python = (Get-Command $pythonNames -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $python) { throw "Python 3 not found on PATH (looked for $($pythonNames -join ', '))." }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("pee-kits-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temporary | Out-Null

function Invoke-Checked {
    param([string]$Name, [string]$File, [string[]]$Arguments, [int]$Expected = 0, [string]$Expect)
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $File @Arguments 2>&1 | Out-String
        $actual = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($actual -ne $Expected) { throw "$Name expected exit $Expected, got $actual.`n$output" }
    if ($Expect -and $output -notmatch [regex]::Escape($Expect)) { throw "$Name output lacks '$Expect'.`n$output" }
    return $output
}

try {
    # 1. Reference implementations against the shared vectors (both languages).
    Invoke-Checked 'TypeScript kit tests' $node @('--test', (Join-Path $kits 'execution-controls\ts\test\')) | Out-Null
    Invoke-Checked 'Python kit tests' $python @('-m', 'unittest', 'discover', '-s', (Join-Path $kits 'execution-controls\python\tests')) | Out-Null

    # 1b. Strict typecheck of the TypeScript a product vendors (tsconfig: strict,
    # exactOptionalPropertyTypes, noUnused*). AgentHub carries no TypeScript
    # dependency, so point EXECUTION_CONTROLS_TSC at a typescript/bin/tsc and
    # EXECUTION_CONTROLS_TYPE_ROOTS at a node_modules/@types that has `node`.
    if ($env:EXECUTION_CONTROLS_TSC -and $env:EXECUTION_CONTROLS_TYPE_ROOTS) {
        Invoke-Checked 'strict tsc over vendored TypeScript' $node @($env:EXECUTION_CONTROLS_TSC, '-p', (Join-Path $kits 'execution-controls/ts/tsconfig.json'), '--typeRoots', $env:EXECUTION_CONTROLS_TYPE_ROOTS) | Out-Null
    } else {
        'SKIP: strict tsc over vendored TypeScript (set EXECUTION_CONTROLS_TSC and EXECUTION_CONTROLS_TYPE_ROOTS to run it).'
    }

    # 2. Vendoring: a fresh copy checks clean; an edited copy fails.
    $vendorScript = Join-Path $pluginRoot 'scripts\vendor-execution-controls.mjs'
    foreach ($lang in 'python', 'ts') {
        $dest = Join-Path $temporary "vendored-$lang"
        Invoke-Checked "vendor $lang" $node @($vendorScript, '--lang', $lang, '--dest', $dest) | Out-Null
        Invoke-Checked "check $lang" $node @($vendorScript, '--check', '--dest', $dest) -Expect 'PASS' | Out-Null
    }
    $edited = Join-Path $temporary 'vendored-python\approval_capsule.py'
    Add-Content -LiteralPath $edited -Value '# local edit'
    Invoke-Checked 'check edited copy' $node @($vendorScript, '--check', '--dest', (Join-Path $temporary 'vendored-python')) -Expected 1 -Expect 'edited after vendoring' | Out-Null
    # An extra file in a vendored copy is drift too; generated __pycache__ is not.
    $tsDest = Join-Path $temporary 'vendored-ts'
    $extra = Join-Path $tsDest 'extra.ts'
    [IO.File]::WriteAllText($extra, "export const extra = 1;`n", (New-Object System.Text.UTF8Encoding($false)))
    Invoke-Checked 'check copy with an extra file' $node @($vendorScript, '--check', '--dest', $tsDest) -Expected 1 -Expect 'extra.ts: not in the manifest' | Out-Null
    Remove-Item -LiteralPath $extra
    Invoke-Checked 'check after removing the extra file' $node @($vendorScript, '--check', '--dest', $tsDest) -Expect 'PASS' | Out-Null
    $pyDest = Join-Path $temporary 'vendored-python-cache'
    Invoke-Checked 'vendor python again' $node @($vendorScript, '--lang', 'python', '--dest', $pyDest) | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $pyDest '__pycache__') | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $pyDest '__pycache__\approval_capsule.cpython-313.pyc'), [byte[]](0, 1, 2))
    Invoke-Checked 'check ignores __pycache__' $node @($vendorScript, '--check', '--dest', $pyDest) -Expect 'PASS' | Out-Null
    # A manifest entry for a file the kit does not ship is drift even when the file is present and matches.
    $ghost = Join-Path $tsDest 'ghost.ts'
    [IO.File]::WriteAllText($ghost, "export const ghost = 1;`n", (New-Object System.Text.UTF8Encoding($false)))
    $manifestFile = Join-Path $tsDest 'KIT_MANIFEST.json'
    $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.files | Add-Member -NotePropertyName 'ghost.ts' -NotePropertyValue ((Get-FileHash -Algorithm SHA256 -LiteralPath $ghost).Hash.ToLowerInvariant())
    [IO.File]::WriteAllText($manifestFile, ($manifest | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    Invoke-Checked 'check manifest naming a file the kit does not ship' $node @($vendorScript, '--check', '--dest', $tsDest) -Expected 1 -Expect 'ghost.ts: in the manifest, not shipped by the kit' | Out-Null
    $jsDest = Join-Path $temporary 'vendored-js'
    Invoke-Checked 'vendor ts with .js imports' $node @($vendorScript, '--lang', 'ts', '--dest', $jsDest, '--import-ext', 'js') | Out-Null
    if ((Get-Content -LiteralPath (Join-Path $jsDest 'approval-capsule.ts') -Raw -Encoding UTF8) -notmatch 'from "\./canonical-json\.js"') {
        throw 'vendor --import-ext js did not rewrite relative imports.'
    }

    # 3. Demo-harness validator passes the valid fixture and reports each defect in the invalid one.
    $validator = Join-Path $pluginRoot 'scripts\validate-demo-harness.mjs'
    Invoke-Checked 'valid harness' $node @($validator, (Join-Path $PSScriptRoot 'fixtures\demo-harness-app')) -Expect 'PASS' | Out-Null
    $invalid = Invoke-Checked 'invalid harness' $node @($validator, (Join-Path $PSScriptRoot 'fixtures\demo-harness-invalid')) -Expected 1
    foreach ($expected in @('looks like a secret', 'versionEndpoints is empty', 'truth table', 'no product source renders', 'not a package.json script')) {
        if ($invalid -notmatch [regex]::Escape($expected)) { throw "invalid harness output lacks '$expected'.`n$invalid" }
    }

    # 4. Hidden runner: up (supervised, windowless), status, down, nothing left listening.
    $env:AGENTHUB_DEMO_STACK_ROOT = Join-Path $temporary 'demo-stack'
    $stack = Join-Path $pluginRoot 'scripts\demo-stack.mjs'
    # Run a copy on a port the OS hands out now: Windows reserves shifting port
    # ranges (WinNAT/Hyper-V), so any fixed fixture port eventually fails with EACCES.
    $fixture = Join-Path $temporary 'demo-harness-app'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\demo-harness-app') -Destination $fixture -Recurse
    $port = [int](& $node -e "const s=require('net').createServer();s.listen(0,'127.0.0.1',()=>{console.log(s.address().port);s.close()})")
    $harnessFile = Join-Path $fixture 'demo\harness.json'
    $harnessText = (Get-Content -LiteralPath $harnessFile -Raw -Encoding UTF8) -replace '47613', [string]$port
    [IO.File]::WriteAllText($harnessFile, $harnessText, (New-Object System.Text.UTF8Encoding($false)))
    # -WindowStyle exists only on Windows; elsewhere there is no console window to hide.
    $hidden = if ($env:OS -eq 'Windows_NT') { @{ WindowStyle = 'Hidden' } } else { @{} }
    $up = Start-Process -FilePath $node -ArgumentList @("`"$stack`"", 'up', '--repo', "`"$fixture`"") -PassThru @hidden `
        -RedirectStandardOutput (Join-Path $temporary 'up.out') -RedirectStandardError (Join-Path $temporary 'up.err')
    $deadline = (Get-Date).AddSeconds(30)
    $isUp = $false
    while ((Get-Date) -lt $deadline -and -not $isUp) {
        Start-Sleep -Milliseconds 500
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $node $stack status --repo $fixture *> $null
        $isUp = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $previous
    }
    if (-not $isUp) { throw "demo-stack up did not become ready.`n$(Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $temporary 'up.err') -ErrorAction SilentlyContinue)" }
    Invoke-Checked 'demo-stack down' $node @($stack, 'down', '--repo', $fixture) -Expect 'Stopped' | Out-Null
    Start-Sleep -Milliseconds 800
    Invoke-Checked 'demo-stack status after down' $node @($stack, 'status', '--repo', $fixture) -Expected 1 | Out-Null
    if (-not $up.HasExited) { Start-Sleep -Seconds 1 }
    if (-not $up.HasExited) { throw 'demo-stack supervisor survived down.' }

    'PASS: execution-controls and demo-harness kits.'
}
finally {
    Remove-Item Env:\AGENTHUB_DEMO_STACK_ROOT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
