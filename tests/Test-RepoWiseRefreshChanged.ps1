#Requires -Version 7.0
# Runs the shipped changed-repo refresh over real synthetic Git repositories, with
# the bounded wrapper stubbed: nothing here starts RepoWise.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { Write-Host 'RESULT: 0 passed, 0 failed (Windows Job Objects only)'; exit 0 }
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'packages\repowise\scripts'
$passed = 0
function Assert-That([bool]$Condition, [string]$Name) {
    if (-not $Condition) { Write-Host "FAIL: $Name"; Write-Host "RESULT: 1 failed, $script:passed passed"; exit 1 }
    $script:passed++
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('refresh-changed-' + [Guid]::NewGuid().ToString('N'))
$scripts = Join-Path $scratch 'scripts'
$workspace = Join-Path $scratch 'workspace'
$runtime = Join-Path $scratch 'runtime'
$null = New-Item -ItemType Directory -Path $scripts, $workspace, $runtime
try {
    Copy-Item (Join-Path $package 'Invoke-RepoWiseRefreshChanged.ps1'), (Join-Path $package 'changed_repos.py') $scripts
    $visits = Join-Path $scratch 'visits.log'
    @'
param($Workspace, $RepositoryRoot, $LeasePath, $OutputDirectory, $Deadline, $TimeoutSeconds, $Python, [switch]$RenderDocs)
Add-Content -LiteralPath $env:STUB_VISITS -Value "$(Split-Path -Leaf $RepositoryRoot) docs=$RenderDocs"
if ($RepositoryRoot -like '*bad*' -or $env:STUB_FAIL_ALL) { throw 'Bounded indexing was not accepted.' }
'@ | Set-Content -LiteralPath (Join-Path $scripts 'Invoke-RepoWiseBoundedIndex.ps1') -Encoding UTF8
    $env:STUB_VISITS = $visits

    $yaml = "version: 1`nrepos:`n"
    foreach ($name in 'still', 'bad', 'moved') {
        $repo = Join-Path $workspace $name
        $null = New-Item -ItemType Directory -Path (Join-Path $repo '.repowise')
        git -C $repo init -q
        Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Value '.repowise/'
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'x'
        git -C $repo add .
        git -C $repo -c user.email=t@example.invalid -c user.name=t commit -qm first
        @{ last_sync_commit = (git -C $repo rev-parse HEAD) } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $repo '.repowise\state.json') -Encoding UTF8
        if ($name -ne 'still') {
            Set-Content -LiteralPath (Join-Path $repo 'b.txt') -Value 'y'
            git -C $repo add .
            git -C $repo -c user.email=t@example.invalid -c user.name=t commit -qm second
        }
        $yaml += "- path: $name`n  alias: $name`n"
    }
    [IO.File]::WriteAllText((Join-Path $workspace '.repowise-workspace.yaml'), $yaml)

    $refresh = Join-Path $scripts 'Invoke-RepoWiseRefreshChanged.ps1'
    $common = @{ Workspace = $workspace; RuntimeDir = $runtime }

    $plan = & $refresh @common -DryRun | Out-String | ConvertFrom-Json
    Assert-That ($plan.visit -eq 2 -and $plan.counts.unchanged -eq 1) 'dry run names only moved entries'
    Assert-That (-not (Test-Path -LiteralPath $visits)) 'dry run visits nothing'

    $first = & $refresh @common | Out-String | ConvertFrom-Json
    $seen = @(Get-Content -LiteralPath $visits -Encoding UTF8)
    Assert-That ($seen.Count -eq 2 -and $seen -notcontains 'still docs=False') 'unchanged entry is never started'
    Assert-That ($first.accepted -eq 1 -and @($first.failed).Count -eq 1) 'one failure does not stop the rest'

    $again = & $refresh @common | Out-String | ConvertFrom-Json
    Assert-That ($again.skipped -and @(Get-Content -LiteralPath $visits -Encoding UTF8).Count -eq 2) 'repeat inside the window visits nothing'

    $null = & $refresh @common -Force -RenderDocs
    $seen = @(Get-Content -LiteralPath $visits -Encoding UTF8)
    Assert-That ($seen.Count -eq 4 -and $seen[-1] -like '*docs=True') '-Force overrides the window and -RenderDocs reaches the wrapper'

    Remove-Item -LiteralPath (Join-Path $runtime 'last-run.json')
    $null = & $refresh @common -Only (Join-Path $workspace 'moved')
    Assert-That (@(Get-Content -LiteralPath $visits -Encoding UTF8).Count -eq 5) '-Only limits the visit'
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $runtime 'last-run.json'))) '-Only does not count as the daily run'

    $stamp = Join-Path $runtime 'last-run.json'
    $env:STUB_FAIL_ALL = '1'
    $none = & $refresh @common | Out-String | ConvertFrom-Json
    $env:STUB_FAIL_ALL = $null
    Assert-That ($none.accepted -eq 0 -and -not (Test-Path -LiteralPath $stamp)) 'a run where every visit failed does not use up the day'

    $lease = Join-Path $runtime 'refresh.lease'
    function Set-Lease([hashtable]$Record) { [IO.File]::WriteAllText($lease, ($Record | ConvertTo-Json -Compress)) }
    function Get-VisitCount { @(Get-Content -LiteralPath $visits -Encoding UTF8).Count }

    Set-Lease @{ pid = 999999; token = [Guid]::NewGuid().ToString('N') }
    $before = Get-VisitCount
    $null = & $refresh @common -Force
    Assert-That (-not (Test-Path -LiteralPath $lease) -and (Get-VisitCount) -eq $before + 2) 'a lease from a killed run is cleared'

    foreach ($held in @(@{ pid = $PID; token = 'live' }, @{ pid = 999999; token = 'kept'; retained = $true })) {
        Set-Lease $held
        $before = Get-VisitCount
        Remove-Variable -Name stopped -ErrorAction SilentlyContinue
        $stopped = & $refresh @common -Force | Out-String | ConvertFrom-Json
        Assert-That ($stopped.stopped -and (Get-VisitCount) -eq $before -and (Test-Path -LiteralPath $lease)) "a held lease stops the run ($($held.token))"
    }
    [IO.File]::Delete($lease)

    $kept = Join-Path $scratch 'kept'
    $null = New-Item -ItemType Directory -Path $kept
    Copy-Item (Join-Path $package 'Invoke-RepoWiseBoundedIndex.ps1') $kept
    Set-Content -LiteralPath (Join-Path $kept 'bounded_index.py') -Value 'raise SystemExit(3)'
    # The first python.exe on PATH may be a Store alias or an application's private copy.
    $python = foreach ($candidate in @(Get-Command python.exe, py.exe -All -CommandType Application -ErrorAction SilentlyContinue)) {
        $found = & $candidate.Source -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $found -and $found -notlike '*\WindowsApps\*' -and (Test-Path -LiteralPath $found -PathType Leaf)) { $found; break }
    }
    $message = $null
    try {
        $null = & (Join-Path $kept 'Invoke-RepoWiseBoundedIndex.ps1') -Workspace $workspace -RepositoryRoot (Join-Path $workspace 'moved') `
            -LeasePath $lease -OutputDirectory (Join-Path $scratch 'out') -Deadline ([DateTimeOffset]::Now.AddMinutes(5)) `
            -Python $python -RamFloorWaiverReason 'test'
    } catch { $message = $_.Exception.Message }
    $record = [IO.File]::ReadAllText($lease) | ConvertFrom-Json
    Assert-That ($message -match 'REMAINS' -and $record.retained -and $record.token) 'exit 3 marks the lease as kept'
    [IO.File]::Delete($lease)

    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $package 'Invoke-RepoWiseRefreshChanged.ps1'), [ref]$null, [ref]$null)
    $text = $ast.Extent.Text
    Assert-That ($text -match 'CreateNoWindow\s*=\s*\$true' -and $text -match 'UseShellExecute\s*=\s*\$false') 'Python runs windowless'
    Assert-That ($text -notmatch 'Register-ScheduledTask|schtasks') 'no schedule is registered'
} finally {
    $env:STUB_VISITS = $null
    # Git marks its object files read-only.
    Get-ChildItem -LiteralPath $scratch -Recurse -Force -File | ForEach-Object { $_.Attributes = 'Normal' }
    [IO.Directory]::Delete($scratch, $true)
}
Write-Host "RESULT: $passed passed, 0 failed"
exit 0
