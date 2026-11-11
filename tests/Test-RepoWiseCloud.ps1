#Requires -Version 5.1
<#
Static and unit coverage for the SH-4410 RepoWise cloud recipe under
packages/repowise/cloud/. Nothing here deploys, indexes, opens an SSH
connection, or runs repowise: the bash scripts are syntax-checked (bash -n,
or a text check when bash is absent -- the used path is printed), the
revision-skip decision is unit-tested through bash, and the Windows
connector is checked statically for the no-persistence contract.

Covers:
  1. The three bash scripts parse (bash -n) or pass the structural text check.
  2. mirrors.example.json parses and every repository entry carries owner,
     name, alias, defaultBranch and a placeholder url.
  3. No cloud file contains a credential-shaped string, a non-loopback IPv4
     literal, or a non-placeholder repository URL.
  4. Sync-RepoWiseMirrors.sh: bare-mirror ops only, credential by env NAME,
     no interactive prompt path, failure exits non-zero, no working tree.
  5. Invoke-RepoWiseCloudIndex.sh: hard caps (systemd-run scope MemoryMax +
     timeout), status JSON fields, no scheduler artifacts; should_index is
     unit-tested through bash (skip on unchanged, index on changed/missing/
     previously-failed).
  6. The service unit and serve launcher expose loopback only.
  7. Connect-RepoWiseCloud.ps1 parses, launches ssh windowless, verifies the
     MCP endpoint, does the stale-index check, kills only its own tunnel, and
     registers nothing persistent (no scheduled task, Run key, or service).

Run: pwsh -NoProfile -File tests/Test-RepoWiseCloud.ps1
     powershell.exe -NoProfile -File tests/Test-RepoWiseCloud.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$cloud = Join-Path $repoRoot 'packages\repowise\cloud'

$failures = [Collections.Generic.List[string]]::new()
$script:reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }

$bashFiles = 'Sync-RepoWiseMirrors.sh', 'Invoke-RepoWiseCloudIndex.sh', 'repowise-mcp-serve.sh'
$bash = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

# --- 1. bash scripts parse --------------------------------------------------
foreach ($name in $bashFiles) {
    $path = Join-Path $cloud $name
    $text = Read-Text $path
    if ($bash) {
        $argPath = $path -replace '\\', '/'
        $null = & $bash.Source -n $argPath 2>&1
        Report "$name passes bash -n" ($LASTEXITCODE -eq 0) "bash -n exited $LASTEXITCODE"
    } else {
        # No bash on this machine: a structural check, printed as such.
        $ok = $text.StartsWith('#!/usr/bin/env bash') -and
              $text -match 'set -euo pipefail' -and
              $text -match 'BASH_SOURCE\[0\]' -and
              ([regex]::Matches($text, '\{').Count -eq [regex]::Matches($text, '\}').Count)
        Write-Host 'NOTE: bash unavailable -- structural text check used for .sh parse' -ForegroundColor Yellow
        Report "$name passes the structural text check (bash -n unavailable)" $ok 'missing shebang, pipefail, source guard or unbalanced braces'
    }
}

# --- 2. mirrors example + schema -------------------------------------------
$exampleOk = $false
try {
    $example = Get-Content -LiteralPath (Join-Path $cloud 'mirrors.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $repos = @($example.repositories)
    $exampleOk = $repos.Count -ge 1
    foreach ($r in $repos) {
        foreach ($f in 'owner', 'name', 'alias', 'defaultBranch', 'url') {
            if ([string]::IsNullOrWhiteSpace([string]$r.$f)) { $exampleOk = $false }
        }
        if ($r.alias -notmatch '^[a-z0-9][a-z0-9._-]*$') { $exampleOk = $false }
        if ([string]$r.url -notmatch '<') { $exampleOk = $false }  # placeholder only
    }
    foreach ($env in @($example.defaultCredentialEnv) + @($repos.credentialEnv)) {
        if ($env -and [string]$env -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { $exampleOk = $false }
    }
} catch { $exampleOk = $false }
Report 'mirrors.example.json parses; every entry has owner/name/alias/defaultBranch and a placeholder url' $exampleOk 'see mirrors.schema.json'

$schemaOk = $false
try {
    $schema = Get-Content -LiteralPath (Join-Path $cloud 'mirrors.schema.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $req = @($schema.'$defs'.repository.required)
    $schemaOk = @('owner', 'name', 'alias', 'defaultBranch', 'url' | Where-Object { $req -notcontains $_ }).Count -eq 0
} catch { $schemaOk = $false }
Report 'mirrors.schema.json requires owner/name/alias/defaultBranch/url' $schemaOk 'schema required list incomplete'

# --- 3. no credentials, no non-loopback IPs, no real repository URLs --------
$cloudTexts = Get-ChildItem -LiteralPath $cloud -Recurse -File |
    Where-Object { $_.Extension -in '.sh', '.ps1', '.py', '.json', '.example', '.log' -or $_.Name -eq 'repowise-mcp.service.example' } |
    ForEach-Object { @{ Rel = $_.FullName.Substring($cloud.Length + 1); Text = Read-Text $_.FullName } }
$credPattern = 'sk-[A-Za-z0-9_-]{24,}|ghp_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{24,}|AKIA[0-9A-Z]{16}|xox[bpa]-[0-9A-Za-z-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ssh-(rsa|ed25519) AAAA'
$credHits = @($cloudTexts | Where-Object { $_.Text -match $credPattern } | ForEach-Object { $_.Rel })
Report 'no cloud file contains a credential-shaped string' ($credHits.Count -eq 0) "found in: $($credHits -join ', ')"

$ipHits = [Collections.Generic.List[string]]::new()
foreach ($f in $cloudTexts) {
    foreach ($m in [regex]::Matches($f.Text, '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')) {
        if ($m.Value -ne '127.0.0.1') { $ipHits.Add("$($f.Rel): $($m.Value)") }
    }
}
Report 'no cloud file contains a non-loopback IPv4 literal' ($ipHits.Count -eq 0) "found: $($ipHits -join ', ')"

$urlHits = [Collections.Generic.List[string]]::new()
foreach ($f in $cloudTexts) {
    foreach ($m in [regex]::Matches($f.Text, '(?i)(?:git@|https?://)([A-Za-z0-9._-]+)')) {
        $host_ = $m.Groups[1].Value
        $allowed = $host_ -match '^(127\.0\.0\.1|localhost)$' -or $host_ -match 'example' -or
            $host_ -match 'openai\.azure\.com$' -or $host_ -match 'agent-plugins\.org$' -or $host_ -match 'json-schema\.org$'
        if (-not $allowed) { $urlHits.Add("$($f.Rel): $host_") }
    }
}
Report 'no cloud file names a real git/http host (placeholders only)' ($urlHits.Count -eq 0) "found: $($urlHits -join ', ')"

# --- 4. sync script contract -------------------------------------------------
$sync = Read-Text (Join-Path $cloud 'Sync-RepoWiseMirrors.sh')
Report 'sync script mirrors bare only (clone --mirror / remote update --prune)' `
    ($sync -match 'git clone --mirror' -and $sync -match 'remote update --prune') 'bare-mirror operations missing'
Report 'sync script never fetches into a working tree' `
    ($sync -notmatch 'git\s+(-C\s+\S+\s+)?(checkout|worktree|pull|reset --hard|stash)') 'working-tree git op found'
Report 'sync script references the deploy credential by env NAME only' `
    ($sync -match '\$\{!cred_env' -and $sync -match 'GIT_SSH_COMMAND' -and $sync -notmatch 'PRIVATE KEY-----') 'credential indirection missing'
Report 'sync script cannot prompt (GIT_TERMINAL_PROMPT=0, BatchMode)' `
    ($sync -match 'GIT_TERMINAL_PROMPT=0' -and $sync -match 'BatchMode=yes') 'non-interactive guards missing'
Report 'sync script records the fetched revision per repository' `
    ($sync -match '\$STATE_DIR/\$alias\.rev' -or $sync -match 'STATE_DIR.*\.rev') 'per-repo .rev record missing'
Report 'sync script exits non-zero on any repository failure' `
    ($sync -match 'failed \+ 1' -and $sync -match "exit 1") 'failure does not reach the exit code'
Report 'sync script serializes runs (flock) and stays idempotent' `
    ($sync -match 'flock -n' -and $sync -match 'clone --mirror') 'lock or idempotent clone/update split missing'

# --- 5. index script contract + should_index unit test -----------------------
$index = Read-Text (Join-Path $cloud 'Invoke-RepoWiseCloudIndex.sh')
Report 'index script enforces a hard memory cap (systemd-run scope MemoryMax)' `
    ($index -match 'systemd-run --user --scope' -and $index -match 'MemoryMax') 'systemd-run MemoryMax cap missing'
Report 'index script enforces a hard time cap (timeout -k)' `
    ($index -match 'timeout -k 30 "\$\{TIMEOUT_S\}s"') 'timeout wrapper missing'
Report 'index script refuses to index with no cap mechanism' `
    ($index -match 'refusing to index uncapped') 'uncapped path found'
Report 'index script skips unchanged revisions (should_index)' `
    ($index -match 'should_index\(\)' -and $index -match 'indexed_revision\(\)') 'decision function missing'
Report 'index script writes the status JSON contract fields' `
    ($index -match 'repository:\$repository' -and $index -match 'revision:\$revision' -and
     $index -match 'startedUtc' -and $index -match 'finishedUtc' -and $index -match 'result:\$result') 'status fields missing'
Report 'index script installs no schedule' `
    ($index -notmatch 'crontab' -and $index -notmatch '\.timer' -and $index -notmatch 'systemctl\s+(--user\s+)?(enable|start)') 'scheduling artifact found'
Report 'index script refreshes facts only through repowise update --index-only (or workspace add --no-docs)' `
    ($index -match 'repowise update --no-workspace --index-only' -and $index -match 'workspace add.*--no-docs' -and
     $index -notmatch 'repowise (init|agents|update --full)') 'unexpected repowise invocation'

if ($bash) {
    $jqProbe = & $bash.Source -c 'command -v jq' 2>$null
    if ($LASTEXITCODE -eq 0 -and $jqProbe) {
        $scratch = Join-Path ([IO.Path]::GetTempPath()) ('rwcloud-should-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $scratch | Out-Null
        try {
            $statusFile = ($scratch -replace '\\', '/') + '/demo.json'
            $scriptPath = (Join-Path $cloud 'Invoke-RepoWiseCloudIndex.sh') -replace '\\', '/'
            $unit = @'
source "$1"
sf="$2"
ra="aaaa1111"; rb="bbbb2222"
out=""
should_index demo "$ra" "$sf" && out="$out missing->index;" || out="$out missing->skip;"
jq -n --arg r "$ra" '{repository:"demo",revision:$r,startedUtc:"t",finishedUtc:"t",result:"indexed",detail:""}' > "$sf"
should_index demo "$ra" "$sf" && out="$out same->index;" || out="$out same->skip;"
should_index demo "$rb" "$sf" && out="$out diff->index;" || out="$out diff->skip;"
jq -n '{repository:"demo",revision:"zzz",startedUtc:"t",finishedUtc:"t",result:"failed",detail:""}' > "$sf"
should_index demo "$rb" "$sf" && out="$out failed->index;" || out="$out failed->skip;"
echo "$out"
'@
            $out = & $bash.Source -c $unit 'unit' $scriptPath $statusFile 2>&1 | Out-String
            Report 'should_index skips unchanged, indexes changed/missing, retries a failed run' `
                ($out -match 'missing->index' -and $out -match 'same->skip' -and $out -match 'diff->index' -and $out -match 'failed->index') $out
        } finally {
            Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host 'NOTE: jq unavailable inside bash -- should_index unit skipped' -ForegroundColor Yellow
        Report 'should_index unit test (skipped: no jq for bash)' $true 'skipped, not run'
    }
}

# --- 6. service unit + serve launcher: loopback only --------------------------
$service = Read-Text (Join-Path $cloud 'repowise-mcp.service.example')
$serve = Read-Text (Join-Path $cloud 'repowise-mcp-serve.sh')
Report 'service unit binds no public listener' `
    ($service -notmatch '0\.0\.0\.0' -and $service -notmatch '(?im)^\s*ListenStream' -and
     $service -notmatch 'REPOWISE_HOST\s*=' -and $service -notmatch '(?im)^\s*Sockets?=') 'public surface found in unit'
Report 'service unit hardens the process (NoNewPrivileges, ProtectSystem)' `
    ($service -match 'NoNewPrivileges=true' -and $service -match 'ProtectSystem=') 'hardening directives missing'
Report 'service unit carries only environment NAMES, never values' `
    ($service -match 'EnvironmentFile' -and $service -notmatch '(?i)(api[_-]?key|secret|token)\s*=\s*[^<\s#]') 'key material pattern in unit'
Report 'serve launcher execs shared_server.py (loopback-bound inside)' `
    ($serve -match 'exec "\$PYTHON" "\$SHARED_SERVER"' -and $serve -match 'shared_server\.py') 'launcher does not exec the shared server'
Report 'serve launcher never re-binds a public interface' `
    ($serve -notmatch '0\.0\.0\.0|REPOWISE_HOST|--host\s+(?!127)') 'public bind found in launcher'
Report 'serve launcher keeps the server resident under the unit (--idle-minutes 0)' `
    ($serve -match '--idle-minutes 0') 'idle exit would fight Restart=on-failure'

# --- 7. connector: windowless, verifies, stale-check, clean close, no hooks ---
$connectorPath = Join-Path $cloud 'Connect-RepoWiseCloud.ps1'
$tokens = $null; $parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($connectorPath, [ref]$tokens, [ref]$parseErrors)
Report 'Connect-RepoWiseCloud.ps1 parses as PowerShell' ($parseErrors.Count -eq 0) ($parseErrors | Out-String)
$connector = Read-Text $connectorPath
Report 'connector launches ssh windowless via ProcessStartInfo' `
    ($connector -match 'UseShellExecute\s*=\s*\$false' -and $connector -match 'CreateNoWindow\s*=\s*\$true') 'windowless launch flags missing'
Report 'connector forwards loopback-to-loopback only' `
    ($connector -match '127\.0\.0\.1:\$LocalPort`:127\.0\.0\.1:\$RemotePort' -and $connector -notmatch '0\.0\.0\.0') 'non-loopback forward found'
Report 'connector verifies the server answers (initialize + tools/call)' `
    ($connector -match '"method":"initialize"' -and $connector -match 'tools/call' -and $connector -match 'list_repos') 'MCP verification missing'
Report 'connector does the stale-index check (remote status vs local HEAD)' `
    ($connector -match 'rev-parse.*HEAD' -and $connector -match "\.json" -and $connector -match 'indexStatus') 'stale check missing'
Report 'connector closes only the tunnel it started' `
    ($connector -match '\$tunnel\.Kill\(\)' -and $connector -notmatch 'taskkill|Stop-Process\s+-Name|Get-NetTCPConnection.*Remove') 'over-broad process kill found'
Report 'connector registers nothing persistent (no scheduled task, Run key, service)' `
    ($connector -notmatch 'Register-ScheduledTask|schtasks|CurrentVersion\\Run|New-Service|Set-Service|reg\.exe.*add') 'persistence mechanism found'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($script:reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $script:reported passed, 0 failed" -ForegroundColor Green
exit 0
