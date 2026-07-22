#!/usr/bin/env node
// Validates one or more capture manifests against the shape documented in
// skills/product-demo-studio-capture/SKILL.md. Accepts a single manifest object, a JSON array of
// manifests, or an object with a top-level "captures" array.
// Usage: node validate-capture-manifest.mjs <path-to-manifest.json>
import { readFileSync } from "node:fs";

const manifestPath = process.argv[2];
if (!manifestPath) {
  console.error("Usage: node validate-capture-manifest.mjs <path-to-manifest.json>");
  process.exit(1);
}

const parsed = JSON.parse(readFileSync(manifestPath, "utf8"));
const manifests = Array.isArray(parsed) ? parsed : (parsed.captures ?? [parsed]);

function isRect(value) {
  return (
    value &&
    typeof value.x === "number" &&
    typeof value.y === "number" &&
    typeof value.width === "number" &&
    value.width > 0 &&
    typeof value.height === "number" &&
    value.height > 0
  );
}

function isPoint(value) {
  return Array.isArray(value) && value.length === 2 && value.every((n) => typeof n === "number");
}

let errorCount = 0;

manifests.forEach((manifest, index) => {
  const label = manifest.scenario ?? manifest.beat ?? `#${index}`;
  const fail = (message) => {
    console.error(`[error] ${label}: ${message}`);
    errorCount++;
  };

  if (!manifest.scenario && !manifest.beat) fail('missing "scenario" or "beat" identifier.');
  if (!manifest.route) fail('missing "route".');

  if (!manifest.viewport || typeof manifest.viewport.width !== "number" || typeof manifest.viewport.height !== "number") {
    fail('missing or invalid "viewport" ({ width, height }).');
  }

  if (manifest.focus !== undefined && !isRect(manifest.focus)) {
    fail('"focus" must be a rect ({ x, y, width, height } with positive width/height).');
  }

  if (manifest.protectedRegions !== undefined) {
    if (!Array.isArray(manifest.protectedRegions)) {
      fail('"protectedRegions" must be an array of rects.');
    } else {
      manifest.protectedRegions.forEach((region, i) => {
        if (!isRect(region)) fail(`protectedRegions[${i}] is not a valid rect.`);
      });
    }
  }

  if (manifest.cursor !== undefined) {
    if (manifest.cursor.from !== undefined && !isPoint(manifest.cursor.from)) {
      fail('"cursor.from" must be a [x, y] point.');
    }
    if (manifest.cursor.to !== undefined && !isPoint(manifest.cursor.to)) {
      fail('"cursor.to" must be a [x, y] point.');
    }
  }

  if (!manifest.focus && (!manifest.protectedRegions || manifest.protectedRegions.length === 0)) {
    console.warn(
      `[warn] ${label}: no "focus" and no "protectedRegions" -- overlay placement has nothing to ` +
        "avoid, which is only correct for scenes with no on-screen product UI.",
    );
  }
});

console.log(`\n${manifests.length} manifest(s) checked: ${errorCount} error(s).`);
process.exit(errorCount > 0 ? 1 : 0);
