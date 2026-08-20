#Requires -Version 5.1
<#
.SYNOPSIS
Checks in seconds, on Windows, whether an Expo/React Native app's required
EXPO_PUBLIC_* environment variables will actually be present at build time.

.DESCRIPTION
On 2026-08-17 an ABACare iOS simulator build ran to completion in the macOS
guest, took roughly 40 minutes, installed, launched -- and rendered its own
"BUILD NOT CONFIGURED" error screen. The cause was knowable in under a second
beforehand: Expo inlines `EXPO_PUBLIC_*` environment variables into the
JavaScript bundle at BUILD time, the app's `.env` file is gitignored, and the
repo-to-guest sync excludes gitignored files by default. The build baked in
absent values.

The essential property of that failure is not that the build failed -- it
SUCCEEDED and produced a finished binary that cannot work, and cannot be
repaired afterwards by any amount of configuration, because the values are
already inlined. Forty minutes to learn something a file existence check
would have said instantly.

This script is that check. It discovers which EXPO_PUBLIC_* names the project
actually references (never a hardcoded list -- this is shared fleet
infrastructure and stays product-neutral), determines whether each will
resolve at build time in the order Expo itself resolves them (process
environment, then `.env`), and -- when a required value depends on a `.env`
that git would exclude from a guest sync -- names the exact remedy instead of
letting the next build discover it the expensive way.

It never prints a variable's VALUE, only its presence. `.env` files carry
credentials, and a diagnostic tool that echoes them back is a second leak
waiting to happen.

.PARAMETER ProjectPath
Directory of the Expo/React Native app, i.e. the one containing package.json.

.PARAMETER Require
Extra variable names to treat as required even though the source scan did not
find a `process.env.EXPO_PUBLIC_<NAME>` reference for them (for example, a
name assembled dynamically that static scanning cannot see).

.PARAMETER Json
Emit a machine-readable result object as the final line, for agent use.

.EXAMPLE
.\Test-MobileLabAppConfig.ps1 -ProjectPath C:\Repos\shmindmaster\abacare\apps\mobile

.EXAMPLE
.\Test-MobileLabAppConfig.ps1 -ProjectPath C:\Repos\shmindmaster\abacare\apps\mobile -Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ProjectPath,
    [string[]] $Require = @(),
    [switch] $Json
)

$ErrorActionPreference = 'Stop'

# Directories a project generates or vendors for itself. Never worth scanning:
# node_modules alone can be tens of thousands of files, and none of them are
# this project's own source. `.git` is added defensively -- nothing under it
# is source either, and walking it wastes time on large histories.
$script:ExcludeDirs = @('node_modules', 'ios', 'android', '.expo', 'build', 'dist', '.git')
$script:ScanExtensions = @('ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs')

function Write-VarLine {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Present,
        [string]$SatisfiedBy,
        [string]$DiscoveredIn
    )
    if ($Present) {
        Write-Host ("PASS  {0}" -f $Name) -ForegroundColor Green
        Write-Host ("      satisfied by: {0}" -f $SatisfiedBy) -ForegroundColor DarkGray
    }
    else {
        Write-Host ("FAIL  {0}" -f $Name) -ForegroundColor Red
        Write-Host '      not set in the environment and not present (or empty) in .env' -ForegroundColor Yellow
    }
    if ($DiscoveredIn) {
        Write-Host ("      referenced in: {0}" -f $DiscoveredIn) -ForegroundColor DarkGray
    }
}

# Walks the tree manually, pruning $script:ExcludeDirs BEFORE descending into
# them. Get-ChildItem -Recurse -Include has no way to skip a directory during
# the walk -- it would enumerate all of node_modules and filter afterwards,
# which is the difference between this running in a second and not finishing.
function Get-SourceFiles {
    param([Parameter(Mandatory)][string]$Root)
    $found = [System.Collections.Generic.List[string]]::new()
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $children = $null
        try { $children = Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop }
        catch { continue }
        foreach ($child in $children) {
            if ($child.PSIsContainer) {
                if ($script:ExcludeDirs -notcontains $child.Name) { $stack.Push($child.FullName) }
            }
            else {
                $ext = $child.Extension.TrimStart('.').ToLowerInvariant()
                if ($script:ScanExtensions -contains $ext) { $found.Add($child.FullName) }
            }
        }
    }
    return $found
}

# Relative path for display, without prefix arithmetic.
#
# `$full.Substring($root.Length)` looks obviously correct and is not: it assumes
# the two strings spell the same directory the same way. They do not when 8.3
# short names are involved. Measured 2026-08-18 with a project under
# `C:\Users\SAROSH~1\...`: the root had been expanded to `SaroshHussain` while
# the file paths had not, so the trim removed five characters too many and
# reported `xture/src/config.ts` for `envfixture/src/config.ts`.
#
# That is the bad kind of wrong -- a mangled path still looks like a path, so it
# misdirects instead of announcing itself. Junctions, substituted drives and
# case-differing mounts all produce the same class of error.
function ConvertTo-RelativeDisplayPath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Full)

    $normalizedRoot = ([System.IO.Path]::GetFullPath($Root)).TrimEnd('\', '/')
    $normalizedFull = [System.IO.Path]::GetFullPath($Full)
    $separator = [System.IO.Path]::DirectorySeparatorChar

    if ($normalizedFull.StartsWith($normalizedRoot + $separator, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($normalizedFull.Substring($normalizedRoot.Length + 1) -replace '\\', '/')
    }

    # The prefix does not match, so any subtraction here would be a guess.
    # A full path is longer but true.
    return ($normalizedFull -replace '\\', '/')
}

# Discovers every EXPO_PUBLIC_* name the source actually references, keyed to
# the first file it was seen in. A hardcoded list is exactly the thing this
# script exists to replace -- shared fleet infrastructure that special-cased
# one product's variable names would silently miss every other product's.
function Find-RequiredEnvNames {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string[]]$Files)
    $pattern = [regex]'process\.env\.(EXPO_PUBLIC_[A-Za-z0-9_]+)'
    $discovered = [ordered]@{}
    foreach ($file in $Files) {
        $content = $null
        try { $content = [System.IO.File]::ReadAllText($file) }
        catch { continue }
        foreach ($m in $pattern.Matches($content)) {
            $name = $m.Groups[1].Value
            if (-not $discovered.Contains($name)) {
                $discovered[$name] = ConvertTo-RelativeDisplayPath -Root $Root -Full $file
            }
        }
    }
    return $discovered
}

# KEY=VALUE parsing per the spec: blank lines and `#` comments ignored,
# `export KEY=VALUE` handled, surrounding single/double quotes stripped.
# Returns a name -> value map. Callers must never print a value from it --
# only use it to test presence/emptiness.
function Read-DotEnvFile {
    param([Parameter(Mandatory)][string]$Path)
    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^export\s+(.+)$') { $trimmed = $Matches[1].Trim() }
        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $trimmed.Substring(0, $eq).Trim()
        $value = $trimmed.Substring($eq + 1).Trim()
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if ((($first -eq '"') -and ($last -eq '"')) -or (($first -eq "'") -and ($last -eq "'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        $result[$key] = $value
    }
    return $result
}

# Same EAP hazard Sync-RepoToGuest.ps1 works around in Invoke-SyncGit:
# Windows PowerShell 5.1 promotes an ordinary git stderr line -- "not a git
# repository" from rev-parse, or check-ignore's silent no-match -- into a
# terminating NativeCommandError when ErrorActionPreference is Stop. Contain
# it locally and hand the caller git's real exit code instead.
function Invoke-GitQuiet {
    param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$WorkingDirectory)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $WorkingDirectory @Arguments 2>&1 | Out-String
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output.Trim()
    }
}

function Emit-Json {
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][string]$ProjectPathOut,
        # NOT [Parameter(Mandatory)] on these three: PowerShell treats an empty
        # array bound to a mandatory array parameter as "no value supplied" and
        # throws "Cannot bind argument ... because it is an empty collection."
        # The success path calls this with an empty $Missing every time, so a
        # Mandatory array parameter would fail exactly the runs that matter
        # most -- and, worse, that failure does not touch $LASTEXITCODE, so a
        # caller checking the exit code alone would see a stale 0 from an
        # earlier git call and never notice JSON emission had silently failed.
        [array]$Variables = @(),
        [array]$Missing = @(),
        [array]$Warnings = @(),
        # Untyped, not [string]: a typed string parameter silently coerces a
        # caller's $null into '', which would report "no .env" the same way
        # as "an empty path" in the JSON. $null must survive to ConvertTo-Json
        # as a real null so a consumer can tell the two apart.
        $DotEnvPath,
        [bool]$DotEnvIgnored,
        [string]$Remediation
    )
    $payload = [ordered]@{
        ok            = $Ok
        projectPath   = $ProjectPathOut
        variables     = $Variables
        missing       = $Missing
        warnings      = $Warnings
        dotEnvPath    = $DotEnvPath
        dotEnvIgnored = $DotEnvIgnored
        remediation   = $Remediation
    }
    Write-Output ($payload | ConvertTo-Json -Depth 6 -Compress)
}

Write-Host ''
Write-Host '=== Mobile app build-config check ===' -ForegroundColor White
Write-Host ''

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    Write-Host ("FAIL  project directory does not exist: {0}" -f $ProjectPath) -ForegroundColor Red
    if ($Json) { Emit-Json -Ok $false -ProjectPathOut $ProjectPath -Variables @() -Missing @() -Warnings @('project directory does not exist') -DotEnvIgnored $false }
    exit 1
}
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

$packageJsonPath = Join-Path $ProjectPath 'package.json'
if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
    Write-Host ("FAIL  no package.json in {0} -- this does not look like a JS project" -f $ProjectPath) -ForegroundColor Red
    if ($Json) { Emit-Json -Ok $false -ProjectPathOut $ProjectPath -Variables @() -Missing @() -Warnings @('no package.json found') -DotEnvIgnored $false }
    exit 1
}
Write-Host ("PASS  package.json present" ) -ForegroundColor Green

$pkg = Get-Content -LiteralPath $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

$configCandidates = @('app.config.ts', 'app.config.js', 'app.json')
$foundConfigs = @($configCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectPath $_) -PathType Leaf })
if ($foundConfigs.Count -gt 0) {
    Write-Host ("      app config: {0}" -f ($foundConfigs -join ', ')) -ForegroundColor DarkGray
}
else {
    Write-Host '      app config: none of app.config.ts / app.config.js / app.json found' -ForegroundColor Yellow
}

$expoSpec = $null
if ($pkg.dependencies -and $pkg.dependencies.expo) { $expoSpec = [string]$pkg.dependencies.expo }
elseif ($pkg.devDependencies -and $pkg.devDependencies.expo) { $expoSpec = [string]$pkg.devDependencies.expo }
if ($expoSpec) {
    Write-Host ("      expo SDK: {0}" -f $expoSpec) -ForegroundColor DarkGray
}
else {
    Write-Host '      expo SDK: no "expo" dependency in package.json' -ForegroundColor Yellow
}
Write-Host ''

# --- discover the required EXPO_PUBLIC_* names --------------------------
$sourceFiles = Get-SourceFiles -Root $ProjectPath
$discovered = Find-RequiredEnvNames -Root $ProjectPath -Files $sourceFiles

$allNames = [System.Collections.Generic.List[string]]::new()
foreach ($n in ($discovered.Keys | Sort-Object)) { $allNames.Add($n) }
foreach ($n in $Require) { if (-not $allNames.Contains($n)) { $allNames.Add($n) } }

if ($allNames.Count -eq 0) {
    Write-Host 'No EXPO_PUBLIC_* variables were found referenced in the source, and none were passed via -Require.' -ForegroundColor Yellow
    Write-Host ("Scanned {0} source file(s) under {1}." -f $sourceFiles.Count, $ProjectPath) -ForegroundColor DarkGray
    if ($Json) { Emit-Json -Ok $true -ProjectPathOut $ProjectPath -Variables @() -Missing @() -Warnings @('no EXPO_PUBLIC_* variables discovered or required') -DotEnvIgnored $false }
    exit 0
}

Write-Host ("Discovered {0} EXPO_PUBLIC_* reference(s) across {1} source file(s):" -f $allNames.Count, $sourceFiles.Count) -ForegroundColor White
Write-Host ''

# --- resolve each name the way Expo itself would at build time ----------
# Order matters and mirrors Expo: process environment first, then .env.
$dotEnvPath = Join-Path $ProjectPath '.env'
$dotEnvExists = Test-Path -LiteralPath $dotEnvPath -PathType Leaf
$dotenvValues = if ($dotEnvExists) { Read-DotEnvFile -Path $dotEnvPath } else { [ordered]@{} }

$variables = [System.Collections.Generic.List[object]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
$anyDotEnvOnly = $false

foreach ($name in $allNames) {
    $envValue = [Environment]::GetEnvironmentVariable($name)
    $satisfiedBy = $null
    if (-not [string]::IsNullOrEmpty($envValue)) {
        $satisfiedBy = 'environment'
    }
    elseif ($dotenvValues.Contains($name) -and -not [string]::IsNullOrEmpty($dotenvValues[$name])) {
        $satisfiedBy = 'dotenv'
        $anyDotEnvOnly = $true
    }
    $present = [bool]$satisfiedBy
    $discoveredIn = if ($discovered.Contains($name)) { $discovered[$name] } else { $null }

    Write-VarLine -Name $name -Present $present -SatisfiedBy $satisfiedBy -DiscoveredIn $discoveredIn
    $variables.Add([pscustomobject]@{
            name         = $name
            present      = $present
            satisfiedBy  = $satisfiedBy
            discoveredIn = $discoveredIn
        })
    if (-not $present) { $missing.Add($name) }
}
Write-Host ''

# --- .env.example drift --------------------------------------------------
$warnings = [System.Collections.Generic.List[string]]::new()
$exampleCandidates = @('.env.example', '.env.sample', '.env.template')
$exampleFile = $null
foreach ($candidate in $exampleCandidates) {
    $candidatePath = Join-Path $ProjectPath $candidate
    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { $exampleFile = $candidatePath; break }
}
if ($exampleFile) {
    $exampleKeys = (Read-DotEnvFile -Path $exampleFile).Keys
    $driftKeys = @($exampleKeys | Where-Object { -not $dotenvValues.Contains($_) })
    if ($driftKeys.Count -gt 0) {
        $driftMessage = "$(Split-Path -Leaf $exampleFile) declares key(s) missing from .env: $($driftKeys -join ', ')"
        $warnings.Add($driftMessage)
        Write-Host ("WARN  {0}" -f $driftMessage) -ForegroundColor Yellow
    }
}

# --- guest-transfer warning ------------------------------------------------
# A variable satisfied only by .env is almost certainly about to be dropped by
# the repo-to-guest sync, which excludes gitignored files by default. This is
# the exact mechanism behind the 2026-08-17 ABACare failure this script exists
# to catch before a build, not after one.
$dotEnvIgnored = $false
$remediation = ''
if ($anyDotEnvOnly -and $dotEnvExists) {
    $repoRootCheck = Invoke-GitQuiet -Arguments @('rev-parse', '--show-toplevel') -WorkingDirectory $ProjectPath
    if ($repoRootCheck.ExitCode -eq 0 -and $repoRootCheck.Output) {
        $repoRoot = $repoRootCheck.Output
        $repoRootNormalized = ($repoRoot -replace '\\', '/').TrimEnd('/')
        $dotEnvFullNormalized = ((Resolve-Path -LiteralPath $dotEnvPath).Path -replace '\\', '/')
        $repoRelativeEnvPath = $null
        if ($dotEnvFullNormalized.StartsWith($repoRootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
            $repoRelativeEnvPath = $dotEnvFullNormalized.Substring($repoRootNormalized.Length).TrimStart('/')
        }
        if ($repoRelativeEnvPath) {
            $ignoreCheck = Invoke-GitQuiet -Arguments @('check-ignore', '-q', '--', $repoRelativeEnvPath) -WorkingDirectory $repoRoot
            $dotEnvIgnored = ($ignoreCheck.ExitCode -eq 0)
            if ($dotEnvIgnored) {
                $remediation = ".\Sync-RepoToGuest.ps1 -RepoPath $repoRoot -GuestPath '<guest-path>' -IncludeIgnored '$repoRelativeEnvPath'"
                $warnMessage = "one or more variables are satisfied only by $dotEnvPath, and that file is gitignored ($repoRelativeEnvPath). The default repo-to-guest sync excludes gitignored files, so a build in the guest will bake in absent values and still SUCCEED. Rerun the sync with: $remediation"
                $warnings.Add($warnMessage)
                Write-Host ''
                Write-Host 'WARN  .env is gitignored and will NOT reach the guest by default:' -ForegroundColor Yellow
                Write-Host ("      {0}" -f $remediation) -ForegroundColor Cyan
                Write-Host '      (path passed to -IncludeIgnored is relative to the repo root, not this project directory)' -ForegroundColor DarkGray
            }
        }
        else {
            $warnings.Add("could not compute a repo-relative path for $dotEnvPath under $repoRoot; verify manually whether it is gitignored before a guest build")
        }
    }
    else {
        $warnings.Add("$ProjectPath is not inside a resolvable git repository; could not check whether $dotEnvPath is gitignored")
    }
}

$ok = ($missing.Count -eq 0)
Write-Host ''
if ($ok) {
    Write-Host ("READY: {0}/{0} required EXPO_PUBLIC_* variable(s) satisfied for a build." -f $allNames.Count) -ForegroundColor Green
}
else {
    Write-Host ("NOT READY: {0}/{1} required EXPO_PUBLIC_* variable(s) missing: {2}" -f $missing.Count, $allNames.Count, ($missing -join ', ')) -ForegroundColor Red
}
Write-Host ''

if ($Json) {
    Emit-Json -Ok $ok -ProjectPathOut $ProjectPath -Variables $variables -Missing $missing -Warnings $warnings -DotEnvPath $(if ($dotEnvExists) { $dotEnvPath } else { $null }) -DotEnvIgnored $dotEnvIgnored -Remediation $remediation
}

if ($ok) { exit 0 } else { exit 1 }
