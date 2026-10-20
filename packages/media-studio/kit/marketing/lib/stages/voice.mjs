// Stage 2: voice. One file per narrated beat; ElevenLabs (governed ledger, request stitching), OpenAI
// gpt-4o-mini-tts (instructions) or local Qwen (Local-AI) behind one interface. Cached by
// (text, voice, model, settings, neighbors), so an unchanged line never costs twice.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { recordStage } from '../context.mjs';
import { checkStage, stageKey, writeStage } from '../cache.mjs';
import { normalizeCuts } from '../lint.mjs';
import { estimateOpenAiSpeechUsd, estimateTtsCredits } from '../prices.mjs';
import { fileSha, hashOf, writeJson } from '../util.mjs';

export function lineKey(spec, text, prev, next) {
  const v = spec.voice;
  return hashOf({
    provider: v.provider, voiceId: v.voiceId, model: v.model, settings: v.settings || null, instructions: v.instructions || null,
    dictionaries: v.pronunciationDictionaries || null, stitching: !!v.stitching, text, prev: v.stitching ? prev || null : null, next: v.stitching ? next || null : null,
  });
}

export const lineExt = (provider) => (provider === 'local' ? 'wav' : 'mp3');

async function renderLine(ctx, { text, prev, next, out, key }) {
  const v = ctx.spec.voice;
  const P = ctx.providers;
  if (v.provider === 'elevenlabs') {
    const credits = estimateTtsCredits(text, v.model);
    ctx.ledger.check('elevenlabs', credits, `voice line "${text.slice(0, 40)}"`);
    const eleven = P.elevenlabs || (await import('../providers/elevenlabs.mjs'));
    const cli = P.elevenCli || eleven.resolveCli(ctx.brand);
    const res = await eleven.speech(cli, {
      text, output: out, voiceId: v.voiceId, model: v.model, settings: v.settings, maxCredits: credits,
      workspace: ctx.workspaceId, revision: 'mvg-voice-v1', previousText: v.stitching ? prev : undefined, nextText: v.stitching ? next : undefined,
      dictionaries: v.pronunciationDictionaries, run: P.runCli,
    });
    const reused = !!res.receipt?.reused;
    ctx.ledger.charge({ stage: 'voice', provider: 'elevenlabs', service: 'tts', units: res.receipt?.actual_credits ?? credits, estimated: res.receipt?.actual_credits == null, cached: reused, ref: key.slice(0, 12), note: `request ${res.receipt?.request_id || '?'}` });
    return { receipt: res.receipt };
  }
  if (v.provider === 'openai') {
    const usd = estimateOpenAiSpeechUsd(text);
    ctx.ledger.check('openai', usd, 'OpenAI speech');
    const openai = P.openai || (await import('../providers/openai.mjs'));
    const res = await openai.speech({ text, voice: v.voiceId, instructions: v.instructions, model: v.model });
    mkdirSync(join(out, '..'), { recursive: true });
    writeFileSync(out, res.bytes);
    ctx.ledger.charge({ stage: 'voice', provider: 'openai', service: 'speech', units: usd, ref: key.slice(0, 12) });
    return { receipt: { provider: 'openai', model: v.model, voice: v.voiceId, aiGenerated: true } };
  }
  if (v.provider === 'local') {
    const local = P.localVoice || (await import('../providers/local.mjs')).qwenRole;
    await local({ speaker: v.voiceId, instruction: v.instructions || '', text, out });
    return { receipt: { provider: 'local', speaker: v.voiceId } };
  }
  throw new Error(`unsupported voice provider ${v.provider}`);
}

export async function voiceStage(ctx) {
  const results = {};
  for (const cut of normalizeCuts(ctx.spec)) {
    const narrated = cut.beats.filter((b) => b.narration);
    const plan = narrated.map((b, i) => ({
      beat: b.id, text: b.narration, prev: narrated[i - 1]?.narration, next: narrated[i + 1]?.narration,
    })).map((l) => ({ ...l, key: lineKey(ctx.spec, l.text, l.prev, l.next) }));
    const ext = lineExt(ctx.spec.voice.provider);
    const stageK = stageKey('voice', { lines: plan.map((l) => l.key) });
    const cached = checkStage(ctx.jobDir, 'voice', cut.id, stageK);
    if (cached.hit && !ctx.flags.force) { ctx.log(`voice/${cut.id}: cached`); results[cut.id] = cached.manifest; continue; }
    const lines = [];
    for (const l of plan) {
      const rel = join('voice', 'lines', `${l.key.slice(0, 16)}.${ext}`);
      const out = join(ctx.jobDir, rel);
      mkdirSync(join(ctx.jobDir, 'voice', 'lines'), { recursive: true });
      let receipt = null;
      if (existsSync(out)) {
        ctx.ledger.charge({ stage: 'voice', provider: ctx.spec.voice.provider === 'openai' ? 'openai' : 'elevenlabs', service: 'tts', units: 0, cached: true, ref: l.key.slice(0, 12), note: 'line file already present' });
      } else if (ctx.flags.dryRun) {
        ctx.log(`voice/${cut.id}/${l.beat}: would render ${l.text.length} chars`);
        continue;
      } else {
        ctx.log(`voice/${cut.id}/${l.beat}: rendering (${ctx.spec.voice.provider})`);
        receipt = (await renderLine(ctx, { ...l, out })).receipt;
      }
      lines.push({ beatId: l.beat, text: l.text, file: rel.replace(/\\/g, '/'), key: l.key, sha256: existsSync(out) ? fileSha(out) : null, receipt });
    }
    if (ctx.flags.dryRun) { results[cut.id] = { dryRun: true, lines: plan.map((l) => ({ beatId: l.beat, key: l.key })) }; continue; }
    const manifestPath = join(ctx.jobDir, 'voice', `${cut.id}.lines.json`);
    writeJson(manifestPath, { cut: cut.id, voice: { provider: ctx.spec.voice.provider, voiceId: ctx.spec.voice.voiceId, model: ctx.spec.voice.model, name: ctx.spec.voice.name || null, aiGenerated: true }, lines });
    results[cut.id] = writeStage(ctx.jobDir, 'voice', cut.id, stageK, { lines, outputs: [relative(ctx.jobDir, manifestPath), ...lines.map((l) => l.file)] });
  }
  recordStage(ctx, 'voice', ctx.flags.dryRun ? 'dry-run' : 'done', { cost: ctx.ledger.summary() });
  return results;
}
