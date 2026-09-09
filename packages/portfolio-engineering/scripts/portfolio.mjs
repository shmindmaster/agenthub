#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync as fsRealpath, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const packageRoot = fileURLToPath(new URL('../', import.meta.url));
const realpathSync = fsRealpath.native;
export const statuses = ['passed', 'failed', 'blocked', 'not-run', 'not-applicable'];
export function command(exe, args, cwd, timeout = 20000) {
  const result = spawnSync(exe, args, { cwd, encoding: 'utf8', windowsHide: true, timeout, maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`${exe} failed (${result.error?.code ?? result.status})`);
  return result.stdout.trim();
}
const sha256 = value => createHash('sha256').update(value).digest('hex');
const samePath = (a, b) => process.platform === 'win32' ? resolve(a).toLowerCase() === resolve(b).toLowerCase() : resolve(a) === resolve(b);
const git = (root, ...args) => command('git', ['-C', root, ...args]);
function inside(root, path) {
  const rel = relative(root, path);
  return rel !== '' && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}
export function loadManifest(path = join(packageRoot, 'portfolio.json')) {
  const manifest = JSON.parse(readFileSync(path, 'utf8'));
  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.repos) || !Array.isArray(manifest.excluded)) throw new Error('Invalid inventory contract');
  const seen = new Set();
  for (const row of manifest.repos) {
    if (!/^[a-z0-9-]+$/.test(row.id) || row.path !== row.id || seen.has(row.id) || manifest.excluded.some(x => x.id === row.id)) throw new Error('Invalid, duplicate, or excluded repository');
    if (!['business','website','redirect','tool','learning','infrastructure'].includes(row.kind)) throw new Error('Invalid repository kind');
    if (!Array.isArray(row.checks) || row.checks.some(x => !statuses.includes(x.status))) throw new Error('Invalid check disposition');
    seen.add(row.id);
  }
  return manifest;
}
export function target(manifest, id, root = manifest.fleetRoot) {
  const row = manifest.repos.find(r => r.id === id);
  if (!row) throw new Error(`Repository is outside the approved allowlist: ${id}`);
  const fleet = realpathSync(root);
  const path = resolve(fleet, row.path);
  if (!inside(fleet, path)) throw new Error('Repository escapes the fleet root');
  if (!existsSync(path)) return { row, path, missing: true };
  const canonical = realpathSync(path);
  if (!inside(fleet, canonical)) throw new Error('Repository link escapes the fleet root');
  if (!samePath(realpathSync(git(canonical, 'rev-parse', '--show-toplevel')), canonical)) throw new Error('Not a repository root');
  return { row, path: canonical, missing: false };
}
export function remoteIdentity(value) {
  // Never return raw remotes: HTTPS URLs can carry credentials.
  let path;
  if (/^https?:\/\//i.test(value)) {
    try { const url = new URL(value); if (url.hostname !== 'github.com' || url.protocol !== 'https:' || url.search || url.hash) return null; path = url.pathname.slice(1); } catch { return null; }
  } else { path = value.match(/^git@(?:github\.com|github-shmindmaster):([^\s]+)$/i)?.[1]; }
  return path && /^[\w.-]+\/[\w.-]+$/.test(path) ? path.replace(/\.git$/, '').toLowerCase() : null;
}
export function snapshot(path) {
  const head = git(path, 'rev-parse', 'HEAD');
  const branch = git(path, 'branch', '--show-current');
  const commonDirectory = realpathSync(git(path, 'rev-parse', '--path-format=absolute', '--git-common-dir'));
  const status = git(path, 'status', '--porcelain=v1', '--untracked-files=all');
  return { head, branch, commonDirectory, dirty: status.length > 0, statusHash: sha256(status) };
}
export function inspect(manifest, id, root = manifest.fleetRoot) {
  const located = target(manifest, id, root);
  const result = { id, kind: located.row.kind, lifecycle: located.row.lifecycle, tracker: located.row.tracker, path: located.path, checks: located.row.checks };
  if (located.missing) return { ...result, status: 'blocked', reason: 'Checkout unavailable' };
  const state = snapshot(located.path);
  const remotes = git(located.path, 'remote').split('\n');
  const hasOrigin = remotes.includes('origin');
  const identity = hasOrigin ? remoteIdentity(git(located.path, 'remote', 'get-url', 'origin')) : null;
  if (hasOrigin && identity === null) return { ...result, ...state, status: 'blocked', reason: 'Unsupported origin identity' };
  if (identity !== located.row.remote?.toLowerCase() && !(identity === null && located.row.remote === null)) return { ...result, ...state, status: 'blocked', reason: 'Remote identity does not match allowlist' };
  let files = git(located.path, 'ls-files', '-z').split('\0').filter(Boolean);
  const manifestPaths = files.filter(f => /(^|\/)(package\.json|pyproject\.toml|requirements[^/]*\.txt|uv\.lock|poetry\.lock|pnpm-lock\.yaml|package-lock\.json)$/.test(f) && !/(^|\/)(examples|fixtures|\.demo|vendor|node_modules|src\/runtime\/models)(\/|$)/.test(f));
  const packages = manifestPaths.filter(f => f.endsWith('package.json')).map(f => {
    try {
      const source = realpathSync(join(located.path, f));
      if (!inside(located.path, source)) throw new Error('Manifest escapes repository');
      const p = JSON.parse(readFileSync(source, 'utf8')); return { path: f, packageManager: p.packageManager ?? null, node: p.engines?.node ?? null, scripts: Object.keys(p.scripts ?? {}) }; }
    catch { return { path: f, status: 'blocked', reason: 'Unreadable package manifest' }; }
  });
  let index = { status: 'not-run', indexedCommit: null };
  try {
    const source = realpathSync(join(located.path, '.repowise/state.json'));
    if (!inside(located.path, source)) throw new Error('Index state escapes repository');
    const s = JSON.parse(readFileSync(source, 'utf8')); const commit = s.last_sync_commit ?? null; index = { status: commit === state.head ? 'passed' : 'failed', indexedCommit: commit, dirtySource: state.dirty }; }
  catch { index = { status: 'blocked', indexedCommit: null, reason: 'Index state unavailable' }; }
  return { ...result, ...state, remote: identity, status: 'passed', observedAt: new Date().toISOString(), manifests: manifestPaths, packages,
    instructions: files.filter(f => /(^|\/)AGENTS\.md$/.test(f)),
    deploymentFiles: files.filter(f => /(^|\/)(\.do\/.*\.ya?ml|Dockerfile[^/]*|docker-compose[^/]*\.ya?ml|.*app\.prd\.yaml)$/.test(f)),
    dependencyFiles: files.filter(f => /(^|\/)(renovate\.[^/]+|dependabot\.ya?ml)$/.test(f)),
    repoWise: index, verification: { status: 'not-run', reason: 'Source inventory does not execute or certify product tests.' } };
}
export function collect(manifest, root = manifest.fleetRoot) {
  const common = new Set();
  const repositories = manifest.repos.map(row => {
    let r;
    try { r = inspect(manifest, row.id, root); } catch (e) { r = { id: row.id, status: 'blocked', reason: e.message }; }
    if (r.commonDirectory) {
      if (common.has(r.commonDirectory)) return { id: row.id, status: 'blocked', reason: 'Duplicate Git common directory' };
      common.add(r.commonDirectory);
    }
    return r;
  });
  return { schemaVersion: 1, recordType: 'inventory', observedAt: new Date().toISOString(), repositories, excluded: manifest.excluded, authority: 'working-tree inventory; product verification is separate' };
}
export function validateRecord(record) {
  if (record.schemaVersion !== 1 || !['finding','execution'].includes(record.recordType)) throw new Error('Unsupported evidence record');
  if (!/^[a-z0-9-]+$/.test(record.repo) || !/^[0-9a-f]{40}$/.test(record.head ?? '') || !statuses.includes(record.status)) throw new Error('Missing repository, exact SHA or disposition');
  if (record.recordType === 'finding' && (!record.evidence?.length || !record.workflow || !record.correction || !record.validation || !record.disposition || !['critical','high','medium','low'].includes(record.severity))) throw new Error('Incomplete finding');
  if (record.recordType === 'execution') {
    if (!Array.isArray(record.commands) || !record.review || !record.rollback || !record.branch || record.stage !== 'local') throw new Error('Incomplete local execution record');
    if (record.status === 'passed' && (!record.commands.length || record.commands.some(c => c.exitCode !== 0 || !c.command || !c.finishedAt) || record.review.status !== 'passed')) throw new Error('Passing execution requires successful commands and independent review');
  }
  return record;
}
export function assertEvidenceCurrent(record, manifest, root = manifest.fleetRoot) {
  validateRecord(record);
  const t = target(manifest, record.repo, root);
  if (t.missing) throw new Error('Checkout unavailable');
  const state = snapshot(t.path);
  const identity = inspect(manifest, record.repo, root);
  if (identity.status !== 'passed') throw new Error('Repository identity cannot be verified');
  if (state.head !== record.head || (record.branch && state.branch !== record.branch)) throw new Error('Stale evidence: source revision or branch changed');
  // A HEAD-only record cannot verify an uncommitted diff.
  if (state.dirty) throw new Error('Uncommitted work requires a separately reviewed diff; HEAD-only evidence is stale');
  return true;
}
export function writeReport(report, out) {
  const output = resolve(out);
  let ancestor = output;
  while (!existsSync(ancestor) && dirname(ancestor) !== ancestor) ancestor = dirname(ancestor);
  // Never place generated report data inside a Git checkout.
  const inGit = spawnSync('git', ['-C', realpathSync(ancestor), 'rev-parse', '--show-toplevel'], { encoding: 'utf8', windowsHide: true, timeout: 20000, env: { ...process.env, LC_ALL: 'C', LANG: 'C' } });
  if (inGit.status === 0) throw new Error('Reports must be outside repositories');
  if (inGit.error || inGit.status !== 128 || !/^fatal: not a git repository \(or any of the parent directories\): \.git\s*$/.test(inGit.stderr.trim())) throw new Error('Cannot establish report destination is outside repositories');
  mkdirSync(output, { recursive: true });
  const atomicWrite = (name, content) => {
    const destination = join(output, name);
    try {
      const stat = lstatSync(destination);
      if (!stat.isFile() || stat.nlink !== 1) throw new Error('Report file must be an ordinary unlinked file');
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    const temporary = join(output, `.${name}.${randomUUID()}.tmp`);
    try {
      writeFileSync(temporary, content, { flag: 'wx' });
      // Rename replaces the directory entry, never follows an existing link.
      renameSync(temporary, destination);
    } finally { rmSync(temporary, { force: true }); }
  };
  atomicWrite('inventory.json', JSON.stringify(report, null, 2) + '\n');
  const lines = ['# Portfolio baseline', '', `Observed: ${report.observedAt}`, '', 'Inventory success is not application verification.', '', '| Repository | Inventory | Branch | Dirty | RepoWise | Product checks |', '|---|---|---|---|---|---|'];
  for (const r of report.repositories) lines.push(`| ${r.id} | ${r.status} | ${(r.branch ?? 'unknown').replaceAll('|','/')} | ${r.dirty ?? 'unknown'} | ${r.repoWise?.status ?? 'not-run'} | not-run |`);
  atomicWrite('README.md', lines.join('\n') + '\n');
}
export function main(args) {
  const [action, ...rest] = args;
  const manifest = loadManifest();
  if (action === 'inventory' && rest.length === 0) { process.stdout.write(JSON.stringify(collect(manifest), null, 2) + '\n'); return; }
  if (action === 'report' && rest.length === 1) { writeReport(collect(manifest), rest[0]); return; }
  if (action === 'validate-record' && rest.length === 1) { assertEvidenceCurrent(JSON.parse(readFileSync(rest[0], 'utf8')), manifest); return; }
  throw new Error('Usage: portfolio.mjs inventory | report <external-directory> | validate-record <file>');
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { main(process.argv.slice(2)); } catch (e) { console.error(e.message); process.exitCode = 1; }
}
