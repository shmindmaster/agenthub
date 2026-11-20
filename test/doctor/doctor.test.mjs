import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { bindPath, buildHostCatalog, createPathContext } from '../../src/doctor/hosts.js';
import { isReference, normalizeServer, readMcpSource, unpinnedPackage } from '../../src/doctor/mcp.js';
import { probeOne, runDoctor } from '../../src/doctor/doctor.js';
import { renderText } from '../../src/doctor/render.js';
import { fake, makeHome, platform, roamingRoot, snapshot } from './fixtures.mjs';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const cli = join(repoRoot, 'scripts', 'agenthub-cli.mjs');
const homes = [];
after(() => homes.forEach((h) => h.cleanup()));
const newHome = () => {
  const h = makeHome();
  homes.push(h);
  return h;
};
const codes = (report) => report.findings.map((f) => f.code);
const find = (report, code, subject) => report.findings.filter((f) => f.code === code && (!subject || f.subject === subject));

test('AutoClaw native inventory uses the bundled runtime in the single initialized account', { skip: platform !== 'windows' }, async () => {
  const h = newHome();
  const accountRoot = 'AppData/Roaming/AutoClaw-oversea-official/accounts';
  const home = name => `${accountRoot}/${name}/runtime/zcode-runtime/home`;
  const options = {
    env: h.env({ USERPROFILE: h.home, HOME: 'synthetic-home', ZCODE_HOME: 'synthetic-override' }),
    hosts: ['autoclaw'], native: true, registry: false,
  };
  const runNative = async () => (await runDoctor(options)).native.autoclaw;
  assert.equal((await runNative()).status, 'unavailable');

  const plugin = { id: 'browser@market', enabled: true, version: '1.3.7', declaredMcpServerNames: ['search'] };
  h.write('AppData/Local/Programs/AutoClaw2/resources/vendor/zcode/zcode.cjs', `
    const assert = require('node:assert/strict');
    const { join } = require('node:path');
    assert.equal(process.env.HOME, undefined);
    assert.equal(process.env.ZCODE_HOME, undefined);
    assert.equal(process.env.USERPROFILE, process.cwd());
    assert.equal(process.cwd(), ${JSON.stringify(join(h.home, ...home('account-id').split('/')))});
    const [group, ...args] = process.argv.slice(2);
    assert.deepEqual(args, ['list', '--json', '--cwd', process.cwd()]);
    assert.ok(['plugins', 'skills'].includes(group));
    console.log(JSON.stringify(group === 'plugins'
      ? [{ ...${JSON.stringify(plugin)}, dataPath: process.cwd(), diagnostics: ['synthetic-sensitive-output'] }]
      : { skills: [{ name: 'built-in' }, { name: 'browse', qualifiedName: 'browser:browse' }] }));
  `);
  assert.equal((await runNative()).status, 'no-account');
  h.write(`${home('account-id')}/.zcode/cli/fixture.json`, {});
  h.write(`${accountRoot}/uninitialized/placeholder.json`, {});
  assert.deepEqual(await runNative(), {
    status: 'listed',
    plugins: [{ id: plugin.id, version: plugin.version, enabled: true, declaredMcpServers: ['search'] }],
    skills: ['built-in', 'browser:browse'],
  });
  assert.match(renderText(await runDoctor(options)), /AutoClaw: 1 plugins \(1 enabled\), 2 skills/);
  h.write(`${home('second-account')}/.zcode/cli/fixture.json`, {});
  assert.equal((await runNative()).status, 'ambiguous-account');
});

test('Cline Doctor reads native nested transports and flat entries without exposing credentials', async () => {
  const h = newHome();
  const syntheticKey = 'sk-' + 'a'.repeat(40);
  h.write('.cline/data/settings/cline_mcp_settings.json', {
    mcpServers: {
      local: { transport: { type: 'stdio', command: 'node', args: ['server.js'] } },
      remote: {
        transport: { type: 'streamableHttp', url: 'https://example.test/sse', headers: { Authorization: 'Bearer ' + syntheticKey } },
        disabled: true,
        oauth: { clientId: 'fixture' },
      },
      flat: { type: 'streamableHttp', url: 'https://example.test/mcp' },
      legacy: { transportType: 'sse', url: 'https://example.test/events' },
    },
  });
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const { servers } = report.hosts.find(({ id }) => id === 'cline').mcp;
  assert.deepEqual(servers.map(({ name, transport, enabled }) => [name, transport, enabled]), [
    ['flat', 'http', true], ['legacy', 'sse', true], ['local', 'stdio', true], ['remote', 'http', false],
  ]);
  assert.equal(servers.find(({ name }) => name === 'local').fingerprint, 'stdio:node server.js');
  assert.equal(servers.find(({ name }) => name === 'remote').authConfigured, true);
  assert.doesNotMatch(JSON.stringify(report), new RegExp(syntheticKey));
});

test('Cline Doctor reports the separate VS Code Insiders MCP file', async () => {
  const h = newHome();
  const settings = join(roamingRoot(h.home), 'Code - Insiders/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json');
  h.write('.cline/data/settings/cline_mcp_settings.json', {
    mcpServers: { cli: { type: 'streamableHttp', url: 'https://cli.example.test/mcp' } },
  });
  h.writeAbs(settings, {
    mcpServers: { editor: { type: 'streamableHttp', url: 'https://editor.example.test/mcp', disabled: true } },
  });
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false, hosts: ['cline'] });
  const { sources, servers } = report.hosts[0].mcp;
  assert.equal(sources.filter(({ exists }) => exists).length, 2);
  assert.deepEqual(servers.map(({ name, enabled }) => [name, enabled]), [['cli', true], ['editor', false]]);
});

test('ZCode Doctor reads native user MCP settings without requiring agent-wide registrations', async () => {
  const h = newHome();
  h.write('.agents/skills/shared/SKILL.md', 'Shared skill fixture');
  const options = { home: h.home, env: h.env(), registry: repoRoot, hosts: ['zcode'] };
  assert.equal((await runDoctor(options)).hosts.length, 0);
  h.write('.zcode/cli/config.json', {
    mcp: { servers: {
      parallel: { type: 'http', url: 'https://example.test/mcp', enabled: true },
      compatible: { type: 'remote', url: 'https://example.test/mcp', enable: false },
      local: { command: 'node', args: [], environment: { MODE: 'fixture' } },
      importedCodex: { url: 'https://example.test/mcp', http_headers_helper: 'fixture' },
      importedRuntime: { command: 'node', env_vars: ['FIXTURE'] },
      servers: { remote: { type: 'remote', url: 'https://example.test/mcp' } },
    } },
  });
  const report = await runDoctor(options);
  assert.deepEqual(report.hosts[0].mcp.servers.map(({ name, transport, enabled }) => [name, transport, enabled]),
    [['compatible', 'http', false], ['local', 'stdio', true], ['parallel', 'http', true]]);
  const rejected = report.findings.find(({ code }) => code === 'MCP_NATIVE_ENTRY_IGNORED');
  assert.match(rejected.message, /importedCodex, importedRuntime, servers/);
  assert.ok(!codes(report).includes('REGISTRY_MISSING'));
});

test('standalone ZCode native inventory uses the Windows user profile', { skip: platform !== 'windows' }, async () => {
  const h = newHome();
  h.write('AppData/Local/Programs/ZCode/resources/glm/zcode.cjs', `
    const assert = require('node:assert/strict');
    assert.equal(process.env.ZCODE_HOME, undefined);
    assert.equal(process.env.USERPROFILE, ${JSON.stringify(h.home)});
    assert.equal(process.cwd(), process.env.USERPROFILE);
    const data = process.argv[2] === 'plugins'
      ? [{ id: 'parallel@parallel-agent-skills', enabled: true, version: '0.12.0', declaredMcpServerNames: ['parallel'] }]
      : { skills: [{ qualifiedName: 'parallel:search' }] };
    console.log(JSON.stringify(data));
  `);
  const report = await runDoctor({
    env: h.env({ USERPROFILE: h.home, ZCODE_HOME: 'synthetic-override' }),
    hosts: ['zcode'], native: true, registry: false,
  });
  assert.deepEqual(Object.keys(report.native), ['zcode']);
  assert.deepEqual(report.native.zcode.skills, ['parallel:search']);
  assert.deepEqual(report.native.zcode.plugins[0].declaredMcpServers, ['parallel']);
  assert.match(renderText(report), /ZCode: 1 plugins \(1 enabled\), 1 skills/);
});

test('OpenCode Doctor distinguishes a server named servers from a nested server map', () => {
  const h = newHome();
  const legacy = { type: 'remote', url: 'https://example.test/mcp' };
  const local = { type: 'local', command: ['node', 'server.js'] };
  const path = join(h.home, '.config/opencode/opencode.json');
  const read = (mcp) => {
    h.write('.config/opencode/opencode.json', { mcp });
    return readMcpSource({ path, format: 'jsonc', key: 'mcp', dialect: 'opencode' }).servers
      .map(({ name, transport }) => [name, transport]);
  };

  assert.deepEqual(read({ servers: legacy }), [['servers', 'http']]);
  assert.deepEqual(read({ servers: { type: local, url: legacy } }), [['type', 'stdio'], ['url', 'http']]);
  assert.deepEqual(read({ flat: legacy, servers: { nested: local } }), [['flat', 'http'], ['nested', 'stdio']]);
});

// ---------------------------------------------------------------------------
// Path binding
// ---------------------------------------------------------------------------

test('path templates bind to each OS layout and Windows-only AppData pins are dropped elsewhere', () => {
  const win = createPathContext({ platform: 'windows', home: 'C:\\Users\\dev', env: {}, homeOverridden: true });
  assert.equal(bindPath('{roamingConfig}/Code/User/mcp.json', win), 'C:\\Users\\dev\\AppData\\Roaming\\Code\\User\\mcp.json');
  assert.equal(bindPath('{userHome}/AppData/Roaming/warp', win), 'C:\\Users\\dev\\AppData\\Roaming\\warp');

  const mac = createPathContext({ platform: 'darwin', home: '/Users/dev', env: {} });
  assert.equal(bindPath('{roamingConfig}/Code/User/mcp.json', mac), '/Users/dev/Library/Application Support/Code/User/mcp.json');
  assert.equal(bindPath('{userHome}/AppData/Roaming/warp', mac), null);

  const linux = createPathContext({ platform: 'linux', home: '/home/dev', env: { XDG_CONFIG_HOME: '/xdg' } });
  assert.equal(bindPath('{roamingConfig}/devin/config.json', linux), '/xdg/devin/config.json');
  const linuxOverride = createPathContext({ platform: 'linux', home: '/tmp/h', env: { XDG_CONFIG_HOME: '/xdg' }, homeOverridden: true });
  assert.equal(bindPath('{roamingConfig}/devin/config.json', linuxOverride), '/tmp/h/.config/devin/config.json');

  assert.equal(bindPath('C:/Users/someone/bin/codex.cmd', win), null, 'recorded absolute paths are one machine, not a template');
});

test('the catalog covers every host in registry/agents.json plus Claude Desktop and VS Code', () => {
  const agents = JSON.parse(readFileSync(join(repoRoot, 'registry', 'agents.json'), 'utf8'));
  const ids = [...agents.activeAgents, ...agents.inactiveAgents].map((a) => a.id);
  const ctx = createPathContext({ platform: 'linux', home: '/home/dev', env: {} });
  const catalog = buildHostCatalog(ctx).map((h) => h.id);
  for (const id of ids) assert.ok(catalog.includes(id), `missing ${id}`);
  assert.ok(catalog.includes('claude-desktop') && catalog.includes('vscode'));
});

test('hosts whose layout differs by OS resolve to their documented macOS and Linux locations', () => {
  const host = (ctx, id) => buildHostCatalog(ctx).find((h) => h.id === id);
  const mac = createPathContext({ platform: 'darwin', home: '/Users/dev', env: {} });
  const linux = createPathContext({ platform: 'linux', home: '/home/dev', env: {} });
  const win = createPathContext({ platform: 'windows', home: 'C:\\Users\\dev', env: {}, homeOverridden: true });

  assert.ok(host(mac, 'devin').markers.includes('/Users/dev/.config/devin/config.json'), 'Devin is ~/.config/devin on macOS');
  assert.ok(host(linux, 'devin').markers.includes('/home/dev/.config/devin/config.json'));
  assert.ok(host(win, 'devin').markers.includes('C:\\Users\\dev\\AppData\\Roaming\\devin\\config.json'));
  assert.ok(host(win, 'autoclaw').markers.includes('C:\\Users\\dev\\AppData\\Local\\Programs\\AutoClaw2\\AutoClaw2.exe'));
  assert.ok(host(win, 'grokbot').markers.includes('C:\\Users\\dev\\AppData\\Local\\Programs\\Grok Bot\\Grok Bot.exe'));
  assert.ok(host(win, 'manus').markers.includes('C:\\Users\\dev\\AppData\\Local\\Packages\\ManusAI.Manus_vajzd2mq3s8wj'));
  assert.deepEqual(host(linux, 'manus').markers, []);

  assert.ok(host(mac, 'warp').markers.includes('/Users/dev/.warp'), 'Warp config home is ~/.warp on macOS');
  assert.ok(host(linux, 'warp').markers.includes('/home/dev/.config/warp-terminal'));

  assert.ok(host(mac, 'antigravity-desktop').markers.includes('/Users/dev/Library/Application Support/Antigravity'));
  assert.ok(host(linux, 'antigravity-desktop').markers.includes('/home/dev/.config/Antigravity'));
  assert.ok(host(mac, 'cursor').markers.includes('/Users/dev/Library/Application Support/Cursor/User/settings.json'));
  assert.ok(host(linux, 'vscode-insiders').markers.includes('/home/dev/.config/Code - Insiders/User/settings.json'));

  assert.deepEqual(host(mac, 'claude').executables, ['claude']);
  assert.deepEqual(host(linux, 'cursor-agent').executables, ['cursor-agent']);
});

// ---------------------------------------------------------------------------
// One fixture home per host: every MCP dialect and location is read
// ---------------------------------------------------------------------------

test('reads the MCP config of every host from its native location and format', async () => {
  const h = newHome();
  h.command('node');
  const stdio = { command: 'node', args: ['server.js'] };
  const roaming = roamingRoot(h.home);
  const writes = {
    claude: () => h.write('.claude.json', { mcpServers: { shared: stdio } }),
    codex: () => h.write('.codex/config.toml', '[mcp_servers.shared]\ncommand = "node"\nargs = ["server.js"]\n'),
    grok: () => h.write('.grok/config.toml', '[mcp_servers.shared]\ncommand = "node"\nargs = ["server.js"]\n'),
    opencode: () => h.write('.config/opencode/opencode.json', { mcp: { shared: { type: 'local', command: ['node', 'server.js'] } } }),
    copilot: () => h.write('.copilot/mcp-config.json', { mcpServers: { shared: stdio } }),
    antigravity: () => h.write('.gemini/config/mcp_config.json', { mcpServers: { shared: stdio } }),
    warp: () => h.write('.warp/.mcp.json', { mcpServers: { shared: stdio } }),
    cline: () => h.write('.cline/data/settings/cline_mcp_settings.json', { mcpServers: { shared: stdio } }),
    cursor: () => h.write('.cursor/mcp.json', '// Cursor allows comments\n{ "mcpServers": { "shared": { "command": "node", "args": ["server.js"], }, }, }'),
    amp: () => h.write('.config/amp/settings.json', { 'amp.mcpServers': { shared: stdio } }),
    // Devin keeps user config in %APPDATA%\devin on Windows and the XDG path ~/.config/devin elsewhere.
    devin: () => h.writeAbs(join(platform === 'windows' ? roaming : join(h.home, '.config'), 'devin', 'mcp_config.json'), { mcpServers: { shared: stdio } }),
    factory: () => h.write('.factory/mcp.json', { mcpServers: { shared: stdio } }),
    'vscode-insiders': () => h.writeAbs(join(roaming, 'Code - Insiders', 'User', 'mcp.json'), { servers: { shared: { type: 'stdio', ...stdio } } }),
    windsurf: () => h.write('.codeium/windsurf/mcp_config.json', { mcpServers: { shared: stdio } }),
    'claude-desktop': () => h.writeAbs(join(roaming, 'Claude', 'claude_desktop_config.json'), { mcpServers: { shared: stdio } }),
    vscode: () => h.writeAbs(join(roaming, 'Code', 'User', 'mcp.json'), { servers: { shared: { type: 'stdio', ...stdio } } }),
  };
  for (const write of Object.values(writes)) write();

  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const byId = new Map(report.hosts.map((x) => [x.id, x]));
  for (const id of Object.keys(writes)) {
    const host = byId.get(id);
    assert.ok(host?.detected, `${id} not detected`);
    assert.deepEqual(host.mcp.servers.map((s) => s.name), ['shared'], `${id} servers`);
    assert.equal(host.mcp.servers[0].fingerprint, 'stdio:node server.js', `${id} fingerprint`);
  }
  assert.ok(byId.get('cursor-agent')?.detected, 'Cursor Agent CLI reads ~/.cursor/mcp.json');
  assert.ok(byId.get('opencode-desktop')?.detected, 'OpenCode Desktop shares the OpenCode config');
  assert.deepEqual(find(report, 'DRIFT_SERVER_DIFFERS'), [], 'identical definitions are not drift');
  assert.deepEqual(find(report, 'MCP_COMMAND_NOT_FOUND'), []);
});

test('reports an unreadable config instead of crashing', async () => {
  const h = newHome();
  h.write('.codex/config.toml', '[mcp_servers.x]\ncommand = \n');
  h.write('.cursor/mcp.json', '{ "mcpServers": ');
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const unreadable = find(report, 'MCP_CONFIG_UNREADABLE');
  assert.equal(unreadable.length, 2);
  assert.ok(unreadable.some((f) => /line 2/.test(f.message)));
});

// ---------------------------------------------------------------------------
// Risky MCP configs
// ---------------------------------------------------------------------------

test('flags inline secrets anywhere in an entry and never prints the value', async () => {
  const h = newHome();
  h.command('node');
  h.write('.claude.json', {
    mcpServers: {
      envToken: { command: 'node', args: ['s.js'], env: { GITHUB_TOKEN: fake.github } },
      literalKey: { command: 'node', args: ['s.js'], env: { SERVICE_API_KEY: fake.literal } },
      argToken: { command: 'node', args: ['s.js', '--key', fake.openai] },
      header: { type: 'http', url: 'https://mcp.example.test/mcp', headers: { Authorization: `Bearer ${fake.literal}` } },
      query: { type: 'http', url: `https://mcp.example.test/mcp?api_key=${fake.literal}` },
      referenced: { command: 'node', args: ['s.js'], env: { GITHUB_TOKEN: '${GITHUB_TOKEN}', OTHER_TOKEN: '${env:OTHER}' } },
      placeholder: { command: 'node', args: ['s.js'], env: { API_KEY: '<your-api-key>' } },
    },
  });
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const secretSubjects = find(report, 'MCP_INLINE_SECRET').map((f) => f.subject).sort();
  assert.deepEqual(secretSubjects, ['argToken', 'envToken', 'header', 'literalKey', 'query']);
  assert.ok(find(report, 'MCP_INLINE_SECRET').every((f) => f.severity === 'high'));

  const json = JSON.stringify(report);
  for (const value of Object.values(fake)) assert.ok(!json.includes(value), 'secret value leaked into the JSON report');
  const text = renderText(report, { color: false, verbose: true });
  for (const value of Object.values(fake)) assert.ok(!text.includes(value), 'secret value leaked into the text report');
});

test('flags plaintext remote transport, remote servers without credentials, missing commands and unpinned packages', async () => {
  const h = newHome();
  h.command('npx');
  h.write('.cursor/mcp.json', {
    mcpServers: {
      plain: { url: 'http://mcp.example.test/mcp' },
      anon: { url: 'https://mcp.example.test/mcp' },
      withAuth: { url: 'https://auth.example.test/mcp', headers: { Authorization: 'Bearer ${TOKEN}' } },
      local: { url: 'http://127.0.0.1:7339/mcp' },
      ghost: { command: 'definitely-not-installed-cmd', args: [] },
      unpinned: { command: 'npx', args: ['-y', '@scope/server@latest'] },
      pinned: { command: 'npx', args: ['-y', '@scope/server@1.4.2'] },
      disabled: { command: 'definitely-not-installed-cmd', disabled: true },
    },
  });
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  assert.deepEqual(find(report, 'MCP_PLAINTEXT_REMOTE').map((f) => f.subject), ['plain']);
  assert.deepEqual(find(report, 'MCP_REMOTE_NO_CREDENTIALS').map((f) => f.subject), ['anon']);
  assert.deepEqual(find(report, 'MCP_COMMAND_NOT_FOUND').map((f) => f.subject), ['ghost']);
  assert.deepEqual(find(report, 'MCP_UNPINNED_PACKAGE').map((f) => f.subject), ['unpinned']);
  assert.deepEqual(report.hosts.find((x) => x.id === 'cursor').mcp.servers.length, 8);
});

test('unpinnedPackage understands npx, uvx, pnpm dlx and pinned specs', () => {
  const s = (command, args) => normalizeServer('x', { command, args }, 'generic');
  assert.equal(unpinnedPackage(s('npx', ['-y', 'pkg'])), 'pkg');
  assert.equal(unpinnedPackage(s('npx', ['-y', '@a/b@2.0.0'])), null);
  assert.equal(unpinnedPackage(s('npx.cmd', ['--yes', '@a/b'])), '@a/b');
  assert.equal(unpinnedPackage(s('uvx', ['mcp-server-fetch'])), 'mcp-server-fetch');
  assert.equal(unpinnedPackage(s('uvx', ['--from', 'pkg==1.2.0', 'cmd'])), null);
  assert.equal(unpinnedPackage(s('pnpm', ['dlx', 'tool'])), 'tool');
  assert.equal(unpinnedPackage(s('node', ['server.js'])), null);
  assert.equal(unpinnedPackage(s('npx', ['-y', './local'])), null);
});

test('isReference recognises every host reference syntax', () => {
  for (const v of ['${TOKEN}', '${env:TOKEN}', '${input:token}', '$TOKEN', '{env:TOKEN}', '%TOKEN%', 'Bearer ${TOKEN}']) {
    assert.ok(isReference(v), v);
  }
  assert.ok(!isReference(fake.literal));
});

// ---------------------------------------------------------------------------
// Drift between hosts
// ---------------------------------------------------------------------------

test('reports a server defined differently across hosts, but treats an mcp-remote bridge as the same server', async () => {
  const h = newHome();
  h.command('npx');
  h.command('node');
  h.write('.claude.json', {
    mcpServers: {
      db: { command: 'node', args: ['db.js', '--readonly'] },
      docs: { command: 'npx', args: ['-y', 'mcp-remote@0.1.29', 'https://docs.example.test/mcp'] },
    },
  });
  h.write('.codex/config.toml', '[mcp_servers.db]\ncommand = "node"\nargs = ["db.js"]\n\n[mcp_servers.docs]\nurl = "https://docs.example.test/mcp"\n');
  h.write('.gemini/config/mcp_config.json', { mcpServers: {} });
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const differs = find(report, 'DRIFT_SERVER_DIFFERS');
  assert.deepEqual(differs.map((f) => f.subject), ['db']);
  assert.deepEqual(differs[0].hosts.sort(), ['claude', 'codex']);
  const partial = find(report, 'DRIFT_SERVER_PARTIAL');
  assert.ok(partial.some((f) => f.subject === 'db' && f.hosts.includes('antigravity')));
});

test('skills: lists them, flags missing frontmatter and shadowed copies, and merges shared-library findings', async () => {
  const h = newHome();
  h.write('.claude/settings.json', {});
  h.write('.codex/config.toml', '');
  h.skill('.agents/skills', 'review');
  h.skill('.agents/skills', 'nofront', null);
  h.skill('.codex/skills', 'review', { name: 'review', description: 'Codex copy.' }, 'Different body.');
  h.skill('.claude/skills', 'only-claude');
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const claude = report.hosts.find((x) => x.id === 'claude');
  assert.deepEqual(claude.skills.items.map((s) => s.name).sort(), ['nofront', 'only-claude', 'review']);
  const shadowed = find(report, 'SKILL_SHADOWED');
  assert.equal(shadowed.length, 1);
  assert.deepEqual(shadowed[0].hosts, ['codex']);
  const front = find(report, 'SKILL_FRONTMATTER', 'nofront');
  assert.equal(front.length, 1, 'one finding for a shared skill, not one per host');
  assert.ok(front[0].hosts.includes('claude') && front[0].hosts.includes('codex'));
});

test('instructions: size, AgentHub marker, and divergence between hosts', async () => {
  const h = newHome();
  const body = 'Always run the tests.\n'.repeat(2000);
  h.write('.claude/CLAUDE.md', `# Claude\n\n${body}\n<!-- agenthub:managed -->\n`);
  h.write('.codex/AGENTS.md', `# Codex\n\n${body}`);
  h.write('.gemini/GEMINI.md', '# Gemini\n\nSomething else entirely.\n');
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const claude = report.hosts.find((x) => x.id === 'claude');
  assert.equal(claude.instructions.files[0].managed, true);
  assert.ok(claude.instructions.estimatedTokens > 10000);
  assert.ok(find(report, 'INSTRUCTIONS_LARGE').some((f) => f.hosts.includes('claude')));
  const drift = find(report, 'DRIFT_INSTRUCTIONS');
  assert.equal(drift.length, 1);
  assert.match(drift[0].message, /2 different bodies/);
});

// ---------------------------------------------------------------------------
// Guarantees: read-only, offline, registry comparison, probing on request
// ---------------------------------------------------------------------------

test('doctor writes nothing and makes no network request by default', async () => {
  const h = newHome();
  h.command('node');
  h.write('.claude.json', { mcpServers: { remote: { url: 'https://mcp.example.test/mcp' }, local: { command: 'node' } } });
  h.write('.codex/config.toml', '[mcp_servers.remote]\nurl = "https://mcp.example.test/mcp"\n');
  h.skill('.agents/skills', 'one');
  h.write('.claude/CLAUDE.md', '# x\n');
  const before = snapshot(h.home);
  const realFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    throw new Error('network used');
  };
  try {
    await runDoctor({ home: h.home, env: h.env(), registry: false });
  } finally {
    globalThis.fetch = realFetch;
  }
  assert.equal(calls, 0);
  assert.deepEqual(snapshot(h.home), before);
});

test('compares with an AgentHub registry when one is given', async () => {
  const h = newHome();
  h.write('.claude.json', { mcpServers: { github: { url: 'https://api.example.test/mcp', headers: { Authorization: 'Bearer ${T}' } }, mine: { url: 'https://mine.example.test/mcp' } } });
  h.write('.claude/CLAUDE.md', '# Claude\n\nhand written\n');
  const registry = mkdtempSync(join(tmpdir(), 'agenthub-registry-'));
  homes.push({ cleanup: () => rmSync(registry, { recursive: true, force: true }) });
  mkdirSync(join(registry, 'registry'));
  copyFileSync(join(repoRoot, 'registry', 'agents.json'), join(registry, 'registry', 'agents.json'));
  writeFileSync(
    join(registry, 'registry', 'mcps.json'),
    JSON.stringify({
      migrationAliases: { 'old-docs': 'docs' },
      mcpServers: [
        { id: 'github', scope: 'global-default', transport: 'http', url: 'https://api.example.test/mcp' },
        { id: 'docs', scope: 'global-default', transport: 'http', url: 'https://docs.example.test/mcp' },
        { id: 'codex-only', scope: 'global-default', hosts: ['codex'], transport: 'http', url: 'https://x.test' },
        { id: 'via-plugin', scope: 'global-default', pluginOwnersByHost: { claude: 'plugin' }, transport: 'http', url: 'https://y.test' },
        { id: 'on-demand', scope: 'on-demand-desktop', activationMode: 'on-demand-local', command: 'x' },
      ],
    }),
  );
  const report = await runDoctor({ home: h.home, env: h.env(), registry });
  assert.equal(report.registry.mode, 'agenthub');
  const missing = find(report, 'REGISTRY_MISSING');
  assert.equal(missing.length, 1);
  assert.match(missing[0].message, /: docs\.$/);
  assert.match(find(report, 'REGISTRY_UNKNOWN')[0].message, /mine/);
  assert.equal(find(report, 'REGISTRY_UNMANAGED_INSTRUCTIONS').length, 1);

  const mcpPath = join(registry, 'registry', 'mcps.json');
  h.write('.codex/config.toml', '[mcp_servers.github]\nurl = "https://api.example.test/mcp"\n');
  h.write('.cursor/mcp.json', { mcpServers: { github: { url: 'https://api.example.test/mcp' } } });
  const mcpRegistry = JSON.parse(readFileSync(mcpPath, 'utf8'));
  mcpRegistry.activationPolicy = {
    pluginOnly: { hosts: { claude: { 'old-docs': 'Allowed direct endpoint' }, codex: {}, cursor: { github: 'Allowed direct endpoint' } } },
  };
  mcpRegistry.mcpServers.push({ id: 'other-default', transport: 'http', url: 'https://other.example.test/mcp' });
  writeFileSync(mcpPath, JSON.stringify(mcpRegistry));
  const policyReport = await runDoctor({ home: h.home, env: h.env(), registry });
  assert.deepEqual(find(policyReport, 'REGISTRY_MISSING').map(({ hosts, message }) => [hosts, message]), [
    [['claude'], 'Claude Code is missing 1 MCP server(s) the registry deploys to it: docs.'],
  ]);
});

const initializeResult = JSON.stringify({
  jsonrpc: '2.0', id: 1, result: { protocolVersion: '2025-06-18', serverInfo: { name: 'fixture' }, capabilities: {} },
});

test('--probe-remote sends one unauthenticated initialize per remote server and reports open servers', async () => {
  const h = newHome();
  h.write('.cursor/mcp.json', {
    mcpServers: {
      open: { url: 'https://open.example.test/mcp' },
      locked: { url: 'https://locked.example.test/mcp' },
      authed: { url: 'https://authed.example.test/mcp', headers: { Authorization: 'Bearer ${T}' } },
    },
  });
  const seen = [];
  const fetchImpl = async (url, init) => {
    seen.push({ url, auth: init.headers.authorization ?? init.headers.Authorization ?? null, body: JSON.parse(init.body).method });
    return new Response(initializeResult, { status: url.includes('open.') ? 200 : 401 });
  };
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false, probeRemote: true, fetchImpl });
  assert.deepEqual(seen.map((s) => s.url).sort(), ['https://locked.example.test/mcp', 'https://open.example.test/mcp']);
  assert.ok(seen.every((s) => s.auth === null && s.body === 'initialize'));
  assert.deepEqual(find(report, 'MCP_REMOTE_UNAUTHENTICATED').map((f) => f.subject), ['open']);
  assert.deepEqual(find(report, 'MCP_REMOTE_NO_CREDENTIALS').map((f) => f.subject), ['open'], 'a server that demands auth is no longer flagged');
  assert.equal(report.network, 'probe-remote');
});

test('the documented AWS OAuth switch is public while a literal query credential stays flagged', async () => {
  const h = newHome();
  h.write('.cursor/mcp.json', {
    mcpServers: {
      aws: { url: 'https://aws-mcp.us-east-1.api.aws/mcp?oauth=initialize' },
      other: { url: 'https://example.test/mcp?oauth=initialize' },
    },
  });
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  assert.deepEqual(find(report, 'MCP_INLINE_SECRET').map((finding) => finding.subject), ['other']);
});

test('probeOne distinguishes MCP, an HTML login page and an authentication challenge', async () => {
  const server = createServer((req, res) => {
    res.statusCode = req.url === '/locked' ? 401 : 200;
    if (req.url === '/sse') {
      res.setHeader('content-type', 'text/event-stream');
      res.end('event: message\ndata: ' + initializeResult + '\n\n');
      return;
    }
    res.end(req.url === '/open' ? initializeResult : '<html>Login</html>');
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  try {
    assert.equal((await probeOne(`http://127.0.0.1:${port}/open`, fetch, 2000)).outcome, 'open');
    assert.equal((await probeOne(`http://127.0.0.1:${port}/locked`, fetch, 2000)).outcome, 'requires-auth');
    assert.equal((await probeOne(`http://127.0.0.1:${port}/sse`, fetch, 2000)).outcome, 'open');
    assert.equal((await probeOne(`http://127.0.0.1:${port}/login`, fetch, 2000)).outcome, 'error');
  } finally {
    server.close();
  }
});

// ---------------------------------------------------------------------------
// CLI: `agenthub doctor` runs under plain Node
// ---------------------------------------------------------------------------

function runCli(args, h, extraEnv = {}) {
  return spawnSync(process.execPath, [cli, 'doctor', ...args], {
    cwd: tmpdir(),
    env: { ...h.env(), NO_COLOR: '1', ...extraEnv },
    encoding: 'utf8',
  });
}

test('CLI prints a table and summary, JSON on --json, and honours --strict and bad flags', () => {
  const h = newHome();
  h.command('node');
  h.write('.claude.json', { mcpServers: { leaky: { command: 'node', env: { GITHUB_TOKEN: fake.github } } } });
  h.write('.codex/config.toml', '');

  const text = runCli(['--home', h.home], h);
  assert.equal(text.status, 0, text.stderr);
  assert.match(text.stdout, /AGENT\s+MCP\s+SKILLS\s+INSTRUCTIONS\s+ISSUES/);
  assert.match(text.stdout, /Claude Code\s+1\s+0/);
  assert.match(text.stdout, /HIGH {2}MCP server 'leaky'/);
  assert.match(text.stdout, /Nothing was written\./);
  assert.doesNotMatch(text.stdout, /\x1b\[/, 'NO_COLOR disables colour');
  assert.ok(!text.stdout.includes(fake.github));

  const json = runCli(['--home', h.home, '--json'], h);
  assert.equal(json.status, 0, json.stderr);
  const report = JSON.parse(json.stdout);
  assert.equal(report.schemaVersion, 1);
  assert.equal(report.readOnly, true);
  assert.equal(report.network, 'none');
  assert.equal(report.registry.mode, 'host-vs-host');
  assert.deepEqual(report.hosts.map((x) => x.id).sort(), ['claude', 'codex']);

  assert.equal(runCli(['--home', h.home, '--strict'], h).status, 1);
  const bad = runCli(['--bogus'], h);
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /unknown option '--bogus'/);
  assert.match(runCli(['--help'], h).stdout, /--probe-remote/);
});

test('CLI colours output when forced', () => {
  const h = newHome();
  h.write('.codex/config.toml', '');
  const out = runCli(['--home', h.home], h, { NO_COLOR: '', FORCE_COLOR: '1' });
  assert.match(out.stdout, /\x1b\[1mAgentHub doctor/);
});

test('an empty home reports no agents and exits 0', () => {
  const h = newHome();
  const out = runCli(['--home', h.home], h);
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /No coding agents found/);
});

test(`fixtures run on ${platform}`, () => {
  assert.ok(['windows', 'darwin', 'linux'].includes(platform));
});
