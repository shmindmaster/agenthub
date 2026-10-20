// Stage 1: lint. Fail closed before any paid provider is contacted.
import { join } from 'node:path';
import { recordStage } from '../context.mjs';
import { lintSpec, normalizeCuts, estimateCutSeconds } from '../lint.mjs';
import { estimateImageUsd, estimateMusicCredits, estimateSfxCredits, estimateTtsCredits } from '../prices.mjs';
import { writeJson } from '../util.mjs';

/** Planned spend of a full run, so the budget fails before voice rather than during assets. */
export function planCost(spec, brand) {
  const cuts = normalizeCuts(spec);
  let credits = 0;
  let usd = 0;
  const lines = new Set();
  for (const cut of cuts) {
    for (const b of cut.beats) {
      if (b.narration) {
        const key = `${b.narration}`;
        if (!lines.has(key)) {
          lines.add(key);
          if (spec.voice.provider === 'elevenlabs') credits += estimateTtsCredits(b.narration, spec.voice.model);
          else if (spec.voice.provider === 'openai') usd += 0.02;
          usd += 0.002; // whisper-1 timing for the line
        }
      }
      if (b.broll?.provider === 'openai-image') usd += estimateImageUsd(brand.images?.model || 'gpt-image-2', b.broll.quality || brand.images?.quality || 'medium');
    }
  }
  const sfxPrompts = new Set(cuts.flatMap((c) => c.beats.flatMap((b) => (b.sfx || []).map((s) => `${s.prompt}|${s.durationSeconds || 1}`))));
  credits += sfxPrompts.size * estimateSfxCredits(1);
  if (spec.music?.provider === 'elevenlabs') credits += estimateMusicCredits(Math.ceil(Math.max(...cuts.map(estimateCutSeconds)) + 2) * 1000);
  usd += cuts.flatMap((c) => c.ratios).length * 0.35; // vision QA per ratio (padded)
  return { elevenlabsCredits: credits, openaiUsd: Number(usd.toFixed(2)) };
}

export async function lintStage(ctx) {
  const result = lintSpec(ctx.spec, ctx.brand, { adSchema: ctx.adSchema, brandSchema: ctx.brandSchema, specDir: ctx.specDir });
  const plan = result.ok ? planCost(ctx.spec, ctx.brand) : null;
  const budget = { ...(ctx.brand.budgets?.perRun || {}), ...(ctx.spec.budget || {}) };
  const errors = [...result.errors];
  if (plan) {
    if (budget.elevenlabsCredits !== undefined && plan.elevenlabsCredits > budget.elevenlabsCredits) errors.push({ code: 'budget', message: `planned ElevenLabs spend ${plan.elevenlabsCredits} credits exceeds the per-run cap ${budget.elevenlabsCredits}` });
    if (budget.openaiUsd !== undefined && plan.openaiUsd > budget.openaiUsd) errors.push({ code: 'budget', message: `planned OpenAI spend $${plan.openaiUsd} exceeds the per-run cap $${budget.openaiUsd}` });
  }
  const report = { generator: 'media-studio/mvg-lint', ok: errors.length === 0, errors, warnings: result.warnings, estimates: result.estimates, plannedCost: plan, specSha256: ctx.specSha, brandSha256: ctx.brandSha };
  writeJson(join(ctx.jobDir, 'lint', 'report.json'), report);
  recordStage(ctx, 'lint', report.ok ? 'pass' : 'fail', { errors: errors.length, warnings: result.warnings.length });
  for (const e of errors) ctx.log(`LINT ERROR [${e.code}] ${e.where ? `${e.where}: ` : ''}${e.message}`);
  for (const w of result.warnings) ctx.log(`lint warning [${w.code}] ${w.where ? `${w.where}: ` : ''}${w.message}`);
  if (!report.ok) throw new Error(`lint failed with ${errors.length} error(s); see ${join(ctx.jobDir, 'lint', 'report.json')}`);
  return report;
}
