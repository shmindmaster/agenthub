// @ts-check
// Host catalog for doctor. Paths come from registry/agents.json, the same
// catalog the PowerShell sync engine uses, and are bound with the same rules
// as scripts/lib/PathBinding.ps1: {userHome} is the home directory everywhere,
// {localData}/{roamingConfig} are the OS data roots, and a template with an
// AppData segment is a Windows install pin that does not exist elsewhere.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const packageRoot = join(here, '..', '..');
export const defaultAgentsPath = join(packageRoot, 'registry', 'agents.json');

/** @typedef {'windows' | 'darwin' | 'linux'} Platform */

/**
 * @typedef {object} PathContext
 * @property {Platform} platform
 * @property {string} home
 * @property {string} localData
 * @property {string} roamingConfig
 */

/**
 * @typedef {object} McpSource
 * @property {string} path
 * @property {'json' | 'toml'} format
 * @property {string} key      Property holding the server map. 'amp.mcpServers' is one literal key.
 * @property {'generic' | 'opencode' | 'codex'} dialect
 */

/**
 * @typedef {object} HostDescriptor
 * @property {string} id
 * @property {string} name
 * @property {string} status          active | inactive | unverified | doctor-only
 * @property {string[]} markers       Paths whose existence means the host is set up on this machine.
 * @property {string[]} executables   Command names looked up on PATH (never executed).
 * @property {McpSource[]} mcp
 * @property {string | null} instructions
 * @property {string | null} instructionsOwnedBy
 * @property {string[]} skillsDirs    Host-specific skill directories, highest precedence first.
 * @property {string | null} sharedSkillsDir
 * @property {string[]} rulesDirs
 */

/**
 * @param {{ platform?: string, home?: string, env?: NodeJS.ProcessEnv, homeOverridden?: boolean }} options
 * @returns {PathContext}
 */
export function createPathContext(options) {
  const env = options.env ?? process.env;
  const platform = normalizePlatform(options.platform ?? process.platform);
  const home = trimSlash(options.home ?? (env.USERPROFILE || env.HOME || ''));
  if (!home) throw new Error('Could not determine the home directory. Pass --home <dir>.');
  const overridden = Boolean(options.homeOverridden);
  const sep = platform === 'windows' ? '\\' : '/';
  const under = (/** @type {string} */ rel) => home + sep + rel.split('/').join(sep);
  if (platform === 'windows') {
    return {
      platform,
      home,
      localData: !overridden && env.LOCALAPPDATA ? trimSlash(env.LOCALAPPDATA) : under('AppData/Local'),
      roamingConfig: !overridden && env.APPDATA ? trimSlash(env.APPDATA) : under('AppData/Roaming'),
    };
  }
  if (platform === 'darwin') {
    const support = under('Library/Application Support');
    return { platform, home, localData: support, roamingConfig: support };
  }
  return {
    platform,
    home,
    localData: !overridden && env.XDG_DATA_HOME ? trimSlash(env.XDG_DATA_HOME) : under('.local/share'),
    roamingConfig: !overridden && env.XDG_CONFIG_HOME ? trimSlash(env.XDG_CONFIG_HOME) : under('.config'),
  };
}

/** @param {string} value @returns {Platform} */
export function normalizePlatform(value) {
  const v = value.toLowerCase();
  if (v === 'win32' || v === 'windows') return 'windows';
  if (v === 'darwin' || v === 'macos') return 'darwin';
  if (v === 'linux') return 'linux';
  throw new Error(`unsupported platform '${value}'; coding agents ship for windows, darwin and linux`);
}

/** @param {string} p */
function trimSlash(p) {
  return p.length > 1 ? p.replace(/[\\/]+$/, '') : p;
}

/**
 * Binds a registry path template. Returns null for anything that is not a
 * portable template (recorded absolute paths are one machine's install) and
 * for Windows-only layouts on macOS/Linux.
 * @param {unknown} template
 * @param {PathContext} ctx
 * @returns {string | null}
 */
export function bindPath(template, ctx) {
  if (typeof template !== 'string') return null;
  const value = template.trim();
  if (!/^\{(userHome|userProfile|localData|localAppData|roamingConfig)\}/.test(value)) return null;
  if (ctx.platform !== 'windows' && /(^|[\\/])AppData([\\/]|$)/i.test(value)) return null;
  const expanded = value
    .replace('{userHome}', ctx.home)
    .replace('{userProfile}', ctx.home)
    .replace('{localData}', ctx.localData)
    .replace('{localAppData}', ctx.localData)
    .replace('{roamingConfig}', ctx.roamingConfig);
  return ctx.platform === 'windows' ? expanded.replace(/\//g, '\\') : expanded.replace(/\\/g, '/');
}

/**
 * Per-host MCP config locations and dialects, matching how
 * scripts/Sync-AgentHub.ps1 writes each host. `field` names a nativePaths
 * entry; `template` is used when the registry has no field for it.
 * @type {Record<string, Array<{ field?: string, template?: string, format?: 'json' | 'toml', key?: string, dialect?: 'generic' | 'opencode' | 'codex', file?: string }>>}
 */
const MCP_LAYOUT = {
  claude: [{ field: 'mcpUser', key: 'mcpServers' }],
  codex: [{ field: 'config', format: 'toml', key: 'mcp_servers', dialect: 'codex' }],
  grok: [{ field: 'config', format: 'toml', key: 'mcp_servers', dialect: 'codex' }],
  opencode: [{ field: 'config', key: 'mcp', dialect: 'opencode', file: 'opencode.json' }],
  'opencode-desktop': [{ field: 'config', key: 'mcp', dialect: 'opencode', file: 'opencode.json' }],
  gemini: [{ field: 'settings', key: 'mcpServers' }],
  copilot: [{ field: 'mcp', key: 'mcpServers' }],
  antigravity: [{ field: 'mcp', key: 'mcpServers' }, { field: 'legacyMcp', key: 'mcpServers' }],
  warp: [{ field: 'mcp', key: 'mcpServers' }],
  cline: [{ field: 'mcp', key: 'mcpServers' }],
  cursor: [{ field: 'mcp', key: 'mcpServers' }],
  'cursor-agent': [{ template: '{userHome}/.cursor/mcp.json', key: 'mcpServers' }],
  amp: [{ field: 'settings', key: 'amp.mcpServers' }],
  devin: [{ field: 'mcp', key: 'mcpServers' }, { field: 'config', key: 'mcpServers', file: 'mcp_config.json' }],
  factory: [{ field: 'mcp', key: 'mcpServers' }],
  'vscode-insiders': [{ field: 'mcp', key: 'servers' }],
  windsurf: [{ field: 'mcp', key: 'mcpServers' }],
};

/**
 * Hosts doctor inspects that AgentHub does not sync. Kept out of
 * registry/agents.json so the sync engine's host set is unchanged.
 */
const DOCTOR_ONLY_HOSTS = [
  {
    id: 'claude-desktop',
    name: 'Claude Desktop',
    status: 'doctor-only',
    executable: null,
    nativePaths: { mcp: '{roamingConfig}/Claude/claude_desktop_config.json' },
  },
  {
    id: 'vscode',
    name: 'VS Code',
    status: 'doctor-only',
    executable: 'code',
    nativePaths: { mcp: '{roamingConfig}/Code/User/mcp.json', settings: '{roamingConfig}/Code/User/settings.json' },
    mcpLayout: [{ field: 'mcp', key: 'servers' }],
  },
];

/**
 * @param {string} [agentsPath]
 * @returns {any[]}
 */
export function loadAgentsRegistry(agentsPath = defaultAgentsPath) {
  const doc = JSON.parse(readFileSync(agentsPath, 'utf8'));
  const active = Array.isArray(doc.activeAgents) ? doc.activeAgents : [];
  const inactive = Array.isArray(doc.inactiveAgents) ? doc.inactiveAgents : [];
  return [...active, ...inactive];
}

/**
 * @param {PathContext} ctx
 * @param {{ agentsPath?: string }} [options]
 * @returns {HostDescriptor[]}
 */
export function buildHostCatalog(ctx, options = {}) {
  const entries = [...loadAgentsRegistry(options.agentsPath), ...DOCTOR_ONLY_HOSTS];
  const seen = new Set();
  /** @type {HostDescriptor[]} */
  const hosts = [];
  for (const entry of entries) {
    if (!entry || typeof entry.id !== 'string' || seen.has(entry.id)) continue;
    seen.add(entry.id);
    hosts.push(describeHost(entry, ctx));
  }
  return hosts;
}

/**
 * Applies the entry's platformPaths.<platform> block, the same merge as
 * Use-AgentHubPlatformPaths in scripts/lib/PathBinding.ps1: `executable`
 * replaces the declared executable and `nativePaths` fields replace (or, when
 * null, clear) the top-level ones.
 * @param {any} entry @param {Platform} platform @returns {any}
 */
export function applyPlatformPaths(entry, platform) {
  const override = entry?.platformPaths?.[platform];
  if (!override || typeof override !== 'object') return entry;
  const merged = { ...entry, nativePaths: { ...(entry.nativePaths ?? {}) } };
  for (const [key, value] of Object.entries(override)) {
    if (key === 'nativePaths' && value && typeof value === 'object') Object.assign(merged.nativePaths, value);
    else merged[key] = value;
  }
  return merged;
}

/** @param {any} rawEntry @param {PathContext} ctx @returns {HostDescriptor} */
function describeHost(rawEntry, ctx) {
  const entry = applyPlatformPaths(rawEntry, ctx.platform);
  const paths = entry.nativePaths ?? {};
  const bind = (/** @type {unknown} */ v) => bindPath(v, ctx);
  const join2 = (/** @type {string} */ base, /** @type {string} */ child) =>
    base + (ctx.platform === 'windows' ? '\\' : '/') + child;

  /** @type {McpSource[]} */
  const mcp = [];
  const layout = entry.mcpLayout ?? MCP_LAYOUT[entry.id] ?? (paths.mcp ? [{ field: 'mcp', key: paths.mcpKey ?? 'mcpServers' }] : []);
  for (const spec of layout) {
    let p = spec.template ? bind(spec.template) : spec.field ? bind(paths[spec.field]) : null;
    if (!p) continue;
    if (spec.file) {
      if (entry.id === 'devin') p = join2(p.replace(/[\\/][^\\/]*$/, ''), spec.file);
      else if (!/\.jsonc?$/i.test(p)) p = join2(p, spec.file);
    }
    const format = spec.format ?? (/\.toml$/i.test(p) ? 'toml' : 'json');
    if (!mcp.some((m) => m.path === p)) {
      mcp.push({ path: p, format, key: spec.key ?? 'mcpServers', dialect: spec.dialect ?? 'generic' });
    }
  }

  const skillsDirs = ['skillsDir', 'cliSkillsDir'].map((f) => bind(paths[f])).filter(isString);
  const sharedSkillsDir = bind(paths.sharedSkillsDir);
  const rulesDirs = ['rulesDir'].map((f) => bind(paths[f])).filter(isString);
  const instructions = bind(paths.instructions);

  const markers = [
    ...mcp.map((m) => m.path),
    ...['config', 'settings', 'configHome', 'dataDir', 'mcpUser', 'mcp'].map((f) => bind(paths[f])),
    instructions,
    ...skillsDirs,
    ...rulesDirs,
  ].filter(isString);

  return {
    id: entry.id,
    name: typeof entry.name === 'string' && entry.name ? entry.name : entry.id,
    status: typeof entry.status === 'string' ? entry.status : 'active',
    markers: [...new Set(markers)],
    executables: executableNames(entry.executable),
    mcp,
    instructions,
    instructionsOwnedBy: typeof paths.instructionsOwnedBy === 'string' ? paths.instructionsOwnedBy : null,
    skillsDirs: [...new Set(skillsDirs)],
    sharedSkillsDir: sharedSkillsDir && !skillsDirs.includes(sharedSkillsDir) ? sharedSkillsDir : null,
    rulesDirs,
  };
}

/** @param {unknown} v @returns {v is string} */
function isString(v) {
  return typeof v === 'string' && v.length > 0;
}

/**
 * The registry records where the owner's install lives. Only the command
 * name is portable, so doctor looks that name up on PATH.
 * @param {unknown} executable
 */
function executableNames(executable) {
  if (typeof executable !== 'string' || !executable) return [];
  const base = executable.split(/[\\/]/).pop() ?? '';
  const name = base.replace(/\.(exe|cmd|bat|ps1)$/i, '');
  if (!name || /\s/.test(name) || /^[A-Z]/.test(name)) return [];
  return [name];
}
