import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseJsonc, parseToml } from '../../src/doctor/parsers.js';

test('parseJsonc accepts comments, trailing commas and a BOM, and keeps // inside strings', () => {
  const text = '\uFEFF{\n  // line comment\n  "servers": { /* block */ "a": { "url": "https://x.test//path", }, },\n}';
  assert.deepEqual(parseJsonc(text), { servers: { a: { url: 'https://x.test//path' } } });
});

test('parseJsonc keeps escaped quotes and commas inside strings', () => {
  assert.deepEqual(parseJsonc('{"a": "x\\",}", "b": [1,2,],}'), { a: 'x",}', b: [1, 2] });
});

test('parseToml reads the mcp_servers shape Codex and Grok write', () => {
  const toml = `
model = "gpt-5"   # trailing comment
[mcp_servers.playwright]
command = "npx"
args = [
  "-y",
  "@playwright/mcp@latest", # pinned below
]
startup_timeout_sec = 30
enabled = true

[mcp_servers.playwright.env]
DEBUG = 'pw:*'

[mcp_servers."remote one"]
url = "https://mcp.example.test/mcp"
bearer_token_env_var = "REMOTE_TOKEN"
env_http_headers = { "X-Org" = "ORG_ID", Other = "OTHER" }

[[profiles]]
name = "a"
[[profiles]]
name = "b"
`;
  const doc = parseToml(toml);
  assert.equal(doc.model, 'gpt-5');
  assert.deepEqual(doc.mcp_servers.playwright.args, ['-y', '@playwright/mcp@latest']);
  assert.equal(doc.mcp_servers.playwright.startup_timeout_sec, 30);
  assert.equal(doc.mcp_servers.playwright.enabled, true);
  assert.deepEqual(doc.mcp_servers.playwright.env, { DEBUG: 'pw:*' });
  assert.equal(doc.mcp_servers['remote one'].bearer_token_env_var, 'REMOTE_TOKEN');
  assert.deepEqual(doc.mcp_servers['remote one'].env_http_headers, { 'X-Org': 'ORG_ID', Other: 'OTHER' });
  assert.deepEqual(doc.profiles.map((p) => p.name), ['a', 'b']);
});

test('parseToml handles escapes, multi-line strings, dotted keys and Windows line endings', () => {
  const doc = parseToml('a.b = "C:\\\\tools\\\\x.exe"\r\nc = """\nline1\nline2"""\r\nd = \'\'\'raw\\n\'\'\'\r\ne = 1_000\r\nf = 1979-05-27T07:32:00Z\r\n');
  assert.equal(doc.a.b, 'C:\\tools\\x.exe');
  assert.equal(doc.c, 'line1\nline2');
  assert.equal(doc.d, 'raw\\n');
  assert.equal(doc.e, 1000);
  assert.equal(doc.f, '1979-05-27T07:32:00Z');
});

test('parseToml reports the line of a syntax error', () => {
  assert.throws(() => parseToml('ok = 1\nbroken = \n'), /line 2/);
});
