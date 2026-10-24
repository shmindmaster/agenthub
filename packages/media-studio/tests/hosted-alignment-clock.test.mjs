import test from 'node:test';
import assert from 'node:assert/strict';
import {validateHostedRaw,readHostedClock,measureHostedClock} from '../scripts/hosted-alignment-clock.mjs';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const raw=()=>({loss:.01,characters:[{text:'Hello ',start:.02,end:.08},{text:'world',start:.12,end:.18}],words:[{text:'Hello',start:.02,end:.08,loss:.01},{text:'world',start:.12,end:.18,loss:.02}]});
const cue=()=>[{w:'Hello',start:.02,end:.08},{w:'world',start:.12,end:.18}];
test('hosted clock retains unknown uncertainty, real seconds and losses',()=>{
 const clock=validateHostedRaw(raw(),'Hello world',.25),result=measureHostedClock(clock,cue());
 assert.equal(result.ok,true);assert.equal(result.gridMs,null);assert.equal(result.uncertaintyMs,null);assert.equal(result.providerLoss,.01);assert.equal(result.words[1].loss,.02);
 assert.equal(result.method,'hosted-forced-alignment-on-encoded');
});
test('provider whitespace words are validated without inventing lexical words',()=>{
 const r=raw();r.words.splice(1,0,{text:' ',start:.08,end:.12,loss:.03});
 assert.equal(validateHostedRaw(r,'Hello world',.25).words.length,2);
 r.words.splice(2,0,{text:'\n',start:.08,end:.081,loss:.03});
 assert.equal(validateHostedRaw(r,'Hello world',.25).words.length,2);
 const overlap=raw();overlap.words[1].start=.07;
 assert.throws(()=>validateHostedRaw(overlap,'Hello world',.25),/overlapping/);
 r.words[1].loss=null;assert.throws(()=>validateHostedRaw(r,'Hello world',.25));
});
test('incomplete/reordered text, malformed/raw loss and bounds fail closed',()=>{
 for(const mutate of [r=>r.words.pop(),r=>r.words.reverse(),r=>r.words[0].text='Invented',r=>r.characters.pop(),r=>r.characters.reverse(),r=>r.words[1].start=-1,r=>r.words[1].end=.26,r=>r.words[1].loss=null,r=>r.loss=null,r=>r.characters[0].start=NaN]){
  const r=raw();mutate(r);assert.throws(()=>validateHostedRaw(r,'Hello world',.25));
 }
});
test('40ms offset/drift floors remain unchanged and cue order is complete',()=>{
 const c=validateHostedRaw(raw(),'Hello world',.25);
 assert.equal(measureHostedClock(c,cue().map(w=>({...w,start:w.start+.05,end:w.end+.05}))).ok,false);
 assert.throws(()=>measureHostedClock(c,cue().reverse()));assert.throws(()=>measureHostedClock(c,cue().slice(0,1)));
});
function wav(){const b=Buffer.alloc(44+12000);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(24000,24);b.writeUInt32LE(48000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(12000,40);return b;}
test('immutable bindings and exact decoded PCM reject changed audio/raw/script/candidate',()=>{
 const root=mkdtempSync(join(tmpdir(),'hosted-clock-'));
 try{
 const files={'candidate.wav':wav(),'upload.wav':wav(),'script.txt':'Hello world','raw.json':JSON.stringify(raw())};
 for(const [p,v] of Object.entries(files))writeFileSync(join(root,p),v);
 const ref=p=>({path:p,sha256:createHash('sha256').update(readFileSync(join(root,p))).digest('hex')});
 const manifest={schema:'media-studio/hosted-forced-alignment/1',provider:'elevenlabs',endpoint:'/v1/forced-alignment',units:'seconds',gridSeconds:null,uncertaintySeconds:null,durationSeconds:.25,candidate:{...ref('candidate.wav'),bytes:12044},script:ref('script.txt'),raw:ref('raw.json'),uploadedAudio:{...ref('upload.wav'),format:'pcm_s16le',sampleRate:24000,channels:1},request:{state:'completed',id:'provider-test',requestKey:'immutable-test'}};
 const bindings={takeSha256:manifest.candidate.sha256,scriptSha256:manifest.script.sha256};
 assert.equal(readHostedClock(root,manifest,bindings).pcmSamples,6000);
 // A lossless container is transport only; it cannot change the exact PCM,
 // sample rate, channels, provider clock or quality thresholds.
 const encode=(input,output,args=[])=>{const r=spawnSync('ffmpeg',['-v','error','-nostdin','-threads','1','-filter_threads','1','-i',join(root,input),...args,'-c:a','flac','-y',join(root,output)],{windowsHide:true});assert.equal(r.status,0);};
 encode('upload.wav','upload.flac');
 const flac={...manifest,uploadedAudio:{...ref('upload.flac'),format:'flac',sampleRate:24000,channels:1}};
 assert.equal(readHostedClock(root,flac,bindings).pcmSamples,6000);
 assert.throws(()=>readHostedClock(root,{...flac,uploadedAudio:{...flac.uploadedAudio,format:'pcm_s16le'}},bindings),/codec/);
 encode('upload.wav','wrong-rate.flac',['-ar','16000']);
 assert.throws(()=>readHostedClock(root,{...flac,uploadedAudio:{...flac.uploadedAudio,...ref('wrong-rate.flac')}},bindings),/rate/);
 const altered=wav();altered.writeInt16LE(100,100);writeFileSync(join(root,'changed.wav'),altered);encode('changed.wav','changed.flac');
 assert.throws(()=>readHostedClock(root,{...flac,uploadedAudio:{...flac.uploadedAudio,...ref('changed.flac')}},bindings),/exact decoded/);
 for(const durationSeconds of [undefined,null,NaN,0,.3])assert.throws(()=>readHostedClock(root,{...manifest,durationSeconds},bindings),/duration/);
 for(const name of ['raw.json','script.txt','candidate.wav','upload.wav']){
  const before=readFileSync(join(root,name));writeFileSync(join(root,name),Buffer.concat([before,Buffer.from('changed')]));assert.throws(()=>readHostedClock(root,manifest,bindings));writeFileSync(join(root,name),before);
 }
 const changed=wav();changed.writeInt16LE(100,100);writeFileSync(join(root,'upload.wav'),changed);manifest.uploadedAudio= {...manifest.uploadedAudio,...ref('upload.wav')};
 assert.throws(()=>readHostedClock(root,manifest,bindings),/exact decoded/);
 }finally{rmSync(root,{recursive:true,force:true});}
});
