// @ts-check

import { execFile } from 'node:child_process';
import { accessSync, constants, statSync } from 'node:fs';
import { delimiter, isAbsolute, join } from 'node:path';
import { promisify } from 'node:util';

const run = promisify(execFile);
const DEADLINE_MS = 10_000;

/**
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 */
export async function inspectDevin(ctx, env) {
  const windows = ctx.platform === 'windows';
  if (ctx.platform !== (process.platform === 'win32' ? 'windows' : process.platform)) {
    return { status: /** @type {const} */ ('unavailable') };
  }
  const baseName = windows ? 'devin.exe' : 'devin';
  const pathDirs = (env.PATH ?? env.Path ?? '').split(delimiter).filter(isAbsolute);
  const candidates = pathDirs.map((dir) => join(dir, baseName));
  if (windows) candidates.unshift(join(ctx.localData, 'Microsoft', 'WinGet', 'Links', baseName));
  const executable = candidates.find((path) => {
    try {
      if (!isAbsolute(path) || !statSync(path).isFile()) return false;
      if (!windows) accessSync(path, constants.X_OK);
      return true;
    } catch {
      return false;
    }
  });
  if (!executable) return { status: /** @type {const} */ ('unavailable') };

  try {
    const read = async (/** @type {string} */ group) => {
      const { stdout } = await run(executable, [group, 'list', '--json', '--process-model', 'in-process'], {
        cwd: ctx.home,
        env,
        encoding: 'utf8',
        timeout: DEADLINE_MS,
        maxBuffer: 4 * 1024 * 1024,
        windowsHide: true,
      });
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

/** @param {unknown} value */
function identifier(value) {
  if (typeof value !== 'string' || !/^[a-z0-9._:/-]{1,200}$/i.test(value)) {
    throw new Error('Invalid Devin inventory name');
  }
  return value;
}
