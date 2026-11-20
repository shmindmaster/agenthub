import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync } from 'node:fs';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { createPathContext } from '../src/doctor/hosts.js';
import { openAutoClawRuntime, openZCodeRuntime } from '../src/doctor/native.js';

const parallel = {
  name: 'parallel-agent-skills',
  repo: 'parallel-web/parallel-agent-skills',
  plugins: [{ name: 'parallel' }],
};
const json = (file) => JSON.parse(readFileSync(file, 'utf8'));
const sourcePaths = ['.claude-plugin', 'packages'];
const nativeTimeout = 120_000;
const key = (path) => resolve(path).toLowerCase();

function run(command, argv, cwd) {
  try {
    return execFileSync(command, argv, { cwd, windowsHide: true, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch {
    throw new Error(`Could not prepare the tracked AutoClaw marketplace (${command}).`);
  }
}

function localMarketplace(root, base, disabled) {
  if (key(run('git', ['rev-parse', '--show-toplevel'], root)) !== key(root)) {
    throw new Error('An AutoClaw marketplace requires its own Git checkout.');
  }
  const { name, plugins } = json(join(root, '.claude-plugin', 'marketplace.json'));
  if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) throw new Error('Invalid AutoClaw marketplace name.');
  const trees = run('git', ['rev-parse', ...sourcePaths.map((path) => `HEAD:${path}`)], root).split(/\s+/);
  if (trees.length !== sourcePaths.length || !trees.every((tree) => /^[a-f0-9]{40}$/.test(tree))) {
    throw new Error('Invalid AutoClaw marketplace tree.');
  }
  const directory = join(base, name, trees.join('-'), 'marketplace');
  return {
    name, root, directory,
    plugins: plugins.map(({ name: id, source }) => {
      if (!/^\.\/packages\/[a-z0-9][a-z0-9-]*$/.test(source) || !/^[a-z0-9][a-z0-9-]*$/.test(id)) {
        throw new Error('Invalid AutoClaw plugin source.');
      }
      const { name: manifestName, version } = json(join(root, source, '.claude-plugin', 'plugin.json'));
      if (manifestName !== id || typeof version !== 'string') throw new Error('Invalid AutoClaw plugin manifest.');
      return { name: id, capability: basename(source), version, disabled: disabled.has(basename(source)) };
    }),
  };
}

function stageMarketplace(market) {
  const target = dirname(market.directory);
  if (existsSync(market.directory)) return;
  const parent = dirname(target);
  mkdirSync(parent, { recursive: true });
  const temporary = mkdtempSync(join(parent, 'staging-'));
  try {
    const archive = join(temporary, 'tracked.tar');
    const contents = join(temporary, 'marketplace');
    mkdirSync(contents);
    run('git', ['archive', '--format=tar', `--output=${archive}`, 'HEAD', '--', ...sourcePaths], market.root);
    run('tar', ['-xf', archive, '-C', contents], temporary);
    rmSync(archive);
    renameSync(temporary, target);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

function sourceStatus(market, entry, base) {
  if (!entry) return 'missing';
  const { source } = entry;
  if (market.repo) return source?.source === 'github' && source.repo === market.repo ? 'current' : 'blocked';
  if (source?.source !== 'directory' || typeof source.path !== 'string') return 'blocked';
  if (key(market.directory) === key(source.path)) return 'current';
  if (key(market.root) === key(source.path)) return 'drift';
  const suffix = relative(key(join(base, market.name)), key(source.path)).replaceAll('\\', '/');
  return /^[a-f0-9]{40}-[a-f0-9]{40}\/marketplace$/.test(suffix) ? 'drift' : 'blocked';
}

export async function syncAutoClawPlugins(runtime, markets, base, { apply, plugin, host = 'autoclaw' } = {}) {
  const selected = markets.map((market) => ({
    ...market,
    plugins: market.plugins.filter((row) => !plugin || [row.name, row.capability, `${row.name}@${market.name}`].includes(plugin)),
  })).filter((market) => market.plugins.length);
  if (!selected.length) throw new Error('No AutoClaw plugins matched the filter.');

  const readMarkets = async () => {
    const data = await runtime.invoke(['plugins', 'marketplace', 'list']);
    if (!Array.isArray(data)) throw new Error('Invalid native marketplace inventory.');
    return data;
  };
  const changes = [];
  const before = await readMarkets();
  const checkSources = (entries) => selected.map((market) => ({
    name: market.name,
    status: sourceStatus(market, entries.find((entry) => entry.name === market.name), base),
  }));
  const prior = checkSources(before);
  if (apply && prior.some(({ status }) => status === 'blocked')) throw new Error('An AutoClaw marketplace has a different source owner.');
  if (apply) for (const [index, market] of selected.entries()) {
    if (prior[index].status !== 'current') {
      if (market.directory) stageMarketplace(market);
      const source = market.repo ?? `./${basename(market.directory)}`;
      const cwd = market.directory ? dirname(market.directory) : undefined;
      await runtime.invoke(['plugins', 'marketplace', 'add', source, '--scope', 'user'], cwd, nativeTimeout);
      changes.push({ marketplace: market.name, action: 'register' });
    } else if (market.repo) {
      await runtime.invoke(['plugins', 'marketplace', 'update', market.name], undefined, nativeTimeout);
    }
  }
  const marketplaces = apply ? checkSources(await readMarkets()) : prior;
  if (apply && marketplaces.some(({ status }) => status !== 'current')) throw new Error('AutoClaw marketplace registration did not converge.');

  const inventory = async () => {
    const data = await runtime.invoke(['plugins', 'list', '--available']);
    if (!Array.isArray(data?.installed) || !Array.isArray(data?.available)) throw new Error('Invalid native plugin inventory.');
    return data;
  };
  const readRows = ({ installed, available }) => selected.flatMap((market, index) => market.plugins.map((plugin) => {
    const id = `${plugin.name}@${market.name}`;
    const observed = installed.find((entry) => entry.id === id);
    const expected = plugin.version ?? available.find((entry) => entry.id === id)?.version ?? null;
    let status = 'current';
    if (!expected || marketplaces[index].status === 'blocked') status = 'blocked';
    else if (!observed) status = 'missing';
    else if (observed.version !== expected || (plugin.disabled && observed.enabled !== false)) status = 'drift';
    return {
      host, plugin: id, expected, observed: observed?.version ?? null,
      enabled: observed?.enabled ?? null, expectedEnabled: plugin.disabled ? false : null, status,
    };
  }));
  let mappings = readRows(await inventory());
  if (apply) {
    if (mappings.some(({ status }) => status === 'blocked')) throw new Error('An AutoClaw plugin could not be verified in its marketplace.');
    for (const row of mappings) {
      if (row.status === 'current') continue;
      if (row.observed !== row.expected) {
        const action = row.observed ? 'update' : 'install';
        await runtime.invoke(['plugins', action, row.plugin, '--scope', 'user'], undefined, nativeTimeout);
        changes.push({ plugin: row.plugin, action });
      }
      if (row.expectedEnabled === false) {
        await runtime.invoke(['plugins', 'disable', row.plugin, '--scope', 'user']);
        changes.push({ plugin: row.plugin, action: 'disable' });
      }
    }
    mappings = readRows(await inventory());
  }
  return { mode: apply ? 'Apply' : 'Audit', marketplaces, mappings, changes };
}

async function main() {
  const { values } = parseArgs({ options: {
    root: { type: 'string' }, overlay: { type: 'string' }, account: { type: 'string' },
    host: { type: 'string', default: 'autoclaw' },
    plugin: { type: 'string' }, apply: { type: 'boolean' }, json: { type: 'boolean' },
  } });
  if (!['autoclaw', 'zcode'].includes(values.host)) throw new Error('Unsupported native marketplace host.');
  if (values.host === 'autoclaw' && (values.apply || values.overlay) && !values.account) {
    throw new Error('AutoClaw apply or private overlay audit requires an explicit account.');
  }
  if (values.host === 'zcode' && values.account) throw new Error('Standalone ZCode uses the invoking Windows profile.');
  const ctx = createPathContext({});
  const runtime = values.host === 'zcode'
    ? openZCodeRuntime(ctx, process.env)
    : openAutoClawRuntime(ctx, process.env, values.account);
  if (runtime.status !== 'ready') throw new Error(`${values.host} runtime status is ${runtime.status}.`);
  const base = join(ctx.localData, 'AgentHub', 'runtime', 'autoclaw-marketplaces');
  const { mcpServers } = json(join(values.root, 'registry', 'mcps.json'));
  const disabled = new Set(mcpServers.filter((server) => server.startupEnabled === false &&
    server.activationMode === 'on-demand-local' && server.owner?.type === 'capability').map((server) => server.owner.id));
  const roots = [values.root];
  if (values.overlay) roots.push(values.overlay);
  if (values.apply) for (const root of roots) {
    const dirty = run('git', ['status', '--porcelain', '--', ...sourcePaths], root);
    if (dirty) throw new Error('Apply requires committed marketplace sources.');
  }
  const markets = [...roots.map((root) => localMarketplace(root, base, disabled)), parallel];
  if (new Set(markets.map(({ name }) => name)).size !== markets.length) throw new Error('AutoClaw marketplace names must be distinct.');
  const result = await syncAutoClawPlugins(runtime, markets, base, values);
  if (values.json) console.log(JSON.stringify(result, null, 2));
  else {
    console.table(result.marketplaces);
    console.table(result.mappings);
    if (result.changes.length) console.table(result.changes);
  }
  if (values.apply && result.mappings.some((row) => row.status !== 'current')) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error instanceof SyntaxError ? 'Invalid AutoClaw marketplace data.' : error.message);
    process.exitCode = 1;
  });
}
