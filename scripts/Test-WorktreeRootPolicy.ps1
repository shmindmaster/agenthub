#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$UserProfilePath = $env:USERPROFILE,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
        [string]$Check,
        [string]$Detail
    )
    $results.Add([pscustomobject]@{ status = $Status; check = $Check; detail = $Detail })
}

$registryPath = Join-Path $RegistryRoot 'registry\worktree-roots.json'
$hostsPath = Join-Path $RegistryRoot 'registry\hosts.json'
try {
    $rootPolicy = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $hosts = Get-Content -LiteralPath $hostsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
} catch {
    Add-Result FAIL 'registry:worktree-roots' "missing or invalid registry: $($_.Exception.Message)"
    $rootPolicy = $null
    $hosts = $null
}

if ($rootPolicy) {
    if ($rootPolicy.canonicalRoot -eq 'C:/wt' -and $rootPolicy.pathPattern -eq 'C:/wt/{repository}/{task}') {
        Add-Result PASS 'registry:canonical-root' 'C:\wt\<repository>\<task>'
    } else {
        Add-Result FAIL 'registry:canonical-root' 'expected only C:\wt\<repository>\<task>'
    }

    $wrapperWithKey = @($rootPolicy.hosts | Where-Object hostId -ne 'codex' |
        Where-Object { $_.PSObject.Properties['settingKey'] })
    if ($wrapperWithKey.Count -eq 0) {
        Add-Result PASS 'registry:unsupported-host-keys' 'no fabricated worktree-root keys'
    } else {
        Add-Result FAIL 'registry:unsupported-host-keys' "unexpected keys: $($wrapperWithKey.hostId -join ', ')"
    }

    $environmentContract = $rootPolicy.PSObject.Properties['environmentContract']
    if (-not $environmentContract -or
        [string]$environmentContract.Value.name -ne 'AGENTHUB_WORKTREE_ROOT' -or
        [string]$environmentContract.Value.expectedValue -ne 'C:/wt') {
        Add-Result FAIL 'registry:environment-contract' 'expected optional user-owned AGENTHUB_WORKTREE_ROOT=C:\wt contract'
    } elseif ([string]::IsNullOrWhiteSpace($env:AGENTHUB_WORKTREE_ROOT)) {
        Add-Result PASS 'live:environment-contract' 'unset; helper default is C:\wt'
    } elseif ([System.IO.Path]::GetFullPath([string]$env:AGENTHUB_WORKTREE_ROOT).TrimEnd('\') -eq 'C:\wt') {
        Add-Result PASS 'live:environment-contract' 'user-owned value is C:\wt'
    } else {
        Add-Result FAIL 'live:environment-contract' 'user-owned value is not C:\wt; no write attempted'
    }

    if ($hosts) {
        $missing = @($hosts.hosts.id | Where-Object { $_ -notin @($rootPolicy.hosts.hostId) })
        $unknown = @($rootPolicy.hosts.hostId | Where-Object { $_ -notin @($hosts.hosts.id) })
        if ($missing.Count -eq 0 -and $unknown.Count -eq 0) {
            Add-Result PASS 'registry:host-coverage' "$(@($hosts.hosts).Count) current hosts"
        } else {
            Add-Result FAIL 'registry:host-coverage' "missing=$($missing -join ',') unknown=$($unknown -join ',')"
        }
    }

    $codexConfigPath = Join-Path $UserProfilePath '.codex\config.toml'
    if (Test-Path -LiteralPath $codexConfigPath -PathType Leaf) {
        $codexRaw = Get-Content -LiteralPath $codexConfigPath -Raw -Encoding UTF8
        if ($codexRaw -match "(?m)^git-worktree-root\s*=\s*['""]C:\\wt['""]\s*$") {
            Add-Result PASS 'live:codex-root' 'user-managed setting is C:\wt'
        } else {
            Add-Result WARN 'live:codex-root' 'user-managed setting was not confirmed as C:\wt; no write attempted'
        }
    } else {
        Add-Result WARN 'live:codex-root' 'config.toml not present; no write attempted'
    }

    $claude = @($rootPolicy.hosts | Where-Object hostId -eq 'claude')
    if ($claude.Count -eq 1 -and $claude[0].desktopMutationPolicy -eq 'verify-manually-never-overwrite') {
        Add-Result WARN 'live:claude-desktop-root' 'manual Settings verification required; stale activeWorktreeSession paths are not root settings'
    } else {
        Add-Result FAIL 'registry:claude-desktop-root' 'manual verify-only policy is missing'
    }
}

$summary = [ordered]@{
    pass = @($results | Where-Object status -eq 'PASS').Count
    warn = @($results | Where-Object status -eq 'WARN').Count
    fail = @($results | Where-Object status -eq 'FAIL').Count
}

if ($Json) {
    [ordered]@{ summary = $summary; results = @($results.ToArray()) } | ConvertTo-Json -Depth 5
} else {
    $results | Format-Table status, check, detail -AutoSize
    Write-Output "Summary: pass=$($summary.pass) warn=$($summary.warn) fail=$($summary.fail)"
}

if ($summary.fail -gt 0) { exit 1 }
exit 0
