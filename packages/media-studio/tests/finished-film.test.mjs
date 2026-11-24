// Finished-film gate against REAL synthetic media. Run: node --test tests/finished-film.test.mjs
// Requires ffmpeg/ffprobe on PATH; every test is skipped (visibly) otherwise.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(resolve(here, '..'), 'scripts', 'validate-finished-film.mjs');
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { windowsHide: true, timeout: 180000, stdio: ['ignore', 'ignore', 'inherit'] });
function hasTool(n, a = ['-version']) { try { execFileSync(n, a, { windowsHide: true, timeout: 10000, stdio: 'ignore' }); return true; } catch { return false; } }
const ok = hasTool('ffmpeg') && hasTool('ffprobe');
if (!ok) console.warn('SKIPPED: ffmpeg/ffprobe not on PATH; the finished-film tests did not run');
const scratch = mkdtempSync(join(tmpdir(), 'ms-finished-'));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));

const enc = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '96k'];
const SRC = (d, size = '640x360') => ['-f', 'lavfi', '-i', `testsrc2=size=${size}:rate=25:duration=${d}`];
const SINE = (d, filter = '') => ['-f', 'lavfi', '-i', `sine=frequency=440:sample_rate=44100:duration=${d}${filter ? ',' + filter : ''}`];
const gap = (a, b) => `volume=enable='between(t,${a},${b})':volume=0`;
let n = 0;
// vf: video filter chain ('' for none); audio: null for no audio track, '' for a plain tone, or an audio filter
function make(vf, { dur = 8, audio = '', size, audioDur = dur } = {}) {
  const out = join(scratch, `c${n++}.mp4`);
  const inputs = [...SRC(dur, size)];
  if (audio !== null) inputs.push(...SINE(audioDur, audio));
  ff([...inputs, ...(vf ? ['-vf', vf] : []), ...enc, ...(audio === null ? ['-an'] : []), '-shortest', out]);
  return out;
}
function run(file, args = []) {
  const out = join(scratch, `r${n++}.json`);
  const r = spawnSync(process.execPath, [script, file, '--out', out, ...args], { windowsHide: true, encoding: 'utf8' });
  let j = null; try { j = JSON.parse(readFileSync(out, 'utf8')); } catch { /* usage failure */ }
  return { code: r.status, out: (r.stdout || '') + (r.stderr || ''), j };
}
const codes = (list) => list.map((e) => e.code);
const reqFile = (obj) => { const p = join(scratch, `q${n++}.json`); writeFileSync(p, JSON.stringify(obj)); return p; };
const black = (a, b) => `drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill:enable='between(t,${a},${b})'`;

test('good film passes with the schema and a bound hash', { skip: !ok }, () => {
  const r = run(make('', {}));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.j.schema, 'media-studio/finished-film/1');
  assert.equal(r.j.ok, true);
  assert.match(r.j.sha256, /^[0-9a-f]{64}$/);
  assert.deepEqual(r.j.errors, []);
  assert.ok(r.j.durationSeconds > 7);
  assert.ok(Array.isArray(r.j.silences) && Array.isArray(r.j.blankSpans));
});

test('black opening fails', { skip: !ok }, () => {
  const r = run(make(black(0, 0.6)));
  assert.notEqual(r.code, 0);
  assert.ok(codes(r.j.errors).includes('opening-blank'), r.out);
});

test('dark title card with text-like detail is not flagged black', { skip: !ok }, () => {
  // dark background with thin light lines standing in for text: edge energy and contrast well above blank
  const vf = 'drawbox=x=0:y=0:w=iw:h=ih:color=0x101828:t=fill,drawbox=x=80:y=120:w=480:h=10:color=white:t=fill,drawbox=x=80:y=150:w=360:h=10:color=white:t=fill,drawbox=x=80:y=200:w=240:h=6:color=0xaaaaaa:t=fill';
  const r = run(make(vf, {}));
  assert.ok(!codes(r.j.errors).includes('opening-blank'), r.out);
  assert.ok(!codes(r.j.errors).includes('blank-span'), r.out);
  assert.equal(r.j.blankSpans.length, 0);
});

test('drawtext title card on dark background is not flagged (when drawtext exists)', { skip: !(ok && hasTool('ffmpeg', ['-hide_banner', '-h', 'filter=drawtext'])) }, () => {
  let f;
  try { f = make("drawbox=x=0:y=0:w=iw:h=ih:color=0x0b1020:t=fill,drawtext=text='Quarterly outlook':fontcolor=white:fontsize=48:x=60:y=150", {}); } catch { return; }
  const r = run(f);
  assert.ok(!codes(r.j.errors).includes('opening-blank'), r.out);
  assert.equal(r.j.blankSpans.length, 0, r.out);
});

test('a blank gap mid-film fails; a short end fade does not', { skip: !ok }, () => {
  let r = run(make(black(3, 4)));
  assert.ok(codes(r.j.errors).includes('blank-span'), r.out);
  assert.ok(r.j.blankSpans.length >= 1);
  r = run(make('fade=t=out:st=7.2:d=0.8'));
  assert.ok(!codes(r.j.errors).includes('blank-span'), r.out);
});

test('6 s mid silence fails; passes when reviewed; 4 s is an advisory only', { skip: !ok }, () => {
  const f = make('', { dur: 14, audio: gap(4, 10) });
  let r = run(f);
  assert.ok(codes(r.j.errors).includes('silence'), r.out);
  r = run(f, ['--reviewed-silence', '3.5-10.5']);
  assert.ok(!codes(r.j.errors).includes('silence'), r.out);
  r = run(make('', { dur: 12, audio: gap(4, 8) }));
  assert.ok(!codes(r.j.errors).includes('silence'), r.out);
  const adv = r.j.advisories.find((a) => a.code === 'silence-review');
  assert.ok(adv && adv.message.length > 20, r.out);
});

test('final hold: met passes, unmet fails, fading fails', { skip: !ok }, () => {
  const req = reqFile({ finalHoldSeconds: 5 });
  let r = run(make('tpad=stop_mode=clone:stop_duration=5', { dur: 6, audioDur: 11 }), ['--requirements', req]);
  assert.equal(r.code, 0, r.out);
  assert.ok(r.j.ending.stillSeconds >= 4.5, JSON.stringify(r.j.ending));
  r = run(make('', { dur: 9 }), ['--requirements', req]);
  assert.ok(codes(r.j.errors).includes('final-hold-unmet'), r.out);
  r = run(make('tpad=stop_mode=clone:stop_duration=5,fade=t=out:st=8:d=3', { dur: 6, audioDur: 11 }), ['--requirements', req]);
  assert.ok(codes(r.j.errors).some((c) => c.startsWith('final-hold')), r.out);
});

test('trailing silence beyond the declared hold fails', { skip: !ok }, () => {
  let r = run(make('', { dur: 12, audio: gap(5, 12) }));
  assert.ok(codes(r.j.errors).includes('trailing-silence'), r.out);
  assert.ok(r.j.ending.trailingSilenceSeconds >= 6);
  // 4 s of silence with nothing declared is a wanted held ending: advisory only, on both sides of the 3 s line
  r = run(make('', { dur: 12, audio: gap(8, 12) }));
  assert.ok(!codes(r.j.errors).includes('trailing-silence'), r.out);
  assert.ok(codes(r.j.advisories).includes('trailing-silence-review'), r.out);
  r = run(make('', { dur: 12, audio: gap(10, 12) }));
  assert.ok(!codes(r.j.advisories).includes('trailing-silence-review'), r.out);
  // declared hold 5: 8.5 s of silence is over hold + 3
  r = run(make('tpad=stop_mode=clone:stop_duration=5', { dur: 6, audioDur: 11, audio: gap(2.5, 11) }), ['--requirements', reqFile({ finalHoldSeconds: 5 })]);
  assert.ok(codes(r.j.errors).includes('trailing-silence'), r.out);
  r = run(make('tpad=stop_mode=clone:stop_duration=5', { dur: 6, audioDur: 11, audio: gap(6, 11) }), ['--requirements', reqFile({ finalHoldSeconds: 5 })]);
  assert.ok(!codes(r.j.errors).includes('trailing-silence'), r.out);
  assert.equal(r.code, 0, r.out);
});

test('narrated video without audio fails; silent video without audio passes', { skip: !ok }, () => {
  const f = make('', { audio: null });
  assert.ok(codes(run(f).j.errors).includes('no-audio'));
  const r = run(f, ['--deliverable', 'silent-video']);
  assert.equal(r.code, 0, r.out);
});

test('audio deliverable needs no video; silence still counts', { skip: !ok }, () => {
  const good = join(scratch, 'a-good.m4a');
  ff([...SINE(6), '-c:a', 'aac', good]);
  let r = run(good, ['--deliverable', 'audio']);
  assert.equal(r.code, 0, r.out);
  const bad = join(scratch, 'a-bad.m4a');
  ff([...SINE(14, gap(3, 10)), '-c:a', 'aac', bad]);
  r = run(bad, ['--deliverable', 'audio']);
  assert.ok(codes(r.j.errors).includes('silence'), r.out);
});

test('aspect mismatch against requirements fails', { skip: !ok }, () => {
  const f = make('', {});
  assert.ok(codes(run(f, ['--requirements', reqFile({ aspect: '9:16' })]).j.errors).includes('aspect-mismatch'));
  assert.equal(run(f, ['--requirements', reqFile({ aspect: '16:9' })]).code, 0);
});

test('advisories: static opening, unsettled ending, low-detail page', { skip: !ok }, () => {
  let r = run(make('tpad=start_mode=clone:start_duration=4', { dur: 8 }));
  const op = r.j.advisories.find((a) => a.code === 'opening-static');
  assert.ok(op, r.out);
  assert.equal(r.code, 0, r.out);
  assert.match(op.message, /first 3/);
  r = run(make('', { dur: 8 }));
  assert.ok(codes(r.j.advisories).includes('ending-unsettled'), r.out);
  assert.ok(!codes(r.j.advisories).includes('opening-static'), r.out);
  // a pale, near-empty page with one small mark, sandwiched between busy frames
  const page = "noise=alls=30:allf=t,drawbox=x=0:y=0:w=iw:h=ih:color=0xf4f4f4:t=fill:enable='between(t,3,4)',drawbox=x=300:y=170:w=20:h=20:color=0x303030:t=fill:enable='between(t,3,4)'";
  r = run(make(page, { dur: 8 }));
  const low = r.j.advisories.find((a) => a.code === 'low-detail');
  assert.ok(low, r.out);
  assert.ok(low.at >= 2.8 && low.at <= 3.3, JSON.stringify(low));
  assert.ok(!codes(r.j.errors).includes('blank-span'), r.out);
});

test('blurred-fill vertical cut is an advisory; native vertical is not', { skip: !ok }, () => {
  const fill = join(scratch, 'fill.mp4');
  ff([...SRC(6, '1280x720'), ...SINE(6), '-filter_complex', '[0:v]split[a][b];[a]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,gblur=sigma=40[bg];[b]scale=720:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2[v]', '-map', '[v]', '-map', '1:a', ...enc, '-shortest', fill]);
  let r = run(fill);
  assert.ok(codes(r.j.advisories).includes('blurred-fill'), r.out);
  r = run(make('', { dur: 6, size: '720x1280' }));
  assert.ok(!codes(r.j.advisories).includes('blurred-fill'), r.out);
});

test('an unreadable candidate exits non-zero', { skip: !ok }, () => {
  const bad = join(scratch, 'bad.mp4');
  writeFileSync(bad, 'not a video');
  assert.notEqual(run(bad).code, 0);
});

// ---- review findings
const runRaw = (argv) => { const r = spawnSync(process.execPath, [script, ...argv], { windowsHide: true, encoding: 'utf8', env: { ...process.env, ...(argv.env || {}) } }); return { code: r.status, out: (r.stdout || '') + (r.stderr || '') }; };
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));

test('report carries deliverable and requirementsSha256', { skip: !ok }, () => {
  const f = make('', {});
  let r = run(f);
  assert.equal(r.j.deliverable, 'narrated-video');
  assert.equal(r.j.requirementsSha256, null);
  r = run(f, ['--requirements', reqFile({ aspect: '16x9' })]);
  assert.match(r.j.requirementsSha256, /^[0-9a-f]{64}$/);
  assert.equal(r.code, 0, r.out);
});

test('aspect 16x9 is canonical, 16:9 tolerated, 9x16 mismatches', { skip: !ok }, () => {
  const f = make('', {});
  assert.equal(run(f, ['--requirements', reqFile({ aspect: '16x9' })]).code, 0);
  assert.equal(run(f, ['--requirements', reqFile({ aspect: '16:9' })]).code, 0);
  assert.ok(codes(run(f, ['--requirements', reqFile({ aspect: '9x16' })]).j.errors).includes('aspect-mismatch'));
});

test('width, height and deliverable in requirements are not read', { skip: !ok }, () => {
  const r = run(make('', { audio: null }), ['--requirements', reqFile({ deliverable: 'silent-video', width: 100, height: 100 })]);
  assert.ok(codes(r.j.errors).includes('no-audio'), r.out);
  assert.ok(!codes(r.j.errors).includes('size-mismatch'));
});

test('deliverable comes from job.json; explicit contradiction is an error', { skip: !ok }, () => {
  const root = join(scratch, `job${n++}`);
  mkdirSync(join(root, 'out'), { recursive: true });
  mkdirSync(join(root, 'story'), { recursive: true });
  writeFileSync(join(root, 'job.json'), JSON.stringify({ kind: 'audio-only' }));
  const a = join(root, 'out', 'a.m4a');
  ff([...SINE(6), '-c:a', 'aac', a]);
  let r = run(a);
  assert.equal(r.j.deliverable, 'audio');
  assert.equal(r.code, 0, r.out);
  r = run(a, ['--deliverable', 'silent-video']);
  assert.ok(codes(r.j.errors).includes('deliverable-mismatch'), r.out);
  writeFileSync(join(root, 'job.json'), JSON.stringify({ deliverable: 'silent-video' }));
  const v = join(root, 'out', 'v.mp4');
  ff([...SRC(4), ...enc, '-an', v]);
  r = run(v);
  assert.equal(r.j.deliverable, 'silent-video');
  assert.equal(r.code, 0, r.out);
  // found from the requirements file's job root as well
  writeFileSync(join(root, 'story', 'requirements.json'), JSON.stringify({}));
  r = run(v, ['--requirements', join(root, 'story', 'requirements.json')]);
  assert.equal(r.j.deliverable, 'silent-video');
});

test('stills and storyboard deliverables are not applicable', { skip: !ok }, () => {
  const root = join(scratch, `job${n++}`);
  mkdirSync(root, { recursive: true });
  writeFileSync(join(root, 'job.json'), JSON.stringify({ deliverable: 'stills' }));
  const r = run(join(root, 'nothing.png'));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.j.ok, true);
  assert.equal(r.j.notApplicable, true);
  const r2 = run(make('', {}), ['--deliverable', 'storyboard']);
  assert.equal(r2.code, 0);
  assert.equal(r2.j.notApplicable, true);
});

test('--reviewed-silence takes one range per flag and does not swallow the candidate', { skip: !ok }, () => {
  const f = make('', { dur: 14, audio: gap(4, 10) });
  const out = join(scratch, `r${n++}.json`);
  let r = runRaw(['--reviewed-silence', '3.5-10.5:long music-less read beat', f, '--out', out]);
  assert.equal(r.code, 0, r.out);
  assert.equal(readJson(out).silences.find((s) => s.kind === 'mid').reviewed, true);
  r = runRaw(['--reviewed-silence', '1-2', '--reviewed-silence', '3.5-10.5', f, '--out', out]);
  assert.equal(r.code, 0, r.out);
  r = runRaw(['--reviewed-silence', 'nonsense', f, '--out', out]);
  assert.equal(r.code, 2);
});

test('requirements reviewedSilences need a reason', { skip: !ok }, () => {
  const f = make('', { dur: 14, audio: gap(4, 10) });
  let r = run(f, ['--requirements', reqFile({ reviewedSilences: [{ start: 3.5, end: 10.5, reason: 'reader pauses on the result' }] })]);
  assert.equal(r.code, 0, r.out);
  r = run(f, ['--requirements', reqFile({ reviewedSilences: [{ start: 3.5, end: 10.5 }] })]);
  assert.ok(codes(r.j.errors).includes('reviewed-silence-invalid'), r.out);
  assert.ok(codes(r.j.errors).includes('silence'), r.out);
});

test('declared durationSeconds is the schema {min,max} range', { skip: !ok }, () => {
  const f = make('', { dur: 8 });
  assert.equal(run(f, ['--requirements', reqFile({ durationSeconds: { min: 6, max: 10 } })]).code, 0);
  assert.equal(run(f, ['--requirements', reqFile({ durationSeconds: { min: 8, max: 8 } })]).code, 0);
  assert.ok(codes(run(f, ['--requirements', reqFile({ durationSeconds: { min: 20, max: 30 } })]).j.errors).includes('duration-mismatch'));
  assert.ok(codes(run(f, ['--requirements', reqFile({ durationSeconds: { min: 1, max: 4 } })]).j.errors).includes('duration-mismatch'));
});

test('a malformed durationSeconds is an error, not a skipped check', { skip: !ok }, () => {
  const f = make('', { dur: 8 });
  for (const bad of [8, '8', { min: 'a', max: 9 }, { min: 10, max: 5 }, { min: 6 }, { min: -1, max: 9 }, [6, 10]]) {
    const r = run(f, ['--requirements', reqFile({ durationSeconds: bad })]);
    assert.notEqual(r.code, 0, JSON.stringify(bad));
    assert.ok(codes(r.j.errors).includes('duration-invalid'), JSON.stringify(bad) + ' ' + r.out);
  }
});

test('the requirements file check_requirements.py accepts is accepted here too', { skip: !ok }, () => {
  const shared = join(here, 'fixtures', 'requirements-shared.json');
  const r = run(make('', { dur: 8 }), ['--requirements', shared]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.j.errors, []);
  // and the same range is enforced, not skipped
  assert.ok(codes(run(make('', { dur: 2 }), ['--requirements', shared]).j.errors).includes('duration-mismatch'));
});

test('an ffmpeg call that exceeds its timeout reports a clear error', { skip: !ok }, () => {
  const f = make('', {});
  const out = join(scratch, `r${n++}.json`);
  const r = spawnSync(process.execPath, [script, f, '--out', out], { windowsHide: true, encoding: 'utf8', env: { ...process.env, FINISHED_FILM_TIMEOUT_MS: '1' } });
  assert.notEqual(r.status, 0);
  assert.ok(codes(readJson(out).errors).includes('timeout'));
});

test('a pale empty page with a spinner inside an app header shell is low-detail', { skip: !ok }, () => {
  // header strip with text-like marks (edge energy ~3%), empty cream body, small spinner mark
  const page = "noise=alls=30:allf=t,drawbox=x=0:y=0:w=iw:h=ih:color=0xfaf6e8:t=fill:enable='between(t,3,4)',drawbox=x=0:y=0:w=iw:h=40:color=0x14203a:t=fill:enable='between(t,3,4)',drawbox=x=20:y=15:w=80:h=8:color=white:t=fill:enable='between(t,3,4)',drawbox=x=300:y=170:w=24:h=24:color=0x303030:t=fill:enable='between(t,3,4)'";
  const r = run(make(page, { dur: 8 }));
  assert.ok(codes(r.j.advisories).includes('low-detail'), r.out);
});
