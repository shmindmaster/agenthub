import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { executeAssembly, makeBatches, parseRate, preflight } from '../scripts/narration-preflight.mjs';

const now = Date.parse('2026-11-22T18:30:00Z');
const env = { ASSEMBLYAI_API_KEY: 'fixture-key', OPENAI_API_KEY: 'openai-fixture', DEEPGRAM_API_KEY: 'dg-fixture' };
const hash = value => createHash('sha256').update(value).digest('hex');
const auth = (quote, maxUsd = 1) => ({ quoteSha256: hash(JSON.stringify(quote)), entity: 'personal', maxUsd, ownerApproval: 'fixture approval' });
const snapshot = (key, availableUsd = 20) => ({ entity: 'personal', source: 'dashboard', availableUsd,
  observedAt: new Date(now).toISOString(), credentialSha256: hash(key) });
const snapshots = { assemblyai: snapshot(env.ASSEMBLYAI_API_KEY), openai: snapshot(env.OPENAI_API_KEY), deepgram: snapshot(env.DEEPGRAM_API_KEY) };
const stock = { source: 'assemblyai', visibility: 'public', status: 'active', language: 'english', ready_models: ['assemblyai-tts-1'] };
const script = { entity: 'personal', longForm: true, turns: [{ text: 'The answer opens here.' }, { text: 'The answer continues here.' }] };
const openaiRate = '### Text tokens\n| Input | $0.6 | 1M tokens |\n### Audio tokens\n| Output | $20 | 1M tokens |\n### Image tokens';
const assemblyRate = '| AssemblyAI-TTS-1 | \\$15 per 1M input characters | Available |';

function fake({ assemblyRateDoc = assemblyRate, voice = stock, postStatus = 200 } = {}) {
  const posts = [];
  return { posts, fetcher: async (url, init) => {
    if (init.method === 'POST') {
      posts.push(JSON.parse(init.body));
      const wav = Buffer.alloc(46);
      wav.write('RIFF', 0); wav.writeUInt32LE(38, 4); wav.write('WAVEfmt ', 8);
      wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
      wav.writeUInt32LE(24000, 24); wav.writeUInt32LE(48000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
      wav.write('data', 36); wav.writeUInt32LE(2, 40);
      return new Response(wav, { status: postStatus });
    }
    if (url.endsWith('models.md')) return new Response(assemblyRateDoc);
    if (url.endsWith('text-to-speech')) return new Response('Flux TTS is $0.045 per 1,000 characters on pay-as-you-go');
    if (url.endsWith('gpt-realtime-2.1-mini.md')) return new Response(openaiRate);
    if (url.includes('tts.us.assemblyai.com')) return Response.json(voice);
    if (url.endsWith('/projects')) return Response.json({ projects: [{ project_id: 'fixture' }] });
    if (url.endsWith('/balances')) return new Response(null, { status: 403 });
    if (url.includes('api.openai.com')) return Response.json({ id: 'gpt-realtime-2.1-mini' });
    throw new Error('Unexpected URL');
  }};
}

test('read live rate units; stale or unrelated docs cannot quote an amount', () => {
  assert.deepEqual(parseRate('assemblyai', assemblyRate), { usdPerMillionCharacters: 15 });
  assert.equal(parseRate('assemblyai', '| AssemblyAI-STT-3.7 | $0.21/hr |'), null);
  assert.equal(parseRate('openai', openaiRate).usdPerMillionOutputAudioTokens, 20);
});

test('group adjacent same-speaker turns and preserve order, exact Unicode and cuts', () => {
  const long = '𐐷'.repeat(5020);
  const plan = makeBatches({ entity: 'personal', turns: [
    { text: long, speaker: 'A', voices: { assemblyai: 'aai-jane' } },
    { text: 'Second.', speaker: 'A', voices: { assemblyai: 'aai-jane' } },
    { text: 'Question?', speaker: 'B', voices: { assemblyai: 'aai-sara' } },
    { text: 'Answer.', speaker: 'A', voices: { assemblyai: 'aai-jane' }, keepSeparate: true },
  ] }, 'assemblyai');
  assert.equal(plan.length, 4);
  assert.equal([...plan[0].text].length, 5000);
  assert.equal(plan[0].text + plan[1].text, long + '\n\nSecond.');
  assert.deepEqual(plan.map(p => p.speaker), ['A', 'A', 'B', 'A']);
  assert.equal(makeBatches({ entity: 'personal', turns: [{ text: 'A', speaker: 'A' }, { text: 'B', speaker: 'B' }] }, 'assemblyai'), null);
});

test('long-form defaults to funded AssemblyAI; quote only performs reads', async () => {
  const provider = fake();
  const quote = await preflight(script, { ...provider, snapshots, now, env });
  assert.equal(quote.pick, 'assemblyai');
  assert.equal(quote.candidates[0].requests, 1);
  assert.equal(quote.candidates[1].method, 'native-complete-text-batch');
  assert.equal(quote.candidates[2].discountedBatch, false);
  assert.equal(quote.candidates[1].funding.balanceEndpoint, 'unavailable to this credential');
  assert.equal(provider.posts.length, 0);
});

test('unknown, stale, low, and mismatched funding never become available credit', async () => {
  const provider = fake();
  for (const bad of [undefined, { ...snapshots.assemblyai, observedAt: '2026-11-19' },
    { ...snapshots.assemblyai, entity: 'abacare' }, { ...snapshots.assemblyai, credentialSha256: 'wrong' },
    snapshot(env.ASSEMBLYAI_API_KEY, 0)]) {
    const quote = await preflight(script, { ...provider, snapshots: { assemblyai: bad }, now, env });
    assert.equal(quote.pick, null);
  }
});

test('unavailable price, private clone or direction requirements select another qualified lane', async () => {
  for (const option of [{ assemblyRateDoc: 'changed' }, { voice: { ...stock, visibility: 'private' } }]) {
    const q = await preflight(script, { ...fake(option), snapshots, now, env });
    assert.notEqual(q.pick, 'assemblyai');
  }
  const pinned = { ...script, turns: [{ text: 'Keep this voice.', voices: { assemblyai: 'private-fixture' } }] };
  const incompatible = await preflight(pinned, { ...fake({ voice: { ...stock, visibility: 'private' } }), snapshots, now, env });
  assert.equal(incompatible.pick, null);
  const priced = await preflight({ ...script, requiresDirection: true }, { ...fake(), snapshots, now, env });
  assert.equal(priced.pick, 'openai');
});

test('execution requires exact authorization and a current rate, then uses one metered request and reuses bytes', async () => {
  const folder = mkdtempSync(join(tmpdir(), 'studio-narration-'));
  try {
    const provider = fake();
    const options = { ...provider, snapshots, now, env };
    const pinned = await preflight(script, options);
    const authorization = auth(pinned);
    await assert.rejects(executeAssembly(script, pinned, auth(pinned, 0), folder, options), /authorization/);
    await assert.rejects(executeAssembly(script, pinned, authorization, folder,
      { ...options, ...fake({ assemblyRateDoc: assemblyRate.replace('$15', '$16') }) }), /authorization/);
    const quote = { ...pinned, quoteSha256: authorization.quoteSha256 };
    const result = await executeAssembly(script, quote, authorization, folder, options);
    assert.equal(result[0].actualUsd, null);
    assert.equal(provider.posts[0].stream, false);
    await executeAssembly(script, quote, authorization, folder, options);
    assert.equal(provider.posts.length, 1);
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('ambiguous provider failure fences the exact request without retrying', async () => {
  const folder = mkdtempSync(join(tmpdir(), 'studio-narration-'));
  try {
    const provider = fake({ postStatus: 503 });
    const options = { ...provider, snapshots, now, env };
    const quote = await preflight(script, options);
    await assert.rejects(executeAssembly(script, quote, auth(quote), folder, options), /503/);
    await assert.rejects(executeAssembly(script, quote, auth(quote), folder, options), /EEXIST/);
    assert.equal(provider.posts.length, 1);
  } finally { rmSync(folder, { recursive: true, force: true }); }
});
