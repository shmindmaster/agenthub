#!/usr/bin/env node
// Resolves a safe on-screen-text placement for one scene from its capture-manifest geometry, so
// headlines/callouts never cover the focus region, a protected region, or the cursor destination.
// Usage:
//   node compute-overlay-placement.mjs --manifest <path> --canvas-width <n> --canvas-height <n>
//     --text-width <n> --text-height <n> [--margin <px>] [--cursor-margin <px>]
//     [--safe-area-percent <n>]
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : fallback;
};
const num = (name, fallback) => {
  const v = flag(name);
  return v === undefined ? fallback : Number(v);
};

const manifestPath = flag("--manifest");
const canvasWidth = num("--canvas-width");
const canvasHeight = num("--canvas-height");
const textWidth = num("--text-width");
const textHeight = num("--text-height");
const margin = num("--margin", 24);
const cursorMargin = num("--cursor-margin", 80);
const safeAreaPercent = num("--safe-area-percent", 5);

if (!manifestPath || !canvasWidth || !canvasHeight || !textWidth || !textHeight) {
  console.error(
    "Usage: node compute-overlay-placement.mjs --manifest <path> --canvas-width <n> " +
      "--canvas-height <n> --text-width <n> --text-height <n> " +
      "[--margin <px>] [--cursor-margin <px>] [--safe-area-percent <n>]",
  );
  process.exit(1);
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

const viewport = manifest.viewport ?? { width: canvasWidth, height: canvasHeight };
const scaleX = canvasWidth / viewport.width;
const scaleY = canvasHeight / viewport.height;

function scaleRect(rect) {
  return {
    x: rect.x * scaleX,
    y: rect.y * scaleY,
    width: rect.width * scaleX,
    height: rect.height * scaleY,
  };
}

function inflate(rect, by) {
  return { x: rect.x - by, y: rect.y - by, width: rect.width + 2 * by, height: rect.height + 2 * by };
}

function intersects(a, b) {
  return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}

function within(rect, bounds) {
  return rect.x >= bounds.x && rect.y >= bounds.y &&
    rect.x + rect.width <= bounds.x + bounds.width &&
    rect.y + rect.height <= bounds.y + bounds.height;
}

const occupied = [];
if (manifest.focus) occupied.push({ rect: inflate(scaleRect(manifest.focus), margin), source: "focus" });
for (const region of manifest.protectedRegions ?? []) {
  occupied.push({ rect: inflate(scaleRect(region), margin), source: "protectedRegion" });
}
if (manifest.cursor?.to) {
  const [cx, cy] = manifest.cursor.to;
  const scaledCursor = { x: cx * scaleX, y: cy * scaleY, width: 0, height: 0 };
  occupied.push({ rect: inflate(scaledCursor, cursorMargin), source: "cursorDestination" });
}

const safeArea = {
  x: (canvasWidth * safeAreaPercent) / 100,
  y: (canvasHeight * safeAreaPercent) / 100,
  width: canvasWidth - (2 * canvasWidth * safeAreaPercent) / 100,
  height: canvasHeight - (2 * canvasHeight * safeAreaPercent) / 100,
};

const candidates = [
  { anchor: "upper-left", x: safeArea.x, y: safeArea.y },
  { anchor: "upper-right", x: safeArea.x + safeArea.width - textWidth, y: safeArea.y },
  { anchor: "lower-left", x: safeArea.x, y: safeArea.y + safeArea.height - textHeight },
  { anchor: "lower-right", x: safeArea.x + safeArea.width - textWidth, y: safeArea.y + safeArea.height - textHeight },
  {
    anchor: "lower-center",
    x: safeArea.x + (safeArea.width - textWidth) / 2,
    y: safeArea.y + safeArea.height - textHeight,
  },
];

const attempts = [];
for (const candidate of candidates) {
  const rect = { x: candidate.x, y: candidate.y, width: textWidth, height: textHeight };
  const conflicts = occupied.filter((o) => intersects(rect, o.rect)).map((o) => o.source);
  const fitsCanvas = within(rect, safeArea);
  const ok = conflicts.length === 0 && fitsCanvas;
  attempts.push({ anchor: candidate.anchor, rect, ok, conflicts, fitsCanvas });
  if (ok) {
    console.log(JSON.stringify({ region: { anchor: candidate.anchor, ...rect }, attempts }, null, 2));
    process.exit(0);
  }
}

console.log(
  JSON.stringify(
    {
      region: null,
      reason:
        "No candidate overlay position clears the focus region, protected regions, and cursor " +
        "destination with the required margins. Use a dedicated title beat, re-crop the frame, " +
        "shorten the text, or drop the visual headline for this scene.",
      attempts,
    },
    null,
    2,
  ),
);
process.exit(0);
