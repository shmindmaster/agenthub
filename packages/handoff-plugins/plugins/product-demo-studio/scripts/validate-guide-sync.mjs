#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const expected = new Map([
  ["skills/product-demo-studio/references/killer-demo-production-guide.md", "DB66F309E10523E3408C684E5D0CF7F1AF0F6A3CBEE2AF4F477ACD6B3175717A"],
  ["skills/product-demo-studio/references/Visual-Asset-Guide.md", "10FF70EB3006572BB1151919ED97A73CE8E4528B3DF19627C83D4BEF8FDAD159"]
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
  JSON.parse(await readFile(new URL(".devin-plugin/plugin.json", root), "utf8")),
  JSON.parse(await readFile(new URL(".qoder-plugin/plugin.json", root), "utf8"))
];
if (manifests.some(manifest => manifest.version !== "1.3.1")) {
  failures.push("All host-native plugin manifests must be version 1.3.1.");
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
