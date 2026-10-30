// Film-chain gates (media-studio 2.0.0) run on the exact encoded ad: picture integrity, pointer path, frame integrity and the
// marketing readiness floor. The scripts are the shared tools (deployed beside the kit's screencast tools, or scripts/ in a checkout);
// this module only prepares what they read, runs them and turns the exit code and the report into a gate result.
// mvg never writes the reviewer's marketing-readiness file: it only copies a file that names this exact candidate.
import { copyFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { gateScript } from './gate-runners.mjs';
import { run } from './mix.mjs';
import { readJson } from './util.mjs';

export const CHAIN_GATES = Object.freeze(['integrity', 'pointer', 'frameIntegrity', 'marketing']);

const tailLine = (r) => String(r?.stderr || r?.stdout || '').trim().split(/\r?\n/).filter(Boolean).slice(-1).join(' ').slice(0, 300);
const parseJson = (text) => { try { return JSON.parse(text); } catch { return null; } };
const readReport = (path) => { try { return existsSync(path) ? readJson(path) : null; } catch { return null; } };

/**
 * The capture viewport each portrait or square ratio must be recorded at: its own delivery frame (mvg records 4x5 and 9x16
 * natively, `mobileLayout`). Landscape is unconstrained by the gate, so 16x9 has no entry. Keys are the gate's `W:H` form.
 */
export function captureViewportsFor(ratio, frame) {
  if (!(frame.height >= frame.width)) return {};
  return { [ratio.replace('x', ':')]: { width: frame.width, height: frame.height } };
}

/**
 * The reviewer's marketing-readiness file for one ratio. It counts only for the candidate it names (candidate.sha256, the
 * contract of validate-marketing-readiness, or candidateSha256, the reviews.json convention); anything else is absent or stale.
 * @returns {{state:'bound'|'absent'|'stale'|'unreadable', readiness:object|null, boundTo:string|null}}
 */
export function readMarketingReadiness(path, candidateSha) {
  if (!existsSync(path)) return { state: 'absent', readiness: null, boundTo: null };
  let readiness;
  try { readiness = readJson(path); } catch { return { state: 'unreadable', readiness: null, boundTo: null }; }
  const named = [readiness?.candidate?.sha256, readiness?.candidateSha256].filter((s) => typeof s === 'string' && s);
  if (candidateSha && named.includes(candidateSha)) return { state: 'bound', readiness, boundTo: candidateSha };
  return { state: 'stale', readiness: null, boundTo: named[0] || null };
}

/** The pending detail that names the file the reviewer must write for this exact candidate. */
export function readinessPending({ ratio, state, boundTo, sha }) {
  const file = `qa/${ratio}/marketing-readiness.json`;
  const need = `candidate.sha256 ${sha.slice(0, 12)}... and its byte count, schema media-studio/marketing-readiness/1 (skills/media-studio/references/marketing-readiness.md)`;
  if (state === 'stale') return `${file} is bound to another candidate (${String(boundTo || 'no candidate hash').slice(0, 12)}...); the reviewer must re-review this file and write ${need}`;
  if (state === 'unreadable') return `${file} is not valid JSON; the reviewer must rewrite it with ${need}`;
  return `the reviewer must write ${file} for this candidate: ${need}`;
}

/** Map a gate script's exit code and report to a gate result. Pass needs exit 0 and report.ok === true. */
export function chainGateResult(name, { code, report, stderr = '' }) {
  const ok = code === 0 && report?.ok === true;
  const errors = (report?.errors || []).slice(0, 3).join(' | ');
  if (name === 'marketing' && report && report.applies === false) return { status: 'fail', detail: `the marketing floor did not apply to this job (${report.reason || 'job.json is not a marketing cut'})` };
  if (!ok) return { status: 'fail', detail: errors || stderr || `exit ${code}, no report` };
  if (name === 'integrity') return { status: 'pass', detail: `${report.clips?.length ?? 0} product clips, ratio ${report.ratio?.deliverable || '?'}${report.warnings?.length ? `, ${report.warnings.length} warnings` : ''}`, report: 'qa/picture-integrity.json' };
  if (name === 'frameIntegrity') return { status: 'pass', detail: `${report.sampled ?? 0} frames sampled, no tiled frame or undeclared luma jump${report.warnings?.length ? `, ${report.warnings.length} warnings` : ''}`, report: 'qa/frame-integrity.json' };
  if (name === 'pointer') return { status: 'pass', detail: `${report.windows?.length ?? 0} windows (${report.mode})${report.mode === 'clip' ? ', whole clips: beat windows need the mapped cue sheet from the sync gate' : ''}`, report: 'qa/pointer-path.json' };
  return { status: 'pass', detail: `${Object.keys(report.checks || {}).filter((k) => !k.endsWith('.note') && report.checks[k] === 'pass').length} checks at or above the marketing floor`, report: 'qa/marketing-readiness-check.json' };
}

async function runScript(moduleRoot, script, args, report) {
  try {
    const r = await run(process.execPath, [gateScript(script, moduleRoot), ...args], { timeoutMs: 600000 });
    return { code: r.code, stderr: tailLine(r), stdout: parseJson(r.stdout), report: readReport(report) };
  } catch (e) { return { code: -1, stderr: e.message, stdout: null, report: null }; }
}

/** gates.integrity: validate-picture-integrity.mjs on the exact candidate, against the compose map the film was cut from. */
export async function runIntegrityGate({ ws, candidate, composeMapRel, moduleRoot }) {
  const out = join(ws, 'qa', 'picture-integrity.json');
  rmSync(out, { force: true });
  const r = await runScript(moduleRoot, 'validate-picture-integrity.mjs', [ws, candidate, '--compose-map', composeMapRel, '--out', out], out);
  return chainGateResult('integrity', r);
}

/** gates.pointer: validate-pointer-path.mjs on the receipt copy in the workspace; a freshly mapped cue sheet gives per-beat windows. */
export async function runPointerGate({ ws, moduleRoot }) {
  const out = join(ws, 'qa', 'pointer-path.json');
  rmSync(out, { force: true });
  const sheet = join(ws, 'plan', 'cue-sheet.json');
  const r = await runScript(moduleRoot, 'validate-pointer-path.mjs', [ws, ...(existsSync(sheet) ? ['--cue-sheet', 'plan/cue-sheet.json'] : []), '--out', out], out);
  return chainGateResult('pointer', r);
}

/** The planned cuts of the edit, from mvg's own compose map, in the shape validate-frame-integrity reads (edl[].startSeconds). */
export function declaredCutsSheet(composeMap) {
  return { generator: 'media-studio/mvg', mode: 'compose-map', edl: (composeMap?.groups || []).map((g) => ({ startSeconds: Number(g.startSeconds) })).filter((g) => Number.isFinite(g.startSeconds)) };
}

/**
 * gates.frameIntegrity: validate-frame-integrity.mjs on the exact candidate (tiled frames, undeclared luma jumps). Its declared
 * cuts come from the mapped cue sheet when the sync gate built one, else from mvg's own compose map (the cuts the edit really
 * plans, so a hard cut from a light title to dark UI is declared, while a flash anywhere else still fails). The report is
 * written to <ws>/qa/frame-integrity.json, where validate-viewer-release.mjs reads it.
 */
export async function runFrameIntegrityGate({ ws, candidate, composeMapRel, moduleRoot }) {
  const out = join(ws, 'qa', 'frame-integrity.json');
  rmSync(out, { force: true });
  const args = [ws, candidate, '--out', out];
  if (!existsSync(join(ws, 'plan', 'cue-sheet.json')) && composeMapRel && existsSync(join(ws, composeMapRel))) {
    mkdirSync(join(ws, 'qa'), { recursive: true });
    const cuts = join(ws, 'qa', 'frame-integrity-cuts.json');
    writeFileSync(cuts, `${JSON.stringify(declaredCutsSheet(readJson(join(ws, composeMapRel))), null, 2)}
`);
    args.push('--cue-sheet', cuts);
  }
  const r = await runScript(moduleRoot, 'validate-frame-integrity.mjs', args, out);
  return chainGateResult('frameIntegrity', r);
}

/**
 * gates.marketing: the reviewer's file is copied into the workspace only when it names this candidate; otherwise the gate is
 * pending (never a fail: nobody has judged it yet) and any earlier copy is removed so no stale report is read.
 */
export async function runMarketingGate({ ws, qdir, ratio, candidate, sha, composeMapRel, moduleRoot }) {
  const wsReadiness = join(ws, 'qa', 'marketing-readiness.json');
  const check = join(ws, 'qa', 'marketing-readiness-check.json');
  rmSync(wsReadiness, { force: true });
  rmSync(check, { force: true });
  // The no-fluff rule is part of the floor and of validate-viewer-release: qa/narration-check.json (validate-narration on the
  // locked script) is written whether or not a reviewer has filed yet.
  const narration = join(ws, 'qa', 'narration-check.json');
  rmSync(narration, { force: true });
  await runScript(moduleRoot, 'validate-narration.mjs', [ws, '--out', narration], narration);
  const found = readMarketingReadiness(join(qdir, 'marketing-readiness.json'), sha);
  if (found.state !== 'bound') return { status: 'pending', detail: readinessPending({ ratio, state: found.state, boundTo: found.boundTo, sha }) };
  mkdirSync(join(ws, 'qa'), { recursive: true });
  copyFileSync(join(qdir, 'marketing-readiness.json'), wsReadiness);
  const cueSheet = join(ws, 'plan', 'cue-sheet.json');
  const r = await runScript(moduleRoot, 'validate-marketing-readiness.mjs', [ws, candidate, '--readiness', wsReadiness, '--compose-map', composeMapRel, ...(existsSync(cueSheet) ? ['--cue-sheet', 'plan/cue-sheet.json'] : []), '--out', check], check);
  return chainGateResult('marketing', r);
}
