#!/usr/bin/env node
// mvg: marketing video generator. One ad spec in, gated 16:9 / 4:5 / 9:16 ads out.
//
//   node mvg.mjs <spec.json> [--stage lint|voice|timing|assets|capture|compose|qa|deliver|all] [--dry-run]
//
// Stages run in order (lint -> voice -> timing -> assets -> capture -> compose -> qa -> deliver), each cached by the
// hash of its inputs so reruns skip unchanged work. `--stage X` runs the stages up to and including X that are not
// already satisfied; `--only X` runs just X. Flags:
//   --dry-run         plan only: lint, planned spend, no provider call, no render, no delivery
//   --prepare-only    compose writes props / compose map / mix plan but does not render or encode
//   --hosted-only     hosted providers only: implies --prepare-only (no render/encode), no recording, no local gates; deliver is skipped
//   --local-gates     qa also runs local whisper + the sync and Local-AI listen gates (GPU)
//   --allow-capture   permit ui.record clips to be (re)recorded through record-job.mjs
//   --no-vision       skip OpenAI vision QA (it stays `pending`, so deliver refuses)
//   --force           ignore stage caches
//   --workspace DIR   media workspace root (default: the parent of the spec folder)
// Exit codes: 0 ok, 1 stage failed (lint/budget/gate), 2 usage.
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { loadContext } from './lib/context.mjs';
import { lintStage } from './lib/stages/lint.mjs';
import { voiceStage } from './lib/stages/voice.mjs';
import { timingStage } from './lib/stages/timing.mjs';
import { assetsStage } from './lib/stages/assets.mjs';
import { captureStage } from './lib/stages/capture.mjs';
import { composeStage } from './lib/stages/compose.mjs';
import { qaStage } from './lib/stages/qa.mjs';
import { deliverStage } from './lib/stages/deliver.mjs';

export const STAGES = [
  ['lint', lintStage], ['voice', voiceStage], ['timing', timingStage], ['assets', assetsStage],
  ['capture', captureStage], ['compose', composeStage], ['qa', qaStage], ['deliver', deliverStage],
];

export function parseArgs(argv) {
  const flags = {};
  const pos = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) { pos.push(a); continue; }
    const name = a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (['stage', 'only', 'workspace', 'kit'].includes(name)) flags[name] = argv[++i];
    else flags[name] = true;
  }
  return { specPath: pos[0], flags };
}

export async function runPipeline(ctx) {
  const names = STAGES.map(([n]) => n);
  const last = ctx.flags.only || ctx.flags.stage || 'all';
  if (last !== 'all' && !names.includes(last)) throw new Error(`unknown stage ${last} (stages: ${names.join(', ')})`);
  const selected = ctx.flags.only ? [ctx.flags.only] : names.slice(0, last === 'all' ? names.length : names.indexOf(last) + 1);
  const results = {};
  for (const [name, fn] of STAGES) {
    if (!selected.includes(name)) continue;
    if (ctx.flags.dryRun && ['timing', 'compose', 'qa', 'deliver'].includes(name)) { ctx.log(`${name}: skipped in --dry-run (needs generated audio)`); continue; }
    if (ctx.flags.hostedOnly && name === 'deliver') { ctx.log('deliver: skipped (--hosted-only)'); continue; }
    ctx.log(`stage ${name}`);
    results[name] = await fn(ctx);
  }
  return results;
}

async function main() {
  const { specPath, flags } = parseArgs(process.argv.slice(2));
  if (!specPath) { console.error('usage: node mvg.mjs <spec.json> [--stage lint|voice|timing|assets|capture|compose|qa|deliver|all] [--dry-run] [--prepare-only] [--hosted-only] [--local-gates] [--allow-capture] [--no-vision] [--force] [--workspace DIR]'); process.exit(2); }
  if (flags.hostedOnly) { flags.prepareOnly = true; flags.allowCapture = false; flags.localGates = false; }
  const ctx = loadContext({ specPath, flags });
  try {
    await runPipeline(ctx);
    const s = ctx.ledger.summary();
    console.log(JSON.stringify({ ok: true, jobDir: ctx.jobDir, cost: { elevenlabsCredits: s.elevenlabsCredits, openaiUsd: s.openaiUsd } }));
  } catch (e) {
    console.error(`[mvg] ${e.name === 'BudgetError' ? 'BUDGET STOP' : 'FAILED'}: ${e.message}`);
    const s = ctx.ledger.summary();
    console.log(JSON.stringify({ ok: false, error: e.message, jobDir: ctx.jobDir, cost: { elevenlabsCredits: s.elevenlabsCredits, openaiUsd: s.openaiUsd } }));
    process.exit(1);
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) await main();
