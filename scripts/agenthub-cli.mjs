#!/usr/bin/env node
/**
 * Thin cross-platform entry for AgentHub. Resolves pwsh/powershell and
 * delegates to scripts/AgentHub.ps1 (and Export-PublicCore.ps1 for export).
 * First-click UX only — lifecycle logic stays in PowerShell.
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

Requires PowerShell 7.4+ (pwsh) on Windows, macOS, and Linux.
Docs: docs/development/quickstart.md
`;

function findShell() {
  const candidates = process.platform === "win32" ? ["pwsh.exe", "pwsh"] : ["pwsh"];
  return candidates[0];
}

function run(shell, args) {
  return new Promise((resolve) => {
    const child = spawn(shell, args, {
      stdio: "inherit",
      shell: false,
      cwd: repoRoot,
      env: process.env,
    });
    child.on("error", (err) => {
      if (err.code === "ENOENT") {
        console.error(
          `Could not find '${shell}'. Install PowerShell 7.4+ (https://aka.ms/powershell) and ensure 'pwsh' is on PATH.`
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
  if (argv.length === 0 || argv.includes("-h") || argv.includes("--help")) {
    process.stdout.write(HELP);
    process.exit(0);
  }

  const command = argv[0];
  const rest = argv.slice(1);
  const apply = rest.includes("--apply");

  if (!existsSync(agentHubPs1)) {
    console.error(`Missing ${agentHubPs1}`);
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
