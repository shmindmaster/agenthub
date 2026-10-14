// Read-only source access for the code-walkthrough stage, and the receipt that proves the film shows the real code.
// Every file is read from git objects at a resolved commit (`git show <commit>:<path>`), never from the working tree,
// so uncommitted edits cannot leak into a film and the receipt can be re-verified later from the same repository.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import path from 'node:path';

export const RECEIPT_GENERATOR = 'media-studio/code-stage';
const git = (repo, args, opts = {}) => execFileSync('git', ['-C', repo, ...args], { maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'], ...opts });
export const sha256 = (data) => createHash('sha256').update(data).digest('hex');

/** Full commit sha for a ref (branch, tag, sha). Throws when the ref does not resolve. */
export function resolveCommit(repo, ref) {
  return git(repo, ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`]).toString().trim();
}

/** File text at a commit, plus its git blob id and sha256 of the exact bytes. */
export function readAtCommit(repo, commit, file) {
  const buf = git(repo, ['show', `${commit}:${file}`]);
  const blob = git(repo, ['rev-parse', `${commit}:${file}`]).toString().trim();
  return { text: buf.toString('utf8'), bytes: buf.length, sha256: sha256(buf), blob };
}

/** Split into lines the way an editor numbers them (CRLF or LF; a trailing newline does not add a line). */
export function splitLines(text) {
  const lines = text.split(/\r?\n/);
  if (lines.length > 1 && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

/** sha256 of each line's text (no line ending) for lines a..b inclusive, and of the whole range joined by \n. */
export function lineHashes(lines, [a, b]) {
  if (a < 1 || b > lines.length || a > b) throw new Error(`lines ${a}-${b} are outside the file (1-${lines.length})`);
  const rows = [];
  for (let n = a; n <= b; n++) rows.push({ n, sha256: sha256(lines[n - 1]) });
  return { lines: [a, b], rangeSha256: sha256(lines.slice(a - 1, b).join('\n')), rows };
}

/** Directory listing at a commit: [{ name, type: 'dir'|'file' }] sorted like the VS Code explorer (folders first). */
export function listDir(repo, commit, dir) {
  const spec = dir ? `${commit}:${dir}` : `${commit}:`;
  const out = git(repo, ['ls-tree', spec]).toString();
  return out.split(/\r?\n/).filter(Boolean).map((l) => {
    const [meta, name] = l.split('\t');
    const type = meta.split(' ')[1] === 'tree' ? 'dir' : 'file';
    return { name, type };
  }).sort((x, y) => (x.type === y.type ? x.name.localeCompare(y.name, 'en', { sensitivity: 'base' }) : x.type === 'dir' ? -1 : 1));
}

/** Explorer tree for the files a shot list touches: every directory on each path, listed at the commit. */
export function explorerTree(repo, commit, files) {
  const dirs = new Set(['']);
  for (const f of files) { const parts = f.split('/'); for (let i = 1; i < parts.length; i++) dirs.add(parts.slice(0, i).join('/')); }
  const listing = {};
  for (const d of dirs) listing[d] = listDir(repo, commit, d);
  return { root: path.basename(path.resolve(repo)), expanded: [...dirs].filter(Boolean), listing };
}

/**
 * Receipt for a parsed shot list. `sources` maps `${ref}\0${file}` -> { commit, text, sha256, blob, bytes }.
 * Binds every shot to the commit, the file's sha256 and blob id, and a sha256 per shown line and per highlight band.
 */
export function buildCodeReceipt(parsed, sources, { repo } = {}) {
  const files = {};
  const span = (ref, file, lines, highlight, startLine = null) => {
    const src = sources.get(`${ref}\u0000${file}`);
    if (!src) throw new Error(`no source read for ${ref}:${file}`);
    const all = splitLines(src.text);
    files[`${src.commit}:${file}`] = { path: file, ref, commit: src.commit, blob: src.blob, sha256: src.sha256, bytes: src.bytes, lineCount: all.length };
    const shown = lineHashes(all, lines);
    // Lines in view before the reveal scroll (startLine) are on screen too, so they are hashed as well.
    const context = startLine && startLine < lines[0] ? lineHashes(all, [startLine, lines[0] - 1]) : null;
    return {
      file, ref, commit: src.commit, fileSha256: src.sha256, blob: src.blob,
      lines: shown.lines, rangeSha256: shown.rangeSha256, lineHashes: shown.rows,
      highlight: highlight.map((h) => ({ lines: h, sha256: lineHashes(all, h).rangeSha256 })),
      ...(context ? { contextLines: context.lines, contextSha256: context.rangeSha256, contextLineHashes: context.rows } : {}),
    };
  };
  const shots = parsed.shots.map((s) => {
    if (s.kind !== 'code') return { id: s.id, kind: s.kind, nodes: s.nodes.map((n) => n.id), lit: s.lit, events: s.events, durationSeconds: s.durationSeconds };
    return {
      id: s.id, kind: 'code', ...span(s.ref, s.file, s.lines, s.highlight, s.startLine),
      callout: s.callout, zoom: s.zoom, events: s.events, durationSeconds: s.durationSeconds,
      crossRefs: s.crossRefs.map((x) => ({ ...span(x.ref, x.file, x.lines, x.highlight), callout: x.callout, label: x.label })),
    };
  });
  return {
    schemaVersion: '1.0.0',
    generator: RECEIPT_GENERATOR,
    createdAt: new Date().toISOString(),
    repo: repo ? path.resolve(repo) : parsed.repo,
    ref: parsed.ref,
    files: Object.values(files),
    shots,
  };
}

/** Re-read every file named in a receipt from the repository and compare all hashes. Returns { ok, problems[] }. */
export function verifyCodeReceipt(receipt, repo = receipt.repo) {
  const problems = [];
  const cache = new Map();
  const load = (commit, file) => {
    const k = `${commit}:${file}`;
    if (!cache.has(k)) { try { cache.set(k, readAtCommit(repo, commit, file)); } catch (e) { cache.set(k, { error: String(e.message).split('\n')[0] }); } }
    return cache.get(k);
  };
  for (const f of receipt.files || []) {
    const src = load(f.commit, f.path);
    if (src.error) { problems.push(`${f.path}@${f.commit.slice(0, 8)}: ${src.error}`); continue; }
    if (src.sha256 !== f.sha256) problems.push(`${f.path}@${f.commit.slice(0, 8)}: file sha256 differs`);
    if (src.blob !== f.blob) problems.push(`${f.path}@${f.commit.slice(0, 8)}: blob differs`);
  }
  const checkSpan = (where, sp) => {
    const src = load(sp.commit, sp.file);
    if (src.error) return;
    const all = splitLines(src.text);
    let got;
    try { got = lineHashes(all, sp.lines); } catch (e) { problems.push(`${where}: ${e.message}`); return; }
    if (got.rangeSha256 !== sp.rangeSha256) problems.push(`${where}: range ${sp.lines.join('-')} sha256 differs`);
    for (const r of sp.lineHashes || []) { const g = got.rows.find((x) => x.n === r.n); if (!g || g.sha256 !== r.sha256) problems.push(`${where}: line ${r.n} differs`); }
    if (sp.contextLines) {
      try { const c = lineHashes(all, sp.contextLines); if (c.rangeSha256 !== sp.contextSha256) problems.push(`${where}: context ${sp.contextLines.join('-')} differs`); } catch (e) { problems.push(`${where}: ${e.message}`); }
    }
    for (const h of sp.highlight || []) { if (lineHashes(all, h.lines).rangeSha256 !== h.sha256) problems.push(`${where}: highlight ${h.lines.join('-')} differs`); }
  };
  for (const s of receipt.shots || []) {
    if (s.kind !== 'code') continue;
    checkSpan(s.id, s);
    (s.crossRefs || []).forEach((x, i) => checkSpan(`${s.id}.crossRef[${i}]`, x));
  }
  return { ok: problems.length === 0, problems };
}
