#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "skills",
  "product-demo-studio-remotion",
  "rules",
);
const provenancePath = join(root, "PROVENANCE.json");
const failures = [];
let provenance;

try {
  provenance = JSON.parse(readFileSync(provenancePath, "utf8"));
} catch (error) {
  console.error(`Remotion rule provenance is unreadable: ${error.message}`);
  process.exit(1);
}

if (provenance.schemaVersion !== "1.0.0") failures.push("unsupported provenance schema");
if (provenance.upstream?.capability !== "remotion:remotion-best-practices") {
  failures.push("wrong upstream capability owner");
}
if (!/^\d+\.\d+\.\d+$/.test(provenance.upstream?.version ?? "")) {
  failures.push("upstream version is not pinned");
}

const upstreamFiles = [...(provenance.upstream?.files ?? [])].sort();
const expectedFiles = [
  ...upstreamFiles,
  ...(provenance.agentHubOverrides ?? []),
  ...(provenance.productDemoSupplements ?? []),
  "PROVENANCE.json",
].sort();
const actualFiles = readdirSync(root, { withFileTypes: true })
  .filter((entry) => entry.isFile())
  .map((entry) => entry.name)
  .sort();

if (JSON.stringify(actualFiles) !== JSON.stringify(expectedFiles)) {
  failures.push("rule inventory differs from pinned upstream, overrides, and supplements");
}

const hash = createHash("sha256");
for (const name of upstreamFiles) {
  const path = join(root, name);
  if (!existsSync(path)) {
    failures.push(`missing upstream mirror ${name}`);
    continue;
  }
  hash.update(name);
  hash.update("\0");
  hash.update(readFileSync(path, "utf8").replace(/\r\n/g, "\n"));
  hash.update("\0");
}
const actualHash = hash.digest("hex");
if (actualHash !== provenance.upstream?.normalizedTreeSha256) {
  failures.push(
    `upstream mirror hash ${actualHash} does not match ${provenance.upstream?.normalizedTreeSha256}`,
  );
}

const voiceover = readFileSync(join(root, "voiceover.md"), "utf8");
if (!voiceover.includes("`use-elevenlabs` is the single provider owner") ||
    voiceover.includes("api.elevenlabs.io")) {
  failures.push("voiceover override bypasses the canonical use-elevenlabs owner");
}

if (failures.length > 0) {
  console.error(`Remotion rule provenance FAILED (${failures.length}):`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(
  `PASS: ${upstreamFiles.length} Remotion rules match pinned ${provenance.upstream.version}; ` +
    "AgentHub overrides and supplements are explicit.",
);
