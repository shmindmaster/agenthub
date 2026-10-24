#!/usr/bin/env node
/**
 * Thin cross-platform entry for AgentHub. `doctor` runs in Node
 * (src/doctor) and needs no PowerShell. Every other command resolves
 * pwsh/powershell and delegates to scripts/AgentHub.ps1 (and
 * Export-PublicCore.ps1 for export); lifecycle logic stays in PowerShell.
 */
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");
const agentHubPs1 = join(repoRoot, "scripts", "AgentHub.ps1");
const exportPs1 = join(repoRoot, "scripts", "Export-PublicCore.ps1");

const HELP = `AgentHub — portable control plane for skills, plugins, MCP, and policy

Usage:
  agenthub <command> [options]

Commands:
  doctor               Show every agent's MCP servers, skills and instructions,
                       and what's broken. Read-only, no PowerShell needed.
                       Run 'agenthub doctor --help' for options.

  These need a clone of the repository and PowerShell 7+:
  init                 Create local overlay + profile from examples (no host writes)
  validate             Run registry validation
  sync                 Read-only drift audit (default)
  sync --apply         Deploy after validate passes
  drift                Same as sync without --apply
  inventory            List registered hosts / capabilities
  export <dir>         Write a public-core tree (does not push)

Options:
  --apply              Only for sync
  -h, --help           Show this help

Docs: https://github.com/shmindmaster/agenthub#readme
`;

const CLONE_HINT = `This command runs the PowerShell sync engine, which ships with the repository, not the npm package:

  git clone https://github.com/shmindmaster/agenthub
  cd agenthub
  npx agenthub init

'agenthub doctor' works from anywhere without it.
`;

function findShell() {
  const candidates =
    process.platform === "win32"
      ? ["pwsh.exe", "pwsh", "powershell.exe"]
      : ["pwsh", "powershell"];
  return candidates[0];
}

function run(shell, args) {
  return new Promise((resolve) => {
    const child = spawn(shell, args, {
      stdio: "inherit",
      shell: false,
      windowsHide: true,
      cwd: repoRoot,
      env: process.env,
    });
    child.on("error", (err) => {
      if (err.code === "ENOENT") {
        console.error(
          `Could not find '${shell}'. Install PowerShell 7+ (https://aka.ms/powershell) and ensure 'pwsh' is on PATH.`
        );
        resolve(127);
        return;
      }
      console.error(err.message);
      resolve(1);
    });
    child.on("exit", (code) => resolve(code ?? 1));
  });
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv[0] === "doctor") {
    const { main: doctor } = await import("../src/doctor/cli.js");
    process.exitCode = await doctor(argv.slice(1));
    return;
  }
  if (argv.length === 0 || argv.includes("-h") || argv.includes("--help")) {
    process.stdout.write(HELP);
    process.exit(0);
  }

  const command = argv[0];
  const rest = argv.slice(1);
  const apply = rest.includes("--apply");

  if (!existsSync(agentHubPs1)) {
    process.stderr.write(CLONE_HINT);
    process.exit(1);
  }

  const shell = findShell();

  if (command === "export") {
    const dest = rest.find((a) => !a.startsWith("-"));
    if (!dest) {
      console.error("Usage: agenthub export <destination-dir>");
      process.exit(2);
    }
    if (!existsSync(exportPs1)) {
      console.error(`Missing ${exportPs1}`);
      process.exit(1);
    }
    const code = await run(shell, [
      "-NoProfile",
      "-File",
      exportPs1,
      "-Destination",
      dest,
    ]);
    process.exit(code);
  }

  const psArgs = ["-NoProfile", "-File", agentHubPs1, command];
  if (apply && (command === "sync" || command === "drift")) {
    psArgs.push("-Apply");
  }
  // Forward unknown flags that look like PowerShell switches for future use
  for (const arg of rest) {
    if (arg === "--apply") continue;
    if (arg.startsWith("-")) psArgs.push(arg);
  }

  const code = await run(shell, psArgs);
  process.exit(code);
}

main();
