#!/usr/bin/env node
// Copy render-program.mjs and every module it loads (static and dynamic) into one folder for a remote render host.
// The layout matches the package (scripts/, kit/marketing/lib/, kit/screencast/), so picture-gates.mjs finds its
// caption chunker and sync-lib.mjs with no manual copying.
// Usage: node pack-render-bundle.mjs <outDir>
import { copyFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
// picture-gates.mjs loads these two with a runtime path search, so the walker cannot see them.
export const RUNTIME_SEEDS = ['scripts/render-program.mjs', 'kit/marketing/lib/captions.mjs', 'kit/screencast/sync-lib.mjs'];

export function closure(root = packageRoot, seeds = RUNTIME_SEEDS) {
  const found = new Set();
  const visit = (file) => {
    const rel = relative(root, file).split('\\').join('/');
    if (found.has(rel)) return;
    if (!existsSync(file)) throw new Error(`render bundle: missing module ${rel}`);
    found.add(rel);
    const src = readFileSync(file, 'utf8');
    for (const match of src.matchAll(/(?:import|export)\s[^'"]*?from\s*['"](\.{1,2}\/[^'"]+)['"]|import\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g)) {
      visit(resolve(dirname(file), match[1] ?? match[2]));
    }
  };
  for (const seed of seeds) visit(join(root, seed));
  return [...found].sort();
}

const invoked = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  const out = process.argv[2];
  if (!out) { console.error('Usage: node pack-render-bundle.mjs <outDir>'); process.exit(1); }
  const files = closure();
  for (const rel of files) {
    const target = join(resolve(out), rel);
    mkdirSync(dirname(target), { recursive: true });
    copyFileSync(join(packageRoot, rel), target);
  }
  console.log(JSON.stringify({ ok: true, out: resolve(out), files }));
}
