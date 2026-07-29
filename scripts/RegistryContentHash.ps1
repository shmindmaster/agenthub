#Requires -Version 5.1

function Get-AgentHubStableFileHash {
    param([Parameter(Mandatory)][string]$Path)

    $textExtensions = @(
        '.cjs', '.cmd', '.css', '.cts', '.csv', '.editorconfig', '.eslintrc',
        '.example', '.gitattributes', '.html', '.js', '.json', '.map',
        '.markdown', '.md', '.mdc', '.mjs', '.mts', '.npmignore', '.nycrc',
        '.ps1', '.py', '.sh', '.svg', '.toml', '.ts', '.tsx', '.txt',
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

function Get-AgentHubRegistryHashBasisValue {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-AgentHubStableFileHash -Path $Path
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }

    $excludedDirectoryNames = @(
        'node_modules', '.venv', '__pycache__', 'dist', 'build', '.next'
    )
    $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
    [string[]]$filePaths = @(
        Get-ChildItem -LiteralPath $root -Recurse -File -Force |
            Where-Object {
                $relativePath = $_.FullName.Substring($root.Length).TrimStart('\')
                @($relativePath -split '\\' | Where-Object {
                    $_ -in $excludedDirectoryNames
                }).Count -eq 0
            } |
            ForEach-Object FullName
    )
    [Array]::Sort($filePaths, [System.StringComparer]::Ordinal)
    $inventory = @(
        foreach ($filePath in $filePaths) {
            $relativePath = $filePath.Substring($root.Length).TrimStart('\').Replace('\', '/')
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
