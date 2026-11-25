// Stage 1: lint. Fail closed before any paid provider is contacted.
import { join } from 'node:path';
import { recordStage } from '../context.mjs';
import { lintSpec, normalizeCuts, estimateCutSeconds } from '../lint.mjs';
import { musicLengthMs } from './assets.mjs';
import { estimateImageUsd, estimateMusicCredits, estimateSfxCredits, estimateTtsCredits } from '../prices.mjs';
import { writeJson } from '../util.mjs';

/** Planned spend of a full run, so the budget fails before voice rather than during assets. */
export function planCost(spec, brand, flags = {}) {
  const cuts = normalizeCuts(spec);
  let credits = 0;
  let usd = 0;
  const lines = new Set();
  const unknown = []; // spend this plan cannot price: reported as unknown, never as $0
  const unknownProviders = [];
  const paidElsewhere = []; // work that is imported: priced outside this run, nothing is charged here
  const voiceProvider = spec.voice.provider;
  if (voiceProvider === 'import') paidElsewhere.push(`narration imported from ${spec.voice.source || 'an import manifest'} (${spec.voice.manifest || 'no manifest'}): produced and paid outside this run, 0 charged here`);
  else if (!['elevenlabs', 'openai'].includes(voiceProvider)) { unknown.push(`voice provider ${voiceProvider} has no price table, so its narration cost is unknown`); unknownProviders.push(voiceProvider); }
  for (const cut of cuts) {
    for (const b of cut.beats) {
      if (b.narration) {
        const key = `${b.narration}`;
        if (!lines.has(key)) {
          lines.add(key);
          if (spec.voice.provider === 'elevenlabs') credits += estimateTtsCredits(b.narration, spec.voice.model);
          else if (spec.voice.provider === 'openai') usd += 0.02;
          if (flags.whisperTiming && (flags.hostedOnly || brand.timing?.provider !== 'local-whisper')) usd += 0.002;
        }
      }
      if (b.broll?.provider === 'import') paidElsewhere.push(`b-roll ${b.id}: still imported (${b.broll.source || 'unknown source'}), produced and paid outside this run, 0 charged here`);
      if (b.broll?.provider === 'openai-image') usd += estimateImageUsd(brand.images?.model || 'gpt-image-2.6-flare', b.broll.quality || brand.images?.quality || 'medium');
    }
  }
  const sfxPrompts = new Set(cuts.flatMap((c) => c.beats.flatMap((b) => (b.sfx || []).map((s) => `${s.prompt}|${s.durationSeconds || 1}`))));
  credits += sfxPrompts.size * estimateSfxCredits(1);
  if (spec.music?.provider === 'elevenlabs') credits += estimateMusicCredits(musicLengthMs(spec.music, Math.max(...cuts.map((c) => estimateCutSeconds(c, spec))), { measured: false }));
  if (!flags.noVision && (flags.visionProvider || brand.vision?.provider || 'local') === 'openai') usd += cuts.flatMap((c) => c.ratios).length * 0.35; // explicit paid vision, padded
  return { elevenlabsCredits: credits, openaiUsd: Number(usd.toFixed(2)), costKnown: unknown.length === 0, unknown, unknownProviders, paidElsewhere };
}

/** A plan with a provider whose cost is unknown stops the run, except the injected local hook (Local AI is off, so it refuses later anyway). */
export function costErrors(plan) {
  return (plan?.unknownProviders || []).filter((p) => p !== 'local').map((p) => ({ code: 'cost-unknown', message: `the cost of provider "${p}" is unknown, so the plan cannot be checked against a budget` }));
}

export async function lintStage(ctx) {
  const result = lintSpec(ctx.spec, ctx.brand, { adSchema: ctx.adSchema, brandSchema: ctx.brandSchema, specDir: ctx.specDir });
  const plan = result.ok ? planCost(ctx.spec, ctx.brand, ctx.flags) : null;
  const budget = { ...(ctx.brand.budgets?.perRun || {}), ...(ctx.spec.budget || {}) };
  const errors = [...result.errors];
  if (plan) {
    errors.push(...costErrors(plan));
    if (budget.elevenlabsCredits !== undefined && plan.elevenlabsCredits > budget.elevenlabsCredits) errors.push({ code: 'budget', message: `planned ElevenLabs spend ${plan.elevenlabsCredits} credits exceeds the per-run cap ${budget.elevenlabsCredits}` });
    if (budget.openaiUsd !== undefined && plan.openaiUsd > budget.openaiUsd) errors.push({ code: 'budget', message: `planned OpenAI spend $${plan.openaiUsd} exceeds the per-run cap $${budget.openaiUsd}` });
  }
  const report = { generator: 'media-studio/mvg-lint', ok: errors.length === 0, errors, warnings: [...result.warnings, ...(plan?.unknown || []).map((message) => ({ code: 'cost-unknown', message, where: 'voice' }))], estimates: result.estimates, plannedCost: plan, specSha256: ctx.specSha, brandSha256: ctx.brandSha };
  writeJson(join(ctx.jobDir, 'lint', 'report.json'), report);
  recordStage(ctx, 'lint', report.ok ? 'pass' : 'fail', { errors: errors.length, warnings: result.warnings.length });
  for (const e of errors) ctx.log(`LINT ERROR [${e.code}] ${e.where ? `${e.where}: ` : ''}${e.message}`);
  for (const u of plan?.unknown || []) ctx.log(`lint warning [cost-unknown] ${u}`);
  for (const w of result.warnings) ctx.log(`lint warning [${w.code}] ${w.where ? `${w.where}: ` : ''}${w.message}`);
  if (!report.ok) throw new Error(`lint failed with ${errors.length} error(s); see ${join(ctx.jobDir, 'lint', 'report.json')}`);
  return report;
}
