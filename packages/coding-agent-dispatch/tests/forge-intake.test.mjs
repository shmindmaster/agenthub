import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import {
  GIT_ENV, GIT_SAFE, denyPaths, gitFingerprint, isProtected, parseRawModes, permissionArgs, redact, validIssueId, countToday,
  acquireLock, lockState, coolingRoutes, isProviderLimit, summarize, branchName, checkDiff, failedAttempts, finishPrompt, implementPrompt, inspectWorktree, isEligible, isMainModule, linearArgs, loadConfig, parseAgentJson, pickRoute, preClaimLabels, repoFor, runsToday, selectPrompt, skipList, slugify,
} from '../skills/dispatch/forge-intake.mjs';

const config = loadConfig(join(fileURLToPath(new URL('../skills/dispatch/', import.meta.url)), 'forge-intake.json'));
const repo = config.repos['app:agenthub'];
const bug = { state: 'Backlog', labels: ['from-execution', 'app:agenthub', 'type:bug'] };

test('config enables the plan routes that passed execution smokes and a repo allowlist', () => {
  assert.deepEqual(config.routes.filter((r) => r.enabled).map((r) => r.id), ['codex-zai', 'codex-qwen', 'codex-go']);
  assert.ok(config.routes.every((r) => r.launcher.startsWith('.local/bin/codex-')), 'unattended routes are Codex launchers only');
  assert.deepEqual(Object.keys(config.repos), ['app:agenthub']);
  assert.equal(config.linear.claimLabel, 'agent:forge');
});

test('eligibility accepts a small unclaimed bug and refuses the rest', () => {
  assert.equal(isEligible(bug, config.linear), null);
  assert.equal(isEligible({ ...bug, state: 'Done' }, config.linear), 'state');
  assert.equal(isEligible({ ...bug, state: 'In Progress' }, config.linear), 'state');
  assert.equal(isEligible({ state: 'Todo', labels: ['app:agenthub', 'priority:now'] }, config.linear), 'no include label');
  for (const extra of ['agent:codex', 'type:epic', 'attention:owner', 'risk:compliance', 'risk:security', 'stage:submitted', 'lane:career', 'funding:active']) {
    assert.equal(isEligible({ ...bug, labels: [...bug.labels, extra] }, config.linear), 'excluded label', extra);
  }
});

test('only a mapped app label yields a repository', () => {
  assert.equal(repoFor(bug.labels, config).repo, 'shmindmaster/agenthub');
  assert.equal(repoFor(['app:abacare', 'type:bug'], config), null);
  assert.equal(repoFor(['app:pendoah', 'type:bug'], config), null);
});

test('branch names are short, lowercase and carry the issue id', () => {
  assert.equal(slugify('[AgentHub] check-config-payloads.mjs filesystem pass skips symlinked configs (scan bypass)'), 'check-config-payloads-mjs-filesystem-pas');
  assert.match(branchName('SH-4512', '[AgentHub] Fix it!'), /^forge\/sh-4512-fix-it$/);
  assert.ok(branchName('SH-1', 'x'.repeat(200)).length < 60);
});

test('agent replies parse from prose and fences, and reject non-JSON', () => {
  assert.deepEqual(parseAgentJson('Done.\n```json\n{"outcome":"none","reason":"empty"}\n```'), { outcome: 'none', reason: 'empty' });
  assert.deepEqual(parseAgentJson('{"a":{"b":1}} trailing'), { a: { b: 1 } });
  assert.equal(parseAgentJson('no json here'), null);
});

test('daily cap counts claimed runs for today only', () => {
  const now = '2026-11-12T10:00:00.000Z';
  const ledger = [
    { ts: '2026-11-11T23:00:00.000Z', phase: 'run', issue: 'SH-1', outcome: 'pr', route: 'codex-zai' },
    { ts: '2026-11-12T01:00:00.000Z', phase: 'run', issue: 'SH-2', outcome: 'failed', route: 'codex-zai' },
    { ts: '2026-11-12T02:00:00.000Z', phase: 'other' },
  ];
  assert.equal(runsToday(ledger, now), 1);
});

test('an issue is skipped after a PR or too many failures', () => {
  const ledger = [
    { phase: 'run', issue: 'SH-1', outcome: 'pr' },
    { phase: 'run', issue: 'SH-2', outcome: 'failed' },
    { phase: 'run', issue: 'SH-3', outcome: 'failed' }, { phase: 'run', issue: 'SH-3', outcome: 'failed' },
  ];
  assert.equal(failedAttempts(ledger, 'SH-3'), 2);
  assert.deepEqual(skipList(ledger, config).sort(), ['SH-1', 'SH-3']);
});

test('route rotation picks the least recently used enabled plan', () => {
  const two = { ...config, routes: config.routes.map((r) => ({ ...r, enabled: ['codex-zai', 'codex-qwen'].includes(r.id) })) };
  assert.equal(pickRoute(two, []).id, 'codex-zai');
  assert.equal(pickRoute(two, [{ phase: 'run', route: 'codex-zai' }]).id, 'codex-qwen');
  assert.equal(pickRoute(two, [{ phase: 'run', route: 'codex-zai' }, { phase: 'run', route: 'codex-qwen' }]).id, 'codex-zai');
  assert.equal(pickRoute({ ...config, routes: [] }, []), null);
});

test('a plan at its limit cools down and is not charged to the issue', () => {
  assert.equal(isProviderLimit('ERROR: rate limit exceeded: Usage limit reached for 5 hour. Your limit will reset at 19:25'), true);
  assert.equal(isProviderLimit("ERROR: You've reached your additional usage limit for your plan"), true);
  assert.equal(isProviderLimit('ERROR: 429 Too Many Requests'), true);
  assert.equal(isProviderLimit('SyntaxError: unexpected token'), false);
  assert.equal(isProviderLimit('user\nthis issue is about quota and rate limit handling'), false, 'echoed issue text is not a provider error');
  const now = '2026-11-12T12:00:00.000Z';
  const ledger = [
    { phase: 'run', route: 'codex-qwen' }, { phase: 'run', route: 'codex-go' },
    { phase: 'cooldown', route: 'codex-zai', until: '2026-11-12T13:00:00.000Z' },
    { phase: 'cooldown', route: 'codex-go', until: '2026-11-12T11:00:00.000Z' },
  ];
  assert.deepEqual([...coolingRoutes(ledger, now)], ['codex-zai']);
  assert.equal(pickRoute(config, ledger, now).id, 'codex-qwen', 'zai is cooling; qwen was used before go');
  const allCooling = config.routes.filter((r) => r.enabled).map((r) => ({ phase: 'cooldown', route: r.id, until: '2026-11-12T13:00:00.000Z' }));
  assert.equal(pickRoute(config, allCooling, now), null);
  const failures = [{ phase: 'run', issue: 'SH-7', outcome: 'limited' }, { phase: 'run', issue: 'SH-7', outcome: 'limited' }, { phase: 'run', issue: 'SH-7', outcome: 'limited' }];
  assert.equal(failedAttempts(failures, 'SH-7'), 0);
  assert.deepEqual(skipList(failures, config), []);
});

test('diff gate refuses protected paths, secrets, empty and oversized changes', () => {
  const ok = { files: ['packages/security/scripts/a.mjs'], addedLines: ['+const a = 1;'], numstat: [[10, 2]] };
  assert.deepEqual(checkDiff(ok, repo, config.limits), []);
  assert.match(checkDiff({ ...ok, files: ['.github/workflows/ci.yml'] }, repo, config.limits).join(), /protected path/);
  assert.match(checkDiff({ ...ok, files: ['config/.env.local'] }, repo, config.limits).join(), /secret-shaped path/);
  assert.match(checkDiff({ ...ok, addedLines: [`+token = ghp_${'a'.repeat(30)}`] }, repo, config.limits).join(), /secret-shaped content/);
  assert.match(checkDiff({ ...ok, files: [] }, repo, config.limits).join(), /no changed files/);
  assert.match(checkDiff({ ...ok, numstat: [[config.limits.maxChangedLines + 1, 0]] }, repo, config.limits).join(), /changed lines/);
  assert.match(checkDiff({ ...ok, files: Array.from({ length: config.limits.maxFiles + 1 }, (_, i) => `f${i}`) }, repo, config.limits).join(), /files exceeds/);
});

test('each phase gets a Linear tool allowlist, and only select and finish can write', () => {
  const writes = (phase) => config.linear.toolsByPhase[phase].some((t) => t.startsWith('save_') || t.startsWith('create_'));
  assert.equal(writes('select'), true);
  assert.equal(writes('finish'), true);
  assert.equal(writes('implement'), false);
  for (const phase of Object.keys(config.linear.toolsByPhase)) assert.ok(!config.linear.toolsByPhase[phase].some((t) => /^(delete|merge|unshare)/.test(t)));
  const args = linearArgs(config.linear, 'implement');
  assert.equal(args[0], '-c');
  assert.match(args[1], /^mcp_servers\.linear\.url="https:\/\/mcp\.linear\.app\/mcp"$/);
  assert.match(args[3], /^mcp_servers\.linear\.enabled_tools=\["get_issue","list_comments"\]$/);
  assert.equal(args.length, 4, 'a read-only phase approves nothing');
  const select = linearArgs(config.linear, 'select').filter((a) => a !== '-c');
  assert.ok(select.includes('mcp_servers.linear.tools.save_issue.approval_mode="approve"'));
  assert.ok(!select.some((a) => a.includes('.tools.get_issue.')));
});

test('a retry gets a new branch and the claim label is not evidence against eligibility', () => {
  assert.equal(branchName('SH-9', 'Fix it'), 'forge/sh-9-fix-it');
  assert.equal(branchName('SH-9', 'Fix it', 2), 'forge/sh-9-fix-it-r2');
  const labels = preClaimLabels([...bug.labels, 'agent:forge'], config.linear);
  assert.deepEqual(labels, bug.labels);
  assert.equal(isEligible({ state: 'Backlog', labels }, config.linear), null);
  assert.equal(isEligible({ state: 'Backlog', labels: [...bug.labels, 'agent:forge'] }, config.linear), 'excluded label');
  assert.deepEqual(preClaimLabels(undefined, config.linear), []);
});

test('the entry point guard works through a symlinked install path', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'intake-main-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const real = join(dir, 'real.mjs'); writeFileSync(real, '');
  const link = join(dir, 'current.mjs');
  try { symlinkSync(real, link); } catch { t.skip('symlinks unavailable on this runner'); return; }
  assert.equal(isMainModule(pathToFileURL(real).href, link), true);
  assert.equal(isMainModule(pathToFileURL(real).href, real), true);
  assert.equal(isMainModule(pathToFileURL(real).href, join(dir, 'other.mjs')), false);
  assert.equal(isMainModule(pathToFileURL(real).href, undefined), false);
});

test('protected paths hold even for non-ASCII file names that git would quote', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'intake-git-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const g = (...args) => assert.equal(spawnSync('git', args, { cwd: dir }).status, 0, args.join(' '));
  g('init', '-q', '-b', 'main'); g('config', 'user.email', 't@example.invalid'); g('config', 'user.name', 't');
  writeFileSync(join(dir, 'a.txt'), 'a\n'); g('add', '-A'); g('commit', '-q', '-m', 'base');
  g('update-ref', 'refs/remotes/origin/main', 'HEAD');
  mkdirSync(join(dir, '.github/workflows'), { recursive: true });
  writeFileSync(join(dir, '.github/workflows/café.yml'), 'on: push\n'); g('add', '-A'); g('commit', '-q', '-m', 'change');
  const seen = inspectWorktree(dir, repo);
  assert.deepEqual(seen.files, ['.github/workflows/café.yml']);
  assert.match(checkDiff(seen, repo, config.limits).join(), /protected path/);
});

test('the single-run lock is atomic and recovers from a dead holder', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'intake-lock-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const lock = join(dir, 'lock');
  assert.equal(acquireLock(lock), true);
  assert.equal(acquireLock(lock), false, 'a live holder (this process) blocks a second run');
  rmSync(lock);
  writeFileSync(lock, '2147483646');
  assert.equal(acquireLock(lock), true, 'a dead holder is taken over');
});

test('the status report names a live lock holder and flags a stale one', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'intake-lockstate-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const lock = join(dir, 'lock');
  assert.deepEqual(lockState(lock), { lockHeldBy: null, staleLock: null }, 'no lock file');
  writeFileSync(lock, `${process.pid}\n`);
  assert.deepEqual(lockState(lock), { lockHeldBy: process.pid, staleLock: null }, 'a live holder is reported as a number');
  writeFileSync(lock, '2147483646\n');
  assert.deepEqual(lockState(lock), { lockHeldBy: null, staleLock: 2147483646 }, 'a dead holder is stale, not held');
  writeFileSync(lock, 'garbage');
  assert.deepEqual(lockState(lock), { lockHeldBy: null, staleLock: 'unreadable' }, 'an unreadable lock is stale');
});

test('the status report counts runs, PRs, failures, retired issues and routes', () => {
  const ledger = [
    { ts: '2026-11-12T01:00:00.000Z', phase: 'run', issue: 'SH-1', outcome: 'pr', route: 'codex-zai', pr: 'https://x/pull/1', linearClosed: true },
    { ts: '2026-11-12T02:00:00.000Z', phase: 'run', issue: 'SH-2', outcome: 'failed', route: 'codex-zai', reason: 'r', linearClosed: false },
    { ts: '2026-11-12T03:00:00.000Z', phase: 'run', issue: 'SH-2', outcome: 'failed', route: 'codex-zai', linearClosed: true },
  ];
  const s = summarize(ledger, config, '2026-11-12T12:00:00.000Z');
  assert.equal(s.runsToday, 3);
  assert.equal(s.dailyCap, config.limits.maxRunsPerDay);
  assert.deepEqual(s.draftPrs, [{ issue: 'SH-1', pr: 'https://x/pull/1' }]);
  assert.equal(s.failed, 2);
  assert.deepEqual(s.linearCloseOutUnconfirmed, ['SH-2']);
  assert.deepEqual(s.retired.sort(), ['SH-1', 'SH-2']);
  assert.deepEqual(s.byRoute, { 'codex-zai': 3 });
  assert.deepEqual(s.enabledRoutes, ['codex-zai', 'codex-qwen', 'codex-go']);
  assert.deepEqual(s.coolingRoutes, []);
});

test('the permission profile denies every credential entry of the home and nothing Codex needs', () => {
  const home = '/srv/work/agenthub-runner';
  const listing = { [home]: ['.config', '.codex', '.claude', '.claude.json', '.ssh', '.local', 'worktrees', '.cache', '.npm', 'evidence'], [`${home}/.local`]: ['bin', 'lib', 'share', 'state'] };
  const listDir = (dir) => { if (!listing[dir]) throw new Error('ENOENT'); return listing[dir]; };
  const denied = denyPaths(home, listDir);
  for (const must of ['.config', '.codex', '.claude', '.claude.json', '.ssh', 'evidence']) assert.ok(denied.includes(`${home}/${must}`), must);
  for (const must of ['share', 'state']) assert.ok(denied.includes(`${home}/.local/${must}`), must);
  for (const keep of ['.local', 'worktrees', '.cache', '.npm']) assert.ok(!denied.includes(`${home}/${keep}`), keep);
  assert.ok(!denied.includes(`${home}/.local/bin`) && !denied.includes(`${home}/.local/lib`), 'Codex helper binaries stay readable');
  const write = permissionArgs(home, 'write', listDir);
  const read = permissionArgs(home, 'read', listDir);
  assert.equal(write[1], 'default_permissions="intake"');
  assert.ok(!write.includes('-s') && !write.includes('--sandbox'), 'a profile cannot be mixed with -s');
  assert.match(write[3], /^permissions\.intake=\{"filesystem"=\{":root"="read"/);
  assert.match(write[3], /":workspace_roots"=\{"\."="write",".git"="read"\}/);
  assert.match(read[3], /":workspace_roots"=\{"\."="read"\}/);
  assert.match(write[3], /"network"=\{"enabled"=false\}/);
  assert.match(write[3], new RegExp(`"${home}/.config"="deny"`));
});

test('model-written text is redacted and issue ids are validated before use', () => {
  assert.equal(redact('fixed the scanner'), 'fixed the scanner');
  assert.equal(redact(`token ghp_${'a'.repeat(30)} leaked`), '[redacted: secret-shaped text]');
  assert.equal(redact([{ command: 'x', result: `sk-${'b'.repeat(30)}` }]), '[redacted: secret-shaped text]');
  assert.equal(redact(undefined), '""');
  for (const ok of ['SH-4512', 'SH-1']) assert.equal(validIssueId(ok), true, ok);
  for (const bad of ['SH-', '../SH-1', 'SH-1/../../x', 'sh-1', 'SH-12345678', 'SH-1; rm -rf /', '', null, undefined, 4512]) assert.equal(validIssueId(bad), false, String(bad));
});

test('the diff gate refuses binaries, symlinks, submodules, mode changes and sensitive directories', () => {
  const ok = { files: ['docs/a.md'], addedLines: ['+x'], numstat: [[1, 0]], modes: [{ path: 'docs/a.md', oldMode: '100644', newMode: '100644' }] };
  assert.deepEqual(checkDiff(ok, repo, config.limits), []);
  assert.match(checkDiff({ ...ok, numstat: [[null, null]] }, repo, config.limits).join(), /binary file change/);
  assert.match(checkDiff({ ...ok, modes: [{ path: 'l', oldMode: '000000', newMode: '120000' }] }, repo, config.limits).join(), /symlink l/);
  assert.match(checkDiff({ ...ok, modes: [{ path: 'm', oldMode: '000000', newMode: '160000' }] }, repo, config.limits).join(), /submodule m/);
  assert.match(checkDiff({ ...ok, modes: [{ path: 's.sh', oldMode: '100644', newMode: '100755' }] }, repo, config.limits).join(), /mode change s\.sh/);
  assert.deepEqual(checkDiff({ ...ok, modes: [{ path: 'n', oldMode: '000000', newMode: '100644' }] }, repo, config.limits), [], 'a new regular file is fine');
  for (const file of ['registry/capabilities.json', 'AGENTS.md', '.mcp.json', 'packages/x/hooks/pre-push', 'packages/x/.mcp.json', '.agents/plugins/marketplace.json', '.gitmodules', '.claude-plugin/marketplace.json']) {
    assert.match(checkDiff({ ...ok, files: [file] }, repo, config.limits).join(), /protected path|submodule config/, file);
  }
  assert.equal(isProtected('docs/development/agent-change-contract.md', repo.protectedPaths), false);
  assert.equal(isProtected('packages/security/scripts/check-config-payloads.mjs', repo.protectedPaths), false);
  assert.deepEqual(parseRawModes(':100644 100755 aaa bbb M\0scripts/a.sh\0:000000 120000 000 ccc A\0link\0'), [
    { oldMode: '100644', newMode: '100755', path: 'scripts/a.sh' }, { oldMode: '000000', newMode: '120000', path: 'link' }]);
});

test('a changed git hook or config in the agent tree is detected', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'intake-fp-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, '.git/hooks'), { recursive: true });
  writeFileSync(join(dir, '.git/config'), '[core]\n');
  const before = gitFingerprint(dir);
  assert.equal(gitFingerprint(dir), before);
  writeFileSync(join(dir, '.git/hooks/pre-commit'), '#!/bin/sh\n');
  assert.notEqual(gitFingerprint(dir), before, 'a new hook changes the fingerprint');
  rmSync(join(dir, '.git/hooks/pre-commit'));
  writeFileSync(join(dir, '.git/config'), '[core]\n\tfsmonitor = evil\n');
  assert.notEqual(gitFingerprint(dir), before, 'a config edit changes the fingerprint');
  assert.ok(GIT_SAFE.includes('core.hooksPath=/dev/null') && GIT_SAFE.includes('core.fsmonitor=false'));
  assert.equal(GIT_ENV.GIT_CONFIG_GLOBAL, '/dev/null');
});

test('prompts carry the guardrails the wrapper relies on', () => {
  const select = selectPrompt(config, ['SH-1'], null);
  assert.match(select, /SH-4063/);
  assert.match(select, /agent:forge/);
  assert.match(select, /lost the claim race/);
  assert.match(select, /Never pick these issues: SH-1/);
  assert.match(selectPrompt(config, [], 'SH-4512'), /Take only SH-4512/);
  const implement = implementPrompt({ issue: 'SH-4512', title: 'T', branch: 'forge/sh-4512-t', repo });
  assert.match(implement, /Do not push/);
  assert.match(implement, /do not run git add or git commit/);
  assert.match(implement, /Never edit a contentHash/);
  assert.match(implement, /do not edit the issue/);
  const route = config.routes[0];
  assert.match(finishPrompt(config, { issue: 'SH-4512', ok: true, pr: 'https://x/pull/1', route, summary: 's' }), /Never set it Done/);
  assert.match(finishPrompt(config, { issue: 'SH-4512', ok: false, stateBefore: 'Backlog', reason: 'r' }), /back to Backlog/);
});
