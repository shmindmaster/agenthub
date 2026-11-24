#!/usr/bin/env node
// Estimate a video job's AI spend per quality tier before any paid call.
//   node scripts/estimate-job-cost.mjs --scenes 9 --words 120 --stills 6 --hero 2 [--frames 24] [--tier all|draft|standard|premium] [--voice azure|openai] [--batch] [--json]
//   node scripts/estimate-job-cost.mjs --plan <jobRoot>/story/picture-plan.json --script <locked-script.txt> ...
// Prices come from kit/marketing/lib/prices.mjs (revision printed). Estimates are reservations, not bills: the ledger
// records actual usage. Azure lanes are paid from Azure credit; their USD is shown only where a measured rate exists.
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const P = await import(new URL('file:///' + join(here, '../kit/marketing/lib/prices.mjs').replace(/\\/g, '/')).href);
const args = process.argv.slice(2); const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? (args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : true) : d; };
let scenes = Number(opt('scenes', 0)); let words = Number(opt('words', 0)); let stills = Number(opt('stills', 0)); const hero = Number(opt('hero', 0));
const frames = Number(opt('frames', 24)); const tierArg = String(opt('tier', 'all')); const voice = String(opt('voice', 'azure')); const batch = opt('batch', false) === true;
const plan = opt('plan', null); const script = opt('script', null);
if (plan && existsSync(plan)) { const j = JSON.parse(readFileSync(plan, 'utf8')); const list = j.beats || j.scenes || j.lines || (Array.isArray(j) ? j : []);
  if (!scenes) scenes = list.length; if (!stills) stills = list.filter((b) => /generat|still|illustrat|photo/i.test(JSON.stringify(b))).length; }
if (script && existsSync(script) && !words) words = readFileSync(script, 'utf8').split(/\s+/).filter(Boolean).length;
if (!scenes) { console.error('Give --scenes (or --plan). Optional: --words, --stills, --hero, --frames, --voice azure|openai, --batch.'); process.exit(2); }
if (!words) words = scenes * 18; // about 7 seconds of narration per scene
const STABLE = 6000, DYN = 900, OUT = 700; // tokens per scene for writing calls; the stable prefix is cached after the first call
const text = (model, calls) => P.estimateOpenAiTextUsd(model, (STABLE + DYN) * calls, OUT * calls, { batch, cachedInTokens: STABLE * Math.max(0, calls - 1) });
const TIERS = {
  draft: { write: 'gpt-6-luna', edit: 'gpt-6.1-terra', review: 'gpt-6.1-terra', reviewPasses: 1, still: 'low', heroQ: 'medium', heroModel: 'gpt-image-2.6-flare' },
  standard: { write: 'gpt-6.1-sol', edit: 'gpt-6.1-terra', review: 'gpt-6.1-terra', reviewPasses: 1, still: 'medium', heroQ: 'high', heroModel: 'gpt-image-2.6-sunburst' },
  premium: { write: 'gpt-6-astra', edit: 'gpt-6.1-sol', review: 'gpt-6.1-terra', reviewPasses: 2, still: 'high', heroQ: 'xhigh', heroModel: 'gpt-image-2.6-sunburst' },
};
function estimate(name) { const t = TIERS[name]; const rows = [];
  rows.push(['script and storyboard', t.write, text(t.write, scenes)]);
  rows.push(['copy edit pass', t.edit, text(t.edit, scenes)]);
  if (stills) rows.push([`${stills} stills (${t.still})`, 'gpt-image-2.6-flare', stills * P.estimateOpenAiImageUsd(t.still, { batch })]);
  if (hero) rows.push([`${hero} hero images (${t.heroQ})`, t.heroModel, hero * P.estimateOpenAiImageUsd(t.heroQ, { batch })]);
  if (voice === 'openai') rows.push([`narration ${words} words`, 'gpt-realtime-2.1-mini (marin/cedar)', P.estimateOpenAiRealtimeSpeechUsd(words.toString().length ? 'x '.repeat(words) : '', 'gpt-realtime-2.1-mini')]);
  else rows.push([`narration ${words} words`, 'Azure DragonHD (governed default)', null]);
  rows.push(['caption and alignment check', 'gpt-transcribe', P.estimateOpenAiTranscribeUsd(Math.ceil(words / 150 * 60))]);
  rows.push([`frame review x${t.reviewPasses}`, t.review, t.reviewPasses * P.estimateVisionUsd(t.review, frames)]);
  rows.push(['render', 'Remotion on Daytona (compute, not AI spend)', 0]);
  const usd = rows.reduce((s, r) => s + (r[2] || 0), 0); return { tier: name, rows, usd }; }
const tiers = tierArg === 'all' ? Object.keys(TIERS) : [tierArg]; const out = tiers.map(estimate);
if (opt('json', false) === true) { console.log(JSON.stringify({ pricesRevision: P.OPENAI_PRICES_REVISION, inputs: { scenes, words, stills, hero, frames, voice, batch }, tiers: out }, null, 2)); process.exit(0); }
console.log(`Job: ${scenes} scenes, ${words} narration words, ${stills} stills, ${hero} hero images, ${frames} review frames, voice ${voice}${batch ? ', Batch pricing' : ''}. Prices rev ${P.OPENAI_PRICES_REVISION}; estimates, not bills.`);
for (const t of out) { console.log(`\n${t.tier.toUpperCase()}  about $${t.usd.toFixed(2)}`); for (const [what, model, usd] of t.rows) console.log(`  ${what.padEnd(30)} ${model.padEnd(38)} ${usd === null ? 'Azure credit' : '$' + usd.toFixed(3)}`); }