#Requires -Version 5.1
<#
Behavior tests for registry/mobile-scope.json: the mobile eligibility guard.

WHY THIS FILE EXISTS

Mobile identifiers are effectively permanent. An Apple bundle identifier
cannot be changed after the first build reaches App Store Connect, and
Android treats a changed applicationId as a different application. So a
product whose name is known to be temporary must not have ANY long-lived
mobile identity created for it -- and "not yet" is not enforceable by
intention alone, because the cheapest thing an agent can do while scaffolding
is reserve a convenient placeholder identifier.

registry/mobile-scope.json records the decision; global-agent-policy.md
compiles the prohibition into every host's global instruction file. This file
is what keeps the two true, and true TOGETHER: a registry entry nobody's
policy references is decoration, and a policy line whose registry entry has
been softened to non-frozen is worse than no policy at all.

Rexa is the proof this is a real failure mode and not a hypothetical: its EAS
project shipped as @shmindmaster/recallforge, the pre-rename product name,
recoverable only because nothing had been store-submitted yet.

THE ACCOUNTABILITY BEHAVIOR IS THE LOAD-BEARING ONE

Behavior 2 requires every fleet repository to be classified. That inverts the
default: a newly cloned repository is a FAILURE until somebody classifies it,
rather than silently defaulting into eligibility. Same philosophy as
tests/Test-DeclaredPathAccountability.ps1 -- absence must be explained, never
interpreted.

Its filesystem half is machine-local by construction: it enumerates .git
children of repo-standard.json -> fleetRoot, so on a different machine a
different set of repositories is present. That is correct for a personal
fleet registry, not a portability defect, but a reader should not mistake a
pass here for a claim about any other machine. The roster half (every
repo-standard.json roster key is classified) is machine-independent.

Not a Pester suite: this repo carries no Pester dependency. Same
accumulate-and-report idiom as the rest of tests/.

Run: pwsh -NoProfile -File tests/Test-MobileScope.ps1
     powershell.exe -NoProfile -File tests/Test-MobileScope.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

# -Encoding UTF8 is load-bearing under Windows PowerShell 5.1, which otherwise
# decodes a BOM-less UTF-8 file as the ANSI code page.
# tests/Test-FileEncodingDiscipline.ps1 enforces it repo-wide.
$scopePath    = Join-Path $repoRoot 'registry\mobile-scope.json'
$standardPath = Join-Path $repoRoot 'registry\repo-standard.json'
$policyPath   = Join-Path $repoRoot 'global-agent-policy.md'

$scope    = Get-Content -LiteralPath $scopePath    -Raw -Encoding UTF8 | ConvertFrom-Json
$standard = Get-Content -LiteralPath $standardPath -Raw -Encoding UTF8 | ConvertFrom-Json

# This worktree is checked out CRLF (core.autocrlf=true) while the main
# checkout is LF, so every match below runs against a newline-normalized copy.
# A bare (?m)...$ anchor would otherwise pass in one checkout and fail in the
# other -- the defect tests/Test-CrlfAnchors.ps1 exists to close.
$policy = ([IO.File]::ReadAllText($policyPath)).Replace("`r`n", "`n")

$products      = @($scope.products)
$bucketNames   = @($scope.buckets.PSObject.Properties | ForEach-Object { $_.Name })
$frozenBucket  = 'excludedPendingReposition'
$frozen        = @($products | Where-Object { $_.bucket -eq $frozenBucket })

# ---------------------------------------------------------------------------
# Behavior 1: the file is structurally usable as an authority.
# ---------------------------------------------------------------------------
function Test-SchemaIsSound {
    $problems = [Collections.Generic.List[string]]::new()

    if ($products.Count -eq 0) {
        return @{ Passed = $false; Detail = 'mobile-scope.json declares zero products. An authority that classifies nothing authorizes everything by omission.' }
    }
    if ($bucketNames.Count -eq 0) {
        return @{ Passed = $false; Detail = 'mobile-scope.json declares no buckets, so no product classification can be validated.' }
    }
    if ($scope.scopePolicy.unclassifiedIsEligible -ne $false) {
        $problems.Add("scopePolicy.unclassifiedIsEligible must be false; it is '$($scope.scopePolicy.unclassifiedIsEligible)'. Defaulting an unlisted product to eligible defeats the entire guard.")
    }
    if (@($scope.scopePolicy.frozenIdentifierClasses).Count -eq 0) {
        $problems.Add('scopePolicy.frozenIdentifierClasses is empty, so a freeze prohibits nothing concrete.')
    }

    $seen = @{}
    foreach ($product in $products) {
        $id = [string]$product.productId
        if ([string]::IsNullOrWhiteSpace($id)) { $problems.Add('a product entry has no productId'); continue }
        if ($seen.ContainsKey($id)) { $problems.Add("duplicate productId '$id'") }
        $seen[$id] = $true

        if ([string]::IsNullOrWhiteSpace([string]$product.repository)) { $problems.Add("$id has no repository") }
        if ([string]::IsNullOrWhiteSpace([string]$product.bucket))     { $problems.Add("$id has no bucket") }
        elseif ($product.bucket -notin $bucketNames)                   { $problems.Add("$id declares undeclared bucket '$($product.bucket)'") }
    }

    if ($problems.Count -gt 0) {
        return @{ Passed = $false; Detail = ($problems -join '; ') }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 2: every fleet repository is classified. This is the guard that
# stops a new repository from silently defaulting into eligibility.
# ---------------------------------------------------------------------------
function Test-EveryFleetRepoIsClassified {
    $classified = @{}
    foreach ($product in $products) { $classified[[string]$product.productId] = $true }

    $unclassified = [Collections.Generic.List[string]]::new()

    # Half one, machine-independent: the repo-standard.json roster.
    foreach ($entry in $standard.repos.PSObject.Properties) {
        if (-not $classified.ContainsKey($entry.Name)) {
            $unclassified.Add("$($entry.Name) (repo-standard.json roster)")
        }
    }

    # Half two, machine-local: anything cloned to the fleet root. Reuses
    # repo-standard.json -> excluded rather than restating which repositories
    # are deliberately outside the fleet standard, so the two files cannot
    # disagree about it.
    $fleetRoot = [string]$standard.fleetRoot
    $excluded  = @($standard.excluded | ForEach-Object { [string]$_.name })
    if (Test-Path -LiteralPath $fleetRoot) {
        $children = @(Get-ChildItem -LiteralPath $fleetRoot -Directory -Force -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            if ($child.Name -in $excluded) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $child.FullName '.git'))) { continue }
            if (-not $classified.ContainsKey($child.Name)) {
                $unclassified.Add("$($child.Name) (cloned at $fleetRoot)")
            }
        }
    }

    if ($unclassified.Count -gt 0) {
        $rendered = (@($unclassified | Sort-Object -Unique) -join '; ')
        return @{ Passed = $false; Detail = "$($unclassified.Count) fleet repository(ies) carry no mobile-scope classification: $rendered. Classify each one in registry/mobile-scope.json. An unclassified repository is not implicitly ineligible to a hurried agent -- it is simply unmentioned, which is how a placeholder bundle identifier gets created for a product nobody decided to ship." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 3: the products the owner froze are still recorded as frozen, with
# an exit condition that names who can lift the freeze.
# ---------------------------------------------------------------------------
function Test-FrozenProductsStayFrozen {
    $required = @('sabhi', 'empowera', 'documed')
    $problems = [Collections.Generic.List[string]]::new()

    foreach ($id in $required) {
        $product = $products | Where-Object { $_.productId -eq $id } | Select-Object -First 1
        if ($null -eq $product) { $problems.Add("$id is absent from mobile-scope.json entirely"); continue }
        if ($product.bucket -ne $frozenBucket) { $problems.Add("$id is in bucket '$($product.bucket)', not '$frozenBucket'") }
        if ($product.frozen -ne $true)         { $problems.Add("$id is not marked frozen: true") }
        if ([string]::IsNullOrWhiteSpace([string]$product.exitCondition)) { $problems.Add("$id carries no exitCondition, so nothing records what would lift the freeze") }
    }

    if ($problems.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($problems -join '; '). These products are pending refactor, repositioning, and rebranding; their current names must not reach any permanent Apple, Google, Firebase, or EAS identifier. Unfreezing is the owner's call, recorded in the product's exitCondition -- not a side effect of a convenient edit." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 4: the policy that reaches every host still carries the guard.
# A registry entry no compiled policy references is decoration.
# ---------------------------------------------------------------------------
function Test-PolicyStillCarriesTheGuard {
    $problems = [Collections.Generic.List[string]]::new()

    if ($policy -notmatch '(?m)^##\s+Mobile scope\s*$') {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '## Mobile scope' section, so no host's compiled instruction file carries the prohibition and every assertion below would search an empty string." }
    }

    if ($policy -notmatch [regex]::Escape('`registry/mobile-scope.json` is the sole authority')) {
        $problems.Add('the policy no longer names registry/mobile-scope.json as the sole authority')
    }
    if ($policy -notmatch [regex]::Escape('do not create, configure, publish, register, reserve, or modify')) {
        $problems.Add('the verbatim prohibition verbs (create, configure, publish, register, reserve, modify) are gone')
    }
    if ($policy -notmatch [regex]::Escape('A placeholder identifier is a prohibited identifier')) {
        $problems.Add('the placeholder-identifier clause is gone -- reserving a convenient placeholder is the specific harm the freeze prevents')
    }
    if ($policy -notmatch [regex]::Escape('cannot be changed after the first build is uploaded to App Store Connect')) {
        $problems.Add('the Apple permanence rationale is gone, leaving the freeze looking like a scheduling preference')
    }
    if ($policy -notmatch 'mobile-platform-standard') {
        $problems.Add('the policy no longer points at the mobile-platform-standard skill')
    }

    # Every bucket the policy names must exist, or the instruction compiled to
    # 17 hosts refers to a classification the registry cannot resolve.
    foreach ($name in @($frozenBucket)) {
        if ($policy -notmatch [regex]::Escape($name)) { $problems.Add("the policy does not name the '$name' bucket") }
        elseif ($name -notin $bucketNames)            { $problems.Add("the policy names bucket '$name', which mobile-scope.json does not declare") }
    }

    if ($problems.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($problems -join '; '). This section is compiled verbatim into every managed host's global instruction file by scripts/Sync-Instructions.ps1; weakening it silently weakens the guard on all of them at once." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 5: no frozen product has grown a mobile footprint on disk. The
# other behaviors check that the rule is written down; this one checks that
# it held.
# ---------------------------------------------------------------------------
function Test-NoFrozenProductHasMobileArtifacts {
    $fleetRoot = [string]$standard.fleetRoot
    $findings  = [Collections.Generic.List[string]]::new()
    $inspected = 0

    foreach ($product in $frozen) {
        $repoPath = Join-Path $fleetRoot ([string]$product.productId)
        if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) { continue }
        $inspected++

        # Config files anywhere in the tree, excluding dependency directories.
        $configs = @(
            Get-ChildItem -LiteralPath $repoPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -notmatch '\\(node_modules|\.git|\.venv|__pycache__|dist|build|out|\.next)\\' -and
                    ($_.Name -eq 'eas.json' -or $_.Name -like 'app.config.*')
                }
        )
        foreach ($config in $configs) {
            $findings.Add("$($product.productId): $($config.FullName.Substring($fleetRoot.Length).TrimStart('\','/'))")
        }

        # app.json only counts when it actually carries an Expo block; the
        # filename alone is used by plenty of non-mobile tooling.
        $appJsons = @(
            Get-ChildItem -LiteralPath $repoPath -Recurse -File -Force -Filter 'app.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|\.venv|__pycache__|dist|build|out|\.next)\\' }
        )
        foreach ($appJson in $appJsons) {
            $parsed = $null
            try { $parsed = Get-Content -LiteralPath $appJson.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $parsed = $null }
            if ($null -ne $parsed -and $null -ne $parsed.expo) {
                $findings.Add("$($product.productId): $($appJson.FullName.Substring($fleetRoot.Length).TrimStart('\','/')) carries an 'expo' block")
            }
        }

        # Native project directories at any workspace root.
        foreach ($native in @('android', 'ios')) {
            $nativePath = Join-Path $repoPath $native
            if (Test-Path -LiteralPath $nativePath -PathType Container) {
                $findings.Add("$($product.productId): native $native/ directory")
            }
            $nestedNative = @(
                Get-ChildItem -LiteralPath $repoPath -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notin @('node_modules', '.git') } |
                    ForEach-Object { Join-Path $_.FullName $native } |
                    Where-Object { Test-Path -LiteralPath $_ -PathType Container }
            )
            foreach ($nested in $nestedNative) {
                $findings.Add("$($product.productId): native $($nested.Substring($fleetRoot.Length).TrimStart('\','/'))")
            }
        }

        # Expo / React Native dependencies in any tracked manifest.
        $manifests = @(
            Get-ChildItem -LiteralPath $repoPath -Recurse -File -Force -Filter 'package.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|dist|build|out|\.next)\\' }
        )
        foreach ($manifest in $manifests) {
            $parsed = $null
            try { $parsed = Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
            foreach ($section in @('dependencies', 'devDependencies')) {
                if ($null -eq $parsed.$section) { continue }
                $hits = @(
                    $parsed.$section.PSObject.Properties |
                        Where-Object { $_.Name -eq 'expo' -or $_.Name -like 'expo-*' -or $_.Name -eq 'react-native' -or $_.Name -like '@expo/*' } |
                        ForEach-Object { $_.Name }
                )
                if ($hits.Count -gt 0) {
                    $relative = $manifest.FullName.Substring($fleetRoot.Length).TrimStart('\', '/')
                    $findings.Add("$($product.productId): $relative $section carries $($hits -join ', ')")
                }
            }
        }
    }

    if ($findings.Count -gt 0) {
        return @{ Passed = $false; Detail = "mobile artifacts exist under frozen product(s): $($findings -join '; '). Remove them and check whether a matching remote identity (Expo/EAS project, Apple bundle identifier, Play package, Firebase app) was also created -- the on-disk file is the visible half, and the registered identifier is the half that cannot be taken back." }
    }
    return @{ Passed = $true; Detail = "inspected $inspected of $($frozen.Count) frozen product(s) present on this machine" }
}

# ---------------------------------------------------------------------------

$behaviors = @(
    @{ Name = 'mobile-scope.json is structurally sound';                 Run = { Test-SchemaIsSound } }
    @{ Name = 'every fleet repository carries a classification';         Run = { Test-EveryFleetRepoIsClassified } }
    @{ Name = 'sabhi, empowera and documed are still frozen';            Run = { Test-FrozenProductsStayFrozen } }
    @{ Name = 'global-agent-policy.md still carries the guard verbatim'; Run = { Test-PolicyStillCarriesTheGuard } }
    @{ Name = 'no frozen product has grown a mobile footprint';          Run = { Test-NoFrozenProductHasMobileArtifacts } }
)
foreach ($behavior in $behaviors) {
    $result = & $behavior.Run
    Report $behavior.Name ([bool]$result.Passed) ([string]$result.Detail)
}

Write-Host ''
Write-Host "SCOPE: $($products.Count) products classified, $($frozen.Count) frozen, $(@($standard.repos.PSObject.Properties).Count) repos on the repo-standard roster"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
