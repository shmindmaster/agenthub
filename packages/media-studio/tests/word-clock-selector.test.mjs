import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { alignScript, scriptTokens, heardKeys } from '../kit/cloud/cloud-ai.mjs';

const release = fileURLToPath(new URL('../scripts/validate-viewer-release.mjs', import.meta.url));
const wordGate = fileURLToPath(new URL('../scripts/validate-word-sync.mjs', import.meta.url));
const sha = p => createHash('sha256').update(readFileSync(p)).digest('hex');
function fixture(job) {
  const root = mkdtempSync(join(tmpdir(), 'word-selector-'));
  for (const dir of ['qa', 'plan', 'story']) mkdirSync(join(root, dir));
  const put = (p, v) => writeFileSync(join(root, p), JSON.stringify(v));
  put('job.json', job);
  writeFileSync(join(root, 'candidate.wav'), 'synthetic candidate');
  return { root, put, candidate: join(root, 'candidate.wav'), ref: p => ({ path: p, sha256: sha(join(root, p)) }) };
}
function aggregate(f) {
  const r = spawnSync(process.execPath, [release, f.root, f.candidate], { windowsHide: true });
  assert.equal(r.signal, null); assert.ok(r.stdout?.length, r.stderr?.toString());
  const report = JSON.parse(r.stdout.toString());
  // These fixtures intentionally omit independent release evidence. Clock success
  // must never turn that unrelated missing review into a blanket release PASS.
  assert.equal(report.ok, false); assert.notEqual(r.status, 0);
  return report.errors;
}
function using(job, fn) { const f = fixture(job); try { fn(f); } finally { rmSync(f.root, { recursive: true, force: true }); } }

test('both selectors and explicit ASR opt-in require word evidence', () => {
  for (const job of [{syncClock:'forced-aligner'}, {syncClock:'asr-anchored',clockPolicy:{allowAsrAnchored:true}}, {clockPolicy:{allowAsrAnchored:true}}]) {
    using(job, f => assert.ok(aggregate(f).some(e => e.includes('missing qa/word-sync.json'))));
  }
});
test('ASR selector requires explicit true opt-in, and unknown selectors fail closed', () => {
  for (const policy of [undefined, {}, {allowAsrAnchored:false}, {allowAsrAnchored:'true'}]) using({syncClock:'asr-anchored',clockPolicy:policy}, f => {
    const errors = aggregate(f); assert.ok(errors.some(e => e.includes('requires clockPolicy.allowAsrAnchored'))); assert.ok(errors.some(e => e.includes('missing qa/word-sync.json')));
  });
  for (const syncClock of ['whisper', 'asr-anchorred', '', 3]) using({syncClock}, f => assert.ok(aggregate(f).some(e => e.includes('unsupported syncClock'))));
});
test('legacy jobs without a selected word clock preserve existing behavior', () => {
  using({}, f => assert.equal(aggregate(f).some(e => /word-sync|syncClock/.test(e)), false));
});

function derived(f) {
  // Create a tiny synthetic PCM fixture without a renderer or external service.
  const rate = 16000, samples = rate * 2.4, wav = Buffer.alloc(44 + samples * 2);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8); wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22); wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * 2, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(samples * 2, 40);
  writeFileSync(f.candidate, wav); writeFileSync(join(f.root, 'source.wav'), wav);
  const text = 'Hello world again'; writeFileSync(join(f.root, 'story/locked-script.txt'), text);
  const words = [{word:'hello',start:.16,end:.48},{word:'world',start:.64,end:.96},{word:'again',start:1.2,end:1.6}];
  const aligned = alignScript(scriptTokens(text), heardKeys(words.map(w => ({text:w.word,start:w.start,end:w.end}))), 2.4);
  f.put('raw.json', {metadata:{request_id:'synthetic-selector-test',sha256:f.ref('source.wav').sha256,duration:2.4,model_info:{synthetic:{arch:'nova-3'}}},results:{channels:[{alternatives:[{words}]}]}});
  f.put('alignment.json', {schema:'cloud-speech/script-alignment/1',method:'asr-anchored-alignment',ok:true,errors:[],units:'seconds',gridSeconds:.08,durationSeconds:2.4,take:f.ref('source.wav'),script:f.ref('story/locked-script.txt'),provider:{name:'deepgram',model:'nova-3'},...aligned});
  f.put('qa/derived-audio-clock.json', {schema:'media-studio/derived-audio-clock/1',transform:'identity-decoded-pcm',pcm:{sampleRate:rate,channels:1,sampleFormat:'s16le'},candidate:f.ref('candidate.wav'),sourceAudio:f.ref('source.wav'),script:f.ref('story/locked-script.txt'),sourceAlignment:f.ref('alignment.json'),raw:f.ref('raw.json')});
  f.put('plan/cue-sheet.json', {beats:[{narration:{words:aligned.words.map(w => ({w:w.text,start:w.start,end:w.end}))}}]});
  const r = spawnSync(process.execPath, [wordGate, f.root, f.candidate], {windowsHide:true});
  assert.equal(r.status, 0, r.stdout?.toString() + r.stderr?.toString());
}
test('truthful ASR selector verifies derived PCM without claiming forced alignment or complete release', () => {
  using({syncClock:'asr-anchored',clockPolicy:{allowAsrAnchored:true,providerAccuracyBound:null}}, f => {
    derived(f);
    assert.equal(aggregate(f).some(e => /word-sync|derived ASR/.test(e)), false);
    const word = JSON.parse(readFileSync(join(f.root,'qa/word-sync.json')));
    assert.equal(word.method,'asr-anchored-identity-pcm-on-encoded'); assert.equal(word.gridMs,80);
    assert.equal(JSON.parse(readFileSync(join(f.root,'job.json'))).clockPolicy.providerAccuracyBound,null);
    for (const path of ['candidate.wav','story/locked-script.txt','plan/cue-sheet.json','qa/derived-audio-clock.json']) {
      const original = readFileSync(join(f.root,path)); writeFileSync(join(f.root,path), 'changed');
      assert.ok(aggregate(f).some(e => /word-sync|derived ASR/.test(e)), path);
      writeFileSync(join(f.root,path), original);
    }
    f.put('job.json',{syncClock:'asr-anchored',clockPolicy:{allowAsrAnchored:false}});
    assert.ok(aggregate(f).some(e => e.includes('invalid derived ASR provenance')));
  });
});
