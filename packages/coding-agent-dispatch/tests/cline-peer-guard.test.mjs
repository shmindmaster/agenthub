import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, existsSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';
import test from 'node:test';

const skill = fileURLToPath(new URL('../skills/use-coding-agent/', import.meta.url));
const source = readFileSync(join(skill, 'cline/peer-guard.js'), 'utf8');

function makePlugin() {
  const context = vm.createContext({ process: { env: { ...process.env } } });
  vm.runInContext(source.replace('export default', 'globalThis.plugin ='), context);
  return context.plugin;
}

const run = (c) => plugin.hooks.beforeTool({ tool: { name: 'run_commands' }, input: { commands: [c] } });

const ed = (path) => plugin.hooks.beforeTool({ tool: { name: 'editor' }, input: { path, new_text: 'x' } });
const rd = (paths) => plugin.hooks.beforeTool({ tool: { name: 'read_files' }, input: { paths } });
const pt = (input) => plugin.hooks.beforeTool({ tool: { name: 'apply_patch' }, input });

let plugin;
// Setup: create plugin with AGENTHUB_PEER_GUARD=1
test.beforeEach(() => {
  process.env.AGENTHUB_PEER_GUARD = '1';
  plugin = makePlugin();
});

test.afterEach(() => {
  delete process.env.AGENTHUB_PEER_GUARD;
});

const block = [
  'git push origin main',
  'git -C x push',
  'git reset --hard HEAD~1',
  'git clean -fdx',
  'git branch -D feat',
  'gh pr create --fill',
  'gh api repos/a/b/issues -f title=x',
  'gh auth token',
  'npm publish',
  'railway up',
  'az group list',
  'schtasks /create /tn x /tr y',
  'Register-ScheduledTask -TaskName x',
  'cline schedule create',
  'printenv',
  'Get-ChildItem env:',
  'rm -rf /',
  'Remove-Item -Recurse -Force C:\\\\',
  'cat .env',
  'type C:\\\\Users\\\\x\\\\.cline\\\\data\\\\settings\\\\providers.json',
  'cd repo && git push',
];

const allow = [
  'git status',
  'git commit -m "push docs"',
  'git branch -d merged',
  'gh pr view 81',
  'gh pr diff 81',
  'gh api repos/a/b/pulls',
  'npm test',
  'python test_interval.py',
  'pwsh -File tests/Run-AllTests.ps1',
  'git log --oneline',
  'Remove-Item -Recurse -Force .\\build',
  'git branch feature',
  'pnpm run build',
  'npx playwright test',
  'git worktree list',
];
test('every deny rule has at least one blocked case', () => {
  for (const c of block) {
    const r = run(c);
    if (!r?.skip) {
      console.log('NOT BLOCKED:', c);
      assert.fail(`Expected blocked: ${c}`);
    }
  }
});

test('at least 15 realistic allowed developer commands are NOT blocked', () => {
  for (const c of allow) {
    const r = run(c);
    if (r?.skip) {
      console.log('WRONGLY BLOCKED:', c, r.reason);
      assert.fail(`Expected allowed: ${c}`);
    }
  }
});

test('editor/apply_patch/read_files path rules', () => {
  // D:\Local-AI (not cache/temp) should be blocked
  assert.ok(ed('D:\\\\Local-AI\\\\runtime\\\\x.ps1')?.skip, 'editor Local-AI not blocked');
  assert.ok(pt({ input: '*** Begin Patch\\n*** Update File: D:\\\\Local-AI\\\\ai.ps1\\n' })?.skip, 'patch Local-AI not blocked');

  // D:\Local-AI\cache\temp\... should NOT be blocked (scratch area)
  assert.equal(ed('D:\\\\Local-AI\\\\cache\\\\temp\\\\x\\\\a.py')?.skip, undefined, 'scratch wrongly blocked');
  assert.equal(pt({ input: '*** Begin Patch\\n*** Update File: D:\\\\Local-AI\\\\cache\\\\temp\\\\x\\\\a.py\\n' })?.skip, undefined, 'patch scratch wrongly blocked');

  // C:\wt\repo\task\... should NOT be blocked (worktree)
  assert.equal(ed('C:\\\\wt\\\\repo\\\\task\\\\src\\\\a.ts')?.skip, undefined, 'wt wrongly blocked');
  assert.equal(pt({ input: '*** Begin Patch\\n*** Update File: C:\\\\wt\\\\repo\\\\task\\\\src\\\\a.ts\\n' })?.skip, undefined, 'patch wt wrongly blocked');

  // .env read should be blocked
  assert.ok(rd(['C:\\\\r\\\\.env'])?.skip, '.env read not blocked');

  // .env.example read is conservative (may be blocked)
  const envExample = rd(['C:\\\\r\\\\.env.example']);
  if (envExample?.skip) console.log('note: .env.example blocked (conservative)');
});

test('guard is a no-op when AGENTHUB_PEER_GUARD is unset', () => {
  delete process.env.AGENTHUB_PEER_GUARD;
  plugin = makePlugin();
  for (const c of block) {
    const r = run(c);
    assert.equal(r?.skip, undefined, `Should not block when guard disabled: ${c}`);
  }
  process.env.AGENTHUB_PEER_GUARD = '1';
  plugin = makePlugin();
});

test('malformed inputs (missing input, commands as objects) never throw', () => {
  assert.doesNotThrow(() => plugin.hooks.beforeTool({ tool: { name: 'run_commands' }, input: {} }));
  assert.doesNotThrow(() => plugin.hooks.beforeTool({ tool: { name: 'run_commands' }, input: { commands: [{ command: 'git push' }] } }));
  assert.doesNotThrow(() => plugin.hooks.beforeTool({ tool: { name: 'run_commands' }, input: { command: 'git push' } }));
  assert.doesNotThrow(() => plugin.hooks.beforeTool({ tool: { name: 'editor' }, input: {} }));
  assert.doesNotThrow(() => plugin.hooks.beforeTool({ tool: { name: 'read_files' }, input: {} }));
  assert.doesNotThrow(() => plugin.hooks.beforeTool({ tool: { name: 'apply_patch' }, input: {} }));
});

test('manual installer detects missing and changed files, repairs and reads back without host startup', () => {
  const home = mkdtempSync(join(tmpdir(), 'cline-peer-guard-fixture-'));
  const destination = join(home, 'plugins/peer-guard.js');
  const installerPath = join(skill, 'Install-ClinePeerGuard.ps1');
  const runInstaller = (...args) => spawnSync('pwsh', ['-NoProfile', '-File', installerPath, '-ClineHome', home, ...args], { encoding: 'utf8', windowsHide: true });

  try {
    // Audit (no -Apply): missing file
    let result = runInstaller();
    assert.equal(result.status, 1, 'Audit must fail when missing');
    assert.equal(existsSync(destination), false, 'Audit must not write');

    // Apply: install
    result = runInstaller('-Apply');
    assert.equal(result.status, 0, 'Apply must succeed');
    assert.equal(readFileSync(destination, 'utf8'), source, 'Installed file must match source');

    // Audit again: current
    result = runInstaller();
    assert.equal(result.status, 0, 'Audit must pass when current');

    // Drift: modify the file
    writeFileSync(destination, '// synthetic incompatible update\n');
    result = runInstaller();
    assert.equal(result.status, 1, 'Audit must fail on real drift');

    // Apply again: repair
    result = runInstaller('-Apply');
    assert.equal(result.status, 0, 'Apply must succeed on repair');
    assert.equal(readFileSync(destination, 'utf8'), source, 'Repaired file must match source');
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});