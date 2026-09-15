#!/usr/bin/env node
// Cross-repo render wrapper: finds the target repo's actual Remotion workspace and
// package.json script names (which differ per repo -- SubOps uses render:all/
// render:priority/render:still, CoLedger uses bespoke per-video scripts like
// render:v1/render:social) and runs the closest match, rather than assuming one
// fixed set of script names everywhere.
//
// Usage: node render-videos.mjs --repo <path> [--script <name>] [--list] [--id <video-id>]
//          [--format wide|vertical|square]
// Any --id/--format (or other unrecognized) flags are forwarded to the underlying package.json
// script as extra CLI args -- this script does not know what a target repo's render script
// accepts, it passes intent through rather than guessing.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { detectPackageManager, detectVideoConvention, readJson } from "./lib.mjs";

const args = process.argv.slice(2);
function flag(name) {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}
const listOnly = args.includes("--list");

const KNOWN_FLAGS = new Set(["--repo", "--script", "--list"]);
const passthroughArgs = [];
for (let i = 0; i < args.length; i++) {
  if (KNOWN_FLAGS.has(args[i])) {
    if (args[i] !== "--list") i++; // skip this flag's value
    continue;
  }
  passthroughArgs.push(args[i]);
}

const repoPath = flag("--repo");
if (!repoPath || !existsSync(repoPath)) {
  console.error("Usage: node render-videos.mjs --repo <path> [--script <name>] [--list]");
  process.exit(1);
}

const detection = detectVideoConvention(repoPath);
if (!detection.remotionDir) {
  console.error(
    `No Remotion project found under ${repoPath} (detected: ${detection.convention}). ` +
      "Run scaffold-video-workspace.mjs first, or point --repo at the right directory.",
  );
  process.exit(1);
}

const pkgPath = `${detection.remotionDir}/package.json`;
if (!existsSync(pkgPath)) {
  console.error(`No package.json at ${detection.remotionDir}`);
  process.exit(1);
}
const pkg = readJson(pkgPath);
const renderScripts = Object.keys(pkg.scripts ?? {}).filter((name) => name.includes("render"));

if (renderScripts.length === 0) {
  console.error(`No render-related scripts found in ${pkgPath}. Available scripts: ${Object.keys(pkg.scripts ?? {}).join(", ")}`);
  process.exit(1);
}

if (listOnly) {
  console.log(`Remotion project: ${detection.remotionDir}`);
  console.log("Available render scripts:");
  for (const name of renderScripts) console.log(`  - ${name}: ${pkg.scripts[name]}`);
  process.exit(0);
}

const requested = flag("--script");
let scriptName;
if (requested) {
  if (!renderScripts.includes(requested)) {
    console.error(`"${requested}" is not a render script in ${pkgPath}. Available: ${renderScripts.join(", ")}`);
    process.exit(1);
  }
  scriptName = requested;
} else if (renderScripts.includes("render:all")) {
  scriptName = "render:all";
} else if (renderScripts.length === 1) {
  scriptName = renderScripts[0];
} else {
  console.error(
    `Multiple render scripts exist and none is named "render:all" -- pass --script to pick one. Available: ${renderScripts.join(", ")}`,
  );
  process.exit(1);
}

const packageManager = detectPackageManager(detection.remotionDir);
const runArgs = ["run", scriptName, ...(passthroughArgs.length > 0 ? ["--", ...passthroughArgs] : [])];
console.log(`Running "${packageManager} ${runArgs.join(" ")}" in ${detection.remotionDir} ...`);
const result = spawnSync(packageManager, runArgs, {
  cwd: detection.remotionDir,
  stdio: "inherit",
  shell: process.platform === "win32",
});

if (result.error) {
  console.error(result.error);
  process.exit(1);
}
process.exit(result.status ?? 1);
