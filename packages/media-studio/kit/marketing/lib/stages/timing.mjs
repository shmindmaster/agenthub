// Stage 3: timing. Word timings per narration line (OpenAI whisper-1 word timestamps, or local whisper), aligned to
// the authored script, then the voice-first timeline (scene length = narration span), caption chunks and an SRT.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { recordStage } from '../context.mjs';
import { checkStage, stageKey, writeStage } from '../cache.mjs';
import { chunkWords, toSrt } from '../captions.mjs';
import { alignBeat, chooseResult, expectationClipTimes } from '../align.mjs';
import { LEAD_SECONDS, TAIL_SECONDS, normalizeCuts } from '../lint.mjs';
import { resolveClip } from './capture.mjs';
import { estimateWhisperUsd } from '../prices.mjs';
import { alignScriptToAsr, buildTimeline, parseAsrWords } from '../timing.mjs';
import { run } from '../mix.mjs';
import { readJson, round, writeJson } from '../util.mjs';

/** Seconds of leading silence before speech (ffmpeg silencedetect at -42 dB), less a 30 ms guard; 0 when speech starts at once. */
export async function speechOnset(file) {
  const r = await run('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-af', 'silencedetect=n=-42dB:d=0.1', '-f', 'null', '-']);
  const text = `${r.stdout || ''}${r.stderr || ''}`;
  const start = /silence_start: ([\d.]+)/.exec(text);
  const end = /silence_end: ([\d.]+)/.exec(text);
  return start && Number(start[1]) <= 0.02 && end ? Math.max(0, round(Number(end[1]) - 0.03, 3)) : 0;
}

export async function probeDuration(file) {
  const r = await run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file]);
  const d = parseFloat(r.stdout);
  if (!(d > 0)) throw new Error(`cannot probe duration of ${file}`);
  return d;
}

async function wordsFor(ctx, { audio, asrPath, duration }) {
  if (existsSync(asrPath)) return { payload: readJson(asrPath), cached: true };
  const provider = ctx.brand.timing?.provider || 'openai-whisper';
  mkdirSync(join(asrPath, '..'), { recursive: true });
  if (provider === 'local-whisper') {
    const local = ctx.providers.localWhisper || (await import('../providers/local.mjs')).whisperWords;
    await local({ file: audio, jsonOut: asrPath, txtOut: asrPath.replace(/\.json$/, '.txt') });
    // Whisper without VAD pins a line's first word at 0 s whatever silence precedes it; move it to the measured speech
    // onset (the film pipeline's fix_asr_onset), so cue words match what the encoded-file ASR hears.
    const payload = readJson(asrPath);
    const onset = await (ctx.providers.speechOnset || speechOnset)(audio);
    const first = (payload.segments || []).flatMap((x) => x.words || [])[0];
    if (first && first.start < onset) {
      first.start = round(Math.min(onset, first.end - 0.05), 3);
      writeFileSync(asrPath, `${JSON.stringify(payload, null, 2)}\n`);
    }
    ctx.ledger.charge({ stage: 'timing', provider: 'openai', service: 'whisper', units: 0, cached: true, note: 'local whisper' });
    return { payload, cached: false };
  }
  const usd = estimateWhisperUsd(duration);
  ctx.ledger.check('openai', usd, 'whisper-1 timing');
  const transcribe = ctx.providers.transcribeWords || (await import('../providers/openai.mjs')).transcribeWords;
  const payload = await transcribe(audio);
  writeFileSync(asrPath, `${JSON.stringify(payload, null, 2)}\n`);
  ctx.ledger.charge({ stage: 'timing', provider: 'openai', service: 'whisper', units: usd, ref: relative(ctx.jobDir, audio) });
  return { payload, cached: false };
}

export async function timingStage(ctx) {
  const out = {};
  for (const cut of normalizeCuts(ctx.spec)) {
    const voicePath = join(ctx.jobDir, 'voice', `${cut.id}.lines.json`);
    if (!existsSync(voicePath)) throw new Error(`timing needs the voice stage first (missing ${voicePath})`);
    const voice = readJson(voicePath);
    const clipShas = cut.beats.filter((b) => b.ui).map((b) => { const r = resolveClip(ctx, b).entry; return [b.id, r.sha256, b.ui.trimStart, b.ui.actions, b.ui.align]; });
    const k = stageKey('timing', { lines: voice.lines.map((l) => [l.key, l.sha256]), beats: cut.beats.map((b) => [b.id, b.kind, b.minSeconds, b.narration, b.onScreenText]), clips: clipShas, provider: ctx.brand.timing?.provider || 'openai-whisper' });
    const cached = checkStage(ctx.jobDir, 'timing', cut.id, k);
    if (cached.hit && !ctx.flags.force) { ctx.log(`timing/${cut.id}: cached`); out[cut.id] = cached.manifest; continue; }
    const byBeat = new Map(voice.lines.map((l) => [l.beatId, l]));
    const lines = [];
    const asrFiles = [];
    for (const beat of cut.beats) {
      const line = byBeat.get(beat.id);
      if (!beat.narration) { lines.push({ beat }); continue; }
      if (!line) throw new Error(`no voice line for narrated beat ${cut.id}/${beat.id}`);
      const audio = join(ctx.jobDir, line.file);
      const duration = await (ctx.providers.probeDuration || probeDuration)(audio);
      const asrRel = join('timing', cut.id, 'asr', `${beat.id}-${line.key.slice(0, 12)}-${ctx.brand.timing?.provider || 'openai-whisper'}.json`);
      const { payload } = await wordsFor(ctx, { audio, asrPath: join(ctx.jobDir, asrRel), duration });
      asrFiles.push(asrRel);
      const words = alignScriptToAsr(beat.narration, parseAsrWords(payload), duration);
      // A beat is as long as the result needs to hold after its last narrated pointer action (>= 1.5 s), measured with the
      // clip cut so the first action lands on its spoken word.
      let sized = beat;
      if (beat.ui) {
        const { entry } = resolveClip(ctx, beat);
        let trimStart = beat.ui.trimStart || 0;
        let required = null;
        if (beat.ui.actions?.length && beat.ui.align !== false) {
          const a = alignBeat({ actions: beat.ui.actions, receiptActions: entry.actions, headTrim: entry.recastHeadTrimSeconds ?? 0, wordsRel: words.map((w) => ({ word: w.word, start: w.start + LEAD_SECONDS })), fallbackTrim: trimStart });
          if (a.aligned) { trimStart = a.trimStart; required = a.requiredSeconds; }
        }
        // A result the capture observed must be visible inside the beat and hold >= 1.5 s: a slightly late one lengthens the beat.
        const natural = Math.max(LEAD_SECONDS + duration + TAIL_SECONDS, beat.minSeconds || 0, required || 0);
        const result = chooseResult({ expectations: expectationClipTimes(entry), trimStart, naturalSeconds: natural });
        const needed = Math.max(required || 0, result.requiredSeconds || 0);
        if (needed > (beat.minSeconds || 0)) sized = { ...beat, minSeconds: needed };
      }
      lines.push({ beat: sized, audio: { durationSeconds: round(duration, 3), words, asr: asrRel } });
    }
    const timeline = buildTimeline(lines);
    const chunks = [];
    for (const seg of timeline.segments) {
      if (!seg.words.length) continue;
      const beat = cut.beats.find((b) => b.id === seg.id);
      for (const c of chunkWords(seg.words, { ...(ctx.brand.captionStyle || {}) })) chunks.push({ ...c, beatId: seg.id, emphasis: beat.emphasis || [] });
    }
    const base = join('timing', cut.id);
    const files = { timeline: join(base, 'timeline.json'), captions: join(base, 'captions.json'), srt: join(base, 'captions.srt') };
    writeJson(join(ctx.jobDir, files.timeline), { ...timeline, cut: cut.id, targetSeconds: cut.targetSeconds, lines: lines.map((l) => ({ beatId: l.beat.id, asr: l.audio?.asr || null })) });
    writeJson(join(ctx.jobDir, files.captions), { cut: cut.id, chunks });
    writeFileSync(join(ctx.jobDir, files.srt), toSrt(chunks), 'utf8');
    const over = timeline.durationSeconds - cut.targetSeconds;
    const detail = { durationSeconds: timeline.durationSeconds, targetSeconds: cut.targetSeconds, overSeconds: round(over, 2), captionChunks: chunks.length };
    out[cut.id] = writeStage(ctx.jobDir, 'timing', cut.id, k, { ...detail, outputs: [...Object.values(files), ...asrFiles] });
    if (over > Math.max(2, cut.targetSeconds * 0.1)) throw new Error(`cut ${cut.id} runs ${timeline.durationSeconds}s against a ${cut.targetSeconds}s target (+${over.toFixed(1)}s; allowed ${Math.max(2, cut.targetSeconds * 0.1).toFixed(1)}s, the longer of 2 s and 10%): trim the narration or beat minimums`);
    if (over < -0.2 * cut.targetSeconds - 2) ctx.log(`timing/${cut.id}: ${timeline.durationSeconds}s is well under the ${cut.targetSeconds}s target`);
  }
  recordStage(ctx, 'timing', 'done', { cuts: Object.fromEntries(Object.entries(out).map(([k, v]) => [k, { durationSeconds: v.durationSeconds, targetSeconds: v.targetSeconds }])) });
  return out;
}

