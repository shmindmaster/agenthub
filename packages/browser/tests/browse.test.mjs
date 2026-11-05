import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { buildInvocation, parseWrapperArgs, resolveBinary, sessionName } from '../skills/automate/scripts/browse.mjs';

const SCRIPT = fileURLToPath(new URL('../skills/automate/scripts/browse.mjs', import.meta.url));

function makeFake(body) {
  const dir = mkdtempSync(join(tmpdir(), 'ah-browser-test-'));
  const file = join(dir, 'fake-agent-browser.mjs');
  writeFileSync(file, body);
  chmodSync(file, 0o755);
  return { dir, file };
}

function runWrapper(args, env) {
  return new Promise((resolve) => {
    const started = Date.now();
    const child = spawn(process.execPath, [SCRIPT, ...args], {
      env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('close', (code) => resolve({ code, stdout, stderr, ms: Date.now() - started }));
  });
}

test('sessionName is stable per directory and differs between directories', () => {
  assert.equal(sessionName('C:/a'), sessionName('c:/A'));
  assert.notEqual(sessionName('C:/a'), sessionName('C:/b'));
  assert.match(sessionName('C:/a'), /^ah-[0-9a-f]{10}$/);
});

test('parseWrapperArgs removes only the wrapper timeout flag', () => {
  const parsed = parseWrapperArgs(['--wrapper-timeout', '5', 'open', 'https://example.com', '--session', 'x']);
  assert.equal(parsed.timeoutSeconds, 5);
  assert.deepEqual(parsed.args, ['open', 'https://example.com', '--session', 'x']);
  assert.throws(() => parseWrapperArgs(['--wrapper-timeout', 'zero']), /positive number/);
});

test('buildInvocation adds a session, fleet defaults, and respects what is already set', () => {
  const plain = buildInvocation(['open', 'https://example.com'], { PATH: 'x' }, 'C:/work');
  assert.deepEqual(plain.args.slice(0, 2), ['--session', sessionName('C:/work')]);
  assert.equal(plain.env.AGENT_BROWSER_IDLE_TIMEOUT_MS, '300000');
  assert.equal(plain.env.AGENT_BROWSER_CONTENT_BOUNDARIES, '1');
  assert.equal(plain.env.AGENT_BROWSER_MAX_OUTPUT, '50000');
  const custom = buildInvocation(['--session', 'mine', 'snapshot'], { AGENT_BROWSER_MAX_OUTPUT: '10' }, 'C:/work');
  assert.deepEqual(custom.args, ['--session', 'mine', 'snapshot']);
  assert.equal(custom.env.AGENT_BROWSER_MAX_OUTPUT, '10');
});

test('buildInvocation refuses a visible window unless the owner allows it', () => {
  assert.throws(() => buildInvocation(['--headed', 'open', 'x'], {}, 'C:/w'), /refused/);
  assert.doesNotThrow(() => buildInvocation(['--headed', 'open', 'x'], { AH_BROWSER_ALLOW_HEADED: '1' }, 'C:/w'));
  assert.throws(() => buildInvocation([], {}, 'C:/w'), /Pass an agent-browser command/);
});

test('resolveBinary finds the override, searches PATH, and explains a missing install without installing', () => {
  assert.equal(resolveBinary({ AH_BROWSER_BIN: 'B' }, 'linux', (p) => p === 'B'), 'B');
  assert.throws(() => resolveBinary({ AH_BROWSER_BIN: 'missing' }, 'linux', () => false), /does not exist/);
  const found = resolveBinary({ PATH: ['/a', '/b'].join(process.platform === 'win32' ? ';' : ':') }, 'linux', (p) => p.replace(/\\/g, '/') === '/b/agent-browser');
  assert.ok(found.replace(/\\/g, '/').endsWith('/b/agent-browser'));
  assert.throws(() => resolveBinary({ PATH: '' }, 'linux', () => false), /npm i -g agent-browser/);
});

test('end to end: passes args and defaults to the binary and prints its output', async () => {
  const fake = makeFake('console.log(JSON.stringify({ args: process.argv.slice(2), idle: process.env.AGENT_BROWSER_IDLE_TIMEOUT_MS, boundaries: process.env.AGENT_BROWSER_CONTENT_BOUNDARIES }));');
  try {
    const result = await runWrapper(['open', 'https://example.com'], { AH_BROWSER_BIN: fake.file });
    assert.equal(result.code, 0, result.stderr);
    const seen = JSON.parse(result.stdout);
    assert.equal(seen.args[0], '--session');
    assert.deepEqual(seen.args.slice(2), ['open', 'https://example.com']);
    assert.equal(seen.idle, '300000');
    assert.equal(seen.boundaries, '1');
  } finally {
    rmSync(fake.dir, { recursive: true, force: true });
  }
});

test('end to end: a background daemon that keeps the output handle open does not hang the wrapper', async () => {
  const fake = makeFake(`
    import { spawn } from 'node:child_process';
    const daemon = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 6000)'], { stdio: 'inherit', detached: true });
    daemon.unref();
    console.log('opened');
  `);
  try {
    const result = await runWrapper(['open', 'https://example.com'], { AH_BROWSER_BIN: fake.file });
    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /opened/);
    assert.ok(result.ms < 4500, `wrapper took ${result.ms} ms; it waited for the daemon's handle`);
  } finally {
    rmSync(fake.dir, { recursive: true, force: true });
  }
});

test('end to end: exit codes pass through and a hung command times out with a close hint', async () => {
  const failing = makeFake('console.error("boom"); process.exit(3);');
  const hanging = makeFake('setTimeout(() => {}, 30000);');
  try {
    const failed = await runWrapper(['click', '@e1'], { AH_BROWSER_BIN: failing.file });
    assert.equal(failed.code, 3);
    assert.match(failed.stderr, /boom/);
    const timedOut = await runWrapper(['--wrapper-timeout', '1', 'open', 'https://example.com'], { AH_BROWSER_BIN: hanging.file });
    assert.equal(timedOut.code, 124);
    assert.match(timedOut.stderr, /Timed out after 1s/);
    assert.match(timedOut.stderr, /"close"/);
  } finally {
    rmSync(failing.dir, { recursive: true, force: true });
    rmSync(hanging.dir, { recursive: true, force: true });
  }
});
