#!/usr/bin/env node
/**
 * Node port of scripts/RegistryContentHash.ps1.
 *
 * Why: the registry content hash is the trust root for "the package on disk is
 * the package the registry says it is", and the only implementation was
 * PowerShell. A host without pwsh (Daytona sandboxes, plain Linux boxes) could
 * neither verify nor recompute a hash, so any change to a hashed package needed
 * a human follow-up. This file produces byte-identical hashes to
 * Get-AgentHubRegistryHashBasisValue and mirrors its helpers one for one.
 *
 * Mirror contract (authoritative source: scripts/RegistryContentHash.ps1,
 * behavior tests: tests/Test-RegistryContentHash.ps1):
 *   - enumeration is `git -C <path> ls-files -z`, NUL-split, never a filesystem
 *     walk; zero tracked files throws rather than hashing an empty work set;
 *   - a file path hashes as that file alone; a path that is neither a file nor
 *     a directory yields null (PowerShell returns $null);
 *   - text files are read as UTF-8 with the BOM stripped, CRLF and lone CR
 *     collapsed to LF, then re-encoded as UTF-8 without a BOM; every other file
 *     is hashed as raw bytes;
 *   - file hashes are uppercase-hex SHA-256; the package hash is
 *     uppercase-hex SHA-256 over `<relativePath>|<fileHash>` lines joined with
 *     LF, relative paths sorted ordinally (UTF-16 code-unit order, which is also
 *     JavaScript's default string sort order);
 *   - recorded hashes are compared case-insensitively, because PowerShell's `-ne`
 *     is case-insensitive;
 *   - git is bypassed only for personal-overlay packages
 *     (`overlays/personal/packages/...`), which are gitignored by design and
 *     hash from disk. Same branch as PowerShell, so the two stay consistent.
 *
 * Known divergences from PowerShell, neither reachable in tracked content today:
 *   - a text file with a UTF-16 BOM hashes as raw bytes here, while .NET's
 *     File.ReadAllText decodes it and re-encodes as UTF-8. No tracked file under
 *     any registry hashBasis carries a BOM of any kind (measured 2026-11-12);
 *     add decoding here if that ever stops being true.
 *   - a BOM-less text file in some other code page (Windows-1252) decodes
 *     differently in .NET and Node. Same rule: do not ship those in a package.
 *   - --check reads registry/capabilities.json only. The overlay merge that
 *     scripts/Validate-AgentHub.ps1 performs is out of scope for this tool.
 *
 * Usage:
 *   node scripts/registry-content-hash.mjs --check   # recompute every registry hashBasis
 *   node scripts/registry-content-hash.mjs <path>    # print one hash
 */
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync, realpathSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Keep these two lists in step with Get-AgentHubStableFileHash in
// scripts/RegistryContentHash.ps1: the hash definition is shared, not forked.
export const TEXT_EXTENSIONS = new Set([
  '.cjs', '.cmd', '.css', '.cts', '.csv', '.editorconfig', '.eslintrc',
  '.example', '.gitattributes', '.gitignore', '.html', '.js', '.json', '.jsonc', '.map',
  '.markdown', '.md', '.mdc', '.mjs', '.mts', '.npmignore', '.nycrc',
  '.ps1', '.psm1', '.py', '.service', '.sh', '.svg', '.timer', '.toml', '.ts', '.tsx', '.txt',
  '.xml', '.yaml', '.yml',
]);
// License files have no extension, and git checks them out with CRLF on Windows.
// PowerShell's `-in` compares names case-insensitively, so this set is lowercase.
const TEXT_FILE_NAMES = new Set(['license', 'notice', 'copying']);
const FILESYSTEM_SKIP_DIRECTORIES = new Set(['node_modules', '.git', '__pycache__']);

function fileNameOf(filePath) {
  const separator = Math.max(filePath.lastIndexOf('/'), filePath.lastIndexOf('\\'));
  return separator === -1 ? filePath : filePath.slice(separator + 1);
}

// .NET Path.GetExtension: the last '.' in the file name, which must not be its
// final character. A leading dot counts, so ".gitignore" has extension
// ".gitignore" rather than none.
export function extensionOf(filePath) {
  const name = fileNameOf(filePath);
  const dot = name.lastIndexOf('.');
  if (dot === -1 || dot === name.length - 1) return '';
  return name.slice(dot);
}

export function isTextFilePath(filePath) {
  if (TEXT_EXTENSIONS.has(extensionOf(filePath).toLowerCase())) return true;
  return TEXT_FILE_NAMES.has(fileNameOf(filePath).toLowerCase());
}

function sha256UpperHex(bytes) {
  return createHash('sha256').update(bytes).digest('hex').toUpperCase();
}

// ReadAllText + UTF8Encoding(false): BOM stripped, line endings normalized.
function normalizedTextBytes(buffer) {
  const withoutBom = buffer.length >= 3 && buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf
    ? buffer.subarray(3)
    : buffer;
  return Buffer.from(withoutBom.toString('utf8').replace(/\r\n/g, '\n').replace(/\r/g, '\n'), 'utf8');
}

export function stableFileHash(filePath) {
  const buffer = readFileSync(filePath);
  return sha256UpperHex(isTextFilePath(filePath) ? normalizedTextBytes(buffer) : buffer);
}

function runGit(dirPath, args, label) {
  const result = spawnSync('git', ['-C', dirPath, ...args], { encoding: 'buffer', maxBuffer: 32 * 1024 * 1024, windowsHide: true });
  if (result.status !== 0) {
    const detail = result.status === null
      ? `git could not be run (${(result.error && result.error.code) || 'unknown error'})`
      : `exit ${result.status}: ${(result.stderr ?? Buffer.alloc(0)).toString('utf8').trim()}`;
    throw new Error(`${label} for '${dirPath}' failed (${detail}). Refusing to fall back to a filesystem walk, which would silently include untracked or ignored files and produce a wrong hash.`);
  }
  return result.stdout;
}

/**
 * Files under dirPath that git considers committed content for the work tree the
 * path belongs to: tracked, not gitignored, not merely present-on-disk. This is
 * the trust root of the registry content hash, so it fails loudly instead of
 * ever returning a hash that cannot prove it reflects committed content.
 */
export function gitTrackedRelativeFiles(dirPath) {
  if (spawnSync('git', ['--version'], { encoding: 'buffer', windowsHide: true }).status !== 0) {
    throw new Error(`contentHashForPath requires 'git' on PATH to enumerate tracked files for '${dirPath}', and it was not found. Refusing to fall back to a filesystem walk, which would silently include untracked/ignored files and produce a wrong hash.`);
  }
  runGit(dirPath, ['rev-parse', '--show-toplevel'], 'contentHashForPath could not resolve a git work tree');
  const listing = runGit(dirPath, ['ls-files', '-z'], "'git ls-files'");
  return listing.toString('utf8').split('\0').filter((entry) => entry.length > 0);
}

/** The personal-overlay branch: hash the on-disk tree, no git required. */
export function filesystemRelativeFiles(dirPath) {
  const root = path.resolve(dirPath);
  const found = [];
  const walk = (current, relative) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const relativePath = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        // Skip common junk; keep everything else so the hash matches disk content.
        if (!FILESYSTEM_SKIP_DIRECTORIES.has(entry.name)) walk(path.join(current, entry.name), relativePath);
        continue;
      }
      if (!entry.isFile()) continue;
      if (entry.name === '.DS_Store' || entry.name === 'Thumbs.db') continue;
      found.push(relativePath);
    }
  };
  walk(root, '');
  return found.filter((relativePath) => relativePath.length > 0);
}

function isPersonalOverlayPackagePath(root) {
  return /[\\/]overlays[\\/]personal[\\/]packages([\\/]|$)/i.test(root.replaceAll('/', '\\'));
}

/** Mirrors Get-AgentHubRegistryHashBasisValue; null when the path is neither a file nor a directory. */
export function registryHashBasisValue(targetPath) {
  const stats = statSync(targetPath, { throwIfNoEntry: false });
  if (!stats || (!stats.isFile() && !stats.isDirectory())) return null;
  if (stats.isFile()) return stableFileHash(targetPath);

  const root = path.resolve(targetPath).replace(/[\\/]+$/, '');
  const relativePaths = isPersonalOverlayPackagePath(root)
    ? filesystemRelativeFiles(root)
    : gitTrackedRelativeFiles(root);
  if (relativePaths.length === 0) {
    throw new Error(`contentHashForPath found zero files under '${root}'. Refusing to hash an empty work set silently -- this usually means the path is wrong or the directory is entirely gitignored.`);
  }
  relativePaths.sort();
  const inventory = relativePaths
    .map((relativePath) => `${relativePath}|${stableFileHash(path.join(root, relativePath))}`)
    .join('\n');
  return sha256UpperHex(Buffer.from(inventory, 'utf8'));
}

/** Public entry point: the registry content hash for one file or package directory. */
export function contentHashForPath(targetPath) {
  return registryHashBasisValue(path.resolve(targetPath));
}

/** Recompute every hashBasis in the core registry and compare it with the recorded contentHash. */
export function checkRegistryHashes(registryPath = path.join(repoRoot, 'registry', 'capabilities.json')) {
  const document = JSON.parse(readFileSync(registryPath, 'utf8'));
  const root = path.resolve(path.dirname(registryPath), '..');
  return (document.capabilities ?? []).map((capability) => {
    const id = String(capability.id ?? capability.owner ?? '<unknown>');
    const basis = typeof capability.hashBasis === 'string' ? capability.hashBasis : '';
    const expected = capability.contentHash == null ? '' : String(capability.contentHash);
    if (basis === '') {
      return { id, hashBasis: basis, expected: expected || '<missing>', actual: null, status: 'no-hash-basis' };
    }
    const actual = contentHashForPath(path.resolve(root, basis));
    const matches = actual !== null && actual.toUpperCase() === expected.toUpperCase();
    return {
      id,
      hashBasis: basis,
      expected: expected || '<missing>',
      actual: actual ?? '<path-missing>',
      status: matches ? 'ok' : 'drift',
    };
  });
}

function formatCheckLine(result) {
  return result.status === 'ok'
    ? `ok    ${result.id}  ${result.hashBasis}  ${result.actual}`
    : `${result.status.padEnd(5)} ${result.id}  ${result.hashBasis}  computed=${result.actual} registry=${result.expected}`;
}

const USAGE = `Usage:
  node scripts/registry-content-hash.mjs --check   Recompute every registry hashBasis; non-zero exit on drift.
  node scripts/registry-content-hash.mjs <path>    Print the content hash for one file or package directory.
`;

export function main(argv, {
  write = (line) => process.stdout.write(`${line}\n`),
  writeError = (line) => process.stderr.write(`${line}\n`),
} = {}) {
  if (argv.includes('--check')) {
    const results = checkRegistryHashes();
    for (const result of results) write(formatCheckLine(result));
    const drifted = results.filter((result) => result.status !== 'ok');
    if (drifted.length > 0) {
      writeError(`${drifted.length} of ${results.length} registry hash bases do not match their recorded contentHash.`);
      return 1;
    }
    return 0;
  }

  if (argv.includes('--help') || argv.length === 0) {
    writeError(USAGE);
    return argv.length === 0 ? 2 : 0;
  }

  for (const target of argv.filter((arg) => !arg.startsWith('-'))) {
    const hash = contentHashForPath(target);
    if (hash === null) {
      writeError(`not a file or a directory: ${path.resolve(target)}`);
      return 1;
    }
    write(hash);
  }
  return 0;
}

// Compare physical paths: a symlinked invocation must still run, not exit 0 silently.
const physical = (target) => { try { return realpathSync(target); } catch { return path.resolve(target); } };
if (process.argv[1] && physical(process.argv[1]) === physical(fileURLToPath(import.meta.url))) {
  // Piping into `head` closes the pipe early; that is a normal way to read a
  // tool, not a crash. EPIPE stays quiet -- the exit code carries the verdict.
  const ignoreEpipe = (error) => {
    if (error.code !== 'EPIPE') throw error;
  };
  process.stdout.on('error', ignoreEpipe);
  process.stderr.on('error', ignoreEpipe);
  process.exitCode = main(process.argv.slice(2));
}
