#!/usr/bin/env node
// Copy the execution-controls kit into a product repository, or check that a
// vendored copy is byte-identical to this kit.
//
// Products deploy on their own (Railway, DigitalOcean, Vercel), so they cannot
// import from AgentHub at runtime. They vendor one language's files plus a
// manifest of hashes; `--check` in the product's tests fails when anyone edits
// the vendored copy instead of the kit.
//
// Usage:
//   node vendor-execution-controls.mjs --lang python --dest <dir>
//   node vendor-execution-controls.mjs --lang ts --dest <dir> [--import-ext ts|js]
//   node vendor-execution-controls.mjs --check --dest <dir>
//
// Exit 0 on success, 1 when --check finds drift, 2 on usage errors.

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const kitRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'kits', 'execution-controls');
const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const check = args.includes('--check');
const dest = flag('--dest');
if (!dest) {
  console.error('Usage: vendor-execution-controls.mjs (--lang python|ts | --check) --dest <dir> [--import-ext ts|js]');
  process.exit(2);
}
const destRoot = resolve(dest);
const MANIFEST = 'KIT_MANIFEST.json';

const sha256 = (text) => createHash('sha256').update(text.replace(/\r\n/g, '\n'), 'utf8').digest('hex');
const kitVersion = () => /KIT_VERSION = "([^"]+)"/.exec(readFileSync(join(kitRoot, 'ts', 'index.ts'), 'utf8'))[1];

function sources(lang) {
  if (lang === 'python') {
    const dir = join(kitRoot, 'python', 'execution_controls');
    return readdirSync(dir).filter((name) => name.endsWith('.py')).map((name) => ({ from: join(dir, name), to: name }));
  }
  if (lang === 'ts') {
    const dir = join(kitRoot, 'ts');
    return readdirSync(dir)
      .filter((name) => name.endsWith('.ts') && name !== 'vectors.ts')
      .map((name) => ({ from: join(dir, name), to: name }));
  }
  console.error(`--lang must be python or ts, got ${lang}`);
  process.exit(2);
}

/** Every file under `root` as a forward-slash relative name. Generated `__pycache__` folders are not part of a vendored copy. */
function listFiles(root, directory = root) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return entry.name === '__pycache__' ? [] : listFiles(root, path);
    return [relative(root, path).split(sep).join('/')];
  });
}

function transform(text, lang, importExt) {
  const header = lang === 'python'
    ? '# Vendored from agenthub packages/product-experience-engineering/kits/execution-controls. Do not edit; re-vendor.\n'
    : '// Vendored from agenthub packages/product-experience-engineering/kits/execution-controls. Do not edit; re-vendor.\n';
  let body = text.replace(/\r\n/g, '\n');
  if (lang === 'ts' && importExt === 'js') body = body.replace(/(from\s+"\.\/[\w-]+)\.ts"/g, '$1.js"');
  return header + body;
}

if (check) {
  const manifestPath = join(destRoot, MANIFEST);
  if (!existsSync(manifestPath)) {
    console.error(`FAIL: ${manifestPath} not found`);
    process.exit(1);
  }
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const drift = [];
  for (const [name, expected] of Object.entries(manifest.files)) {
    const path = join(destRoot, name);
    if (!existsSync(path)) drift.push(`${name}: missing`);
    else if (sha256(readFileSync(path, 'utf8')) !== expected) drift.push(`${name}: edited after vendoring`);
  }
  const kitFiles = sources(manifest.lang);
  for (const { from, to } of kitFiles) {
    if (!(to in manifest.files)) drift.push(`${to}: in the kit, not vendored`);
    else if (sha256(transform(readFileSync(from, 'utf8'), manifest.lang, manifest.importExt)) !== manifest.files[to]) {
      drift.push(`${to}: kit changed since vendoring (vendored ${manifest.kitVersion}, kit ${kitVersion()})`);
    }
  }
  const shipped = new Set(kitFiles.map(({ to }) => to));
  for (const name of Object.keys(manifest.files)) {
    if (!shipped.has(name)) drift.push(`${name}: in the manifest, not shipped by the kit`);
  }
  for (const name of listFiles(destRoot)) {
    if (name !== MANIFEST && !(name in manifest.files)) drift.push(`${name}: not in the manifest`);
  }
  if (drift.length) {
    console.error(`FAIL execution-controls vendored copy at ${destRoot}:\n${drift.map((d) => `  - ${d}`).join('\n')}`);
    process.exit(1);
  }
  console.log(`PASS execution-controls ${manifest.kitVersion} (${manifest.lang}) at ${destRoot}`);
  process.exit(0);
}

const lang = flag('--lang');
const importExt = flag('--import-ext') ?? 'ts';
const files = {};
mkdirSync(destRoot, { recursive: true });
for (const { from, to } of sources(lang)) {
  const text = transform(readFileSync(from, 'utf8'), lang, importExt);
  writeFileSync(join(destRoot, to), text, { encoding: 'utf8' });
  files[to] = sha256(text);
}
const manifest = {
  kit: 'execution-controls',
  kitVersion: kitVersion(),
  lang,
  importExt: lang === 'ts' ? importExt : undefined,
  source: 'agenthub/packages/product-experience-engineering/kits/execution-controls',
  specs: ['spec/approval-capsule.md', 'spec/receipt.md'],
  files,
};
writeFileSync(join(destRoot, MANIFEST), `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
console.log(`Vendored execution-controls ${manifest.kitVersion} (${lang}) into ${relative(process.cwd(), destRoot) || destRoot}`);
