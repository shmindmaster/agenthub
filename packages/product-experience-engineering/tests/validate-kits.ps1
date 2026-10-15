$ErrorActionPreference = 'Stop'

# Behavior tests for kits/execution-controls and kits/demo-harness. Every child
# process runs windowless; the demo-stack check starts and stops a fixture
# service on 127.0.0.1 and leaves nothing running.

$pluginRoot = Split-Path -Parent $PSScriptRoot
$kits = Join-Path $pluginRoot 'kits'
$node = (Get-Command node -ErrorAction Stop).Source
$python = (Get-Command python -ErrorAction Stop).Source
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
    $jsDest = Join-Path $temporary 'vendored-js'
    Invoke-Checked 'vendor ts with .js imports' $node @($vendorScript, '--lang', 'ts', '--dest', $jsDest, '--import-ext', 'js') | Out-Null
    if ((Get-Content -LiteralPath (Join-Path $jsDest 'approval-capsule.ts') -Raw) -notmatch 'from "\./canonical-json\.js"') {
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
    $fixture = Join-Path $PSScriptRoot 'fixtures\demo-harness-app'
    $up = Start-Process -FilePath $node -ArgumentList @("`"$stack`"", 'up', '--repo', "`"$fixture`"") -WindowStyle Hidden -PassThru `
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
    if (-not $isUp) { throw "demo-stack up did not become ready.`n$(Get-Content -Raw (Join-Path $temporary 'up.err') -ErrorAction SilentlyContinue)" }
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
