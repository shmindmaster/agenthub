import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, existsSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';
import test from 'node:test';

const skill = fileURLToPath(new URL('../skills/use-coding-agent/', import.meta.url));
const source = readFileSync(join(skill, 'cline/lightweight-chat.js'), 'utf8');
function fixture() {
  const context = vm.createContext({});
  vm.runInContext(source.replace('export default', 'globalThis.plugin ='), context);
  let discovery;
  const plugin = context.plugin;
  plugin.setup({ registerTool(tool) { discovery = tool; } });
  const tools = [discovery,
    { name: 'skills', description: 'Load a local skill' },
    { name: 'run_commands', description: 'Run terminal commands', execute() { throw Error('Must never execute during discovery'); } },
    { name: 'read_files', description: 'Read local files' },
    { name: 'linear__list_agent_skills', description: 'List agent skills in Linear' },
    ...Array.from({ length: 10 }, (_, i) => ({ name: `search_${i}`, description: 'Search indexed documents' }))];
  const request = (options = {}, available = tools) => plugin.hooks.beforeModel({ request: { tools: available, options } });
  const names = () => Array.from(request().tools, tool => tool.name);
  plugin.hooks.beforeRun();
  request(); // Native lifecycle populates the catalog before a tool can be called.
  return { plugin, discovery, tools, request, names };
}

test('plain turns start with discovery only; loading preserves native tool identity and resets next turn', async () => {
  const f = fixture();
  assert.deepEqual(f.names(), ['find_tools']);
  await f.discovery.execute({ query: 'terminal commands' });
  assert.deepEqual(f.names(), ['find_tools', 'run_commands']);
  assert.equal(f.request().tools[1], f.tools[2]);
  f.plugin.hooks.beforeRun();
  assert.deepEqual(f.names(), ['find_tools']);
});

test('skill lookup selects local skills; unknown names fall back to capability search', async () => {
  const f = fixture();
  await f.discovery.execute({ query: 'skills agent-browser' });
  assert.deepEqual(f.names(), ['find_tools', 'skills']);
  f.plugin.hooks.beforeRun();
  const result = await f.discovery.execute({ query: 'read local files', names: ['guessed_tool'], limit: 1 });
  assert.deepEqual(f.names(), ['find_tools', 'read_files']);
  assert.deepEqual(Array.from(result.unavailableNames), ['guessed_tool']);
  assert.equal(f.request({}, [f.discovery]).tools.length, 1, 'A removed native tool must not remain callable');
});

test('discovery limits schema growth and never invents or executes a tool', async () => {
  const f = fixture();
  assert.equal((await f.discovery.execute({ query: 'search indexed documents' })).loaded.length, 3);
  f.plugin.hooks.beforeRun();
  assert.equal((await f.discovery.execute({ query: 'search indexed documents', limit: 999 })).loaded.length, 5);
  f.plugin.hooks.beforeRun();
  assert.equal((await f.discovery.execute({ query: '', names: ['missing'] })).loaded.length, 0);
  assert.deepEqual(f.names(), ['find_tools']);
});

test('low reasoning is a default; explicit reasoning, off and budgets remain intact', () => {
  const f = fixture();
  assert.equal(f.request().options.reasoningEffort, 'low');
  for (const effort of ['none', 'medium', 'high', 'xhigh']) {
    assert.equal(f.request({ reasoningEffort: effort }).options.reasoningEffort, effort);
  }
  assert.equal(f.request({ thinking: false }).options.reasoningEffort, undefined);
  assert.equal(f.request({ thinkingBudgetTokens: 1024 }).options.reasoningEffort, undefined);
  assert.equal(f.request({ autoApproveTools: false }).options.autoApproveTools, false);
});

test('manual installer detects missing and changed files, repairs and reads back without host startup', () => {
  const home = mkdtempSync(join(tmpdir(), 'cline-plugin-fixture-'));
  const destination = join(home, 'plugins/lightweight-chat.js');
  const run = (...args) => spawnSync('pwsh', ['-NoProfile', '-File', join(skill, 'Install-ClineToolDiscovery.ps1'), '-ClineHome', home, ...args], { encoding: 'utf8', windowsHide: true });
  try {
    assert.equal(run().status, 1);
    assert.equal(existsSync(destination), false, 'Audit must not write');
    assert.equal(run('-Apply').status, 0);
    assert.equal(readFileSync(destination, 'utf8'), source);
    assert.equal(run().status, 0);
    writeFileSync(destination, '// synthetic incompatible update\n');
    assert.equal(run().status, 1, 'Audit must fail on real drift');
    assert.equal(run('-Apply').status, 0);
    assert.equal(readFileSync(destination, 'utf8'), source);
  } finally { rmSync(home, { recursive: true, force: true }); }
});
