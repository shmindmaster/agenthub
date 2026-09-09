import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const hook = fileURLToPath(new URL('../hooks/pre-push', import.meta.url));
const scanner = fileURLToPath(new URL('./check-config-payloads.mjs', import.meta.url));
const shell = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'sh';
function git(cwd, ...args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', windowsHide: true });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
}
function fixture(t, installed = true) {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-hook-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const repo = join(root, 'repos', 'app');
  mkdirSync(repo, { recursive: true });
  git(repo, 'init', '-b', 'main');
  writeFileSync(join(repo, 'vite.config.js'), 'export default {};\n');
  git(repo, 'add', '.');
  git(repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture');
  if (installed) {
    const dest = join(root, 'repos', 'agenthub', 'packages', 'security', 'scripts');
    mkdirSync(dest, { recursive: true });
    copyFileSync(scanner, join(dest, 'check-config-payloads.mjs'));
  }
  return { root, repo, sha: git(repo, 'rev-parse', 'HEAD') };
}
function run(repo, sha, overrides = {}) {
  const env = { ...process.env, ...overrides };
  if (!Object.hasOwn(overrides, 'AGENTHUB_HOME')) delete env.AGENTHUB_HOME;
  return spawnSync(shell, [hook.replaceAll('\\', '/')], {
    cwd: repo, env, encoding: 'utf8', windowsHide: true,
    input: `refs/heads/main ${sha} refs/heads/main ${'0'.repeat(40)}\n`,
  });
}
test('required scanner absence blocks a push', t => {
  const f = fixture(t, false); const r = run(f.repo, f.sha);
  assert.notEqual(r.status, 0); assert.match(r.stderr, /Push blocked/);
});
test('normal checkout and linked worktree resolve the same canonical scanner', t => {
  const f = fixture(t);
  assert.equal(run(f.repo, f.sha).status, 0);
  const wt = join(f.root, 'wt', 'app', 'task');
  git(f.repo, 'worktree', 'add', '--detach', wt);
  const r = run(wt, f.sha); assert.equal(r.status, 0, r.stderr);
});
test('explicit unavailable owner path fails instead of silently falling back', t => {
  const f = fixture(t); const r = run(f.repo, f.sha, { AGENTHUB_HOME: join(f.root, 'missing') });
  assert.notEqual(r.status, 0); assert.match(r.stderr, /Push blocked/);
});
test('scan uses the pushed commit, not a clean working copy', t => {
  const f = fixture(t);
  writeFileSync(join(f.repo, 'vite.config.js'), "global['!']='payload';\n");
  git(f.repo, 'add', '.');
  git(f.repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'bad config');
  writeFileSync(join(f.repo, 'vite.config.js'), 'export default {};\n');
  assert.notEqual(run(f.repo, git(f.repo, 'rev-parse', 'HEAD')).status, 0);
});
test('invalid archive revision blocks the push', t => {
  const f = fixture(t); assert.notEqual(run(f.repo, 'f'.repeat(40)).status, 0);
});
test('export-ignore cannot hide a committed malicious config', t => {
  const f=fixture(t);
  writeFileSync(join(f.repo,'.gitattributes'),'vite.config.js export-ignore\n');
  writeFileSync(join(f.repo,'vite.config.js'),"global['!']='payload';\n");
  git(f.repo,'add','.'); git(f.repo,'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-m','ignored payload');
  assert.notEqual(run(f.repo,git(f.repo,'rev-parse','HEAD')).status,0);
});
test('original ref-reading pre-push receives input and its failure propagates', t => {
  const f=fixture(t); const original=join(f.repo,'.git','hooks','pre-push.original');
  writeFileSync(original,'#!/bin/sh\nread local_ref local_sha remote_ref remote_sha\n[ "$local_ref" = "refs/heads/main" ] || exit 0\nexit 17\n');
  chmodSync(original,0o755);
  assert.notEqual(run(f.repo,f.sha).status,0);
});
