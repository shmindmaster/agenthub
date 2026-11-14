#Requires -Version 5.1
<# OpenCode fleet artifacts: V2 agent profile installer (temp profile only), agent
   frontmatter and permission shape, the enforced read-only reviewer rule the
   dispatcher checks, and a public-safety scan. Never touches a real profile. #>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$openCode = Join-Path $repoRoot 'packages\coding-agent-dispatch\opencode'
$installer = Join-Path $openCode 'Install-OpenCodeProfiles.ps1'
$managedNames = @('peer.md', 'engineer.md', 'reviewer.md', 'tester.md', 'researcher.md', 'readonly.md')
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

$temp = Join-Path ([IO.Path]::GetTempPath()) ('opencode-fleet-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    $configDir = Join-Path $temp '.config\opencode'
    $ownerAgents = Join-Path $configDir 'agents'
    New-Item -ItemType Directory -Path $ownerAgents -Force | Out-Null
    # Owner-authored files that mirror a real profile: a custom agent and the
    # owner's own instruction file. The installer must never touch either.
    $ownerFile = Join-Path $ownerAgents 'product-experience-web.md'
    "---`ndescription: owner`n---`nowner" | Set-Content -Path $ownerFile -Encoding ascii
    $ownerHash = Sha $ownerFile
    $configFile = Join-Path $configDir 'opencode.json'
    '{"model":"owner/kept","provider":{}}' | Set-Content -Path $configFile -Encoding ascii
    $configHash = Sha $configFile

    $r = RunInstaller @('-UserProfile', $temp)
    Check 'audit is default and exits 0' ($r.Exit -eq 0) $r.Text
    Check 'audit reports missing' ($r.Text -match 'missing\s+agents/peer\.md' -and $r.Text -match 'missing\s+agents/reviewer\.md')
    Check 'audit reports owner-authored' ($r.Text -match 'owner-authored\s+agents/product-experience-web\.md')
    Check 'audit writes nothing' (-not (Test-Path (Join-Path $ownerAgents 'peer.md')) -and $r.Text -match 'audit only: nothing written') $r.Text

    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'apply exits 0' ($r.Exit -eq 0) $r.Text
    $allInstalled = $true
    foreach ($name in $managedNames) {
        $src = Join-Path $openCode "agents\$name"
        $dst = Join-Path $ownerAgents $name
        if (-not (Test-Path $dst) -or (Sha $dst) -ne (Sha $src)) { $allInstalled = $false }
    }
    Check 'apply installs every managed agent byte-identical' $allInstalled
    Check 'apply leaves owner-authored agent untouched' ((Test-Path $ownerFile) -and (Sha $ownerFile) -eq $ownerHash)
    Check 'apply never touches opencode.json' ((Sha $configFile) -eq $configHash)
    $stray = @(Get-ChildItem (Join-Path $temp '.config') -Recurse -File | Where-Object { $_.Extension -in '.bak', '.orig', '.old' })
    Check 'apply writes no backup copies' ($stray.Count -eq 0)

    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'second apply changes nothing' ($r.Text -match 'applied: 0 file\(s\) changed' -and $r.Text -notmatch 'changed agents/')

    $drifted = Join-Path $ownerAgents 'tester.md'
    $before = Sha $drifted
    Add-Content -Path $drifted -Value ' ' -Encoding ascii
    $drifthash = Sha $drifted
    $r = RunInstaller @('-UserProfile', $temp)
    Check 'audit reports drift' ($r.Text -match 'drift\s+agents/tester\.md')
    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'apply replaces drifted file' ((Sha $drifted) -eq $before)
    Check 'apply prints both hashes' ($r.Text -match "before=$drifthash after=$before")

    # A directory at a managed name is refused, not written into.
    $asDir = Join-Path $ownerAgents 'researcher.md'
    Remove-Item -LiteralPath $asDir -Force
    New-Item -ItemType Directory -Path $asDir | Out-Null
    $r = RunInstaller @('-Apply', '-UserProfile', $temp)
    Check 'apply refuses a directory at a managed name' ($r.Text -match 'refused-dir\s+agents/researcher\.md' -and @(Get-ChildItem $asDir -Force).Count -eq 0) $r.Text
    Remove-Item -LiteralPath $asDir -Recurse -Force

    # A file link at a managed name is refused, so a file outside the profile is never overwritten.
    $outside = Join-Path $temp 'outside.md'
    'outside' | Set-Content -Path $outside -Encoding ascii
    $outsideHash = Sha $outside
    $linkPath = Join-Path $ownerAgents 'researcher.md'
    $linked = $false
    try { New-Item -ItemType SymbolicLink -Path $linkPath -Target $outside -ErrorAction Stop | Out-Null; $linked = $true } catch { }
    if ($linked) {
        $r = RunInstaller @('-Apply', '-UserProfile', $temp)
        Check 'apply refuses a link at a managed name' ($r.Text -match 'refused-link\s+agents/researcher\.md' -and (Sha $outside) -eq $outsideHash) $r.Text
    } else {
        Write-Host 'SKIP: symbolic links cannot be created here (no Developer Mode or privilege)'
    }
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

# Agent frontmatter and permission shape (V2 ordered list, last match wins).
foreach ($name in $managedNames) {
    $path = Join-Path $openCode "agents\$name"
    $lines = @(Get-Content $path -Encoding utf8)
    $text = $lines -join "`n"
    Check "agent has front matter: $name" ($lines[0] -eq '---' -and @($lines | Where-Object { $_ -eq '---' }).Count -ge 2)
    $close = [Array]::IndexOf($lines, '---', 1)
    $fm = $lines[1..($close - 1)]
    Check "agent records a description: $name" (@($fm | Where-Object { $_ -match '^description: .+' }).Count -eq 1)
    $mode = ($fm | Where-Object { $_ -match '^mode: ' } | Select-Object -First 1)
    $expectedMode = if ($name -eq 'peer.md') { 'mode: primary' } else { 'mode: all' }
    Check "agent mode is $expectedMode : $name" ($mode -eq $expectedMode) $mode
    $rules = @($fm | Where-Object { $_ -match '^\s+- \{ action: ' })
    Check "agent uses flow-permission rules: $name" ($rules.Count -gt 0)
    Check "agent allows broadly first, then denies: $name" ($rules[0] -eq '  - { action: "*", resource: "*", effect: allow }' -and @($rules | Select-Object -Skip 1 | Where-Object { $_ -notmatch 'effect: (allow|deny) \}$' }).Count -eq 0)
    Check "agent denies .env reads: $name" ($text -match '\{ action: read, resource: "\*\.env", effect: deny \}')
    Check "agent denies auth.json reads: $name" ($text -match '\{ action: read, resource: "\*/opencode/auth\.json", effect: deny \}')
    # No deprecated V1 fields.
    Check "agent has no deprecated V1 frontmatter: $name" (@($fm | Where-Object { $_ -match '^(tools|prompt|permission):' }).Count -eq 0)
}
foreach ($name in @('reviewer.md', 'tester.md', 'researcher.md', 'readonly.md')) {
    $text = Get-Content (Join-Path $openCode "agents\$name") -Raw -Encoding utf8
    # The dispatcher's -ReadOnly gate parses the installed readonly profile's
    # ordered frontmatter and requires both of these effective denies.
    Check "$name denies every edit by permission" ($text -match [regex]::Escape('{ action: edit, resource: "*", effect: deny }'))
    Check "$name denies interactive questions" ($text -match [regex]::Escape('{ action: question, resource: "*", effect: deny }'))
}
$readonlyText = Get-Content (Join-Path $openCode 'agents\readonly.md') -Raw -Encoding utf8
Check 'readonly denies every shell command (no write-through-command)' ($readonlyText -match [regex]::Escape('{ action: shell, resource: "*", effect: deny }'))
Check 'readonly denies subagent delegation (no writable child)' ($readonlyText -match [regex]::Escape('{ action: subagent, resource: "*", effect: deny }'))
Check 'readonly denies the browser action' ($readonlyText -match [regex]::Escape('{ action: browser, resource: "*", effect: deny }'))
$reviewerShell = Get-Content (Join-Path $openCode 'agents\reviewer.md') -Raw -Encoding utf8
Check 'reviewer keeps a shell for tests and is not the read-only profile' ($reviewerShell -notmatch [regex]::Escape('{ action: shell, resource: "*", effect: deny }'))
$reviewer = Get-Content (Join-Path $openCode 'agents\reviewer.md') -Raw -Encoding utf8
Check 'reviewer denies git push and commits' ($reviewer -match [regex]::Escape('{ action: shell, resource: "git push*", effect: deny }') -and $reviewer -match [regex]::Escape('{ action: shell, resource: "git commit*", effect: deny }'))
Check 'reviewer denies gh writes' ($reviewer -match [regex]::Escape('{ action: shell, resource: "gh pr *", effect: deny }'))
$engineer = Get-Content (Join-Path $openCode 'agents\engineer.md') -Raw -Encoding utf8
Check 'engineer keeps local edit rights' ($engineer -notmatch [regex]::Escape('{ action: edit, resource: "*", effect: deny }'))
Check 'engineer denies merge, release and publish' ($engineer -match [regex]::Escape('{ action: shell, resource: "gh pr merge*", effect: deny }') -and $engineer -match [regex]::Escape('{ action: shell, resource: "gh release *", effect: deny }') -and $engineer -match [regex]::Escape('{ action: shell, resource: "npm publish*", effect: deny }'))
$peer = Get-Content (Join-Path $openCode 'agents\peer.md') -Raw -Encoding utf8
Check 'peer denies push and outward gh writes' ($peer -match [regex]::Escape('{ action: shell, resource: "git push*", effect: deny }') -and $peer -match [regex]::Escape('{ action: shell, resource: "gh pr *", effect: deny }'))

# Public safety
$secret = '(?i)(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY|(api[_-]?key|secret|token|password)\s*[:=]\s*["''][^"'']{12,})'
$userPath = '(?i)(C:\\Users\\[^\\\s%$<]+|/Users/[a-z]|/home/[a-z])'
# The test file holds the patterns themselves, so it is not scanned.
$files = @(Get-ChildItem $openCode -Recurse -File)
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
