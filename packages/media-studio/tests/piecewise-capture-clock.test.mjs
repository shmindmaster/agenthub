import test from 'node:test';
import assert from 'node:assert/strict';
import { piecewiseCaptureClock } from '../scripts/piecewise-capture-clock.mjs';
import { mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,copyFileSync,unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const hash = 'a'.repeat(64);
const group = () => ({clipId:'real-window',startSeconds:10,needSeconds:4,actualCaptureWindow:{clipId:'real-window',source_sha256:hash,source_start_seconds:2,source_end_seconds:6,output_frames:120,output_seconds:4,output_start_frame:300,piecewise_time_map:[{output_frame:80,source_seconds:2},{output_frame:110,source_seconds:3},{output_frame:200,source_seconds:6}]}});
const build = g => piecewiseCaptureClock(g,{sourceSha256:hash,receiptSha256:hash});

test('sync kit gate list installs a loadable cue builder and its piecewise dependency on both surfaces',()=>{
  const root=mkdtempSync(join(tmpdir(),'piecewise-package-'));
  const pkg=fileURLToPath(new URL('..',import.meta.url));
  const sync=readFileSync(join(pkg,'scripts/Sync-MediaStudioKit.ps1'),'utf8');
  const gateBlock=sync.match(/\$gateScripts\s*=\s*@\(([\s\S]*?)\)\s*\$sharedTools/);
  assert.ok(gateBlock,'canonical explicit gate list must remain discoverable');
  const names=[...gateBlock[1].matchAll(/'([^']+\.mjs)'/g)].map(m=>m[1]);
  assert.ok(names.includes('piecewise-capture-clock.mjs'),'kit copy list must carry the static cue-builder import');
  try {
    const marketing=join(root,'marketing/lib');mkdirSync(marketing,{recursive:true});
    for(const name of ['captions.mjs','util.mjs']) copyFileSync(join(pkg,'kit/marketing/lib',name),join(marketing,name));
    for(const surface of ['screencast','_shared/tools']) {
      const target=join(root,surface);mkdirSync(target,{recursive:true});
      for(const name of names) copyFileSync(join(pkg,'scripts',name),join(target,name));
      copyFileSync(join(pkg,'kit/screencast/sync-lib.mjs'),join(target,'sync-lib.mjs'));
      const run=()=>spawnSync(process.execPath,[join(target,'build-cue-sheet.mjs')],{encoding:'utf8',windowsHide:true});
      let r=run();assert.equal(r.status,1,r.stdout+r.stderr);assert.match(r.stderr,/Usage: node build-cue-sheet/);
      unlinkSync(join(target,'piecewise-capture-clock.mjs'));
      r=run();assert.match(r.stderr,/ERR_MODULE_NOT_FOUND/,'negative control must catch the omitted helper');
    }
  } finally {rmSync(root,{recursive:true,force:true});}
});
test('real nonzero shot-frame window maps through every anchor without averaging',()=>{
  const g=group(), m=build(g);
  assert.equal(m.sourceToProgram(2),10);
  assert.equal(m.sourceToProgram(3),11);
  assert.equal(m.sourceToProgram(4),12);
  assert.equal(m.sourceToProgram(6),14);
  assert.equal(m.sourceToProgram(1.99),null);
  assert.equal(m.sourceToProgram(6.01),null);
  assert.equal(m.sourceToProgram(NaN),null);
  assert.strictEqual(m.evidence.actualCaptureWindow,g.actualCaptureWindow);
});
test('unequal slopes interpolate the exact local interval',()=>{
  const g=group();g.actualCaptureWindow.piecewise_time_map[1].source_seconds=2.5;
  const m=build(g);
  assert.equal(m.sourceToProgram(2.25),10.5);
  assert.equal(m.sourceToProgram(2.5),11);
  assert.equal(m.sourceToProgram(4.25),12.5);
});
test('invalid geometry, incomplete coverage and unbound identities fail closed',()=>{
  for(const change of [
    g=>g.startSeconds++,g=>g.needSeconds++,g=>g.actualCaptureWindow.output_frames++,
    g=>g.actualCaptureWindow.output_start_frame=-1,g=>g.actualCaptureWindow.source_start_seconds++,
    g=>g.actualCaptureWindow.source_end_seconds++,g=>g.actualCaptureWindow.clipId='other',
    g=>g.actualCaptureWindow.source_sha256='b'.repeat(64),
    g=>g.actualCaptureWindow.piecewise_time_map[1].source_seconds=2,
    g=>g.actualCaptureWindow.piecewise_time_map[1].output_frame=80,
    g=>g.actualCaptureWindow.piecewise_time_map[1].source_seconds=NaN,
    g=>g.actualCaptureWindow.piecewise_time_map.pop(),
  ]) {const g=group();change(g);assert.throws(()=>build(g));}
  assert.throws(()=>piecewiseCaptureClock(group(),{sourceSha256:hash}));
  assert.throws(()=>piecewiseCaptureClock(group(),{sourceSha256:'b'.repeat(64),receiptSha256:hash}));
});
test('cue builder preserves the real map, binds source bytes and never falls back to linear edit',()=>{
  const root=mkdtempSync(join(tmpdir(),'piecewise-cue-'));
  const put=(path,data)=>{const p=join(root,path);mkdirSync(join(p,'..'),{recursive:true});writeFileSync(p,typeof data==='string'?data:JSON.stringify(data));};
  const run=()=>spawnSync(process.execPath,[fileURLToPath(new URL('../scripts/build-cue-sheet.mjs',import.meta.url)),root,'--compose-map','output/test-compose-map.json'],{encoding:'utf8',windowsHide:true});
  try {
    put('uploads/source.mp4','synthetic source identity fixture, no decoding performed');
    const h=createHash('sha256').update(readFileSync(join(root,'uploads/source.mp4'))).digest('hex');
    put('story/narration-timeline.json',{durationSeconds:14,segments:[{id:'s1',text:'Click approve',startSeconds:10,durationSeconds:4}]});
    put('voice/asr/s1.json',{words:[{word:'Click',start:0,end:.2},{word:'approve',start:1,end:1.3}]});
    put('capture/receipt.json',{clips:{'real-window':{sha256:h,actionClock:'clip',actions:[{type:'click',label:'approve',tStart:2.5,x:12,y:15}],expectations:[{label:'approved',observed:true,observedAt:4.25}]}}});
    const g=group();g.file='uploads/source.mp4';g.segments=['s1'];g.edit={trimStart:0,speed:1,srcSeconds:30};g.actualCaptureWindow.source_sha256=h;g.actualCaptureWindow.piecewise_time_map[1].source_seconds=2.5;
    put('output/test-compose-map.json',{groups:[g]});
    let result=run();assert.equal(result.status,0,result.stdout+result.stderr);
    const sheet=JSON.parse(readFileSync(join(root,'plan/cue-sheet.json'),'utf8'));
    assert.equal(sheet.beats[0].actions[0].action_time,11);
    assert.equal(sheet.beats[0].actions[0].action_time_natural,null);
    assert.equal(sheet.beats[0].result.visible_at,12.5);
    assert.deepEqual(sheet.edl[0].actualCaptureWindow,g.actualCaptureWindow);
    assert.equal(sheet.edl[0].edit,null);
    g.actualCaptureWindow.source_sha256=hash;put('output/test-compose-map.json',{groups:[g]});
    result=run();assert.equal(result.status,1,'a legacy linear edit must not rescue an unbound piecewise clock');
    assert.match(result.stdout,/source\/receipt identity differs/);
    assert.equal(JSON.parse(readFileSync(join(root,'plan/cue-sheet.json'),'utf8')).beats[0].actions[0].action_time,null);
  } finally {rmSync(root,{recursive:true,force:true});}
});
