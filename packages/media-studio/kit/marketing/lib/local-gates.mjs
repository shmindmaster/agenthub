// Local-AI gates for an encoded ad: forced alignment, independent Whisper text, the cue sheet, sync and Local-AI
// listen gate. These start GPU work through D:\Local-AI\ai.ps1, so mvg runs them only with --local-gates and the
// coordinator's go-ahead. Ported from the film post_gates.sh chain (abacare-video-plan-20261019/films/06/tools).
import { existsSync, rmSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { run } from './mix.mjs';
import { fileSha, readJson, round, writeJson } from './util.mjs';
import { expandKeywords } from './align.mjs';
import { alignWords as forceAlign } from './providers/local.mjs';
import { forcedWordOnsets, textWords } from '../../screencast/sync-lib.mjs';

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

/** Transcript text only. Preserve numeric values and word boundaries, not Whisper onset times. */
export function transcriptKey(text) {
  const source = String(text).toLowerCase().replace(/[’']/g, '').replace(/%/g, ' percent ');
  const words = [...source.matchAll(/[\p{L}]+|-?\d+(?:\.\d+)?/gu)];
  const number = word => expandKeywords([word]).find(key => /^\d+$/.test(key));
  const keys = [];
  for (let i = 0; i < words.length; i++) {
    const hit = words[i];
    const n = number(hit[0]), unit = number(words[i + 1]?.[0]);
    const adjacent = words[i + 1] && /^[\s-]+$/.test(source.slice(hit.index + hit[0].length, words[i + 1].index));
    if (/^[\p{L}]+$/u.test(hit[0]) && n && Number(n) >= 20 && Number(n) <= 90 && Number(n) % 10 === 0 && unit && Number(unit) > 0 && Number(unit) < 10 && adjacent) {
      i++;
      keys.push(String(Number(n) + Number(unit)));
    } else {
      keys.push(/^-?\d/.test(hit[0]) ? hit[0] : number(hit[0]) || hit[0]);
    }
  }
  return keys.join(' ');
}

/** The exact listen command line (the film chain's post_gates.sh passes the same flags). */
export function listenCommand({ candidate, ws, sha, sourceRevision, risk, listenOut }) {
  return `& '${AI}' listen '${candidate}' --transcript '${join(ws, 'story', 'locked-script.txt')}' --pronunciation-manifest '${risk}' --timeline '${join(ws, 'qa', 'listen-timeline.json')}' --candidate-id ${sha} --source-revision ${sourceRevision} --output '${listenOut}'`;
}

export async function runSyncGates({ ws, candidate, moduleRoot, composeMapRel, sourceRevision = 'mvg', voiceLines, align = forceAlign, runCommand = run }) {
  const out = { sync: { status: 'fail' }, listen: { status: 'fail' } };
  rmSync(join(ws, 'qa', 'encoded-alignment.json'), { force: true });
  rmSync(join(ws, 'qa', 'word-sync.json'), { force: true });
  try {
    const timeline = readJson(join(ws, 'story', 'narration-timeline.json'));
    if (voiceLines?.length !== timeline.segments.length) throw new Error('mix-plan voice lines do not cover the narration timeline');
    const alignDir = join(ws, 'qa', 'align', randomUUID());
    mkdirSync(alignDir, { recursive: true });
    for (const [i, seg] of timeline.segments.entries()) {
      const line = voiceLines[i];
      const script = join(alignDir, `${i}.txt`), output = join(alignDir, `${i}.json`);
      writeFileSync(script, seg.text, 'utf8');
      await align({ file: line.file, script, output });
      const expected = textWords(seg.text).map((w) => ({ w }));
      const words = forcedWordOnsets(readJson(output), expected, { takeSha256: fileSha(line.file), scriptSha256: fileSha(script) });
      const lead = line.startSec - seg.startSeconds;
      writeJson(join(ws, 'voice', 'asr', `${seg.id}.json`), { words: words.map((w) => ({ ...w, start: round(w.start + lead), end: round(w.end + lead) })), clock: 'forced-aligner', takeSha256: fileSha(line.file), alignment: output });
    }
    const output = join(alignDir, 'encoded.json');
    await align({ file: candidate, script: join(ws, 'story', 'locked-script.txt'), output });
    copyFileSync(output, join(ws, 'qa', 'encoded-alignment.json'));
    const jobPath = join(ws, 'job.json');
    writeJson(jobPath, { ...readJson(jobPath), syncClock: 'forced-aligner' });
  } catch (e) {
    out.wordSync = { status: 'fail', detail: `forced alignment: ${e.message}` };
  }
  const asrJson = join(ws, 'qa', 'encoded-asr.json');
  const t = await runCommand('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', `& '${AI}' transcribe '${candidate}' --engine whisper --no-vad --json-out '${asrJson}' --out '${join(ws, 'qa', 'encoded-asr.txt')}'`], { timeoutMs: 1800000 });
  out.transcript = { status: 'fail', detail: 'encoded transcript failed' };
  if (t.code === 0) {
    try {
      // Text only. Word timing is deliberately discarded.
      const content = readJson(asrJson);
      const spoken = content.text || content.segments?.map((s) => s.text).join(' ') || content.words?.map((w) => w.word || w.text).join(' ') || '';
      const locked = readJson(join(ws, 'story', 'narration-timeline.json')).segments.map((s) => s.text).join(' ');
      out.transcript = transcriptKey(spoken) && transcriptKey(spoken) === transcriptKey(locked)
        ? { status: 'pass', detail: 'Whisper text matches the locked script (not a timing clock)' }
        : { status: 'fail', detail: 'Whisper text differs from the locked script; inspect transcript, not onsets' };
    } catch {
      out.transcript = { status: 'fail', detail: 'encoded transcript or locked script is unreadable' };
    }
  }
  const cue = await runCommand(process.execPath, [gateScript('build-cue-sheet.mjs', moduleRoot), ws, '--compose-map', composeMapRel], {});
  if (cue.code !== 0) return { ...out, sync: { status: 'fail', detail: `cue sheet: ${(cue.stderr || cue.stdout).trim().split('\n').pop()}` } };
  const word = await runCommand(process.execPath, [gateScript('validate-word-sync.mjs', moduleRoot), ws, candidate], {});
  const wr = existsSync(join(ws, 'qa', 'word-sync.json')) ? readJson(join(ws, 'qa', 'word-sync.json')) : null;
  out.wordSync ||= word.code === 0 && wr?.ok ? { status: 'pass', detail: `forced-aligner grid ${wr.gridMs} ms; offset ${wr.offsetMs} ms, drift ${wr.driftMs} ms`, report: 'qa/word-sync.json' } : { status: 'fail', detail: (wr?.errors || [word.stderr]).join(' | ') };
  const sync = await runCommand(process.execPath, [gateScript('validate-sync.mjs', moduleRoot), ws, candidate], {});
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
  const pr = await runCommand('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', `& '${AI}' voice pronunciation-risk --segments '${join(ws, 'story', 'narration-segments.json')}' --overrides '${join(ws, 'story', 'reading-overrides.json')}' --out '${risk}' --fail-on never`], { timeoutMs: 600000 });
  if (pr.code !== 0 || !existsSync(risk)) { out.listen = { status: 'fail', detail: `pronunciation-risk failed: ${tail(pr)}` }; return out; }
  const listen = await runCommand('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', listenCommand({ candidate, ws, sha, sourceRevision, risk, listenOut })], { timeoutMs: 1800000 });
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
