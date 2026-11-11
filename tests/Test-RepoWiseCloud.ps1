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
     no interactive prompt path, failure exits non-zero, no working tree,
     `--` before the URL, a DISABLED push URL, private umask, and a
     group/world-readable credential refusal. When bash is on PATH the
     decision functions are executed: valid_repo_url accept/reject,
     key_mode_private, assert_key_private on a real file, and sync_one
     refusing an option-shaped URL.
  5. Invoke-RepoWiseCloudIndex.sh: hard caps (systemd-run scope MemoryMax +
     timeout), status JSON fields, no scheduler artifacts, alias regex before
     any repo path is built (index_one and --only), path_under containment,
     RepoWise state preserved across the checkout clean, exit 137 reported as
     a memory kill, private umask. Executed through bash when present:
     should_index, valid_alias/path_under/index_one on hostile input,
     classify_exit, and the real `--only ../x` argument gate.
  6. The service unit and serve launcher expose loopback only.
  7. Connect-RepoWiseCloud.ps1 parses, launches ssh windowless, verifies the
     MCP endpoint, does the stale-index check, kills only its own tunnel, and
     registers nothing persistent (no scheduled task, Run key, or service).
     Its real validation and argument-building functions are extracted from
     the file's own AST and executed with hostile inputs, and the script
     itself is invoked once with an injection-shaped alias and an
     option-shaped target to prove both throw before ssh can start.

Run: pwsh -NoProfile -File tests/Test-RepoWiseCloud.ps1
     powershell.exe -NoProfile -File tests/Test-RepoWiseCloud.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$cloud = (Join-Path (Join-Path (Join-Path $repoRoot 'packages') 'repowise') 'cloud')

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
$hostExe = (Get-Process -Id $PID).Path

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
Report 'sync script ends option parsing before the URL (git clone --mirror --)' `
    ($sync -match 'git clone --mirror -- ') 'a URL could still be read as a git option'
Report 'sync script pins a DISABLED push URL on every mirror' `
    ($sync -match 'remote set-url --push -- origin DISABLED') 'push still possible with a writable credential'
Report 'sync script validates the repository URL shape before fetching' `
    ($sync -match 'valid_repo_url\(\)' -and $sync -match 'valid_repo_url "\$url"') 'url validation missing'
Report 'sync script refuses a group/world-readable credential file' `
    ($sync -match 'assert_key_private' -and $sync -match 'key_mode_private') 'credential permission check missing'
Report 'sync script runs with a private umask' `
    ($sync -match 'umask 077') 'umask missing'

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
Report 'index script validates aliases before building paths' `
    ($index -match 'valid_alias\(\)' -and $index -match 'valid_alias "\$alias"' -and
     $index -match 'invalid --only alias') 'alias regex missing from index_one/--only'
Report 'index script keeps every repo path inside its root (path_under)' `
    ($index -match 'path_under "\$MIRROR_ROOT"' -and $index -match 'path_under "\$INDEX_ROOT"' -and
     $index -match 'path_under "\$STATUS_DIR"' -and $index -match 'path_under "\$STATE_DIR"') 'uncontained repo path found'
Report 'index script keeps RepoWise state across the checkout clean' `
    ($index -match 'clean -fdq -e \.repowise') 'git clean would delete .repowise every run'
Report 'index script reports exit 137 as a memory kill, not a timeout' `
    ($index -match '137\).*memory kill' -and $index -match '124\).*timeout' -and $index -notmatch '124\|137') '137 is still labelled a timeout'
Report 'index script runs with a private umask' `
    ($index -match 'umask 077') 'umask missing'

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
        # sync_one refuses a hostile URL before it reaches git (jq inside bash).
        $syncPath = (Join-Path $cloud 'Sync-RepoWiseMirrors.sh') -replace '\\', '/'
        $unit2 = @'
source "$1"
repo="$(jq -nc '{alias:"demo",url:"-oProxyCommand=touch /tmp/x",defaultBranch:"main"}')"
if sync_one "$repo" >/dev/null 2>&1; then echo "BAD: hostile url synced"; else echo "refused"; fi
'@
        $out2 = & $bash.Source -c $unit2 'unit' $syncPath 2>&1 | Out-String
        Report 'sync_one refuses an option-shaped URL before running git' `
            ($out2 -match 'refused' -and $out2 -notmatch 'BAD:') $out2
    } else {
        Write-Host 'NOTE: jq unavailable inside bash -- should_index unit skipped' -ForegroundColor Yellow
        Report 'should_index unit test (skipped: no jq for bash)' $true 'skipped, not run'
    }

    # --- executed decision functions: no jq, no network, no ssh --------------
    $indexPath = (Join-Path $cloud 'Invoke-RepoWiseCloudIndex.sh') -replace '\\', '/'
    $unit3 = @'
source "$1"
fails=0
valid_alias "../x"           && { echo "BAD: ../x alias accepted"; fails=1; }
valid_alias "x';touch /tmp/p;'" && { echo "BAD: quote alias accepted"; fails=1; }
valid_alias "agenthub"       || { echo "BAD: agenthub rejected"; fails=1; }
[ "$(path_under /srv/mirrors demo 2>/dev/null)" = "/srv/mirrors/demo" ] || { echo "BAD: demo path"; fails=1; }
path_under /srv/mirrors "../x"    2>/dev/null && { echo "BAD: ../x under root"; fails=1; }
path_under /srv/mirrors "..\\x"   2>/dev/null && { echo "BAD: backslash escape"; fails=1; }
l="$(classify_exit 0 systemd-user)";   case "$l" in indexed*) ;; *) echo "BAD: 0 -> $l"; fails=1 ;; esac
l="$(classify_exit 124 rlimit)";       case "$l" in failed*timeout*) ;; *) echo "BAD: 124 -> $l"; fails=1 ;; esac
l="$(classify_exit 137 systemd-user)"; case "$l" in failed*memory*kill*) ;; *) echo "BAD: 137 -> $l"; fails=1 ;; esac
case "$l" in *timeout*) echo "BAD: 137 labelled timeout"; fails=1 ;; esac
l="$(classify_exit 2 rlimit)";         case "$l" in failed*"exited 2"*) ;; *) echo "BAD: 2 -> $l"; fails=1 ;; esac
MIRROR_ROOT=/srv/m STATUS_DIR=/srv/s INDEX_ROOT=/srv/i STATE_DIR=/srv/st CONFIG=/dev/null index_one "../x" >/dev/null 2>&1 \
    && { echo "BAD: index_one ran for ../x"; fails=1; }
[ -e /srv/m/../x ] && { echo "BAD: escape touched fs"; fails=1; }
[ $fails -eq 0 ] && echo "UNIT3-OK"
'@
    $out3 = & $bash.Source -c $unit3 'unit' $indexPath 2>&1 | Out-String
    Report 'index decision functions refuse ../x and classify exit codes' `
        ($LASTEXITCODE -eq 0 -and $out3 -match 'UNIT3-OK' -and $out3 -notmatch 'BAD:') $out3

    # --only ../x is refused by the real entry point before tools are checked.
    $e2e = & $bash.Source -c '"$1" --only "../x"' 'e2e' $indexPath 2>&1 | Out-String
    Report 'index script refuses --only ../x at the argument gate' `
        ($LASTEXITCODE -ne 0 -and $e2e -match 'invalid --only alias') $e2e

    $syncPath2 = (Join-Path $cloud 'Sync-RepoWiseMirrors.sh') -replace '\\', '/'
    $unit4 = @'
source "$1"
fails=0
gh=github.com
valid_repo_url "git@${gh}:owner/repo.git"     || { echo "BAD: scp url rejected"; fails=1; }
valid_repo_url "git@${gh}:owner/repo"         || { echo "BAD: bare scp url rejected"; fails=1; }
valid_repo_url "https://${gh}/owner/repo"     || { echo "BAD: https url rejected"; fails=1; }
valid_repo_url "ssh://git@${gh}/owner/repo.git" || { echo "BAD: ssh url rejected"; fails=1; }
valid_repo_url "-oProxyCommand=touch /tmp/x"  && { echo "BAD: option url accepted"; fails=1; }
valid_repo_url "https://evil.example.com/o/r" && { echo "BAD: wrong host accepted"; fails=1; }
valid_repo_url "git@${gh}:a/b/c"              && { echo "BAD: 3-segment url accepted"; fails=1; }
valid_repo_url "file:///etc/passwd"           && { echo "BAD: file url accepted"; fails=1; }
key_mode_private 600 || { echo "BAD: 600 refused"; fails=1; }
key_mode_private 400 || { echo "BAD: 400 refused"; fails=1; }
key_mode_private 644 && { echo "BAD: 644 accepted"; fails=1; }
key_mode_private 660 && { echo "BAD: 660 accepted"; fails=1; }
key_mode_private garbage && { echo "BAD: garbage mode"; fails=1; } || [ $? -eq 2 ] || { echo "BAD: garbage rc"; fails=1; }
k="$(mktemp)"; chmod 777 "$k" 2>/dev/null || true
assert_key_private "$k" >/dev/null 2>&1 && { echo "BAD: 777 key accepted"; fails=1; }
assert_key_private "$k.nonexistent" >/dev/null 2>&1 && { echo "BAD: missing key accepted"; fails=1; }
rm -f "$k"
[ $fails -eq 0 ] && echo "UNIT4-OK"
'@
    $out4 = & $bash.Source -c $unit4 'unit' $syncPath2 2>&1 | Out-String
    Report 'sync decision functions validate URL shape and key permissions' `
        ($LASTEXITCODE -eq 0 -and $out4 -match 'UNIT4-OK' -and $out4 -notmatch 'BAD:') $out4
} else {
    Write-Host 'NOTE: bash not on PATH -- .sh decision-function tests skipped (structural text check only)' -ForegroundColor Yellow
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
$connectorAst = [Management.Automation.Language.Parser]::ParseFile($connectorPath, [ref]$tokens, [ref]$parseErrors)
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

# Execute the connector's real validation/argument functions: the file's
# function definitions are extracted from its own AST and dot-sourced here, so
# the checks below run the shipped code, not a copy of it.
$connectorFuncs = ($connectorAst.FindAll(
    { param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) |
    ForEach-Object { $_.Extent.Text }) -join "`n"
. ([ScriptBlock]::Create($connectorFuncs))

Report 'connector alias validator accepts real aliases and refuses injection' `
    ((Test-RepoWiseAlias 'agenthub') -and (Test-RepoWiseAlias 'repo-a.v2_1') -and
     -not (Test-RepoWiseAlias "x';touch /tmp/p;'") -and -not (Test-RepoWiseAlias '../x') -and
     -not (Test-RepoWiseAlias 'UPPER') -and -not (Test-RepoWiseAlias '-flag')) 'validator mismatch'

Report 'connector ssh-target validator refuses an option-shaped target' `
    ((Test-SshTarget 'repowise-mirror') -and (Test-SshTarget 'user@host') -and
     -not (Test-SshTarget '-oProxyCommand=echo x') -and -not (Test-SshTarget '-V') -and
     -not (Test-SshTarget 'host;id')) 'validator mismatch'

$dirOut = ConvertTo-RemoteStatusDir '~/.local/share/repowise-cloud/status'
Report 'connector status dir maps ~ to $HOME (expanded remotely inside double quotes)' `
    ($dirOut -eq '$HOME/.local/share/repowise-cloud/status' -and
     (ConvertTo-RemoteStatusDir '/var/lib/status') -eq '/var/lib/status') $dirOut
$dirThrew = $false
try { ConvertTo-RemoteStatusDir 'relative/../x' | Out-Null } catch { $dirThrew = $true }
$dirThrew2 = $false
try { ConvertTo-RemoteStatusDir '~/a";id;"' | Out-Null } catch { $dirThrew2 = $true }
Report 'connector status dir rejects relative, .. and quote-breaking paths' `
    ($dirThrew -and $dirThrew2) 'unvalidated path accepted'

$probeArgs = New-StatusProbeArguments -SshTarget 'repowise-mirror' -StatusDir '~/.local/share/repowise-cloud/status' -Alias 'agenthub'
$probeCmd = [string]$probeArgs[-1]
Report 'connector status probe uses double-quoted $HOME and never swallows errors' `
    ($probeCmd -match 'if \[ -f "\$HOME/\.local/share/repowise-cloud/status/agenthub\.json" \]' -and
     $probeCmd -match 'exit 3' -and $probeCmd -match 'exit 4' -and
     $probeCmd -notmatch '2>/dev/null' -and $probeCmd -notmatch '\|\| true' -and
     $probeArgs -contains '--' -and $probeArgs[-2] -eq 'repowise-mirror') $probeCmd
$probeThrew = $false
try { New-StatusProbeArguments -SshTarget '-oProxyCommand=x' -StatusDir '/x' -Alias 'agenthub' | Out-Null } catch { $probeThrew = $true }
$probeThrew2 = $false
try { New-StatusProbeArguments -SshTarget 'h' -StatusDir '/x' -Alias "x';id;'" | Out-Null } catch { $probeThrew2 = $true }
Report 'connector status probe builder refuses option-shaped target and injection alias' `
    ($probeThrew -and $probeThrew2) 'hostile input reached the argv builder'

$tunArgs = New-SshTunnelArguments -LocalPort 12345 -RemotePort 7339 -SshTarget 'repowise-mirror'
$dashIdx = [array]::IndexOf([object[]]$tunArgs, '--')
Report 'connector tunnel argv ends options with -- and forwards loopback only' `
    ($dashIdx -eq ($tunArgs.Count - 2) -and $tunArgs[-1] -eq 'repowise-mirror' -and
     ($tunArgs -join ' ') -match '127\.0\.0\.1:12345:127\.0\.0\.1:7339' -and
     $tunArgs -contains '-o' -and $tunArgs -contains 'BatchMode=yes') ($tunArgs -join ' ')
$tunThrew = $false
try { New-SshTunnelArguments -LocalPort 1 -RemotePort 7339 -SshTarget '-oProxyCommand=evil' | Out-Null } catch { $tunThrew = $true }
$tunThrew2 = $false
try { New-SshTunnelArguments -LocalPort 0 -RemotePort 7339 -SshTarget 'repowise-mirror' | Out-Null } catch { $tunThrew2 = $true }
Report 'connector tunnel builder refuses option-shaped target and bad port' `
    ($tunThrew -and $tunThrew2) 'hostile input reached the argv builder'

# End to end through the script itself: hostile values throw before ssh.exe is
# even resolved, so no ssh process can start.
$badAliasOut = & $hostExe -NoProfile -File $connectorPath -Alias "x';touch /tmp/p;'" -SshTarget 'repowise-mirror' 2>&1 | Out-String
Report 'connector refuses a shell-injection alias before any ssh call (e2e)' `
    ($LASTEXITCODE -ne 0 -and $badAliasOut -match 'invalid -Alias') $badAliasOut
$badTargetOut = & $hostExe -NoProfile -File $connectorPath -Alias 'agenthub' -SshTarget '-oProxyCommand=echo x' 2>&1 | Out-String
Report 'connector refuses an option-shaped ssh target before any ssh call (e2e)' `
    ($LASTEXITCODE -ne 0 -and $badTargetOut -match 'invalid -SshTarget') $badTargetOut

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($script:reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $script:reported passed, 0 failed" -ForegroundColor Green
exit 0
