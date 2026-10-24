// @ts-check
// `agenthub doctor` argument parsing and entry point. Pure Node: no
// PowerShell, no dependencies, no writes.

import { runDoctor } from './doctor.js';
import { colorEnabled, renderText } from './render.js';

export const DOCTOR_HELP = `agenthub doctor - see what every coding agent on this machine actually loads

Usage:
  agenthub doctor [options]

Reads each agent's MCP servers, skills and global instruction files, compares
them, and flags risky MCP configs. Read-only: it writes nothing, starts no
server, and makes no network request unless you pass --probe-remote.

Options:
  --json              Print the full report as JSON
  --host <id>         Only check these agents (repeatable or comma-separated)
  --all               Include agents that were not found in the report
  --home <dir>        Inspect <dir> as the home directory (fixtures, other users)
  --registry <dir>    Compare with the AgentHub registry in <dir>
  --no-registry       Compare agents with each other even inside an AgentHub checkout
  --probe-remote      Send one unauthenticated MCP initialize to each remote server
                      that has no credentials configured, to see if it answers
  --timeout <ms>      Probe timeout per server (default 5000)
  --strict            Exit 1 when any high-severity finding is reported
  --verbose           List every info finding
  --color, --no-color Force colour on or off (NO_COLOR and FORCE_COLOR work too)
  -h, --help          Show this help

Exit codes: 0 report printed; 1 --strict and high findings; 2 usage or runtime error.
`;

/**
 * @param {string[]} argv
 */
export function parseDoctorArgs(argv) {
  /** @type {{ json: boolean, hosts: string[], all: boolean, home?: string, registry?: string | false, probeRemote: boolean, timeout: number, strict: boolean, verbose: boolean, color?: boolean, help: boolean }} */
  const opts = { json: false, hosts: [], all: false, probeRemote: false, timeout: 5000, strict: false, verbose: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const [flag, inline] = arg.startsWith('--') && arg.includes('=') ? [arg.slice(0, arg.indexOf('=')), arg.slice(arg.indexOf('=') + 1)] : [arg, undefined];
    const value = () => {
      const v = inline ?? argv[++i];
      if (v === undefined || (inline === undefined && v.startsWith('--'))) throw new UsageError(`${flag} needs a value`);
      return v;
    };
    switch (flag) {
      case '--json': opts.json = true; break;
      case '--host':
      case '--hosts': opts.hosts.push(...value().split(',').map((s) => s.trim()).filter(Boolean)); break;
      case '--all': opts.all = true; break;
      case '--home': opts.home = value(); break;
      case '--registry': opts.registry = value(); break;
      case '--no-registry': opts.registry = false; break;
      case '--probe-remote': opts.probeRemote = true; break;
      case '--timeout': {
        const n = Number(value());
        if (!Number.isFinite(n) || n <= 0) throw new UsageError('--timeout needs a positive number of milliseconds');
        opts.timeout = n;
        break;
      }
      case '--strict': opts.strict = true; break;
      case '--verbose': case '-v': opts.verbose = true; break;
      case '--color': opts.color = true; break;
      case '--no-color': opts.color = false; break;
      case '-h': case '--help': opts.help = true; break;
      default: throw new UsageError(`unknown option '${arg}'`);
    }
  }
  return opts;
}

export class UsageError extends Error {}

/**
 * @param {string[]} argv
 * @param {{ stdout?: NodeJS.WritableStream & { isTTY?: boolean }, stderr?: NodeJS.WritableStream, env?: NodeJS.ProcessEnv, cwd?: string }} [io]
 * @returns {Promise<number>}
 */
export async function main(argv, io = {}) {
  const stdout = io.stdout ?? process.stdout;
  const stderr = io.stderr ?? process.stderr;
  const env = io.env ?? process.env;
  let opts;
  try {
    opts = parseDoctorArgs(argv);
  } catch (error) {
    stderr.write(`agenthub doctor: ${error instanceof Error ? error.message : String(error)}\nRun 'agenthub doctor --help' for options.\n`);
    return 2;
  }
  if (opts.help) {
    stdout.write(DOCTOR_HELP);
    return 0;
  }
  try {
    const report = await runDoctor({
      home: opts.home,
      env,
      cwd: io.cwd,
      registry: opts.registry,
      hosts: opts.hosts,
      includeMissing: opts.all,
      probeRemote: opts.probeRemote,
      probeTimeoutMs: opts.timeout,
    });
    if (opts.json) stdout.write(JSON.stringify(report, null, 2) + '\n');
    else stdout.write(renderText(report, { color: colorEnabled(stdout, env, opts.color), verbose: opts.verbose }));
    return opts.strict && report.summary.high > 0 ? 1 : 0;
  } catch (error) {
    stderr.write(`agenthub doctor: ${error instanceof Error ? error.message : String(error)}\n`);
    return 2;
  }
}
