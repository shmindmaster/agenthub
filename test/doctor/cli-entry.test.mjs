// The npm package ships doctor only. Every PowerShell-engine command must
// fail fast with a clone hint there, and in a clone without pwsh it must exit
// with a clear error. Each case runs with stdin closed under a hard timeout,
// so a hang fails the test instead of stalling it.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const TIMEOUT_MS = 15000;
const dirs = [];
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

/** A copy of exactly what `npm pack` ships, per package.json "files". */
function packageShapedCopy() {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-pkg-'));
  dirs.push(root);
  const pkg = JSON.parse(readFileSync(join(repoRoot, 'package.json'), 'utf8'));
  for (const entry of [...pkg.files, 'package.json']) {
    cpSync(join(repoRoot, entry), join(root, entry), { recursive: true });
  }
  return root;
}

function runCli(root, args, env) {
  const started = Date.now();
  const result = spawnSync(process.execPath, [join(root, 'scripts', 'agenthub-cli.mjs'), ...args], {
    cwd: root,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
    timeout: TIMEOUT_MS,
  });
  return { ...result, ms: Date.now() - started };
}

const emptyPath = () => {
  const bin = mkdtempSync(join(tmpdir(), 'agenthub-nopath-'));
  dirs.push(bin);
  return { PATH: bin, SystemRoot: process.env.SystemRoot ?? '' };
};

test('the npm package does not ship the PowerShell engine', () => {
  const pkg = JSON.parse(readFileSync(join(repoRoot, 'package.json'), 'utf8'));
  assert.equal(pkg.private, undefined);
  assert.equal(pkg.name, 'agenthub');
  assert.equal(pkg.version, '0.1.0');
  assert.ok(!pkg.files.some((f) => /AgentHub\.ps1|^scripts\/$/.test(f)));
});

for (const command of ['sync', 'sync --apply', 'validate', 'init', 'drift', 'inventory', 'export out']) {
  test(`'agenthub ${command}' from the npm package exits 1 at once with a clone hint`, () => {
    const root = packageShapedCopy();
    const r = runCli(root, command.split(' '), emptyPath());
    assert.equal(r.error, undefined, `did not exit within ${TIMEOUT_MS} ms`);
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, /git clone https:\/\/github\.com\/shmindmaster\/agenthub/);
    assert.match(r.stderr, /'agenthub doctor' works from anywhere/);
  });
}

test('an unknown command exits 2 instead of pointing at the sync engine', () => {
  const r = runCli(packageShapedCopy(), ['frobnicate'], emptyPath());
  assert.equal(r.status, 2);
  assert.match(r.stderr, /Unknown command 'frobnicate'/);
});

test('doctor runs from the npm package with no PowerShell on PATH', () => {
  const root = packageShapedCopy();
  const home = mkdtempSync(join(tmpdir(), 'agenthub-home-'));
  dirs.push(home);
  const r = runCli(root, ['doctor', '--home', home, '--json'], emptyPath());
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(r.stdout).readOnly, true);
});

test('in a clone without pwsh, sync exits 127 at once with an install hint', () => {
  const root = packageShapedCopy();
  writeFileSync(join(root, 'scripts', 'AgentHub.ps1'), '# stub engine\n');
  const r = runCli(root, ['sync'], emptyPath());
  assert.equal(r.error, undefined, `did not exit within ${TIMEOUT_MS} ms`);
  assert.equal(r.status, 127, r.stderr);
  assert.match(r.stderr, /Install PowerShell 7\+/);
});

test('the engine is launched non-interactively, so a prompt cannot wait on stdin', { skip: process.platform === 'win32' && 'needs a POSIX shell stub for pwsh' }, () => {
  const root = packageShapedCopy();
  writeFileSync(join(root, 'scripts', 'AgentHub.ps1'), '# stub engine\n');
  const bin = mkdtempSync(join(tmpdir(), 'agenthub-fakepwsh-'));
  dirs.push(bin);
  mkdirSync(bin, { recursive: true });
  const stub = join(bin, 'pwsh');
  writeFileSync(stub, '#!/bin/sh\necho "ARGS: $*"\nexit 0\n');
  chmodSync(stub, 0o755);
  const r = runCli(root, ['sync'], { PATH: `${bin}:/usr/bin:/bin` });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^ARGS: -NonInteractive -NoProfile -File .*AgentHub\.ps1 sync$/m);
});
