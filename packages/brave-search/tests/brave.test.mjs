import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { buildRequest, clean, finish, parseArgs, project, readKey, renderAnswer, resolveBase } from '../skills/search/scripts/brave.mjs';

const SCRIPT = fileURLToPath(new URL('../skills/search/scripts/brave.mjs', import.meta.url));
const FAKE_KEY = 'test-key-0000';

function startServer(handler) {
  return new Promise((resolve) => {
    const seen = [];
    const server = createServer(async (req, res) => {
      let body = '';
      for await (const chunk of req) body += chunk;
      seen.push({ method: req.method, url: req.url, headers: req.headers, body });
      handler(req, res, body);
    });
    server.listen(0, '127.0.0.1', () => resolve({ server, seen, base: `http://127.0.0.1:${server.address().port}/res/v1` }));
  });
}

function run(args, env) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [SCRIPT, ...args], {
      env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

test('parseArgs handles values, equals form, booleans and repeats', () => {
  const { positional, flags } = parseArgs(['web', 'rust', 'async', '--count', '5', '--freshness=pw', '--raw', '--ids', 'a', '--ids', 'b']);
  assert.deepEqual(positional, ['web', 'rust', 'async']);
  assert.deepEqual(flags.count, ['5']);
  assert.deepEqual(flags.freshness, ['pw']);
  assert.deepEqual(flags.raw, [true]);
  assert.deepEqual(flags.ids, ['a', 'b']);
});

test('parseArgs rejects a flag with no value', () => {
  assert.throws(() => parseArgs(['web', 'x', '--count']), /needs a value/);
});

test('readKey prefers BRAVE_SEARCH_API_KEY, falls back to BRAVE_API_KEY, and never leaks in the error', () => {
  assert.equal(readKey({ BRAVE_SEARCH_API_KEY: 'a', BRAVE_API_KEY: 'b' }), 'a');
  assert.equal(readKey({ BRAVE_API_KEY: 'b' }), 'b');
  assert.throws(() => readKey({}), /No Brave key found/);
});

test('resolveBase honours only loopback http overrides', () => {
  assert.equal(resolveBase({}), 'https://api.search.brave.com/res/v1');
  assert.equal(resolveBase({ BRAVE_SEARCH_API_BASE: 'http://127.0.0.1:9/res/v1' }), 'http://127.0.0.1:9/res/v1');
  assert.throws(() => resolveBase({ BRAVE_SEARCH_API_BASE: 'https://evil.example/res/v1' }), /honoured only/);
  assert.throws(() => resolveBase({ BRAVE_SEARCH_API_BASE: 'http://evil.example/res/v1' }), /honoured only/);
});

test('buildRequest maps flags to params, headers and the key header', () => {
  const { positional, flags } = parseArgs(['web', 'rust lang', '--count', '5', '--loc-lat', '37.7', '--maximum-number-of-tokens', '2048']);
  const req = buildRequest('web', positional.slice(1), flags, { BRAVE_SEARCH_API_KEY: FAKE_KEY });
  const url = new URL(req.url);
  assert.equal(url.pathname, '/res/v1/web/search');
  assert.equal(url.searchParams.get('q'), 'rust lang');
  assert.equal(url.searchParams.get('count'), '5');
  assert.equal(url.searchParams.get('maximum_number_of_tokens'), '2048');
  assert.equal(req.init.headers['X-Loc-Lat'], '37.7');
  assert.equal(req.init.headers['X-Subscription-Token'], FAKE_KEY);
  assert.ok(!req.url.includes(FAKE_KEY), 'the key must never appear in the URL');
});

test('buildRequest sends repeated ids for pois and requires them', () => {
  const { flags } = parseArgs([]);
  const req = buildRequest('pois', ['id1', 'id2'], flags, { BRAVE_API_KEY: FAKE_KEY });
  assert.deepEqual(new URL(req.url).searchParams.getAll('ids'), ['id1', 'id2']);
  assert.throws(() => buildRequest('pois', [], flags, { BRAVE_API_KEY: FAKE_KEY }), /needs one or more POI ids/);
});

test('buildRequest rejects unknown commands and empty queries', () => {
  const { flags } = parseArgs([]);
  assert.throws(() => buildRequest('nope', ['x'], flags, { BRAVE_API_KEY: FAKE_KEY }), /Unknown command/);
  assert.throws(() => buildRequest('web', [], flags, { BRAVE_API_KEY: FAKE_KEY }), /needs a query/);
});

test('answers builds a streaming research body and keeps tuning flags in the body', () => {
  const { positional, flags } = parseArgs(['answers', 'compare x', '--research', '--research-maximum-number-of-seconds', '90']);
  const req = buildRequest('answers', positional.slice(1), flags, { BRAVE_API_KEY: FAKE_KEY });
  const body = JSON.parse(req.init.body);
  assert.equal(req.init.method, 'POST');
  assert.equal(body.stream, true);
  assert.equal(body.enable_research, true);
  assert.equal(body.research_maximum_number_of_seconds, 90);
  assert.equal(body.messages[0].content, 'compare x');
});

test('project trims context, web, news, images and places, and falls back to raw', () => {
  const ctx = project('context', { grounding: { generic: [{ url: 'u', title: 't', snippets: ['s'], extra: 1 }] }, sources: { u: { title: 't' } } });
  assert.deepEqual(ctx.results, [{ url: 'u', title: 't', snippets: ['s'] }]);
  const web = project('web', { web: { results: [{ title: 'a', url: 'u', description: 'd', meta_url: { hostname: 'h' }, junk: 1 }] }, query: { altered: 'fixed' } });
  assert.deepEqual(web.web[0], { title: 'a', url: 'u', description: 'd', hostname: 'h' });
  assert.equal(web.corrected_query, 'fixed');
  assert.deepEqual(project('news', { results: [{ title: 'n', url: 'u', age: '1 hour ago', thumbnail: {} }] }), [{ title: 'n', url: 'u', age: '1 hour ago' }]);
  const img = project('images', { results: [{ title: 'i', url: 'page', source: 's', thumbnail: { src: 'th' }, properties: { url: 'full' } }] });
  assert.deepEqual(img[0], { title: 'i', source: 's', page: 'page', image: 'full', thumbnail: 'th' });
  const places = project('places', { results: [{ id: 'p1', title: 'Cafe', postal_address: { displayAddress: '1 Main' }, rating: { ratingValue: 4.5 } }] });
  assert.equal(places.results[0].displayAddress, '1 Main');
  assert.deepEqual(project('web', { surprise: true }), { surprise: true });
});

test('clean strips highlight tags and decodes entities, and leaves unknown ones alone', () => {
  assert.equal(clean('Modern apps &amp; <strong>React</strong> &#39;x&#39; &#x41; &unknown; &#0;'), "Modern apps & React 'x' A &unknown; &#0;");
  assert.deepEqual(clean(['<b>a</b>', 'b &lt; c']), ['a', 'b < c']);
  assert.equal(clean(5), 5);
  const web = project('web', { web: { results: [{ title: 'A &amp; B', url: 'https://x', description: 'see <strong>this</strong>' }] } });
  assert.equal(web.web[0].title, 'A & B');
  assert.equal(web.web[0].description, 'see this');
});

test('renderAnswer reads blocking and streaming research responses', () => {
  assert.equal(renderAnswer(JSON.stringify({ choices: [{ message: { content: 'hello' } }] }), false, false, false), 'hello');
  const chunks = [
    `data: ${JSON.stringify({ choices: [{ delta: { content: '<progress>x</progress><answer>Final text</answer>' } }] })}`,
    `data: ${JSON.stringify({ choices: [{ delta: { content: '<blindspots>gap</blindspots><usage>{"X-Request-Total-Cost":0.12}</usage>' } }] })}`,
    'data: [DONE]',
  ].join('\n\n');
  const out = renderAnswer(chunks, true, true, false);
  assert.match(out, /^Final text/);
  assert.match(out, /Blind spots: gap/);
  assert.match(out, /Cost: 0\.12/);
});

test('finish truncates with a visible marker', () => {
  assert.equal(finish('abc', 10), 'abc');
  assert.match(finish('x'.repeat(50), 10), /\[truncated 40 chars/);
});

test('end to end: sends the key header, trims output, and keeps the key off stdout and stderr', async () => {
  const { server, seen, base } = await startServer((_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json', 'x-ratelimit-remaining': '41' });
    res.end(JSON.stringify({ grounding: { generic: [{ url: 'https://example.com', title: 'Example', snippets: ['alpha'] }] }, sources: {} }));
  });
  try {
    const result = await run(['context', 'what is alpha', '--count', '3'], { BRAVE_SEARCH_API_KEY: FAKE_KEY, BRAVE_SEARCH_API_BASE: base });
    assert.equal(result.code, 0, result.stderr);
    assert.equal(seen[0].headers['x-subscription-token'], FAKE_KEY);
    assert.equal(new URL(seen[0].url, 'http://x').searchParams.get('count'), '3');
    assert.match(result.stdout, /alpha/);
    assert.match(result.stderr, /rate-limit remaining: 41/);
    assert.ok(!result.stdout.includes(FAKE_KEY) && !result.stderr.includes(FAKE_KEY));
  } finally {
    server.close();
  }
});

test('end to end: 429 and 401 give actionable messages without the key', async () => {
  const { server, base } = await startServer((req, res) => {
    if (req.url.includes('limited')) {
      res.writeHead(429, { 'x-ratelimit-reset': '7' });
    } else {
      res.writeHead(401);
    }
    res.end('{"error":"nope"}');
  });
  try {
    const limited = await run(['web', 'limited'], { BRAVE_SEARCH_API_KEY: FAKE_KEY, BRAVE_SEARCH_API_BASE: base });
    assert.equal(limited.code, 1);
    assert.match(limited.stderr, /429/);
    assert.match(limited.stderr, /resets in 7s/);
    const denied = await run(['web', 'denied'], { BRAVE_SEARCH_API_KEY: FAKE_KEY, BRAVE_SEARCH_API_BASE: base });
    assert.equal(denied.code, 1);
    assert.match(denied.stderr, /rejected or the plan lacks/);
    assert.ok(!limited.stderr.includes(FAKE_KEY) && !denied.stderr.includes(FAKE_KEY));
  } finally {
    server.close();
  }
});

test('end to end: a redirect is refused so the key cannot follow it', async () => {
  const { server, base } = await startServer((_req, res) => {
    res.writeHead(302, { location: 'http://127.0.0.1:1/steal' });
    res.end();
  });
  try {
    const result = await run(['web', 'x'], { BRAVE_SEARCH_API_KEY: FAKE_KEY, BRAVE_SEARCH_API_BASE: base });
    assert.equal(result.code, 1);
    assert.match(result.stderr, /Request failed/);
    assert.ok(!result.stderr.includes(FAKE_KEY));
  } finally {
    server.close();
  }
});

test('missing key exits 1 with a message that names the variables, not a value', async () => {
  const result = await run(['web', 'x'], {});
  assert.equal(result.code, 1);
  assert.match(result.stderr, /BRAVE_SEARCH_API_KEY/);
});

test('output is capped by --max-chars', async () => {
  const { server, base } = await startServer((_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ web: { results: Array.from({ length: 50 }, (_, i) => ({ title: `T${i}`, url: `https://e.com/${i}`, description: 'd'.repeat(100) })) } }));
  });
  try {
    const result = await run(['web', 'x', '--max-chars', '300'], { BRAVE_SEARCH_API_KEY: FAKE_KEY, BRAVE_SEARCH_API_BASE: base });
    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /\[truncated \d+ chars/);
  } finally {
    server.close();
  }
});
