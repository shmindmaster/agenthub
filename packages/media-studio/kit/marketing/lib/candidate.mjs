// Candidate identity is explicit. QA and delivery never select "the latest" encode.
import { existsSync, lstatSync, mkdirSync, readdirSync, realpathSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileSha, readJson } from './util.mjs';

export function candidateId(flags) {
  if (!/^[a-z0-9][a-z0-9-]{0,62}$/.test(flags.candidateId || '')) throw new Error('a safe --candidate-id is required (lowercase letters, digits, hyphens)');
  return flags.candidateId;
}

function canonicalPath(path) {
  let ancestor = resolve(path);
  const tail = [];
  while (!existsSync(ancestor)) {
    const parent = dirname(ancestor);
    if (parent === ancestor) break;
    tail.unshift(basename(ancestor));
    ancestor = parent;
  }
  return join(realpathSync(ancestor), ...tail);
}

export function candidatePaths(ctx, ratio) {
  const id = candidateId(ctx.flags);
  if (!['16x9', '4x5', '9x16'].includes(ratio)) throw new Error('candidate ratio must be 16x9, 4x5 or 9x16');
  if (ctx.flags.candidate) {
    if (!ctx.flags.qaDir || !ctx.flags.composeDir) throw new Error('external candidate needs --qa-dir and --compose-dir; source evidence stays read-only');
    const rel = relative(canonicalPath(ctx.jobDir), canonicalPath(ctx.flags.qaDir));
    if (rel === '' || (!isAbsolute(rel) && rel !== '..' && !rel.startsWith('../') && !rel.startsWith('..\\'))) throw new Error('--qa-dir must be outside the source evidence job');
  }
  const dir = ctx.flags.composeDir ? resolve(ctx.flags.composeDir) : join(ctx.jobDir, 'compose', 'candidates', id, ratio);
  const qa = ctx.flags.qaDir ? join(resolve(ctx.flags.qaDir), ratio) : join(ctx.jobDir, 'qa', id, ratio);
  if (ctx.flags.candidate) {
    // The actual write tree includes the ratio and ws descendants, not just qaDir.
    // Never follow an existing link while creating or refreshing external evidence.
    const pending = [qa];
    while (pending.length) {
      const path = pending.pop();
      const entry = lstatSync(path, { throwIfNoEntry: false });
      if (!entry) continue;
      if (entry.isSymbolicLink()) throw new Error('external QA write tree must not contain symlinks or reparse points');
      if (entry.isDirectory()) pending.push(...readdirSync(path).map(name => join(path, name)));
    }
  }
  return { id, dir, qa, ad: ctx.flags.candidate ? resolve(ctx.flags.candidate) : join(dir, 'ad.mp4') };
}

export function reserveCandidate(ctx) {
  const id = candidateId(ctx.flags);
  if (ctx.flags.candidate || ctx.flags.composeDir || ctx.flags.qaDir) throw new Error('compose cannot use QA-only candidate overrides');
  const dir = join(ctx.jobDir, 'compose', 'candidates', id);
  mkdirSync(join(ctx.jobDir, 'compose', 'candidates'), { recursive: true });
  // Exclusive directory creation: --force must never overwrite a reviewed candidate.
  mkdirSync(dir);
  return dir;
}

export function selectedCuts(ctx, cuts) {
  if (!ctx.flags.ratio) {
    if (ctx.flags.candidate) throw new Error('an external --candidate requires --ratio');
    return cuts;
  }
  const selected = cuts.filter((c) => c.ratios.includes(ctx.flags.ratio)).map((c) => ({ ...c, ratios: [ctx.flags.ratio] }));
  if (!selected.length) throw new Error(`ratio ${ctx.flags.ratio} is not in the spec`);
  return selected;
}

export function verifiedCandidate(ctx, ratio) {
  const paths = candidatePaths(ctx, ratio);
  const receipt = !ctx.flags.candidate && existsSync(join(paths.dir, 'candidate.json')) ? readJson(join(paths.dir, 'candidate.json')) : null;
  const expected = ctx.flags.candidate ? ctx.flags.candidateSha256 : receipt?.sha256;
  if (!/^[a-f0-9]{64}$/.test(expected || '')) throw new Error('candidate needs its compose receipt or an explicit --candidate-sha256');
  if (receipt && receipt.id !== paths.id) throw new Error('candidate receipt id does not match --candidate-id');
  if (receipt && (receipt.ratio !== ratio || !/^[a-f0-9]{64}$/.test(ctx.specSha || '') || !/^[a-f0-9]{64}$/.test(ctx.brandSha || '') || receipt.specSha256 !== ctx.specSha || receipt.brandSha256 !== ctx.brandSha)) throw new Error('candidate receipt has stale or missing ratio/spec/brand input bindings; compose a new candidate ID');
  if (!existsSync(paths.ad) || fileSha(paths.ad) !== expected) throw new Error('candidate SHA-256 does not match the named candidate');
  return { ...paths, sha256: expected, bytes: statSync(paths.ad).size };
}
