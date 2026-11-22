import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, symlinkSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { executeAssembly, inspectElevenLabs, makeBatches, parseRate, preflight, recoverLedgers, resolveOpenAIKey } from '../scripts/narration-preflight.mjs';

const now = Date.parse('2026-11-22T18:30:00Z');
const env = { ASSEMBLYAI_API_KEY: 'fixture-key', OPENAI_API_KEY: 'openai-fixture', DEEPGRAM_API_KEY: 'dg-fixture' };
const hash = value => createHash('sha256').update(value).digest('hex');
const auth = (quote, outputDir, maxUsd = 1) => ({ quoteSha256: hash(JSON.stringify(quote)), entity: 'personal',
  maxUsd, outputDir, ownerApproval: 'fixture approval' });
const snapshot = (key, availableUsd = 20) => ({ entity: 'personal', source: 'dashboard', availableUsd,
  observedAt: new Date(now).toISOString(), credentialSha256: hash(key) });
const snapshots = { assemblyai: snapshot(env.ASSEMBLYAI_API_KEY), openai: snapshot(env.OPENAI_API_KEY), deepgram: snapshot(env.DEEPGRAM_API_KEY) };
const stock = { source: 'assemblyai', visibility: 'public', status: 'active', language: 'english', ready_models: ['assemblyai-tts-1'] };
const script = { entity: 'personal', longForm: true, turns: [{ text: 'The answer opens here.' }, { text: 'The answer continues here.' }] };
const openaiRate = '### Text tokens\n| Input | $0.6 | 1M tokens |\n### Audio tokens\n| Output | $20 | 1M tokens |\n### Image tokens';
const assemblyRate = '| AssemblyAI-TTS-1 | \\$15 per 1M input characters | Available |';

test('standalone commands run through a Media Studio directory link', () => {
  const folder = mkdtempSync(join(tmpdir(), 'studio-narration-cli-'));
  try {
    const link = join(folder, 'tools');
    symlinkSync(fileURLToPath(new URL('../scripts', import.meta.url)), link, process.platform === 'win32' ? 'junction' : 'dir');
    const result = spawnSync(process.execPath, [join(link, 'narration-preflight.mjs'), 'fingerprint', 'assemblyai'],
      { encoding: 'utf8', windowsHide: true, env: { ...process.env, ...env } });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), hash(env.ASSEMBLYAI_API_KEY));
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('local recovery rolls back an interrupted sqlite write and keeps committed reservations', () => {
  const folder = mkdtempSync(join(tmpdir(), 'studio-narration-ledger-'));
  try {
    const ledger = join(folder, 'assemblyai-submissions.sqlite3');
    const database = new DatabaseSync(ledger);
    database.exec("CREATE TABLE submissions (take_id TEXT PRIMARY KEY, evidence TEXT NOT NULL); INSERT INTO submissions VALUES ('accepted', 'held');");
    database.close();
    const crash = spawnSync(process.execPath, ['-e', `
      const { DatabaseSync } = require('node:sqlite');
      const db = new DatabaseSync(process.argv[1]);
      db.exec('PRAGMA cache_size=2; PRAGMA cache_spill=ON; BEGIN IMMEDIATE;');
      const insert = db.prepare('INSERT INTO submissions VALUES (?, ?)');
      for (let i = 0; i < 60; i++) insert.run('incomplete:' + i, 'x'.repeat(8192));
      process.kill(process.pid, 'SIGKILL');
    `, ledger], { encoding: 'utf8', windowsHide: true });
    assert.notEqual(crash.status, 0);
    assert.ok(readdirSync(folder).includes('assemblyai-submissions.sqlite3-journal'), crash.stderr);
    assert.deepEqual(recoverLedgers(folder, folder), { checked: 1 });
    const recovered = new DatabaseSync(ledger, { readOnly: true });
    try { assert.deepEqual(recovered.prepare('SELECT take_id FROM submissions').all().map(r => r.take_id), ['accepted']); }
    finally { recovered.close(); }
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('local recovery initializes a ledger left empty before its first reservation', () => {
  const folder = mkdtempSync(join(tmpdir(), 'studio-narration-empty-'));
  try {
    const files = [['openai-narration.sqlite3', 'voice_spend'], ['assemblyai-submissions.sqlite3', 'submissions']];
    for (const [name] of files) new DatabaseSync(join(folder, name)).close();
    assert.deepEqual(recoverLedgers(folder, folder), { checked: 2 });
    for (const [name, table] of files) {
      const db = new DatabaseSync(join(folder, name), { readOnly: true });
      try { assert.ok(db.prepare('SELECT name FROM sqlite_schema WHERE name = ?').get(table)); }
      finally { db.close(); }
    }
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

function fake({ assemblyRateDoc = assemblyRate, voice = stock, postStatus = 200 } = {}) {
  const posts = [];
  return { posts, fetcher: async (url, init) => {
    if (init.method === 'POST') {
      assert.equal(url, 'https://tts.us.assemblyai.com/v1/speech');
      assert.equal(init.redirect, 'error');
      assert.equal(init.headers['Content-Type'], 'application/json');
      const body = JSON.parse(init.body);
      const { text, voice_id, ...format } = body;
      assert.ok(text.trim());
      assert.equal(voice_id, 'aai-jane');
      assert.deepEqual(format, { model_id: 'assemblyai-tts-1', sample_rate: 24000, language: 'english',
        encoding: 'pcm_s16le', container: 'wav', stream: false });
      posts.push(body);
      const wav = Buffer.alloc(46);
      wav.write('RIFF', 0); wav.writeUInt32LE(38, 4); wav.write('WAVEfmt ', 8);
      wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
      wav.writeUInt32LE(24000, 24); wav.writeUInt32LE(48000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
      wav.write('data', 36); wav.writeUInt32LE(2, 40);
      return new Response(wav, { status: postStatus, headers: { 'x-request-id': 'fixture-receipt' } });
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
  assert.deepEqual(plan.map(p => p.turns), [[1], [1, 2], [3], [4]]);
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
    const authorization = auth(pinned, folder);
    await assert.rejects(executeAssembly(script, pinned, auth(pinned, folder, 0), folder, options), /authorization/);
    await assert.rejects(executeAssembly(script, pinned, authorization, folder,
      { ...options, ...fake({ assemblyRateDoc: assemblyRate.replace('$15', '$16') }) }), /authorization/);
    const quote = { ...pinned, quoteSha256: authorization.quoteSha256 };
    await assert.rejects(executeAssembly(script, quote, authorization, folder + '-different', options), /authorization/);
    const result = await executeAssembly(script, quote, authorization, folder, options);
    assert.equal(result[0].actualUsd, null);
    assert.equal(provider.posts[0].stream, false);
    const receipt = join(folder, readdirSync(folder).find(name => /^0001-.*(?<!submitted)\.json$/.test(name)));
    renameSync(receipt, receipt + '.staged');
    await executeAssembly(script, quote, authorization, folder, { ...options,
      snapshots: { assemblyai: snapshot(env.ASSEMBLYAI_API_KEY, 0) } });
    assert.equal(provider.posts.length, 1);
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('ambiguous provider failure fences the exact request without retrying', async () => {
  const folder = mkdtempSync(join(tmpdir(), 'studio-narration-'));
  try {
    const provider = fake({ postStatus: 503 });
    const options = { ...provider, snapshots, now, env };
    const quote = await preflight(script, options);
    await assert.rejects(executeAssembly(script, quote, auth(quote, folder), folder, options), /503/);
    const response = readdirSync(folder).find(name => name.endsWith('.response'));
    assert.equal(JSON.parse(readFileSync(join(folder, response))).providerRequestId, 'fixture-receipt');
    // Losing the operator-facing marker still leaves the durable claim.
    unlinkSync(join(folder, readdirSync(folder).find(name => name.endsWith('.submitted.json'))));
    await assert.rejects(executeAssembly(script, quote, auth(quote, folder), folder, options), /reconciliation/);
    assert.equal(provider.posts.length, 1);
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('OpenAI eligibility checks the built-in voice and estimates unspaced speech', async () => {
  const text = '企業向けの取引処理とシステム改善。'.repeat(40);
  const options = { ...fake(), now, env, snapshots: { openai: snapshot(env.OPENAI_API_KEY, 0.001) } };
  const wanted = { entity: 'personal', provider: 'openai', language: 'japanese', turns: [{ text }] };
  const quote = await preflight(wanted, options);
  assert.equal(quote.pick, null);
  assert.ok(quote.candidates[2].estimatedUsd > 0.01);
  const wrongVoice = { ...wanted, turns: [{ text, voices: { openai: 'nova' } }] };
  const blocked = await preflight(wrongVoice, { ...options, snapshots });
  assert.equal(blocked.pick, null);
  assert.equal(blocked.candidates[2].funding.access, 'voice-ineligible');
});

test('Deepgram requires adequate remaining budget from the governed local ledger', async () => {
  const wanted = { ...script, provider: 'deepgram' };
  for (const [micros, pick] of [[null, null], [0, null], [1, null], [1_000_000, 'deepgram']]) {
    const quote = await preflight(wanted, { ...fake(), snapshots, now, env, readDeepgramBudget: () => micros });
    assert.equal(quote.pick, pick);
    if (!pick) assert.match(quote.candidates[1].reasons.join(' '), /local budget/);
  }
});

test('Windows credential precedence uses the user key and its funding evidence', async () => {
  const selected = resolveOpenAIKey({ platform: 'win32', env, run: () => ({ status: 0,
    stdout: '    OPENAI_API_KEY    REG_SZ    user-fixture\r\n' }) });
  assert.equal(selected, 'user-fixture');
  const provider = fake();
  const options = { now, env, openaiKey: selected, fetcher: (url, init) => {
    if (url.includes('api.openai.com')) assert.equal(init.headers.Authorization, 'Bearer user-fixture');
    return provider.fetcher(url, init);
  } };
  const wanted = { ...script, provider: 'openai' };
  assert.equal((await preflight(wanted, { ...options, snapshots })).pick, null);
  assert.equal((await preflight(wanted, { ...options, snapshots: { openai: snapshot(selected) } })).pick, 'openai');
});


test('manual ElevenLabs check uses live model-specific rates and reports dialogue separately', async () => {
  const results = await inspectElevenLabs('eleven_v4_turbo', {
    env: { ELEVENLABS_API_KEY: 'fixture' },
    fetcher: async (url, init) => {
      assert.equal(init.method, undefined);
      if (url.endsWith('/models')) return Response.json([{ model_id: 'eleven_v4_turbo', can_do_text_to_speech: true,
        model_rates: { character_cost_multiplier: .5, cost_discount_multiplier: 1 } }]);
      return Response.json({ status: 'active', character_limit: 120, character_count: 19, can_extend_character_limit: false });
    },
  });
  assert.equal(results.availableCredits, 101);
  assert.equal(results.speechCreditsPerCharacter, .5);
  assert.equal(results.overageEnabled, false);
  assert.match(results.dialogueRate, /billing history/);
});


test('Deepgram rejects unsupported language and an expired or changed adapter rate', async () => {
  const provider = fake();
  const dg = { deepgram: snapshot(env.DEEPGRAM_API_KEY) };
  const wanted = { ...script, provider: 'deepgram' };
  for (const field of [
    { script: { ...wanted, language: 'french' }, now },
    { script: wanted, now: Date.parse('2026-11-25T00:00:00Z') },
  ]) {
    const funds = { deepgram: { ...dg.deepgram, observedAt: new Date(field.now).toISOString() } };
    const quote = await preflight(field.script, { ...provider, snapshots: funds, now: field.now, env });
    assert.equal(quote.pick, null);
    assert.match(quote.candidates[1].reasons.join(' '), /language|refresh/);
  }
});

test('exact integer cap works across takes and the quote cannot move to another account', async () => {
  const folder = mkdtempSync(join(tmpdir(), 'studio-narration-'));
  try {
    const provider = fake();
    const text = { ...script, turns: [{ text: 'x'.repeat(4181), keepSeparate: true }, { text: 'x'.repeat(820) }] };
    const options = { ...provider, snapshots, now, env };
    const quote = await preflight(text, options);
    const approval = auth(quote, folder, 0.075015);
    const other = 'different-account-key';
    await assert.rejects(executeAssembly(text, quote, approval, folder, { ...options,
      env: { ...env, ASSEMBLYAI_API_KEY: other }, snapshots: { assemblyai: snapshot(other) } }), /authorization/);
    assert.equal(provider.posts.length, 0);
    const records = await executeAssembly(text, quote, approval, folder, options);
    assert.equal(records.length, 2);
    assert.equal(provider.posts.length, 2);
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('renewal prices only missing wallet spend and preserves the cumulative authorized cap', async () => {
  const parent = mkdtempSync(join(tmpdir(), 'studio-narration-renew-'));
  const folder = join(parent, 'takes');
  try {
    const provider = fake();
    const text = { ...script, turns: [{ text: 'a'.repeat(2000), keepSeparate: true }, { text: 'b'.repeat(1000) }] };
    const options = { ...provider, snapshots, now, env, outputDir: folder };
    const original = await preflight(text, options);
    await executeAssembly(text, original, auth(original, folder), folder, options);
    // Simulate an interruption before the second request, retaining the verified first take.
    for (const name of readdirSync(folder).filter(name => name.startsWith('0002-')))
      renameSync(join(folder, name), join(parent, name));
    const journal = new DatabaseSync(join(folder, 'assemblyai-submissions.sqlite3'));
    journal.prepare("DELETE FROM submissions WHERE take_id LIKE '0002:%'").run();
    journal.close();
    const later = now + 25 * 60 * 60 * 1000;
    const refreshed = { ...options, now: later,
      snapshots: { assemblyai: { ...snapshot(env.ASSEMBLYAI_API_KEY, 0.015), observedAt: new Date(later).toISOString() } } };
    const quote = await preflight(text, refreshed);
    const candidate = quote.candidates[0];
    assert.equal(quote.pick, 'assemblyai');
    assert.equal(candidate.remainingUsd, 0.015);
    assert.equal(candidate.priorReservedUsd, 0.03);
    assert.equal(candidate.estimatedUsd, 0.045);
    await assert.rejects(executeAssembly(text, quote, auth(quote, folder, 0.015), folder, refreshed), /authorization/);
    const results = await executeAssembly(text, quote, auth(quote, folder, 0.045), folder, refreshed);
    assert.equal(results.length, 2);
    assert.equal(provider.posts.length, 3);
    assert.equal(provider.posts[2].text, 'b'.repeat(1000));
  } finally { rmSync(parent, { recursive: true, force: true }); }
});
