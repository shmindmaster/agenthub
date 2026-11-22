// Stage 2: voice. One file per narrated beat; ElevenLabs (governed ledger, request stitching), OpenAI
// OpenAI speech (instructions) or an injected local voice (Local AI is off: the default refuses). Cached by
// (text, voice, model, settings, neighbors), so an unchanged line never costs twice. A beat's `voiceTake` (1, 2, …) asks
// for a fresh take of that one line (a new key and ledger revision) after a listen or review rejects the delivery.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { recordStage } from '../context.mjs';
import { checkStage, stageKey, writeStage } from '../cache.mjs';
import { normalizeCuts } from '../lint.mjs';
import { estimateTtsCredits, realtimeUsdFromUsage } from '../prices.mjs';
import { fileSha, hashOf, localAiOff, readJson, writeJson } from '../util.mjs';

export function lineKey(spec, text, prev, next, take = 0) {
  const v = spec.voice;
  return hashOf({
    ...(take ? { take } : {}),
    provider: v.provider, voiceId: v.voiceId, model: v.model, settings: v.settings || null, instructions: v.instructions || null,
    dictionaries: v.pronunciationDictionaries || null, stitching: !!v.stitching, text, prev: v.stitching ? prev || null : null, next: v.stitching ? next || null : null,
  });
}

export const lineExt = (provider) => (provider === 'local' || provider === 'openai' ? 'wav' : 'mp3');

async function renderLine(ctx, { text, prev, next, out, key, take }, openaiPlan) {
  const v = ctx.spec.voice;
  const P = ctx.providers;
  if (v.provider === 'elevenlabs') {
    const credits = estimateTtsCredits(text, v.model);
    ctx.ledger.check('elevenlabs', credits, `voice line "${text.slice(0, 40)}"`);
    const eleven = P.elevenlabs || (await import('../providers/elevenlabs.mjs'));
    const cli = P.elevenCli || eleven.resolveCli(ctx.brand);
    const res = await eleven.speech(cli, {
      text, output: out, voiceId: v.voiceId, model: v.model, settings: v.settings, maxCredits: credits,
      workspace: ctx.workspaceId, revision: take ? `mvg-voice-v1-take${take}` : 'mvg-voice-v1', previousText: v.stitching ? prev : undefined, nextText: v.stitching ? next : undefined,
      dictionaries: v.pronunciationDictionaries, run: P.runCli,
    });
    const reused = !!res.receipt?.reused;
    ctx.ledger.charge({ stage: 'voice', provider: 'elevenlabs', service: 'tts', units: res.receipt?.actual_credits ?? credits, estimated: res.receipt?.actual_credits == null, cached: reused, ref: key.slice(0, 12), note: `request ${res.receipt?.request_id || '?'}` });
    return { receipt: res.receipt };
  }
  if (v.provider === 'openai') {
    const reservation = openaiPlan?.byLine.get(key);
    if (!reservation) throw new Error('OpenAI narration inputs changed after preflight. Run voice again.');
    const usd = reservation.usdMicros / 1e6;
    ctx.ledger.check('openai', usd, 'OpenAI speech');
    const openai = P.openai || (await import('../providers/openai.mjs'));
    const payment = openaiPlan.wallet.reserve(out, key, reservation.usdMicros);
    let res;
    try {
      res = await openai.speech({ text, voice: v.voiceId, instructions: v.instructions, model: openaiPlan.model,
        credential: openaiPlan.key, maxOutputTokens: reservation.maxOutputTokens });
    } catch (error) {
      if (error.definitelyUnsubmitted === true) payment.cancelUnsubmitted();
      throw error;
    }
    mkdirSync(join(out, '..'), { recursive: true });
    writeFileSync(out, res.bytes);
    // Charge what the response's usage says it cost; fall back to the estimate only when usage is missing, and say so.
    const billed = realtimeUsdFromUsage(openaiPlan.model, res.usage, openaiPlan.rate);
    payment.settle(Math.ceil((billed ?? 0) * 1e6));
    ctx.ledger.charge({ stage: 'voice', provider: 'openai', service: 'speech', units: billed ?? usd, estimated: billed == null, ref: key.slice(0, 12), note: res.usage ? `usage ${JSON.stringify(res.usage.output_token_details || {})}` : 'no usage returned' });
    return { receipt: { provider: 'openai', model: openaiPlan.model, voice: v.voiceId, aiGenerated: true,
      usage: res.usage ?? null, billedUsd: billed, rateEvidence: openaiPlan.rateEvidence,
      fundingObservedAt: openaiPlan.funding.observedAt, reservedUsd: usd } };
  }
  if (v.provider === 'local') {
    const local = P.localVoice || localAiOff('local voice');
    await local({ speaker: v.voiceId, instruction: v.instructions || '', text, out });
    return { receipt: { provider: 'local', speaker: v.voiceId } };
  }
  throw new Error(`unsupported voice provider ${v.provider}`);
}

function planCut(ctx, cut) {
  const narrated = cut.beats.filter(b => b.narration);
  return narrated.map((b, i) => ({
      beat: b.id, text: b.narration, prev: narrated[i - 1]?.narration, next: narrated[i + 1]?.narration, take: Number(b.voiceTake || 0),
    })).map(l => ({ ...l, key: lineKey(ctx.spec, l.text, l.prev, l.next, l.take) }));
}

async function planOpenAI(ctx, plans, linePath) {
  if (ctx.flags.dryRun || ctx.spec.voice.provider !== 'openai') return null;
  const pending = new Map(plans.flatMap(({ plan }) => plan).filter(l => !existsSync(linePath(l.key))).map(l => [l.key, l.text]));
  if (!pending.size) return null;
  const { narrationEntity: entity, narrationFunding } = ctx.flags;
  if (!entity || !narrationFunding) throw new Error('New OpenAI narration requires --narration-entity and --narration-funding with current dashboard evidence');
  const source = [new URL('../../../../scripts/narration-preflight.mjs', import.meta.url),
    new URL('../../../../_shared/tools/narration-preflight.mjs', import.meta.url)].find(url => existsSync(url));
  if (!source) throw new Error('Media Studio narration preflight missing. Sync the runtime kit before generating voice.');
  const { preflightMarketingOpenAI } = await import(source.href);
  const voice = ctx.spec.voice;
  const quote = await preflightMarketingOpenAI({ entity, model: voice.model, voice: voice.voiceId, lines: [...pending.values()],
    instructions: voice.instructions, snapshot: readJson(narrationFunding) }, { ...ctx.providers.narrationPreflight, recoverInterrupted: true });
  ctx.ledger.check('openai', quote.totalMicros / 1e6, 'planned OpenAI narration');
  return { ...quote, byLine: new Map([...pending.keys()].map((key, i) => [key, quote.reservations[i]])) };
}

export async function voiceStage(ctx) {
  const results = {};
  const ext = lineExt(ctx.spec.voice.provider);
  const lineFile = key => join('voice', 'lines', `${key.slice(0, 16)}.${ext}`);
  const plans = normalizeCuts(ctx.spec).map(cut => ({ cut, plan: planCut(ctx, cut) }));
  const openaiPlan = await planOpenAI(ctx, plans, key => join(ctx.jobDir, lineFile(key)));
  for (const { cut, plan } of plans) {
    const stageK = stageKey('voice', { lines: plan.map((l) => l.key) });
    const cached = checkStage(ctx.jobDir, 'voice', cut.id, stageK);
    if (cached.hit && !ctx.flags.force) { ctx.log(`voice/${cut.id}: cached`); results[cut.id] = cached.manifest; continue; }
    const lines = [];
    for (const l of plan) {
      const rel = lineFile(l.key);
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
        receipt = (await renderLine(ctx, { ...l, out }, openaiPlan)).receipt;
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
