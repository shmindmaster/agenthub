#!/usr/bin/env node
// Appends a new video entry to whichever catalog format a repo's video workspace
// already uses (SubOps-style content.ts, CoLedger-style JSON, or GentleNext-style
// markdown table), validating the audience enum and computing durationInFrames.
//
// Legacy migration-only writer. New catalogs belong in the external AgentHub workspace.
// Usage: node new-video-catalog-entry.mjs --repo <path> --entry <path-to-entry.json> --allow-legacy-repo-write
//    or: node new-video-catalog-entry.mjs --repo <path> --entry-json '<inline json>' --allow-legacy-repo-write
//
// entry shape (durationInFrames is computed, do not include it):
//   {
//     "id": "V2-NewFeature", "audience": "Pillar", "title": "...", "subtitle": "...",
//     "durationSeconds": 60, "cta": "...",
//     "scenes": [ { "durationSeconds": 10, "eyebrow": "...", "title": "...", "caption": "...", "motif": "..." } ]
//   }
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AUDIENCES, FPS, detectVideoConvention, readJson } from "./lib.mjs";

const args = process.argv.slice(2);
function flag(name) {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}

const repoPath = flag("--repo");
const entryPath = flag("--entry");
const entryJson = flag("--entry-json");
const allowLegacyRepoWrite = args.includes("--allow-legacy-repo-write");
if (!repoPath || (!entryPath && !entryJson)) {
  console.error("Usage: node new-video-catalog-entry.mjs --repo <path> --entry <path-to-entry.json> --allow-legacy-repo-write");
  console.error("   or: node new-video-catalog-entry.mjs --repo <path> --entry-json '<inline json>' --allow-legacy-repo-write");
  process.exit(1);
}
if (!allowLegacyRepoWrite) {
  console.error("Refusing to modify a product-repository video catalog.");
  console.error("Create or update the catalog in the external AgentHub video workspace instead.");
  console.error("For an explicitly authorized legacy migration write, pass --allow-legacy-repo-write.");
  process.exit(2);
}

const entry = entryJson ? JSON.parse(entryJson) : readJson(entryPath);

function validateEntry(e) {
  const errors = [];
  if (!e.id) errors.push("entry.id is required");
  if (!AUDIENCES.includes(e.audience)) {
    errors.push(`entry.audience must be one of ${AUDIENCES.join(", ")}, got "${e.audience}"`);
  }
  if (!Array.isArray(e.scenes) || e.scenes.length === 0) {
    errors.push("entry.scenes must be a non-empty array");
  }
  if (typeof e.durationSeconds !== "number" || e.durationSeconds <= 0) {
    errors.push("entry.durationSeconds must be a positive number");
  }
  if (Array.isArray(e.scenes)) {
    const sceneSum = e.scenes.reduce((sum, s) => sum + (s.durationSeconds ?? 0), 0);
    if (Math.abs(sceneSum - e.durationSeconds) > 0.01) {
      console.warn(
        `warning: sum of scene durations (${sceneSum}s) does not match entry.durationSeconds ` +
          `(${e.durationSeconds}s) -- double-check before rendering.`,
      );
    }
  }
  return errors;
}

const errors = validateEntry(entry);
if (errors.length > 0) {
  console.error("Entry validation failed:");
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}

const detection = detectVideoConvention(repoPath);

if (detection.convention === "apps-videos-workspace") {
  if (!detection.catalog) {
    console.error(
      `${repoPath} has an apps/videos workspace but no content.ts or catalog.ts under src/. ` +
        "Its video data likely lives elsewhere (e.g. embedded directly in components, as in Lawli's " +
        "apps/videos/src/components/scenes.tsx). This script only knows how to insert into the " +
        "standard content.ts shape -- add the entry by hand, following that repo's own README and types.",
    );
    process.exit(1);
  }
  if (!detection.matchesReferenceShape) {
    console.error(
      `${detection.catalog.path} exists but does not match the supported shape ` +
        '(`export const videos = [...] satisfies ProductVideo[];`). Found `export const ' +
        `${detection.catalog.arrayName} = [...] ${detection.catalog.typeName}[]\` instead. ` +
        "This is a real, working catalog with its own schema (e.g. ABACare's catalog.ts has a " +
        "richer VideoEntry type with capture manifests, chapters, and external-asset requests) -- " +
        "this script deliberately refuses to force-fit the reference shape onto it. Read " +
        `${detection.catalog.path} and ${detection.readme ?? "this workspace's README"} and add the ` +
        "entry by hand in its own idiom.",
    );
    process.exit(1);
  }
  appendToTsCatalog(detection.catalog.path, entry);
  process.exit(0);
}

if (detection.convention === "coledger-production" && detection.videoProgramDir) {
  const jsonCatalogPath = join(detection.videoProgramDir, "_production", "catalog", "video-catalog.json");
  if (existsSync(jsonCatalogPath)) {
    appendToJsonCatalog(jsonCatalogPath, entry);
    process.exit(0);
  }
}

if (detection.videoProgramDir) {
  const mdCatalogPath = join(detection.videoProgramDir, "05_Product_Videos", "catalog.md");
  if (existsSync(mdCatalogPath)) {
    appendToMarkdownCatalog(mdCatalogPath, entry);
    process.exit(0);
  }
}

console.error(
  `No known catalog found under ${repoPath} (detected: ${detection.convention}). Run ` +
    "scaffold-video-workspace.mjs to create an external workspace, or " +
    "run repo-registry.mjs to see what was actually detected.",
);
process.exit(1);

function indent(text, spaces) {
  const pad = " ".repeat(spaces);
  return text
    .split("\n")
    .map((line) => pad + line)
    .join("\n");
}

function appendToTsCatalog(path, e) {
  const content = readFileSync(path, "utf8");
  const arrayDeclRegex = /export const videos = \[([\s\S]*?)\](\s*(?:satisfies|as)\s*ProductVideo\[\];)/;
  const match = content.match(arrayDeclRegex);
  if (!match) {
    console.error(`Could not find "export const videos = [...] satisfies/as ProductVideo[];" in ${path}`);
    process.exit(1);
  }

  const objLiteral = JSON.stringify(e, null, 2);
  const entryText = `\n${indent(`makeVideo(${objLiteral}),`, 2)}\n`;

  const startIdx = match.index;
  const endIdx = startIdx + match[0].length;
  const existingEntries = match[1];
  const closer = match[2];
  const rebuilt = `export const videos = [${existingEntries}${entryText}]${closer}`;
  const newContent = content.slice(0, startIdx) + rebuilt + content.slice(endIdx);
  writeFileSync(path, newContent);
  console.log(`Appended "${e.id}" to ${path} (durationInFrames computed as ${e.durationSeconds * FPS} at ${FPS}fps).`);
}

function appendToJsonCatalog(path, e) {
  const data = readJson(path);
  if (!Array.isArray(data.videos)) {
    console.error(`Expected a "videos" array in ${path}`);
    process.exit(1);
  }
  data.videos.push(e);
  writeFileSync(path, JSON.stringify(data, null, 2) + "\n");
  console.log(`Appended "${e.id}" to ${path}.`);
}

function appendToMarkdownCatalog(path, e) {
  const content = readFileSync(path, "utf8");
  const route = e.route ?? e.primaryRoute ?? "(fill in route)";
  const status = e.status ?? "pending for capture";
  const row = `| ${e.id} | ${e.title} | ${route} | ${status} |\n`;
  writeFileSync(path, content.trimEnd() + "\n" + row);
  console.log(`Appended "${e.id}" as a table row to ${path}. Verify column alignment/formatting by hand.`);
}
