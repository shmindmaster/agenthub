import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { bindPath, buildHostCatalog, createPathContext } from '../../src/doctor/hosts.js';
import { isReference, normalizeServer, unpinnedPackage } from '../../src/doctor/mcp.js';
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
    gemini: () => h.write('.gemini/settings.json', { mcpServers: { shared: stdio } }),
    copilot: () => h.write('.copilot/mcp-config.json', { mcpServers: { shared: stdio } }),
    antigravity: () => h.write('.gemini/config/mcp_config.json', { mcpServers: { shared: stdio } }),
    warp: () => h.write('.warp/.mcp.json', { mcpServers: { shared: stdio } }),
    cline: () => h.write('.cline/data/settings/cline_mcp_settings.json', { mcpServers: { shared: stdio } }),
    cursor: () => h.write('.cursor/mcp.json', '// Cursor allows comments\n{ "mcpServers": { "shared": { "command": "node", "args": ["server.js"], }, }, }'),
    amp: () => h.write('.config/amp/settings.json', { 'amp.mcpServers': { shared: stdio } }),
    devin: () => h.writeAbs(join(roaming, 'devin', 'mcp_config.json'), { mcpServers: { shared: stdio } }),
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
  h.write('.gemini/settings.json', { mcpServers: {} });
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false });
  const differs = find(report, 'DRIFT_SERVER_DIFFERS');
  assert.deepEqual(differs.map((f) => f.subject), ['db']);
  assert.deepEqual(differs[0].hosts.sort(), ['claude', 'codex']);
  const partial = find(report, 'DRIFT_SERVER_PARTIAL');
  assert.ok(partial.some((f) => f.subject === 'db' && f.hosts.includes('gemini')));
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
    return new Response('{}', { status: url.includes('open.') ? 200 : 401 });
  };
  const report = await runDoctor({ home: h.home, env: h.env(), registry: false, probeRemote: true, fetchImpl });
  assert.deepEqual(seen.map((s) => s.url).sort(), ['https://locked.example.test/mcp', 'https://open.example.test/mcp']);
  assert.ok(seen.every((s) => s.auth === null && s.body === 'initialize'));
  assert.deepEqual(find(report, 'MCP_REMOTE_UNAUTHENTICATED').map((f) => f.subject), ['open']);
  assert.deepEqual(find(report, 'MCP_REMOTE_NO_CREDENTIALS').map((f) => f.subject), ['open'], 'a server that demands auth is no longer flagged');
  assert.equal(report.network, 'probe-remote');
});

test('probeOne classifies a real HTTP server by status', async () => {
  const server = createServer((req, res) => {
    res.statusCode = req.url === '/open' ? 200 : 401;
    res.end('{}');
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  try {
    assert.equal((await probeOne(`http://127.0.0.1:${port}/open`, fetch, 2000)).outcome, 'open');
    assert.equal((await probeOne(`http://127.0.0.1:${port}/locked`, fetch, 2000)).outcome, 'requires-auth');
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
