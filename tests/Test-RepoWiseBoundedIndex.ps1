#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'packages\repowise'
$prior = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = & python.exe -m unittest discover -s "$package\tests" -p 'test_bounded*.py' -v 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = $prior
$output | ForEach-Object { Write-Host ([string]$_) }
$passed = $code -eq 0 -and (($output | Out-String) -match 'Ran [1-9][0-9]* tests')
if (-not $passed) { Write-Host 'RESULT: 1 failed, 0 passed'; exit 1 }
$tokens = $null; $errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile(
    "$package\scripts\Invoke-RepoWiseBoundedIndex.ps1", [ref]$tokens, [ref]$errors)
if ($errors.Count) { $errors | Write-Host; Write-Host 'RESULT: 1 failed, 1 passed'; exit 1 }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('bounded-admission-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
try {
    $lease = Join-Path $scratch 'lease.json'
    # The wrapper refuses the Microsoft Store stub, and an ambient PATH may list
    # it first. Hand it a real interpreter so these cases reach the lease code.
    $realPython = Get-Command python.exe -All -CommandType Application |
        Where-Object { $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1 -ExpandProperty Source
    if (-not $realPython) { throw 'No installed (non-Store) python.exe found for the admission tests.' }
    $params = @{ Python = $realPython
        Workspace = $scratch; RepositoryRoot = $scratch; LeasePath = $lease
        OutputDirectory = (Join-Path $scratch 'output'); MinimumFreeGiB = 0.01 }
    # Run a copy of the wrapper whose only difference is a relaxed RAM floor
    # range, so these cases do not depend on how much RAM is free right now
    # (the shipped 4-64 GiB range is checked to be the sole difference).
    $stubRoot = Join-Path $scratch 'stub'
    $null = New-Item -ItemType Directory -Path $stubRoot
    $shipped = [IO.File]::ReadAllText("$package\scripts\Invoke-RepoWiseBoundedIndex.ps1")
    $relaxed = $shipped.Replace('[ValidateRange(4, 64)][double]$MinimumFreeGiB', '[ValidateRange(0, 64)][double]$MinimumFreeGiB')
    if ($relaxed -eq $shipped) { throw 'Wrapper RAM-floor parameter changed; update this test.' }
    $wrapper = Join-Path $stubRoot 'Invoke-RepoWiseBoundedIndex.ps1'
    [IO.File]::WriteAllText($wrapper, $relaxed)
    [IO.File]::WriteAllText((Join-Path $stubRoot 'bounded_index.py'),
        "import os, sys`nsys.exit(int(os.environ['STUB_EXIT']))`n")
    $refused = $null
    try { & $wrapper @params -Deadline ([DateTimeOffset]::Now.AddSeconds(-1)) }
    catch { $refused = $_.Exception.Message }
    if ($refused -ne 'Admission deadline has passed.' -or (Test-Path -LiteralPath $lease)) { throw 'Expired deadline admitted work.' }
    [IO.File]::WriteAllText($lease, 'synthetic foreign lease')
    # The refusal must come from the exclusive CreateNew, not from another
    # admission gate such as low free RAM; any other reason fails this test.
    $refusal = $null
    try { & $wrapper @params -Deadline ([DateTimeOffset]::Now.AddSeconds(30)) }
    catch { $refusal = $_.Exception }
    if ($null -eq $refusal) { throw 'Foreign lease was admitted.' }
    $chain = @(); for ($e = $refusal; $null -ne $e; $e = $e.InnerException) { $chain += $e }
    if (-not ($chain | Where-Object { $_ -is [IO.IOException] -and $_.Message -match 'already exists' })) {
        throw "Foreign lease was refused for the wrong reason (not the CreateNew collision): $($refusal.Message)"
    }
    if ([IO.File]::ReadAllText($lease) -ne 'synthetic foreign lease' -or
        (Test-Path -LiteralPath $params.OutputDirectory)) { throw 'Foreign lease boundary failed.' }
    [IO.File]::Delete($lease)
    # Lease lifecycle cases below run against a stub bounded_index.py: its exit
    # status stands in for the real run's outcome.
    $deadline = [DateTimeOffset]::Now.AddMinutes(5)
    foreach ($case in @(@{ Exit = '0'; Throws = $false; Keeps = $false }, @{ Exit = '1'; Throws = $true; Keeps = $false },
                        @{ Exit = '3'; Throws = $true; Keeps = $true })) {
        $env:STUB_EXIT = $case.Exit
        $thrown = $null
        try { & $wrapper @params -Deadline $deadline } catch { $thrown = $_.Exception }
        $env:STUB_EXIT = $null
        if ($case.Throws -ne ($null -ne $thrown)) { throw "Stub exit $($case.Exit): wrong throw behaviour." }
        if ($case.Keeps -ne (Test-Path -LiteralPath $lease)) { throw "Stub exit $($case.Exit): wrong lease retention." }
        if ($case.Keeps) {
            $kept = [IO.File]::ReadAllText($lease) | ConvertFrom-Json
            if ($kept.owner -ne 'AgentHub bounded RepoWise index' -or -not $kept.token) { throw 'Retained lease lost its owner record.' }
            if ($thrown.Message -notlike "*$lease*" -or $thrown.Message -notmatch 'operator') {
                throw 'Retention message must name the lease path and the operator check.'
            }
            [IO.File]::Delete($lease)
        }
    }
    $owned = Join-Path $scratch 'owned.json'
    $handle = [IO.FileStream]::new($owned, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::Read, 4096, [IO.FileOptions]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes((@{owner='AgentHub bounded RepoWise index'
            pid=$PID; token='synthetic'} | ConvertTo-Json -Compress))
        $handle.Write($bytes, 0, $bytes.Length); $handle.Flush($true)
        $runtime = (& python.exe -c 'import sys; print(sys.executable)').Trim()
        & $runtime -c "import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from bounded_index import require_lease; require_lease(Path(sys.argv[2]),'synthetic')" "$package\scripts" $owned
        if ($LASTEXITCODE -ne 0) { throw 'Owned live lease (wrapper open mode) is unreadable.' }
    } finally { $handle.Dispose() }
    if (-not (Test-Path -LiteralPath $owned)) { throw 'Lease vanished without an explicit delete.' }
    [IO.File]::Delete($owned)
} finally {
    # This tree contains only the synthetic files created by this test.
    [IO.Directory]::Delete($scratch, $true)
}
Write-Host 'RESULT: 8 passed, 0 failed'
exit 0
