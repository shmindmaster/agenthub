#Requires -Version 5.1
<#
Behavior test: a deployed stdio MCP entry must not boot npm to reach a package
that is already installed globally.

Why: Sync-AgentHub rewrites a bare `npx` command into
`Hide-Stdio.exe node.exe npx-cli.js -y <spec> ...`. That removes the PATH
hazard but keeps npm's own CLI bootstrap on the session-start path. Measured on
2026-08-20 against @playwright/mcp@0.0.79, which IS installed globally, so no
network fetch was involved either way:

    node cli.js --browser chromium        -> 0.48s to MCP initialize
    node npx-cli.js -y <spec> --browser   -> 2.12s to MCP initialize

Identical handshake both ways (protocolVersion 2025-11-25, serverInfo
Playwright 1.63.0-alpha-2026-08-05). The 1.64s difference is pure npm startup,
paid once per host session, and the fleet declares playwright on eight hosts.

Resolve-WindowsHiddenStdioEntry already does this for appium-mcp; the rule
below is what stops the next server from being added without it.

The rule is deliberately conditional: routing through npx is CORRECT when the
package is not installed globally, because then npx is what fetches it. Only a
package with a resolvable global entry point is asserted.

Run: pwsh -NoProfile -File tests/Test-McpLauncherDirectness.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$failures = [Collections.Generic.List[string]]::new()
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

function Read-Json([string]$RelPath) {
    Get-Content -LiteralPath (Join-Path $repoRoot $RelPath) -Raw -Encoding UTF8 | ConvertFrom-Json
}

$formats = Read-Json 'registry\plugin-formats.json'

function Resolve-LivePath([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    # Deliberately NOT `-replace '^~', $env:USERPROFILE`. In -replace the second
    # operand is a replacement STRING, where backslash-digit and $ are special;
    # regex-escaping it (the reflex) is worse, because the escaped form's doubled
    # backslashes survive literally into the result and yield C:\\Users\\... .
    # Win32 tolerates the doubled separators, so the damage shows up in error
    # text rather than as a failure. Substring has none of these hazards.
    $expanded = if ($Raw.StartsWith('~')) { $env:USERPROFILE + $Raw.Substring(1) } else { $Raw }
    $expanded = $expanded -replace '/', '\'
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

# The global npm root. A package resolvable here is one npx would find rather
# than download, which is exactly the case the rule applies to.
$globalRoot = Join-Path $env:APPDATA 'npm\node_modules'

# Does this package spec have a global entry point? Returns the .js path, or
# $null when the package is genuinely not installed (npx is then correct).
function Get-GlobalEntryPoint([string]$Spec) {
    if ([string]::IsNullOrWhiteSpace($Spec)) { return $null }
    # Strip the version suffix without eating the leading @ of a scope.
    $name = if ($Spec.StartsWith('@')) {
        $at = $Spec.IndexOf('@', 1)
        if ($at -ge 0) { $Spec.Substring(0, $at) } else { $Spec }
    } else {
        ($Spec -split '@')[0]
    }
    $pkgDir = Join-Path $globalRoot ($name -replace '/', '\')
    $pkgJson = Join-Path $pkgDir 'package.json'
    if (-not (Test-Path -LiteralPath $pkgJson)) { return $null }
    $manifest = Get-Content -LiteralPath $pkgJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $bin = $manifest.bin
    if (-not $bin) { return $null }
    $rel = if ($bin -is [string]) { $bin } else { @($bin.PSObject.Properties)[0].Value }
    if ([string]::IsNullOrWhiteSpace($rel)) { return $null }
    $entry = Join-Path $pkgDir ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $entry)) { return $null }
    return $entry
}

# Every token a host would hand the OS, command first, for one server entry.
function Get-LaunchTokens($Entry) {
    if ($null -eq $Entry) { return ,@() }
    # opencode stores the whole launch line as a single `command` array.
    if ($Entry.command -is [array]) { return ,@($Entry.command) }
    $tokens = [Collections.Generic.List[string]]::new()
    if ($Entry.command) { $tokens.Add([string]$Entry.command) }
    foreach ($a in @($Entry.args)) { if ($null -ne $a) { $tokens.Add([string]$a) } }
    # `return @()` UNROLLS to $null leaving a function; the comma keeps an empty
    # set an empty set rather than a missing-data signal.
    return ,@($tokens.ToArray())
}

# Given the launch tokens, return the npx package spec, or $null if this entry
# does not route through npx at all.
function Get-NpxSpec([string[]]$Tokens) {
    $npxAt = -1
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        if ($t -match '(^|[\\/])npx(\.cmd|\.ps1)?$' -or $t -match 'npx-cli\.js$') { $npxAt = $i; break }
    }
    if ($npxAt -lt 0) { return $null }
    # After npx come its own flags (-y/--yes/-p/--package); the first bare token
    # is the package spec.
    for ($i = $npxAt + 1; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        if ($t.StartsWith('-')) { continue }
        return $t
    }
    return $null
}

$examined = 0
$viaNpx = 0

foreach ($h in @($formats.hosts)) {
    $hostId = [string]$h.id
    if (-not $h.mcpPath) { continue }
    $path = Resolve-LivePath ([string]$h.mcpPath)
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8

    $entries = @{}
    if ($path -like '*.toml') {
        foreach ($m in [regex]::Matches($text, '(?ms)^\[mcp_servers\.([^\].]+)\]\r?\n(.*?)(?=^\[|\Z)')) {
            $sid = $m.Groups[1].Value
            $body = $m.Groups[2].Value
            $tokens = [Collections.Generic.List[string]]::new()
            $cm = [regex]::Match($body, "(?m)^command\s*=\s*'([^']*)'")
            if ($cm.Success) { $tokens.Add($cm.Groups[1].Value) }
            $am = [regex]::Match($body, "(?m)^args\s*=\s*\[(.*)\]")
            if ($am.Success) {
                foreach ($q in [regex]::Matches($am.Groups[1].Value, "'([^']*)'")) { $tokens.Add($q.Groups[1].Value) }
            }
            # No comma wrapper here. The `,@(...)` idiom exists to survive a
            # function RETURN, which unrolls one level; a hashtable assignment
            # does not unroll, so the wrapper would store an array-in-an-array
            # and every token check below would silently see one opaque element.
            # That is exactly what hid grok from this test's first run.
            $entries[$sid] = @($tokens.ToArray())
        }
    } else {
        $key = [string]$h.mcpKey
        if ([string]::IsNullOrWhiteSpace($key) -or $key.StartsWith('[')) { continue }
        $json = $text | ConvertFrom-Json
        # A dotted mcpKey may be a PATH (mcpServers) or a LITERAL key name
        # (amp stores "amp.mcpServers" as one property). Literal first.
        $node = $json.PSObject.Properties[$key].Value
        if ($null -eq $node) {
            $node = $json
            foreach ($seg in ($key -split '\.')) {
                if ($null -eq $node) { break }
                $node = $node.PSObject.Properties[$seg].Value
            }
        }
        if ($null -eq $node) { continue }
        foreach ($p in $node.PSObject.Properties) { $entries[$p.Name] = Get-LaunchTokens $p.Value }
    }

    foreach ($sid in $entries.Keys) {
        $tokens = @($entries[$sid])
        if ($tokens.Count -eq 0) { continue }
        $examined++
        $spec = Get-NpxSpec $tokens
        if ($spec) { $viaNpx++ }
        # $null when the entry does not use npx at all, or uses it for a package
        # that genuinely is not installed -- which is npx doing its actual job.
        $entryPoint = if ($spec) { Get-GlobalEntryPoint $spec } else { $null }
        # Reported per entry, PASS included, so the suite's own count is evidence
        # of how many launchers were covered. Reporting only failures made a
        # fully-green run indistinguishable from a run whose detection loop had
        # quietly stopped matching anything.
        Report "'$sid' on '$hostId' launches directly, not through npm" (-not $entryPoint) `
            "$spec is installed globally at $entryPoint, so npx only adds npm's bootstrap. Rewrite the launch to run that file with node.exe, as Resolve-WindowsHiddenStdioEntry already does for appium-mcp. Config: $path"
    }
}

# Without this, a change that stops finding configs would leave the file green
# having asserted nothing. ($viaNpx is reported, not asserted: zero is the
# desired end state here, so an assertion on it would have to pass either way.)
Report 'deployed MCP entries were actually examined' ($examined -gt 0) `
    'No host config yielded a single server entry. If mcpPath/mcpKey changed shape, every check above silently vanished.'

Write-Host ''
Write-Host "examined $examined deployed server entries; $viaNpx route through npx"
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
