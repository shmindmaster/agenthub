// cloud-ai unit tests: helpers, provider order, mocked provider calls, alignment output, and Gemini key handling.
// Run: node --test tests/cloud-ai.test.mjs (provider calls are mocked)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { parseArgs, extractJson, providerOrder, ask, align, callGemini } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-ai.mjs')).href);

test('parseArgs collects list options until the next flag', () => {
  const { sub, opts } = parseArgs(['qa', '--images', 'a.jpg', 'b.png', '--prompt', 'look', '--out', 'r.json', '--client']);
  assert.equal(sub, 'qa');
  assert.deepEqual(opts.images, ['a.jpg', 'b.png']);
  assert.equal(opts.prompt, 'look');
  assert.equal(opts.out, 'r.json');
  assert.equal(opts.client, true);
});

test('extractJson reads fenced and prose-wrapped replies', () => {
  assert.deepEqual(extractJson('Here:\n```json\n{"score": 90, "pass": true}\n```'), { score: 90, pass: true });
  assert.deepEqual(extractJson('Verdict {"score": 40, "findings": []} done'), { score: 40, findings: [] });
  assert.throws(() => extractJson('no json here'), /no JSON/);
});

test('providerOrder: Anthropic only by default, no paid spillover; --client stays in the owner tenant', () => {
  assert.deepEqual(providerOrder({}), ['anthropic']);
  assert.deepEqual(providerOrder({ provider: 'gemini' }), ['gemini']);
  assert.deepEqual(providerOrder({ client: true }), ['azure-openai']);
  assert.throws(() => providerOrder({ client: true, provider: 'anthropic' }), /may not go to Anthropic/);
  assert.deepEqual(providerOrder({ client: true, provider: 'openai' }), ['openai']);
});

const { canonKey, heardKeys, scriptTokens, alignScript } = await import(pathToFileURL(join(pkg, 'kit', 'cloud', 'cloud-ai.mjs')).href);
const { forcedWordOnsets, cloudAlignCoverage } = await import(pathToFileURL(join(pkg, 'kit', 'screencast', 'sync-lib.mjs')).href);

test('canonKey speaks numbers and expands apostrophe contractions', () => {
  assert.equal(canonKey('30'), 'thirty');
  assert.equal(canonKey('$1.71'), 'onepointsevenonedollars');
  assert.equal(canonKey('10%'), 'tenpercent');
  assert.equal(canonKey('twenty-four'), canonKey('24'));
  assert.equal(canonKey('20-person'), 'twentyperson');
  assert.equal(canonKey('I’m'), 'iam');
  assert.equal(canonKey('ill'), 'ill');
});

test('heardKeys moves a currency word after its scale word', () => {
  assert.deepEqual(heardKeys([{ text: '$800', start: 0, end: 1 }, { text: 'million', start: 1, end: 2 }]).map((w) => w.key), ['eighthundred', 'milliondollars']);
});

const heard = (pairs) => pairs.map(([text, start, end]) => ({ key: canonKey(text), start, end }));

test('alignScript keeps exact ASR onsets, merges compounds and snaps to the 80 ms grid', () => {
  const script = scriptTokens("Hi, I'm a language-model builder.");
  const { words, coverage } = alignScript(script, heard([['hi', 0.1, 0.3], ['i', 0.41, 0.5], ['am', 0.5, 0.62], ['a', 0.7, 0.75], ['language', 0.8, 1.2], ['model', 1.2, 1.5], ['builder', 1.6, 2.0]]), 2.5);
  assert.deepEqual(words.map((w) => w.text), ['Hi,', "I'm", 'a', 'language-model', 'builder.']);
  assert.ok(words.every((w) => !w.precisionLimited));
  assert.ok(words.every((w) => Math.abs(w.start / 0.08 - Math.round(w.start / 0.08)) < 1e-6));
  assert.equal(words[1].start, 0.4);
  assert.equal(coverage.exact, 5);
});

test('alignScript bounds a misheard word by its neighbours and flags it', () => {
  const { words, coverage } = alignScript(scriptTokens('at Pendoah where'), heard([['at', 0, 0.2], ['pandoa', 0.25, 0.8], ['where', 0.9, 1.1]]), 1.5);
  assert.equal(words[1].precisionLimited, true);
  assert.ok(words[1].start >= words[0].end && words[1].end <= words[2].start);
  assert.equal(coverage.longestUnmatchedRun, 1);
});

const cloudReport = (words) => ({ schema: 'cloud-speech/script-alignment/1', units: 'seconds', gridSeconds: 0.08, durationSeconds: 10, take: { sha256: 't' }, script: { sha256: 's' }, words });

test('sync gate refuses cloud alignment unless the job opted in', () => {
  const words = [{ text: 'a', start: 0, end: 0.08, precisionLimited: false }];
  assert.throws(() => forcedWordOnsets(cloudReport(words), [{ w: 'a', start: 0 }], { takeSha256: 't', scriptSha256: 's' }), /not forced alignment/);
});

test('picture clock: asr-anchored accepted only with the job opt-in and valid coverage', async () => {
  const { clockAccepted, asrAnchoredAllowed } = await import(pathToFileURL(join(pkg, 'scripts', 'picture-gates.mjs')).href);
  assert.equal(clockAccepted({ method: 'asr-anchored-alignment' }).ok, false);
  const goodWords = Array.from({ length: 10 }, (_, i) => ({ text: `w${i}`, start: i * 0.16, end: i * 0.16 + 0.08 }));
  assert.equal(clockAccepted({ method: 'asr-anchored-alignment', words: goodWords }, { allowAsrAnchored: asrAnchoredAllowed({ clockPolicy: { allowAsrAnchored: true } }) }).ok, true);
  assert.equal(clockAccepted({ method: 'forced-alignment' }).ok, true);
});

test('sync gate accepts a tight cloud alignment and refuses a loose one', () => {
  const tight = Array.from({ length: 10 }, (_, i) => ({ text: `w${i}`, start: +(i * 0.16).toFixed(2), end: +(i * 0.16 + 0.08).toFixed(2), precisionLimited: i === 4 }));
  const cue = tight.map((w) => ({ w: w.text, start: w.start }));
  assert.equal(forcedWordOnsets(cloudReport(tight), cue, { takeSha256: 't', scriptSha256: 's', allowAsrAnchored: true }).length, 10);
  const loose = tight.map((w, i) => ({ ...w, precisionLimited: i < 3 }));
  assert.equal(cloudAlignCoverage(loose).exactRatio, 0.7);
  assert.throws(() => forcedWordOnsets(cloudReport(loose), cue, { takeSha256: 't', scriptSha256: 's', allowAsrAnchored: true }), /too loose/);
  assert.throws(() => forcedWordOnsets({ ...cloudReport(tight), schema: 'whisper/1' }, cue, { takeSha256: 't', scriptSha256: 's', allowAsrAnchored: true }), /80 ms grid/);
  assert.throws(() => forcedWordOnsets(cloudReport(tight), cue, { takeSha256: 'other', scriptSha256: 's', allowAsrAnchored: true }), /SHA-256 mismatch/);
});

function makeWav(durationSeconds = 2) {
  const sampleRate = 16000;
  const byteRate = sampleRate * 2; // mono 16-bit
  const dataSize = Math.floor(durationSeconds * byteRate);
  const totalSize = 36 + dataSize;
  const buf = Buffer.alloc(44 + dataSize);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(totalSize, 4);
  buf.write('WAVE', 8);
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(byteRate, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36);
  buf.writeUInt32LE(dataSize, 40);
  return buf;
}

function makeResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => JSON.stringify(body),
    json: async () => body,
    headers: { get: () => null },
  };
}

function saveEnv(keys) {
  return Object.fromEntries(keys.map((k) => [k, process.env[k]]));
}

function restoreEnv(saved) {
  for (const [k, v] of Object.entries(saved)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
}

test('align() writes <out>.failed.json and skips --out when coverage is too low', async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cloud-ai-align-'));
  const takePath = path.join(tmp, 'take.wav');
  const scriptPath = path.join(tmp, 'script.txt');
  const outPath = path.join(tmp, 'report.json');
  const failedPath = `${outPath}.failed.json`;
  const env = saveEnv(['AZURE_SPEECH_KEY', 'AZURE_SPEECH_REGION']);
  process.env.AZURE_SPEECH_KEY = 'test-key';
  process.env.AZURE_SPEECH_REGION = 'eastus';

  const originalFetch = global.fetch;
  global.fetch = async (url, init) => {
    if (url.includes('cognitive.microsoft.com/speechtotext/transcriptions:transcribe')) {
      return makeResponse({
        durationMilliseconds: 2000,
        phrases: [{ words: [{ text: 'hello', offsetMilliseconds: 0, durationMilliseconds: 200 }] }],
      });
    }
    return makeResponse({}, 404);
  };

  try {
    fs.writeFileSync(takePath, makeWav(2));
    fs.writeFileSync(scriptPath, 'one two three four five six seven eight nine ten eleven twelve');

    const report = await align({ take: takePath, script: scriptPath, out: outPath });

    assert.equal(report.ok, false);
    assert.equal(fs.existsSync(outPath), false, 'requested --out file should not exist when coverage is too low');
    assert.equal(fs.existsSync(failedPath), true, 'failed report should be written');
    const failedReport = JSON.parse(fs.readFileSync(failedPath, 'utf8'));
    assert.equal(failedReport.ok, false);
    assert.ok(failedReport.errors[0].includes('coverage too low'));
  } finally {
    global.fetch = originalFetch;
    restoreEnv(env);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test('ask() without --provider stops on Anthropic auth failure and does not call other providers', async () => {
  const env = saveEnv(['ANTHROPIC_API_KEY']);
  process.env.ANTHROPIC_API_KEY = 'test-key';
  const originalFetch = global.fetch;
  const called = [];
  global.fetch = async (url, init) => {
    called.push(url);
    if (url.startsWith('https://api.anthropic.com/')) {
      return makeResponse({ error: { message: 'invalid auth' } }, 401);
    }
    if (url.includes('openai.azure.com') || url.includes('api.openai.com') || url.includes('generativelanguage.googleapis.com')) {
      return makeResponse({ choices: [{ message: { content: '{"score":90,"pass":true,"summary":"ok","findings":[]}' } }], model: 'mock', usage: {} });
    }
    return makeResponse({}, 404);
  };

  try {
    await assert.rejects(ask({}, { system: 's', text: 't', images: [] }), /anthropic blocked \(authentication or free-tier quota refused\)/);
    assert.ok(called.some((u) => u.startsWith('https://api.anthropic.com/')), 'Anthropic URL should be called');
    assert.ok(!called.some((u) => /openai\.azure\.com|api\.openai\.com|generativelanguage\.googleapis\.com/.test(u)), 'no other paid provider should be called');
  } finally {
    global.fetch = originalFetch;
    restoreEnv(env);
  }
});

test('Gemini model discovery sends the key in x-goog-api-key header, not the URL', async () => {
  const env = saveEnv(['GEMINI_API_KEY']);
  process.env.GEMINI_API_KEY = 'test-api-key';
  const originalFetch = global.fetch;
  let captured = null;
  global.fetch = async (url, init) => {
    if (url.includes('/models?')) {
      captured = { url, headers: init?.headers || {} };
      return makeResponse({ models: [{ name: 'models/gemini-2.0-flash' }] });
    }
    if (url.includes(':generateContent')) {
      return makeResponse({ candidates: [{ content: { parts: [{ text: 'hi' }] } }], usageMetadata: {} });
    }
    return makeResponse({}, 404);
  };

  try {
    await callGemini({ system: 's', text: 't', images: [] });
    assert.ok(captured, 'model discovery fetch was captured');
    assert.ok(!captured.url.includes('key='), 'API key must not appear in the discovery URL');
    assert.equal(captured.headers['x-goog-api-key'], 'test-api-key');
  } finally {
    global.fetch = originalFetch;
    restoreEnv(env);
  }
});

test('ask({provider: gemini}) calls the Gemini URL', async () => {
  const env = saveEnv(['GEMINI_API_KEY']);
  process.env.GEMINI_API_KEY = 'test-key';
  const originalFetch = global.fetch;
  const called = [];
  global.fetch = async (url, init) => {
    called.push(url);
    if (url.includes('/models?')) {
      return makeResponse({ models: [{ name: 'models/gemini-2.0-flash' }] });
    }
    if (url.includes(':generateContent')) {
      return makeResponse({ candidates: [{ content: { parts: [{ text: '{"score":90,"pass":true,"summary":"ok","findings":[]}' }] } }], usageMetadata: {} });
    }
    return makeResponse({}, 404);
  };

  try {
    const r = await ask({ provider: 'gemini' }, { system: 's', text: 't', images: [] });
    assert.equal(r.provider, 'gemini');
    assert.ok(called.some((u) => u.includes('generativelanguage.googleapis.com')), 'Gemini URL should be called');
  } finally {
    global.fetch = originalFetch;
    restoreEnv(env);
  }
});

test('ask() stops with a credit blocker when Anthropic credits are exhausted and does not spill to a paid provider', async () => {
  const env = saveEnv(['ANTHROPIC_API_KEY']);
  process.env.ANTHROPIC_API_KEY = 'test-key';
  const originalFetch = global.fetch;
  const called = [];
  global.fetch = async (url) => {
    called.push(url);
    if (url.startsWith('https://api.anthropic.com/')) return makeResponse({ error: { message: 'Your credit_balance is too low' } }, 400);
    return makeResponse({ choices: [{ message: { content: '{}' } }] });
  };
  try {
    await assert.rejects(ask({}, { system: 's', text: 't', images: [] }), /anthropic blocked \(credit or quota exhausted\)/);
    assert.deepEqual(called, ['https://api.anthropic.com/v1/messages']);
  } finally {
    global.fetch = originalFetch;
    restoreEnv(env);
  }
});

test('ask() with --client and an explicit anthropic provider is still refused', async () => {
  await assert.rejects(ask({ client: true, provider: 'anthropic' }, { system: 's', text: 't', images: [] }), /may not go to Anthropic/);
});

test('align() on free-tier quota refusal stops and does not try azure-s0 or deepgram', async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cloud-ai-align-quota-'));
  const env = saveEnv(['AZURE_SPEECH_KEY', 'AZURE_SPEECH_REGION', 'AZURE_AI_SERVICES_KEY', 'AZURE_AI_SERVICES_REGION', 'DEEPGRAM_API_KEY']);
  Object.assign(process.env, { AZURE_SPEECH_KEY: 'k', AZURE_SPEECH_REGION: 'eastus', AZURE_AI_SERVICES_KEY: 'k2', AZURE_AI_SERVICES_REGION: 'eastus', DEEPGRAM_API_KEY: 'k3' });
  const originalFetch = global.fetch;
  const called = [];
  global.fetch = async (url) => {
    called.push(String(url));
    return makeResponse({ error: 'quota' }, 429);
  };
  try {
    fs.writeFileSync(path.join(tmp, 'take.wav'), makeWav(1));
    fs.writeFileSync(path.join(tmp, 'script.txt'), 'hello world');
    await assert.rejects(align({ take: path.join(tmp, 'take.wav'), script: path.join(tmp, 'script.txt'), out: path.join(tmp, 'r.json') }), /azure blocked/);
    assert.equal(called.length, 1, called.join(', '));
    assert.ok(!called.some((u) => /deepgram/.test(u)));
  } finally {
    global.fetch = originalFetch;
    restoreEnv(env);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
