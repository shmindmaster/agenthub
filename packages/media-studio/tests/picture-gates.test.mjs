// Pre-render picture gate. These fail before Remotion: a missing props file, a Whisper clock,
// a changed percent, and a spotlight word that is not the spoken word.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {
  anchorMisses, captionCues, clockAccepted, designedCuts, durationAgrees, factDrift, factNumbers,
  propsArg, renderArgv, roleProblems, takeProblems,
} from '../scripts/picture-gates.mjs';
import { planRender } from '../scripts/render-program.mjs';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const scratch = mkdtempSync(join(tmpdir(), 'picture-gates-'));
test.after(() => rmSync(scratch, { recursive: true, force: true }));
const run = (script, args) => {
  const result = spawnSync(process.execPath, [join(pkg, 'scripts', script), ...args], { encoding: 'utf8', windowsHide: true });
  return { code: result.status, output: `${result.stdout}${result.stderr}` };
};
const write = (path, body) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, typeof body === 'string' ? body : JSON.stringify(body)); };

test('spoken numbers and digits are the same fact, and a changed percent is drift', () => {
  assert.deepEqual(factNumbers('fifty nine percent'), ['59%']);
  assert.deepEqual(factNumbers('59%'), ['59%']);
  assert.deepEqual(factNumbers('seventy'), ['70']);
  assert.deepEqual(factNumbers('one hundred ninety three'), ['193']);
  assert.equal(factDrift('fifty nine percent', '59%').ok, true);
  const drift = factDrift('59%', '58%');
  assert.equal(drift.ok, false);
  assert.deepEqual(drift.missing, ['59%']);
  assert.deepEqual(drift.added, ['58%']);
});

test('the five first-cut spotlight misses fail, and nine does not match ninety', () => {
  const words = (list) => ({ s: 1, words: list.map((w, index) => ({ w, s: index + 1 })) });
  const script = [
    { id: 'M09', v: [{ w: 'ninety' }] },
    { id: 'M13', v: [{ w: 'groups' }] },
    { id: 'M19', v: [{ w: 'conflict' }, { w: 'software' }] },
    { id: 'M28', v: [{ w: 'L28:there' }] },
    { id: 'M33', v: [{ w: 'context' }] },
  ];
  const timing = {
    M09: words(['fifty', 'nine', 'percent', 'seventy']),
    M13: words(['rule']),
    M19: words(['software', 'approver', 'conflict']),
    M28: words(['getGuestMessages', 'is', 'missing']),
    M33: words(['history']),
  };
  const misses = anchorMisses(script, timing);
  assert.match(misses.join('\n'), /M09 word ninety/);
  assert.match(misses.join('\n'), /M13 word groups/);
  assert.match(misses.join('\n'), /M19 word software is out of spoken order/);
  assert.match(misses.join('\n'), /M28 word L28:there/);
  assert.match(misses.join('\n'), /M33 word context/);
  assert.match(anchorMisses([{ id: 'M09', v: { w: 'nine' } }], { M09: words(['ninety']) }).join('\n'), /nine/);
  assert.deepEqual(anchorMisses([{ id: 'M13', v: { w: 'rule' } }], { M13: words(['rules']) }), []);
});

test('Whisper cannot drive the picture clock', () => {
  assert.equal(clockAccepted({ method: 'forced-alignment' }).ok, true);
  assert.equal(clockAccepted({ method: 'forced-alignment-on-encoded' }).ok, true);
  const refused = clockAccepted({ method: 'faster-whisper' });
  assert.equal(refused.ok, false);
  assert.match(refused.reason, /Whisper is a transcript check/);
  assert.match(clockAccepted({}).reason, /picture clock is ai.ps1 align/);
});

test('clockAccepted rejects reports marked not ok', () => {
  assert.equal(clockAccepted({ ok: false, method: 'forced-alignment' }).ok, false);
  const asr = clockAccepted({ ok: false, method: 'asr-anchored-alignment' }, { allowAsrAnchored: true });
  assert.equal(asr.ok, false);
  assert.match(asr.reason, /not ok/);
});

test('clockAccepted enforces coverage limits on asr-anchored-alignment', () => {
  const makeWords = (limitedRun, exactCount) => {
    const words = [];
    for (let i = 0; i < limitedRun; i += 1) words.push({ text: `l${i}`, start: i * 0.08, end: i * 0.08 + 0.08, precisionLimited: true });
    for (let i = 0; i < exactCount; i += 1) words.push({ text: `e${i}`, start: (limitedRun + i) * 0.08, end: (limitedRun + i) * 0.08 + 0.08 });
    return words;
  };
  assert.equal(clockAccepted({ method: 'asr-anchored-alignment', words: makeWords(0, 10) }, { allowAsrAnchored: true }).ok, true);
  const lowRatio = clockAccepted({ method: 'asr-anchored-alignment', words: makeWords(5, 1) }, { allowAsrAnchored: true });
  assert.equal(lowRatio.ok, false);
  assert.match(lowRatio.reason, /exact onsets/);
  const longRun = clockAccepted({ method: 'asr-anchored-alignment', words: makeWords(7, 70) }, { allowAsrAnchored: true });
  assert.equal(longRun.ok, false);
  assert.match(longRun.reason, /longest precision-limited run/);
});

test('props are one argument, and a missing or empty props file is refused', () => {
  assert.throws(() => propsArg(''), /props file is required/);
  const argv = renderArgv({ cli: 'cli.js', composition: 'Meeting', propsPath: 'C:\\films\\props.json', outFile: 'out.mp4' });
  assert.equal(argv.filter((arg) => String(arg).startsWith('--props')).length, 1);
  assert.equal(argv[5], '--props=C:\\films\\props.json');
  assert.throws(() => planRender({ kit: scratch, composition: 'Meeting', propsPath: join(scratch, 'missing.json'), outFile: 'out.mp4', voiceSeconds: 10, cli: 'cli.js' }), /missing or empty/);
  const empty = join(scratch, 'empty.json');
  write(empty, '');
  assert.throws(() => planRender({ kit: scratch, composition: 'Meeting', propsPath: empty, outFile: 'out.mp4', voiceSeconds: 10, cli: 'cli.js' }), /missing or empty/);
});

test('a synthetic picture duration does not match the voice', () => {
  assert.equal(durationAgrees(852, 449), false);
  assert.equal(durationAgrees(450.4, 449), true);
  assert.equal(durationAgrees(450.6, 449), false);
});

test('an mp3, a wav without PASS, and an undisclosed role voice fail', () => {
  assert.match(takeProblems([{ name: 'voice/D25.mp3', pass: true }, { name: 'voice/D25.wav', pass: false }]).join('\n'), /D25\.mp3/);
  assert.match(takeProblems([{ name: 'voice/D25.wav', pass: false }]).join('\n'), /no PASS receipt/);
  const script = [{ id: 'M08', speaker: 'lina', v: { w: 'seventy' } }];
  assert.match(roleProblems(script, {}).join('\n'), /dramatization/);
  const disclosed = [{ id: 'M08', speaker: 'lina', v: { card: 'Read as Lina', w: 'seventy' } }];
  assert.deepEqual(roleProblems(disclosed, { lina: { dramatization: true, card: 'Read as Lina' } }), []);
});

test('designed cuts are the mount, the spoken word, and the spotlight hold', () => {
  const script = [{ id: 'M09', v: { w: 'seventy' } }];
  const timing = { M09: { s: 10, words: [{ w: 'seventy', s: 12.5, start: 12.5 }] } };
  const designed = designedCuts(script, timing);
  assert.deepEqual(designed.misses, []);
  assert.deepEqual(designed.cuts, [0, 9.75, 12.5, 12.95]);
});

test('a packed phrase stays one rate-bound cue instead of an orphan line', () => {
  const words = [
    { word: 'about', start: 0, end: 0.08 },
    { word: 'four', start: 0.08, end: 0.16 },
    { word: 'percent.', start: 0.16, end: 0.24 },
    { word: 'Then', start: 0.26, end: 0.4 },
    { word: 'the', start: 0.4, end: 0.48 },
    { word: 'next', start: 0.48, end: 0.6 },
    { word: 'sentence', start: 0.6, end: 0.8 },
    { word: 'continues', start: 0.8, end: 1 },
    { word: 'onward', start: 1, end: 1.2 },
    { word: 'here.', start: 1.2, end: 1.4 },
  ];
  const { cues, rateBound } = captionCues(words);
  const packed = cues.find((cue) => cue.text.includes('about'));
  assert.equal(packed.text, 'about four percent.');
  assert.equal(packed.rateBound, true);
  assert.ok(rateBound.includes(packed.index));
  assert.equal(cues.some((cue) => cue.text === 'four percent.'), false);
});

test('a scene voiceStyle is the batch style, and an unlisted style throws', () => {
  const reuse = join(pkg, 'scripts', 'OwnerVoice-TakeReuse.ps1').replace(/'/g, "''");
  const command = `
$ErrorActionPreference = 'Stop'
. '${reuse}'
$picked = Resolve-RequestedStyle ([pscustomobject]@{ voiceStyle = '08_quiet'; style = '02_explaining' }) '02_explaining' @('02_explaining','08_quiet')
if ($picked -ne '08_quiet') { throw "picked $picked" }
$threw = $false
try { Resolve-RequestedStyle ([pscustomobject]@{ style = '11_stage' }) '02_explaining' @('02_explaining','08_quiet') } catch { if ($_.Exception.Message -match 'not allowlisted') { $threw = $true } else { throw } }
if (-not $threw) { throw 'unlisted style was accepted' }
Write-Output 'STYLE_OK'
`;
  const result = spawnSync('pwsh', ['-NoProfile', '-Command', command], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 0, `${result.stdout}${result.stderr}`);
  assert.match(result.stdout, /STYLE_OK/);
});

test('picture inputs fail on a missing props file, a Whisper clock, a changed percent, and the five bad anchors', () => {
  const root = join(scratch, 'bad');
  write(join(root, 'story', 'fact-lock.json'), { numbers: ['59%'] });
  write(join(root, 'story', 'locked-script.txt'), 'fifty eight percent\n');
  write(join(root, 'story', 'picture-script.json'), [
    { id: 'D00' },
    { id: 'M09', v: [{ w: 'ninety' }] },
    { id: 'M13', v: [{ w: 'groups' }] },
    { id: 'M19', v: [{ w: 'conflict' }, { w: 'software' }] },
    { id: 'M28', v: [{ w: 'L28:there' }] },
    { id: 'M33', v: [{ w: 'context' }] },
  ]);
  const align = (id, words) => write(join(root, 'voice', 'align', `${id}.json`), { method: 'forced-alignment', words: words.map((w, index) => ({ w, s: index + 1, e: index + 1.2 })) });
  write(join(root, 'voice', 'align', 'D00.json'), { method: 'faster-whisper', words: [{ w: 'hello', s: 0.2, e: 0.4 }] });
  align('M09', ['fifty', 'nine', 'percent', 'seventy']);
  align('M13', ['rule']);
  align('M19', ['software', 'approver', 'conflict']);
  align('M28', ['missing']);
  align('M33', ['history']);
  write(join(root, 'voice', 'D25.mp3'), 'old');
  write(join(root, 'voice', 'D18.wav'), 'take');
  const result = run('validate-picture-inputs.mjs', [root]);
  assert.equal(result.code, 1, result.output);
  assert.match(result.output, /--props/);
  assert.match(result.output, /Whisper is a transcript check/);
  assert.match(result.output, /narration numbers changed/);
  assert.match(result.output, /M09 word ninety/);
  assert.match(result.output, /M13 word groups/);
  assert.match(result.output, /out of spoken order/);
  assert.match(result.output, /M28 word L28:there/);
  assert.match(result.output, /M33 word context/);
  assert.match(result.output, /D25\.mp3/);
  assert.match(result.output, /D18\.wav has no PASS receipt/);
});

test('picture inputs pass a locked number, an aligner clock, a disclosed role, and a PASS take', () => {
  const root = join(scratch, 'good');
  write(join(root, 'story', 'fact-lock.json'), { numbers: ['59%'] });
  write(join(root, 'story', 'locked-script.txt'), 'fifty nine percent\n');
  write(join(root, 'story', 'props.json'), { ok: true });
  write(join(root, 'story', 'speakers.json'), { lina: { dramatization: true, voice: 'Serena', card: 'Read as Lina' } });
  write(join(root, 'story', 'picture-script.json'), [{ id: 'M09', speaker: 'lina', v: { card: 'Read as Lina', w: 'seventy' } }]);
  write(join(root, 'voice', 'align', 'M09.json'), { method: 'forced-alignment', lineStart: 1, words: [{ w: 'seventy', s: 1.4, e: 1.8 }] });
  write(join(root, 'voice', 'M09.wav'), 'take');
  write(join(root, 'voice', 'M09.PASS.json'), { status: 'PASS' });
  const result = run('validate-picture-inputs.mjs', [root, '--props', 'story/props.json']);
  assert.equal(result.code, 0, result.output);
});

test('a forced-aligner job refuses Whisper, and an align report beats an asr file', () => {
  const refused = join(scratch, 'whisper-clock');
  write(join(refused, 'job.json'), { syncClock: 'forced-aligner' });
  write(join(refused, 'story', 'narration-timeline.json'), { durationSeconds: 3, segments: [{ id: 'S01', scene: 'S01', text: 'Seventy percent', startSeconds: 0, durationSeconds: 3 }] });
  write(join(refused, 'voice', 'asr', 'S01.json'), { words: [{ word: 'Seventy', start: 0.2, end: 0.6 }, { word: 'percent', start: 0.6, end: 1 }] });
  let result = run('build-cue-sheet.mjs', [refused]);
  assert.equal(result.code, 1, result.output);
  assert.match(result.output, /cannot time the picture/);

  const preferred = join(scratch, 'align-wins');
  write(join(preferred, 'story', 'narration-timeline.json'), { durationSeconds: 3, segments: [{ id: 'meeting-M09', scene: 'M09', text: 'seventy', startSeconds: 10, durationSeconds: 3 }] });
  write(join(preferred, 'voice', 'asr', 'meeting-M09.json'), { words: [{ word: 'whispered', start: 0.9, end: 1.2 }] });
  write(join(preferred, 'voice', 'align', 'meeting-M09.json'), { method: 'forced-alignment', words: [{ w: 'seventy', s: 2.5, e: 2.9 }] });
  write(join(preferred, 'kit', 'src', 'films', 'meeting.script.json'), [{ id: 'M09', v: { w: 'seventy' } }]);
  result = run('build-cue-sheet.mjs', [preferred]);
  assert.equal(result.code, 0, result.output);
  const cue = JSON.parse(spawnSync(process.execPath, ['-e', `process.stdout.write(require('fs').readFileSync(${JSON.stringify(join(preferred, 'plan', 'cue-sheet.json'))},'utf8'))`], { encoding: 'utf8', windowsHide: true }).stdout);
  assert.equal(cue.beats[0].narration.words[0].w, 'seventy');
  assert.equal(cue.beats[0].narration.source, 'voice/align/meeting-M09.json');
  assert.ok(cue.edl.some((cut) => cut.kind === 'designed' && cut.startSeconds === 12.5));
  assert.ok(cue.edl.some((cut) => cut.startSeconds === 9.75));
});

test('merge-designed-cuts puts the mounts back and keeps a cut that was already declared', () => {
  const root = join(scratch, 'merge');
  write(join(root, 'story', 'picture-script.json'), [{ id: 'M09', v: { w: 'seventy' } }]);
  write(join(root, 'voice', 'align', 'M09.json'), { method: 'forced-alignment', lineStart: 10, words: [{ w: 'seventy', s: 12.5, e: 12.9 }] });
  write(join(root, 'plan', 'cue-sheet.json'), { beats: [], edl: [{ startSeconds: 3, kind: 'speech' }] });
  const result = run('merge-designed-cuts.mjs', [root, '--offset', '600']);
  assert.equal(result.code, 0, result.output);
  const cue = JSON.parse(spawnSync(process.execPath, ['-e', `process.stdout.write(require('fs').readFileSync(${JSON.stringify(join(root, 'plan', 'cue-sheet.json'))},'utf8'))`], { encoding: 'utf8', windowsHide: true }).stdout);
  const starts = cue.edl.map((cut) => cut.startSeconds);
  assert.ok(starts.includes(3));
  assert.ok(starts.includes(609.75));
  assert.ok(starts.includes(612.5));
  assert.ok(starts.includes(612.95));
});
