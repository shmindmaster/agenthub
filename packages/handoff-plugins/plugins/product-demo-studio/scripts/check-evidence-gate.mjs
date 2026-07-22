#!/usr/bin/env node
// Validates a release-evidence manifest before a render/capture may be treated as
// "approved". classification/reviewedBy are human attestations -- this script
// never sets or upgrades them; it only validates what a human already wrote, plus
// runs a best-effort regex scan (warnings only) over accompanying text for common
// PII/secret/dollar-figure shapes.
//
// Fast path (no JSON file to write first): pass the manifest fields as flags --
// still requires an explicit --reviewed-by name and --classification, it just
// skips the file-authoring step:
//   node check-evidence-gate.mjs --asset out/v1.mp4 --classification approved \
//     --reviewed-by jane.doe --synthetic-data-confirmed [--notes "..."] [--text captions.srt]
//
// File path (unchanged): node check-evidence-gate.mjs --manifest <path> [--text <path>]
import { existsSync, readFileSync } from "node:fs";
import { readJson } from "./lib.mjs";

const args = process.argv.slice(2);
function flag(name) {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}

const manifestPath = flag("--manifest");
const inlineAsset = flag("--asset");

let manifest;
if (manifestPath) {
  if (!existsSync(manifestPath)) {
    console.error(`--manifest path does not exist: ${manifestPath}`);
    process.exit(1);
  }
  manifest = readJson(manifestPath);
} else if (inlineAsset) {
  manifest = {
    assetPath: inlineAsset,
    classification: flag("--classification"),
    reviewedBy: flag("--reviewed-by"),
    reviewedAt: flag("--reviewed-at") ?? new Date().toISOString().slice(0, 10),
    syntheticDataConfirmed: args.includes("--synthetic-data-confirmed"),
    watchThroughStatus: flag("--watch-through-status") ?? (args.includes("--watched") ? "completed" : "pending"),
    redactionNotes: flag("--notes"),
  };
} else {
  console.error("Usage: node check-evidence-gate.mjs --manifest <path> [--text <path>]");
  console.error("   or: node check-evidence-gate.mjs --asset <path> --classification <c> --reviewed-by <name> --synthetic-data-confirmed [--notes ...] [--text <path>]");
  console.error(`See release-evidence.example.json in this directory for the expected shape.`);
  process.exit(1);
}
const errors = [];
const placeholderNames = ["", "todo", "tbd", "reviewer", "changeme", "xxx"];

if (!manifest.assetPath) errors.push("assetPath is required");

if (!["approved", "needs-redaction", "rejected"].includes(manifest.classification)) {
  errors.push('classification must be "approved", "needs-redaction", or "rejected"');
}

if (!manifest.reviewedBy || placeholderNames.includes(manifest.reviewedBy.toLowerCase().trim())) {
  errors.push("reviewedBy must name a real reviewer -- this is a human attestation, not something to auto-fill");
}

if (!manifest.reviewedAt || Number.isNaN(Date.parse(manifest.reviewedAt))) {
  errors.push("reviewedAt must be a valid date");
}

if (typeof manifest.syntheticDataConfirmed !== "boolean") {
  errors.push("syntheticDataConfirmed must be true or false");
}

if (manifest.classification === "approved" && manifest.syntheticDataConfirmed !== true) {
  errors.push('classification cannot be "approved" unless syntheticDataConfirmed is true');
}

// No video ships without a recorded human watch-through (start-to-finish at normal speed, captions
// on then off, at delivery size). This is a human attestation -- never auto-fill it as "completed".
if (manifest.classification === "approved" && manifest.watchThroughStatus !== "completed") {
  errors.push(
    'classification cannot be "approved" unless watchThroughStatus is "completed" -- a named human must ' +
      "watch the master start-to-finish (captions on, then off, at delivery size) first",
  );
}

if (errors.length > 0) {
  console.error(`Evidence gate FAILED for ${manifest.assetPath ?? manifestPath}:`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}

console.log(`Evidence gate passed for ${manifest.assetPath} (classification: ${manifest.classification}).`);

const textPath = flag("--text");
if (textPath && existsSync(textPath)) {
  const text = readFileSync(textPath, "utf8");
  const heuristics = [
    { name: "email address", pattern: /[\w.+-]+@[\w-]+\.[\w.-]+/g },
    { name: "SSN-like pattern", pattern: /\b\d{3}-\d{2}-\d{4}\b/g },
    { name: "phone-like pattern", pattern: /\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b/g },
    { name: "dollar figure", pattern: /\$\s?\d[\d,]*(\.\d+)?/g },
    {
      name: "common secret/token shape",
      pattern: /\b(sk|pk|ghp|gho|xox[baprs]|AIza|AKIA)[A-Za-z0-9_-]{10,}\b/g,
    },
  ];

  let warned = false;
  for (const { name, pattern } of heuristics) {
    const matches = text.match(pattern);
    if (matches && matches.length > 0) {
      warned = true;
      console.warn(`  warning: found ${matches.length} possible ${name}(s) in ${textPath} -- review before reuse.`);
    }
  }
  if (!warned) console.log(`  no heuristic matches in ${textPath} (this is not a guarantee -- it's a first-pass assist).`);
} else if (textPath) {
  console.warn(`  warning: --text path ${textPath} does not exist, skipping heuristic scan.`);
}
