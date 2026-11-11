import test from 'node:test';
import assert from 'node:assert/strict';
import {
  INDEX_URL, validateSchemaUrl, quotePricing, filterLiveCatalog,
  discoverAndQuote, MODEL_SHORTLIST,
} from '../scripts/quote-runware-models.mjs';

const rates = {
  currency: 'USD',
  rates: [
    { amount: 0.025, unit: 'durationSecond', label: '480p' },
    { amount: 0.04, unit: 'durationSecond', label: '768p' },
  ],
};
const catalog = [
  { id: 'minimax-h3-max-turbo', air: 'minimax:h3@max-turbo', name: 'Turbo', status: 'live', capabilities: ['text-to-video', 'image-to-video'], schema: 'https://runware.ai/docs/models/minimax-h3-max-turbo/schema.json' },
  { id: 'recraft-v4-1-flash', air: 'recraft:v4.1@flash', status: 'live', capabilities: ['text-to-image'], schema: 'https://runware.ai/docs/models/recraft-v4-1-flash/schema.json' },
  { id: 'retired', air: 'v:retired@1', status: 'deprecated', capabilities: ['text-to-video'], schema: 'https://runware.ai/docs/models/retired/schema.json' },
];
const schemas = {
  'https://runware.ai/docs/models/minimax-h3-max-turbo/schema.json': { info: { 'x-air-id': 'minimax:h3@max-turbo', 'x-status': 'live', 'x-pricing': rates } },
  'https://runware.ai/docs/models/recraft-v4-1-flash/schema.json': { info: { 'x-air-id': 'recraft:v4.1@flash', 'x-status': 'live', 'x-pricing': { currency: 'USD', rates: [{ amount: 0.007, unit: 'output' }] } } },
};
const fetchJson = async url => url === INDEX_URL ? catalog : schemas[url];

test('official price for a 5s 480p clip is quoted, not a guessed flat charge', () => {
  const q = quotePricing(rates, { seconds: 5, label: '480p' });
  assert.equal(q.status, 'estimated');
  assert.equal(q.usd, 0.125);
});
test('multiple published configurations cannot be treated as a single low rate', () => {
  assert.equal(quotePricing(rates, { seconds: 5 }).status, 'manual-quote');
});
test('per-output images apply requested count', () => {
  assert.equal(quotePricing({ currency: 'USD', rates: [{ amount: 0.007, unit: 'output' }] }, { count: 3 }).usd, 0.021);
});
test('text bytes and characters are billed using the model-specific unit', () => {
  assert.equal(quotePricing({ currency: 'USD', rates: [{ amount: 0.000015, unit: 'byte' }] }, { bytes: 1000 }).usd, 0.015);
  assert.equal(quotePricing({ currency: 'USD', rates: [{ amount: 0.00004, unit: 'character' }] }, { characters: 500 }).usd, 0.02);
});
test('unfamiliar or GPU-compute charges never become $0', () => {
  const q = quotePricing({ currency: 'USD', examples: [{ price: 0.20 }] }, { seconds: 5 });
  assert.equal(q.status, 'manual-quote');
});
test('schema URL is confined to official public model schemas', () => {
  assert.equal(validateSchemaUrl(catalog[0].schema), catalog[0].schema);
  for (const bad of ['http://runware.ai/docs/models/foo/schema.json', 'https://evil.test/docs/models/foo/schema.json', 'https://runware.ai.evil.test/docs/models/foo/schema.json', 'https://runware.ai/../../other', 'https://runware.ai/docs/models/foo/schema.json?token=abc']) {
    assert.throws(() => validateSchemaUrl(bad), /noncanonical/);
  }
});
test('live and modality-compatible selection excludes deprecated models', () => {
  assert.deepEqual(filterLiveCatalog(catalog, { capability: 'text-to-video' }).map(m => m.id), ['minimax-h3-max-turbo']);
});
test('no-spend discovery and quote, with source, status and explicit quality not approved', async () => {
  const r = await discoverAndQuote({ capability: 'image-to-video', models: ['minimax-h3-max-turbo'], label: '480p', seconds: 5, maxUsd: 0.20, fetchJson });
  assert.equal(r.paidCalls, 0);
  assert.equal(r.results[0].quote.usd, 0.125);
  assert.equal(r.results[0].underBudget, true);
  assert.equal(r.results[0].qualityApproved, false);
  assert.match(r.results[0].selection, /approval before generation/);
});
test('catalogue discovery returns models without fetching price schemas', async () => {
  const seen = [];
  const r = await discoverAndQuote({ capability: 'text-to-image', list: true, fetchJson: async url => { seen.push(url); return fetchJson(url); } });
  assert.deepEqual(seen, [INDEX_URL]);
  assert.deepEqual(r.catalog.map(m => m.id), ['recraft-v4-1-flash']);
});
test('quote rejects AIR mismatch and never presents it as an approved model', async () => {
  const r = await discoverAndQuote({
    models: ['recraft-v4-1-flash'],
    fetchJson: async url => url === INDEX_URL ? catalog : { info: { 'x-air-id': 'unknown:fake', 'x-status': 'live' } },
  });
  assert.equal(r.results[0].quote.status, 'manual-quote');
});
test('shortlists keep names as discoverable candidates; they do not imply entitlement', () => {
  assert.ok(MODEL_SHORTLIST.video.includes('minimax-h3-max-turbo'));
});

test('coming-soon Seedream 5.5 stays visible as unavailable and is never quoted or routed as live', async () => {
  const coming = { id: 'bytedance-seedream-5-5', air: 'bytedance:seedream@5.5', status: 'coming-soon',
    capabilities: ['text-to-image', 'image-to-image'], schema: 'https://runware.ai/docs/models/bytedance-seedream-5-5/schema.json' };
  const urls = [];
  const r = await discoverAndQuote({
    capability: 'text-to-image', models: ['bytedance-seedream-5-5'],
    fetchJson: async url => { urls.push(url); if (url !== INDEX_URL) throw Error('should never fetch or quote unavailable schema'); return [...catalog, coming]; },
  });
  assert.deepEqual(urls, [INDEX_URL]);
  assert.deepEqual(r.results, []);
  assert.equal(r.unavailable[0].status, 'coming-soon');
  assert.match(r.unavailable[0].reason, /not live/);
});

test('a live model without a requested modality is clearly excluded', async () => {
  const r = await discoverAndQuote({
    capability: 'image-to-video', models: ['recraft-v4-1-flash'],
    fetchJson,
  });
  assert.deepEqual(r.results, []);
  assert.equal(r.unavailable[0].status, 'live');
  assert.match(r.unavailable[0].reason, /does not support/);
});

test('unknown model ID is reported rather than silently yielding no choices', async () => {
  const r = await discoverAndQuote({ models: ['imagined-model-9'], fetchJson });
  assert.deepEqual(r.unknownModels, ['imagined-model-9']);
  assert.deepEqual(r.results, []);
});

test('specialist modes remain discoverable without treating animations as videoInfererence', () => {
  assert.ok(MODEL_SHORTLIST.image.includes('openai-gpt-image-2-6-sunburst'));
  assert.ok(MODEL_SHORTLIST.image.includes('bytedance-seedream-5-5'));
  assert.ok(MODEL_SHORTLIST.video.includes('minimax-h3-lite'));
  assert.ok(MODEL_SHORTLIST.video.includes('google-gemini-omni-flash-1-2'));
  assert.ok(MODEL_SHORTLIST.speech.includes('heygen-voice-1-0-turbo-free'));
});

