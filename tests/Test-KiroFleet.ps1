#Requires -Version 5.1
<# Kiro fleet artifacts: profile installer (temp profile only), profile JSON shape,
   steering limits, workflow recipe rules and a public-safety scan. Never touches a real profile. #>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$kiro = Join-Path $repoRoot 'packages\coding-agent-dispatch\kiro'
$installer = Join-Path $kiro 'Install-KiroProfiles.ps1'
$failed = 0; $passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { $script:passed++; Write-Host "PASS: $Name" } else { $script:failed++; Write-Host "FAIL: $Name -- $Detail" }
}
function Sha([string]$Path) {
    $s = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($Path))) -replace '-', '').ToLowerInvariant() } finally { $s.Dispose() }
}
function RunInstaller([string[]]$ArgList) {
    $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $out = & $pwsh -NoProfile -File $installer @ArgList 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('kiro-fleet-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    $ownerAgents = Join-Path $temp '.kiro\agents'
    New-Item -ItemType Directory -Path $ownerAgents -Force | Out-Null
    $ownerFile = Join-Path $ownerAgents 'owner-custom.json'
    '{"name":"owner-custom","tools":["read"]}' | Set-Content -Path $ownerFile -Encoding ascii
    $ownerHash = Sha $ownerFile
    $mcpDir = Join-Path $temp '.kiro\settings'
    New-Item -ItemType Directory -Path $mcpDir -Force | Out-Null
    $mcp = Join-Path $mcpDir 'mcp.json'
    '{"mcpServers":{}}' | Set-Content -Path $mcp -Encoding ascii
    $mcpHash = Sha $mcp

    $r = RunInstaller @('-UserProfile', $temp)
    Check 'audit is default and exits 0' ($r.Exit -eq 0) $r.Text
    Check 'audit reports missing' ($r.Text -match 'missing\s+agents/ah-readonly.json')
    Check 'audit reports owner-authored' ($r.Text -match 'owner-authored\s+agents/owner-custom.json')
    $afterAudit = @(Get-ChildItem (Join-Path $temp '.kiro') -Recurse -File | ForEach-Object FullName)
    Check 'audit writes nothing' ($afterAudit.Count -eq 2 -and -not (Test-Path (Join-Path $temp '.kiro\steering'))) ($afterAudit -join ', ')

    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'apply exits 0' ($r.Exit -eq 0) $r.Text
    $managedAgents = Get-ChildItem (Join-Path $kiro 'agents') -Filter *.json
    $allInstalled = $true
    foreach ($f in $managedAgents) {
        $dst = Join-Path $ownerAgents $f.Name
        if (-not (Test-Path $dst) -or (Sha $dst) -ne (Sha $f.FullName)) { $allInstalled = $false }
    }
    Check 'apply installs every managed agent' $allInstalled
    Check 'apply installs steering' (Test-Path (Join-Path $temp '.kiro\steering\ah-invariants.md'))
    Check 'apply leaves owner-authored file untouched' ((Test-Path $ownerFile) -and (Sha $ownerFile) -eq $ownerHash)
    Check 'apply leaves MCP file untouched' ((Sha $mcp) -eq $mcpHash)
    $stray = @(Get-ChildItem (Join-Path $temp '.kiro') -Recurse -File | Where-Object { $_.Extension -in '.bak', '.orig', '.old' })
    Check 'apply writes no backup copies' ($stray.Count -eq 0)

    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'second apply changes nothing' ($r.Text -match 'applied: 0 file\(s\) changed' -and $r.Text -notmatch 'changed agents/')

    $drifted = Join-Path $ownerAgents 'ah-tester.json'
    $before = Sha $drifted
    Add-Content -Path $drifted -Value ' ' -Encoding ascii
    $drifthash = Sha $drifted
    $r = RunInstaller @('-UserProfile', $temp)
    Check 'audit reports drift' ($r.Text -match 'drift\s+agents/ah-tester.json')
    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'apply replaces drifted file' ((Sha $drifted) -eq $before)
    Check 'apply prints both hashes' ($r.Text -match "before=$drifthash after=$before")

    # An owner-authored steering file is left alone.
    $ownerSteer = Join-Path $temp '.kiro\steering\owner-notes.md'
    "---`ninclusion: manual`n---`nowner" | Set-Content -Path $ownerSteer -Encoding ascii
    $ownerSteerHash = Sha $ownerSteer
    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'apply leaves owner-authored steering untouched' ((Sha $ownerSteer) -eq $ownerSteerHash -and $r.Text -match 'owner-authored\s+steering/owner-notes.md')

    # A directory at a managed name is refused, not written into.
    $asDir = Join-Path $ownerAgents 'ah-architect.json'
    Remove-Item -LiteralPath $asDir -Force
    New-Item -ItemType Directory -Path $asDir | Out-Null
    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'apply refuses a directory at a managed name' ($r.Text -match 'refused-dir\s+agents/ah-architect.json' -and @(Get-ChildItem $asDir -Force).Count -eq 0) $r.Text
    Remove-Item -LiteralPath $asDir -Recurse -Force

    # A file link at a managed name is refused, so a file outside the profile is never overwritten.
    $outside = Join-Path $temp 'outside.json'
    'outside' | Set-Content -Path $outside -Encoding ascii
    $outsideHash = Sha $outside
    $linkPath = Join-Path $ownerAgents 'ah-architect.json'
    $linked = $false
    try { New-Item -ItemType SymbolicLink -Path $linkPath -Target $outside -ErrorAction Stop | Out-Null; $linked = $true } catch { }
    if ($linked) {
        $r = RunInstaller @('-Apply', '-UserProfile', $temp)
        Check 'apply refuses a link at a managed name' ($r.Text -match 'refused-link\s+agents/ah-architect.json' -and (Sha $outside) -eq $outsideHash) $r.Text
    } else {
        Write-Host 'SKIP: symbolic links cannot be created here (no Developer Mode or privilege)'
    }
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

# Profile JSON shape
foreach ($f in Get-ChildItem (Join-Path $kiro 'agents') -Filter *.json) {
    $j = $null
    try { $j = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json } catch { }
    Check "profile parses with tools list: $($f.Name)" ($j -and $j.tools -and @($j.tools).Count -gt 0)
}
$ro = Get-Content (Join-Path $kiro 'agents\ah-readonly.json') -Raw -Encoding utf8 | ConvertFrom-Json
$bad = @($ro.tools | Where-Object { $_ -notin @('read', 'glob', 'grep', 'thinking', 'todo') })
Check 'ah-readonly has only read-type tools' ($bad.Count -eq 0) ($bad -join ',')

# Steering
$always = Join-Path $kiro 'steering\ah-invariants.md'
$lines = @(Get-Content $always -Encoding utf8)
Check 'always-on steering is under 60 lines' ($lines.Count -lt 60) "$($lines.Count) lines"
Check 'always-on steering has inclusion: always' ($lines[1] -eq 'inclusion: always')
Check 'always-on steering has the pull-request rule' ((($lines -join "`n") -match 'gh pr ready') -and (($lines -join "`n") -match 'draft'))
foreach ($s in Get-ChildItem (Join-Path $kiro 'steering') -Filter *.md) {
    $first = (Get-Content $s.FullName -TotalCount 1 -Encoding utf8)
    Check "steering has front matter: $($s.Name)" ($first -eq '---')
}

# Workflow recipes
$recipes = @(Get-ChildItem (Join-Path $kiro 'workflows') -Filter *.workflow.json)
Check 'five workflow recipes exist' ($recipes.Count -eq 5) "$($recipes.Count)"
foreach ($w in $recipes) {
    $j = $null
    try { $j = Get-Content $w.FullName -Raw -Encoding utf8 | ConvertFrom-Json } catch { }
    $text = Get-Content $w.FullName -Raw -Encoding utf8
    Check "recipe parses with steps: $($w.Name)" ($j -and $j.name -and @($j.steps).Count -gt 0)
    Check "recipe states three-iteration limit: $($w.Name)" ($text -match 'at most three remediation iterations')
    Check "recipe states no merge: $($w.Name)" ($text -match 'Never merge')
    # A step that must run a command cannot go to an agent without a shell tool.
    foreach ($s in @($j.steps)) {
        $needsShell = $s.prompt -match '(?i)\b(using gh|run (the|a)\b|gh pr|repowise (status|health|update)|Invoke-\w+\.ps1)'
        $profilePath = Join-Path $kiro "agents\$($s.agent).json"
        if ($needsShell -and (Test-Path $profilePath)) {
            $tools = @((Get-Content $profilePath -Raw -Encoding utf8 | ConvertFrom-Json).tools)
            Check "step $($w.BaseName)/$($s.id) has a shell agent" ($tools -contains 'shell') "$($s.agent)"
        }
    }
}
$knownBuiltIns = @('wf-planner', 'wf-coder', 'semantic_reviewer')
$unknown = @(foreach ($w in $recipes) { foreach ($s in @((Get-Content $w.FullName -Raw -Encoding utf8 | ConvertFrom-Json).steps)) {
    if (-not (Test-Path (Join-Path $kiro "agents\$($s.agent).json")) -and $s.agent -notin $knownBuiltIns) { "$($w.Name):$($s.agent)" } } })
Check 'every recipe agent is a managed profile or a listed workflow built-in' ($unknown.Count -eq 0) ($unknown -join ', ')

# Public safety
$secret = '(?i)(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY|(api[_-]?key|secret|token|password)\s*[:=]\s*["''][^"'']{12,})'
$userPath = '(?i)(C:\\Users\\[^\\\s%$<]+|/Users/[a-z]|/home/[a-z])'
# The test file holds the patterns themselves, so it is not scanned.
$files = @(Get-ChildItem $kiro -Recurse -File) + @(Get-Item (Join-Path $repoRoot 'docs\runbooks\kiro-fleet.md'))
$hits = @()
foreach ($f in $files) {
    $t = Get-Content $f.FullName -Raw -Encoding utf8
    if ($t -match $secret) { $hits += "secret-like: $($f.Name)" }
    if ($t -match $userPath) { $hits += "user path: $($f.Name)" }
    if ($t -match [regex]::Escape($env:USERNAME) -and $env:USERNAME.Length -gt 3) { $hits += "user name: $($f.Name)" }
}
Check 'no secret-looking string, user name or user path' ($hits.Count -eq 0) ($hits -join '; ')

Write-Host "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
