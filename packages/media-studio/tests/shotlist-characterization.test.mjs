// Characterization tests for parseShotList / resolveCue / filesToRead.
// They pin the CURRENT behavior (error text and order, defaults, return shapes, timeline pacing, whitespace and
// boundary handling) so a refactor of shotlist.mjs can be proven behavior-preserving. Run:
//   node --test packages/media-studio/tests/shotlist-characterization.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseShotList, resolveCue, ShotListError, filesToRead, SCHEMA_VERSION } from '../kit/code-stage/shotlist.mjs';

const code = (extra = {}) => ({ id: 'S01', file: 'src/gate.py', lines: [1, 8], highlight: [[3, 4]], callout: { line: 4, text: 'nothing executes without this' }, ...extra });
const doc = (shots, extra = {}) => ({ repo: 'C:/repo', ref: 'main', shots, ...extra });
const node = (id, extra = {}) => ({ id, label: id.toUpperCase(), ...extra });
const diagram = (extra = {}) => ({ id: 'D01', kind: 'diagram', nodes: [node('a'), node('b')], ...extra });
const errorsOf = (d, o) => { try { parseShotList(d, o); } catch (e) { assert.ok(e instanceof ShotListError, e.message); return e.errors; } assert.fail('expected ShotListError'); };
const shotOf = (s, o) => parseShotList(doc([s]), o).shots[0];
const times = (s) => Object.fromEntries(s.events.map((e) => [e.event, e.t]));
const ID_RE = '/^[A-Za-z][A-Za-z0-9_-]{0,31}$/';

// ---- document level ----
test('input: JSON string (with BOM) parses to the same normalized document as the object', () => {
  const d = doc([code()], { title: 'T', refLabel: 'v1' });
  const a = parseShotList(d);
  assert.deepEqual(parseShotList(JSON.stringify(d)), a);
  assert.deepEqual(parseShotList('\uFEFF' + JSON.stringify(d)), a);
  assert.deepEqual([a.schemaVersion, a.repo, a.ref, a.refLabel, a.title], [SCHEMA_VERSION, 'C:/repo', 'main', 'v1', 'T']);
});

test('input: invalid JSON text surfaces the SyntaxError, non-objects raise ShotListError', () => {
  assert.throws(() => parseShotList('not json'), SyntaxError);
  for (const bad of [null, 42, 'null', '0', undefined]) assert.deepEqual(errorsOf(bad), ['shot list must be a JSON object']);
});

test('ShotListError: message joins errors with a bullet list and keeps .errors', () => {
  const e = new ShotListError(['a', 'b']);
  assert.equal(e.message, 'invalid shot list:\n  - a\n  - b');
  assert.deepEqual(e.errors, ['a', 'b']);
  assert.ok(e instanceof Error);
});

test('document defaults: ref HEAD, viewport 1280x800, title empty, refLabel null unless a string, repo null for diagram-only', () => {
  const p = parseShotList({ repo: 'r', shots: [code()] });
  assert.deepEqual([p.ref, p.viewport, p.title, p.refLabel], ['HEAD', { width: 1280, height: 800 }, '', null]);
  assert.equal(p.shots[0].ref, 'HEAD');
  assert.equal(parseShotList(doc([code()], { refLabel: 123 })).refLabel, null);
  assert.equal(parseShotList({ shots: [diagram()] }).repo, null);
  assert.deepEqual(parseShotList(doc([code()], { viewport: { width: 1920, height: 1080 } })).viewport, { width: 1920, height: 1080 });
});

test('schemaVersion: same major is accepted (output stays 1.0.0), other major is rejected verbatim', () => {
  assert.equal(parseShotList(doc([code()], { schemaVersion: '1.9.9' })).schemaVersion, '1.0.0');
  assert.deepEqual(errorsOf(doc([code()], { schemaVersion: '2.0' })), ['schemaVersion 2.0 is not compatible with 1.0.0']);
  assert.deepEqual(errorsOf(doc([code()], { schemaVersion: 3 })), ['schemaVersion 3 is not compatible with 1.0.0']);
});

test('repo is required only when some shot is (or defaults to) a code shot', () => {
  const msg = 'repo (absolute path to the git repository, read-only) is required for code shots';
  assert.deepEqual(errorsOf({ shots: [code()] }), [msg]);
  assert.deepEqual(errorsOf({ repo: '', shots: [code()] }), [msg]);
  assert.deepEqual(errorsOf({ repo: 7, shots: [code()] }), [msg]);
  assert.deepEqual(errorsOf({ shots: [diagram(), { id: 'S2', file: 'f', lines: [1, 1] }] }), [msg]);
});

test('viewport: both dimensions must be positive integers', () => {
  const msg = 'viewport must be {width, height}';
  for (const v of [{ width: 1280 }, { width: 0, height: 800 }, { width: 1.5, height: 2 }, { width: '1280', height: 800 }, 'wide']) assert.deepEqual(errorsOf(doc([code()], { viewport: v })), [msg]);
});

test('shots must be a non-empty array; a null shot is reported without demanding a repo', () => {
  assert.deepEqual(errorsOf({ repo: 'r', shots: [] }), ['shots must be a non-empty array']);
  assert.deepEqual(errorsOf({ repo: 'r' }), ['shots must be a non-empty array']);
  assert.deepEqual(errorsOf({ shots: [null] }), ['shots[0] must be an object']);
  assert.deepEqual(errorsOf(doc([42, code()])), ['shots[0] must be an object']);
});

test('quirk: a non-array truthy shots value throws a TypeError rather than a ShotListError', () => {
  assert.throws(() => parseShotList({ repo: 'r', shots: 'nope' }), TypeError);
  assert.throws(() => parseShotList({ repo: 'r', shots: { a: 1 } }), TypeError);
});

test('errors are reported in document order: doc-level first, then each shot in order', () => {
  assert.deepEqual(errorsOf({ schemaVersion: '9', viewport: {}, shots: [code({ id: '1x', zoom: 5 }), { id: 'S2', kind: 'video' }] }), [
    'schemaVersion 9 is not compatible with 1.0.0',
    'repo (absolute path to the git repository, read-only) is required for code shots',
    'viewport must be {width, height}',
    `shots[0] (1x).id must match ${ID_RE}`,
    'shots[0] (1x).zoom must be 1.0-2.2',
    'shots[1] (S2).kind must be "code" or "diagram"',
  ]);
});

// ---- ids, kind inference, common shot fields ----
test('shot id: pattern, 32 char limit, duplicates', () => {
  assert.equal(shotOf(code({ id: 'a' + 'b'.repeat(31) })).id.length, 32);
  assert.deepEqual(errorsOf(doc([code({ id: 'a' + 'b'.repeat(32) })])), [`shots[0] (${'a' + 'b'.repeat(32)}).id must match ${ID_RE}`]);
  assert.deepEqual(errorsOf(doc([code({ id: undefined })])), [`shots[0].id must match ${ID_RE}`]);
  assert.deepEqual(errorsOf(doc([code({ id: 7 })])), [`shots[0] (7).id must match ${ID_RE}`]);
  assert.deepEqual(errorsOf(doc([code({ id: 'a-1_B' }), code({ id: 'a-1_B' }), code({ id: 'other' })])), ['shots[1] (a-1_B).id is duplicated']);
});

test('kind is inferred: nodes => diagram, otherwise code; explicit kind wins; unknown kind is rejected and skips cues', () => {
  assert.equal(shotOf({ id: 'S', file: 'f', lines: [1, 2] }).kind, 'code');
  assert.equal(parseShotList({ shots: [{ id: 'D', nodes: [node('a'), node('b')] }] }).shots[0].kind, 'diagram');
  assert.deepEqual(errorsOf(doc([code({ kind: 'video', cues: [{ event: 'nope', at: 1 }], holdSeconds: 9 })])), [
    'shots[0] (S01).holdSeconds must be 0-8 (visual bible: no dead hold over 8 s)',
    'shots[0] (S01).kind must be "code" or "diagram"',
  ]);
});

test('holdSeconds: default 1.5, 0..8 inclusive, otherwise the exact message', () => {
  const msg = (w) => `${w}.holdSeconds must be 0-8 (visual bible: no dead hold over 8 s)`;
  assert.equal(shotOf(code()).holdSeconds, 1.5);
  assert.equal(shotOf(code({ holdSeconds: null })).holdSeconds, 1.5);
  assert.equal(shotOf(code({ holdSeconds: 0 })).holdSeconds, 0);
  assert.equal(shotOf(code({ holdSeconds: 8 })).holdSeconds, 8);
  for (const h of [8.01, -0.1, '2']) assert.deepEqual(errorsOf(doc([code({ holdSeconds: h })])), [msg('shots[0] (S01)')]);
});

// ---- code shot: file, lines, highlight ----
test('file: separators are normalized to forward slashes; non-strings pass through untouched', () => {
  assert.equal(shotOf(code({ file: 'src\\deep\\gate.py' })).file, 'src/deep/gate.py');
  assert.equal(shotOf(code({ file: 'a..b/c.py' })).file, 'a..b/c.py');
  assert.deepEqual(errorsOf(doc([code({ file: undefined })])), ['shots[0] (S01).file must be a repo-relative path without ".." (got undefined)']);
});

test('file: absolute, drive, rooted and traversal paths are rejected with the quoted value', () => {
  for (const f of ['C:/abs/gate.py', 'c:rel.py', '/etc/passwd', '\\share\\x', '../outside.py', 'a/../b.py', 'a\\..\\b.py', '..', '', 5]) {
    assert.deepEqual(errorsOf(doc([code({ file: f })])), [`shots[0] (S01).file must be a repo-relative path without ".." (got ${JSON.stringify(f)})`], String(f));
  }
});

test('lines: must be an ordered pair of positive integers spanning at most 60', () => {
  const bad = 'shots[0] (S01).lines must be [start, end] 1-based with start <= end';
  for (const l of [undefined, [5, 2], [0, 3], [1.5, 3], [1], [1, 2, 3], 'x']) assert.deepEqual(errorsOf(doc([code({ lines: l, highlight: [], callout: null })])), [bad], JSON.stringify(l));
  assert.deepEqual(shotOf(code({ lines: [10, 69], highlight: [], callout: null })).lines, [10, 69]);
  assert.deepEqual(errorsOf(doc([code({ lines: [10, 70], highlight: [], callout: null })])), ['shots[0] (S01).lines spans 61 lines; a walkthrough shot shows at most 60']);
});

test('highlight: defaults to [], is copied, invalid and out-of-range entries are reported and dropped', () => {
  assert.deepEqual(shotOf(code({ highlight: undefined })).highlight, []);
  const input = [[1, 2], [3, 8]];
  const out = shotOf(code({ highlight: input })).highlight;
  assert.deepEqual(out, input);
  assert.notEqual(out[0], input[0]);
  assert.deepEqual(errorsOf(doc([code({ highlight: 'x' })])), ['shots[0] (S01).highlight must be an array of [start, end]']);
  assert.deepEqual(errorsOf(doc([code({ highlight: [[1, 2], [4, 3], [7, 9], 'z'] })])), [
    'shots[0] (S01).highlight[1] must be [start, end]',
    'shots[0] (S01).highlight[2] 7-9 is outside lines 1-8',
    'shots[0] (S01).highlight[3] must be [start, end]',
  ]);
});

test('highlight outside check is skipped when lines are invalid (only the lines error is reported)', () => {
  assert.deepEqual(errorsOf(doc([code({ lines: undefined, highlight: [[50, 60]], callout: null })])), ['shots[0] (S01).lines must be [start, end] 1-based with start <= end']);
});

// ---- code shot: callout, zoom, startLine, pointer ----
test('callout: null when absent, text trimmed, 90 chars allowed, output is a fresh {line,text}', () => {
  assert.equal(shotOf(code({ callout: undefined })).callout, null);
  assert.deepEqual(shotOf(code({ callout: { line: 4, text: '  spaced  ', extra: 1 } })).callout, { line: 4, text: 'spaced' });
  assert.equal(shotOf(code({ callout: { line: 4, text: 'x'.repeat(90) } })).callout.text.length, 90);
});

test('callout: every failure mode has its exact message', () => {
  const w = 'shots[0] (S01)';
  for (const c of ['str', { line: 4 }, { line: 4, text: '   ' }, { line: 0, text: 'x' }, { line: 4, text: 5 }]) assert.deepEqual(errorsOf(doc([code({ callout: c })])), [`${w}.callout needs {line, text}`]);
  assert.deepEqual(errorsOf(doc([code({ callout: { line: 9, text: 'x' } })])), [`${w}.callout.line 9 is outside lines 1-8`]);
  assert.deepEqual(errorsOf(doc([code({ callout: { line: 4, text: 'x'.repeat(91) } })])), [`${w}.callout.text is 91 chars; keep it under 90`]);
  assert.deepEqual(errorsOf(doc([code({ callout: { line: 9, text: 'y'.repeat(100) } })])), [`${w}.callout.line 9 is outside lines 1-8`, `${w}.callout.text is 100 chars; keep it under 90`]);
});

test('zoom: default 1.4, inclusive 1.0..2.2, otherwise the exact message', () => {
  assert.equal(shotOf(code()).zoom, 1.4);
  assert.equal(shotOf(code({ zoom: null })).zoom, 1.4);
  assert.equal(shotOf(code({ zoom: 1 })).zoom, 1);
  assert.equal(shotOf(code({ zoom: 2.2 })).zoom, 2.2);
  for (const z of [0.99, 2.21, '1.5']) assert.deepEqual(errorsOf(doc([code({ zoom: z })])), ['shots[0] (S01).zoom must be 1.0-2.2']);
});

test('startLine: null by default, positive integer accepted, anything else rejected', () => {
  assert.equal(shotOf(code()).startLine, null);
  assert.equal(shotOf(code({ startLine: 1 })).startLine, 1);
  for (const v of [0, 1.5, 'a', -2]) assert.deepEqual(errorsOf(doc([code({ startLine: v })])), ['shots[0] (S01).startLine must be a 1-based line number']);
});

test('pointer: null by default, click defaults to true, explicit false kept, bounds use startLine when lower', () => {
  assert.equal(shotOf(code()).pointer, null);
  assert.deepEqual(shotOf(code({ pointer: [{ line: 3 }, { line: 5, click: false }, { line: 6, click: 0 }] })).pointer, [{ line: 3, click: true }, { line: 5, click: false }, { line: 6, click: true }]);
  assert.deepEqual(shotOf(code({ lines: [5, 8], highlight: [], callout: null, startLine: 2, pointer: [{ line: 3 }] })).pointer, [{ line: 3, click: true }]);
  const msg = (i) => `shots[0] (S01).pointer[${i}] needs a line between startLine/lines start and lines end`;
  assert.deepEqual(errorsOf(doc([code({ pointer: [{ line: 100 }, { line: 1.5 }, { line: 0 }, {}, null] })])), [0, 1, 2, 3, 4].map(msg));
  assert.deepEqual(errorsOf(doc([code({ lines: [5, 8], highlight: [], callout: null, pointer: [{ line: 4 }] })])), [msg(0)]);
  assert.equal(shotOf(code({ pointer: 'x' })).pointer, null);
});

// ---- cross-refs ----
test('crossRef: spellings, array form, key precedence and normalization', () => {
  const x = { file: 'web\\a.ts', lines: [10, 20] };
  assert.equal(shotOf(code({ crossRef: x })).crossRefs.length, 1);
  assert.equal(shotOf(code({ 'cross-ref': x })).crossRefs[0].file, 'web/a.ts');
  assert.equal(shotOf(code({ crossRef: null, 'cross-ref': x })).crossRefs.length, 1);
  assert.equal(shotOf(code({ crossRef: x, 'cross-ref': [x, x] })).crossRefs.length, 1);
  assert.deepEqual(shotOf(code()).crossRefs, []);
  assert.equal(shotOf(code({ crossRef: [x, { file: 'b.ts', lines: [1, 2] }] })).crossRefs[1].file, 'b.ts');
  assert.deepEqual(shotOf(code({ ref: 'dev', crossRef: x })).crossRefs[0], { file: 'web/a.ts', ref: 'dev', lines: [10, 20], highlight: [[10, 20]], callout: null, label: null });
});

test('crossRef: own ref and label, explicit highlight replaces the whole-span default', () => {
  const s = shotOf(code({ crossRef: { file: 'a.ts', ref: 'v2', lines: [10, 20], highlight: [[12, 13]], label: 'Button', callout: { line: 11, text: ' ok ' } } }));
  assert.deepEqual(s.crossRefs[0], { file: 'a.ts', ref: 'v2', lines: [10, 20], highlight: [[12, 13]], callout: { line: 11, text: 'ok' }, label: 'Button' });
});

test('crossRef: errors carry the crossRef[i] prefix; unusable entries are dropped from the output', () => {
  const w = 'shots[0] (S01).crossRef';
  assert.deepEqual(errorsOf(doc([code({ crossRef: 'nope' })])), [`${w}[0] must be an object`]);
  assert.deepEqual(errorsOf(doc([code({ crossRef: { file: '../x', lines: [1, 2], highlight: [[3, 4]], callout: { line: 5, text: 'x' } } })])), [
    `${w}[0].file must be a repo-relative path without ".." (got "../x")`,
    `${w}[0].highlight[0] 3-4 is outside lines 1-2`,
    `${w}[0].callout.line 5 is outside lines 1-2`,
  ]);
  assert.deepEqual(errorsOf(doc([code({ crossRef: [{ file: 'a.ts' }, null] })])), [`${w}[0].lines must be [start, end] 1-based with start <= end`, `${w}[1] must be an object`]);
  assert.deepEqual(errorsOf(doc([code({ crossRef: { file: 'a.ts', lines: [1, 61] } })])), [`${w}[0].lines spans 61 lines; a walkthrough shot shows at most 60`]);
});

// ---- default timelines and durations ----
test('code timeline: exact default pacing for pointer, highlight, callout and cross-ref events', () => {
  const s = shotOf(code({ pointer: [{ line: 3 }], crossRef: [{ file: 'a.ts', lines: [10, 20], callout: { line: 12, text: 'c' } }, { file: 'b.ts', lines: [1, 2] }] }));
  assert.deepEqual(s.events, [
    { event: 'reveal', t: 0.4 },
    { event: 'pointer:0', t: 2 },
    { event: 'highlight:0', t: 3.2 },
    { event: 'callout', t: 5.7 },
    { event: 'crossref:0', t: 8.2 },
    { event: 'crossref:0:highlight', t: 10.399999999999999 }, // float accumulation is part of the contract
    { event: 'crossref:0:callout', t: 12.2 },
    { event: 'crossref:1', t: 14.7 },
    { event: 'crossref:1:highlight', t: 16.9 },
  ]);
  assert.equal(s.durationSeconds, 18.4);
});

test('code timeline: a bare shot has only reveal; duration is last event + hold, floored by targetSeconds', () => {
  const bare = shotOf(code({ highlight: [], callout: null }));
  assert.deepEqual(bare.events, [{ event: 'reveal', t: 0.4 }]);
  assert.equal(bare.durationSeconds, 1.9);
  assert.equal(bare.targetSeconds, null);
  assert.equal(shotOf(code({ targetSeconds: 10 })).durationSeconds, 10);
  assert.equal(shotOf(code({ targetSeconds: 1 })).durationSeconds, 6);
  assert.equal(shotOf(code({ holdSeconds: 0 })).durationSeconds, 4.5);
});

test('diagram timeline: node events 1s apart from 0.5s, lit 0.4s after the last slot', () => {
  const s = parseShotList({ shots: [diagram({ nodes: [node('a'), node('b'), node('c')], lit: 'c' })] }).shots[0];
  assert.deepEqual(s.events, [{ event: 'node:a', t: 0.5 }, { event: 'node:b', t: 1.5 }, { event: 'node:c', t: 2.5 }, { event: 'lit', t: 3.9 }]);
  assert.equal(s.durationSeconds, 5.4);
});

// ---- diagram shot ----
test('diagram: full normalized output shape with defaults', () => {
  const s = parseShotList({ shots: [diagram({ nodes: [node('a', { sub: 'x' }), node('b'), node('c')] })] }).shots[0];
  assert.deepEqual(s, {
    id: 'D01', kind: 'diagram', holdSeconds: 1.5, targetSeconds: null,
    title: '', kicker: '', footer: '',
    nodes: [{ id: 'a', label: 'A', sub: 'x' }, { id: 'b', label: 'B', sub: '' }, { id: 'c', label: 'C', sub: '' }],
    edges: [{ from: 'a', to: 'b', label: '' }, { from: 'b', to: 'c', label: '' }],
    lit: null, litChip: null,
    events: [{ event: 'node:a', t: 0.5 }, { event: 'node:b', t: 1.5 }, { event: 'node:c', t: 2.5 }],
    durationSeconds: 4,
  });
});

test('diagram: title, kicker, footer, litChip, explicit edges and lit pass through', () => {
  const s = parseShotList({ shots: [diagram({ title: 'T', kicker: 'K', footer: 'F', litChip: 'chip', lit: 'b', edges: [['b', 'a', 'back']] })] }).shots[0];
  assert.deepEqual([s.title, s.kicker, s.footer, s.litChip, s.lit], ['T', 'K', 'F', 'chip', 'b']);
  assert.deepEqual(s.edges, [{ from: 'b', to: 'a', label: 'back' }]);
});

test('diagram nodes: count 2..8, id pattern, label required, label at most 3 words, label kept untrimmed', () => {
  const w = 'shots[0] (D01)';
  const run = (nodes) => errorsOf({ shots: [diagram({ nodes })] });
  assert.deepEqual(run([node('a')]), [`${w}.nodes must hold 2-8 nodes`]);
  assert.deepEqual(run(Array.from({ length: 9 }, (_, i) => node('n' + i))), [`${w}.nodes must hold 2-8 nodes`]);
  assert.deepEqual(errorsOf({ shots: [diagram({ nodes: 'x' })] }), [`${w}.nodes must hold 2-8 nodes`]);
  assert.equal(parseShotList({ shots: [diagram({ nodes: Array.from({ length: 8 }, (_, i) => node('n' + i)) })] }).shots[0].nodes.length, 8);
  assert.deepEqual(run([{ id: '1bad', label: 'A' }, node('b')]), [`${w}.nodes[0].id must match ${ID_RE}`]);
  assert.deepEqual(run([{ id: 'a' }, { id: 'b', label: '   ' }]), [`${w}.nodes[0].label is required`, `${w}.nodes[1].label is required`]);
  assert.deepEqual(run([node('a', { label: 'one two three four' }), node('b')]), [`${w}.nodes[0].label "one two three four" is over 3 words`]);
  assert.deepEqual(run([null, node('b')]), [`${w}.nodes[0].id must match ${ID_RE}`, `${w}.nodes[0].label is required`]);
  const ok = parseShotList({ shots: [diagram({ nodes: [node('a', { label: '  one  two three ' }), node('b')] })] }).shots[0];
  assert.equal(ok.nodes[0].label, '  one  two three ');
});

test('diagram edges and lit must reference known nodes', () => {
  const w = 'shots[0] (D01)';
  const edgeMsg = (i) => `${w}.edges[${i}] must be [fromId, toId, label?] of known nodes`;
  assert.deepEqual(errorsOf({ shots: [diagram({ edges: [['a', 'zzz'], 'ab', null, ['a', 'b']] })] }), [edgeMsg(0), edgeMsg(1), edgeMsg(2)]);
  assert.deepEqual(errorsOf({ shots: [diagram({ lit: 'z' })] }), [`${w}.lit "z" is not a node id`]);
  assert.equal(parseShotList({ shots: [diagram({ lit: 'a' })] }).shots[0].lit, 'a');
});

// ---- cues ----
test('cue "at" replaces the default time and events are re-sorted by time', () => {
  const s = shotOf(code({ cues: [{ event: 'callout', at: 0.1 }, { event: 'reveal', at: 0.5 }] }));
  assert.deepEqual(s.events, [{ event: 'callout', t: 0.1 }, { event: 'reveal', t: 0.5 }, { event: 'highlight:0', t: 2 }]);
  assert.equal(s.durationSeconds, 3.5);
});

test('cue "word" resolves from options.words, shot.words wins, and lead/occurrence/rounding apply', () => {
  const words = [{ text: 'gate', start: 1 }, { text: 'x', start: 1.5 }, { word: 'Gate!', start: 2.1239 }];
  const cue = { event: 'callout', word: 'gate', occurrence: 2, lead: 0.5 };
  assert.equal(times(shotOf(code({ cues: [cue] }), { words: { S01: words } })).callout, 2.624);
  assert.equal(times(shotOf(code({ cues: [cue], words }), { words: { S01: [] } })).callout, 2.624);
  assert.equal(times(shotOf(code({ cues: [{ event: 'callout', word: 'gate', lead: -5 }] }), { words: { S01: words } })).callout, 0);
});

test('cue errors: exact messages, one per bad cue, in cue order; non-array cues are ignored', () => {
  const w = 'shots[0] (S01).cues';
  assert.deepEqual(errorsOf(doc([code({ cues: [null, { at: 1 }, { event: 'explode', at: 1 }, { event: 'callout' }, { event: 'callout', at: -1 }, { event: 'callout', word: 'zzz' }] })]), { words: { S01: [{ text: 'a', start: 1 }] } }), [
    `${w}[0].event is required`,
    `${w}[1].event is required`,
    `${w}[2].event "explode" is not an event of this shot (reveal, highlight:0, callout)`,
    `${w}[3]: cue needs "at" (seconds) or "word"`,
    `${w}[4]: at must be >= 0`,
    `${w}[5]: cue word "zzz" (occurrence 1) not found in the narration words`,
  ]);
  assert.equal(shotOf(code({ cues: 'x' })).events.length, 3);
});

test('cue ordering checks: cross-ref highlight/callout cannot precede the open, lit cannot precede its node', () => {
  assert.deepEqual(errorsOf(doc([code({ crossRef: { file: 'a.ts', lines: [1, 2] }, cues: [{ event: 'crossref:0', at: 5 }, { event: 'crossref:0:highlight', at: 4 }] })])), ['shots[0] (S01): crossref:0:highlight at 4s precedes crossref:0 at 5s']);
  assert.deepEqual(errorsOf({ shots: [diagram({ lit: 'b', cues: [{ event: 'node:b', at: 5 }, { event: 'lit', at: 2 }] })] }), ['shots[0] (D01): lit at 2s precedes node:b at 5s']);
  assert.equal(shotOf(code({ crossRef: { file: 'a.ts', lines: [1, 2] }, cues: [{ event: 'crossref:0', at: 4 }, { event: 'crossref:0:highlight', at: 4 }] })).events.length, 5);
});

test('multiple errors from one shot are all collected, and across shots', () => {
  assert.deepEqual(errorsOf(doc([code({ holdSeconds: 12, zoom: 3, startLine: 'bad' }), code({ id: 'S02', zoom: 0 })])), [
    'shots[0] (S01).holdSeconds must be 0-8 (visual bible: no dead hold over 8 s)',
    'shots[0] (S01).startLine must be a 1-based line number',
    'shots[0] (S01).zoom must be 1.0-2.2',
    'shots[1] (S02).zoom must be 1.0-2.2',
  ]);
});

// ---- full output shape ----
test('code shot: full normalized output shape', () => {
  const s = shotOf(code({ startLine: 1, targetSeconds: 9, crossRef: { file: 'web/B.tsx', lines: [10, 12] } }));
  assert.deepEqual(s, {
    id: 'S01', kind: 'code', holdSeconds: 1.5, targetSeconds: 9,
    file: 'src/gate.py', ref: 'main', lines: [1, 8], startLine: 1, highlight: [[3, 4]],
    callout: { line: 4, text: 'nothing executes without this' }, zoom: 1.4, pointer: null,
    crossRefs: [{ file: 'web/B.tsx', ref: 'main', lines: [10, 12], highlight: [[10, 12]], callout: null, label: null }],
    events: [{ event: 'reveal', t: 0.4 }, { event: 'highlight:0', t: 2 }, { event: 'callout', t: 4.5 }, { event: 'crossref:0', t: 7 }, { event: 'crossref:0:highlight', t: 9.2 }],
    durationSeconds: 10.7,
  });
});

// ---- resolveCue ----
test('resolveCue: explicit at, negative at, missing both', () => {
  assert.equal(resolveCue({ at: 1.25 }, []), 1.25);
  assert.equal(resolveCue({ at: 0 }, []), 0);
  assert.throws(() => resolveCue({ at: -1 }, [], 'w'), { message: 'w: at must be >= 0' });
  assert.throws(() => resolveCue({}, []), { message: 'cue: cue needs "at" (seconds) or "word"' });
});

test('resolveCue: word matching ignores case/punctuation, supports phrases, occurrences, lead, and skips non-word tokens', () => {
  const words = [{ text: 'Hello', start: 0.1 }, { text: ' ', start: 0.2, type: 'spacing' }, { text: 'world.', start: 0.4 }, { text: 'Hello', start: 0.9 }, { text: 'WORLD', start: 1.0 }, { text: '', start: 3 }, { text: 'nostart', start: 'x' }];
  assert.equal(resolveCue({ word: 'World' }, words), 0.4);
  assert.equal(resolveCue({ word: 'hello world' }, words), 0.1);
  assert.equal(resolveCue({ word: 'hello world', occurrence: 2, lead: 0.05 }, words), 0.95);
  assert.equal(resolveCue({ word: 'hello', lead: -1 }, words), 0);
  assert.throws(() => resolveCue({ word: 'hello', occurrence: 3 }, words, 'W'), { message: 'W: cue word "hello" (occurrence 3) not found in the narration words' });
  assert.throws(() => resolveCue({ word: 'nostart' }, words), /not found/);
  assert.throws(() => resolveCue({ word: 'a' }, 'notarray'), /not found/);
});

// ---- filesToRead ----
test('filesToRead: code and cross-ref files, deduplicated by ref+path, diagrams skipped', () => {
  const p = parseShotList(doc([
    code({ crossRef: [{ file: 'src/gate.py', lines: [1, 2] }, { file: 'src/gate.py', ref: 'dev', lines: [1, 2] }] }),
    code({ id: 'S02', ref: 'dev' }),
    diagram(),
  ]));
  assert.deepEqual(filesToRead(p), [{ file: 'src/gate.py', ref: 'main' }, { file: 'src/gate.py', ref: 'dev' }]);
});
