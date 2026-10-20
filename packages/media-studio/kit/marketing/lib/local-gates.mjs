// Local-AI gates for an encoded ad: encoded ASR (local whisper), the cue sheet, the sync gate and the Local-AI
// listen gate. These start GPU work through D:\Local-AI\ai.ps1, so mvg runs them only with --local-gates and the
// coordinator's go-ahead. Ported from the film post_gates.sh chain (abacare-video-plan-20261019/films/06/tools).
import { existsSync } from 'node:fs';
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
  const listen = await run('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', `& '${AI}' listen '${candidate}' --transcript '${join(ws, 'story', 'locked-script.txt')}' --candidate-id ${sha} --source-revision ${sourceRevision} --output '${join(ws, 'qa', 'listen-encoded.json')}'`], { timeoutMs: 1800000 });
  const lr = existsSync(join(ws, 'qa', 'listen-encoded.json')) ? readJson(join(ws, 'qa', 'listen-encoded.json')) : null;
  out.listen = listen.code === 0 && lr?.releaseEligible === true ? { status: 'pass', detail: `${(lr.findings || []).length} findings` } : { status: 'fail', detail: lr ? `status ${lr.status}, ${(lr.findings || []).length} findings` : 'listen produced no report' };
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
