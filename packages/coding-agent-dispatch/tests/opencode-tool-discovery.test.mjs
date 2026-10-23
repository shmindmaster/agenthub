import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../skills/use-coding-agent/opencode/lightweight-chat.js', import.meta.url), 'utf8');
async function fixture() {
  const sandbox = vm.createContext({});
  vm.runInContext(source.replace('export default', 'globalThis.plugin ='), sandbox);
  const hooks = {};
  let discovery;
  const removedSkills = [];
  await sandbox.plugin.setup({
    skill: { transform(callback) { callback({ remove(id) { removedSkills.push(id); } }); } },
    tool: { transform(callback) { callback({ add(tool) { discovery = tool; } }); } },
    session: { hook(name, callback) { hooks[name] = callback; } }
  });
  const tools = Object.fromEntries([
    ['find_tools', discovery], ['read', { description: 'Read local files', input: { type: 'object' } }],
    ['shell', { description: 'Run terminal shell commands' }], ['skill', { description: 'Load skill' }],
    ['execute', { description: 'Execute JavaScript Code Mode' }]
  ]);
  const policy = '# OpenCode Global Instructions\nKeep all approvals and private boundaries.\n';
  const text = '# Code Mode\nNative catalog and exact signatures\n\n<mcp_instructions><server name="linear">Original instructions</server></mcp_instructions>\n<available_skills><skill><id>browser-test</id><name>Browser Test</name><description>Browser automation and testing</description></skill></available_skills>\n' + policy;
  const request = (sessionID = 'one', available = tools, system = text) => {
    const event = { sessionID, tools: { ...available }, system: [{ type: 'text', text: system }], options: { reasoning: 'explicit' }, messages: [{ role: 'user', content: 'untouched' }] };
    hooks.context(event);
    return event;
  };
  const search = async (query, sessionID = 'one', extra = {}) => JSON.parse((await discovery.execute({ query, ...extra }, { sessionID })).content);
  return { hooks, tools, request, search, policy, text, removedSkills };
}

test('plain chat defers catalogs, preserving complete policy, user text and provider options', async () => {
  const f = await fixture();
  const event = f.request();
  assert.deepEqual(Object.keys(event.tools), ['find_tools']);
  assert.ok(event.system[0].text.endsWith(f.policy));
  assert.ok(!event.system[0].text.includes('Native catalog'));
  assert.ok(!event.system[0].text.includes('Original instructions'));
  assert.ok(!event.system[0].text.includes('<skill>'));
  assert.deepEqual(event.messages, [{ role: 'user', content: 'untouched' }]);
  assert.equal(event.options.reasoning, 'explicit');
});
test('tool selection retains native schema identity and resets for each user turn', async () => {
  const f = await fixture(); f.request();
  await f.search('read files', 'one', { names: ['read'], limit: 1 });
  assert.equal(f.request().tools.read, f.tools.read);
  f.hooks.prompt({ sessionID: 'one' });
  assert.deepEqual(Object.keys(f.request().tools), ['find_tools']);
});
test('app discovery restores native Code Mode and exact server guidance only when needed', async () => {
  const f = await fixture(); f.request();
  await f.search('Linear current user');
  const event = f.request();
  assert.equal(event.tools.execute, f.tools.execute);
  assert.ok(event.system[0].text.includes('Native catalog and exact signatures'));
  assert.ok(event.system[0].text.includes('Original instructions'));
  assert.ok(event.system[0].text.endsWith(f.policy));
});
test('skills remain searchable and loadable without exposing forbidden skills or leaking sessions', async () => {
  const f = await fixture(); f.request();
  const result = await f.search('skills browser automation');
  assert.equal(result.skills[0].name, 'browser-test');
  assert.equal(f.request().tools.skill, f.tools.skill);
  assert.deepEqual(Object.keys(f.request('two').tools), ['find_tools']);
  assert.equal((await f.search('forbidden skill')).skills.length, 0);
});
test('removed tools cannot be reintroduced and unrelated headings survive deferral', async () => {
  const f = await fixture(); f.request();
  await f.search('shell', 'one', { names: ['shell'] });
  const { shell, ...remaining } = f.tools;
  assert.ok(!f.request('one', remaining).tools.shell);
  const event = f.request('three', f.tools, '# Code Mode\nNative catalog\n\n# Project policy\nNever remove this.');
  assert.ok(event.system[0].text.endsWith('# Project policy\nNever remove this.'));
});

test('OpenCode prunes incompatible and low-value skills while retaining core capabilities', async () => {
  const f = await fixture();
  assert.equal(f.removedSkills.length, 14);
  for (const id of ['built-in-browser', 'chrome-browser', 'computer-use', 'comedy-writer', 'sarosh-voice'])
    assert.ok(f.removedSkills.includes(id));
  for (const id of ['sarosh-communication', 'use-playwright-cli', 'use-playwright-test', 'use-repowise', 'opportunity-engine', 'media-studio'])
    assert.ok(!f.removedSkills.includes(id));
});

test('exact file discovery does not return unrelated skills and server instructions reset next turn', async () => {
  const f = await fixture(); f.request();
  const result = await f.search('native read file tool', 'one', { names: ['read'] });
  assert.equal(result.skills.length, 0);
  assert.deepEqual(Array.from(f.request().tools ? Object.keys(f.request().tools) : []), ['find_tools', 'read']);
  await f.search('Linear app');
  assert.ok(f.request().system[0].text.includes('Original instructions'));
  f.hooks.prompt({ sessionID: 'one' });
  assert.ok(!f.request().system[0].text.includes('Original instructions'));
});
