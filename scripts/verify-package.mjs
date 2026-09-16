#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const npmCli = process.env.npm_execpath;
const command = npmCli ? process.execPath : process.platform === "win32" ? "npm.cmd" : "npm";
const args = npmCli
  ? [npmCli, "pack", "--dry-run", "--json"]
  : ["pack", "--dry-run", "--json"];
const run = spawnSync(command, args, {
  cwd: fileURLToPath(new URL("..", import.meta.url)),
  encoding: "utf8",
  shell: false,
});

if (run.error) {
  process.stderr.write(`${run.error.message}\n`);
  process.exit(1);
}

if (run.status !== 0) {
  process.stderr.write(run.stderr || run.stdout || "npm pack failed without output.\n");
  process.exit(run.status ?? 1);
}

const report = JSON.parse(run.stdout)[0];
const paths = new Set(report.files.map((entry) => entry.path.replaceAll("\\", "/")));
const required = [
  "scripts/agenthub-cli.mjs",
  "scripts/AgentHub.ps1",
  "scripts/Repair-QwenCodeMcpOAuth.mjs",
  "scripts/Validate-AgentHub.ps1",
  "registry/agents.json",
  "registry/capabilities.json",
  "policy-core.md",
  "README.md",
  "LICENSE",
];
const forbidden = [
  /^overlays\/personal\//,
  /^agenthub\.profile\.json$/,
  /^tests\//,
  /^\.github\//,
  /node_modules/,
  /(^|\/)\.env($|\.(?!example$))/,
];

const missing = required.filter((path) => !paths.has(path));
const leaked = [...paths].filter((path) => forbidden.some((pattern) => pattern.test(path)));

if (missing.length || leaked.length) {
  if (missing.length) process.stderr.write(`Missing required package files: ${missing.join(", ")}\n`);
  if (leaked.length) process.stderr.write(`Forbidden package files: ${leaked.join(", ")}\n`);
  process.exit(1);
}

process.stdout.write(
  `PASS: ${report.entryCount} files, ${report.size} packed bytes, source-bundle CLI/registry files present, private/runtime paths excluded; npm publication remains disabled.\n`,
);
