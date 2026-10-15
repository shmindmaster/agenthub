#!/usr/bin/env node
// Hidden-window runner for a product's demo stack (demo-harness/v1, section 7).
//
//   node demo-stack.mjs up     --repo <path> [--only api,web]   start, wait for ready, supervise
//   node demo-stack.mjs status --repo <path>                    readiness of each service
//   node demo-stack.mjs down   --repo <path>                    stop the supervisor and every child
//
// `up` stays in the foreground as the supervisor: agents launch it as a
// background command. Each service is a NON-detached child spawned with
// windowsHide, which on Windows means CREATE_NO_WINDOW: the shell and every
// console program under it share one hidden console, so no window opens and
// focus never moves. (Detached children get DETACHED_PROCESS instead, which
// makes Windows ignore CREATE_NO_WINDOW and lets grandchildren open consoles;
// `conhost --headless` ends its session when its stdin closes. Both were tested
// and rejected.) Non-detached children also die with the supervisor, so nothing
// outlives `down`. No scheduled task, Run key or service is ever registered.

import { spawn, spawnSync } from 'node:child_process';
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';

const [command, ...rest] = process.argv.slice(2);
const flag = (name) => {
  const index = rest.indexOf(name);
  return index === -1 ? undefined : rest[index + 1];
};
const usage = 'Usage: demo-stack.mjs up|status|down --repo <path> [--only name,name]';
if (!['up', 'status', 'down'].includes(command) || !flag('--repo')) {
  console.error(usage);
  process.exit(2);
}

const repo = resolve(flag('--repo'));
const harnessPath = join(repo, 'demo', 'harness.json');
if (!existsSync(harnessPath)) {
  console.error(`No demo/harness.json in ${repo}`);
  process.exit(2);
}
const harness = JSON.parse(readFileSync(harnessPath, 'utf8'));
const only = flag('--only')?.split(',');
const services = harness.services.filter((service) => !only || only.includes(service.name));
const stateRoot = process.env.AGENTHUB_DEMO_STACK_ROOT
  ?? join(process.env.LOCALAPPDATA ?? join(homedir(), '.local', 'share'), 'AgentHub', 'demo-stack');
const stateDir = join(stateRoot, harness.product);
const statePath = join(stateDir, 'state.json');

async function ready(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(2000) });
    return response.status < 500;
  } catch {
    return false;
  }
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function killTree(pid) {
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
  } else {
    try { process.kill(-pid, 'SIGTERM'); } catch { /* group already gone */ }
    try { process.kill(pid, 'SIGTERM'); } catch { /* already gone */ }
  }
}

async function status() {
  const state = existsSync(statePath) ? JSON.parse(readFileSync(statePath, 'utf8')) : null;
  const rows = [];
  for (const service of services) {
    rows.push({ name: service.name, readyUrl: service.readyUrl, ready: await ready(service.readyUrl) });
  }
  const supervisor = state && alive(state.supervisorPid) ? state.supervisorPid : null;
  console.log(JSON.stringify({ product: harness.product, supervisorPid: supervisor, logs: stateDir, services: rows }, null, 2));
  return rows.every((row) => row.ready);
}

if (command === 'status') {
  process.exit((await status()) ? 0 : 1);
}

if (command === 'down') {
  if (!existsSync(statePath)) {
    console.log(`No running demo stack for ${harness.product}.`);
    process.exit(0);
  }
  const state = JSON.parse(readFileSync(statePath, 'utf8'));
  for (const child of state.children ?? []) if (alive(child.pid)) killTree(child.pid);
  if (alive(state.supervisorPid)) killTree(state.supervisorPid);
  rmSync(statePath, { force: true });
  console.log(`Stopped demo stack for ${harness.product}.`);
  process.exit(0);
}

// up
if (existsSync(statePath)) {
  const prior = JSON.parse(readFileSync(statePath, 'utf8'));
  if (alive(prior.supervisorPid)) {
    console.error(`A demo stack for ${harness.product} is already running (supervisor ${prior.supervisorPid}). Run down first.`);
    process.exit(1);
  }
}
mkdirSync(stateDir, { recursive: true });
const children = [];
const shutdown = (code) => {
  for (const child of children) if (child.process.exitCode === null) killTree(child.process.pid);
  rmSync(statePath, { force: true });
  process.exit(code);
};
process.on('SIGINT', () => shutdown(130));
process.on('SIGTERM', () => shutdown(143));

for (const service of services) {
  const logPath = join(stateDir, `${service.name}.log`);
  const log = openSync(logPath, 'a');
  const child = spawn(service.command, {
    cwd: service.cwd ? join(repo, service.cwd) : repo,
    env: { ...process.env, ...(service.env ?? {}) },
    shell: true,
    windowsHide: true,
    detached: false,
    stdio: ['ignore', log, log],
  });
  closeSync(log);
  child.on('exit', (code) => {
    console.error(`${service.name} exited with ${code}; see ${logPath}`);
  });
  children.push({ name: service.name, process: child, logPath });
}
writeFileSync(statePath, JSON.stringify({
  product: harness.product,
  repo,
  supervisorPid: process.pid,
  startedAt: new Date().toISOString(),
  children: children.map((child) => ({ name: child.name, pid: child.process.pid, log: child.logPath })),
}, null, 2));

for (const service of services) {
  const deadline = Date.now() + (service.readyTimeoutSeconds ?? 120) * 1000;
  const child = children.find((entry) => entry.name === service.name);
  while (!(await ready(service.readyUrl))) {
    if (child.process.exitCode !== null) {
      console.error(`${service.name} exited before it was ready; see ${child.logPath}`);
      shutdown(1);
    }
    if (Date.now() > deadline) {
      console.error(`${service.name} not ready at ${service.readyUrl} within the timeout; see ${child.logPath}`);
      shutdown(1);
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 1000));
  }
  console.log(`ready ${service.name} ${service.readyUrl}`);
}
console.log(`Demo stack for ${harness.product} is up. Logs: ${stateDir}. Stop with: node demo-stack.mjs down --repo "${repo}"`);
// Supervise until down/SIGTERM. If every child exits, stop too.
setInterval(() => {
  if (children.every((child) => child.process.exitCode !== null)) shutdown(1);
}, 2000);
