// Code-walkthrough stage: shot-list parser and hash receipt.
// Run: node --test packages/media-studio/tests/code-stage.test.mjs   (also discovered by tests/Run-AllTests.ps1)
// Requires git on PATH. No browser: the recorded path is proven by the proof job, not by unit tests.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseShotList, resolveCue, ShotListError, filesToRead } from '../kit/code-stage/shotlist.mjs';
import { lineHashes, splitLines, sha256, verifyCodeReceipt } from '../kit/code-stage/source.mjs';
import { buildStage } from '../kit/code-stage/build-stage.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const kit = resolve(here, '..', 'kit', 'code-stage');

const code = (extra = {}) => ({ id: 'S01', file: 'src/gate.py', lines: [1, 8], highlight: [[3, 4]], callout: { line: 4, text: 'nothing executes without this' }, ...extra });
const doc = (shots, extra = {}) => ({ repo: 'C:/repo', ref: 'main', shots, ...extra });
const errorsOf = (d, o) => { try { parseShotList(d, o); return []; } catch (e) { assert.ok(e instanceof ShotListError, e.message); return e.errors; } };

test('parses a code shot with defaults and a paced event timeline', () => {
  const p = parseShotList(doc([code({ crossRef: { file: 'web/Button.tsx', lines: [10, 20], callout: { line: 12, text: 'disabled until signed' } } })]));
  const s = p.shots[0];
  assert.equal(s.kind, 'code');
  assert.equal(s.ref, 'main');
  assert.equal(s.zoom, 1.4);
  assert.deepEqual(s.crossRefs[0].highlight, [[10, 20]], 'a cross-ref without highlight highlights its whole span');
  assert.deepEqual(s.events.map((e) => e.event), ['reveal', 'highlight:0', 'callout', 'crossref:0', 'crossref:0:highlight', 'crossref:0:callout']);
  for (let i = 1; i < s.events.length; i++) assert.ok(s.events[i].t > s.events[i - 1].t, 'default events are strictly ordered');
  assert.equal(s.durationSeconds, Math.round((s.events.at(-1).t + 1.5) * 100) / 100);
  assert.deepEqual(filesToRead(p).map((f) => f.file), ['src/gate.py', 'web/Button.tsx']);
});

test('accepts the owner spelling "cross-ref" and Windows separators', () => {
  const p = parseShotList(doc([code({ file: 'src\\gate.py', 'cross-ref': { file: 'web\\Button.tsx', lines: [1, 2] } })]));
  assert.equal(p.shots[0].file, 'src/gate.py');
  assert.equal(p.shots[0].crossRefs[0].file, 'web/Button.tsx');
});

test('word cues bind events to the narration word timings', () => {
  const words = [{ text: 'This', start: 0.1 }, { text: ' ', start: 0.3, type: 'spacing' }, { text: 'is', start: 0.4 }, { text: 'the', start: 0.6 }, { text: 'gate.', start: 0.8 }, { text: 'Nothing', start: 2.0 }, { text: 'executes', start: 2.3 }, { text: 'gate', start: 3.1 }];
  assert.equal(resolveCue({ word: 'gate' }, words), 0.8, 'punctuation is ignored');
  assert.equal(resolveCue({ word: 'gate', occurrence: 2 }, words), 3.1);
  assert.equal(resolveCue({ word: 'nothing executes' }, words), 2.0, 'multi-word cue');
  assert.equal(resolveCue({ word: 'gate', lead: -0.2 }, words), 0.6);
  assert.equal(resolveCue({ at: 1.25 }, words), 1.25);
  assert.throws(() => resolveCue({ word: 'missing' }, words), /not found/);
  const p = parseShotList(doc([code({ cues: [{ event: 'highlight:0', word: 'gate' }, { event: 'callout', word: 'nothing executes' }] })]), { words: { S01: words } });
  const ev = Object.fromEntries(p.shots[0].events.map((e) => [e.event, e.t]));
  assert.equal(ev['highlight:0'], 0.8);
  assert.equal(ev.callout, 2.0);
});

test('rejects fabricated or unsafe spans', () => {
  const errs = errorsOf(doc([
    code({ id: 'S01', file: 'C:/abs/gate.py' }),
    code({ id: 'S02', file: '../outside.py' }),
    code({ id: 'S03', highlight: [[7, 9]] }),
    code({ id: 'S04', callout: { line: 20, text: 'x' } }),
    code({ id: 'S05', lines: [1, 80] }),
    code({ id: 'S05' }),
    code({ id: 'S06', lines: [5, 2] }),
    code({ id: 'S07', holdSeconds: 12 }),
    code({ id: 'S08', zoom: 3 }),
  ]));
  const has = (re) => assert.ok(errs.some((e) => re.test(e)), `expected ${re} in\n${errs.join('\n')}`);
  has(/S01.*repo-relative/);
  has(/S02.*repo-relative/);
  has(/S03.*highlight\[0\] 7-9 is outside lines 1-8/);
  has(/S04.*callout.line 20 is outside/);
  has(/S05.*at most 60/);
  has(/duplicated/);
  has(/S06.*lines must be/);
  has(/S07.*holdSeconds/);
  has(/S08.*zoom/);
});

test('rejects unknown cue events, missing words, cross-ref ordering and a missing repo', () => {
  const errs = errorsOf({ ref: 'main', shots: [code({ cues: [{ event: 'explode', at: 1 }, { event: 'callout', word: 'absent' }], crossRef: { file: 'a.ts', lines: [1, 2] } }),
    code({ id: 'S02', crossRef: { file: 'a.ts', lines: [1, 2] }, cues: [{ event: 'crossref:0', at: 5 }, { event: 'crossref:0:highlight', at: 4 }] })] });
  assert.ok(errs.some((e) => /repo .* is required/.test(e)));
  assert.ok(errs.some((e) => /"explode" is not an event/.test(e)));
  assert.ok(errs.some((e) => /"absent".*not found/.test(e)));
  assert.ok(errs.some((e) => /crossref:0:highlight at 4s precedes crossref:0 at 5s/.test(e)));
});

test('parses a diagram shot and validates nodes, edges and the lit gate', () => {
  const nodes = ['Evidence', 'Rule', 'Proposal', 'Approval', 'Action', 'Audit'].map((l) => ({ id: l.toLowerCase(), label: l }));
  const p = parseShotList({ shots: [{ id: 'S03', kind: 'diagram', title: 'Decision chain', nodes, lit: 'approval', cues: [{ event: 'node:approval', at: 3 }, { event: 'lit', at: 3.5 }] }] });
  const s = p.shots[0];
  assert.equal(p.repo, null, 'diagram-only lists need no repo');
  assert.equal(s.edges.length, 5, 'default edges chain the nodes in order');
  assert.equal(s.edges[2].from, 'proposal');
  assert.ok(s.events.find((e) => e.event === 'lit').t >= s.events.find((e) => e.event === 'node:approval').t);
  const errs = errorsOf({ shots: [{ id: 'D1', kind: 'diagram', nodes: [{ id: 'a', label: 'one two three four' }, { id: 'b', label: 'B' }], edges: [['a', 'zzz']], lit: 'q' }] });
  assert.ok(errs.some((e) => /over 3 words/.test(e)));
  assert.ok(errs.some((e) => /edges\[0\]/.test(e)));
  assert.ok(errs.some((e) => /lit "q"/.test(e)));
  const order = errorsOf({ shots: [{ id: 'D2', kind: 'diagram', nodes, lit: 'approval', cues: [{ event: 'node:approval', at: 5 }, { event: 'lit', at: 2 }] }] });
  assert.ok(order.some((e) => /lit at 2s precedes node:approval/.test(e)));
});

test('line hashes match an editor line split (CRLF/LF, trailing newline)', () => {
  assert.deepEqual(splitLines('a\r\nb\nc\n'), ['a', 'b', 'c']);
  const h = lineHashes(['x', 'y', 'z'], [2, 3]);
  assert.equal(h.rows[0].sha256, sha256('y'));
  assert.equal(h.rangeSha256, sha256('y\nz'));
  assert.throws(() => lineHashes(['x'], [1, 2]), /outside the file/);
});

function tempRepo() {
  const dir = mkdtempSync(join(tmpdir(), 'code-stage-repo-'));
  const g = (...a) => execFileSync('git', ['-C', dir, ...a], { stdio: ['ignore', 'pipe', 'pipe'] }).toString().trim();
  g('init', '-q', '-b', 'main');
  g('config', 'user.email', 'test@example.invalid'); g('config', 'user.name', 'test'); g('config', 'core.autocrlf', 'false');
  mkdirSync(join(dir, 'src'), { recursive: true }); mkdirSync(join(dir, 'web'), { recursive: true });
  const py = ['def approve(note, user):', '    """Gate."""', '    if not note.evidence:', '        raise PermissionError("evidence required")', '    if not note.signed_by:', '        raise PermissionError("signature required")', '    note.status = "approved"', '    return note', ''].join('\n');
  writeFileSync(join(dir, 'src', 'gate.py'), py);
  writeFileSync(join(dir, 'web', 'Button.tsx'), 'export function Approve({ ready }: { ready: boolean }) {\r\n  return <button disabled={!ready}>Approve note</button>;\r\n}\r\n');
  g('add', '-A'); g('commit', '-q', '-m', 'one');
  return { dir, g, commit: g('rev-parse', 'HEAD') };
}

test('receipt binds the commit, file sha256 and every shown line, and catches drift', () => {
  const { dir, g, commit } = tempRepo();
  try {
    // An uncommitted edit must not reach the film: files are read from git objects at the commit.
    writeFileSync(join(dir, 'src', 'gate.py'), '# uncommitted edit\n');
    const shotDoc = { repo: dir, ref: 'main', shots: [code({ crossRef: { file: 'web/Button.tsx', lines: [1, 3], highlight: [[2, 2]] } }), { id: 'S02', kind: 'diagram', nodes: [{ id: 'a', label: 'A' }, { id: 'b', label: 'B' }] }] };
    const { stage, receipt } = buildStage(shotDoc);
    assert.equal(receipt.files.length, 2);
    assert.ok(receipt.files.every((f) => f.commit === commit));
    assert.ok(stage.files['src/gate.py'].text.startsWith('def approve'), 'stage text is the committed file');
    const s1 = receipt.shots[0];
    assert.equal(s1.lineHashes.length, 8);
    assert.equal(s1.lineHashes[2].sha256, sha256('    if not note.evidence:'));
    assert.equal(s1.highlight[0].sha256, sha256('    if not note.evidence:\n        raise PermissionError("evidence required")'));
    assert.equal(s1.crossRefs[0].highlight[0].sha256, sha256('  return <button disabled={!ready}>Approve note</button>;'), 'CRLF file lines hash without the CR');
    assert.equal(stage.shots[0].rangeSha256, s1.rangeSha256, 'the page verifies against the receipt hash');
    assert.ok(stage.tree.listing[''].some((e) => e.name === 'src' && e.type === 'dir'));
    assert.deepEqual(verifyCodeReceipt(receipt, dir), { ok: true, problems: [] });

    // A later commit does not change what the receipt proves (it is pinned to a commit).
    g('add', '-A'); g('commit', '-q', '-m', 'two');
    assert.equal(verifyCodeReceipt(receipt, dir).ok, true);

    // Tampering with any hash is caught.
    const bad = JSON.parse(JSON.stringify(receipt));
    bad.shots[0].lineHashes[3].sha256 = sha256('fabricated');
    bad.shots[0].crossRefs[0].highlight[0].sha256 = sha256('fabricated');
    const r = verifyCodeReceipt(bad, dir);
    assert.equal(r.ok, false);
    assert.ok(r.problems.some((p) => /S01: line 4 differs/.test(p)));
    assert.ok(r.problems.some((p) => /crossRef\[0\]: highlight 2-2 differs/.test(p)));

    // A span past the end of the file fails before anything renders.
    assert.throws(() => buildStage({ ...shotDoc, shots: [code({ lines: [1, 30], highlight: [[29, 30]], callout: null })] }), /outside the file/);
    // An unknown ref fails.
    assert.throws(() => buildStage({ ...shotDoc, ref: 'no-such-branch' }));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('build-stage CLI writes stage.json, receipt.json and a scenes module; verify-receipt passes', () => {
  const { dir } = tempRepo();
  const job = mkdtempSync(join(tmpdir(), 'code-stage-job-'));
  try {
    mkdirSync(join(job, 'story'));
    writeFileSync(join(job, 'job.json'), JSON.stringify({ kind: 'explainer', repositoryWritePolicy: 'read-only', workspace: job }));
    writeFileSync(join(job, 'story', 'code-shots.json'), JSON.stringify({ repo: dir, ref: 'main', shots: [code({ cues: [{ event: 'callout', word: 'nothing' }] })] }));
    writeFileSync(join(job, 'story', 'code-words.json'), JSON.stringify({ S01: [{ text: 'Nothing', start: 4.2 }] }));
    const r = spawnSync(process.execPath, [join(kit, 'build-stage.mjs'), job, '--fps', '15', '--monaco', join(job, 'no-monaco')], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stdout + r.stderr);
    for (const f of ['stage.json', 'receipt.json', 'scenes.mjs']) assert.ok(existsSync(join(job, 'capture', 'code-stage', f)), f);
    const stage = JSON.parse(readFileSync(join(job, 'capture', 'code-stage', 'stage.json'), 'utf8'));
    assert.equal(stage.fps, 15);
    assert.equal(stage.monacoSource, 'cdn', 'no local Monaco falls back to the pinned CDN build');
    assert.match(stage.monacoBase, /monaco-editor\/0\.52\.2\//);
    assert.equal(stage.shots[0].events.find((e) => e.event === 'callout').t, 4.2);
    const v = spawnSync(process.execPath, [join(kit, 'verify-receipt.mjs'), join(job, 'capture', 'code-stage', 'receipt.json')], { encoding: 'utf8' });
    assert.equal(v.status, 0, v.stdout + v.stderr);

    // A job inside the product repository is refused.
    const inside = join(dir, 'media-job'); mkdirSync(join(inside, 'story'), { recursive: true });
    writeFileSync(join(inside, 'job.json'), JSON.stringify({ repositoryWritePolicy: 'read-only' }));
    writeFileSync(join(inside, 'story', 'code-shots.json'), JSON.stringify({ repo: dir, ref: 'main', shots: [code()] }));
    const bad = spawnSync(process.execPath, [join(kit, 'build-stage.mjs'), inside], { encoding: 'utf8' });
    assert.notEqual(bad.status, 0);
    assert.match(bad.stderr, /outside the product repository/);
  } finally { rmSync(dir, { recursive: true, force: true }); rmSync(job, { recursive: true, force: true }); }
});
