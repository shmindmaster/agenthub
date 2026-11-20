// @ts-check

import { execFile } from 'node:child_process';
import { accessSync, constants, readdirSync, readFileSync, statSync } from 'node:fs';
import { delimiter, isAbsolute, join } from 'node:path';
import { promisify } from 'node:util';

const run = promisify(execFile);
const INVENTORY_TIMEOUT_MS = 10_000;
const NATIVE_HEALTH_TIMEOUT_MS = 120_000;

/**
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 * @param {string} name
 */
function findNativeExecutable(ctx, env, name) {
  const windows = ctx.platform === 'windows';
  if (ctx.platform !== (process.platform === 'win32' ? 'windows' : process.platform)) return undefined;
  const baseName = windows ? `${name}.exe` : name;
  const pathDirs = (env.PATH ?? env.Path ?? '').split(delimiter).filter(isAbsolute);
  const candidates = pathDirs.map((dir) => join(dir, baseName));
  if (windows) candidates.unshift(join(ctx.localData, 'Microsoft', 'WinGet', 'Links', baseName));
  return candidates.find((path) => {
    try {
      if (!isAbsolute(path) || !statSync(path).isFile()) return false;
      if (!windows) accessSync(path, constants.X_OK);
      return true;
    } catch {
      return false;
    }
  });
}

/**
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 * @param {number} timeout
 */
function nativeOptions(ctx, env, timeout) {
  return {
    cwd: ctx.home,
    env,
    encoding: /** @type {const} */ ('utf8'),
    timeout,
    maxBuffer: 4 * 1024 * 1024,
    windowsHide: true,
  };
}

/**
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 */
export async function inspectDevin(ctx, env) {
  const executable = findNativeExecutable(ctx, env, 'devin');
  if (!executable) return { status: /** @type {const} */ ('unavailable') };

  try {
    const read = async (/** @type {string} */ group) => {
      const { stdout } = await run(executable, [group, 'list', '--json', '--process-model', 'in-process'], nativeOptions(ctx, env, INVENTORY_TIMEOUT_MS));
      const data = JSON.parse(stdout);
      if (!Array.isArray(data)) throw new Error('Expected an array from Devin');
      return data;
    };
    const mcp = (await read('mcp')).map((entry) => ({
      name: identifier(entry?.name),
      enabled: typeof entry?.enabled === 'boolean' ? entry.enabled : null,
      transport: ['http', 'stdio', 'sse'].includes(entry?.transport) ? entry.transport : 'unknown',
      plugin: typeof entry?.source === 'string' && /^plugin(?:\s|$)/i.test(entry.source),
    }));
    const skills = (await read('skills')).map((entry) => identifier(entry?.name));
    return { status: /** @type {const} */ ('listed'), mcp, skills };
  } catch {
    // Native stderr and URLs can contain credentials. Keep subprocess output
    // private even when the command fails or a newer host changes its schema.
    return { status: /** @type {const} */ ('failed') };
  }
}

/**
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 * @param {string} [accountEmail]
 */
export function openAutoClawRuntime(ctx, env, accountEmail) {
  if (ctx.platform !== 'windows' || process.platform !== 'win32') return { status: /** @type {const} */ ('unavailable') };
  const runtime = join(ctx.localData, 'Programs', 'AutoClaw2', 'resources', 'vendor', 'zcode', 'zcode.cjs');
  const accounts = join(ctx.roamingConfig, 'AutoClaw-oversea-official', 'accounts');

  try {
    if (!statSync(runtime, { throwIfNoEntry: false })?.isFile()) return { status: /** @type {const} */ ('unavailable') };
    const profiles = statSync(accounts, { throwIfNoEntry: false })?.isDirectory()
      ? readdirSync(accounts, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => {
          const directory = join(accounts, entry.name);
          return { directory, home: join(directory, 'runtime', 'zcode-runtime', 'home') };
        })
        .filter(({ home }) => statSync(join(home, '.zcode', 'cli'), { throwIfNoEntry: false })?.isDirectory())
      : [];
    const matches = accountEmail ? profiles.filter(({ directory }) => {
      const path = join(directory, 'account-profile.json');
      if (!statSync(path, { throwIfNoEntry: false })?.isFile()) return false;
      const profile = JSON.parse(readFileSync(path, 'utf8')).profile;
      return profile?.isGuest !== true && typeof profile?.email === 'string' &&
        profile.email.toLowerCase() === accountEmail.toLowerCase();
    }) : profiles;
    if (!matches.length) return { status: /** @type {const} */ ('no-account') };
    if (matches.length > 1) return { status: /** @type {const} */ ('ambiguous-account') };

    const [{ home }] = matches;
    const childEnv = Object.fromEntries(Object.entries(env)
      .filter(([key]) => !['HOME', 'USERPROFILE', 'ZCODE_HOME'].includes(key.toUpperCase())));
    childEnv.USERPROFILE = home;
    return {
      status: /** @type {const} */ ('ready'),
      async invoke(/** @type {string[]} */ args, cwd = home, timeout = INVENTORY_TIMEOUT_MS) {
        try {
          const { stdout } = await run(process.execPath, [runtime, ...args, '--json', '--cwd', cwd],
            nativeOptions({ ...ctx, home: cwd }, childEnv, timeout));
          const data = JSON.parse(stdout);
          if (data == null || data.ok === false) throw new Error('Native operation failed');
          return data;
        } catch {
          throw new Error('Bundled AutoClaw command failed.');
        }
      },
    };
  } catch {
    return { status: /** @type {const} */ ('failed') };
  }
}

/**
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 */
export async function inspectAutoClaw(ctx, env) {
  const runtime = openAutoClawRuntime(ctx, env);
  if (runtime.status !== 'ready') return { status: runtime.status };
  try {
    const plugins = await runtime.invoke(['plugins', 'list']);
    const inventory = await runtime.invoke(['skills', 'list']);
    if (!Array.isArray(plugins) || !Array.isArray(inventory?.skills)) throw new Error('Invalid AutoClaw inventory');
    return {
      status: /** @type {const} */ ('listed'),
      plugins: plugins.map((entry) => {
        const parts = typeof entry?.id === 'string' ? entry.id.split('@') : [];
        if (parts.length !== 2 || typeof entry.enabled !== 'boolean' || !Array.isArray(entry.declaredMcpServerNames)) {
          throw new Error('Invalid AutoClaw plugin inventory');
        }
        return {
          id: parts.map(identifier).join('@'),
          version: typeof entry.version === 'string' && entry.version.length <= 80 &&
            /^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9a-z.+-]+)?$/i.test(entry.version) ? entry.version : null,
          enabled: entry.enabled,
          declaredMcpServers: entry.declaredMcpServerNames.map(identifier),
        };
      }),
      skills: inventory.skills.map((/** @type {{qualifiedName?: unknown, name?: unknown}} */ entry) =>
        identifier(entry?.qualifiedName ?? entry?.name)),
    };
  } catch {
    // The desktop runtime includes profile paths and internal diagnostics in its output.
    return { status: /** @type {const} */ ('failed') };
  }
}

/**
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 * @param {number} [timeout]
 */
export async function checkGrokMcp(ctx, env, timeout = NATIVE_HEALTH_TIMEOUT_MS) {
  const executable = findNativeExecutable(ctx, env, 'grok');
  if (!executable) return { status: /** @type {const} */ ('unavailable') };

  try {
    const stdout = await run(executable, ['mcp', 'doctor', '--json'], nativeOptions(ctx, env, timeout))
      .then((result) => result.stdout, (error) => {
        // Grok exits 1 when a server fails, even when it emits a complete report.
        if (error?.code === 1 && typeof error.stdout === 'string') return error.stdout;
        throw error;
      });
    const data = JSON.parse(stdout);
    if (!Array.isArray(data?.servers)) throw new Error('Expected Grok server diagnostics');
    const mcp = data.servers.map((/** @type {{ name?: unknown, transport?: unknown, healthy?: unknown, checks?: unknown }} */ entry) => {
      if (typeof entry?.name !== 'string' || !/^[a-z0-9_-]{1,200}$/i.test(entry.name) ||
          typeof entry.healthy !== 'boolean' || !Array.isArray(entry.checks)) {
        throw new Error('Invalid Grok server diagnostic');
      }
      const disabled = entry.checks.some((check) => check?.label === 'disabled in config' && check.passed === false);
      const requiresAuth = entry.checks.some((check) => check?.label === 'handshake failed' &&
        check.passed === false && typeof check.detail === 'string' && /\bAuth required\b/i.test(check.detail));
      const discovered = entry.checks.find((check) => check?.passed === true && /^\d+ tools? discovered$/.test(check.label));
      const tools = discovered ? Number.parseInt(discovered.label, 10) : null;
      return {
        name: entry.name,
        transport: typeof entry.transport === 'string' && ['http', 'stdio', 'sse'].includes(entry.transport) ? entry.transport : 'unknown',
        outcome: entry.healthy ? 'healthy' : disabled ? 'disabled' : requiresAuth ? 'requires-auth' : 'failed',
        tools: Number.isSafeInteger(tools) ? tools : null,
      };
    });
    return { status: /** @type {const} */ ('checked'), mcp };
  } catch {
    return { status: /** @type {const} */ ('failed') };
  }
}

/** @param {unknown} value */
function identifier(value) {
  if (typeof value !== 'string' || value.length > 200 || !/^[a-z0-9][a-z0-9._-]*(?::[a-z0-9][a-z0-9._-]*)?$/i.test(value)) {
    throw new Error('Invalid native inventory name');
  }
  return value;
}
