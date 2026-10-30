// Gate runners for an encoded ad: the shared gate scripts (cue sheet, word-sync, sync), the independent transcript text
// check and the loudness measurement. Ported from the film post_gates.sh chain (abacare-video-plan-20261019/films/06/tools).
// Local AI is off (owner direction 2026-10-29): nothing here starts a model. The forced aligner and the transcript are
// injected; their defaults refuse and name the hosted route. The listen gate had no hosted runner, so mvg leaves it pending.
import { existsSync, rmSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { run } from './mix.mjs';
import { fileSha, localAiOff, readJson, round, writeJson } from './util.mjs';
import { expandKeywords } from './align.mjs';
import { forcedWordOnsets, textWords } from '../../screencast/sync-lib.mjs';

/** Resolve a shared gate script (deployed beside the kit's screencast tools, or in the repo's scripts folder). */
export function gateScript(name, moduleRoot) {
  const candidates = [join(moduleRoot, '..', 'screencast', name), join(moduleRoot, '..', '..', 'scripts', name)];
  const found = candidates.find((c) => existsSync(c));
  if (!found) throw new Error(`gate script ${name} not found (looked in ${candidates.join(', ')}); run Sync-MediaStudioKit.ps1`);
  return found;
}

/** Transcript text only. Preserve numeric values and word boundaries, not ASR onset times. */
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

/**
 * Sync, word-sync and transcript gates on the exact encoded candidate.
 * @param {Function} [o.align] ({ file, script, output }) => writes a forced-alignment report; default refuses (Local AI is off)
 * @param {Function|null} [o.transcribe] ({ file, jsonOut, txtOut }) => writes the encoded transcript JSON; default refuses;
 *   null skips the transcript gate (no result, so the caller reports it pending)
 */
export async function runSyncGates({ ws, candidate, moduleRoot, composeMapRel, voiceLines, align = localAiOff('local aligner'), transcribe = localAiOff('encoded transcript'), runCommand = run }) {
  const out = { sync: { status: 'fail' } };
  rmSync(join(ws, 'qa', 'encoded-alignment.json'), { force: true });
  rmSync(join(ws, 'qa', 'word-sync.json'), { force: true });
  try {
    const timeline = readJson(join(ws, 'story', 'narration-timeline.json'));
    if (voiceLines?.length !== timeline.segments.length) throw new Error('mix-plan voice lines do not cover the narration timeline');
    const jobPath = join(ws, 'job.json');
    const job = readJson(jobPath);
    // A hosted asr-anchored report clocks the picture only where job.json opts in, exactly as the shared gates require.
    const allowAsrAnchored = job.clockPolicy?.allowAsrAnchored === true;
    const alignDir = join(ws, 'qa', 'align', randomUUID());
    mkdirSync(alignDir, { recursive: true });
    for (const [i, seg] of timeline.segments.entries()) {
      const line = voiceLines[i];
      const script = join(alignDir, `${i}.txt`), output = join(alignDir, `${i}.json`);
      writeFileSync(script, seg.text, 'utf8');
      await align({ file: line.file, script, output });
      const expected = textWords(seg.text).map((w) => ({ w }));
      const words = forcedWordOnsets(readJson(output), expected, { takeSha256: fileSha(line.file), scriptSha256: fileSha(script), allowAsrAnchored });
      const lead = line.startSec - seg.startSeconds;
      writeJson(join(ws, 'voice', 'asr', `${seg.id}.json`), { words: words.map((w) => ({ ...w, start: round(w.start + lead), end: round(w.end + lead) })), clock: 'forced-aligner', takeSha256: fileSha(line.file), alignment: output });
    }
    const output = join(alignDir, 'encoded.json');
    await align({ file: candidate, script: join(ws, 'story', 'locked-script.txt'), output });
    copyFileSync(output, join(ws, 'qa', 'encoded-alignment.json'));
    writeJson(jobPath, { ...job, syncClock: 'forced-aligner' });
  } catch (e) {
    out.wordSync = { status: 'fail', detail: `forced alignment: ${e.message}` };
  }
  const asrJson = join(ws, 'qa', 'encoded-asr.json');
  rmSync(asrJson, { force: true });
  // transcribe: null means no transcript runner was provided; the caller records the gate as pending.
  if (transcribe) try {
    await transcribe({ file: candidate, jsonOut: asrJson, txtOut: join(ws, 'qa', 'encoded-asr.txt') });
    try {
      // Text only. Word timing is deliberately discarded.
      const content = readJson(asrJson);
      const spoken = content.text || content.segments?.map((s) => s.text).join(' ') || content.words?.map((w) => w.word || w.text).join(' ') || '';
      const locked = readJson(join(ws, 'story', 'narration-timeline.json')).segments.map((s) => s.text).join(' ');
      out.transcript = transcriptKey(spoken) && transcriptKey(spoken) === transcriptKey(locked)
        ? { status: 'pass', detail: 'transcript text matches the locked script (not a timing clock)' }
        : { status: 'fail', detail: 'transcript text differs from the locked script; inspect transcript, not onsets' };
    } catch {
      out.transcript = { status: 'fail', detail: 'encoded transcript or locked script is unreadable' };
    }
  } catch (e) {
    out.transcript = { status: 'fail', detail: `encoded transcript failed: ${e.message}` };
  }
  const cue = await runCommand(process.execPath, [gateScript('build-cue-sheet.mjs', moduleRoot), ws, '--compose-map', composeMapRel], {});
  if (cue.code !== 0) return { ...out, sync: { status: 'fail', detail: `cue sheet: ${(cue.stderr || cue.stdout).trim().split('\n').pop()}` } };
  const word = await runCommand(process.execPath, [gateScript('validate-word-sync.mjs', moduleRoot), ws, candidate], {});
  const wr = existsSync(join(ws, 'qa', 'word-sync.json')) ? readJson(join(ws, 'qa', 'word-sync.json')) : null;
  out.wordSync ||= word.code === 0 && wr?.ok ? { status: 'pass', detail: `forced-aligner grid ${wr.gridMs} ms; offset ${wr.offsetMs} ms, drift ${wr.driftMs} ms`, report: 'qa/word-sync.json' } : { status: 'fail', detail: (wr?.errors || [word.stderr]).join(' | ') };
  const sync = await runCommand(process.execPath, [gateScript('validate-sync.mjs', moduleRoot), ws, candidate], {});
  const report = existsSync(join(ws, 'qa', 'sync.json')) ? readJson(join(ws, 'qa', 'sync.json')) : null;
  out.sync = sync.code === 0 && report?.ok ? { status: 'pass', detail: `${report.errors?.length || 0} errors`, report: 'qa/sync.json' } : { status: 'fail', detail: (report?.errors || [sync.stderr]).slice(0, 3).join(' | ') };
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
