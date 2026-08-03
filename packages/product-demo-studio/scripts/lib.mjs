import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

export const FPS = 30;
export const AUDIENCES = ["Hero", "Pillar", "Persona", "Training", "Trust", "Marketing", "Sales"];

function isDir(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function isGitRepo(path) {
  return isDir(join(path, ".git"));
}

/**
 * Walk upward from `startDir` looking for a directory that has a
 * `portfolio-wiki/registry/repositories.yaml` child — that ancestor is the
 * workspace root (e.g. C:\Repos\shmindmaster). Returns null if none found.
 */
export function findWorkspaceRoot(startDir) {
  let dir = resolve(startDir);
  for (;;) {
    const candidate = join(dir, "portfolio-wiki", "registry", "repositories.yaml");
    if (existsSync(candidate)) return dir;
    const parent = resolve(dir, "..");
    if (parent === dir) return null;
    dir = parent;
  }
}

/**
 * Hand-rolled parser for the simple `repositories.yaml` shape used by
 * portfolio-wiki:
 *
 *   repositories:
 *     - slug: lawli
 *       github: shmindmaster/lawli
 *       branch: main
 *
 * Avoids taking a YAML library dependency for a format this constrained.
 */
export function parseRepositoriesYaml(yamlPath) {
  const text = readFileSync(yamlPath, "utf8");
  const entries = [];
  let current = null;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, "");
    const itemMatch = line.match(/^\s*-\s*slug:\s*(\S+)\s*$/);
    if (itemMatch) {
      current = { slug: itemMatch[1] };
      entries.push(current);
      continue;
    }
    const fieldMatch = line.match(/^\s+(\w+):\s*(\S+)\s*$/);
    if (fieldMatch && current) {
      current[fieldMatch[1]] = fieldMatch[2];
    }
  }
  return entries;
}

/**
 * List sibling directories of `workspaceRoot` that look like git repos.
 */
export function listSiblingGitRepos(workspaceRoot) {
  return readdirSync(workspaceRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .filter((name) => isGitRepo(join(workspaceRoot, name)));
}

/**
 * Look for a top-level catalog array in a workspace's src/content.ts or
 * src/catalog.ts -- the two filenames actually observed across this
 * portfolio's video workspaces (SubOps uses content.ts; ABACare uses
 * catalog.ts with a materially different, richer schema). Scans line-by-line
 * for the LAST `] as [const] satisfies <Type>[];`-shaped closing line (the
 * main catalog is conventionally defined last, after any smaller typed
 * arrays), then walks backward for the nearest `export const <name> = [`.
 *
 * This deliberately does not try to parse or normalize the array contents --
 * every workspace inspected so far (SubOps, ABACare, CoLedger, GentleNext,
 * Lawli) uses a different shape. The goal is to report what's really there
 * so a human/agent can decide, not to force one schema onto all of them.
 */
function findCatalogFile(srcDir) {
  const candidates = ["content.ts", "catalog.ts"];
  for (const name of candidates) {
    const path = join(srcDir, name);
    if (!existsSync(path)) continue;

    const lines = readFileSync(path, "utf8").split(/\r?\n/);
    let typeName = null;
    let arrayName = null;
    let closingLineIndex = -1;
    for (let i = 0; i < lines.length; i++) {
      // Matches both the multi-line case (closing "]" alone on its own line,
      // e.g. real SubOps/ABACare catalogs with entries) and the single-line
      // empty-array case a fresh scaffold starts with
      // (`export const videos = [] as ProductVideo[];`).
      const m = lines[i].match(/\]\s*(?:as const\s*)?(?:satisfies|as)\s+(\w+)\[\]\s*;?\s*$/);
      if (m) {
        typeName = m[1];
        closingLineIndex = i;
        const sameLineOpen = lines[i].match(/export const (\w+)\s*=\s*\[/);
        arrayName = sameLineOpen ? sameLineOpen[1] : null;
      }
    }

    if (!arrayName && closingLineIndex !== -1) {
      for (let i = closingLineIndex - 1; i >= 0; i--) {
        const m = lines[i].match(/^export const (\w+)\s*=\s*\[/);
        if (m) {
          arrayName = m[1];
          break;
        }
      }
    }

    return { file: name, path, arrayName, typeName };
  }
  return null;
}

/**
 * Detect which (if any) of the known video conventions a repo already uses,
 * and return the path to its Remotion project directory plus what's actually
 * inside it (catalog file/shape, storyboards, notable scripts). Never
 * assumes a workspace matches the SubOps reference shape just because
 * `apps/videos/` exists -- ABACare and Lawli both have real, working
 * `apps/videos/` workspaces with completely different internals.
 */
export function detectVideoConvention(repoPath) {
  const subopsStyle = join(repoPath, "apps", "videos", "package.json");
  if (existsSync(subopsStyle)) {
    const remotionDir = join(repoPath, "apps", "videos");
    const srcDir = join(remotionDir, "src");
    const catalog = existsSync(srcDir) ? findCatalogFile(srcDir) : null;
    const storyboardsDir = join(remotionDir, "storyboards");
    const readmePath = join(remotionDir, "README.md");
    let scripts = [];
    try {
      scripts = readdirSync(join(remotionDir, "scripts")).filter((f) => f.endsWith(".ts"));
    } catch {
      // no scripts/ dir -- fine, not every workspace has one
    }

    return {
      convention: "apps-videos-workspace",
      remotionDir,
      catalog,
      matchesReferenceShape: catalog?.arrayName === "videos" && catalog?.typeName === "ProductVideo",
      storyboardsDir: existsSync(storyboardsDir) ? storyboardsDir : null,
      readme: existsSync(readmePath) ? readmePath : null,
      scripts,
    };
  }

  const gentlenextStyle = join(repoPath, "_production", "remotion", "package.json");
  if (existsSync(gentlenextStyle)) {
    return { convention: "gentlenext-production", remotionDir: join(repoPath, "_production", "remotion") };
  }

  let topLevel = [];
  try {
    topLevel = readdirSync(repoPath, { withFileTypes: true });
  } catch {
    return { convention: "unknown", remotionDir: null };
  }

  const videoProgramDir = topLevel.find(
    (entry) => entry.isDirectory() && /_Video_Program$/i.test(entry.name),
  );
  if (videoProgramDir) {
    const coledgerStyle = join(repoPath, videoProgramDir.name, "_production", "remotion", "package.json");
    if (existsSync(coledgerStyle)) {
      return {
        convention: "coledger-production",
        remotionDir: join(repoPath, videoProgramDir.name, "_production", "remotion"),
        videoProgramDir: join(repoPath, videoProgramDir.name),
      };
    }
    return {
      convention: "video-program-no-remotion-yet",
      remotionDir: null,
      videoProgramDir: join(repoPath, videoProgramDir.name),
    };
  }

  return { convention: "none", remotionDir: null };
}

export function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

/**
 * Detect which package manager a directory actually uses from its lockfile, rather than
 * assuming one. Falls back to npm (the `run` syntax every package manager accepts) if no
 * lockfile is present.
 */
export function detectPackageManager(dir) {
  if (existsSync(join(dir, "pnpm-lock.yaml"))) return "pnpm";
  if (existsSync(join(dir, "yarn.lock"))) return "yarn";
  if (existsSync(join(dir, "bun.lockb")) || existsSync(join(dir, "bun.lock"))) return "bun";
  if (existsSync(join(dir, "package-lock.json"))) return "npm";
  return "npm";
}

/**
 * Hand-rolled parser for the one YAML shape this plugin's manifests use: a single top-level
 * `key:` followed by a list of flat objects (`- field: value` / `  field: value`). Not a general
 * YAML parser -- deliberately avoids taking a YAML library dependency for a format this
 * constrained. Supports quoted string values, and coerces `true`/`false`/`null`/bare numbers.
 *
 *   segments:
 *     - id: opening
 *       text: "Approvals used to take a full day."
 *       verified: true
 */
export function parseYamlObjectList(text) {
  const lines = text.split(/\r?\n/);
  let topKey = null;
  const items = [];
  let current = null;

  const coerce = (raw) => {
    const v = raw.trim();
    if (v === "") return "";
    if (v === "true") return true;
    if (v === "false") return false;
    if (v === "null" || v === "~") return null;
    if (/^-?\d+(\.\d+)?$/.test(v)) return Number(v);
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      return v.slice(1, -1);
    }
    return v;
  };

  for (const rawLine of lines) {
    if (/^\s*#/.test(rawLine) || rawLine.trim() === "") continue;

    if (!topKey) {
      const topMatch = rawLine.match(/^(\w+):\s*$/);
      if (topMatch) {
        topKey = topMatch[1];
      }
      continue;
    }

    const listItemMatch = rawLine.match(/^\s*-\s*(\w+):\s?(.*)$/);
    if (listItemMatch) {
      current = {};
      items.push(current);
      current[listItemMatch[1]] = coerce(listItemMatch[2]);
      continue;
    }

    const fieldMatch = rawLine.match(/^\s+(\w+):\s?(.*)$/);
    if (fieldMatch && current) {
      current[fieldMatch[1]] = coerce(fieldMatch[2]);
    }
  }

  return { topKey, items };
}

/**
 * Read a manifest that may be JSON or this plugin's simple YAML-object-list shape, returning the
 * parsed item array regardless of which one it is.
 */
export function readManifestList(path, expectedTopKey) {
  const text = readFileSync(path, "utf8");
  const trimmed = text.trimStart();
  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    const parsed = JSON.parse(text);
    return Array.isArray(parsed) ? parsed : parsed[expectedTopKey];
  }
  const { topKey, items } = parseYamlObjectList(text);
  if (expectedTopKey && topKey !== expectedTopKey) {
    throw new Error(
      `Expected top-level key "${expectedTopKey}" in ${path}, found "${topKey ?? "(none)"}".`,
    );
  }
  return items;
}
