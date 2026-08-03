#!/usr/bin/env node
// Reports which video convention (if any) a repository already uses, so existing work gets
// extended instead of duplicated or force-migrated.
//
// Primary usage -- single repo, no workspace/portfolio concept required:
//   node repo-registry.mjs --repo <path-to-repo> [--json]
//
// Optional multi-repo convenience, only relevant if you're operating across a workspace of
// sibling repos:
//   node repo-registry.mjs --root <workspace-root> [--json]
//   node repo-registry.mjs [--json]   (root defaults to the nearest ancestor with a
//                                       portfolio-wiki/registry/repositories.yaml, or
//                                       falls back to a sibling-directory scan)
import { join, resolve } from "node:path";
import {
  detectVideoConvention,
  findWorkspaceRoot,
  listSiblingGitRepos,
  parseRepositoriesYaml,
} from "./lib.mjs";

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
};
const asJson = args.includes("--json");

const conventionLabel = {
  "apps-videos-workspace": "apps/videos workspace package",
  "coledger-production": "<Product>_Video_Program/_production/remotion (JSON catalog)",
  "gentlenext-production": "_production/remotion (markdown catalog)",
  "video-program-no-remotion-yet": "*_Video_Program folder exists, no Remotion project yet",
  none: "no video infrastructure",
  unknown: "repo not found at the given path",
};

function printResult(r) {
  console.log(`- ${r.slug}: ${conventionLabel[r.convention] ?? r.convention}`);
  if (r.remotionDir) console.log(`    Remotion project: ${r.remotionDir}`);
  if (r.readme) console.log(`    README (read this first): ${r.readme}`);

  if (r.convention === "apps-videos-workspace") {
    if (r.catalog) {
      const shapeNote = r.matchesReferenceShape
        ? "matches the content.ts/videos/ProductVideo reference shape"
        : "DOES NOT match the reference shape -- do not force-fit new-video-catalog-entry.mjs's TS insertion; read this file's own types and README first";
      console.log(`    Catalog: ${r.catalog.path} (array "${r.catalog.arrayName}": ${r.catalog.typeName}[]) -- ${shapeNote}`);
    } else {
      console.log(
        "    Catalog: no content.ts or catalog.ts found under src/ -- video data may live elsewhere " +
          "(e.g. embedded in components) or under a different filename. Read the workspace's own " +
          "README/scripts before assuming there is no catalog.",
      );
    }
    if (r.storyboardsDir) console.log(`    Storyboards: ${r.storyboardsDir}`);
    if (r.scripts.length > 0) console.log(`    Scripts: ${r.scripts.join(", ")}`);
  }
}

// --- Single-repo mode: the default, always-available way to invoke this plugin against any
// repository. Requires nothing but the repo's own path -- no registry, no workspace root. ---
const explicitRepo = flag("--repo");
if (explicitRepo) {
  const repoPath = resolve(explicitRepo);
  const slug = repoPath.split(/[\\/]/).filter(Boolean).pop();
  const result = { slug, path: repoPath, ...detectVideoConvention(repoPath) };

  if (asJson) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    printResult(result);
    console.log(
      "\nPreserve any existing convention as migration input; do not expand it. Use " +
        'scaffold-video-workspace.mjs only when this repo reports "no video infrastructure"; it ' +
        "creates an external workspace and refuses paths inside the product repo.",
    );
  }
  process.exit(0);
}

// --- Optional multi-repo mode: only for workspaces that actually contain several sibling
// product repos. Not required for normal single-repo use. ---
const explicitRoot = flag("--root");
const root = explicitRoot ?? findWorkspaceRoot(process.cwd());

if (!root) {
  console.error(
    "No --repo given, and no workspace root could be determined either (no --root, and no " +
      "portfolio-wiki/registry/repositories.yaml found in any ancestor of the current directory). " +
      "Falling back to a sibling-directory scan of the current directory's parent. If you meant to " +
      "run this against one repository, use --repo <path-to-repo> instead.",
  );
}

const workspaceRoot = root ?? join(process.cwd(), "..");
const registryPath = join(workspaceRoot, "portfolio-wiki", "registry", "repositories.yaml");

let repoSlugs;
let source;
try {
  repoSlugs = parseRepositoriesYaml(registryPath).map((r) => r.slug);
  source = registryPath;
} catch {
  repoSlugs = listSiblingGitRepos(workspaceRoot).filter((name) => name !== "portfolio-wiki");
  source = `sibling-directory scan of ${workspaceRoot}`;
}

const results = repoSlugs.map((slug) => {
  const repoPath = join(workspaceRoot, slug);
  const detection = detectVideoConvention(repoPath);
  return { slug, path: repoPath, ...detection };
});

if (asJson) {
  console.log(JSON.stringify({ workspaceRoot, source, repos: results }, null, 2));
  process.exit(0);
}

console.log(`Workspace root: ${workspaceRoot}`);
console.log(`Repo list source: ${source}\n`);

for (const r of results) printResult(r);

console.log(
  "\nPreserve existing conventions as migration input; do not expand them. Use " +
    'scaffold-video-workspace.mjs only for a repo reporting "none"; it creates an external ' +
    "workspace and refuses paths inside product repos.",
);
