import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import {
  branchName, checkDiff, failedAttempts, finishPrompt, implementPrompt, isEligible, linearArgs, loadConfig, parseAgentJson, pickRoute, repoFor, runsToday, selectPrompt, skipList, slugify,
} from '../skills/dispatch/forge-intake.mjs';

const config = loadConfig(join(fileURLToPath(new URL('../skills/dispatch/', import.meta.url)), 'forge-intake.json'));
const repo = config.repos['app:agenthub'];
const bug = { state: 'Backlog', labels: ['from-execution', 'app:agenthub', 'type:bug'] };

test('config enables exactly the verified Z.ai route and a repo allowlist', () => {
  assert.deepEqual(config.routes.filter((r) => r.enabled).map((r) => r.id), ['codex-zai']);
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

test('prompts carry the guardrails the wrapper relies on', () => {
  const select = selectPrompt(config, ['SH-1'], null);
  assert.match(select, /SH-4063/);
  assert.match(select, /agent:forge/);
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
