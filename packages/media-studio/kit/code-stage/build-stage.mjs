// Build a code-walkthrough stage for a media-studio job: validate the shot list, read every named file from git
// objects at a resolved commit (read-only), write the hash receipt, and emit a scenes module that record-job.mjs runs.
//
// Usage: node build-stage.mjs <jobRoot> [--shots story/code-shots.json] [--words story/code-words.json] [--monaco <dir>] [--fps 15]
// Writes <jobRoot>/capture/code-stage/stage.json     editor/diagram data (file text at the commit, explorer listing)
//        <jobRoot>/capture/code-stage/receipt.json   commit, file sha256 + blob, sha256 per shown line and per highlight
//        <jobRoot>/capture/code-stage/scenes.mjs     { scenes, recast, order } for capture/scenes.mjs to spread in
// Monaco resolves from --monaco, CODE_STAGE_MONACO_DIR, or <kit>/node_modules/monaco-editor/min; otherwise the page
// loads the pinned CDN build (cdnjs monaco-editor 0.52.2). The product repository is never written.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseShotList, filesToRead } from './shotlist.mjs';
import { resolveCommit, readAtCommit, explorerTree, buildCodeReceipt, verifyCodeReceipt } from './source.mjs';

export const MONACO_VERSION = '0.52.2';
export const MONACO_CDN = `https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/${MONACO_VERSION}/min/vs`;
const here = path.dirname(fileURLToPath(import.meta.url));

export function resolveMonaco(explicit) {
  const candidates = [explicit, process.env.CODE_STAGE_MONACO_DIR, path.join(here, '..', 'node_modules', 'monaco-editor', 'min')].filter(Boolean);
  for (const c of candidates) {
    const dir = fs.existsSync(path.join(c, 'vs', 'loader.js')) ? c : fs.existsSync(path.join(c, 'min', 'vs', 'loader.js')) ? path.join(c, 'min') : null;
    if (dir) {
      let version = null;
      try { version = JSON.parse(fs.readFileSync(path.join(dir, '..', 'package.json'), 'utf8')).version; } catch { /* unknown */ }
      return { monacoDir: path.resolve(dir), monacoBase: '/monaco/vs', monacoVersion: version, monacoSource: 'local' };
    }
  }
  return { monacoDir: null, monacoBase: MONACO_CDN, monacoVersion: MONACO_VERSION, monacoSource: 'cdn' };
}

/** Pure-ish core so tests can drive it without a CLI. Returns { stage, receipt }. */
export function buildStage(shotDoc, { words = {}, monaco = {}, fps = null } = {}) {
  const parsed = parseShotList(shotDoc, { words });
  const commits = new Map();
  const commitOf = (ref) => { if (!commits.has(ref)) commits.set(ref, resolveCommit(parsed.repo, ref)); return commits.get(ref); };
  const sources = new Map();
  const files = {};
  for (const f of filesToRead(parsed)) {
    const commit = commitOf(f.ref);
    const src = readAtCommit(parsed.repo, commit, f.file);
    sources.set(`${f.ref}\u0000${f.file}`, { ...src, commit });
    if (files[f.file] && files[f.file].commit !== commit) throw new Error(`${f.file} is shown at two different commits; one stage shows one version of a file`);
    files[f.file] = { text: src.text, commit, sha256: src.sha256 };
  }
  const receipt = buildCodeReceipt(parsed, sources, { repo: parsed.repo });
  const check = parsed.repo ? verifyCodeReceipt(receipt, parsed.repo) : { ok: true, problems: [] };
  if (!check.ok) throw new Error('receipt does not verify against the repository:\n  ' + check.problems.join('\n  '));
  const firstCommit = commits.size ? [...commits.values()][0] : null;
  const tree = parsed.repo && firstCommit ? explorerTree(parsed.repo, firstCommit, Object.keys(files)) : { root: 'diagram', expanded: [], listing: {} };
  const byId = Object.fromEntries(receipt.shots.map((s) => [s.id, s]));
  const stage = {
    schemaVersion: parsed.schemaVersion,
    viewport: parsed.viewport,
    fps,
    ...monaco,
    refLabel: firstCommit ? `${parsed.ref} · ${firstCommit.slice(0, 7)}` : parsed.ref,
    tree,
    files,
    shots: parsed.shots.map((s) => s.kind === 'code'
      ? { ...s, rangeSha256: byId[s.id].rangeSha256, crossRefs: s.crossRefs.map((x, i) => ({ ...x, rangeSha256: byId[s.id].crossRefs[i].rangeSha256 })) }
      : s),
  };
  receipt.monaco = { source: monaco.monacoSource || null, version: monaco.monacoVersion || null };
  return { stage, receipt, parsed };
}

async function main() {
  const argv = process.argv.slice(2);
  const opt = (name, dflt) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : dflt; };
  const jobRoot = argv.find((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
  if (!jobRoot) { console.error('usage: node build-stage.mjs <jobRoot> [--shots story/code-shots.json] [--words story/code-words.json] [--monaco <dir>] [--fps 15]'); process.exit(2); }
  const root = path.resolve(jobRoot);
  const job = JSON.parse(fs.readFileSync(path.join(root, 'job.json'), 'utf8').replace(/^﻿/, ''));
  if (job.repositoryWritePolicy !== 'read-only') throw new Error('job.json must record repositoryWritePolicy: read-only');
  const shotsPath = path.resolve(root, opt('--shots', 'story/code-shots.json'));
  const wordsPath = path.resolve(root, opt('--words', 'story/code-words.json'));
  const words = fs.existsSync(wordsPath) ? JSON.parse(fs.readFileSync(wordsPath, 'utf8')) : {};
  const fps = opt('--fps', null) ? Number(opt('--fps')) : null;
  const shotDoc = JSON.parse(fs.readFileSync(shotsPath, 'utf8').replace(/^﻿/, ''));
  if (shotDoc.repo && root.startsWith(path.resolve(shotDoc.repo) + path.sep)) throw new Error('the job workspace must live outside the product repository');
  const { stage, receipt } = buildStage(shotDoc, { words, monaco: resolveMonaco(opt('--monaco', null)), fps });
  const out = path.join(root, 'capture', 'code-stage');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'stage.json'), JSON.stringify(stage, null, 2));
  receipt.shotList = path.relative(root, shotsPath).replace(/\\/g, '/');
  fs.writeFileSync(path.join(out, 'receipt.json'), JSON.stringify(receipt, null, 2));
  const driverUrl = pathToFileURL(path.join(here, 'driver.mjs')).href;
  fs.writeFileSync(path.join(out, 'scenes.mjs'),
    `// Generated by kit/code-stage/build-stage.mjs. Spread into capture/scenes.mjs: scenes, recast options, order.\n` +
    `import { stageScenes } from ${JSON.stringify(driverUrl)};\n` +
    `import { fileURLToPath } from 'node:url';\n` +
    `export const { scenes, recast, order } = stageScenes(fileURLToPath(new URL('.', import.meta.url)));\n`);
  for (const s of stage.shots) {
    const what = s.kind === 'code' ? `${s.file}:${s.lines.join('-')} hl ${s.highlight.map((h) => h.join('-')).join(',') || '-'}${s.crossRefs.length ? ' + ' + s.crossRefs.map((x) => x.file + ':' + x.lines.join('-')).join(', ') : ''}` : `diagram ${s.nodes.map((n) => n.id).join(' > ')}${s.lit ? ' lit ' + s.lit : ''}`;
    console.log(`${s.id} ${s.durationSeconds}s ${what}`);
    console.log('   events ' + s.events.map((e) => `${e.event}@${e.t}`).join(' '));
  }
  console.log(`monaco ${stage.monacoSource} ${stage.monacoVersion || ''}; receipt ${receipt.files.length} file(s) at ${[...new Set(receipt.files.map((f) => f.commit.slice(0, 8)))].join(',')}`);
  console.log('wrote ' + out);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}
