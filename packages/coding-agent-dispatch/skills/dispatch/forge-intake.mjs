#!/usr/bin/env node
// Unattended Forge intake: one eligible Linear issue per run becomes one draft pull request.
// Runs on Forge as agenthub-runner. Linear reads and writes go through a headless Codex session on a
// token plan; clone, push and `gh pr create` stay in this script so the model sandbox never holds
// GitHub credentials. Nothing is merged, marked ready or deployed.
import { spawn, spawnSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { freemem, userInfo } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HOME = '/srv/work/agenthub-runner';
const STATE = join(HOME, '.local/state/agenthub/forge-intake');
const KILL_SWITCH = join(HOME, '.config/agenthub/forge-intake.disabled');
const WORK = join(HOME, 'worktrees/intake');
const COOLDOWN_MS = 3 * 3600_000; // Z.ai's window is 5 hours; the others reset sooner, so 3 hours is a middle value.
const CONFIG_PATH = fileURLToPath(new URL('./forge-intake.json', import.meta.url));
const SECRET_PATTERNS = [/gh[pousr]_[A-Za-z0-9]{20,}/, /github_pat_[A-Za-z0-9_]{20,}/, /\bsk-[A-Za-z0-9_-]{20,}/, /AKIA[0-9A-Z]{16}/, /xox[abprs]-[A-Za-z0-9-]{10,}/, /-----BEGIN [A-Z ]*PRIVATE KEY-----/, /lin_(?:api|oauth)_[A-Za-z0-9]{20,}/];

export const loadConfig = (path = CONFIG_PATH) => JSON.parse(readFileSync(path, 'utf8'));

export const slugify = (text, max = 40) =>
  text.toLowerCase().replace(/^\[[^\]]*\]\s*/, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, max).replace(/-+$/, '');

// A retry gets its own branch: a first attempt may have pushed before a later step failed.
export const branchName = (id, title, attempt = 1) => `forge/${id.toLowerCase()}-${slugify(title)}`.replace(/-+$/, '') + (attempt > 1 ? `-r${attempt}` : '');

// The service starts this file through the /opt/agenthub/current symlink, so compare real paths.
export const isMainModule = (metaUrl, argv1) => {
  if (!argv1) return false;
  try { return realpathSync(fileURLToPath(metaUrl)) === realpathSync(argv1); } catch { return false; }
};

export const splitNul = (text) => text.split('\0').filter(Boolean);

// The claim label is added by the intake itself, so it is not evidence against eligibility.
export const preClaimLabels = (labels, linear) => (labels || []).filter((label) => label !== linear.claimLabel);

const globToRegExp = (glob) => new RegExp(`^${glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`);

export function isEligible({ state, labels }, linear) {
  if (!linear.pickStates.includes(state)) return 'state';
  if (!labels.some((label) => linear.includeLabelsAny.includes(label))) return 'no include label';
  const blocked = linear.excludeLabelPatterns.map(globToRegExp);
  if (labels.some((label) => blocked.some((re) => re.test(label)))) return 'excluded label';
  return null;
}

export const repoFor = (labels, config) => {
  const key = labels.find((label) => config.repos[label]);
  return key ? { key, ...config.repos[key] } : null;
};

// Pull the last JSON object out of an agent's final message.
export function parseAgentJson(text) {
  const starts = [...text.matchAll(/\{/g)].map((m) => m.index);
  for (const start of starts) {
    for (let end = text.lastIndexOf('}'); end > start; end = text.lastIndexOf('}', end - 1)) {
      try { return JSON.parse(text.slice(start, end + 1)); } catch { /* try a shorter span */ }
    }
  }
  return null;
}

export const dayKey = (iso) => iso.slice(0, 10);

export function runsToday(ledger, now) {
  return ledger.filter((row) => row.phase === 'run' && dayKey(row.ts) === dayKey(now)).length;
}

export const failedAttempts = (ledger, issue) => ledger.filter((row) => row.phase === 'run' && row.issue === issue && row.outcome === 'failed').length;

export function skipList(ledger, config) {
  const ids = [...new Set(ledger.filter((row) => row.phase === 'run' && row.issue).map((row) => row.issue))];
  return ids.filter((id) => failedAttempts(ledger, id) >= config.limits.maxAttemptsPerIssue || ledger.some((row) => row.issue === id && row.outcome === 'pr'));
}

// A plan that reports its quota or rate limit is not at fault for the issue: it cools down and the
// attempt is not charged to the issue.
export const LIMIT_PATTERN = /usage limit|rate limit|quota|too many requests|insufficient (?:balance|credit)|limit (?:has been )?reached/i;
export const isProviderLimit = (text) => LIMIT_PATTERN.test(text || '');

export const coolingRoutes = (ledger, now) => new Set(ledger.filter((row) => row.phase === 'cooldown' && row.until > now).map((row) => row.route));

// Least recently used enabled route that is not cooling down, so work spreads over the plans.
export function pickRoute(config, ledger, now = new Date().toISOString()) {
  const cooling = coolingRoutes(ledger, now);
  const enabled = config.routes.filter((route) => route.enabled && !cooling.has(route.id));
  if (!enabled.length) return null;
  const lastUse = (id) => ledger.map((row, i) => (row.phase === 'run' && row.route === id ? i : -1)).reduce((a, b) => Math.max(a, b), -1);
  return [...enabled].sort((a, b) => lastUse(a.id) - lastUse(b.id))[0];
}

export function checkDiff({ files, addedLines, numstat }, repo, limits) {
  const problems = [];
  if (!files.length) problems.push('no changed files');
  if (files.length > limits.maxFiles) problems.push(`${files.length} files exceeds ${limits.maxFiles}`);
  const changed = numstat.reduce((sum, [a, d]) => sum + a + d, 0);
  if (changed > limits.maxChangedLines) problems.push(`${changed} changed lines exceeds ${limits.maxChangedLines}`);
  for (const file of files) {
    if (repo.protectedPaths.some((p) => file.startsWith(p))) problems.push(`protected path ${file}`);
    if (/(^|\/)(\.env[^/]*|credentials?|[^/]*\.pem|[^/]*\.key)$/i.test(file)) problems.push(`secret-shaped path ${file}`);
  }
  if (addedLines.some((line) => SECRET_PATTERNS.some((re) => re.test(line)))) problems.push('secret-shaped content in added lines');
  return problems;
}

const claimRules = (config) => {
  const l = config.linear;
  return `Eligible issue: team ${l.team}; state one of ${l.pickStates.join(', ')}; no assignee; at least one of these labels: ${l.includeLabelsAny.join(', ')}; a label that names a mapped app (${Object.keys(config.repos).join(', ')}); and none of these label patterns: ${l.excludeLabelPatterns.join(', ')}. Never pick an epic, an issue that has sub-issues, or one whose body asks for an owner decision, a purchase, an external message, a deployment or access to a client system.`;
};

const l = (config) => config.linear;

export const selectPrompt = (config, skip, forcedIssue) => `You are the unattended Forge intake for the owner's Linear backlog. Follow the claim protocol of issue SH-4063. Use only the Linear MCP; run no shell commands.
${claimRules(config)}
${skip.length ? `Never pick these issues: ${skip.join(', ')}.` : ''}
First release stale claims: any issue labelled ${l(config).claimLabel} that is ${l(config).claimedState} and untouched for ${l(config).staleClaimHours}+ hours loses that label, returns to Backlog and gets a one-line comment saying the Forge claim expired.
${forcedIssue ? `Take only ${forcedIssue}, and only if it is eligible.` : 'Pick the single eligible issue with the highest priority (Urgent first, then oldest), skipping an issue another session claimed.'}
If one qualifies: add the label ${l(config).claimLabel} and set it ${l(config).claimedState}. Then read the issue again to detect a duplicate claim: if any other agent:* label or an assignee appeared, remove only ${l(config).claimLabel}, restore the earlier state and reply {"outcome":"none","reason":"lost the claim race"}. Otherwise reply with one JSON object and nothing else: {"outcome":"claimed","issue":"SH-123","title":"...","state_before":"Backlog","labels":["every label the issue had BEFORE you added ${l(config).claimLabel}"],"summary":"two sentences on what the issue asks"}.
If none qualifies, change nothing and reply {"outcome":"none","reason":"..."}.`;

export const implementPrompt = ({ issue, title, branch, repo }) => `You are an unattended coding agent on a Forge worktree of ${repo.repo}, on branch ${branch}. Implement Linear issue ${issue} ("${title}").
1. Read the issue with the Linear MCP (read only: do not edit the issue, comment or change labels; the intake wrapper does that).
2. Read AGENTS.md in this repository and follow it, including the package change contract.
3. Make the smallest change that fully resolves the issue, with a test that fails before and passes after. Run the focused tests the repository documents. The network is off and this checkout is the only writable place. Subprocess-spawning tests can fail under this sandbox with EPERM and pwsh is not installed: run what works, name what could not run, and leave the rest to the pull request's CI. Never edit a contentHash in registry/capabilities.json (the algorithm needs PowerShell, and a hand-computed hash fails CI): list each package whose files you changed under "notes" so the reviewer recomputes it.
4. Leave your edits in the working tree. The sandbox makes .git read-only, so do not run git add or git commit: the wrapper commits as "${issue}: ..." after checking the diff. Do not push, open a pull request, merge, change .github/, or touch credentials.
If the issue is ambiguous, needs a decision from the owner, or needs access you do not have, make no edits and say so.
Reply with one JSON object and nothing else: {"status":"done"|"blocked","summary":"what changed and why","tests":[{"command":"...","result":"pass|fail|not-run"}],"notes":"limits or follow-ups"}. Use "done" when the change is complete in the working tree, even if some tests could not run here.`;

export const finishPrompt = (config, { issue, ok, pr, route, summary, stateBefore, reason }) => `You are the unattended Forge intake closing out Linear issue ${issue}. Use only the Linear MCP; run no shell commands.
${ok
  ? `A draft pull request is open: ${pr}. It was written by Codex on the ${route.plan} (${route.id}) and has had no review. Comment on the issue with the PR link and this summary: ${JSON.stringify(summary)}. State plainly that it is a draft, not reviewed, not merged and not deployed. Remove the label ${config.linear.claimLabel} and set the issue to ${config.linear.reviewState}. Never set it Done.`
  : `The run did not produce a pull request. Comment on the issue with this reason: ${JSON.stringify(reason)}. Remove the label ${config.linear.claimLabel} and set the issue back to ${stateBefore || 'Backlog'}.`}
Reply with {"ok":true} when the issue reflects this, otherwise {"ok":false,"error":"..."}.`;

// ---- process helpers (not exercised by unit tests) ----
const run = (cmd, args, opts = {}) => spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, ...opts });
const git = (cwd, ...args) => run('git', args, { cwd });
const log = (dir, name, text) => appendFileSync(join(dir, name), text);

// Codex hides most of the Linear server's 78 tools from the model unless an allowlist names them, so the
// allowlist both makes save_issue callable and keeps each phase to the tools it needs (no deletes).
// With approval "never" Codex refuses non-read-only MCP tools, so the write tools a phase lists are
// approved one by one; nothing outside the allowlist is reachable.
export const linearArgs = (linear, phase) => {
  const tools = linear.toolsByPhase[phase];
  return [
    '-c', `mcp_servers.linear.url=${JSON.stringify(linear.mcpUrl)}`,
    '-c', `mcp_servers.linear.enabled_tools=${JSON.stringify(tools)}`,
    ...tools.filter((tool) => /^(save|create)_/.test(tool)).flatMap((tool) => ['-c', `mcp_servers.linear.tools.${tool}.approval_mode="approve"`]),
  ];
};

function runAgent({ route, cwd, sandbox, prompt, seconds, dir, name, linear }) {
  const out = join(dir, `${name}.last.txt`);
  const args = ['exec', '--skip-git-repo-check', '--ephemeral', '-s', sandbox, '-C', cwd, ...linearArgs(linear, name), '-o', out, prompt];
  const env = { HOME, PATH: `${HOME}/.local/bin:/usr/bin:/bin`, TERM: 'dumb' };
  return new Promise((resolve) => {
    const child = spawn(join(HOME, route.launcher), args, { cwd, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let tail = '';
    const sink = (chunk) => { log(dir, `${name}.log`, chunk); tail = (tail + chunk).slice(-6000); };
    child.stdout.on('data', sink); child.stderr.on('data', sink);
    const timer = setTimeout(() => { try { process.kill(-child.pid, 'SIGKILL'); } catch { /* gone */ } resolve({ code: 'timeout', reply: null }); }, seconds * 1000);
    // A missing or non-executable launcher must fail the phase, not crash the run before close-out.
    child.on('error', (error) => { clearTimeout(timer); log(dir, `${name}.log`, `spawn error: ${error.message}\n`); resolve({ code: 'spawn-error', reply: null }); });
    child.on('close', (code) => {
      clearTimeout(timer);
      const reply = existsSync(out) ? parseAgentJson(readFileSync(out, 'utf8')) : null;
      resolve({ code, reply, limited: !reply && code !== 0 && isProviderLimit(tail) });
    });
  });
}

const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

// Atomic single-run lock. A lock whose process is gone (crash, kill, reboot) is taken over.
export function acquireLock(path, pid = process.pid) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try { writeFileSync(path, String(pid), { flag: 'wx' }); return true; } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (alive(Number(readFileSync(path, 'utf8')))) return false;
      rmSync(path, { force: true });
    }
  }
  return false;
}

// What an operator needs from the ledger: caps, outcomes, retired issues and per-route use.
export function summarize(ledger, config, now) {
  const runs = ledger.filter((row) => row.phase === 'run');
  const count = (pick) => runs.filter(pick).length;
  const byRoute = {};
  for (const row of runs) byRoute[row.route] = (byRoute[row.route] || 0) + 1;
  return {
    runsToday: runsToday(ledger, now), dailyCap: config.limits.maxRunsPerDay, coolingRoutes: [...coolingRoutes(ledger, now)],
    runsTotal: runs.length, draftPrs: runs.filter((row) => row.pr).map((row) => ({ issue: row.issue, pr: row.pr })),
    failed: count((row) => row.outcome === 'failed'), linearCloseOutUnconfirmed: runs.filter((row) => row.linearClosed === false).map((row) => row.issue),
    retired: skipList(ledger, config), byRoute,
    enabledRoutes: config.routes.filter((route) => route.enabled).map((route) => route.id),
    last: runs.slice(-3).map(({ ts, issue, outcome, route, pr, reason }) => ({ ts, issue, outcome, route, pr, reason })),
  };
}

const readLedger = () => (existsSync(join(STATE, 'ledger.jsonl')) ? readFileSync(join(STATE, 'ledger.jsonl'), 'utf8').split('\n').filter(Boolean).map((line) => JSON.parse(line)) : []);
const record = (row) => appendFileSync(join(STATE, 'ledger.jsonl'), `${JSON.stringify({ ts: new Date().toISOString(), ...row })}\n`);

function prune(config) {
  const cutoff = Date.now() - config.limits.keepRunDays * 86400_000;
  for (const base of [join(STATE, 'runs'), WORK]) {
    if (!existsSync(base)) continue;
    for (const name of readdirSync(base)) {
      const path = join(base, name);
      if (statSync(path).mtimeMs < cutoff) rmSync(path, { recursive: true, force: true });
    }
  }
}

export function inspectWorktree(dir, repo) {
  const base = `origin/${repo.base}`;
  // NUL-delimited and rename-free: git quotes non-ASCII paths otherwise, which would slip past the path checks.
  const files = splitNul(git(dir, 'diff', '-z', '--no-renames', '--name-only', `${base}...HEAD`).stdout);
  const numstat = splitNul(git(dir, 'diff', '-z', '--no-renames', '--numstat', `${base}...HEAD`).stdout).map((row) => row.split('\t').slice(0, 2).map((n) => Number(n) || 0));
  const addedLines = git(dir, 'diff', '-U0', `${base}...HEAD`).stdout.split('\n').filter((line) => line.startsWith('+') && !line.startsWith('+++'));
  const commits = Number(git(dir, 'rev-list', '--count', `${base}..HEAD`).stdout.trim() || 0);
  const whitespace = git(dir, 'diff', '--check', `${base}...HEAD`);
  return { files, numstat, addedLines, commits, whitespaceOk: whitespace.status === 0, dirty: git(dir, 'status', '--porcelain').stdout.trim().length > 0 };
}

export async function main(argv) {
  const config = loadConfig();
  const flag = (name) => { const i = argv.indexOf(name); return i === -1 ? null : argv[i + 1] ?? true; };
  const ledger = readLedger();
  const now = new Date().toISOString();
  // Read-only report, safe as root or runner: nothing below this branch runs.
  if (flag('--status') !== null) {
    console.log(JSON.stringify({ disabled: existsSync(KILL_SWITCH), lockHeldBy: existsSync(join(STATE, 'lock')) ? readFileSync(join(STATE, 'lock'), 'utf8') : null, ...summarize(ledger, config, now) }, null, 2));
    return 0;
  }
  if (existsSync(KILL_SWITCH)) return console.log('forge-intake: disabled by kill switch');
  if (userInfo().username !== 'agenthub-runner') throw new Error('run as agenthub-runner on Forge');
  mkdirSync(STATE, { recursive: true }); mkdirSync(WORK, { recursive: true });
  const lock = join(STATE, 'lock');
  if (!acquireLock(lock)) return console.log('forge-intake: another run holds the lock');
  const dir = join(STATE, 'runs', now.replace(/[:.]/g, '-')); mkdirSync(dir, { recursive: true });
  const row = { phase: 'run', outcome: 'none' };
  const cool = (limitedRoute, phase) => record({ phase: 'cooldown', route: limitedRoute.id, during: phase, until: new Date(Date.now() + COOLDOWN_MS).toISOString() });
  let claimed = null; let route = null; let pr = null; let reason = null; let checkout = null;
  try {
    prune(config);
    if (runsToday(ledger, now) >= config.limits.maxRunsPerDay && !flag('--issue')) return console.log('forge-intake: daily cap reached');
    if (freemem() / 1048576 < config.limits.minFreeMemMiB) return console.log('forge-intake: not enough free memory');
    route = flag('--route') ? config.routes.find((r) => r.id === flag('--route')) : pickRoute(config, ledger);
    if (!route) throw new Error('no enabled route');
    row.route = route.id;
    // 1. select and claim
    const sel = await runAgent({ route, cwd: WORK, sandbox: 'read-only', prompt: selectPrompt(config, skipList(ledger, config), flag('--issue')), seconds: config.limits.selectSeconds, dir, name: 'select', linear: config.linear });
    if (sel.limited) { cool(route, 'select'); return console.log(`forge-intake: ${route.id} is at its plan limit; cooling down`); }
    if (!sel.reply || sel.reply.outcome === 'none') { row.reason = sel.reply?.reason || `select failed (${sel.code})`; return console.log(`forge-intake: nothing taken: ${row.reason}`); }
    claimed = sel.reply; row.issue = claimed.issue;
    const labelsBefore = preClaimLabels(claimed.labels, config.linear);
    const bad = isEligible({ state: claimed.state_before, labels: labelsBefore }, config.linear);
    const repo = repoFor(labelsBefore, config);
    if (bad || !repo) throw new Error(`claimed an ineligible issue (${bad || 'no mapped repo'})`);
    // 2. clone and implement
    checkout = join(WORK, `${claimed.issue.toLowerCase()}-${Date.now()}`);
    const clone = run('gh', ['repo', 'clone', repo.repo, checkout, '--', '--depth', '50', '--branch', repo.base]);
    if (clone.status !== 0) throw new Error(`clone failed: ${clone.stderr.trim().slice(0, 200)}`);
    const branch = branchName(claimed.issue, claimed.title, failedAttempts(ledger, claimed.issue) + 1);
    git(checkout, 'switch', '-c', branch);
    git(checkout, 'config', 'user.name', 'AgentHub Forge'); git(checkout, 'config', 'user.email', 'forge@users.noreply.github.com');
    const impl = await runAgent({ route, cwd: checkout, sandbox: 'workspace-write', prompt: implementPrompt({ issue: claimed.issue, title: claimed.title, branch, repo }), seconds: config.limits.implementSeconds, dir, name: 'implement', linear: config.linear });
    if (impl.limited) { cool(route, 'implement'); const limit = new Error(`${route.id} hit its plan limit during implementation; the issue is released without charging an attempt`); limit.limited = true; throw limit; }
    if (!impl.reply || impl.reply.status !== 'done') throw new Error(`implementation ${impl.reply?.status || `failed (${impl.code})`}: ${impl.reply?.notes || impl.reply?.summary || ''}`.slice(0, 400));
    // 3. commit, verify the diff outside the model's control, then push and open a draft PR
    git(checkout, 'add', '-A');
    const commit = git(checkout, 'commit', '-q', '-m', `${claimed.issue}: ${claimed.title.replace(/^\[[^\]]*\]\s*/, '')}\n\nLinear: ${claimed.issue}\nWritten unattended on ${route.plan} (${route.id}); see the pull request for review state.`);
    if (commit.status !== 0 && !/nothing to commit/.test(commit.stdout + commit.stderr)) throw new Error(`commit failed: ${commit.stderr.trim().slice(0, 200)}`);
    const seen = inspectWorktree(checkout, repo);
    const problems = checkDiff(seen, repo, config.limits);
    if (seen.dirty) problems.push('uncommitted changes left behind');
    if (!seen.commits) problems.push('no commit');
    if (!seen.whitespaceOk) problems.push('git diff --check failed');
    if (problems.length) throw new Error(`diff refused: ${problems.join('; ')}`);
    const push = run('git', ['-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', 'push', 'origin', `HEAD:refs/heads/${branch}`], { cwd: checkout });
    if (push.status !== 0) throw new Error(`push failed: ${push.stderr.trim().slice(0, 200)}`);
    const body = `Linear: ${claimed.issue}\n\n${impl.reply.summary}\n\nTests reported by the agent: ${JSON.stringify(impl.reply.tests || [])}\n\nOpened unattended by Forge intake on ${route.plan} (${route.id}). Draft: no human has reviewed it, nothing is merged or deployed. CI on this PR is the verification.`;
    const created = run('gh', ['pr', 'create', '--repo', repo.repo, '--draft', '--base', repo.base, '--head', branch, '--title', `${claimed.issue}: ${claimed.title.replace(/^\[[^\]]*\]\s*/, '')}`, '--body', body], { cwd: checkout });
    if (created.status !== 0) {
      run('git', ['-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', 'push', 'origin', '--delete', branch], { cwd: checkout });
      throw new Error(`gh pr create failed: ${created.stderr.trim().slice(0, 200)}`);
    }
    pr = created.stdout.trim().split('\n').pop(); row.pr = pr; row.outcome = 'pr';
    claimed.summary = impl.reply.summary;
  } catch (error) {
    reason = String(error.message || error); row.outcome = error.limited ? 'limited' : 'failed'; row.reason = reason; console.error(`forge-intake: ${reason}`);
  } finally {
    if (claimed && route) {
      const fin = await runAgent({ route, cwd: WORK, sandbox: 'read-only', prompt: finishPrompt(config, { issue: claimed.issue, ok: Boolean(pr), pr, route, summary: claimed.summary, stateBefore: claimed.state_before, reason }), seconds: config.limits.finishSeconds, dir, name: 'finish', linear: config.linear });
      row.linearClosed = Boolean(fin.reply?.ok);
      if (!row.linearClosed) console.error(`forge-intake: Linear close-out for ${claimed.issue} not confirmed; see ${dir}`);
    }
    if (checkout && existsSync(checkout)) {
      if (row.outcome !== 'pr') writeFileSync(join(dir, 'patch.diff'), git(checkout, 'diff', 'HEAD').stdout + git(checkout, 'log', '-p', '--stat', '-n', '3').stdout);
      rmSync(checkout, { recursive: true, force: true });
    }
    if (claimed) record(row);
    rmSync(lock, { force: true });
  }
  console.log(`forge-intake: ${row.outcome}${row.issue ? ` ${row.issue}` : ''}${pr ? ` ${pr}` : ''}`);
  return row.outcome === 'failed' ? 1 : 0;
}

if (isMainModule(import.meta.url, process.argv[1])) {
  main(process.argv.slice(2)).then((code) => process.exit(code || 0), (error) => { console.error(`forge-intake: ${error.message}`); process.exit(2); });
}
