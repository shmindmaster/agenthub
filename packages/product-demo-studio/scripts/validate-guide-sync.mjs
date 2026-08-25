#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const expected = new Map([
  ["skills/product-demo-studio/references/killer-demo-production-guide.md", "C41A65F5ADB925657C67995D8ECD74FEA746B865623F3A1FEBF320A4708546A0"],
  ["skills/product-demo-studio/references/Visual-Asset-Guide.md", "68991C7D4FB72BEE01570C9CFD0E4C71A314DF5FD4816E689B49E67AE044EA0B"]
]);
const failures = [];

for (const [path, expectedHash] of expected) {
  const bytes = await readFile(new URL(path, root));
  // The reviewed hashes are over repository-normalized LF text. Git may materialize CRLF on
  // Windows, which must not be reported as content drift.
  const normalized = bytes.toString("utf8").replace(/\r\n/g, "\n");
  const actual = createHash("sha256").update(normalized).digest("hex").toUpperCase();
  if (actual !== expectedHash) failures.push(`${path}: expected ${expectedHash}, got ${actual}`);
}

const manifests = [
  JSON.parse(await readFile(new URL(".claude-plugin/plugin.json", root), "utf8")),
  JSON.parse(await readFile(new URL(".codex-plugin/plugin.json", root), "utf8")),
  JSON.parse(await readFile(new URL(".cursor-plugin/plugin.json", root), "utf8")),
  JSON.parse(await readFile(new URL(".qoder-plugin/plugin.json", root), "utf8"))
];
if (manifests.some(manifest => manifest.version !== "1.8.1")) {
  failures.push("All host-native plugin manifests must be version 1.8.1.");
}
const visualSkill = await readFile(new URL("skills/product-demo-studio-visual-assets/SKILL.md", root), "utf8");
if (!visualSkill.includes("name: product-demo-studio-visual-assets")) {
  failures.push("Visual-assets skill is missing or has invalid frontmatter.");
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("PASS: product-demo and visual-asset guides match the reviewed sources; host-native plugin versions and visual skill are valid.");
