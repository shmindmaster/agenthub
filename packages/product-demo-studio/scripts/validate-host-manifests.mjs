#!/usr/bin/env node
// Check that every host in policy/host-parity.json#mappedHosts either ships a
// manifest or carries a documented reason it cannot.
//
// validate-host-parity.mjs compares mappedHosts against the external registry's
// hostMappings. It never looks at the plugin directory, so a host can be mapped,
// pass parity, and have no manifest at all. This closes that gap.
//
// Static presence is not parity. Passing here proves the files exist, parse, and
// agree on identity — not that any host loads them. See
// policy/host-parity.json#validationScope.
//
// Exit 0 pass, 1 fail, 2 could not evaluate.
//
// Usage: node validate-host-manifests.mjs [--root <plugin root>]

import { readFileSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const flag = argv.indexOf("--root");
const ROOT = resolve(flag >= 0 && argv[flag + 1] ? argv[flag + 1] : join(here, ".."));

const parityPath = join(ROOT, "policy", "host-parity.json");
const inventoryPath = join(ROOT, "policy", "host-manifests.json");

for (const [label, p] of [["host-parity.json", parityPath], ["host-manifests.json", inventoryPath]]) {
  if (!existsSync(p)) {
    console.error(`[blocked] ${label} not found at ${p}`);
    process.exit(2);
  }
}

const parity = JSON.parse(readFileSync(parityPath, "utf8"));
const inventory = JSON.parse(readFileSync(inventoryPath, "utf8"));

const NEEDS_MANIFEST = new Set(["format-verified", "format-unverified"]);
const NO_MANIFEST = new Set(["auto-detected", "not-applicable", "documentation-not-read"]);
const errors = [];
const warnings = [];

/* --- inventory covers mappedHosts exactly, in both directions --------- */

const mapped = new Set(parity.mappedHosts ?? []);
const inventoried = new Set(inventory.hosts.map((h) => h.hostId));

for (const id of mapped) {
  if (!inventoried.has(id)) errors.push(`mapped host "${id}" has no entry in host-manifests.json`);
}
for (const id of inventoried) {
  if (!mapped.has(id)) errors.push(`host-manifests.json lists "${id}", which is not in host-parity.json#mappedHosts`);
}

/* --- capability version agreement ------------------------------------- */

if (inventory.capabilityVersion !== parity.capabilityVersion) {
  errors.push(
    `capabilityVersion mismatch: host-parity.json says ${parity.capabilityVersion}, host-manifests.json says ${inventory.capabilityVersion}`,
  );
}

/* --- each entry is internally coherent, and its manifest is real ------- */

const seenPaths = new Map();

for (const h of inventory.hosts) {
  const label = `host "${h.hostId}"`;

  if (!h.verification || !(NEEDS_MANIFEST.has(h.verification) || NO_MANIFEST.has(h.verification))) {
    errors.push(`${label}: unknown verification "${h.verification}"`);
    continue;
  }

  if (NO_MANIFEST.has(h.verification)) {
    if (h.manifestPath) errors.push(`${label}: verification "${h.verification}" must not declare a manifestPath`);
    // A host with no manifest owes an explanation. Silence is how a gap persists.
    if (!h.openQuestion && !h.notes) {
      errors.push(`${label}: no manifest and no documented reason. Add openQuestion or notes.`);
    }
    if (h.verification === "documentation-not-read") {
      warnings.push(`${label}: mapped but unresolved — plugin format has not been established`);
    }
    if (h.verification === "auto-detected") {
      // No local manifest means no local signal if the host drops its shim.
      if (!h.source) errors.push(`${label}: auto-detected requires a source URL for the translation rule`);
      if (!existsSync(join(ROOT, ".claude-plugin", "plugin.json"))) {
        errors.push(`${label}: relies on the Claude layout, but .claude-plugin/plugin.json is missing`);
      }
      if (h.openQuestion) warnings.push(`${label}: auto-detection carries an unresolved caveat`);
    }
    continue;
  }

  if (!h.manifestPath) {
    errors.push(`${label}: verification "${h.verification}" requires a manifestPath`);
    continue;
  }

  const p = join(ROOT, h.manifestPath);
  if (!existsSync(p)) {
    errors.push(`${label}: manifest missing at ${h.manifestPath}`);
    continue;
  }

  let manifest;
  try {
    manifest = JSON.parse(readFileSync(p, "utf8"));
  } catch (e) {
    errors.push(`${label}: ${h.manifestPath} does not parse — ${e.message}`);
    continue;
  }

  // Identity must agree across every host, or installs collide under different names.
  if (manifest.name !== inventory.capabilityId) {
    errors.push(`${label}: ${h.manifestPath} name "${manifest.name}" does not match capabilityId "${inventory.capabilityId}"`);
  }
  if (manifest.version && manifest.version !== inventory.capabilityVersion) {
    errors.push(`${label}: ${h.manifestPath} version "${manifest.version}" does not match capabilityVersion "${inventory.capabilityVersion}"`);
  }

  // Kebab-case identity is required by at least one host and harmless everywhere.
  if (typeof manifest.name === "string" && !/^[a-z0-9][a-z0-9-]*$/.test(manifest.name)) {
    errors.push(`${label}: name "${manifest.name}" is not lowercase kebab-case`);
  }

  // A shared path means two hosts read the same bytes. That is legal and worth stating.
  if (seenPaths.has(h.manifestPath)) {
    const other = seenPaths.get(h.manifestPath);
    warnings.push(`${h.manifestPath} is shared by "${other}" and "${h.hostId}" — one file must satisfy both formats`);
  } else {
    seenPaths.set(h.manifestPath, h.hostId);
  }

  if (h.verification === "format-unverified") {
    warnings.push(`${label}: manifest shipped but format not verified against host documentation`);
  }

  // Referenced component directories must exist, or the manifest points at nothing.
  for (const key of ["skills", "agents", "commands"]) {
    const v = manifest[key];
    if (typeof v === "string" && !existsSync(join(ROOT, v))) {
      errors.push(`${label}: ${h.manifestPath} declares ${key} "${v}", which does not exist`);
    }
  }
  if (typeof manifest.mcpServers === "string" && !existsSync(join(ROOT, manifest.mcpServers))) {
    errors.push(`${label}: ${h.manifestPath} declares mcpServers "${manifest.mcpServers}", which does not exist`);
  }
}

/* --- report ----------------------------------------------------------- */

const withManifest = inventory.hosts.filter((h) => NEEDS_MANIFEST.has(h.verification));
const verified = withManifest.filter((h) => h.verification === "format-verified");
const auto = inventory.hosts.filter((h) => h.verification === "auto-detected");
const unresolved = inventory.hosts.filter((h) => h.verification === "documentation-not-read");

console.log(`${inventory.hosts.length} mapped host(s)`);
console.log(`  ${withManifest.length} ship a manifest (${verified.length} format-verified)`);
console.log(`  ${auto.length} auto-detect the Claude layout`);
console.log(`  ${inventory.hosts.length - withManifest.length - auto.length} without either, each with a documented reason`);
for (const h of inventory.hosts) {
  const mark = h.manifestPath ?? `(${h.verification})`;
  console.log(`    ${h.hostId.padEnd(16)} ${mark}`);
}
if (unresolved.length) {
  console.log(`\nUnresolved: ${unresolved.map((h) => h.hostId).join(", ")}`);
}

for (const w of warnings) console.log(`\n[warn] ${w}`);

if (errors.length) {
  console.error(`\n${errors.length} error(s):`);
  for (const e of errors) console.error(`  [error] ${e}`);
  process.exit(1);
}
console.log(`\nhost manifest inventory consistent. ${inventory.loadTestStatus}`);
