// @ts-check
// Reads each host's MCP server map into one shape and flags risky entries.
// Nothing here starts a server or contacts the network.

import { existsSync, readFileSync, statSync } from 'node:fs';
import { delimiter, isAbsolute, join } from 'node:path';
import { parseJsonc, parseToml } from './parsers.js';

/**
 * @typedef {object} McpServer
 * @property {string} name
 * @property {'stdio' | 'http' | 'sse' | 'unknown'} transport
 * @property {string | null} command
 * @property {string[]} args
 * @property {string | null} url       Redacted when it carries a credential.
 * @property {Record<string, string>} env      Values redacted unless they are references.
 * @property {Record<string, string>} headers  Values redacted unless they are references.
 * @property {boolean} enabled
 * @property {boolean} authConfigured  Headers, bearer env var or OAuth settings are present.
 * @property {string} fingerprint      Stable summary used to compare hosts.
 * @property {SecretHit[]} secrets
 * @property {string} [source]         Config file the entry was read from.
 */

/** @typedef {{ where: string, kind: string }} SecretHit */

/**
 * @typedef {object} McpReadResult
 * @property {string} path
 * @property {boolean} exists
 * @property {string | null} error
 * @property {McpServer[]} servers
 * @property {McpServer[]} ignoredEntries
 */

/**
 * @param {import('./hosts.js').McpSource} source
 * @returns {McpReadResult}
 */
export function readMcpSource(source) {
  /** @type {McpReadResult} */
  const result = { path: source.path, exists: false, error: null, servers: [], ignoredEntries: [] };
  let text;
  try {
    if (!statSync(source.path).isFile()) return result;
    text = readFileSync(source.path, 'utf8');
  } catch {
    return result;
  }
  result.exists = true;
  let doc;
  try {
    doc = source.format === 'toml' ? parseToml(text) : text.trim() === '' ? {} : parseJsonc(text);
  } catch (error) {
    result.error = `could not parse ${source.format.toUpperCase()}: ${error instanceof Error ? error.message : String(error)}`;
    return result;
  }
  const map = objectOrEmpty(doc)[source.key] ??
    source.key.split('.').reduce((value, key) => objectOrEmpty(value)[key], doc);
  if (!map || typeof map !== 'object' || Array.isArray(map)) return result;
  const nested = source.dialect === 'opencode' ? map.servers : null;
  const isNestedMap = nested && typeof nested === 'object' && !Array.isArray(nested)
    && typeof nested.type !== 'string' && typeof nested.transport !== 'string'
    && typeof nested.url !== 'string' && typeof nested.enabled !== 'boolean'
    && typeof nested.command !== 'string' && !Array.isArray(nested.command);
  const entries = Object.entries(map).filter(([name]) => name !== 'servers' || !isNestedMap);
  if (isNestedMap) entries.push(...Object.entries(nested));
  for (const [name, raw] of new Map(entries)) {
    const config = source.dialect === 'zcode' ? readZCodeConnection(raw) : raw;
    if (source.dialect === 'zcode' && !config) {
      const ignored = normalizeServer(name, objectOrEmpty(raw), source.dialect);
      result.ignoredEntries.push({ ...ignored, enabled: false, source: source.path });
      continue;
    }
    if (!config || typeof config !== 'object' || Array.isArray(config)) continue;
    result.servers.push({ ...normalizeServer(name, config, source.dialect), source: source.path });
  }
  result.servers.sort((a, b) => a.name.localeCompare(b.name));
  return result;
}

const zcodeCommonFields = ['type', 'enabled', 'alwaysLoad', 'isolation', 'protocolVersion', 'timeoutMs'];
const zcodeStdioFields = new Set([...zcodeCommonFields, 'command', 'args', 'cwd', 'env']);
const zcodeRemoteFields = new Set([...zcodeCommonFields, 'url', 'headers', 'oauth']);

/**
 * Normalize the compatibility aliases from the native ZCode parser. Reject
 * foreign fields and invalid transport shapes that the runtime ignores.
 * @param {unknown} value
 */
function readZCodeConnection(value) {
  const {
    enable, environment, http_headers, timeout: _timeout,
    startup_timeout_sec: _startupTimeout, ...config
  } = objectOrEmpty(value);
  if (enable === false) config.enabled = false;
  if (config.type === 'remote') config.type = 'http';
  if (typeof config.type !== 'string') {
    if (typeof config.command === 'string' && config.command.trim()) config.type = 'stdio';
    else if (typeof config.url === 'string' && config.url.trim()) config.type = 'http';
  }
  if (config.env === undefined && environment !== undefined) config.env = environment;
  if (config.type === 'stdio') {
    if (typeof config.command === 'string' && config.command.length &&
        Object.keys(config).every((key) => zcodeStdioFields.has(key))) return config;
  }
  if (config.type === 'http' || config.type === 'sse') {
    if (config.headers === undefined && http_headers !== undefined) config.headers = http_headers;
    if (typeof config.url === 'string' && config.url.length &&
        Object.keys(config).every((key) => zcodeRemoteFields.has(key))) return config;
  }
  return null;
}

/**
 * @param {string} name
 * @param {Record<string, any>} raw
 * @param {import('./hosts.js').McpSource['dialect']} dialect
 * @returns {McpServer}
 */
export function normalizeServer(name, raw, dialect) {
  /** @type {SecretHit[]} */
  const secrets = [];
  // Cline's CLI nests connection fields. Activation and OAuth stay on the server entry.
  const nativeTransport = objectOrEmpty(raw.transport);
  const connection = dialect === 'cline' && typeof nativeTransport.type === 'string' ? nativeTransport : raw;
  let command = null;
  /** @type {string[]} */
  let args = [];
  let url = null;
  /** @type {Record<string, unknown>} */
  let envRaw = {};
  /** @type {Record<string, unknown>} */
  let headersRaw = {};
  let enabled = true;
  let authConfigured = false;

  if (dialect === 'opencode') {
    if (Array.isArray(raw.command)) {
      command = raw.command.length ? String(raw.command[0]) : null;
      args = raw.command.slice(1).map(String);
    } else if (typeof raw.command === 'string') {
      command = raw.command;
    }
    url = typeof raw.url === 'string' ? raw.url : null;
    envRaw = objectOrEmpty(raw.environment);
    headersRaw = objectOrEmpty(raw.headers);
    enabled = raw.enabled !== false;
    authConfigured = raw.oauth !== undefined && raw.oauth !== false;
  } else {
    command = typeof connection.command === 'string' ? connection.command : null;
    args = Array.isArray(connection.args) ? connection.args.map(String) : [];
    url = firstString(connection.url, connection.httpUrl, connection.serverUrl, connection.uri);
    envRaw = objectOrEmpty(connection.env);
    headersRaw = { ...objectOrEmpty(connection.headers), ...objectOrEmpty(connection.http_headers), ...objectOrEmpty(connection.requestInit?.headers) };
    enabled = raw.disabled !== true && raw.enabled !== false;
    if (dialect === 'codex') {
      if (typeof raw.bearer_token_env_var === 'string' || raw.env_http_headers) authConfigured = true;
    }
    if (raw.oauth || raw.auth || raw.authProviderType || raw.headersHelper) authConfigured = true;
  }

  const type = (firstString(connection.type, connection.transport, dialect === 'cline' ? connection.transportType : null) ?? '').toLowerCase();
  /** @type {McpServer['transport']} */
  let transport = 'unknown';
  if (command) transport = 'stdio';
  else if (url) {
    const isSse = type === 'sse' || (dialect === 'cline' ? type === '' : /\/sse\/?$/.test(url));
    transport = isSse ? 'sse' : 'http';
  }
  if (type === 'stdio' || type === 'local') transport = command ? 'stdio' : transport;

  const env = redactMap(envRaw, 'env', secrets);
  const headers = redactMap(headersRaw, 'headers', secrets);
  if (Object.keys(headersRaw).some((k) => /^(authorization|x-api-key|api-key|x-auth-token|cookie)$/i.test(k))) {
    authConfigured = true;
  }
  args = args.map((arg, index) => {
    const kind = tokenKind(arg);
    if (kind) {
      secrets.push({ where: `args[${index}]`, kind });
      return '[redacted]';
    }
    return arg;
  });
  if (url) {
    const checked = checkUrl(url);
    for (const hit of checked.hits) secrets.push(hit);
    if (checked.hits.length) authConfigured = true;
    url = checked.redacted;
  }

  const fingerprint =
    transport === 'stdio'
      ? `stdio:${commandBase(command)} ${args.join(' ')}`.trim()
      : `${transport}:${(url ?? '').replace(/[?#].*$/, '').replace(/\/+$/, '')}`;

  return { name, transport, command, args, url, env, headers, enabled, authConfigured, fingerprint, secrets };
}

/** @param {unknown} v @returns {Record<string, unknown>} */
function objectOrEmpty(v) {
  return v && typeof v === 'object' && !Array.isArray(v) ? /** @type {Record<string, unknown>} */ (v) : {};
}

/** @param {...unknown} values */
function firstString(...values) {
  for (const v of values) if (typeof v === 'string' && v) return v;
  return null;
}

/** @param {string | null} command */
function commandBase(command) {
  if (!command) return '';
  return (command.split(/[\\/]/).pop() ?? command).replace(/\.(exe|cmd|bat)$/i, '').toLowerCase();
}

const TOKEN_PATTERNS = /** @type {Array<[string, RegExp]>} */ ([
  ['Anthropic/OpenAI-style API key', /\bsk-(?:ant-|proj-|svcacct-)?[A-Za-z0-9_-]{20,}/],
  ['Stripe key', /\b[sr]k_(?:live|test)_[A-Za-z0-9]{16,}/],
  ['GitHub token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})/],
  ['GitLab token', /\bglpat-[A-Za-z0-9_-]{20,}/],
  ['Slack token', /\bxox[abprs]-[A-Za-z0-9-]{10,}/],
  ['AWS access key', /\bAKIA[0-9A-Z]{16}\b/],
  ['Google API key', /\bAIza[0-9A-Za-z_-]{35}\b/],
  ['Firecrawl key', /\bfc-[0-9a-f]{32}\b/],
  ['Notion token', /\b(?:ntn_|secret_)[A-Za-z0-9]{40,}/],
  ['Linear key', /\blin_api_[A-Za-z0-9]{30,}/],
  ['Hugging Face token', /\bhf_[A-Za-z0-9]{30,}/],
  ['xAI/Groq/Perplexity key', /\b(?:xai-|gsk_|pplx-)[A-Za-z0-9]{30,}/],
  ['JSON Web Token', /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/],
]);

/** @param {string} value @returns {string | null} */
export function tokenKind(value) {
  for (const [kind, pattern] of TOKEN_PATTERNS) if (pattern.test(value)) return kind;
  return null;
}

/**
 * True for values that point at a secret instead of containing one:
 * ${VAR}, ${env:VAR}, ${input:id}, $VAR, {env:VAR}, %VAR%, and "Bearer ${VAR}".
 * @param {string} value
 */
export function isReference(value) {
  return (
    /\$\{(?:env:|input:)?[A-Za-z_][\w.-]*\}/.test(value) ||
    /^\$[A-Za-z_]\w*$/.test(value.replace(/^Bearer\s+/i, '')) ||
    /\{(?:env|file):[^}]+\}/.test(value) ||
    /^%[A-Za-z_]\w*%$/.test(value)
  );
}

/** @param {string} value */
function isPlaceholder(value) {
  return /^(?:<[^>]*>|your[\s_-].*|xx+|\*+|\.\.\.|changeme|change-me|todo|placeholder|redacted|none|null|true|false)$/i.test(value.trim());
}

const SENSITIVE_NAME = /(api[_-]?key|apikey|token|secret|passw(or)?d|pwd|credential|private[_-]?key|access[_-]?key|session|cookie|bearer|authorization|auth)/i;

/**
 * @param {Record<string, unknown>} map
 * @param {string} label
 * @param {SecretHit[]} secrets
 * @returns {Record<string, string>}
 */
function redactMap(map, label, secrets) {
  /** @type {Record<string, string>} */
  const out = {};
  for (const [key, rawValue] of Object.entries(map)) {
    const value = rawValue == null ? '' : String(rawValue);
    if (value === '' || isReference(value)) {
      out[key] = value;
      continue;
    }
    const kind = tokenKind(value) ?? (looksLikeLiteralSecret(key, value) ? `literal value for ${key}` : null);
    if (kind) {
      secrets.push({ where: `${label}.${key}`, kind });
      out[key] = '[redacted]';
    } else {
      out[key] = SENSITIVE_NAME.test(key) ? '[redacted]' : value;
    }
  }
  return out;
}

/** @param {string} key @param {string} value */
function looksLikeLiteralSecret(key, value) {
  if (!SENSITIVE_NAME.test(key) || isPlaceholder(value)) return false;
  const bare = value.replace(/^(Bearer|Basic|Token)\s+/i, '');
  if (bare.length < 12) return false;
  if (/^https?:\/\//i.test(bare)) return false;
  if (/^(?:[A-Za-z]:[\\/]|[~./\\])/.test(bare)) return false;
  return /^[A-Za-z0-9_\-+/=.:]+$/.test(bare);
}

/**
 * @param {string} url
 * @returns {{ redacted: string, hits: SecretHit[] }}
 */
function checkUrl(url) {
  /** @type {SecretHit[]} */
  const hits = [];
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    const kind = tokenKind(url);
    return kind ? { redacted: '[redacted url]', hits: [{ where: 'url', kind }] } : { redacted: url, hits };
  }
  if (parsed.password) {
    hits.push({ where: 'url', kind: 'password in URL' });
    parsed.password = 'redacted';
  }
  for (const [key, value] of [...parsed.searchParams.entries()]) {
    // AWS documents this literal as an OAuth discovery switch for older clients.
    if (key === 'oauth' && value === 'initialize' && parsed.protocol === 'https:' &&
        /^aws-mcp\.[a-z0-9-]+\.api\.aws$/i.test(parsed.hostname)) continue;
    if (value && !isReference(value) && (SENSITIVE_NAME.test(key) || tokenKind(value))) {
      hits.push({ where: `url ?${key}=`, kind: tokenKind(value) ?? `literal ${key} in query string` });
      parsed.searchParams.set(key, 'redacted');
    }
  }
  const segments = parsed.pathname.split('/');
  let pathHit = false;
  const cleaned = segments.map((segment) => {
    const kind = tokenKind(decodeURIComponent(segment));
    if (kind) {
      hits.push({ where: 'url path', kind });
      pathHit = true;
      return 'redacted';
    }
    return segment;
  });
  if (pathHit) parsed.pathname = cleaned.join('/');
  return { redacted: hits.length ? parsed.toString() : url, hits };
}

/** @param {string | null} url */
export function isLoopback(url) {
  if (!url) return false;
  try {
    const host = new URL(url).hostname.replace(/^\[|\]$/g, '');
    return host === 'localhost' || host === '::1' || /^127\./.test(host) || host === '0.0.0.0';
  } catch {
    return false;
  }
}

/**
 * Looks a command up on PATH without running it.
 * @param {string} command
 * @param {NodeJS.ProcessEnv} env
 * @param {string} platform
 */
export function commandExists(command, env, platform) {
  if (isAbsolute(command) || /[\\/]/.test(command)) return existsSync(command);
  const pathValue = env.PATH ?? env.Path ?? '';
  const sep = platform === 'windows' ? ';' : delimiter;
  const exts =
    platform === 'windows'
      ? ['', ...(env.PATHEXT ?? '.COM;.EXE;.BAT;.CMD').split(';').filter(Boolean).map((e) => e.toLowerCase())]
      : [''];
  for (const dir of pathValue.split(sep)) {
    if (!dir) continue;
    for (const ext of exts) {
      try {
        if (statSync(join(dir, command + ext)).isFile()) return true;
      } catch {
        // not here
      }
    }
  }
  return false;
}

/**
 * Package runners that fetch whatever is newest at every start. Returns the
 * unpinned spec, or null when the package has an exact version.
 * @param {McpServer} server
 */
export function unpinnedPackage(server) {
  const base = commandBase(server.command);
  let rest = server.args;
  if (base === 'pnpm' || base === 'yarn') {
    if (rest[0] !== 'dlx') return null;
    rest = rest.slice(1);
  } else if (base === 'uv') {
    if (rest[0] !== 'tool' || rest[1] !== 'run') return null;
    rest = rest.slice(2);
  } else if (!['npx', 'bunx', 'uvx', 'pipx'].includes(base)) {
    return null;
  }
  if (base === 'pipx') {
    if (rest[0] !== 'run') return null;
    rest = rest.slice(1);
  }
  const flagsWithValue = new Set(['-p', '--package', '--from', '--python', '--with', '--registry', '--cache']);
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (flagsWithValue.has(arg)) {
      const pkg = rest[i + 1] ?? '';
      if (arg === '-p' || arg === '--package' || arg === '--from') return isPinned(pkg) ? null : pkg;
      i++;
      continue;
    }
    if (arg.startsWith('-')) continue;
    return isPinned(arg) ? null : arg;
  }
  return null;
}

/** @param {string} spec */
function isPinned(spec) {
  if (/^(?:\.|\/|[A-Za-z]:|file:|git\+|https?:)/.test(spec)) return true;
  const py = /==\s*\d/.test(spec);
  if (py) return true;
  const at = spec.lastIndexOf('@');
  if (at <= 0) return false;
  const version = spec.slice(at + 1);
  return /^\d+\.\d+\.\d+/.test(version);
}
