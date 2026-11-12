// Behavior tests for scripts/registry-content-hash.mjs — the Node port of
// scripts/RegistryContentHash.ps1. Fixtures are throwaway git work trees under
// $AGENTHUB_TEST_SCRATCH (or the OS temp directory), never this checkout:
// 'git init' plus 'git add' is enough for 'git ls-files' to report a file as
// tracked, so no commit and no user identity is required.
//
// Run: node --test scripts/registry-content-hash.test.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  checkRegistryHashes,
  contentHashForPath,
  extensionOf,
  isTextFilePath,
  main,
  stableFileHash,
} from './registry-content-hash.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const scratchRoot = process.env.AGENTHUB_TEST_SCRATCH || tmpdir();
const createdDirectories = [];

after(() => {
  for (const directory of createdDirectories) rmSync(directory, { recursive: true, force: true });
});

function makeScratch(prefix) {
  const directory = mkdtempSync(path.join(scratchRoot, prefix));
  createdDirectories.push(directory);
  return directory;
}

function runGit(cwd, args) {
  const result = spawnSync('git', ['-C', cwd, ...args], { encoding: 'utf8' });
  assert.equal(result.status, 0, `git ${args.join(' ')} failed: ${(result.stderr || result.error || '').toString().trim()}`);
  return result.stdout;
}

function writeFile(root, relativePath, content) {
  const target = path.join(root, ...relativePath.split('/'));
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, content);
  return target;
}

/**
 * A fixture package in its own git work tree:
 * { workRoot, packageDir, package(relativeToWorkRoot) }. Files listed are
 * committed-to-index content; everything else created later is untracked.
 */
function newFixtureRepo({ files = {}, gitignore = '' } = {}) {
  const workRoot = makeScratch('agenthub-node-hash-fixture-');
  const packageDir = path.join(workRoot, 'package');
  mkdirSync(packageDir, { recursive: true });
  if (gitignore) writeFile(workRoot, '.gitignore', gitignore);
  for (const [relativePath, content] of Object.entries(files)) writeFile(packageDir, relativePath, content);
  runGit(workRoot, ['init', '-q']);
  runGit(workRoot, ['add', '-A']);
  return { workRoot, packageDir };
}

const sha256UpperHex = (text) => createHash('sha256').update(text, 'utf8').digest('hex').toUpperCase();

test('text files hash identically with LF, CRLF or lone CR', () => {
  const { packageDir } = newFixtureRepo({ files: { 'module.psm1': "function Get-Fixture {\n    'fixture'\n}\n" } });
  const lf = contentHashForPath(packageDir);
  writeFile(packageDir, 'module.psm1', "function Get-Fixture {\r\n    'fixture'\r\n}\r\n");
  assert.equal(contentHashForPath(packageDir), lf, 'a CRLF checkout must not move the hash');
  writeFile(packageDir, 'module.psm1', "function Get-Fixture {\r    'fixture'\r}\r");
  assert.equal(contentHashForPath(packageDir), lf, 'a lone CR normalizes like CRLF');
});

test('a file outside the text list is hashed as raw bytes, so line endings move it', () => {
  const { packageDir } = newFixtureRepo({ files: { 'unit.service': '[Unit]\nDescription=x\n' } });
  const lf = contentHashForPath(packageDir);
  writeFile(packageDir, 'unit.service', '[Unit]\r\nDescription=x\r\n');
  assert.notEqual(contentHashForPath(packageDir), lf, '.service is not in the text list; the hash must move');
});

test('an extension-less LICENSE counts as text, matching the PowerShell name list', () => {
  const { packageDir } = newFixtureRepo({ files: { LICENSE: 'line one\r\nline two\r\n' } });
  const crlf = contentHashForPath(packageDir);
  writeFile(packageDir, 'LICENSE', 'line one\nline two\n');
  assert.equal(contentHashForPath(packageDir), crlf, 'git checks LICENSE out with CRLF on Windows');
});

test('a gitignored file inside the package never moves the hash', () => {
  const { workRoot, packageDir } = newFixtureRepo({
    files: { 'content.md': 'fixture content for the gitignore probe\n' },
    gitignore: '*.mp4\n',
  });
  const before = contentHashForPath(packageDir);
  writeFile(packageDir, 'scratch.mp4', 'not a real video -- transient scratch content\n');
  runGit(workRoot, ['check-ignore', '-q', 'package/scratch.mp4']);
  assert.equal(contentHashForPath(packageDir), before, 'ignored content is not committed content');
});

test('an untracked file never moves the hash', () => {
  const { packageDir } = newFixtureRepo({ files: { 'content.md': 'tracked content only\n' } });
  const before = contentHashForPath(packageDir);
  writeFile(packageDir, 'notes.txt', 'present on disk but never git-added\n');
  assert.equal(contentHashForPath(packageDir), before, 'present-on-disk is not tracked');
});

test('a tracked file change moves the hash', () => {
  const { packageDir } = newFixtureRepo({ files: { 'content.md': 'tracked content\n' } });
  const before = contentHashForPath(packageDir);
  writeFile(packageDir, 'content.md', 'tracked content\n<!-- hash-sensitivity probe -->\n');
  assert.notEqual(contentHashForPath(packageDir), before);
});

test('the package hash is SHA-256 over ordinally sorted "<path>|<fileHash>" lines joined with LF', () => {
  const { packageDir } = newFixtureRepo({
    files: { 'b.md': 'second\n', 'a.md': 'first\n', 'nested/c.md': 'third\n' },
  });
  const inventory = ['a.md', 'b.md', 'nested/c.md']
    .map((relativePath) => `${relativePath}|${stableFileHash(path.join(packageDir, ...relativePath.split('/')))}`)
    .join('\n');
  assert.equal(contentHashForPath(packageDir), sha256UpperHex(inventory));
});

test('a text file hashes as UTF-8 over its LF-normalized content', () => {
  const { packageDir } = newFixtureRepo({ files: { 'x.txt': 'a\r\nb\rc\n' } });
  assert.equal(stableFileHash(path.join(packageDir, 'x.txt')), sha256UpperHex('a\nb\nc\n'));
});

test('a file path hashes alone, and equals the same file inside a package', () => {
  const { packageDir } = newFixtureRepo({ files: { 'solo.md': 'alone\n' } });
  const file = path.join(packageDir, 'solo.md');
  assert.equal(contentHashForPath(file), stableFileHash(file));
  assert.match(contentHashForPath(file), /^[0-9A-F]{64}$/);
});

test('the .NET Path.GetExtension mirror keeps the leading dot, and text matching is case-insensitive', () => {
  assert.equal(extensionOf('/pkg/.gitignore'), '.gitignore');
  assert.equal(extensionOf('/pkg/LICENSE'), '');
  assert.equal(extensionOf('/pkg/archive.tar.gz'), '.gz');
  assert.equal(extensionOf('/pkg/trailing.'), '');
  assert.ok(isTextFilePath('/pkg/.editorconfig'));
  assert.ok(isTextFilePath('C:\\pkg\\LICENSE'));
  assert.ok(isTextFilePath('C:\\pkg\\Notice'), 'PowerShell -in compares names case-insensitively');
  assert.ok(!isTextFilePath('/pkg/icon.png'));
});

test('a directory with no git-tracked files fails loudly instead of hashing an empty set', () => {
  const { packageDir } = newFixtureRepo({ files: { 'hidden.txt': 'ignored away\n' }, gitignore: 'package/*\n' });
  assert.throws(() => contentHashForPath(packageDir), /zero files/);
});

test('a path outside any git work tree fails loudly instead of walking the filesystem', () => {
  const orphan = makeScratch('agenthub-node-hash-non-worktree-');
  writeFile(orphan, 'file.txt', 'content outside any git work tree\n');
  assert.throws(
    () => contentHashForPath(orphan),
    /(git|tracked files)/,
    'must refuse to fall back to a filesystem walk',
  );
});

test('--check exits 0 on this repository, agreeing with every PowerShell-computed hashBasis', () => {
  const registry = JSON.parse(readFileSync(path.join(repoRoot, 'registry', 'capabilities.json'), 'utf8'));
  const lines = [];
  const errors = [];
  const collect = { write: (line) => lines.push(line), writeError: (line) => errors.push(line) };
  assert.equal(main(['--check'], collect), 0, `--check reported: ${errors.join(' ')}`);
  assert.equal(lines.length, registry.capabilities.length, 'one line per capability');
  for (const capability of registry.capabilities) {
    const line = lines.find((entry) => entry.includes(`  ${capability.id}  `));
    assert.ok(line, `no --check line for ${capability.id}`);
    assert.ok(line.startsWith('ok '), `expected an ok line, got: ${line}`);
    assert.ok(line.endsWith(capability.contentHash), `computed hash does not equal the recorded one: ${line}`);
  }
});

test('a path argument prints exactly one hash', () => {
  const { packageDir } = newFixtureRepo({ files: { 'content.md': 'command line probe\n' } });
  const lines = [];
  assert.equal(main([packageDir], { write: (line) => lines.push(line), writeError: () => {} }), 0);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^[0-9A-F]{64}$/);
  assert.equal(lines[0], contentHashForPath(packageDir));
});

test('--check reports a drifted, missing or lowercase contentHash against a synthetic registry', () => {
  const { workRoot, packageDir } = newFixtureRepo({ files: { 'content.md': 'registry fixture\n' } });
  const registryPath = writeFile(workRoot, 'registry/capabilities.json', '{}');
  const actual = contentHashForPath(packageDir);
  const statusesFor = (contentHash) =>
    checkRegistryHashes(registryPath).map((result) => `${result.id}:${result.status}`);
  const writeRegistry = (hash) =>
    writeFileSync(registryPath, `${JSON.stringify({ capabilities: [{ id: 'demo', hashBasis: 'package', contentHash: hash }] })}\n`);

  writeRegistry(actual);
  assert.deepEqual(statusesFor(actual), ['demo:ok']);

  writeRegistry(actual.toLowerCase());
  assert.deepEqual(statusesFor(actual.toLowerCase()), ['demo:ok'], 'PowerShell -ne compares hashes case-insensitively');

  writeRegistry('DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF');
  assert.deepEqual(statusesFor('DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'), ['demo:drift']);

  writeRegistry(null);
  assert.deepEqual(statusesFor(null), ['demo:drift'], 'a capability with no recorded contentHash is drift, not a pass');
});
