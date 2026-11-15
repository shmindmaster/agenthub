#!/usr/bin/env node
// Offline, read-only repository health scan. Lists tracked files with git and
// reports measurable quality signals. Never prints file contents or secrets.
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { join, dirname, basename, extname } from 'node:path';

export const SOURCE_EXT = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.py', '.ps1', '.cs', '.go', '.kt', '.swift', '.dart', '.java', '.rb', '.php', '.rs']);
export const EXCLUDE = /(^|\/)(node_modules|dist|build|out|vendor|generated|__generated__|coverage|\.next|migrations|alembic\/versions|__snapshots__|fixtures)(\/|$)|\.min\.|\.d\.ts$|(^|\/)[^/]*lock[^/]*$/i;
export const WARN_LINES = 800;
export const FAIL_LINES = 1500;
const MARKER = /\b(TODO|FIXME|HACK|XXX)\b/g;
const SECRET = /(AKIA[0-9A-Z]{16}|sk_live_[0-9a-zA-Z]{20,}|ghp_[0-9A-Za-z]{30,}|-----BEGIN (RSA |EC )?PRIVATE KEY-----|xox[baprs]-[0-9A-Za-z-]{10,})/;
const TEST_NAME = /(^|\/)(tests?|__tests__|spec|e2e)(\/|$)|[._-](test|spec)\.[a-z]+$|^test_.*\.py$/i;

export function isSource(path) {
  return SOURCE_EXT.has(extname(path).toLowerCase()) && !EXCLUDE.test(path);
}

export function isTest(path) {
  return TEST_NAME.test(path) || TEST_NAME.test(basename(path));
}

export function detectStacks(files) {
  const has = (re) => files.some((f) => re.test(f));
  return {
    node: has(/(^|\/)package\.json$/),
    typescript: has(/(^|\/)tsconfig[^/]*\.json$/),
    python: has(/(^|\/)(pyproject\.toml|setup\.py|requirements[^/]*\.txt)$/),
    powershell: has(/\.ps1$/),
  };
}

export function missingConfigs(files, stacks, readText) {
  const missing = [];
  const has = (re) => files.some((f) => re.test(f));
  const pyproject = files.filter((f) => /(^|\/)pyproject\.toml$/.test(f)).map(readText).join('\n');
  if (stacks.node && !has(/(^|\/)(eslint\.config\.[cm]?[jt]s|\.eslintrc[^/]*|biome\.jsonc?|oxlint[^/]*\.json)$/)) missing.push('JS/TS linter (eslint, biome or oxlint)');
  if (stacks.node && !has(/(^|\/)(\.prettierrc[^/]*|prettier\.config\.[cm]?js|biome\.jsonc?|\.editorconfig)$/)) missing.push('JS/TS formatter (prettier, biome or editorconfig)');
  if (stacks.python && !(has(/(^|\/)(ruff\.toml|\.ruff\.toml|\.flake8|setup\.cfg)$/) || /\[tool\.ruff/.test(pyproject))) missing.push('Python linter (ruff)');
  if (stacks.python && !(has(/(^|\/)(mypy\.ini|pyrightconfig\.json)$/) || /\[tool\.(mypy|pyright)/.test(pyproject))) missing.push('Python type checker (mypy or pyright)');
  if (stacks.powershell && !has(/PSScriptAnalyzerSettings\.psd1$/)) missing.push('PowerShell analyzer settings (PSScriptAnalyzer)');
  return missing;
}

export function untestedDirs(sourceFiles, testFiles) {
  const testText = testFiles.join('\n').toLowerCase();
  const dirs = new Map();
  for (const f of sourceFiles) {
    if (isTest(f)) continue;
    const d = dirname(f);
    dirs.set(d, (dirs.get(d) || 0) + 1);
  }
  const out = [];
  for (const [d, count] of dirs) {
    if (count < 3) continue;
    const leaf = basename(d).toLowerCase();
    const near = testFiles.some((t) => dirname(t).startsWith(d)) || (leaf.length > 2 && testText.includes(leaf));
    if (!near) out.push({ dir: d, files: count });
  }
  return out.sort((a, b) => b.files - a.files);
}

export function scan(root, listFiles = defaultList, readText = (p) => readFileSync(join(root, p), 'utf8')) {
  const files = listFiles(root);
  const sources = files.filter(isSource);
  const tests = sources.filter(isTest);
  const large = [];
  let markers = 0;
  const secretHits = [];
  for (const f of sources) {
    let text;
    try { text = readText(f); } catch { continue; }
    const lines = text.split('\n').length;
    if (lines >= WARN_LINES && !isTest(f)) large.push({ file: f, lines, level: lines >= FAIL_LINES ? 'fail' : 'warn' });
    markers += (text.match(MARKER) || []).length;
    if (SECRET.test(text)) secretHits.push(f);
  }
  const envFiles = files.filter((f) => /(^|\/)\.env(\.[a-z]+)?$/i.test(f) && !/\.(example|sample|template)$/i.test(f));
  const stacks = detectStacks(files);
  return {
    root,
    sourceFiles: sources.length,
    testFiles: tests.length,
    largeFiles: large.sort((a, b) => b.lines - a.lines),
    overFail: large.filter((l) => l.level === 'fail').length,
    overWarn: large.length,
    markers,
    stacks,
    missingConfigs: missingConfigs(files, stacks, (p) => { try { return readText(p); } catch { return ''; } }),
    untestedDirs: untestedDirs(sources, tests).slice(0, 15),
    committedEnvFiles: envFiles,
    secretShapedFiles: secretHits,
  };
}

function defaultList(root) {
  const out = execFileSync('git', ['-C', root, 'ls-files', '-z'], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, windowsHide: true });
  return out.split('\0').filter(Boolean).filter((f) => { try { return statSync(join(root, f)).size < 5 * 1024 * 1024; } catch { return false; } });
}

function report(r) {
  const lines = [`# Scan: ${r.root}`, '', `Source files ${r.sourceFiles}, test files ${r.testFiles}, over ${WARN_LINES} lines ${r.overWarn}, over ${FAIL_LINES} lines ${r.overFail}, TODO/FIXME/HACK ${r.markers}.`, ''];
  if (r.secretShapedFiles.length || r.committedEnvFiles.length) lines.push('## High', ...r.secretShapedFiles.map((f) => `- secret-shaped string in ${f} (value not printed)`), ...r.committedEnvFiles.map((f) => `- committed env file ${f}`), '');
  if (r.missingConfigs.length) lines.push('## Missing tooling', ...r.missingConfigs.map((m) => `- ${m}`), '');
  if (r.largeFiles.length) lines.push('## Large files', ...r.largeFiles.slice(0, 25).map((l) => `- ${l.level} ${l.lines} ${l.file}`), '');
  if (r.untestedDirs.length) lines.push('## Directories with no nearby tests', ...r.untestedDirs.map((u) => `- ${u.dir} (${u.files} files)`), '');
  return lines.join('\n');
}

const invoked = process.argv[1] && import.meta.url.endsWith(basename(process.argv[1]));
if (invoked) {
  const args = process.argv.slice(2);
  const root = args.find((a) => !a.startsWith('--'));
  if (!root || !existsSync(root)) { console.error('usage: scan-repo.mjs <repo-path> [--json]'); process.exit(2); }
  const r = scan(root);
  console.log(args.includes('--json') ? JSON.stringify(r, null, 2) : report(r));
}
