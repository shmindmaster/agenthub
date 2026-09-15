#Requires -Version 5.1

function Get-AgentHubStableFileHash {
    param([Parameter(Mandatory)][string]$Path)

    $textExtensions = @(
        '.cjs', '.cmd', '.css', '.cts', '.csv', '.editorconfig', '.eslintrc',
        '.example', '.gitattributes', '.html', '.js', '.json', '.map',
        '.markdown', '.md', '.mdc', '.mjs', '.mts', '.npmignore', '.nycrc',
        '.ps1', '.psm1', '.py', '.sh', '.svg', '.toml', '.ts', '.tsx', '.txt',
        '.xml', '.yaml', '.yml'
    )
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in $textExtensions) {
        $text = [System.IO.File]::ReadAllText($Path)
        $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
    } else {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Get-AgentHubGitTrackedRelativeFiles {
    # Enumerates the files under $Path that git considers committed content
    # (tracked, not gitignored, not merely present-on-disk) for the work tree
    # $Path happens to belong to. This is the trust root for the registry
    # content hash, so it fails loudly rather than ever silently falling back
    # to a filesystem walk: a hash basis that can't prove it only reflects
    # committed content is not a hash basis at all.
    #
    # `-C $Path` matters: the worktree and the main checkout share one git
    # object store but are separate work trees, so git must be invoked with
    # cwd set to the tree actually being hashed, not wherever the caller's
    # process happens to be running from.
    #
    # `-z` (NUL-delimited output) is used instead of the default newline-
    # delimited listing because git quotes/escapes paths containing spaces or
    # non-ASCII characters unless -z (or core.quotepath=false) is given; NUL
    # splitting avoids that ambiguity entirely.
    param([Parameter(Mandatory)][string]$Path)

    # Windows commonly has more than one git.exe on PATH (e.g. Git for
    # Windows' mingw64\bin and cmd shims). Any one of them is fine for
    # enumeration; take the first deterministically rather than letting an
    # array leak into the invocation below.
    $gitCommand = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommand) {
        throw "Get-AgentHubRegistryHashBasisValue requires 'git' on PATH to enumerate tracked files for '$Path', and it was not found. Refusing to fall back to a filesystem walk, which would silently include untracked/ignored files and produce a wrong hash."
    }

    $toplevelOutput = & $gitCommand.Source -C $Path rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Get-AgentHubRegistryHashBasisValue could not resolve a git work tree for '$Path' (git rev-parse --show-toplevel failed: $toplevelOutput). Refusing to fall back to a filesystem walk."
    }

    $rawOutput = & $gitCommand.Source -C $Path ls-files -z 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Get-AgentHubRegistryHashBasisValue: 'git ls-files' failed for '$Path' (exit $LASTEXITCODE): $rawOutput"
    }

    if ($null -eq $rawOutput -or $rawOutput.Length -eq 0) { return @() }
    $joined = ($rawOutput -join '')
    return @($joined -split [string][char]0 | Where-Object { $_.Length -gt 0 })
}

function Get-AgentHubRegistryHashBasisValue {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-AgentHubStableFileHash -Path $Path
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }

    $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
    [string[]]$relativePaths = @(Get-AgentHubGitTrackedRelativeFiles -Path $root)
    if ($relativePaths.Count -eq 0) {
        throw "Get-AgentHubRegistryHashBasisValue found zero git-tracked files under '$root'. Refusing to hash an empty work set silently -- this usually means the path is wrong or the directory is entirely gitignored."
    }
    [Array]::Sort($relativePaths, [System.StringComparer]::Ordinal)
    $inventory = @(
        foreach ($relativePath in $relativePaths) {
            $filePath = Join-Path $root ($relativePath -replace '/', '\')
            '{0}|{1}' -f $relativePath, (Get-AgentHubStableFileHash -Path $filePath)
        }
    ) -join "`n"
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($inventory)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}
