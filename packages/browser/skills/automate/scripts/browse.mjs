#!/usr/bin/env node
// Runs agent-browser with AgentHub's fleet defaults. Zero dependencies, Node 18+.
// Usage: node browse.mjs [--wrapper-timeout SECONDS] <agent-browser arguments...>
//
// What it adds to a plain agent-browser call:
//   - a session name that is stable for the working directory, so agents do not
//     share one browser;
//   - a 5 minute idle exit, page-content boundary markers and a 50,000 character
//     output cap, unless the environment already sets them;
//   - no visible window: --headed is refused unless AH_BROWSER_ALLOW_HEADED=1;
//   - output captured through files, because agent-browser's background daemon
//     inherits a shell pipe and keeps it open, which hangs `agent-browser ... | head`.
// It never installs anything and never prints environment values.

import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { closeSync, existsSync, mkdtempSync, openSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const DEFAULT_TIMEOUT_SECONDS = 60;
const FLEET_DEFAULTS = {
  AGENT_BROWSER_IDLE_TIMEOUT_MS: '300000',
  AGENT_BROWSER_CONTENT_BOUNDARIES: '1',
  AGENT_BROWSER_MAX_OUTPUT: '50000',
};
const INSTALL_HELP = 'agent-browser is not installed. Install it once with: npm i -g agent-browser && agent-browser install (about 120 MB plus a Chrome download). This script never installs software.';

class UserError extends Error {}

export function sessionName(cwd) {
  return `ah-${createHash('sha1').update(cwd.toLowerCase()).digest('hex').slice(0, 10)}`;
}

export function resolveBinary(env, platform = process.platform, exists = existsSync) {
  const override = env.AH_BROWSER_BIN;
  if (override) {
    if (!exists(override)) throw new UserError('AH_BROWSER_BIN points at a file that does not exist.');
    return override;
  }
  const names = platform === 'win32' ? ['agent-browser.exe'] : ['agent-browser'];
  for (const dir of (env.PATH ?? env.Path ?? '').split(delimiter).filter(Boolean)) {
    for (const name of names) {
      const candidate = join(dir, name);
      if (exists(candidate)) return candidate;
    }
  }
  throw new UserError(INSTALL_HELP);
}

export function parseWrapperArgs(argv) {
  const args = [];
  let timeoutSeconds = DEFAULT_TIMEOUT_SECONDS;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--wrapper-timeout') {
      const value = Number(argv[i + 1]);
      if (!Number.isFinite(value) || value <= 0) throw new UserError('--wrapper-timeout needs a positive number of seconds.');
      timeoutSeconds = value;
      i += 1;
    } else {
      args.push(argv[i]);
    }
  }
  return { args, timeoutSeconds };
}

export function buildInvocation(args, env, cwd) {
  if (args.length === 0) throw new UserError('Pass an agent-browser command, for example: open https://example.com');
  const headed = args.some((a) => a === '--headed' || a.startsWith('--headed='));
  if (headed && env.AH_BROWSER_ALLOW_HEADED !== '1') {
    throw new UserError('--headed is refused: fleet browsers run without a visible window. Set AH_BROWSER_ALLOW_HEADED=1 only when the user asked to watch.');
  }
  const hasSession = args.some((a) => a === '--session' || a.startsWith('--session='));
  const finalArgs = hasSession ? [...args] : ['--session', sessionName(cwd), ...args];
  const finalEnv = { ...env };
  for (const [name, value] of Object.entries(FLEET_DEFAULTS)) {
    if (!finalEnv[name]) finalEnv[name] = value;
  }
  return { args: finalArgs, env: finalEnv };
}

function launchSpec(binary, args) {
  return /\.(mjs|js|cjs)$/i.test(binary)
    ? { command: process.execPath, args: [binary, ...args] }
    : { command: binary, args };
}

export function run(binary, args, env, timeoutSeconds) {
  const dir = mkdtempSync(join(tmpdir(), 'ah-browser-'));
  const outPath = join(dir, 'out.txt');
  const errPath = join(dir, 'err.txt');
  const outFd = openSync(outPath, 'w');
  const errFd = openSync(errPath, 'w');
  const spec = launchSpec(binary, args);
  return new Promise((resolve) => {
    let timedOut = false;
    const child = spawn(spec.command, spec.args, { env, stdio: ['ignore', outFd, errFd], windowsHide: true });
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, timeoutSeconds * 1000);
    const finish = (code, spawnError) => {
      clearTimeout(timer);
      closeSync(outFd);
      closeSync(errFd);
      const stdout = readFileSync(outPath, 'utf8');
      const stderr = readFileSync(errPath, 'utf8');
      rmSync(dir, { recursive: true, force: true });
      resolve({ code: timedOut ? 124 : (code ?? 1), stdout, stderr, timedOut, spawnError });
    };
    child.on('error', (error) => finish(1, error));
    child.on('exit', (code) => finish(code));
  });
}

async function main(argv, env, cwd) {
  const { args, timeoutSeconds } = parseWrapperArgs(argv);
  const binary = resolveBinary(env);
  const invocation = buildInvocation(args, env, cwd);
  const result = await run(binary, invocation.args, invocation.env, timeoutSeconds);
  if (result.spawnError) throw new UserError(`Could not start agent-browser: ${result.spawnError.code ?? result.spawnError.name}.`);
  if (result.stdout) process.stdout.write(result.stdout.endsWith('\n') ? result.stdout : `${result.stdout}\n`);
  if (result.stderr) process.stderr.write(result.stderr.endsWith('\n') ? result.stderr : `${result.stderr}\n`);
  if (result.timedOut) {
    console.error(`Timed out after ${timeoutSeconds}s. The browser daemon may still be running; run the "close" command to stop this session.`);
  }
  return result.code;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env, process.cwd()).then(
    (code) => { process.exitCode = code; },
    (error) => {
      console.error(error instanceof UserError ? error.message : `Unexpected error: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
