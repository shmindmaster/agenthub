// @ts-check
// `agenthub doctor`: a read-only inventory of the coding agents on this
// machine. It reads config files and never writes, starts a server, or opens
// a network connection unless the caller passes probeRemote.

import { existsSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { buildHostCatalog, createPathContext, packageRoot } from './hosts.js';
import { commandExists, isLoopback, readMcpSource, unpinnedPackage } from './mcp.js';
import { listRuleFiles, listSkills, readInstructionFile } from './files.js';

export const REPORT_SCHEMA_VERSION = 1;
const LARGE_INSTRUCTIONS_TOKENS = 8000;

/** @typedef {'high' | 'warn' | 'info'} Severity */

/**
 * @typedef {object} Finding
 * @property {Severity} severity
 * @property {string} code
 * @property {string[]} hosts
 * @property {string} subject
 * @property {string} message
 * @property {string} [fix]
 * @property {string} [path]
 */

/**
 * @typedef {object} DoctorOptions
 * @property {string} [home]             Inspect this directory as the home (fixtures, rehearsals).
 * @property {string} [platform]
 * @property {NodeJS.ProcessEnv} [env]
 * @property {string | false} [registry] AgentHub checkout to compare against; false for host-vs-host only.
 * @property {string} [cwd]
 * @property {string[]} [hosts]          Limit the report to these host ids.
 * @property {boolean} [includeMissing]  Also list hosts that were not found.
 * @property {boolean} [probeRemote]     Send one unauthenticated MCP initialize to each remote server.
 * @property {number} [probeTimeoutMs]
 * @property {typeof fetch} [fetchImpl]
 * @property {string} [agentsPath]
 */

/**
 * @param {DoctorOptions} [options]
 */
export async function runDoctor(options = {}) {
  const env = options.env ?? process.env;
  const ctx = createPathContext({
    platform: options.platform,
    home: options.home ? resolve(options.home) : undefined,
    env,
    homeOverridden: Boolean(options.home),
  });
  const catalog = buildHostCatalog(ctx, { agentsPath: options.agentsPath });
  const registry = loadRegistry(options);
  const wanted = options.hosts?.length ? new Set(options.hosts) : null;

  /** @type {Finding[]} */
  const findings = [];
  const hosts = [];
  // An installed CLI belongs to the machine, not to an alternate --home, so
  // PATH only counts towards detection when inspecting the real home.
  const detectOnPath = !options.home;
  for (const host of catalog) {
    if (wanted && !wanted.has(host.id)) continue;
    hosts.push(inspectHost(host, ctx, env, findings, detectOnPath));
  }
  const detected = hosts.filter((h) => h.detected);

  compareHosts(detected, findings);
  if (registry) compareWithRegistry(detected, registry, findings);
  const probes = options.probeRemote ? await probeRemoteServers(detected, findings, options) : null;

  mergeDuplicateFindings(findings);
  const order = { high: 0, warn: 1, info: 2 };
  findings.sort((a, b) => order[a.severity] - order[b.severity] || a.code.localeCompare(b.code) || a.subject.localeCompare(b.subject));

  const servers = new Set(detected.flatMap((h) => h.mcp.servers.map((s) => `${s.source}::${s.name}`)));
  return {
    schemaVersion: REPORT_SCHEMA_VERSION,
    tool: 'agenthub doctor',
    version: packageVersion(),
    readOnly: true,
    network: options.probeRemote ? 'probe-remote' : 'none',
    platform: ctx.platform,
    home: ctx.home,
    registry: registry ? { mode: 'agenthub', path: registry.root } : { mode: 'host-vs-host', path: null },
    hosts: options.includeMissing ? hosts : detected,
    notFound: hosts.filter((h) => !h.detected).map((h) => h.id),
    findings,
    probes,
    summary: {
      hostsChecked: hosts.length,
      hostsFound: detected.length,
      mcpServers: servers.size,
      skills: new Set(detected.flatMap((h) => h.skills.items.map((s) => s.name))).size,
      high: findings.filter((f) => f.severity === 'high').length,
      warn: findings.filter((f) => f.severity === 'warn').length,
      info: findings.filter((f) => f.severity === 'info').length,
    },
  };
}

/**
 * Hosts that read the same file (a shared skills library, Cursor and its CLI)
 * produce the same finding once each; report it once with every host listed.
 * @param {Finding[]} findings
 */
function mergeDuplicateFindings(findings) {
  /** @type {Map<string, Finding>} */
  const seen = new Map();
  const merged = [];
  for (const finding of findings) {
    const key = [finding.code, finding.subject, finding.path ?? '', finding.message].join('\u0000');
    const first = seen.get(key);
    if (first) {
      for (const id of finding.hosts) if (!first.hosts.includes(id)) first.hosts.push(id);
      continue;
    }
    seen.set(key, finding);
    merged.push(finding);
  }
  findings.splice(0, findings.length, ...merged);
}

/** @typedef {ReturnType<typeof inspectHost>} HostReport */

/**
 * @param {import('./hosts.js').HostDescriptor} host
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 * @param {Finding[]} findings
 * @param {boolean} detectOnPath
 */
function inspectHost(host, ctx, env, findings, detectOnPath) {
  const markerHits = host.markers.filter((p) => existsSync(p));
  const onPath = detectOnPath ? host.executables.filter((name) => commandExists(name, env, ctx.platform)) : [];
  const detected = markerHits.length > 0 || onPath.length > 0;

  const sources = host.mcp.map((source) => readMcpSource(source));
  /** @type {import('./mcp.js').McpServer[]} */
  const servers = [];
  for (const source of sources) {
    if (source.error && detected) {
      findings.push({
        severity: 'warn',
        code: 'MCP_CONFIG_UNREADABLE',
        hosts: [host.id],
        subject: source.path,
        message: `This MCP config cannot be read: ${source.error}`,
        fix: 'Fix the syntax error; the host will ignore or reject the whole file.',
        path: source.path,
      });
    }
    for (const server of source.servers) {
      if (!servers.some((s) => s.name === server.name)) servers.push(server);
    }
  }

  const skillDirs = [...host.skillsDirs, ...(host.sharedSkillsDir ? [host.sharedSkillsDir] : [])];
  const listed = skillDirs.map((dir) => ({ dir, ...listSkills(dir) }));
  /** @type {Map<string, import('./files.js').SkillEntry[]>} */
  const byName = new Map();
  for (const entry of listed) {
    for (const skill of entry.skills) {
      const list = byName.get(skill.name) ?? [];
      list.push(skill);
      byName.set(skill.name, list);
    }
  }
  const items = [...byName.values()].map((copies) => copies[0]);

  const instructionFiles = [];
  if (host.instructions) instructionFiles.push(readInstructionFile(host.instructions));
  for (const dir of host.rulesDirs) instructionFiles.push(...listRuleFiles(dir));
  const presentInstructions = instructionFiles.filter((f) => f.exists);

  if (detected) {
    for (const server of servers) checkServer(host, server, ctx, env, findings);
    for (const [name, copies] of byName) {
      const first = copies[0];
      if (!first.hasDescription || (first.declaredName === null)) {
        findings.push({
          severity: 'warn',
          code: 'SKILL_FRONTMATTER',
          hosts: [host.id],
          subject: name,
          message: `Skill '${name}' has no ${first.declaredName === null ? 'name' : 'description'} in its SKILL.md frontmatter, so agents may not list or trigger it.`,
          fix: 'Add a --- block with name: and description: at the top of SKILL.md.',
          path: join(first.dir, 'SKILL.md'),
        });
      } else if (first.declaredName !== name) {
        findings.push({
          severity: 'info',
          code: 'SKILL_NAME_MISMATCH',
          hosts: [host.id],
          subject: name,
          message: `Skill folder '${name}' declares name '${first.declaredName}'.`,
          path: join(first.dir, 'SKILL.md'),
        });
      }
      const distinct = new Set(copies.map((c) => c.hash));
      if (copies.length > 1 && distinct.size > 1) {
        findings.push({
          severity: 'warn',
          code: 'SKILL_SHADOWED',
          hosts: [host.id],
          subject: name,
          message: `Two different copies of skill '${name}' are visible (${copies.map((c) => c.source).join(' and ')}); one shadows the other.`,
          fix: 'Keep one copy, or make them identical.',
        });
      }
    }
    for (const file of presentInstructions) {
      if (file.estimatedTokens >= LARGE_INSTRUCTIONS_TOKENS) {
        findings.push({
          severity: 'info',
          code: 'INSTRUCTIONS_LARGE',
          hosts: [host.id],
          subject: file.path,
          message: `About ${file.estimatedTokens.toLocaleString('en-US')} tokens of global instructions load into every session.`,
          path: file.path,
        });
      }
    }
  }

  return {
    id: host.id,
    name: host.name,
    status: host.status,
    detected,
    detectedBy: [...markerHits, ...onPath.map((n) => `${n} on PATH`)],
    mcp: {
      sources: sources.map((s) => ({ path: s.path, exists: s.exists, error: s.error, servers: s.servers.length })),
      servers,
    },
    skills: {
      dirs: listed.map((l) => ({ path: l.dir, exists: l.exists, count: l.skills.length })),
      items: items.map((s) => ({ name: s.name, source: s.source, valid: s.declaredName !== null && s.hasDescription })),
    },
    instructions: {
      ownedBy: host.instructionsOwnedBy,
      files: presentInstructions,
      expected: instructionFiles.filter((f) => !f.exists).map((f) => f.path),
      estimatedTokens: presentInstructions.reduce((n, f) => n + f.estimatedTokens, 0),
    },
  };
}

/**
 * @param {import('./hosts.js').HostDescriptor} host
 * @param {import('./mcp.js').McpServer} server
 * @param {import('./hosts.js').PathContext} ctx
 * @param {NodeJS.ProcessEnv} env
 * @param {Finding[]} findings
 */
function checkServer(host, server, ctx, env, findings) {
  const subject = server.name;
  /** @param {Severity} severity @param {string} code @param {string} message @param {string} fix */
  const add = (severity, code, message, fix) => {
    const existing = findings.find((f) => f.code === code && f.subject === subject && f.path === server.source && f.message === message);
    if (existing) {
      if (!existing.hosts.includes(host.id)) existing.hosts.push(host.id);
      return;
    }
    findings.push({ severity, code, hosts: [host.id], subject, message, fix, path: server.source });
  };
  for (const hit of server.secrets) {
    add(
      'high',
      'MCP_INLINE_SECRET',
      `MCP server '${subject}' has a ${hit.kind} written into ${hit.where}. Anything that reads, backs up or syncs this file can copy it.`,
      'Move it to an environment variable or the OS keychain and reference it, then rotate the exposed value.',
    );
  }
  if (!server.enabled) return;
  if (server.transport === 'http' || server.transport === 'sse') {
    const remote = server.url && !isLoopback(server.url);
    if (remote && /^http:\/\//i.test(server.url ?? '')) {
      add(
        'high',
        'MCP_PLAINTEXT_REMOTE',
        `MCP server '${subject}' talks to a remote host over plain http://, so requests and any credentials travel unencrypted.`,
        'Use the https:// endpoint.',
      );
    } else if (remote && !server.authConfigured) {
      add(
        'info',
        'MCP_REMOTE_NO_CREDENTIALS',
        `MCP server '${subject}' is remote and has no credentials in its config. Either the agent completes OAuth for it, or it accepts anonymous requests.`,
        'Run `agenthub doctor --probe-remote` to check whether it answers without authentication.',
      );
    }
  }
  if (server.transport === 'stdio' && server.command) {
    const command = expandHome(server.command, ctx.home);
    if (!/\$\{|%\w+%|\{env:/.test(command) && !commandExists(command, env, ctx.platform)) {
      add(
        'warn',
        'MCP_COMMAND_NOT_FOUND',
        `MCP server '${subject}' will not start: '${server.command}' is not on PATH${/[\\/]/.test(server.command) ? ' or does not exist' : ''}.`,
        'Install it, or use the full path to the command.',
      );
    }
    const spec = unpinnedPackage(server);
    if (spec) {
      add(
        'info',
        'MCP_UNPINNED_PACKAGE',
        `MCP server '${subject}' runs '${spec}' through ${commandName(server.command)} without a version, so every start can fetch and run a different release.`,
        `Pin an exact version, for example ${spec.replace(/@latest$/, '')}@<version>.`,
      );
    }
  }
}

/** @param {string} command @param {string} home */
function expandHome(command, home) {
  return command.replace(/^~(?=[\\/]|$)/, home);
}

/** @param {string | null} command */
function commandName(command) {
  return (command ?? '').split(/[\\/]/).pop() ?? '';
}

/**
 * Host-vs-host comparison: the same server name configured differently, and
 * hosts that share a skill library but have drifted copies.
 * @param {HostReport[]} hosts
 * @param {Finding[]} findings
 */
function compareHosts(hosts, findings) {
  /** @type {Map<string, Map<string, string[]>>} */
  const byServer = new Map();
  /** @type {Map<string, string>} */
  const pathOf = new Map();
  for (const host of hosts) {
    const sourceKey = host.mcp.sources.filter((s) => s.exists).map((s) => s.path).join('|');
    for (const server of host.mcp.servers) {
      const key = server.name.toLowerCase();
      /** @type {Map<string, string[]>} */
      const fingerprints = byServer.get(key) ?? new Map();
      const fp = bridgeFingerprint(server);
      const list = fingerprints.get(fp) ?? [];
      if (!list.some((/** @type {string} */ id) => pathOf.get(id) === sourceKey && sourceKey)) list.push(host.id);
      pathOf.set(host.id, sourceKey);
      fingerprints.set(fp, list);
      byServer.set(key, fingerprints);
    }
  }
  for (const [name, fingerprints] of byServer) {
    if (fingerprints.size < 2) continue;
    const groups = [...fingerprints.entries()].map(([fp, ids]) => `${ids.join(', ')} -> ${fp}`);
    findings.push({
      severity: 'warn',
      code: 'DRIFT_SERVER_DIFFERS',
      hosts: [...fingerprints.values()].flat(),
      subject: name,
      message: `MCP server '${name}' is configured differently across agents: ${groups.join('; ')}.`,
      fix: 'Pick one definition and use it everywhere (AgentHub sync can write it to every host).',
    });
  }

  const mcpHosts = hosts.filter((h) => h.mcp.sources.some((s) => s.exists));
  if (mcpHosts.length > 1) {
    for (const [name, fingerprints] of byServer) {
      const present = new Set([...fingerprints.values()].flat());
      const missing = mcpHosts.filter((h) => !h.mcp.servers.some((s) => s.name.toLowerCase() === name)).map((h) => h.id);
      if (missing.length && present.size) {
        findings.push({
          severity: 'info',
          code: 'DRIFT_SERVER_PARTIAL',
          hosts: missing,
          subject: name,
          message: `MCP server '${name}' is set up in ${mcpHosts.length - missing.length} of ${mcpHosts.length} agents; missing from ${missing.join(', ')}.`,
        });
      }
    }
  }

  const withInstructions = hosts.filter((h) => h.instructions.files.some((f) => f.bodyHash));
  /** @type {Map<string, Set<string>>} */
  const versions = new Map();
  const seenPaths = new Set();
  for (const host of withInstructions) {
    const main = host.instructions.files[0];
    if (!main?.bodyHash || seenPaths.has(main.path)) continue;
    seenPaths.add(main.path);
    const set = versions.get(main.bodyHash) ?? new Set();
    set.add(host.id);
    versions.set(main.bodyHash, set);
  }
  if (versions.size > 1) {
    findings.push({
      severity: 'info',
      code: 'DRIFT_INSTRUCTIONS',
      hosts: [...versions.values()].flatMap((s) => [...s]),
      subject: 'global instructions',
      message: `Global instruction files exist in ${seenPaths.size} agents with ${versions.size} different bodies: ${[...versions.values()].map((s) => [...s].join(' = ')).join(' | ')}.`,
      fix: 'Keep one canonical policy and render it per host (agenthub sync).',
    });
  }
}

/**
 * `npx mcp-remote <url>` is a stdio bridge to a remote server. Treat it as
 * the URL so a bridged host and a native-HTTP host compare equal.
 * @param {import('./mcp.js').McpServer} server
 */
function bridgeFingerprint(server) {
  if (server.transport === 'stdio') {
    const idx = server.args.findIndex((a) => /^mcp-remote(@|$)/.test(a));
    const url = idx >= 0 ? server.args.slice(idx + 1).find((a) => /^https?:\/\//.test(a)) : undefined;
    if (url) return `http:${url.replace(/[?#].*$/, '').replace(/\/+$/, '')}`;
  }
  return server.fingerprint.replace(/^sse:/, 'http:');
}

/**
 * @param {DoctorOptions} options
 */
function loadRegistry(options) {
  if (options.registry === false) return null;
  const candidates = options.registry ? [resolve(options.registry)] : [resolve(options.cwd ?? process.cwd())];
  for (const root of candidates) {
    const mcpsPath = join(root, 'registry', 'mcps.json');
    const agentsPath = join(root, 'registry', 'agents.json');
    const isCheckout = existsSync(join(root, 'scripts', 'AgentHub.ps1'));
    if (!existsSync(mcpsPath) || !existsSync(agentsPath)) {
      if (options.registry) throw new Error(`--registry ${options.registry}: no registry/mcps.json and registry/agents.json there`);
      continue;
    }
    if (!options.registry && !isCheckout) continue;
    const mcps = JSON.parse(readFileSync(mcpsPath, 'utf8'));
    const agents = JSON.parse(readFileSync(agentsPath, 'utf8'));
    return { root, mcps, activeHosts: new Set((agents.activeAgents ?? []).map((/** @type {any} */ a) => a.id)) };
  }
  return null;
}

/**
 * Server-name comparison with the servers AgentHub's default sync scope
 * deploys to each host. `agenthub sync` (PowerShell) remains the full audit:
 * it also accounts for gateways, overlays and per-host overrides.
 * @param {HostReport[]} hosts
 * @param {{ mcps: any, activeHosts: Set<string> }} registry
 * @param {Finding[]} findings
 */
function compareWithRegistry(hosts, registry, findings) {
  /** @type {Record<string, string>} */
  const aliases = registry.mcps.migrationAliases ?? {};
  const resolveAlias = (/** @type {string} */ id) => (aliases[id] ?? id).toLowerCase();
  const servers = Array.isArray(registry.mcps.mcpServers) ? registry.mcps.mcpServers : [];
  const known = new Set(servers.map((/** @type {any} */ s) => resolveAlias(String(s.id))));
  for (const host of hosts) {
    if (!registry.activeHosts.has(host.id) || !host.mcp.sources.length) continue;
    const have = new Set(host.mcp.servers.map((s) => resolveAlias(s.name)));
    const expected = servers.filter((/** @type {any} */ s) => {
      if ((s.scope ?? 'global-default') !== 'global-default') return false;
      if (s.activationMode === 'on-demand-local') return false;
      if (Array.isArray(s.hosts) && s.hosts.length && !s.hosts.includes(host.id)) return false;
      if (s.pluginOwnersByHost && s.pluginOwnersByHost[host.id]) return false;
      return true;
    });
    /** @type {string[]} */
    const expectedIds = expected.map((/** @type {any} */ s) => resolveAlias(String(s.id)));
    const missing = expectedIds.filter((id) => !have.has(id));
    if (missing.length) {
      findings.push({
        severity: 'warn',
        code: 'REGISTRY_MISSING',
        hosts: [host.id],
        subject: host.id,
        message: `${host.name} is missing ${missing.length} MCP server(s) the registry deploys to it: ${missing.join(', ')}.`,
        fix: 'Run `agenthub sync` to see the full drift report, then `agenthub sync --apply`.',
      });
    }
    const extra = [...have].filter((id) => !known.has(id));
    if (extra.length) {
      findings.push({
        severity: 'info',
        code: 'REGISTRY_UNKNOWN',
        hosts: [host.id],
        subject: host.id,
        message: `${host.name} has MCP server(s) the registry does not know: ${extra.join(', ')}.`,
        fix: 'Add them to registry/mcps.json if they should be shared, or leave them as host-local.',
      });
    }
    for (const file of host.instructions.files.slice(0, 1)) {
      if (!file.managed) {
        findings.push({
          severity: 'info',
          code: 'REGISTRY_UNMANAGED_INSTRUCTIONS',
          hosts: [host.id],
          subject: file.path,
          message: `${host.name}'s instruction file has no AgentHub marker, so sync reports it as unmanaged and leaves it alone.`,
          path: file.path,
        });
      }
    }
  }
}

/**
 * Sends one MCP initialize request, with no credentials, to each remote
 * server that has none configured. Only runs when asked.
 * @param {HostReport[]} hosts
 * @param {Finding[]} findings
 * @param {DoctorOptions} options
 */
async function probeRemoteServers(hosts, findings, options) {
  const doFetch = options.fetchImpl ?? globalThis.fetch;
  /** @type {Map<string, string[]>} */
  const targets = new Map();
  for (const host of hosts) {
    for (const server of host.mcp.servers) {
      if (!server.enabled || server.authConfigured || !server.url || isLoopback(server.url)) continue;
      if (server.transport !== 'http' && server.transport !== 'sse') continue;
      if (!/^https?:\/\//i.test(server.url)) continue;
      const key = `${server.name}\u0000${server.url}`;
      targets.set(key, [...(targets.get(key) ?? []), host.id]);
    }
  }
  const results = [];
  for (const [key, hostIds] of targets) {
    const [name, url] = key.split('\u0000');
    const result = await probeOne(url, doFetch, options.probeTimeoutMs ?? 5000);
    results.push({ server: name, url, hosts: hostIds, ...result });
    if (result.outcome === 'open') {
      findings.push({
        severity: 'warn',
        code: 'MCP_REMOTE_UNAUTHENTICATED',
        hosts: hostIds,
        subject: name,
        message: `MCP server '${name}' (${url}) answered an initialize request with no credentials (HTTP ${result.status}). Anyone who knows the URL can use it.`,
        fix: 'Confirm that is intended; otherwise put it behind OAuth or a token.',
      });
    }
    const index = findings.findIndex((f) => f.code === 'MCP_REMOTE_NO_CREDENTIALS' && f.subject === name);
    if (index >= 0 && result.outcome === 'requires-auth') findings.splice(index, 1);
  }
  return results;
}

/**
 * @param {string} url
 * @param {typeof fetch} doFetch
 * @param {number} timeoutMs
 * @returns {Promise<{ outcome: 'open' | 'requires-auth' | 'error', status: number | null, detail?: string }>}
 */
export async function probeOne(url, doFetch, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await doFetch(url, {
      method: 'POST',
      signal: controller.signal,
      redirect: 'manual',
      headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'initialize',
        params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'agenthub-doctor', version: packageVersion() } },
      }),
    });
    try {
      await response.body?.cancel();
    } catch {
      // body already consumed or not cancellable
    }
    if (response.status === 401 || response.status === 403) return { outcome: 'requires-auth', status: response.status };
    if (response.status >= 200 && response.status < 300) return { outcome: 'open', status: response.status };
    return { outcome: 'error', status: response.status };
  } catch (error) {
    return { outcome: 'error', status: null, detail: error instanceof Error ? error.message : String(error) };
  } finally {
    clearTimeout(timer);
  }
}

let cachedVersion = '';
export function packageVersion() {
  if (cachedVersion) return cachedVersion;
  try {
    cachedVersion = String(JSON.parse(readFileSync(join(packageRoot, 'package.json'), 'utf8')).version ?? '0.0.0');
  } catch {
    cachedVersion = '0.0.0';
  }
  return cachedVersion;
}

/** @param {string} p */
export function isDirectory(p) {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
}
