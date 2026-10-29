import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,mkdirSync,copyFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {alignScript,scriptTokens,heardKeys} from '../kit/cloud/cloud-ai.mjs';
import {readDerivedAudioClock,measureDerivedAudioClock} from '../scripts/derived-audio-clock.mjs';
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
function command(args){const r=spawnSync('ffmpeg',['-v','error','-nostdin','-threads','1','-filter_threads','1',...args],{windowsHide:true});assert.equal(r.status,0,r.stderr?.toString());}
function fixture(rate=24000){
 const root=mkdtempSync(join(tmpdir(),'derived-clock-'));
 command(['-f','lavfi','-i','sine=frequency=431:duration=2.4','-c:a','aac','-y',join(root,'candidate.m4a')]);
 command(['-i',join(root,'candidate.m4a'),'-ac','1','-ar',String(rate),'-c:a','pcm_s16le','-y',join(root,'audio.wav')]);
 writeFileSync(join(root,'script.txt'),'Hello world again');
 const words=[{word:'hello',start:.16,end:.48},{word:'world',start:.64,end:.96},{word:'again',start:1.2,end:1.6}];
 // The WAV duration is read from its data chunk, independent of AAC duration.
 const b=readFileSync(join(root,'audio.wav'));let at=12,n;
 while(at+8<=b.length){const size=b.readUInt32LE(at+4);if(b.toString('ascii',at,at+4)==='data'){n=size;break;}at+=8+size+(size%2);}
 const duration=n/(rate*2);
 const raw={metadata:{request_id:'synthetic-retained-request',sha256:hash(join(root,'audio.wav')),duration,model_info:{synthetic:{arch:'nova-3'}}},results:{channels:[{alternatives:[{words}]}]}};
 const regenerated=alignScript(scriptTokens('Hello world again'),heardKeys(words.map(w=>({text:w.word,start:w.start,end:w.end}))),duration);
 const ref=p=>({path:p,sha256:hash(join(root,p))});
 const report={schema:'cloud-speech/script-alignment/1',method:'asr-anchored-alignment',ok:true,errors:[],units:'seconds',gridSeconds:.08,durationSeconds:+duration.toFixed(3),take:ref('audio.wav'),script:ref('script.txt'),provider:{name:'deepgram',model:'nova-3'},...regenerated};
 writeFileSync(join(root,'raw.json'),JSON.stringify(raw));writeFileSync(join(root,'alignment.json'),JSON.stringify(report));
 const manifest={schema:'media-studio/derived-audio-clock/1',transform:'identity-decoded-pcm',pcm:{sampleRate:rate,channels:1,sampleFormat:'s16le'},candidate:ref('candidate.m4a'),sourceAudio:ref('audio.wav'),sourceAlignment:ref('alignment.json'),script:ref('script.txt'),raw:ref('raw.json')};
 const bindings={takeSha256:manifest.candidate.sha256,scriptSha256:manifest.script.sha256,allowAsrAnchored:true};
 return {root,manifest,bindings,report,raw,ref,put:(p,v)=>writeFileSync(join(root,p),JSON.stringify(v)),cue:regenerated.words.map(w=>({w:w.text,start:w.start,end:w.end}))};
}
test('exact complete PCM preserves ASR identity, uncertainty and 40ms drift gate',()=>{
 const f=fixture();try{
 const clock=readDerivedAudioClock(f.root,f.manifest,f.bindings),r=measureDerivedAudioClock(clock,f.cue);
 assert.equal(r.ok,true);assert.equal(r.gridMs,80);assert.match(r.method,/asr-anchored/);assert.equal(r.sourceAudioSha256,f.manifest.sourceAudio.sha256);assert.ok(r.pcmSamples>0);
 assert.equal(measureDerivedAudioClock(clock,f.cue.map(w=>({...w,start:w.start+.05,end:w.end+.05}))).ok,false);
 assert.equal(measureDerivedAudioClock(clock,f.cue.map((w,i)=>({...w,start:w.start+i*.05,end:w.end+i*.05}))).ok,false);
 assert.throws(()=>readDerivedAudioClock(f.root,f.manifest,{...f.bindings,allowAsrAnchored:false}),/opt-in/);
 }finally{rmSync(f.root,{recursive:true,force:true});}
});
test('all immutable inputs and provider upload binding fail closed',()=>{
 for(const key of ['candidate','sourceAudio','sourceAlignment','script','raw']){const f=fixture();try{writeFileSync(join(f.root,f.manifest[key].path),'tampered');assert.throws(()=>readDerivedAudioClock(f.root,f.manifest,f.bindings));}finally{rmSync(f.root,{recursive:true,force:true});}}
 const f=fixture();try{f.raw.metadata.sha256='0'.repeat(64);f.put('raw.json',f.raw);f.manifest.raw=f.ref('raw.json');assert.throws(()=>readDerivedAudioClock(f.root,f.manifest,f.bindings),/bind source/);}finally{rmSync(f.root,{recursive:true,force:true});}
});

test('16k retained ASR representation is exact and format mismatches fail closed',()=>{
 const f=fixture(16000);try{
 assert.equal(readDerivedAudioClock(f.root,f.manifest,f.bindings).pcmSampleRate,16000);
 for(const pcm of [undefined,{sampleRate:8000,channels:1,sampleFormat:'s16le'},{sampleRate:16000,channels:2,sampleFormat:'s16le'},{sampleRate:24000,channels:1,sampleFormat:'s16le'}])assert.throws(()=>readDerivedAudioClock(f.root,{...f.manifest,pcm},f.bindings),/format|sample rate/);
 }finally{rmSync(f.root,{recursive:true,force:true});}
});
test('freshly rebound replacement, offset, padding, truncation and rate drift cannot inherit the clock',()=>{
 for(const filter of ['volume=0','adelay=80:all=1','apad=pad_dur=0.1','atrim=end=2','asetrate=22000']){
 const f=fixture();try{command(['-i',join(f.root,'audio.wav'),'-af',filter,'-ar','24000','-c:a','pcm_s16le','-y',join(f.root,'different.wav')]);f.manifest.sourceAudio=f.ref('different.wav');f.raw.metadata.sha256=f.manifest.sourceAudio.sha256;f.report.take=f.manifest.sourceAudio;f.put('raw.json',f.raw);f.put('alignment.json',f.report);f.manifest.raw=f.ref('raw.json');f.manifest.sourceAlignment=f.ref('alignment.json');assert.throws(()=>readDerivedAudioClock(f.root,f.manifest,f.bindings),/complete decoded/);}finally{rmSync(f.root,{recursive:true,force:true});}}
});
test('rebound fabricated source clock, malformed raw intervals and coverage changes fail closed',()=>{
 for(const change of [f=>f.report.words[0].start+=.08,f=>f.report.coverage.exact=0,f=>f.report.durationSeconds+=.08,f=>f.raw.results.channels[0].alternatives[0].words[0].start=null,f=>f.raw.results.channels[0].alternatives[0].words.reverse()]){
 const f=fixture();try{change(f);f.put('raw.json',f.raw);f.put('alignment.json',f.report);f.manifest.raw=f.ref('raw.json');f.manifest.sourceAlignment=f.ref('alignment.json');assert.throws(()=>readDerivedAudioClock(f.root,f.manifest,f.bindings));}finally{rmSync(f.root,{recursive:true,force:true});}}
});

test('canonical word-sync CLI selects derived clock and rejects changed actual cue timing',()=>{
 const f=fixture(16000);try{
 for(const folder of ['story','plan','qa'])mkdirSync(join(f.root,folder));
 writeFileSync(join(f.root,'story/locked-script.txt'),readFileSync(join(f.root,'script.txt')));
 f.manifest.script=f.ref('story/locked-script.txt');f.report.script=f.manifest.script;f.put('alignment.json',f.report);f.manifest.sourceAlignment=f.ref('alignment.json');
 f.put('job.json',{clockPolicy:{allowAsrAnchored:true}});f.put('qa/derived-audio-clock.json',f.manifest);
 const run=()=>spawnSync(process.execPath,[fileURLToPath(new URL('../scripts/validate-word-sync.mjs',import.meta.url)),f.root,join(f.root,'candidate.m4a')],{windowsHide:true});
 f.put('plan/cue-sheet.json',{beats:[{narration:{words:f.cue}}]});
 let r=run();assert.equal(r.status,0,r.stdout?.toString()+r.stderr?.toString());
 let report=JSON.parse(readFileSync(join(f.root,'qa/word-sync.json')));assert.equal(report.method,'asr-anchored-identity-pcm-on-encoded');assert.equal(report.pcmSampleRate,16000);assert.equal(report.candidate.sha256,f.manifest.candidate.sha256);assert.equal(report.inputs.alignment.path,'qa/derived-audio-clock.json');
 f.put('plan/cue-sheet.json',{beats:[{narration:{words:f.cue.map(w=>({...w,start:w.start+.05,end:w.end+.05}))}}]});
 r=run();assert.equal(r.status,1);report=JSON.parse(readFileSync(join(f.root,'qa/word-sync.json')));assert.equal(report.ok,false);
 }finally{rmSync(f.root,{recursive:true,force:true});}
});

test('declared deployment ships helper and executes exact PCM clock from both runtime layouts',()=>{
 const f=fixture(16000);try{
 const sync=readFileSync(new URL('../scripts/Sync-MediaStudioKit.ps1',import.meta.url),'utf8');
 assert.match(sync,/\$gateScripts\s*=\s*@\([^)]*'derived-audio-clock\.mjs'/s);
 const deploy=join(f.root,'deployment'),kit=join(deploy,'briefing-kit'),shared=join(deploy,'_shared/tools');
 for(const folder of [join(kit,'screencast'),join(kit,'cloud'),shared,join(f.root,'story'),join(f.root,'plan'),join(f.root,'qa')])mkdirSync(folder,{recursive:true});
 copyFileSync(new URL('../kit/cloud/cloud-ai.mjs',import.meta.url),join(kit,'cloud/cloud-ai.mjs'));
 copyFileSync(new URL('../kit/screencast/sync-lib.mjs',import.meta.url),join(kit,'screencast/sync-lib.mjs'));
 copyFileSync(new URL('../kit/screencast/sync-lib.mjs',import.meta.url),join(shared,'sync-lib.mjs'));
 const gates=['derived-audio-clock.mjs','edit-map-clock.mjs','hosted-alignment-clock.mjs','queue-qwen-alignment-clock.mjs','validate-word-sync.mjs'];
 for(const target of [join(kit,'screencast'),shared])for(const name of gates)copyFileSync(new URL('../scripts/'+name,import.meta.url),join(target,name));
 writeFileSync(join(f.root,'story/locked-script.txt'),readFileSync(join(f.root,'script.txt')));f.manifest.script=f.ref('story/locked-script.txt');f.report.script=f.manifest.script;f.put('alignment.json',f.report);f.manifest.sourceAlignment=f.ref('alignment.json');
 f.put('job.json',{clockPolicy:{allowAsrAnchored:true}});f.put('qa/derived-audio-clock.json',f.manifest);f.put('plan/cue-sheet.json',{beats:[{narration:{words:f.cue}}]});
 for(const target of [join(kit,'screencast'),shared]){
  const cli=join(target,'validate-word-sync.mjs');
  let r=spawnSync(process.execPath,[cli,f.root,join(f.root,'candidate.m4a')],{windowsHide:true});assert.equal(r.status,0,r.stdout?.toString()+r.stderr?.toString());
  const report=JSON.parse(readFileSync(join(f.root,'qa/word-sync.json')));assert.equal(report.method,'asr-anchored-identity-pcm-on-encoded');assert.equal(report.pcmSamples>0,true);
 }
 // Missing a deployed dependency must stop import, never select a silent fallback.
 rmSync(join(kit,'cloud/cloud-ai.mjs'));
 const r=spawnSync(process.execPath,[join(shared,'validate-word-sync.mjs'),f.root,join(f.root,'candidate.m4a')],{windowsHide:true});assert.notEqual(r.status,0);assert.match(r.stderr.toString(),/missing canonical cloud alignment library/);
 }finally{rmSync(f.root,{recursive:true,force:true});}
});
