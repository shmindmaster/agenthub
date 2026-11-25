// CORE-52: every cloud model call has a deadline that also covers the body, and a timed-out paid call is never sent again.
// Run: node --test tests/cloud-timeouts.test.mjs (calls go to a local HTTP server; nothing leaves this machine)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const cloud = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'kit', 'cloud');
const { ask, assemblyaiWords, align, callDeadlineMs } = await import('../kit/cloud/cloud-ai.mjs');

const KEYS = { ANTHROPIC_API_KEY: 'k', OPENAI_API_KEY: 'k', GEMINI_API_KEY: 'k', DEEPGRAM_API_KEY: 'k', ASSEMBLYAI_API_KEY: 'k', AZURE_SPEECH_KEY: 'k', AZURE_SPEECH_REGION: 'test' };
const REQUEST = { system: 's', text: 't', images: [] };
const hang = () => {}; // accepts the request and never answers
const stallBody = (req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.write('{');
};

/** Point every fetch at a local server, and shorten each real deadline to 100 ms while recording what was asked for. */
async function withServer(t, handler, run) {
  const seen = { paths: [], deadlines: [] };
  const server = http.createServer((req, res) => {
    seen.paths.push(`${req.method} ${req.url.split('?')[0]}`);
    req.resume();
    handler(req, res, seen);
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const realFetch = globalThis.fetch;
  const realTimeout = AbortSignal.timeout.bind(AbortSignal);
  t.mock.method(globalThis, 'fetch', (url, init) => {
    const u = new URL(url);
    return realFetch(`http://127.0.0.1:${server.address().port}${u.pathname}${u.search}`, init);
  });
  t.mock.method(AbortSignal, 'timeout', (ms) => {
    seen.deadlines.push(ms);
    return realTimeout(Math.min(ms, 100));
  });
  const env = Object.fromEntries(Object.keys(KEYS).map((k) => [k, process.env[k]]));
  Object.assign(process.env, KEYS);
  // A call with no deadline would hang this file: fail it instead.
  let guard;
  const stuck = new Promise((_, reject) => {
    guard = setTimeout(() => reject(new Error('STILL WAITING after 3 s')), 3000);
  });
  try {
    await run(seen, (p) => Promise.race([p, stuck]));
  } finally {
    clearTimeout(guard);
    for (const [k, v] of Object.entries(env)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
}

for (const provider of ['anthropic', 'openai', 'gemini']) {
  const opts = { provider, model: 'm' };
  test(`${provider}: a provider that never answers is aborted and called once`, (t) => withServer(t, hang, async (seen, bounded) => {
    await assert.rejects(bounded(ask(opts, REQUEST)), /blocked \(timed out.*may still.*charge.*\).*no complete response within/);
    assert.equal(seen.paths.length, 1, seen.paths.join(', '));
  }));
  test(`${provider}: a body that stalls after the headers is aborted and called once`, (t) => withServer(t, stallBody, async (seen, bounded) => {
    await assert.rejects(bounded(ask(opts, REQUEST)), /blocked \(timed out/);
    assert.equal(seen.paths.length, 1, seen.paths.join(', '));
  }));
}

test('an error response whose body stalls is aborted and not sent again', (t) => withServer(t, (req, res) => {
  res.writeHead(503);
  res.write('x');
}, async (seen, bounded) => {
  await assert.rejects(bounded(ask({}, REQUEST)), /blocked \(timed out/);
  assert.equal(seen.paths.length, 1);
}));

test("Node's own headers timeout counts as a timeout, not as an ordinary failure", async (t) => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => {
    throw Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('Headers Timeout Error'), { code: 'UND_ERR_HEADERS_TIMEOUT' }) });
  });
  const before = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'k';
  try {
    await assert.rejects(ask({}, REQUEST), /blocked [(]timed out.*Headers Timeout Error/);
  } finally {
    if (before === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = before;
  }
  assert.equal(fetch.mock.callCount(), 1);
});

const answer = (status, retryAfter) => (req, res) => {
  // No keep-alive, so the only long timers are the retry waits.
  res.writeHead(status, { 'retry-after': retryAfter, connection: 'close' });
  res.end('{}');
};
for (const status of [504, 524]) {
  test(`HTTP ${status} is a gateway timeout: the model may have run, so it is not sent again`, (t) => withServer(t, answer(status, '1'), async (seen, bounded) => {
    await assert.rejects(bounded(ask({}, REQUEST)), /blocked \(timed out/);
    assert.equal(seen.paths.length, 1);
  }));
}

for (const retryAfter of ['86400', '1e400', 'Wed, 21 Oct 2099 07:28:00 GMT']) {
  test(`retry-after "${retryAfter}" cannot hold a job beyond the cap`, (t) => withServer(t, answer(429, retryAfter), async (seen, bounded) => {
    const realSetTimeout = globalThis.setTimeout;
    const waits = [];
    t.mock.method(globalThis, 'setTimeout', (fn, ms, ...args) => {
      if (ms < 2000) return realSetTimeout(fn, ms, ...args);
      waits.push(ms);
      return realSetTimeout(fn, 0, ...args);
    });
    await assert.rejects(bounded(ask({}, REQUEST)), /still rate limited or unavailable after retries/);
    assert.equal(seen.paths.length, 3);
    assert.equal(seen.deadlines.length, 3, 'every attempt carries its own deadline');
    assert.equal(waits.length, 2);
    assert.ok(waits.every((ms) => ms <= 20000), waits.join(', '));
  }));
}

test('Gemini model discovery is bounded', (t) => withServer(t, hang, async (seen, bounded) => {
  await assert.rejects(bounded(ask({ provider: 'gemini' }, REQUEST)), /no complete response within/);
  assert.deepEqual(seen.paths, ['GET /v1beta/models']);
}));

for (const provider of ['azure', 'deepgram', 'assemblyai']) {
  for (const [name, handler] of [['never answers', hang], ['stalls its body', stallBody]]) {
    test(`align --provider ${provider}: a service that ${name} is aborted and called once`, (t) => withServer(t, handler, async (seen, bounded) => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloud-timeouts-'));
      try {
        const take = path.join(dir, 'take.wav');
        const script = path.join(dir, 'script.txt');
        fs.writeFileSync(take, Buffer.alloc(64));
        fs.writeFileSync(script, 'hello');
        await assert.rejects(bounded(align({ take, script, out: path.join(dir, 'o.json'), provider })), /blocked \(timed out/);
        assert.equal(seen.paths.length, 1, seen.paths.join(', '));
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    }));
  }
}

const acceptTranscript = (req, res) => res.end(JSON.stringify(req.url === '/v2/upload' ? { upload_url: 'u' } : { id: 't1' }));

test('a hung status poll is polled again, so a paid transcript is neither abandoned nor submitted twice', (t) => withServer(t, (req, res, seen) => {
  if (req.method === 'POST') acceptTranscript(req, res);
  else if (seen.paths.filter((p) => p.startsWith('GET')).length > 1) res.end(JSON.stringify({ status: 'completed', audio_duration: 1, words: [] }));
}, async (seen, bounded) => {
  assert.equal((await bounded(assemblyaiWords(Buffer.alloc(8), { pollMs: 1 }))).durationSeconds, 1);
  assert.deepEqual(seen.paths, ['POST /v2/upload', 'POST /v2/transcript', 'GET /v2/transcript/t1', 'GET /v2/transcript/t1']);
}));

test('a status endpoint that always hangs ends at the poll deadline and names the paid transcript', (t) => withServer(t, (req, res) => {
  if (req.method === 'POST') acceptTranscript(req, res);
}, async (seen, bounded) => {
  await assert.rejects(bounded(assemblyaiWords(Buffer.alloc(8), { pollMs: 1, pollTimeoutMs: 250 })), /transcript t1 not completed within/);
  assert.ok(seen.deadlines.slice(2).every((ms) => ms <= 250), 'a poll never outlives the poll deadline');
}));

test('the deadline leaves room for the largest real request', () => {
  assert.equal(callDeadlineMs(0), 300_000);
  assert.ok(callDeadlineMs(32 * 1024 * 1024) > 400_000, 'a 32 MB vision request, the Anthropic maximum');
  assert.ok(callDeadlineMs(70_000_000) >= 580_000, 'a 70 MB narration WAV sent at 2 Mbit/s');
});

test('every fetch in kit/cloud passes an AbortSignal', () => {
  const bare = [];
  for (const file of fs.readdirSync(cloud).filter((f) => /[.](mjs|ps1)$/.test(f))) {
    const text = fs.readFileSync(path.join(cloud, file), 'utf8');
    for (const m of text.matchAll(/\bfetch(?:Impl)?\(/g)) {
      let end = m.index + m[0].length;
      for (let depth = 1; depth; end++) depth += { '(': 1, ')': -1 }[text[end]] || 0;
      if (!/\bsignal\b/.test(text.slice(m.index, end))) bare.push(`${file}:${text.slice(0, m.index).split('\n').length}`);
    }
  }
  assert.deepEqual(bare, []);
});
