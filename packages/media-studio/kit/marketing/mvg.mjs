#!/usr/bin/env node
// mvg: marketing video generator. One ad spec in, gated 16:9 / 4:5 / 9:16 ads out.
//
//   node mvg.mjs <spec.json> --stage lint|voice|timing|assets|capture|compose|qa|deliver [--dry-run]
//
// Stages run in order (lint -> voice -> timing -> assets -> capture -> compose -> qa -> deliver), each cached by the
// hash of its inputs so reruns skip unchanged work. Compose, QA and deliver are explicit isolated steps;
// preparation stages run their prerequisites. `--only X` also runs just X. Flags:
//   --candidate-id ID new exclusive compose directory; QA/delivery select that exact candidate
//   --candidate FILE --candidate-sha256 SHA --compose-dir DIR --ratio R --qa-dir DIR  gate existing evidence
//   --no-line-chips / --no-captions  disable the burned caption layer (sidecar SRT retained)
//   --vision-provider local|openai  local by default; openai is an explicit paid fallback
//   --dry-run         plan only: lint, planned spend, no provider call, no render, no delivery
//   --prepare-only    compose writes props / compose map / mix plan but does not render or encode
//   --hosted-only     hosted providers only: implies --prepare-only (no render/encode), no recording, no local gates; deliver is skipped
//   --local-gates     forced word alignment, independent Whisper transcript and Local-AI listen (GPU)
//   --allow-capture   permit ui.record clips to be (re)recorded through record-job.mjs
//   --no-vision       skip vision QA (it stays `pending`, so deliver refuses)
//   --force           ignore stage caches
//   --workspace DIR   media workspace root (default: the parent of the spec folder)
// Exit codes: 0 ok, 1 stage failed (lint/budget/gate), 2 usage.
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadContext } from './lib/context.mjs';
import { lintStage } from './lib/stages/lint.mjs';
import { voiceStage } from './lib/stages/voice.mjs';
import { timingStage } from './lib/stages/timing.mjs';
import { assetsStage } from './lib/stages/assets.mjs';
import { captureStage } from './lib/stages/capture.mjs';
import { composeStage } from './lib/stages/compose.mjs';
import { qaStage } from './lib/stages/qa.mjs';
import { deliverStage } from './lib/stages/deliver.mjs';

// The deployed kit is reached through a link (%LOCALAPPDATA%\AgentHub\media-studio -> D:\Local-AI), so compare real paths.
function isMain() {
  try { return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; }
}

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
    if (['stage', 'only', 'workspace', 'kit', 'candidateId', 'candidate', 'candidateSha256', 'composeDir', 'qaDir', 'ratio', 'visionProvider'].includes(name)) {
      if (!argv[i + 1] || argv[i + 1].startsWith('--')) throw new Error(`--${a.slice(2)} needs a value`);
      flags[name] = argv[++i];
    }
    else flags[name] = true;
  }
  return { specPath: pos[0], flags };
}

export function selectedStages(flags) {
  const names = STAGES.map(([n]) => n);
  const last = flags.only || flags.stage || (flags.dryRun ? 'capture' : null);
  if (!last || last === 'all') throw new Error('select an explicit --stage; compose, qa and deliver are separate steps');
  if (last !== 'all' && !names.includes(last)) throw new Error(`unknown stage ${last} (stages: ${names.join(', ')})`);
  if (flags.dryRun && (['compose', 'qa', 'deliver'].includes(last) || (flags.only && last === 'timing'))) throw new Error('isolated encoded stages cannot use --dry-run; use --stage capture --dry-run for lint and planned spend');
  return flags.only || ['compose', 'qa', 'deliver'].includes(last) ? [last] : names.slice(0, names.indexOf(last) + 1);
}

export async function runPipeline(ctx, stages = STAGES) {
  const selected = selectedStages(ctx.flags);
  const results = {};
  for (const [name, fn] of stages) {
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
    const results = await runPipeline(ctx);
    if (results.qa && Object.values(results.qa).some((r) => !r.ok)) throw new Error('QA has failing or pending gates; see candidate gates.json');
    const s = ctx.ledger.summary();
    console.log(JSON.stringify({ ok: true, jobDir: ctx.jobDir, cost: { elevenlabsCredits: s.elevenlabsCredits, openaiUsd: s.openaiUsd } }));
  } catch (e) {
    console.error(`[mvg] ${e.name === 'BudgetError' ? 'BUDGET STOP' : 'FAILED'}: ${e.message}`);
    const s = ctx.ledger.summary();
    console.log(JSON.stringify({ ok: false, error: e.message, jobDir: ctx.jobDir, cost: { elevenlabsCredits: s.elevenlabsCredits, openaiUsd: s.openaiUsd } }));
    process.exit(1);
  }
}

if (isMain()) await main();
