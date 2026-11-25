// CORE-130: every paid call in kit/marketing has a deadline that also covers the body, and a call the provider may have
// finished is never sent again. Run: node --test tests/marketing-timeouts.test.mjs (local HTTP server; nothing leaves this machine)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as openai from '../kit/marketing/lib/providers/openai.mjs';
import { runCli } from '../kit/marketing/lib/providers/elevenlabs.mjs';
import { callDeadlineMs as cloudDeadlineMs } from '../kit/cloud/cloud-ai.mjs';

const marketing = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'kit', 'marketing');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'marketing-timeouts-'));
test.after(() => fs.rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }));
const take = path.join(dir, 'take.wav');
fs.writeFileSync(take, Buffer.alloc(64));

const AZURE = { endpoint: 'https://example.invalid', key: 'k' };
const CALLS = {
  generateImage: () => openai.generateImage({ prompt: 'p' }),
  visionJson: () => openai.visionJson({ model: 'm', system: 's', instructions: 'i', frames: [], schema: {} }),
  generateText: () => openai.generateText({ dynamic: 'd' }),
  transcribeText: () => openai.transcribeText(take),
  moderate: () => openai.moderate('x'),
  transcribeAzure: () => openai.transcribeAzure(take, AZURE),
};

/** Point every fetch at a local server, shorten each real deadline to 100 ms and each retry wait to 0, recording both. */
async function withServer(t, handler, run) {
  const seen = { paths: [], deadlines: [], waits: [] };
  const server = http.createServer((req, res) => {
    seen.paths.push(`${req.method} ${req.url.split('?')[0]}`);
    req.resume();
    req.on('end', () => handler(req, res, seen));
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const realFetch = globalThis.fetch;
  const realTimeout = AbortSignal.timeout.bind(AbortSignal);
  const realSetTimeout = globalThis.setTimeout;
  // A call with no deadline would hang this file: fail it instead.
  let guard;
  const stuck = new Promise((_, reject) => { guard = realSetTimeout(() => reject(new Error('STILL WAITING after 3 s')), 3000); });
  t.mock.method(globalThis, 'fetch', (url, init) => {
    const u = new URL(url);
    return realFetch(`http://127.0.0.1:${server.address().port}${u.pathname}${u.search}`, init);
  });
  t.mock.method(AbortSignal, 'timeout', (ms) => {
    seen.deadlines.push(ms);
    return realTimeout(Math.min(ms, 100));
  });
  t.mock.method(globalThis, 'setTimeout', (fn, ms, ...args) => {
    // Only the provider's own waits: Node's fetch schedules timers here too.
    if (!/providers[\\/]openai\.mjs/.test(new Error().stack)) return realSetTimeout(fn, ms, ...args);
    seen.waits.push(ms);
    return realSetTimeout(fn, 0, ...args);
  });
  const before = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'k';
  try {
    await run(seen, (p) => Promise.race([p, stuck]));
  } finally {
    clearTimeout(guard);
    if (before === undefined) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = before;
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
}

const FAULTS = {
  'never answers': [() => {}, /no complete response within .*not sent again.*may still .*charge/],
  // A byte every 10 ms for ever: an idle timeout never fires on this, only a deadline on the whole body does.
  'trickles its body': [(req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    const drip = setInterval(() => res.write(' '), 10);
    res.on('close', () => clearInterval(drip));
  }, /no complete response within .*not sent again.*may still .*charge/],
  'drops the connection': [(req) => req.socket.destroy(), /not sent again.*may still .*charge/],
  'drops the connection inside the body': [(req, res) => {
    res.writeHead(200, { 'Content-Length': '100' });
    res.write('{', () => req.socket.destroy());
  }, /not sent again.*may still .*charge/],
};
for (const [name, send] of Object.entries(CALLS)) {
  for (const [fault, [handler, message]] of Object.entries(FAULTS)) {
    test(`${name}: a provider that ${fault} is called once`, (t) => withServer(t, handler, async (seen, bounded) => {
      const error = await bounded(send()).then(() => assert.fail('resolved'), (e) => e);
      assert.equal(seen.paths.length, 1, `${error.message}; sent ${seen.paths.join(', ')}`);
      assert.equal(error.name, 'OpenAiError', error.message);
      assert.match(error.message, message);
      assert.equal(seen.deadlines.length, 1);
    }));
  }
}

const answer = (status, body = '{}', headers = {}) => (req, res) => {
  res.writeHead(status, { connection: 'close', ...headers });
  res.end(body);
};
for (const status of [500, 502, 504, 524]) {
  test(`HTTP ${status}: the model may have run, so it is not sent again`, (t) => withServer(t, answer(status, '{"error":{"type":"server_error"}}'), async (seen, bounded) => {
    await assert.rejects(bounded(CALLS.generateImage()), (e) => e.status === status && /not sent again/.test(e.message));
    assert.equal(seen.paths.length, 1);
  }));
}
test('a 503 without an OpenAI error body came from a proxy and is not sent again', (t) => withServer(t, answer(503, 'upstream connect error or disconnect'), async (seen, bounded) => {
  await assert.rejects(bounded(CALLS.generateImage()), /HTTP 503.*not sent again/);
  assert.equal(seen.paths.length, 1);
}));
test('a 503 that OpenAI answers itself is an overload refusal and retries', (t) => withServer(t, answer(503, '{"error":{"code":"overloaded"}}'), async (seen, bounded) => {
  await assert.rejects(bounded(CALLS.generateImage()), (e) => /HTTP 503 \(overloaded\)/.test(e.message) && !/charge/.test(e.message));
  assert.equal(seen.paths.length, 4);
}));

for (const retryAfter of ['86400', '1e400', '-5', 'Wed, 21 Oct 2099 07:28:00 GMT', undefined]) {
  test(`429 is refused before generation, so it retries; retry-after ${retryAfter} is bounded`, (t) => withServer(t, answer(429, '{"error":{"code":"rate_limit_exceeded"}}', retryAfter ? { 'retry-after': retryAfter } : {}), async (seen, bounded) => {
    await assert.rejects(bounded(CALLS.generateImage()), (e) => e.status === 429 && !/charge/.test(e.message));
    assert.equal(seen.paths.length, 4);
    assert.equal(seen.deadlines.length, 4, 'every attempt carries its own deadline');
    assert.equal(seen.waits.length, 3);
    assert.ok(seen.waits.every((ms) => ms > 0 && ms <= 20000), seen.waits.join(', '));
  }));
}

test('a 429 that clears is answered by the retry', (t) => withServer(t, (req, res, seen) => {
  if (seen.paths.length === 1) answer(429, '{}', { 'retry-after': '3' })(req, res);
  else answer(200, JSON.stringify({ text: 'hi' }))(req, res);
}, async (seen, bounded) => {
  assert.equal((await bounded(CALLS.transcribeText())).text, 'hi');
  assert.deepEqual(seen.waits, [3000]);
}));

test('an exhausted balance never clears by waiting, so it stops at once', (t) => withServer(t, answer(429, '{"error":{"code":"insufficient_quota"}}'), async (seen, bounded) => {
  await assert.rejects(bounded(CALLS.generateText()), /HTTP 429 \(insufficient_quota\)/);
  assert.equal(seen.paths.length, 1);
}));

test('a 429 whose body stalls is aborted and not sent again', (t) => withServer(t, (req, res) => {
  res.writeHead(429);
  res.write('x');
}, async (seen, bounded) => {
  await assert.rejects(bounded(CALLS.generateImage()), /no complete response within/);
  assert.equal(seen.paths.length, 1);
}));

test('a paid answer that is not JSON is not sent again and its text is not repeated', (t) => withServer(t, answer(200, '<html>private prompt text'), async (seen, bounded) => {
  await assert.rejects(bounded(CALLS.generateText()), (e) => /not JSON/.test(e.message) && !/private|html/.test(e.message));
  assert.equal(seen.paths.length, 1);
}));

test('a redirect does not send the paid call again', (t) => withServer(t, answer(307, '', { location: '/elsewhere' }), async (seen, bounded) => {
  await assert.rejects(bounded(CALLS.transcribeAzure()), /not sent again/);
  assert.equal(seen.paths.length, 1);
}));

test('a malformed key is not printed', async () => {
  await assert.rejects(openai.transcribeAzure(take, { ...AZURE, key: 'secretvalue' }), (e) => e.name === 'OpenAiError' && !/secret|value/.test(e.message));
});

test("Node's own headers timeout is not sent again", async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    throw Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('Headers Timeout Error'), { code: 'UND_ERR_HEADERS_TIMEOUT' }) });
  };
  await assert.rejects(openai.transcribeAzure(take, { ...AZURE, fetchImpl }), /UND_ERR_HEADERS_TIMEOUT.*not sent again/);
  assert.equal(calls, 1);
});

test('the deadline grows with the upload and matches kit/cloud', (t) => withServer(t, answer(200, '{"text":"hi"}'), async (seen, bounded) => {
  const big = path.join(dir, 'big.wav');
  fs.writeFileSync(big, Buffer.alloc(1_000_000));
  await bounded(openai.transcribeText(big));
  await bounded(openai.transcribeAzure(big, AZURE));
  await bounded(openai.generateText({ dynamic: 'x'.repeat(1_000_000) }));
  assert.equal(seen.deadlines.length, 3);
  for (const ms of seen.deadlines) assert.ok(ms >= cloudDeadlineMs(1_000_000) && ms <= cloudDeadlineMs(1_001_000), `${ms} ms`);
}));

test('Realtime speech that never finishes ends at its deadline and asks for audio once', async () => {
  let created = 0;
  let drip;
  class Endless {
    constructor() {
      queueMicrotask(() => this.onopen());
      drip = setInterval(() => this.onmessage({ data: '{"type":"response.output_audio.delta","delta":"AAAA"}' }), 10);
    }
    send(payload) { if (JSON.parse(payload).type === 'response.create') created++; }
    close() { clearInterval(drip); }
  }
  await assert.rejects(openai.speech({ text: 't', credential: 'k', timeoutMs: 100, WebSocketImpl: Endless }), (e) => /timed out/.test(e.message) && e.definitelyUnsubmitted === false);
  assert.equal(created, 1);
});

test('an ElevenLabs adapter that hangs is stopped at its deadline and started once', async () => {
  const script = path.join(dir, 'adapter.mjs');
  const log = path.join(dir, 'starts.txt');
  fs.writeFileSync(script, "import fs from 'node:fs'; fs.appendFileSync(process.argv[2], 'x'); setInterval(() => process.stdout.write('.'), 10);");
  await assert.rejects(runCli({ python: process.execPath, script, cwd: path.dirname(process.execPath) }, [log], { timeoutMs: 2000 }), /timed out; the reservation is retained/);
  assert.equal(fs.readFileSync(log, 'utf8'), 'x');
});

test('every fetch in kit/marketing passes an AbortSignal', () => {
  const bare = [];
  let checked = 0;
  for (const file of fs.readdirSync(marketing, { recursive: true }).filter((f) => f.endsWith('.mjs'))) {
    const text = fs.readFileSync(path.join(marketing, file), 'utf8');
    for (const m of text.matchAll(/\bfetch(?:Impl)?\(/g)) {
      checked++;
      let end = m.index + m[0].length;
      for (let depth = 1; depth; end++) depth += { '(': 1, ')': -1 }[text[end]] || 0;
      if (!/\bsignal\b/.test(text.slice(m.index, end))) bare.push(`${file}:${text.slice(0, m.index).split('\n').length}`);
    }
  }
  assert.ok(checked > 0);
  assert.deepEqual(bare, []);
});
