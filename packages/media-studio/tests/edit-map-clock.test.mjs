import test from 'node:test';
import assert from 'node:assert/strict';
import { mapClock, measureMappedClock, comparePcm, compareFrames, filters, readVerifiedMap, sha } from '../scripts/edit-map-clock.mjs';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const digest = 'a'.repeat(64), scriptDigest = 'b'.repeat(64);
const source = () => ({schema:'local-ai/forced-alignment/1',units:'seconds',gridSeconds:.08,durationSeconds:4,
  take:{sha256:digest},script:{sha256:scriptDigest},words:[{text:'Hello',start:.4,end:.8},{text:'world',start:2.4,end:2.8}]});
const graph = () => ({schema:'media-studio/edit-map/1',source:{candidate:{sha256:digest},script:{sha256:scriptDigest}},cuts:[[1,2]],mutes:[]});
test('complete native words map through declared silence cut without inventing a new clock',()=>{
  const mapped=mapClock(source(),'Hello world',graph());
  assert.equal(mapped.durationSeconds,3); assert.equal(mapped.sourceUncertaintyMs,80);
  assert.deepEqual(mapped.words,[{w:'Hello',start:.4,end:.8},{w:'world',start:1.4,end:1.7999999999999998}]);
  const stats=measureMappedClock(mapped,[{w:'Hello',start:.4},{w:'world',start:1.4}]);
  assert.equal(stats.ok,true);assert.equal(stats.gridMs,null);assert.equal(stats.sourceGridMs,80);
});
test('reject changed binding, missing script words, malformed cuts, spoken cuts and removed tail',()=>{
  const cases=[g=>g.source.candidate.sha256='c'.repeat(64),g=>g.cuts=[[2,1]],g=>g.cuts=[[.4,.6]],g=>g.cuts=[[3,4]],g=>delete g.mutes];
  for(const change of cases){const g=graph();change(g);assert.throws(()=>mapClock(source(),'Hello world',g));}
  assert.throws(()=>mapClock(source(),'Hello extra world',graph()),/complete locked script/);
  const s=source();s.gridSeconds=.04;assert.throws(()=>mapClock(s,'Hello world',graph()),/80 ms/);
});
test('mute overlap remains explicit and drift/offset floors stay 40 ms',()=>{
  const g=graph();g.mutes=[[.4,.48]];const m=mapClock(source(),'Hello world',g);
  assert.equal(m.changedWords.length,1);
  assert.equal(measureMappedClock(m,[{w:'Hello',start:.3},{w:'world',start:1.3}]).ok,false);
  assert.throws(()=>measureMappedClock(m,[{w:'Hello',start:.4}]),/complete ordered/);
});
function wave(n=8000){const b=Buffer.alloc(n*4);for(let i=0;i<n;i++)b.writeFloatLE(.2*Math.sin(i*.13),i*4);return b;}
test('PCM checks all samples and rejects missing tail, late corruption, silence corruption and phase inversion',()=>{
  const a=wave();assert.equal(comparePcm(a,Buffer.from(a)).windows.length,2);
  assert.throws(()=>comparePcm(a,a.subarray(0,a.length-4)),/count/);
  for(const mode of ['tail','inverse','nonfinite']){const b=Buffer.from(a);for(let i=4000;i<8000;i++)b.writeFloatLE(mode==='nonfinite'?NaN:mode==='inverse'?-a.readFloatLE(i*4):0,i*4);assert.throws(()=>comparePcm(a,b));}
  const quiet=Buffer.from(a);quiet.fill(0,4000*4);const bad=Buffer.from(quiet);for(let i=4000;i<8000;i++)bad.writeFloatLE(.02,i*4);assert.throws(()=>comparePcm(quiet,bad));
});
test('sampled picture comparison catches count and visible frame damage',()=>{
  const a=Buffer.alloc(200000,100);assert.equal(compareFrames(a,Buffer.from(a)).frames,2);
  assert.throws(()=>compareFrames(a,a.subarray(0,100000)),/count/);
  const b=Buffer.from(a);b.fill(150,100000);assert.throws(()=>compareFrames(a,b),/correspondence/);
});
test('declared graph composes mute before exact trim and concat',()=>{
  const g=graph();g.mutes=[[.2,.3]];const f=filters(g,'a');
  assert.match(f,/volume=0/);assert.match(f,/atrim=start=0:end=1/);assert.match(f,/atrim=start=2/);assert.match(f,/concat=n=2:v=0:a=1/);
});
test('persisted proof revalidates immutable graph, full coverage, thresholds and source uncertainty',()=>{
  const root=mkdtempSync(join(tmpdir(),'edit-map-'));
  try {
    const put=(name,body)=>{const p=join(root,name);writeFileSync(p,typeof body==='string'?body:JSON.stringify(body));return {path:name,sha256:sha(p)};};
    const original=put('original.mp4','original'),candidate=put('final.mp4','final'),script=put('script.txt','Hello world');
    const s=source();s.take.sha256=original.sha256;s.script.sha256=script.sha256;
    const alignment=put('alignment.json',s),g=graph();g.source={candidate:original,alignment,script};g.candidate=candidate;g.verifyPicture=true;
    const editMap=put('edit-map.json',g),mapped=mapClock(s,'Hello world',g),pcm=comparePcm(wave(48000),wave(48000));
    const picture={frames:6,maxFrameMAE:0,maxFrameP99AbsoluteError:0,tail:{frames:1,maxFrameMAE:0,maxFrameP99AbsoluteError:0}};
    const p={schema:'media-studio/verified-edit-map/1',generator:'media-studio/validate-edit-map',ok:true,errors:[],candidate,inputs:{editMap,sourceCandidate:original,sourceAlignment:alignment,script},mapped,pcm,picture,thresholds:{minPcmCorrelation:.98,maxPcmRelativeRmsError:.15,maxQuietRmsError:.001,maxFrameMAE:3,maxFrameP99AbsoluteError:16}};
    const binding={takeSha256:candidate.sha256,scriptSha256:script.sha256,editMapSha256:editMap.sha256};
    assert.deepEqual(readVerifiedMap(root,p,binding),mapped);
    const corruptions=[v=>v.mapped.sourceUncertaintyMs=40,v=>v.thresholds.minPcmCorrelation=.5,v=>v.pcm.windows.pop(),v=>v.picture.tail=null,v=>v.inputs.sourceAlignment.sha256='f'.repeat(64),v=>v.candidate.sha256='f'.repeat(64),v=>v.pcm.finalSamples--];
    for(const change of corruptions){const bad=structuredClone(p);change(bad);assert.throws(()=>readVerifiedMap(root,bad,binding));}
    assert.throws(()=>readVerifiedMap(root,p,{...binding,editMapSha256:'f'.repeat(64)}),/selected edit map/);
    writeFileSync(join(root,'original.mp4'),'altered');assert.throws(()=>readVerifiedMap(root,p,binding),/immutable input changed/);
  } finally {rmSync(root,{recursive:true,force:true});}
});
