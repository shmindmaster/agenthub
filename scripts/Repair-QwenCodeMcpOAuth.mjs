// Repair-QwenCodeMcpOAuth.mjs -- AgentHub guard for the qwen-code MCP OAuth
// refresh hotfix.
//
// THE DEFECT
// Qwen Code ships its MCP OAuth token storage inside content-hashed bundle
// chunks (npm global install). Through 0.21.6, FileTokenStorage.getCredentials
// and KeychainTokenStorage.getCredentials return null for EXPIRED tokens, so
// MCPOAuthProvider.getValidToken never reaches its refresh-token branch.
// OAuth servers with short-lived access tokens (Linear ~24h, Notion ~8h) then
// appear unauthenticated and demand a browser re-auth on every session; the
// re-auth itself fails often enough (stale consent page -> "Invalid approval"
// on mcp.linear.app/callback) to look like a connection bug.
//
// THE FIX
// Remove the isTokenExpired early-return from both getCredentials
// implementations. Expired-but-present credentials then reach the refresh
// path, which works with the stored clientId + refreshToken + resource.
//
// NOT THIS BUG (read before patching)
// If qwen-code fails BEFORE token exchange -- "Failed to discover OAuth
// configuration from MCP server" -- the server URL itself is likely
// unreachable from this egress, and nothing in this repository fixes that.
// Run Test-McpOAuthReachability.js (same directory) first. Known foreign
// signature (documented 2026-08-05 on a Comcast residential egress): every
// notion.com / notion.so hostname resets during the TLS handshake on IPv4 and
// IPv6 while a control SNI on the same Notion-owned edge IP completes, DNS
// returns the genuine NOTION-WEB records, and Notion answers fine from other
// vantage points. That is a hostname-keyed network block (gateway security,
// ISP middlebox, or the site edge refusing the client IP). Remediate with the
// network operator: renew the public IP, check gateway blocklists, or change
// egress -- never re-patch qwen-code for it.
//
// This script is idempotent and version-agnostic: chunk file names change
// between releases, so it scans every chunk-*.js for the known code shapes.
// It never invents a replacement shape -- an unrecognized variant is reported
// as shape-drift for manual review instead of guessed at.
//
// MODES
//   node Repair-QwenCodeMcpOAuth.mjs           patch mode (SessionStart hook,
//                                              sync apply, manual repair):
//                                              patches when needed; stdout is
//                                              Qwen hook output JSON.
//   node Repair-QwenCodeMcpOAuth.mjs --check   read-only audit for sync:
//                                              stdout is one status JSON line.
//
// EXIT CODES
//   patch mode: 0 healthy or patched, 2 shape-drift, 1 hard error
//   --check:    0 healthy, 3 patch needed, 2 shape-drift, 0 no-install,
//               1 hard error
//
// INSTALL LOCATION
// Defaults to %APPDATA%\npm\node_modules\@qwen-code\qwen-code; override with
// QWEN_CODE_INSTALL_DIR (used by tests).
//
// A personal mirror of this file lives at
// %USERPROFILE%\.qwen\scripts\repair-mcp-oauth-hotfix.js so the Qwen Code
// SessionStart hook keeps working even when this repository is unavailable.
// Edit the canonical copy in the agenthub repository and re-sync; do not let
// the two diverge.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const HOTFIX_MARKER = 'HOTFIX: return expired credentials';

// FileTokenStorage.getCredentials: isTokenExpired early-return after
// tokens.get(serverName).
const FILE_STORAGE_PATTERN =
  /(async getCredentials\(serverName\) \{\s*const tokens = await this\.loadTokens\(\);\s*const credentials = tokens\.get\(serverName\);\s*if \(!credentials\) \{\s*return null;\s*\})\s*if \(this\.isTokenExpired\(credentials\)\) \{\s*return null;\s*\}/;

// KeychainTokenStorage.getCredentials: isTokenExpired early-return after
// JSON.parse(data).
const KEYCHAIN_STORAGE_PATTERN =
  /(const credentials = JSON\.parse\(data\);)\s*if \(this\.isTokenExpired\(credentials\)\) \{\s*return null;\s*\}/;

// Definition shape only: chunks that merely CALL getCredentials(serverName)
// (e.g. acpAgent-*.js, the delegating wrappers) must never count as suspect.
const DEFINITION_SHAPE = /getCredentials\(serverName\)\s*\{/;

const HOTFIX_NOTE_FILE =
  '$1\n    // HOTFIX: return expired credentials so MCPOAuthProvider.getValidToken can\n    // reach its refresh-token branch; the upstream early-return here breaks\n    // OAuth refresh (Linear/Notion) whenever encrypted file storage is used.\n    // Re-applied by AgentHub scripts/Repair-QwenCodeMcpOAuth.mjs.';

const HOTFIX_NOTE_KEYCHAIN =
  '$1\n      // HOTFIX: return expired credentials so MCPOAuthProvider.getValidToken can\n      // reach its refresh-token branch; the upstream early-return here breaks\n      // OAuth refresh whenever keychain storage is used.\n      // Re-applied by AgentHub scripts/Repair-QwenCodeMcpOAuth.mjs.';

const checkMode = process.argv.includes('--check');

function emit(obj) {
  process.stdout.write(JSON.stringify(obj));
}

function scan(chunksDir) {
  const result = { patchedNow: [], healthy: [], needPatch: [], suspect: [] };
  const files = fs
    .readdirSync(chunksDir)
    .filter((f) => f.startsWith('chunk-') && f.endsWith('.js'));

  for (const file of files) {
    const filePath = path.join(chunksDir, file);
    let src;
    try {
      src = fs.readFileSync(filePath, 'utf8');
    } catch {
      continue;
    }
    if (!src.includes('isTokenExpired')) {
      continue;
    }
    const hasMarker = src.includes(HOTFIX_MARKER);
    const fileMatch = FILE_STORAGE_PATTERN.test(src);
    const keychainMatch = KEYCHAIN_STORAGE_PATTERN.test(src);

    if (fileMatch || keychainMatch) {
      result.needPatch.push(file);
      if (!checkMode) {
        let out = src;
        if (fileMatch) out = out.replace(FILE_STORAGE_PATTERN, HOTFIX_NOTE_FILE);
        if (keychainMatch) {
          out = out.replace(KEYCHAIN_STORAGE_PATTERN, HOTFIX_NOTE_KEYCHAIN);
        }
        const tmp = filePath + '.hotfix.tmp';
        fs.writeFileSync(tmp, out, { mode: 0o644 });
        fs.renameSync(tmp, filePath);
        result.patchedNow.push(file);
      }
      continue;
    }
    if (hasMarker) {
      result.healthy.push(file);
      continue;
    }
    if (DEFINITION_SHAPE.test(src)) {
      // Has a getCredentials definition but not the known buggy shape and no
      // marker: the bundle changed shape. Never guess a replacement -- flag it.
      result.suspect.push(file);
    }
  }
  return result;
}

function main() {
  const candidates = process.env.QWEN_CODE_INSTALL_DIR
    ? [process.env.QWEN_CODE_INSTALL_DIR]
    : process.platform === 'win32'
      ? [
          path.join(process.env.LOCALAPPDATA || '', 'qwen-code', 'qwen-code'),
          path.join(process.env.APPDATA || '', 'npm', 'node_modules', '@qwen-code', 'qwen-code'),
        ]
      : [
          path.join(os.homedir(), '.local', 'lib', 'qwen-code'),
          path.join(os.homedir(), '.npm-global', 'lib', 'node_modules', '@qwen-code', 'qwen-code'),
        ];
  const baseDir = candidates.find((candidate) => fs.existsSync(path.join(candidate, 'chunks')));
  const chunksDir = baseDir ? path.join(baseDir, 'chunks') : null;

  if (!chunksDir) {
    if (checkMode) {
      emit({ status: 'no-install', checked: candidates });
      return 0;
    }
    emit({});
    return 0;
  }

  const r = scan(chunksDir);

  if (checkMode) {
    if (r.needPatch.length > 0) {
      emit({ status: 'patch-needed', path: chunksDir, files: r.needPatch });
      return 3;
    }
    if (r.suspect.length > 0) {
      emit({ status: 'shape-drift', path: chunksDir, files: r.suspect });
      return 2;
    }
    emit({ status: 'healthy', path: chunksDir, files: r.healthy });
    return 0;
  }

  if (r.patchedNow.length > 0) {
    emit({
      hookSpecificOutput: {
        additionalContext:
          `MCP OAuth refresh hotfix re-applied to qwen-code chunks: ${r.patchedNow.join(', ')}. ` +
          'A previous update had restored the upstream expired-token bug; MCP OAuth refresh ' +
          '(Linear/Notion) works again from this session on.'
      }
    });
    return 0;
  }
  if (r.suspect.length > 0) {
    emit({
      hookSpecificOutput: {
        additionalContext:
          'WARNING: the qwen-code MCP OAuth refresh hotfix could not be applied automatically ' +
          `(unrecognized token-storage shape in chunks: ${r.suspect.join(', ')}). Linear/Notion MCP ` +
          'OAuth may fall back to re-authentication loops. Review getCredentials in the installed ' +
          'qwen-code chunks and update AgentHub scripts/Repair-QwenCodeMcpOAuth.mjs patterns.'
      }
    });
    return 2;
  }
  emit({});
  return 0;
}

try {
  process.exit(main());
} catch (err) {
  try {
    if (checkMode) {
      emit({ status: 'error', message: String((err && err.message) || err) });
    } else {
      emit({});
    }
  } catch {
    // stdout unusable; exit code carries the failure.
  }
  process.exit(1);
}
