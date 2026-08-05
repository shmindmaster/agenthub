#Requires -Version 5.1
<#
Behavior tests for scripts/Repair-QwenCodeMcpOAuth.js, the guard that keeps
the qwen-code MCP OAuth refresh hotfix alive across npm updates.

THE DEFECT
qwen-code's bundled token storage returns null from getCredentials for
expired tokens, so MCPOAuthProvider.getValidToken never reaches its
refresh-token branch; every npm update restores that shape and Linear/Notion
fall back to browser re-authentication loops. The repair script removes the
isTokenExpired early-return from the FileTokenStorage and KeychainTokenStorage
shapes. Chunk file names change between releases, so the script scans every
chunk-*.js for code shapes instead of names.

WHAT THIS FILE COVERS
  1. --check detects an unpatched bundle (exit 3, status patch-needed) and
     names the affected chunks.
  2. Patch mode removes BOTH early-returns, inserts the HOTFIX marker, and
     leaves an unrelated isTokenExpired chunk byte-identical (no over-match,
     including the getAllCredentials decoys that also mention isTokenExpired).
  3. Idempotency: after patching, --check exits 0 (healthy) and a second
     patch run rewrites nothing (file hashes unchanged).
  4. Call-site-only chunks (the acpAgent shape) are never classified suspect.
  5. Shape drift: an unrecognized getCredentials definition that references
     isTokenExpired is reported (exit 2 in both modes) and left UNMODIFIED --
     the script must never guess a replacement shape.
  6. Missing install: patch mode is a silent no-op (exit 0, {} hook output);
     --check reports no-install and exits 0.

Run: pwsh -NoProfile -File tests/Test-QwenOAuthRepair.ps1
     powershell.exe -NoProfile -File tests/Test-QwenOAuthRepair.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $repoRoot 'scripts\Repair-QwenCodeMcpOAuth.js'

$passed = 0
$failed = 0
function Assert-True {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        $script:passed++
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        $script:failed++
        Write-Host "FAIL: $Name" -ForegroundColor Red
    }
}

function Invoke-Repair {
    param([string[]]$Arguments, [string]$InstallDir)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $previousEnv = $env:QWEN_CODE_INSTALL_DIR
    $env:QWEN_CODE_INSTALL_DIR = $InstallDir
    try {
        $output = & node $scriptPath @Arguments 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
        $env:QWEN_CODE_INSTALL_DIR = $previousEnv
    }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output.Trim() }
}

function Get-FileSha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host 'FAIL: node.exe is required on PATH to run Test-QwenOAuthRepair.ps1 and was not found.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'RESULT: 0 passed, 1 failed'
    exit 1
}
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Host "FAIL: repair script missing at $scriptPath" -ForegroundColor Red
    Write-Host ''
    Write-Host 'RESULT: 0 passed, 1 failed'
    exit 1
}

# ---------------------------------------------------------------------------
# Fixtures: a synthetic qwen-code install with the upstream buggy shapes,
# reproduced from the 0.21.6 bundle.
# ---------------------------------------------------------------------------
$buggyFileStorage = @'
var FileTokenStorage = class extends BaseTokenStorage {
  async getCredentials(serverName) {
    const tokens = await this.loadTokens();
    const credentials = tokens.get(serverName);
    if (!credentials) {
      return null;
    }
    if (this.isTokenExpired(credentials)) {
      return null;
    }
    return credentials;
  }
  async getAllCredentials() {
    const tokens = await this.loadTokens();
    const result = new Map();
    for (const [serverName, credentials] of tokens) {
      if (!this.isTokenExpired(credentials)) {
        result.set(serverName, credentials);
      }
    }
    return result;
  }
};
'@

$buggyKeychainStorage = @'
var KeychainTokenStorage = class extends BaseTokenStorage {
  async getCredentials(serverName) {
    try {
      const sanitizedName = this.sanitizeServerName(serverName);
      const data = await keytar.getPassword(this.serviceName, sanitizedName);
      if (!data) {
        return null;
      }
      const credentials = JSON.parse(data);
      if (this.isTokenExpired(credentials)) {
        return null;
      }
      return credentials;
    } catch (error) {
      throw error;
    }
  }
  async getAllCredentials() {
    const result = new Map();
    const credentials = await keytar.findCredentials(this.serviceName);
    for (const cred of credentials) {
      const data = JSON.parse(cred.password);
      if (!this.isTokenExpired(data)) {
        result.set(cred.account, data);
      }
    }
    return result;
  }
};
'@

# No getCredentials definition at all -- mirrors BaseTokenStorage plus the
# acpAgent call-site shape. Must survive every run byte-identical and must
# never be classified suspect.
$unrelatedChunk = @'
var BaseTokenStorage = class {
  isTokenExpired(credentials) {
    if (!credentials.token.expiresAt) {
      return false;
    }
    const bufferMs = 5 * 60 * 1000;
    return Date.now() + bufferMs >= credentials.token.expiresAt;
  }
};
async function probeAuth(serverName) {
  const requiresAuth = await new MCPOAuthTokenStorage().getCredentials(serverName) === null;
  return requiresAuth;
}
'@

# A plausible future storage shape the patterns do not recognize: definition
# form plus isTokenExpired, no marker. Must be reported, never modified.
$futureShape = @'
var FutureTokenStorage = class {
  isTokenExpired(credentials) {
    return credentials.expired === true;
  }
  async getCredentials(serverName) {
    const row = await this.database.find(serverName);
    if (!row) {
      return null;
    }
    if (this.isTokenExpired(row)) {
      return null;
    }
    return row;
  }
};
'@

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-oauth-repair-' + [guid]::NewGuid().ToString('n'))

try {
    $chunksDir = Join-Path $scratch 'chunks'
    New-Item -ItemType Directory -Path $chunksDir -Force | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $fileChunkPath = Join-Path $chunksDir 'chunk-FILESTORAGE01.js'
    $keychainChunkPath = Join-Path $chunksDir 'chunk-KEYCHAIN0001.js'
    $unrelatedChunkPath = Join-Path $chunksDir 'chunk-UNRELATED001.js'
    [System.IO.File]::WriteAllText($fileChunkPath, $buggyFileStorage, $utf8NoBom)
    [System.IO.File]::WriteAllText($keychainChunkPath, $buggyKeychainStorage, $utf8NoBom)
    [System.IO.File]::WriteAllText($unrelatedChunkPath, $unrelatedChunk, $utf8NoBom)
    $unrelatedHashBefore = Get-FileSha256 -Path $unrelatedChunkPath

    # Behavior 1: --check detects the unpatched bundle.
    $r = Invoke-Repair -Arguments @('--check') -InstallDir $scratch
    Assert-True ($r.ExitCode -eq 3) "--check exits 3 (patch-needed) on unpatched bundle (got $($r.ExitCode))"
    $checkStatus = try { ($r.Output | ConvertFrom-Json).status } catch { '' }
    Assert-True ($checkStatus -eq 'patch-needed') "--check reports status patch-needed (got '$checkStatus')"
    Assert-True ($r.Output -match 'chunk-FILESTORAGE01\.js' -and $r.Output -match 'chunk-KEYCHAIN0001\.js') '--check names both affected chunks'

    # Behavior 2: patch mode removes both early-returns, marks them, and does
    # not touch the unrelated chunk.
    $r = Invoke-Repair -Arguments @() -InstallDir $scratch
    Assert-True ($r.ExitCode -eq 0) "patch mode exits 0 after patching (got $($r.ExitCode))"
    $patchedFile = [System.IO.File]::ReadAllText($fileChunkPath)
    $patchedKeychain = [System.IO.File]::ReadAllText($keychainChunkPath)
    Assert-True ($patchedFile -match 'HOTFIX: return expired credentials') 'file-storage chunk carries the HOTFIX marker'
    Assert-True ($patchedKeychain -match 'HOTFIX: return expired credentials') 'keychain chunk carries the HOTFIX marker'
    Assert-True ($patchedFile -notmatch 'if \(this\.isTokenExpired\(credentials\)\) \{\s*return null;') 'file-storage early-return removed'
    Assert-True ($patchedKeychain -notmatch 'if \(this\.isTokenExpired\(credentials\)\) \{\s*return null;') 'keychain early-return removed'
    Assert-True ($patchedFile -match 'if \(!this\.isTokenExpired\(credentials\)\) \{\s*result\.set') 'file-storage getAllCredentials decoy left intact'
    Assert-True ($patchedKeychain -match 'if \(!this\.isTokenExpired\(data\)\) \{\s*result\.set') 'keychain getAllCredentials decoy left intact'
    Assert-True ((Get-FileSha256 -Path $unrelatedChunkPath) -eq $unrelatedHashBefore) 'unrelated chunk byte-identical after patch'

    # Behavior 3: idempotency.
    $r = Invoke-Repair -Arguments @('--check') -InstallDir $scratch
    Assert-True ($r.ExitCode -eq 0) "--check exits 0 (healthy) after patching (got $($r.ExitCode))"
    $healthyStatus = try { ($r.Output | ConvertFrom-Json).status } catch { '' }
    Assert-True ($healthyStatus -eq 'healthy') "--check reports status healthy (got '$healthyStatus')"
    $fileHashAfterPatch = Get-FileSha256 -Path $fileChunkPath
    $keychainHashAfterPatch = Get-FileSha256 -Path $keychainChunkPath
    $r = Invoke-Repair -Arguments @() -InstallDir $scratch
    Assert-True ($r.ExitCode -eq 0) "second patch run exits 0 (got $($r.ExitCode))"
    Assert-True ($r.Output -eq '{}') "second patch run emits empty hook output (got '$($r.Output)')"
    Assert-True ((Get-FileSha256 -Path $fileChunkPath) -eq $fileHashAfterPatch) 'second patch run does not rewrite the file-storage chunk'
    Assert-True ((Get-FileSha256 -Path $keychainChunkPath) -eq $keychainHashAfterPatch) 'second patch run does not rewrite the keychain chunk'

    # Behavior 4: call-site-only chunks never count as suspect. Covered by the
    # healthy run above: chunk-UNRELATED001.js mentions isTokenExpired and a
    # getCredentials(serverName) call site, and --check still exited 0.
    Assert-True ($healthyStatus -eq 'healthy') 'call-site-only chunk did not trigger shape-drift'

    # Behavior 5: shape drift is reported and left untouched.
    $futureDir = Join-Path $scratch 'future'
    $futureChunks = Join-Path $futureDir 'chunks'
    New-Item -ItemType Directory -Path $futureChunks -Force | Out-Null
    $futurePath = Join-Path $futureChunks 'chunk-FUTURE00001.js'
    [System.IO.File]::WriteAllText($futurePath, $futureShape, $utf8NoBom)
    $futureHashBefore = Get-FileSha256 -Path $futurePath
    $r = Invoke-Repair -Arguments @('--check') -InstallDir $futureDir
    Assert-True ($r.ExitCode -eq 2) "--check exits 2 (shape-drift) on unrecognized shape (got $($r.ExitCode))"
    $driftStatus = try { ($r.Output | ConvertFrom-Json).status } catch { '' }
    Assert-True ($driftStatus -eq 'shape-drift') "--check reports status shape-drift (got '$driftStatus')"
    $r = Invoke-Repair -Arguments @() -InstallDir $futureDir
    Assert-True ($r.ExitCode -eq 2) "patch mode exits 2 on shape-drift (got $($r.ExitCode))"
    Assert-True ((Get-FileSha256 -Path $futurePath) -eq $futureHashBefore) 'shape-drift chunk left unmodified'

    # Behavior 6: missing install is a silent no-op, not an error.
    $emptyDir = Join-Path $scratch 'empty-install'
    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
    $r = Invoke-Repair -Arguments @() -InstallDir $emptyDir
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -eq '{}') "patch mode silently no-ops without an install (exit $($r.ExitCode), '$($r.Output)')"
    $r = Invoke-Repair -Arguments @('--check') -InstallDir $emptyDir
    Assert-True ($r.ExitCode -eq 0) "--check exits 0 for missing install (got $($r.ExitCode))"
    $noInstallStatus = try { ($r.Output | ConvertFrom-Json).status } catch { '' }
    Assert-True ($noInstallStatus -eq 'no-install') "--check reports status no-install (got '$noInstallStatus')"
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
