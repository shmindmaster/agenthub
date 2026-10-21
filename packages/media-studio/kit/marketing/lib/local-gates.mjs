// Local-AI gates for an encoded ad: encoded ASR (local whisper), the cue sheet, the sync gate and the Local-AI
// listen gate. These start GPU work through D:\Local-AI\ai.ps1, so mvg runs them only with --local-gates and the
// coordinator's go-ahead. Ported from the film post_gates.sh chain (abacare-video-plan-20261019/films/06/tools).
import { existsSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { run } from './mix.mjs';
import { fileSha, readJson, round, writeJson } from './util.mjs';

const AI = process.env.MVG_LOCAL_AI || 'D:\\Local-AI\\ai.ps1';

/** Resolve a shared gate script (deployed beside the kit's screencast tools, or in the repo's scripts folder). */
export function gateScript(name, moduleRoot) {
  const candidates = [join(moduleRoot, '..', 'screencast', name), join(moduleRoot, '..', '..', 'scripts', name)];
  const found = candidates.find((c) => existsSync(c));
  if (!found) throw new Error(`gate script ${name} not found (looked in ${candidates.join(', ')}); run Sync-MediaStudioKit.ps1`);
  return found;
}

const tail = (r) => String(r.stderr || r.stdout || '').trim().split(/\r?\n/).filter(Boolean).slice(-2).join(' | ').slice(0, 300);

export const listenFindings = (report) => ((report.findings || []).map((f) => `${f.severity} ${f.checkId} at ${f.startSeconds}s: ${String(f.description).slice(0, 120)}`).join(' | ') || 'no findings (check the report)');

/** The exact listen command line (the film chain's post_gates.sh passes the same flags). */
export function listenCommand({ candidate, ws, sha, sourceRevision, risk, listenOut }) {
  return `& '${AI}' listen '${candidate}' --transcript '${join(ws, 'story', 'locked-script.txt')}' --pronunciation-manifest '${risk}' --timeline '${join(ws, 'qa', 'listen-timeline.json')}' --candidate-id ${sha} --source-revision ${sourceRevision} --output '${listenOut}'`;
}

export async function runSyncGates({ ws, candidate, moduleRoot, composeMapRel, sourceRevision = 'mvg' }) {
  const out = { sync: { status: 'fail' }, listen: { status: 'fail' } };
  const asrJson = join(ws, 'qa', 'encoded-asr.json');
  const t = await run('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', `& '${AI}' transcribe '${candidate}' --engine whisper --no-vad --json-out '${asrJson}' --out '${join(ws, 'qa', 'encoded-asr.txt')}'`], { timeoutMs: 1800000 });
  if (t.code !== 0) return { ...out, sync: { status: 'fail', detail: 'encoded ASR failed' } };
  const cue = await run(process.execPath, [gateScript('build-cue-sheet.mjs', moduleRoot), ws, '--compose-map', composeMapRel], {});
  if (cue.code !== 0) return { ...out, sync: { status: 'fail', detail: `cue sheet: ${(cue.stderr || cue.stdout).trim().split('\n').pop()}` } };
  const sync = await run(process.execPath, [gateScript('validate-sync.mjs', moduleRoot), ws, candidate], {});
  const report = existsSync(join(ws, 'qa', 'sync.json')) ? readJson(join(ws, 'qa', 'sync.json')) : null;
  out.sync = sync.code === 0 && report?.ok ? { status: 'pass', detail: `${report.errors?.length || 0} errors`, report: 'qa/sync.json' } : { status: 'fail', detail: (report?.errors || [sync.stderr]).slice(0, 3).join(' | ') };
  const sha = fileSha(candidate);
  // The listen gate refuses a speech review without a pronunciation-risk manifest, and the timeline bounds each line.
  const risk = join(ws, 'qa', 'pronunciation-risk.json');
  const listenOut = join(ws, 'qa', 'listen-encoded.json');
  rmSync(risk, { force: true });
  rmSync(listenOut, { force: true });
  // The listen gate also refuses to overwrite its previous raw model response.
  rmSync(`${listenOut}.model-response.txt`, { force: true });
  const pr = await run('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', `& '${AI}' voice pronunciation-risk --segments '${join(ws, 'story', 'narration-segments.json')}' --overrides '${join(ws, 'story', 'reading-overrides.json')}' --out '${risk}' --fail-on never`], { timeoutMs: 600000 });
  if (pr.code !== 0 || !existsSync(risk)) { out.listen = { status: 'fail', detail: `pronunciation-risk failed: ${tail(pr)}` }; return out; }
  const listen = await run('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', listenCommand({ candidate, ws, sha, sourceRevision, risk, listenOut })], { timeoutMs: 1800000 });
  writeFileSync(join(ws, 'qa', 'listen.log'), [listen.stdout, listen.stderr].join(String.fromCharCode(10)));
  const lr = existsSync(listenOut) ? readJson(listenOut) : null;
  // The gate's own rule (and the film chain's): releaseEligible is the pass signal, and ANY finding, a WARNING included,
  // makes the report FAIL / not eligible. Nothing here downgrades a WARNING; the findings are named so a person can judge them.
  out.listen = listen.code === 0 && lr?.releaseEligible === true ? { status: 'pass', detail: `${(lr.findings || []).length} findings` } : { status: 'fail', detail: lr ? `status ${lr.status}, releaseEligible ${lr.releaseEligible}: ${listenFindings(lr)}` : `listen produced no report (exit ${listen.code}): ${tail(listen)}` };
  return out;
}

export async function measureLoudness(candidate, outPath) {
  const r = await run('ffmpeg', ['-hide_banner', '-nostats', '-i', candidate, '-af', 'loudnorm=I=-16:TP=-1:LRA=11:print_format=json', '-f', 'null', '-']);
  const text = r.stderr;
  const m = JSON.parse(text.slice(text.lastIndexOf('{'), text.lastIndexOf('}') + 1));
  const sha = fileSha(candidate);
  const report = { candidate: { path: candidate, sha256: sha }, analyzer: 'ffmpeg-loudnorm', tool: 'ffmpeg-loudnorm', integratedLufs: round(Number(m.input_i), 1), truePeakDbtp: round(Number(m.input_tp), 1), lra: Number(m.input_lra), candidateSha256: sha };
  writeJson(outPath, report);
  return report;
}
