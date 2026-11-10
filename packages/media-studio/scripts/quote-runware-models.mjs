#!/usr/bin/env node
// Public, no-key, no-spend Runware model discovery and price quotation.
// Prices are fetched from the official live index and model OpenAPI x-pricing.
// A rate is never guessed: unclear or compute-time pricing returns "manual-quote".
//
// Examples:
//   node quote-runware-models.mjs --capability image-to-video --list
//   node quote-runware-models.mjs --models minimax-h3-max-turbo,prunaai-p-video-2-pro --capability image-to-video --seconds 5 --label 480p
//   node quote-runware-models.mjs --models recraft-v4-1-flash --capability text-to-image --count 3
import { pathToFileURL } from 'node:url';

export const INDEX_URL = 'https://runware.ai/docs/models/index.json';
export const MODEL_SHORTLIST = Object.freeze({
  image: [
    'bfl-flux-3-image-klein', 'alibaba-qwen-image-2-1-turbo',
    'minimax-h3-image', 'minimax-h3-image-highspeed',
    'openai-gpt-image-2-6-sunburst', 'alibaba-qwen-image-3-0',
    'bytedance-seedream-5-5', // coming-soon at 2026-11-10; excluded until index says live
  ],
  video: [
    'minimax-h3-lite', 'minimax-h3-highspeed', 'minimax-h3-max-turbo',
    'google-gemini-omni-flash-1-2', 'klingai-video-4-0-flash',
    'prunaai-p-video-2-pro-replace', 'prunaai-p-video-2-pro',
  ],
  speech: [
    'heygen-voice-1-0-turbo-free', 'heygen-voice-1-0-turbo',
    'heygen-voice-1-0', 'fish-audio-s2-1-pro',
  ],
  music: ['minimax-music-2-6'],
  '3d': ['microsoft-trellis-2', 'meta-sam-3d-objects'],
});
export const ALLOWED_CAPABILITIES = new Set([
  'text-to-image', 'image-to-image', 'text-to-video', 'image-to-video',
  'video-to-video', 'audio-to-video', 'text-to-audio', 'audio-to-audio',
  'text-to-3d', 'image-to-3d', 'edit', 'upscale', 'vectorize',
  'transparency', 'audio',
]);

export function validateSchemaUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.hostname !== 'runware.ai' || url.port ||
      !/^\/docs\/models\/[a-z0-9-]+\/schema\.json$/.test(url.pathname) ||
      url.username || url.password || url.search || url.hash) {
    throw new Error('refusing noncanonical Runware model schema URL');
  }
  return url.href;
}

const numeric = (n) => typeof n === 'number' && Number.isFinite(n) && n >= 0 ? n : null;
const rounded = (x) => Math.round(x * 1e6) / 1e6;

export function quotePricing(pricing, opts = {}) {
  const rates = Array.isArray(pricing?.rates) ? pricing.rates : [];
  const region = String(opts.label || '').trim().toLowerCase();
  const candidates = region ? rates.filter(r => String(r.label || '').toLowerCase() === region) : rates;
  if (candidates.length !== 1) {
    return { status: 'manual-quote', reason: !candidates.length ? 'no matching unit rate' : 'multiple priced configurations; set --label to the exact rate label', rates: rates.map(r => ({ unit: r.unit, label: r.label ?? null, amount: r.amount })) };
  }
  const r = candidates[0];
  const amount = numeric(r.amount);
  if (pricing.currency !== 'USD' || amount === null) return { status: 'manual-quote', reason: 'currency or amount is unavailable' };
  const unit = String(r.unit || '');
  const count = numeric(opts.count) ?? 1;
  let quantity;
  if (unit === 'output') quantity = count;
  else if (unit === 'durationSecond') quantity = numeric(opts.seconds);
  else if (unit === 'character') quantity = numeric(opts.characters);
  else if (/^(utf8byte|utf-8-byte|byte)$/i.test(unit)) quantity = numeric(opts.bytes);
  else return { status: 'manual-quote', reason: 'nonlinear or unfamiliar pricing unit; use the model schema/examples or Playground', unit, label: r.label ?? null };
  if (quantity === null || quantity <= 0) return { status: 'manual-quote', reason: `missing positive request units for ${unit}`, unit, label: r.label ?? null };
  return { status: 'estimated', usd: rounded(amount * quantity), unit, units: quantity, amountPerUnit: amount, label: r.label ?? null, priceBasis: 'Runware published x-pricing; recheck final request and response cost' };
}

export function filterLiveCatalog(index, { capability = '', models = [] } = {}) {
  if (!Array.isArray(index)) throw new Error('catalog must be an array');
  return index.filter(row => row?.status === 'live' &&
    (!capability || row.capabilities?.includes(capability)) &&
    (!models.length || models.includes(row.id) || models.includes(row.air)));
}

export async function discoverAndQuote({
  capability = '', models = [], label = '', seconds = null, count = 1,
  characters = null, bytes = null, maxUsd = null, list = false, fetchJson,
} = {}) {
  if (capability && !ALLOWED_CAPABILITIES.has(capability)) throw new Error(`unknown capability: ${capability}`);
  const index = await fetchJson(INDEX_URL);
  const catalog = filterLiveCatalog(index, { capability, models });
  // Missing, discontinued, and coming-soon entries must be visible, never
  // silently treated as eligible or priced. A model page is not live access.
  const matches = (row, id) => row.id === id || row.air === id;
  const unavailable = models.length ? index.filter(row =>
    models.some(id => matches(row, id)) &&
    (row.status !== 'live' || (capability && !row.capabilities?.includes(capability)))
  ).map(row => ({
    id: row.id, air: row.air ?? null, status: row.status,
    reason: row.status !== 'live' ? 'model not live; no generation or price ranking' : 'model does not support requested capability',
  })) : [];
  const unknownModels = models.filter(id => !index.some(row => matches(row, id)));
  if (list) return { catalog: catalog.map(x => ({ id: x.id, air: x.air, capabilities: x.capabilities, schema: x.schema })),
    unavailable, unknownModels, source: INDEX_URL, paidCalls: 0 };
  if (catalog.length > 20) throw new Error('explicitly choose <=20 models to quote; use --list to inspect the live catalog first');
  const result = [];
  for (const row of catalog) {
    try {
      const schemaUrl = validateSchemaUrl(row.schema);
      const schema = await fetchJson(schemaUrl);
      const info = schema?.info || {};
      if (info['x-air-id'] !== row.air || info['x-status'] !== 'live') throw new Error('schema AIR/status no longer matches catalog');
      const quote = quotePricing(info['x-pricing'], { label, seconds, count, characters, bytes });
      result.push({ id: row.id, air: row.air, capabilities: row.capabilities, schema: schemaUrl, quote });
    } catch (e) { result.push({ id: row.id, air: row.air, quote: { status: 'manual-quote', reason: String(e.message || e) } }); }
  }
  const ranked = result.sort((a, b) => {
    const ap = a.quote.status === 'estimated' ? a.quote.usd : Infinity;
    const bp = b.quote.status === 'estimated' ? b.quote.usd : Infinity;
    return ap - bp || a.id.localeCompare(b.id);
  }).map(row => ({ ...row,
    underBudget: maxUsd === null || row.quote.status !== 'estimated' ? null : row.quote.usd <= Number(maxUsd),
    qualityApproved: false,
    selection: 'quote-only: verify fidelity, supported request options, license, privacy, provider entitlement and user approval before generation',
  }));
  return { results: ranked, unavailable, unknownModels, source: INDEX_URL, paidCalls: 0,
    evaluatedAt: new Date().toISOString(),
    note: 'No quality rank is inferred from pricing; a listed or discounted model can be coming-soon, and quoted configurations are not executable authorizations.' };
}

const args = process.argv.slice(2);
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    const k = args[i];
    if (k === '--list') { options.list = true; continue; }
    if (!['--capability', '--models', '--shortlist', '--label', '--seconds', '--count', '--characters', '--bytes', '--max-usd'].includes(k)) throw new Error(`unknown argument ${k}`);
    const raw = args[++i];
    if (raw === undefined || raw.startsWith('--')) throw new Error(`missing value for ${k}`);
    if (k === '--models') options.models = raw.split(',').map(v => v.trim()).filter(Boolean);
    else if (k === '--shortlist') {
      if (!MODEL_SHORTLIST[raw]) throw new Error(`unknown shortlist ${raw}; use image,video,speech,music,3d`);
      options.models = [...MODEL_SHORTLIST[raw]];
    }
    else if (['--seconds', '--count', '--characters', '--bytes', '--max-usd'].includes(k)) {
      const val = Number(raw);
      if (!Number.isFinite(val) || val < 0) throw new Error(`invalid numeric value for ${k}`);
      options[k.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = val;
    } else options[k.slice(2)] = raw;
  }
  if (!options.list && !options.models?.length) throw new Error('pass --models id,id,... or --shortlist image|video|speech|music|3d to quote (or --list to discover)');
  const fetchJson = async url => {
    if (url !== INDEX_URL) validateSchemaUrl(url);
    const response = await fetch(url, { headers: { accept: 'application/json' }, signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error(`public model metadata HTTP ${response.status}`);
    return response.json();
  };
  try { console.log(JSON.stringify(await discoverAndQuote({ ...options, fetchJson }), null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
