// Stage 3: timing. The forced aligner clocks each accepted narration take against its authored script, then builds the
// voice-first timeline (scene length = narration span), caption chunks and an SRT. Whisper timing is an explicit
// compatibility fallback for jobs without an aligner. With edit.beatGrid every boundary is held to the next music beat.
// Local AI is off: the aligner is injected (ctx.providers.alignWords); the default refuses and names the hosted route. Receipts already on disk are reused, so existing jobs still rebuild their timelines.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { recordStage } from '../context.mjs';
import { checkStage, stageKey, writeStage } from '../cache.mjs';
import { chunkWords, toSrt } from '../captions.mjs';
import { alignBeat, chooseResult, expectationClipTimes } from '../align.mjs';
import { LEAD_SECONDS, TAIL_SECONDS, normalizeCuts } from '../lint.mjs';
import { resolveClip } from './capture.mjs';
import { estimateWhisperUsd } from '../prices.mjs';
import { FPS, alignScriptToAsr, buildTimeline, parseAsrWords, snapToBeatGrid } from '../timing.mjs';
import { forcedWordOnsets, textWords } from '../../../screencast/sync-lib.mjs';
import { run } from '../mix.mjs';
import { fileSha, localAiOff, readJson, round, writeJson } from '../util.mjs';

export async function probeDuration(file) {
  const r = await run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file]);
  const d = parseFloat(r.stdout);
  if (!(d > 0)) throw new Error(`cannot probe duration of ${file}`);
  return d;
}

export function timingWordSource(flags = {}) {
  if (flags.whisperTiming) {
    return { clock: 'whisper', provider: 'openai-whisper' };
  }
  // 'local-aligner' is the historical receipt label: it keys existing timing caches and timing/<cut>/asr file names.
  return { clock: 'forced-aligner', provider: 'local-aligner' };
}

async function whisperWordsFor(ctx, { audio, asrPath, duration }) {
  if (existsSync(asrPath)) return { payload: readJson(asrPath), cached: true };
  mkdirSync(join(asrPath, '..'), { recursive: true });
  const usd = estimateWhisperUsd(duration);
  ctx.ledger.check('openai', usd, 'hosted word timing');
  const transcribe = ctx.providers.transcribeWords || (await import('../providers/openai.mjs')).transcribeWords;
  const payload = await transcribe(audio);
  writeFileSync(asrPath, `${JSON.stringify(payload, null, 2)}\n`);
  ctx.ledger.charge({ stage: 'timing', provider: 'openai', service: 'whisper', units: usd, ref: relative(ctx.jobDir, audio) });
  return { payload, cached: false };
}

async function alignedWordsFor(ctx, { audio, asrPath, script, acceptedTakeSha256 }) {
  mkdirSync(join(asrPath, '..'), { recursive: true });
  const scriptPath = asrPath.replace(/\.json$/, '.script.txt');
  writeFileSync(scriptPath, script, 'utf8');
  const takeSha256 = fileSha(audio);
  if (!acceptedTakeSha256 || takeSha256 !== acceptedTakeSha256) throw new Error(`accepted narration take changed before timing: ${audio}`);
  const cached = existsSync(asrPath);
  if (!cached) {
    const align = ctx.providers.alignWords || localAiOff('forced alignment');
    await align({ file: audio, script: scriptPath, output: asrPath });
  }
  const report = readJson(asrPath);
  const expectedWords = textWords(script).map((word) => ({ w: word }));
  const words = forcedWordOnsets(report, expectedWords, { takeSha256, scriptSha256: fileSha(scriptPath) })
    .map((w) => ({ word: w.w, start: round(w.start), end: round(w.end) }));
  return { payload: report, words, cached, scriptPath };
}

export async function wordsFor(ctx, options) {
  const source = options.source || timingWordSource(ctx.flags);
  if (source.clock === 'forced-aligner') return alignedWordsFor(ctx, options);
  const result = await whisperWordsFor(ctx, options);
  return { ...result, words: alignScriptToAsr(options.script, parseAsrWords(result.payload), options.duration) };
}

/** Seconds the closing picture must hold after the last spoken word of the program: cut.finalHoldSeconds, else spec.finalHoldSeconds. */
export const finalHoldOf = (spec, cut) => { const n = Number(cut.finalHoldSeconds ?? spec.finalHoldSeconds); return n > 0 ? n : 0; };

/**
 * Grow the last beat so the timeline ends at least `finalHoldSeconds` after the last spoken word anywhere in the program (a silent
 * final beat counts from the speech before it). The end is rounded up to a whole frame. With no hold, or when the timeline already
 * ends that late, the same timeline object comes back, so a spec without the field keeps byte-identical timelines.
 */
export function holdFinalBeat(timeline, finalHoldSeconds, fps = FPS) {
  const hold = Number(finalHoldSeconds);
  if (!(hold > 0) || !timeline.segments.length) return timeline;
  const speechEnd = Math.max(0, ...timeline.segments.map((s) => Math.max(s.words?.length ? s.words[s.words.length - 1].end : 0, s.lineStartSeconds === null || s.lineStartSeconds === undefined ? 0 : s.lineStartSeconds + s.speechSeconds)));
  const end = Math.ceil(((speechEnd + hold) * fps) - 1e-6) / fps;
  if (end <= timeline.durationSeconds) return timeline;
  const segments = timeline.segments.map((s, i, all) => (i === all.length - 1 ? { ...s, durationSeconds: round(end - s.startSeconds) } : s));
  return { ...timeline, durationSeconds: round(end), segments };
}

export async function timingStage(ctx) {
  const out = {};
  const source = timingWordSource(ctx.flags);
  // edit.beatGrid keys the stage only when set, so a spec without it keeps its cache; the music asset never sees it (spec.music).
  const grid = ctx.spec.edit?.beatGrid ? { bpm: ctx.spec.edit.beatGrid.bpm, offsetSeconds: ctx.spec.edit.beatGrid.offsetSeconds } : null;
  for (const cut of normalizeCuts(ctx.spec)) {
    const voicePath = join(ctx.jobDir, 'voice', `${cut.id}.lines.json`);
    if (!existsSync(voicePath)) throw new Error(`timing needs the voice stage first (missing ${voicePath})`);
    const voice = readJson(voicePath);
    const acceptedLines = voice.lines.map((line) => {
      const audio = join(ctx.jobDir, line.file);
      const sha256 = fileSha(audio);
      if (!line.sha256 || sha256 !== line.sha256) throw new Error(`accepted narration take changed before timing: ${audio}`);
      return [line.key, sha256];
    });
    const clipShas = cut.beats.filter((b) => b.ui).map((b) => { const r = resolveClip(ctx, b).entry; return [b.id, r.sha256, b.ui.trimStart, b.ui.actions, b.ui.align]; });
    const k = stageKey('timing', { lines: acceptedLines, beats: cut.beats.map((b) => [b.id, b.kind, b.minSeconds, b.narration, b.onScreenText]), clips: clipShas, clock: source.clock, provider: source.provider, ...(grid ? { beatGrid: grid, frameSnap: FPS } : {}), ...(finalHoldOf(ctx.spec, cut) ? { finalHold: finalHoldOf(ctx.spec, cut) } : {}) });
    const cached = checkStage(ctx.jobDir, 'timing', cut.id, k);
    if (cached.hit && !ctx.flags.force) { ctx.log(`timing/${cut.id}: cached`); out[cut.id] = cached.manifest; continue; }
    const byBeat = new Map(voice.lines.map((l) => [l.beatId, l]));
    const lines = [];
    const timingFiles = [];
    for (const beat of cut.beats) {
      const line = byBeat.get(beat.id);
      if (!beat.narration) { lines.push({ beat }); continue; }
      if (!line) throw new Error(`no voice line for narrated beat ${cut.id}/${beat.id}`);
      const audio = join(ctx.jobDir, line.file);
      const duration = await (ctx.providers.probeDuration || probeDuration)(audio);
      const asrRel = join('timing', cut.id, 'asr', `${beat.id}-${line.key.slice(0, 12)}-${source.provider}.json`);
      const asrPath = join(ctx.jobDir, asrRel);
      const { words, scriptPath } = await wordsFor(ctx, { audio, asrPath, duration, script: beat.narration, acceptedTakeSha256: line.sha256, source });
      timingFiles.push(asrRel);
      if (scriptPath) timingFiles.push(relative(ctx.jobDir, scriptPath));
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
    // Beat-grid boundaries are snapped to whole frames too (FPS): a boundary between frames would leave the picture a gap frame.
    const spoken = grid ? snapToBeatGrid(buildTimeline(lines), grid, { fps: FPS }) : buildTimeline(lines);
    // The authored closing hold is part of the one timeline every later stage and gate reads.
    const timeline = holdFinalBeat(spoken, finalHoldOf(ctx.spec, cut));
    const chunks = [];
    for (const seg of timeline.segments) {
      if (!seg.words.length) continue;
      const beat = cut.beats.find((b) => b.id === seg.id);
      for (const c of chunkWords(seg.words, { ...(ctx.brand.captionStyle || {}) })) chunks.push({ ...c, beatId: seg.id, emphasis: beat.emphasis || [] });
    }
    const base = join('timing', cut.id);
    const files = { timeline: join(base, 'timeline.json'), captions: join(base, 'captions.json'), srt: join(base, 'captions.srt') };
    writeJson(join(ctx.jobDir, files.timeline), {
      ...timeline,
      cut: cut.id,
      targetSeconds: cut.targetSeconds,
      wordClock: source.clock,
      lines: lines.map((line) => {
        const asr = line.audio?.asr || null;
        return { beatId: line.beat.id, asr, alignment: asr ? { path: asr, sha256: fileSha(join(ctx.jobDir, asr)) } : null };
      }),
    });
    writeJson(join(ctx.jobDir, files.captions), { cut: cut.id, chunks });
    writeFileSync(join(ctx.jobDir, files.srt), toSrt(chunks), 'utf8');
    // The delivered length (spoken plus the closing hold) is what the target bounds, as in lint's estimate.
    const over = timeline.durationSeconds - cut.targetSeconds;
    const detail = { durationSeconds: timeline.durationSeconds, targetSeconds: cut.targetSeconds, overSeconds: round(over, 2), captionChunks: chunks.length, wordClock: source.clock, ...(timeline.beatGrid ? { beatGrid: timeline.beatGrid } : {}) };
    out[cut.id] = writeStage(ctx.jobDir, 'timing', cut.id, k, { ...detail, outputs: [...Object.values(files), ...timingFiles] });
    if (over > Math.max(2, cut.targetSeconds * 0.1)) throw new Error(`cut ${cut.id} runs ${timeline.durationSeconds}s against a ${cut.targetSeconds}s target (+${over.toFixed(1)}s; allowed ${Math.max(2, cut.targetSeconds * 0.1).toFixed(1)}s, the longer of 2 s and 10%): trim the narration or beat minimums`);
    if (over < -0.2 * cut.targetSeconds - 2) ctx.log(`timing/${cut.id}: ${timeline.durationSeconds}s is well under the ${cut.targetSeconds}s target`);
  }
  recordStage(ctx, 'timing', 'done', { cuts: Object.fromEntries(Object.entries(out).map(([k, v]) => [k, { durationSeconds: v.durationSeconds, targetSeconds: v.targetSeconds }])) });
  return out;
}

