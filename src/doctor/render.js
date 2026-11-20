// @ts-check
// Human-readable doctor output. JSON output is the report object itself.

const INFO_LIMIT = 8;

/**
 * @param {boolean} enabled
 */
export function palette(enabled) {
  const wrap = (/** @type {string} */ open, /** @type {string} */ close) => (/** @type {string} */ s) =>
    enabled ? `\x1b[${open}m${s}\x1b[${close}m` : s;
  return {
    bold: wrap('1', '22'),
    dim: wrap('2', '22'),
    red: wrap('31', '39'),
    yellow: wrap('33', '39'),
    green: wrap('32', '39'),
    cyan: wrap('36', '39'),
  };
}

/**
 * @param {NodeJS.WriteStream | { isTTY?: boolean }} stream
 * @param {NodeJS.ProcessEnv} env
 * @param {boolean | undefined} flag  --color / --no-color
 */
export function colorEnabled(stream, env, flag) {
  if (flag !== undefined) return flag;
  if (env.NO_COLOR !== undefined && env.NO_COLOR !== '') return false;
  if (env.FORCE_COLOR !== undefined && env.FORCE_COLOR !== '0') return true;
  return Boolean(stream.isTTY) && env.TERM !== 'dumb';
}

/**
 * @param {Awaited<ReturnType<typeof import('./doctor.js').runDoctor>>} report
 * @param {{ color?: boolean, verbose?: boolean }} [options]
 */
export function renderText(report, options = {}) {
  const c = palette(Boolean(options.color));
  const tilde = (/** @type {string} */ p) =>
    p && report.home && p.toLowerCase().startsWith(report.home.toLowerCase()) ? '~' + p.slice(report.home.length) : p;
  const lines = [];

  const network = {
    none: 'no network',
    'probe-remote': 'probed remote MCP servers',
    'native-cli': 'native CLI',
    'native-health': 'native MCP connectivity checks',
    'probe-remote+native-health': 'remote probes and native MCP connectivity checks',
  }[report.network];
  const nativeInventory = report.native?.devin || report.native?.autoclaw || report.nativeHealth?.grok;
  lines.push(`${c.bold('AgentHub doctor')} ${report.version} ${c.dim(`· read-only · ${network}`)}`);
  const registry =
    report.registry.mode === 'agenthub'
      ? `AgentHub registry at ${report.registry.path}`
      : 'none, comparing agents with each other';
  lines.push(c.dim(`Home: ${report.home}   Registry: ${registry}`));
  lines.push('');

  const found = report.hosts.filter((h) => h.detected);
  if (found.length === 0) {
    lines.push(`No coding agents found under ${report.home}.`);
  } else {
    const rows = found.map((h) => {
      const issues = report.findings.filter((f) => f.hosts.includes(h.id) && f.severity !== 'info');
      const high = issues.filter((f) => f.severity === 'high').length;
      const warn = issues.length - high;
      const issueText = [high ? c.red(`${high} high`) : '', warn ? c.yellow(`${warn} warn`) : ''].filter(Boolean).join(' · ') || c.green('ok');
      return [h.name, String(h.mcp.servers.length), String(h.skills.items.length), instructionsCell(h), issueText];
    });
    const header = [
      'AGENT',
      nativeInventory ? 'MCP (FILES)' : 'MCP',
      nativeInventory ? 'SKILLS (FILES)' : 'SKILLS',
      'INSTRUCTIONS',
      'ISSUES',
    ];
    const widths = header.map((title, i) => Math.max(title.length, ...rows.map((r) => visible(r[i]).length)));
    widths[0] = Math.min(widths[0], 26);
    const fmt = (/** @type {string[]} */ cells) =>
      cells
        .map((cell, i) => {
          const text = i === 0 && visible(cell).length > widths[0] ? cell.slice(0, widths[0] - 1) + '…' : cell;
          const pad = widths[i] - visible(text).length;
          return i === 1 || i === 2 ? ' '.repeat(Math.max(0, pad)) + text : text + ' '.repeat(Math.max(0, pad));
        })
        .join('  ')
        .trimEnd();
    lines.push(c.bold(fmt(header)));
    for (const row of rows) lines.push(fmt(row));
  }
  if (report.notFound.length) {
    lines.push(c.dim(`Not found (${report.notFound.length}): ${report.notFound.join(', ')}`));
  }
  lines.push('');

  const important = report.findings.filter((f) => f.severity !== 'info');
  const info = report.findings.filter((f) => f.severity === 'info');
  const shownInfo = options.verbose ? info : info.slice(0, INFO_LIMIT);
  for (const finding of [...important, ...shownInfo]) {
    const label =
      finding.severity === 'high' ? c.red('HIGH') : finding.severity === 'warn' ? c.yellow('WARN') : c.cyan('INFO');
    lines.push(`${label}  ${report.home ? finding.message.split(report.home).join('~') : finding.message}`);
    const where = [`agents: ${finding.hosts.join(', ')}`, finding.path ? tilde(finding.path) : ''].filter(Boolean).join(' · ');
    lines.push(c.dim(`      ${where}`));
    if (finding.fix && finding.severity !== 'info') lines.push(c.dim(`      fix: ${finding.fix}`));
  }
  if (info.length > shownInfo.length) {
    lines.push(c.dim(`      …and ${info.length - shownInfo.length} more info finding(s); run with --verbose to list them.`));
  }
  if (report.probes) {
    for (const probe of report.probes) {
      const outcome =
        probe.outcome === 'open' ? c.yellow('answers without auth') : probe.outcome === 'requires-auth' ? c.green('requires auth') : c.dim(`no answer (${probe.detail ?? probe.status})`);
      lines.push(`PROBE ${probe.server} ${c.dim(probe.url)}: ${outcome}`);
    }
  }
  if (report.native?.devin) {
    const devin = report.native.devin;
    const inventory = devin.status === 'listed'
      ? `${devin.mcp.length} MCP servers (${devin.mcp.filter((server) => server.enabled).length} enabled), ${devin.skills.length} skills`
      : devin.status === 'unavailable' ? 'CLI executable not found' : 'CLI inventory failed';
    lines.push(`NATIVE Devin CLI: ${inventory}.`);
  }
  if (report.native?.autoclaw) {
    const autoclaw = report.native.autoclaw;
    const statuses = {
      unavailable: 'Windows bundled runtime not found',
      'no-account': 'no initialized desktop runtime profile found',
      'ambiguous-account': 'multiple desktop runtime profiles found',
      failed: 'bundled runtime inventory failed',
    };
    const inventory = autoclaw.status === 'listed'
      ? `${autoclaw.plugins.length} plugins (${autoclaw.plugins.filter((plugin) => plugin.enabled).length} enabled), ${autoclaw.skills.length} skills`
      : statuses[autoclaw.status];
    lines.push(`NATIVE AutoClaw: ${inventory}.`);
  }
  if (report.nativeHealth?.grok) {
    const grok = report.nativeHealth.grok;
    if (grok.status === 'checked') {
      for (const { name, outcome, tools } of grok.mcp) {
        const count = tools === null ? '' : ` (${tools} tools)`;
        lines.push(`NATIVE Grok MCP ${name}: ${outcome}${count}.`);
      }
      if (!grok.mcp.length) lines.push('NATIVE Grok MCP: no servers reported.');
    } else {
      lines.push(`NATIVE Grok MCP: ${grok.status === 'unavailable' ? 'CLI executable not found' : 'CLI health check failed'}.`);
    }
  }
  if (report.findings.length || report.probes?.length || nativeInventory) lines.push('');

  const s = report.summary;
  const inventoryType = nativeInventory ? ' from files' : '';
  const writeStatus = nativeInventory ? 'Doctor did not write any files.' : 'Nothing was written.';
  const counts = [
    s.high ? c.red(`${s.high} high`) : `${s.high} high`,
    s.warn ? c.yellow(`${s.warn} warn`) : `${s.warn} warn`,
    `${s.info} info`,
  ].join(', ');
  lines.push(
    `${c.bold('Summary:')} ${s.hostsFound} of ${s.hostsChecked} agents found, ${s.mcpServers} MCP server entries, ${s.skills} skills${inventoryType}. ${counts}. ${writeStatus}`,
  );
  return lines.join('\n') + '\n';

  /** @param {(typeof report.hosts)[number]} h */
  function instructionsCell(h) {
    const files = h.instructions.files;
    if (!files.length) return h.instructions.ownedBy ? c.dim(`via ${h.instructions.ownedBy}`) : c.dim('-');
    const tokens = formatTokens(h.instructions.estimatedTokens);
    if (files.length === 1) return `${baseName(files[0].path)} ~${tokens} tok`;
    return `${files.length} files ~${tokens} tok`;
  }
}

/** @param {number} n */
function formatTokens(n) {
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n);
}

/** @param {string} p */
function baseName(p) {
  return p.split(/[\\/]/).pop() ?? p;
}

/** @param {string} s */
function visible(s) {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\x1b\[[0-9;]*m/g, '');
}
