#!/usr/bin/env node
// Verify both calibration fixture sets before any reviewer is pointed at them.
//
// This is not the calibration run. It proves the fixtures themselves have not
// drifted — checksums match, masters decode, and every expected readiness sheet
// still satisfies validate-demo-readiness.mjs. A calibration result computed
// against drifted fixtures is worthless, so this gate runs first.
//
// Exit 0 pass, 1 fail, 2 could not evaluate.
//
// Usage: node verify-fixtures.mjs [--root <plugin root>]

import { readFileSync, existsSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const i = argv.indexOf("--root");
const ROOT = resolve(i >= 0 && argv[i + 1] ? argv[i + 1] : join(here, ".."));

const errors = [];
const notes = [];
const fail = (m) => errors.push(m);

const sha256 = (p) => createHash("sha256").update(readFileSync(p)).digest("hex");

function checkRef(label, ref) {
  const p = join(ROOT, ref.artifactPath);
  if (!existsSync(p)) return fail(`${label}: missing ${ref.artifactPath}`);
  const actual = sha256(p);
  if (actual !== ref.sha256) {
    fail(`${label}: checksum drift on ${ref.artifactPath}\n    expected ${ref.sha256}\n    actual   ${actual}`);
  }
}

/* -------------------------------------------------------------- *
 * Worthiness set — running applications
 * -------------------------------------------------------------- */

const wCatalogPath = join(ROOT, "fixtures/worthiness/catalog.json");
if (!existsSync(wCatalogPath)) {
  console.error("worthiness catalog not found; cannot evaluate");
  process.exit(2);
}
const w = JSON.parse(readFileSync(wCatalogPath, "utf8"));

if (w.fixtures.length < 5) fail(`worthiness: expected at least 5 fixtures, found ${w.fixtures.length}`);
if (!w.fixtures.some((f) => f.expectedVerdict === "PASS")) {
  // A set of only-defective fixtures cannot detect a reviewer that rejects everything.
  fail("worthiness: no clean fixture. Over-rejection would be undetectable.");
}
if (!w.fixtures.some((f) => f.mustTrip.some((t) => t.classification === "capture-fixable"))) {
  fail("worthiness: no capture-fixable fixture. The classification boundary is only tested from one side.");
}

const readinessValidator = join(ROOT, "scripts/validate-demo-readiness.mjs");
for (const f of w.fixtures) {
  checkRef(`worthiness/${f.id}`, f.app);
  checkRef(`worthiness/${f.id}`, f.expectedReadiness);

  if (existsSync(readinessValidator)) {
    const sheet = join(ROOT, f.expectedReadiness.artifactPath);
    const r = spawnSync(process.execPath, [readinessValidator, sheet], { encoding: "utf8" });
    if (r.status !== 0) {
      fail(`worthiness/${f.id}: expected readiness sheet rejected by validate-demo-readiness.mjs\n${(r.stderr || r.stdout || "").trim().split("\n").slice(0, 4).map((l) => "    " + l).join("\n")}`);
    }
  } else {
    notes.push("validate-demo-readiness.mjs not found; readiness sheets were not cross-validated");
  }
}

/* -------------------------------------------------------------- *
 * Craft set — rendered masters
 * -------------------------------------------------------------- */

const cCatalogPath = join(ROOT, "fixtures/craft/catalog.json");
if (!existsSync(cCatalogPath)) {
  console.error("craft catalog not found; cannot evaluate");
  process.exit(2);
}
const c = JSON.parse(readFileSync(cCatalogPath, "utf8"));

const REQUIRED_IDS = ["buried-hero", "feature-rung", "no-hold", "dead-wait", "three-heroes", "clean-pass"];
for (const id of REQUIRED_IDS) {
  if (!c.fixtures.some((f) => f.id === id)) fail(`craft: missing required fixture "${id}"`);
}
if (!c.fixtures.some((f) => f.expectedVerdict === "PASS")) {
  fail("craft: no clean fixture. Over-rejection would be undetectable.");
}

const haveFfprobe = spawnSync("ffprobe", ["-version"], { encoding: "utf8" }).status === 0;
for (const f of c.fixtures) {
  for (const [name, ref] of Object.entries(f.artifacts)) checkRef(`craft/${f.id}/${name}`, ref);

  if (!haveFfprobe) continue;
  const master = join(ROOT, f.artifacts.master.artifactPath);
  if (!existsSync(master)) continue;
  const probe = spawnSync(
    "ffprobe",
    ["-v", "error", "-show_entries", "stream=codec_type,codec_name", "-show_entries", "format=duration", "-of", "json", master],
    { encoding: "utf8" },
  );
  if (probe.status !== 0) {
    fail(`craft/${f.id}: master does not decode`);
    continue;
  }
  const meta = JSON.parse(probe.stdout);
  const kinds = new Set((meta.streams ?? []).map((s) => s.codec_type));
  if (!kinds.has("video")) fail(`craft/${f.id}: no video stream`);
  if (!kinds.has("audio")) fail(`craft/${f.id}: no audio stream`);
  const dur = Number(meta.format?.duration ?? 0);
  if (Math.abs(dur - f.durationSeconds) > 0.25) {
    fail(`craft/${f.id}: duration ${dur.toFixed(2)}s does not match catalog ${f.durationSeconds}s`);
  }
}

/* -------------------------------------------------------------- *
 * Cross-set invariant
 * -------------------------------------------------------------- */

// dead-wait exists in both sets and means different things. The worthiness copy
// is a running app whose wait has no feedback; the craft copy is a master with
// the wait left uncut. Confusing them is how the two forms get collapsed.
const wDead = w.fixtures.find((f) => f.id === "dead-wait");
const cDead = c.fixtures.find((f) => f.id === "dead-wait");
if (wDead && cDead && wDead.app.sha256 === cDead.artifacts.master.sha256) {
  fail("dead-wait: worthiness and craft fixtures are the same artifact. They test different things.");
}

/* -------------------------------------------------------------- */

console.log(`worthiness: ${w.fixtures.length} fixture(s)`);
for (const f of w.fixtures) {
  console.log(`  ${f.id.padEnd(12)} ${f.expectedVerdict.padEnd(11)} ${f.mustTrip.map((t) => `${t.criterion} (${t.classification})`).join(", ") || "-"}`);
}
console.log(`craft: ${c.fixtures.length} fixture(s)`);
for (const f of c.fixtures) {
  console.log(`  ${f.id.padEnd(14)} ${f.expectedVerdict.padEnd(5)} ${String(f.durationSeconds).padStart(6)}s  ${f.mustTrip.map((t) => `${t.criterion} (${t.classification})`).join(", ") || "-"}`);
}
for (const n of new Set(notes)) console.log(`\n[note] ${n}`);

if (errors.length) {
  console.error(`\n${errors.length} problem(s):`);
  for (const e of errors) console.error(`  [error] ${e}`);
  console.error("\nDo not run calibration against drifted fixtures. Rebuild with build-*-fixtures.mjs, or diagnose the change.");
  process.exit(1);
}
console.log("\nfixtures verified.");
