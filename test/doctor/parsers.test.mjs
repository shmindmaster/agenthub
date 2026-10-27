import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseJsonc, parseToml, TomlError } from '../../src/doctor/parsers.js';

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

// Characterization tests below pin parseToml's behaviour exactly as it stood
// before the function was decomposed into helpers, including the loose edges:
// re-opened tables merge, [a] after [[a]] targets the last entry, inline tables
// may span lines, unterminated multi-line basic strings do not fail, and the
// numeric fallbacks accept sloppy input. A diff here is a behaviour change.

/** Asserts that parseToml throws a TomlError with the exact message and line. */
function tomlError(input, message, line) {
  assert.throws(
    () => parseToml(input),
    (err) => err instanceof TomlError && err.message === `line ${line}: ${message}` && err.line === line,
  );
}

test('parseToml tables: dotted headers, quoted parts, comments and re-opening merge', () => {
  const doc = parseToml(`
[tool.agenthub]
debug = false

["weird name".sub]
x = 1

[tool.agenthub] # re-opening reuses the same table
more = true
`);
  assert.deepEqual(doc, {
    tool: { agenthub: { debug: false, more: true } },
    'weird name': { sub: { x: 1 } },
  });
});

test('parseToml quoted header keys are single parts, not dotted paths', () => {
  const doc = parseToml('["a.b"]\nx = 1\n[\'lit key\']\ny = 2\n');
  assert.deepEqual(doc, { 'a.b': { x: 1 }, 'lit key': { y: 2 } });
});

test('parseToml arrays of tables append entries and nested headers grow the last entry', () => {
  const doc = parseToml(`
[[profiles]]
name = "a"

[[profiles]]
name = "b"

[[profiles.tag]]
kind = "x"

[[a.b]]
x = 1
`);
  assert.deepEqual(doc.profiles, [{ name: 'a' }, { name: 'b', tag: [{ kind: 'x' }] }]);
  assert.deepEqual(doc.a, { b: [{ x: 1 }] });
});

test('parseToml [table] after [[array of tables]] or an inline table reuses that object', () => {
  const aot = parseToml('[[a]]\nx = 1\n[[a]]\ny = 2\n[a]\nz = 3\n');
  assert.deepEqual(aot, { a: [{ x: 1 }, { y: 2, z: 3 }] });
  const inline = parseToml('a = { x = 1 }\n[a]\ny = 2\n');
  assert.deepEqual(inline, { a: { x: 1, y: 2 } });
});

test('parseToml [[a.b]] under [a] nests an array of tables', () => {
  assert.deepEqual(parseToml('[a]\n[[a.b]]\nx = 1\n'), { a: { b: [{ x: 1 }] } });
});

test('parseToml dotted keys create tables, overwrite values and can clobber whole tables', () => {
  const doc = parseToml('a . b . c = 1\na.b.d = 2\na.b = 3\nq = 1\nq = 2\n');
  assert.deepEqual(doc, { a: { b: 3 }, q: 2 });
  assert.deepEqual(parseToml('a.b = 1\na = 2\n'), { a: 2 });
});

test('parseToml inline tables: empty, trailing comma, dotted and quoted keys, nesting', () => {
  const doc = parseToml(
    'empty = {}\nspaced = { }\ntrail = { a = 1, }\ndot = { b.c = 1 }\nquoted = { "x y" = 1, z = { w = [1, 2] } }\n',
  );
  assert.deepEqual(doc, {
    empty: {},
    spaced: {},
    trail: { a: 1 },
    dot: { b: { c: 1 } },
    quoted: { 'x y': 1, z: { w: [1, 2] } },
  });
});

test('parseToml inline tables may span lines with comments (looser than the spec)', () => {
  const doc = parseToml('a = {\n  b = 1, # comment\n  c = "x",\n}\n');
  assert.deepEqual(doc, { a: { b: 1, c: 'x' } });
});

test('parseToml arrays: empty, multi-line with comments, trailing comma, mixed types, nesting', () => {
  const doc = parseToml(
    'empty = []\nml = [\n  1, # one\n  2,\n]\nmixed = [1, "x", true]\nnested = [[1, 2], [3]]\n' +
      'inlineTables = [{ b = 1 }, { c = 2 }]\ncommentOnly = [# just a comment\n]\n',
  );
  assert.deepEqual(doc.empty, []);
  assert.deepEqual(doc.ml, [1, 2]);
  assert.deepEqual(doc.mixed, [1, 'x', true]);
  assert.deepEqual(doc.nested, [[1, 2], [3]]);
  assert.deepEqual(doc.inlineTables, [{ b: 1 }, { c: 2 }]);
  assert.deepEqual(doc.commentOnly, []);
});

test('parseToml parses a space-separated number pair in an array as one bare string', () => {
  assert.deepEqual(parseToml('a = [1 2]\n'), { a: ['1 2'] });
});

test('parseToml booleans are only the lowercase true and false', () => {
  const doc = parseToml('on = true\noff = false\nnotFlag = True\n');
  assert.equal(doc.on, true);
  assert.equal(doc.off, false);
  assert.equal(doc.notFlag, 'True');
});

test('parseToml numbers: signs, underscores, leading zeros, radix, exponents, inf and nan', () => {
  const doc = parseToml(
    [
      'i = 1',
      'neg = -1',
      'plus = +1',
      'grouped = 1_000',
      'sloppy = 1__0',
      'leading = _1',
      'zeros = 007',
      'hex = 0x1F',
      'plus_hex = +0x1F',
      'neg_hex = -0x1F',
      'octal = 0o17',
      'binary = 0b101',
      'float = 3.14',
      'float_grouped = 1_000.5',
      'exp = 1e6',
      'neg_exp = -2E-2',
      'inf = inf',
      'neg_inf = -inf',
      'plus_inf = +inf',
      'nan = nan',
    ].join('\n'),
  );
  assert.equal(doc.i, 1);
  assert.equal(doc.neg, -1);
  assert.equal(doc.plus, 1);
  assert.equal(doc.grouped, 1000);
  assert.equal(doc.sloppy, 10);
  assert.equal(doc.leading, 1);
  assert.equal(doc.zeros, 7);
  assert.equal(doc.hex, 31);
  assert.equal(doc.plus_hex, 31);
  assert.ok(Number.isNaN(doc.neg_hex));
  assert.equal(doc.octal, 15);
  assert.equal(doc.binary, 5);
  assert.equal(doc.float, 3.14);
  assert.equal(doc.float_grouped, 1000.5);
  assert.equal(doc.exp, 1000000);
  assert.equal(doc.neg_exp, -0.02);
  assert.equal(doc.inf, Infinity);
  assert.equal(doc.neg_inf, -Infinity);
  assert.equal(doc.plus_inf, Infinity);
  assert.ok(Number.isNaN(doc.nan));
});

test('parseToml keeps dates, times, fragments and unknown tokens as raw strings', () => {
  const doc = parseToml(
    'iso = 1979-05-27T07:32:00Z\nspace = 1979-05-27 07:32:00\ndate = 1979-05-27\ntime = 07:32:00\n' +
      'word = nope\nhalf = .5\ntrailing = 5.\n',
  );
  assert.equal(doc.iso, '1979-05-27T07:32:00Z');
  assert.equal(doc.space, '1979-05-27 07:32:00');
  assert.equal(doc.date, '1979-05-27');
  assert.equal(doc.time, '07:32:00');
  assert.equal(doc.word, 'nope');
  assert.equal(doc.half, '.5');
  assert.equal(doc.trailing, '5.');
});

test('parseToml basic strings: escapes, unicode, backslash-space and escaped newlines', () => {
  const doc = parseToml('s = "b\\bf\\ft\\tn\\nr\\rq\\"w\\\\z\\eq"\nu = "\\u00e9"\nbig = "\\U0001F600"\nspace = "x\\ y"\nnewline = "x\\\ny"');
  assert.equal(doc.s, 'b\bf\ft\tn\nr\rq"w\\z\x1bq');
  assert.equal(doc.u, 'é');
  assert.equal(doc.big, '😀');
  assert.equal(doc.space, 'xy');
  assert.equal(doc.newline, 'xy');
});

test('parseToml literal strings keep every character raw', () => {
  const doc = parseToml("path = 'C:\\tools\\x.exe'\nnoesc = 'a\\tb'\n");
  assert.equal(doc.path, 'C:\\tools\\x.exe');
  assert.equal(doc.noesc, 'a\\tb');
});

test('parseToml multi-line basic strings: newline trim, \\r kept, extra quotes, line-ending backslash', () => {
  const doc = parseToml(
    [
      'a = """',
      'line1',
      'line2',
      '"""',
      'b = """',
      '',
      'x',
      '"""',
      'c = """ab""""',
      'd = """x\r\ny"""',
      'e = """one',
      'two\\',
      '   three"""',
      'f = """unterminated',
    ].join('\n'),
  );
  assert.equal(doc.a, 'line1\nline2\n');
  assert.equal(doc.b, '\nx\n');
  assert.equal(doc.c, 'ab"');
  assert.equal(doc.d, 'x\r\ny');
  assert.equal(doc.e, 'one\ntwothree');
  assert.equal(doc.f, 'unterminated');
});

test('parseToml multi-line literal strings stay raw and allow one extra closing quote', () => {
  const doc = parseToml("a = '''\nraw\\nno-esc\n'''\nb = '''ab''''\n");
  assert.equal(doc.a, 'raw\\nno-esc\n');
  assert.equal(doc.b, "ab'");
});

test('parseToml quoted assignment keys keep spaces and escapes', () => {
  assert.deepEqual(parseToml('"a b" = 1\n\'c d\' = 2\n"e\\"f" = 3\n'), { 'a b': 1, 'c d': 2, 'e"f': 3 });
});

test('parseToml accepts a BOM, comment-only and empty input, and a missing final newline', () => {
  assert.deepEqual(parseToml('\uFEFFa = 1'), { a: 1 });
  assert.deepEqual(parseToml('# only a comment\n\n# another\n'), {});
  assert.deepEqual(parseToml(''), {});
  assert.deepEqual(parseToml('a = 1'), { a: 1 });
});

test('parseToml handles CRLF line endings in values, headers and comments', () => {
  const doc = parseToml('a = 1 # c\r\n[b] # t\r\nc = "x"\r\n');
  assert.deepEqual(doc, { a: 1, b: { c: 'x' } });
});

test('TomlError is an exported Error subclass carrying the offending line', () => {
  try {
    parseToml('a = 1\nbroken = \n');
    assert.fail('expected parseToml to throw');
  } catch (err) {
    assert.ok(err instanceof TomlError);
    assert.ok(err instanceof Error);
    assert.equal(err.line, 2);
    assert.equal(err.message, 'line 2: expected a value');
  }
});

test('parseToml errors report the exact message and line', () => {
  tomlError('a = 1\nb = "x\ny"', 'newline in string', 2);
  tomlError('a = "abc', 'unterminated string', 1);
  tomlError("a = 'abc", 'unterminated literal string', 1);
  tomlError("a = '''abc", 'unterminated literal string', 1);
  tomlError('ok = 1\nbad = "x\\q"', 'bad escape \\q', 2);
  tomlError('= 1', "expected a key, found '='", 1);
  tomlError('.a = 1', "expected a key, found '.'", 1);
  tomlError('a.', "expected a key, found 'end of file'", 1);
  tomlError('a 1', 'expected =', 1);
  tomlError('ok = 1\nbroken = ', 'expected a value', 2);
  tomlError('a = 1 b = 2', "unexpected 'b'", 1);
  tomlError('[a] b = 1', "unexpected 'b'", 1);
  tomlError('[ ]', "expected a key, found ']'", 1);
  tomlError('[a', 'unterminated table header', 1);
  tomlError('[[a]', 'unterminated table header', 1);
  tomlError('ok = 1\nok2 = 2\n[a\nb = 1', 'unterminated table header', 3);
  tomlError('a = 1\n[a.b]\nx = 2', "'a' is not a table", 2);
  tomlError('[a]\nx = 1\n[[a]]\ny = 2', "'a' is not an array of tables", 3);
  tomlError('a = 1\na.b = 2', "key 'a' is not a table", 2);
  tomlError('a = [1]\na.b = 2', "key 'a' is not a table", 2);
  tomlError('a = { b }', 'expected = in inline table', 1);
  tomlError('a = { b = 1 c = 2 }', 'expected , or } in inline table', 1);
  tomlError('a = ["one" "two"]', 'expected , or ] in array', 1);
});
